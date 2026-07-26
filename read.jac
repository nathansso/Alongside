# read.jac — the read path. Owner: T2 Nathan.
#
# Imports only from `graph.jac` (CONTRACTS §1a discipline 4). It does not know `write.jac` or
# `main.jac` exist. Every private helper is prefixed `rd_` (discipline 1) so the collapse into
# `main.jac` at submission is a concatenation with no rename.
#
# Contents today: `Recall` channel B (#8). Channel A (#15), the four detection mechanisms
# (#10–#12), corroboration (#13), `Vigil` (#21), and `Investigate` (#14) land in later issues.
#
# INVARIANTS THIS FILE IS ACCOUNTABLE FOR
#   A2  channel B is unscored, unpruned, and exempt from beam, budget, decay, and waterline.
#       The ONLY thing that kills a channel B constraint is `Supersedes`.
#   A3  the model never selects a traversal path. There is no `by llm()` in this file and no
#       `visit ... by llm()`. Anchor resolution at `Root` is a deterministic key match.
#   A9  only `Recall` reinforces — and not yet. Reinforcement arrives with channel A in #15.
#       Nothing below writes to the graph.
#   S2  every `Violation` carries a non-empty `source` and `at` read off `DerivedFrom`.
#       `obj Violation` has no defaults, so this is structural, not a runtime check.
#
# `Recall` contains no `while` loop. Policy lives on node-type abilities and the visit queue.

# The EDGE archetypes have to be imported alongside the nodes. Without them every typed traversal
# below infers `any` — and because the locals here are annotated, that surfaces as five E1001s
# instead of passing `jac check` and dying at the first field read. Import the edges you traverse.
import from graph {
    Anchor, Belief, Constraint, Utterance, Verdict, Violation,
    DerivedFrom, Governs, Excludes, Member, Supersedes
}


# ==========================================================================================
# Helpers
# ==========================================================================================

# The `Utterance` a belief is cited to, as a 0-or-1 list. Returns the MOST RECENT source when a
# belief carries several `DerivedFrom` edges: a constraint restated by a clinician is best cited
# to the restatement, and the patient reading the row wants the date they were last told.
#
# 0-or-1 list rather than `Utterance | None` on purpose — an optional here forces every caller
# through a narrowing dance to touch `.at`, and an empty list is the same "no citation" signal
# with none of the friction. An empty return is S2's trigger, handled by the caller.
def rd_latest_source(b: Belief) -> list[Utterance] {
    srcs: list[Utterance] = [b ->:DerivedFrom:->];
    if len(srcs) == 0 {
        return [];
    }
    best: Utterance = srcs[0];
    for u in srcs {
        if u.at >= best.at {
            best = u;
        }
    }
    return [best];
}


# `Excludes.because` for one specific (constraint, anchor) pair. Both endpoints are pinned in the
# edge query — reading `[edge here <-:Excludes:<-]` and zipping against the node list by position
# would silently mispair a constraint that excludes several anchors.
# `Governs` carries no `because` by schema, so a Governs-only hit yields "". S2 pins `source` and
# `at`, not `because`; for a Governs hit the claim is its own reason.
def rd_exclusion_reason(c: Constraint, a: Anchor) -> str {
    for e in [edge c ->:Excludes:-> a] {
        if e.because != "" {
            return e.because;
        }
    }
    return "";
}


# ==========================================================================================
# `Recall` — channel B, the exhaustive constraint traversal (#8)
# ==========================================================================================
#
# Signature is pinned by CONTRACTS §4. `:pub` because the client spawns it (#34) — a plain
# `walker` answers `{"error": "Unauthorized"}` and the browser reports an empty failure reason.
#
# Channel B collects EVERY un-superseded `Constraint` reachable from the requested anchors over
# `Governs`, `Excludes`, and outgoing `Member` expansion. Nothing is scored, ranked, budgeted, or
# dropped for being cold — that is A2, and it is the whole point of the two-channel split.
walker:pub Recall {
    has anchors: list[str];
    has out: Verdict = Verdict();

    # --- internal state; never part of the wire shape ------------------------------------
    # Both `rd_seen_*` lists are CYCLE SAFETY, not pruning. `Member` is not guaranteed acyclic by
    # the schema, and the visit queue does not dedupe — verified: two `visit c` on one node fire
    # its ability twice. Without these a `Member` cycle never terminates and a constraint
    # reachable from two anchors emits two identical `Violation`s. Neither guard can change WHICH
    # constraints are found, only how many times each is processed, so A2 holds.
    has rd_seen_anchors: list[str] = [];
    has rd_seen_constraints: list[str] = [];

    # `because` memoized by constraint jid, written at `Anchor` and read at `Constraint`. Walker
    # `has` state is global to the walker, not per-branch, so a `self.current_anchor` field would
    # be wrong — the queue moves on before the constraint is dequeued.
    has rd_because: dict[str, str] = {};

    # Things that cannot become a `Violation` or a citable `Concern`. Feeds the activity panel
    # (CONTRACTS §4: read from walker internal state) and the #16 eval. Not a wire field.
    has rd_notes: list[str] = [];

    # `allowed` is false iff channel B hit a `Constraint` with `hard == True` (CONTRACTS §3).
    has rd_hard_hit: bool = False;

    # --- Root entry: deterministic anchor resolution, no model (A3) ----------------------
    can rd_start with Root entry {
        # Bound to a typed local before any `len()`: an inline `len([root -->][?:Anchor])` fails
        # JS codegen with E5016 when the walker is reachable from a `cl { }` block (#30).
        # Depth 1 from root, matching how `main.jac` reads `Raised`. If #2 attaches the
        # vocabulary deeper this resolves nothing and returns an empty Verdict with no error —
        # flagged on #2, and the `rd_notes` line below is what makes it visible.
        known: list[Anchor] = [here -->[?:Anchor]];

        for want in self.anchors {
            found: list[Anchor] = [];
            for a in known {
                if a.key == want {
                    found.append(a);
                }
            }
            if len(found) == 0 {
                # S3: absence is "not in your record", never "safe". A1 puts the renderable half
                # of this on the write path (`Remember` writes `needs_review` and cites the
                # `Utterance` it saw). The read path has no `Utterance` to cite, and a `Concern`
                # with no citation is dropped by `pg_row` — so recording it here beats
                # fabricating a row that would silently never render.
                self.rd_notes.append("not in your record: " + want);
            } else {
                visit found;
            }
        }
    }

    # --- Anchor entry: collect ALL constraints, then expand `Member` ---------------------
    can rd_anchor with Anchor entry {
        aid: str = jid(here);
        if aid in self.rd_seen_anchors {
            skip;
        }
        self.rd_seen_anchors.append(aid);

        governed: list[Constraint] = [here <-:Governs:<-];
        excluded: list[Constraint] = [here <-:Excludes:<-];

        for c in governed {
            cid: str = jid(c);
            if cid not in self.rd_because {
                self.rd_because[cid] = "";
            }
        }
        for c in excluded {
            cid: str = jid(c);
            why: str = rd_exclusion_reason(c, here);
            # First non-empty reason wins. A constraint reached from two anchors keeps the one
            # that actually explains something rather than whichever arrived last.
            if (cid not in self.rd_because) or (self.rd_because[cid] == "") {
                self.rd_because[cid] = why;
            }
        }

        visit governed;
        visit excluded;

        # OUTGOING ONLY. The vocabulary points outward and upward —
        # `grapefruit --class_member--> CYP3A4-inhibitor --toxicity_of--> CYP3A4-substrate` — so
        # walking it forward generalizes an ingredient to the classes that constrain it. Walking
        # it in REVERSE would make a constraint on one class bind every sibling ingredient in it,
        # turning "no grapefruit" into "no CYP3A4 inhibitors". That is over-blocking on a safety
        # walker, and it is not what reaches the seeded constraint two hops out.
        visit [here ->:Member:->];
    }

    # --- Constraint entry: Supersedes is the only killer (A2) ----------------------------
    can rd_constraint with Constraint entry {
        cid: str = jid(here);
        if cid in self.rd_seen_constraints {
            skip;
        }
        self.rd_seen_constraints.append(cid);

        # Incoming `Supersedes` means this belief was replaced. Not decay, not the waterline —
        # the one carve-out A2 does NOT grant channel B, because a retracted constraint must die
        # or the graph cannot be corrected.
        superseders: list[Belief] = [here <-:Supersedes:<-];
        if len(superseders) > 0 {
            skip;
        }

        # Set BEFORE the citation check, deliberately. CONTRACTS §3 defines `allowed` on the hard
        # constraint hit, not on whether the hit can be rendered — so a hard constraint we cannot
        # cite still blocks. The blocking answer survives even when no row can be built for it.
        if here.hard {
            self.rd_hard_hit = True;
        }

        cite: list[Utterance] = rd_latest_source(here);
        if len(cite) == 0 {
            # S2: `Violation` has no defaults, so this one is structurally unconstructable — and
            # it cannot reach the page as a `Concern` either, because `pg_row` drops a concern
            # with no `Utterance` citation. There is no read-path recovery. The write path owes
            # a `DerivedFrom` on every `Constraint` it writes; raised on #5.
            self.rd_notes.append("uncitable constraint (no DerivedFrom): " + here.claim);
            skip;
        }

        u: Utterance = cite[0];
        self.out.violations.append(
            Violation(
                claim=here.claim,
                because=self.rd_because.get(cid, ""),
                source=u.role,
                at=u.at
            )
        );
    }

    # --- Root exit: assemble and report exactly once -------------------------------------
    can rd_finish with Root exit {
        self.out.allowed = not self.rd_hard_hit;
        report self.out;
    }
}
