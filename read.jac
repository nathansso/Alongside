# read.jac — the read path. Owner: T2 Nathan.
#
# Imports only from `graph.jac` (CONTRACTS §1a discipline 4). It does not know `write.jac` or
# `main.jac` exist. Every private helper is prefixed `rd_` (discipline 1) so the collapse into
# `main.jac` at submission is a concatenation with no rename.
#
# Contents today: `Recall` channel B (#8), the emergency bypass (#9), and detection mechanism 1
# (#10). Channel A (#15), mechanisms 2–4 (#11, #12), corroboration (#13), `Vigil` (#21), and
# `Investigate` (#14) land in later issues.
#
# INVARIANTS THIS FILE IS ACCOUNTABLE FOR
#   A2  channel B is unscored, unpruned, and exempt from beam, budget, decay, and waterline.
#       The ONLY thing that kills a channel B constraint is `Supersedes`.
#   A3  the model never selects a traversal path. There is no `by llm()` in this file and no
#       `visit ... by llm()`. Anchor resolution at `Root` is a deterministic key match, and the
#       emergency criterion is arithmetic over parsed values (ARCHITECTURE §8, "seven places").
#   A9  only `Recall` reinforces — and not yet. Reinforcement arrives with channel A in #15.
#       Nothing below writes to the graph.
#   S2  every `Violation` carries a non-empty `source` and `at` read off `DerivedFrom`.
#       `obj Violation` has no defaults, so this is structural, not a runtime check.
#   S5  emergency criteria are evaluated BEFORE scoring, drafting, or beam. Implemented as
#       ability declaration order — see the warning on `rd_emergency`.
#   S6  mechanism 1 emits at `ask` and never above. `escalate` is reachable from exactly one
#       place in this file, `rd_emergency`.
#
# `Recall` contains no `while` loop. Policy lives on node-type abilities and the visit queue.

# The EDGE archetypes have to be imported alongside the nodes. Without them every typed traversal
# below infers `any` — and because the locals here are annotated, that surfaces as five E1001s
# instead of passing `jac check` and dying at the first field read. Import the edges you traverse.
import from graph {
    Anchor, Belief, Concern, Constraint, Observation, Preference, Utterance, Verdict, Violation,
    About, DerivedFrom, Governs, Excludes, Member, Reports, Supersedes, Relates, Shortcut
}
import from datetime { date }


# Vigil (#21) thresholds. Kept as globs so they read as policy, not magic numbers buried in a walker.
glob VIGIL_SILENCE_DAYS: int = 3;    # a 4-day gap (the acceptance) is well past this
glob VIGIL_RECUR_DAYS: int = 2;      # a symptom on >= 2 distinct days is "recurring"


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


# Every `Observation` on `a` that satisfies `c`'s PARSED threshold (#9). Pure arithmetic over
# fields #4 wrote — ARCHITECTURE §8 lists threshold evaluation among the seven places that must
# never hold a `by llm()`, and this is that place.
#
# `threshold_metric == ""` means the criterion carries no numeric metric ("call if you get a
# rash"); the qualifying condition is then simply that the symptom was reported at all.
def rd_crossings(c: Constraint, a: Anchor) -> list[Observation] {
    hits: list[Observation] = [];
    for o in [a <-:Reports:<-] {
        if (c.threshold_metric != "") and (o.metric != c.threshold_metric) {
            continue;
        }
        if o.value < c.threshold_level {
            continue;
        }
        # NOT REDUNDANT, and dropping it is a real defect. An emergency constraint whose
        # `threshold_level` is 0.0 — unparsed, or a criterion with no numeric threshold — makes the
        # comparison above true for EVERY observation on the anchor, `value == 0.0` included. On
        # both pinned scales (`patient_selfreport` 0–10, `ctcae_grade` 0–4) zero means the symptom
        # is ABSENT. Without this line, logging "no fever today" raises a full-screen
        # "contact your care team now" — the check-in reporting good news fires the alarm.
        if o.value <= 0.0 {
            continue;
        }
        hits.append(o);
    }
    return hits;
}


# Distinct observation dates, ascending. `threshold_days` is D days at/above L, so the crossing
# test counts DAYS, not observations — three readings on one afternoon are one day.
def rd_distinct_dates(obs: list[Observation]) -> list[str] {
    dates: list[str] = [];
    for o in obs {
        if o.at not in dates {
            dates.append(o.at);
        }
    }
    return sorted(dates);
}


# ==========================================================================================
# Mechanism 1 helpers (#10) — active regimen, `Member` reads, the triangle
# ==========================================================================================

# The un-superseded REGIMEN beliefs about an anchor. `graph.jac` defines "active regimen" by
# traversal and by no field: an anchor is active regimen iff an un-superseded regimen `Belief`
# points at it over `About`. Discontinuation is `Supersedes` — the same carve-out A2 grants
# channel B, and for the same reason.
#
# NOTHING MARKS A BELIEF AS A REGIMEN BELIEF, so the discriminator is EXACT TYPE: a plain
# `Belief`, with the `Preference` and `Constraint` subclasses excluded. Verified on a spike —
# `[a <-:About:<-]` returns subclass instances too, all three of three. Without the `isinstance`
# filter, "grapefruit made me nauseous" (a `Preference`) and "avoid grapefruit" (a `Constraint`)
# each make grapefruit part of the patient's active regimen, and mechanism 1 starts reporting
# interactions between two things nobody is taking.
def rd_regimen_beliefs(a: Anchor) -> list[Belief] {
    out: list[Belief] = [];
    for b in [a <-:About:<-] {
        if isinstance(b, Constraint) or isinstance(b, Preference) {
            continue;
        }
        sup: list[Belief] = [b <-:Supersedes:<-];
        if len(sup) > 0 {
            continue;
        }
        out.append(b);
    }
    return out;
}


def rd_is_regimen(a: Anchor) -> bool {
    bs: list[Belief] = rd_regimen_beliefs(a);
    return len(bs) > 0;
}


# The `Utterance` behind an anchor's active-regimen belief, as a 0-or-1 list. Its `.role` is the
# PRESCRIBER and its `.at` is the REGIMEN DATE (graph.jac's definition, verbatim) — which is what
# lets an `additive_toxicity` concern name two prescribers and two dates without inventing either.
#
# Most recent wins, matching `rd_latest_source`: a regimen restated at a later visit is best cited
# to the restatement. An empty return on an anchor where `rd_is_regimen` is true is the S2 case —
# active regimen, no citation — and the caller records it rather than fabricating a concern.
def rd_regimen_source(a: Anchor) -> list[Utterance] {
    best: list[Utterance] = [];
    for b in rd_regimen_beliefs(a) {
        src: list[Utterance] = rd_latest_source(b);
        if len(src) == 0 {
            continue;
        }
        if (len(best) == 0) or (src[0].at >= best[0].at) {
            best = src;
        }
    }
    return best;
}


# `Member` reads, filtered by `via`. Read PER PAIR — `[edge a ->:Member:->]` zipped against the
# node list by position mispairs an anchor that is a member of two things, which every ingredient
# in the vocabulary eventually is.
#
# These READ `Member`; they do not `visit` it. That distinction is the whole answer to the
# direction question raised in `write.jac` lines 28-35 — see the note on `rd_anchor`'s expansion.
def rd_member_up(a: Anchor, via: str) -> list[Anchor] {
    out: list[Anchor] = [];
    for x in [a ->:Member:->] {
        for e in [edge a ->:Member:-> x] {
            if e.via == via {
                out.append(x);
                break;
            }
        }
    }
    return out;
}


def rd_member_down(a: Anchor, via: str) -> list[Anchor] {
    out: list[Anchor] = [];
    for x in [a <-:Member:<-] {
        for e in [edge x ->:Member:-> a] {
            if e.via == via {
                out.append(x);
                break;
            }
        }
    }
    return out;
}


# Every `ingredient` anchor whose toxicity converges on `sym`.
#
# TWO HOPS IN THE DATA, ONE HOP IN THE DOC. ARCHITECTURE §7 gives the signature as
# `ingredient --toxicity_of--> symptom`, and NO SUCH EDGE EXISTS in the vocabulary. `write.jac`'s
# `VOCAB_MEMBERS` wires the demo triangle as
#     ondansetron  --class_member--> QT-prolonging --toxicity_of--> qt_prolongation
#     levofloxacin --class_member--> QT-prolonging
# so implementing the doc literally finds nothing on the seeded graph. Both shapes are accepted:
# the tail of the `toxicity_of` edge counts if it is an ingredient itself, and so do its
# `class_member` members if it is a class. Three lines, and the rule survives whichever of the two
# gets corrected.
def rd_toxicity_contributors(sym: Anchor) -> list[Anchor] {
    out: list[Anchor] = [];
    keys: list[str] = [];
    for tail in rd_member_down(sym, "toxicity_of") {
        cands: list[Anchor] = [tail];
        for m in rd_member_down(tail, "class_member") {
            cands.append(m);
        }
        for cnd in cands {
            # `ingredient` only. `food` is deliberately not a contributor: grapefruit is not
            # prescribed, so there is no second prescriber and no "nobody compared them" — the
            # grapefruit path is an interaction, which is the other half of this mechanism.
            if cnd.kind != "ingredient" {
                continue;
            }
            if cnd.key in keys {
                continue;
            }
            keys.append(cnd.key);
            out.append(cnd);
        }
    }
    return out;
}


# Un-superseded constraints reaching an anchor by EITHER `Governs` or `Excludes`.
#
# Both, deliberately. `write.jac` says the `INTERACTION_TABLE` pair
# (`CYP3A4-inducer`, `CYP3A4-substrate`) is wired into a `Constraint` by #4/#7 once the regimen
# contains both sides; the natural wiring is one constraint that `Excludes` the inducer and
# `Governs` the substrate. Scanning only `Excludes` finds that pair from St John's Wort and misses
# it entirely from imatinib.
def rd_touching_constraints(a: Anchor) -> list[Constraint] {
    out: list[Constraint] = [];
    seen: list[str] = [];
    cands: list[Constraint] = [a <-:Governs:<-];
    for c in [a <-:Excludes:<-] {
        cands.append(c);
    }
    for c in cands {
        cid: str = jid(c);
        if cid in seen {
            continue;
        }
        seen.append(cid);
        sup: list[Belief] = [c <-:Supersedes:<-];
        if len(sup) > 0 {
            continue;
        }
        out.append(c);
    }
    return out;
}


# An anchor together with the classes it is a `class_member` of. One hop — the vocabulary needs
# exactly one, and an unbounded climb would let a constraint on a distant superclass bind
# everything beneath it.
def rd_self_and_classes(a: Anchor) -> list[Anchor] {
    out: list[Anchor] = [a];
    for g in rd_member_up(a, "class_member") {
        out.append(g);
    }
    return out;
}


# The OTHER side of a constraint, expanded down to concrete substances: every anchor `c` touches
# except `x`, plus the `class_member` members of each, kept if it is a substance the patient could
# actually be taking.
def rd_partner_candidates(c: Constraint, x: Anchor) -> list[Anchor] {
    out: list[Anchor] = [];
    keys: list[str] = [];
    ys: list[Anchor] = [c ->:Governs:->];
    for y in [c ->:Excludes:->] {
        ys.append(y);
    }
    for y in ys {
        if y.key == x.key {
            continue;
        }
        cands: list[Anchor] = [y];
        for m in rd_member_down(y, "class_member") {
            cands.append(m);
        }
        for cnd in cands {
            if cnd.kind not in ["ingredient", "food"] {
                continue;
            }
            if cnd.key in keys {
                continue;
            }
            keys.append(cnd.key);
            out.append(cnd);
        }
    }
    return out;
}


# ==========================================================================================
# Channel A helpers (#15) — beam, budget, lazy decay, reinforcement over About/Relates/Shortcut.
# ==========================================================================================
#
# SCHEMA CORRECTION TO #15's TEXT: the issue's traversal description puts Shortcut at the Belief
# step ("at Belief: ... score [edge here ->:Relates:->] plus ->:Shortcut:->"). graph.jac pins
# `edge Shortcut: Anchor --> Belief`, so a Belief can never have an OUTGOING Shortcut edge — the
# type doesn't allow it, and `[here ->:Shortcut:->]` from a Belief is unconditionally empty.
# Shortcut is scored at the ANCHOR step instead, alongside About, which is where the schema
# actually permits it (Anchor is the left endpoint) and matches Consolidate's own framing of a
# Shortcut as a collapsed Anchor->Belief path (ARCHITECTURE §4, "Shortcut promotion", #57).
#
# SPEC CONFLICT, RESOLVED AGAINST THE ACCEPTANCE LINE: #15's Belief-step text also says "budget
# -= 1; exhausted then disengage". Read literally, `disengage` is the Jac keyword that halts the
# WHOLE walker — but channel A and channel B share one visit queue (`rd_anchor` queues
# `governed`/`excluded`/Member-expansion Anchors; this file's new Belief-entry ability queues
# further Beliefs), so a literal `disengage` on budget exhaustion would abort any channel-B
# Constraint/Anchor visits still queued behind it. That is impossible under #15's own acceptance
# line 5, "channel B results are byte-identical with channel A enabled and disabled" — a
# literal-disengage build could not pass that test on any topology where the queue interleaves.
# Implemented as an early `return`, scoped to the one ability, which stops this branch's further
# collection/expansion without touching the walker's lifecycle or the shared queue.
#
# UNPINNED CONSTANTS: half-life, beam, budget, and the reinforcement step are not given numbers
# anywhere in ARCHITECTURE.md or CONTRACTS.md. Picked here and documented, same treatment as
# write.jac's Consolidate `at`-field gap — not resolved as if it were an open question, just
# recorded as a choice.
glob RD_HALF_LIFE_DAYS: float = 14.0;
glob RD_BEAM: int = 3;
glob RD_BUDGET_DEFAULT: int = 10;
glob RD_REINFORCE_STEP: float = 0.25;
glob RD_WATERLINE: float = 0.1;   # A6/#15 occlusion: effective score below this is excluded from
                                   # the beam pool, not deleted — the belief and its DerivedFrom
                                   # edge are untouched, only absent from THIS read.

# "Now" for lazy decay: the graph's own most-recent Utterance.at, same deterministic-clock
# discipline as write.jac's wr_latest_utterance_at — reimplemented locally, not imported.
# read.jac does not import from write.jac (CONTRACTS §1a discipline 4).
def rd_now(at_root: Root) -> str {
    utts: list[Utterance] = [at_root -->][?:Utterance];
    latest: str = "";
    for u in utts {
        if u.at > latest {
            latest = u.at;
        }
    }
    return latest;
}

# ISO "YYYY-MM-DD" day difference (both dates are always this shape in this graph). A lexical
# 365/30/1-day-per-unit approximation, not a calendar-exact diff — adequate for a decay half-life
# measured in weeks, and it avoids importing `datetime` into a walker file for one subtraction.
def rd_days_between(earlier: str, later: str) -> int {
    if earlier == "" or later == "" {
        return 0;
    }
    ey: int = int(earlier[0:4]);
    em: int = int(earlier[5:7]);
    ed: int = int(earlier[8:10]);
    ly: int = int(later[0:4]);
    lm: int = int(later[5:7]);
    ld: int = int(later[8:10]);
    e_days: int = (ey * 365) + (em * 30) + ed;
    l_days: int = (ly * 365) + (lm * 30) + ld;
    diff: int = l_days - e_days;
    return diff if diff > 0 else 0;
}

# Lazy decay, computed at read time — no sweep, no scheduler (#15's own contract line).
# `strength * 0.5 ** (days_since(last_used) / half_life)`. A belief never reinforced
# (`last_used == ""`) has no staleness to measure — treated as fresh, not maximally decayed.
def rd_effective(strength: float, last_used: str, now: str) -> float {
    if last_used == "" {
        return strength;
    }
    days: int = rd_days_between(last_used, now);
    half_lives: float = float(days) / RD_HALF_LIFE_DAYS;
    return strength * (0.5 ** half_lives);
}

# Top-`beam` of `candidates` by `scores` descending. Beam is single digits, so a manual
# selection pass over a plain list reads clearer than sorting tuples of mixed node/float type.
def rd_top_beam(candidates: list[Belief], scores: dict[str, float], beam: int) -> list[Belief] {
    pool: list[Belief] = [];
    for c in candidates {
        pool.append(c);
    }
    chosen: list[Belief] = [];
    n: int = beam if beam < len(pool) else len(pool);
    for i in range(n) {
        best_idx: int = -1;
        best_score: float = -1.0;
        for idx in range(len(pool)) {
            cid: str = jid(pool[idx]);
            sc: float = float(scores.get(cid, 0.0));
            if sc > best_score {
                best_score = sc;
                best_idx = idx;
            }
        }
        chosen.append(pool[best_idx]);
        pool.pop(best_idx);
    }
    return chosen;
}

# Reinforcement (A9: only Recall reinforces). Bumps the collected belief's own fields, and — for
# a Relates edge actually walked — its weight/co_uses/last_used. `About`/`Shortcut` intentionally
# untouched: neither carries a `last_used` field in the frozen schema (graph.jac), so there is
# nothing for the decay formula to read on either edge type, and bumping a value nothing ever
# decays buys no measurable behavior. `Relates` carries the full field set the formula reads.
def rd_reinforce_belief(b: Belief, now: str) {
    b.uses = b.uses + 1;
    b.last_used = now;
    b.strength = b.strength + RD_REINFORCE_STEP;
}

def rd_reinforce_relates(e: Relates, now: str) {
    e.weight = e.weight + RD_REINFORCE_STEP;
    e.co_uses = e.co_uses + 1;
    e.last_used = now;
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

    # One emergency `Concern` per (constraint, anchor) that crosses; a constraint governing two
    # crossed anchors is two criteria, not one duplicate.
    has rd_seen_emergencies: list[str] = [];

    # Mechanism 1 (#10) dedupe, keyed by kind + the UNORDERED pair (+ the constraint, for
    # `interaction`). Unordered on purpose: the triangle is reachable from either arm and the
    # curated pair from either side, and both must yield the same single concern.
    has rd_seen_pairs: list[str] = [];

    # --- channel A (#15) — extra fields, all defaulted. CONTRACTS §4 pins `anchors`/`out`; an
    # extra defaulted `has` field does not change an existing caller's spawn (`root spawn
    # Recall(anchors=a)` still works unchanged), same discipline as Consolidate's `budget`. -----
    has budget: int = RD_BUDGET_DEFAULT;
    has beam: int = RD_BEAM;
    # Testability toggle for #15's own acceptance line 5 ("channel B byte-identical with channel
    # A enabled and disabled") — without a real switch that line is a code-review claim, not a
    # test. Every channel-A ability below checks this first.
    has rd_channel_a_on: bool = True;

    has rd_now_cached: str = "";              # set once in `rd_start`; Root entry is the only
                                               # place `here` is actually Root
    has rd_soft_taken: int = 0;               # beliefs actually collected into `out.soft`
    has rd_seen_soft_beliefs: list[str] = []; # cycle/dedupe guard, mirrors `rd_seen_anchors`
    has rd_soft_trail_beliefs: list[Belief] = [];    # collected beliefs, reinforced at Root exit
    has rd_soft_trail_relates: list[Relates] = [];   # Relates edges walked, reinforced at exit

    # ============ S5: THE EMERGENCY BYPASS. THIS ABILITY MUST STAY FIRST. ================
    #
    # Two `with Root entry` abilities on one walker BOTH fire, in DECLARATION ORDER — verified on
    # a spike, not read from docs. `disengage` here suppresses `rd_start` AND `rd_finish`, so on
    # the escalate path nothing else in this walker executes and exactly one report is emitted.
    #
    # That is S5 expressed as structure rather than as a flag the rest of the walker agrees to
    # respect: "evaluated before scoring, drafting, or beam" is true because THE REST NEVER RUNS.
    #
    # THE COST: declaration order is load-bearing and invisible. Move this below `rd_start` and S5
    # breaks silently — `jac check` sees nothing and every other test still passes. The test
    # `channel_b_does_not_run_on_the_escalate_path` is the only thing standing between a future
    # refactor and a silent S5 violation. Do not delete it, and do not reorder these abilities.
    can rd_emergency with Root entry {
        # Scanned at root and deliberately NOT filtered by `self.anchors`. Febrile neutropenia is
        # an emergency whether or not the patient thought to ask about fever; scoping the scan to
        # the query would make the interstitial depend on the patient already suspecting the
        # thing, which is the failure this mechanism exists to prevent. Depth 1 from root, same
        # assumption as `rd_start` and `main.jac`'s `pg_status` — flagged to #5.
        cons: list[Constraint] = [here -->[?:Constraint]];

        for c in cons {
            # `emergency` is PARSED by #4 from the patient's own instructions and never inferred.
            if not c.emergency {
                continue;
            }
            # A2's one carve-out, and it matters more here than anywhere: a retracted emergency
            # instruction that keeps firing is an interstitial nobody can turn off.
            superseders: list[Belief] = [c <-:Supersedes:<-];
            if len(superseders) > 0 {
                continue;
            }

            # An emergency criterion is a `Governs` relationship, but `Excludes` is scanned too —
            # it costs nothing, and a malformed emergency constraint should not silently fail.
            targets: list[Anchor] = [c ->:Governs:->];
            for x in [c ->:Excludes:->] {
                targets.append(x);
            }

            for a in targets {
                hits: list[Observation] = rd_crossings(c, a);
                dates: list[str] = rd_distinct_dates(hits);
                # `threshold_days` honored where parsed; the emergency case is 0, because a single
                # crossing IS the emergency. The D-day persistence window belongs to #12.
                need: int = c.threshold_days if c.threshold_days > 1 else 1;
                if len(dates) < need {
                    continue;
                }

                pair: str = jid(c) + "|" + a.key;
                if pair in self.rd_seen_emergencies {
                    continue;
                }
                self.rd_seen_emergencies.append(pair);

                # The emergency hit IS a channel B hit — S6 makes escalate channel-B-only — so
                # CONTRACTS §3 applies unchanged. Set before the citation check, as in #8.
                if c.hard {
                    self.rd_hard_hit = True;
                }

                cite: list[Utterance] = rd_latest_source(c);
                if len(cite) == 0 {
                    # #8 has this hole for a page row. Here it drops a FULL-SCREEN EMERGENCY:
                    # no `Citation` -> `pg_row` returns None -> the interstitial never renders,
                    # with no error. Raised on #5 as the highest-value write-time assert we have.
                    self.rd_notes.append(
                        "uncitable emergency constraint (no DerivedFrom): " + c.claim
                    );
                    continue;
                }

                # ORDER IS LOAD-BEARING. `pg_slots` fills `{criterion}` from `utts[0].text` and
                # `{source}` from `utts[0].role`, and those are the only two slots the `emergency`
                # template has — so the interstitial's headline is the clinician's own sentence,
                # verbatim. S8 satisfied by quotation, which is its stronger half. Observations
                # follow, feeding the "what I've noticed" dates.
                ev: list[str] = [jid(cite[0])];
                for o in hits {
                    ev.append(jid(o));
                }

                self.out.concerns.append(
                    Concern(
                        kind="emergency",
                        anchor=a.key,
                        evidence=ev,
                        since=dates[0],
                        action="escalate"
                    )
                );
            }
        }

        # Gated on a RENDERABLE emergency, not on `rd_hard_hit`. If the criterion was met but the
        # constraint is uncitable, disengaging would return a blocked verdict with nothing in it —
        # no interstitial, no rows, no explanation. Falling through to channel B is strictly more
        # information for the patient, and `rd_notes` still carries the emergency for #16.
        if len(self.out.concerns) > 0 {
            # `rd_finish` never fires after `disengage`, so `allowed` is assembled and reported
            # here. Still exactly one report.
            self.out.allowed = not self.rd_hard_hit;
            report self.out;
            disengage;
        }
    }

    # --- Root entry: deterministic anchor resolution, no model (A3) ----------------------
    can rd_start with Root entry {
        # Channel A's decay clock (#15) — computed once here, since `here` is only ever Root in
        # THIS ability. Cached rather than recomputed at every Anchor/Belief visit.
        self.rd_now_cached = rd_now(here);

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
        #
        # `write.jac` lines 28-35 ask read.jac to read `Member` as UNDIRECTED or "this traversal
        # breaks", which reads as a contradiction and is not one. The split #10 makes explicit:
        #   EXPANSION (`visit`) stays forward-only — reverse expansion is the over-blocking above.
        #   DETECTION reads `Member` backwards as a LOCAL structural read, no `visit`
        #     (`rd_member_down`). Finding the second arm of a triangle is not walking through it.
        # Mechanism 1 is the case that note is about, and it is served by the reverse read alone.
        visit [here ->:Member:->];

        # ===== MECHANISM 1 (#10) — a path exists that should not =========================
        # Structural, unscored, ceiling `ask` (CONTRACTS §3) — never `escalate`, which S6 reserves
        # for `rd_emergency`. Runs after the `visit`s only for reading order; `visit` queues rather
        # than recurses, so nothing below depends on it.
        #
        # ONCE PER ANCHOR. The `rd_seen_anchors` guard at the top of this ability is what makes
        # the shared symptom of a triangle processed a single time no matter how many arms of it
        # the traversal arrived on.

        # --- additive toxicity: the triangle, and the headline detection -----------------
        # Two prescribers, one shared toxicity, nobody compared them because nobody was in both
        # rooms. Gated on `symptom`: `CYP3A4-inhibitor --toxicity_of--> CYP3A4-substrate` converges
        # on a CLASS, and two drugs meeting there is an interaction, not a shared toxicity.
        if here.kind == "symptom" {
            actives: list[Anchor] = [];
            srcs: list[Utterance] = [];
            for cnd in rd_toxicity_contributors(here) {
                u: list[Utterance] = rd_regimen_source(cnd);
                if len(u) == 0 {
                    # Distinguish "not on the regimen" (silent, correct) from "on the regimen but
                    # uncitable" (S2 — recorded, never fabricated into a concern). Same handling
                    # as #8's uncitable constraint; same ask on #5.
                    if rd_is_regimen(cnd) {
                        self.rd_notes.append(
                            "uncitable regimen belief (no DerivedFrom): " + cnd.key
                        );
                    }
                    continue;
                }
                actives.append(cnd);
                srcs.append(u[0]);
            }

            n: int = len(actives);
            for i in range(n) {
                for j in range(i + 1, n) {
                    # Order the pair by (regimen date, key). `pg_slots` reads `{role_a}`/`{at_a}`
                    # off `utts[0]` and `{role_b}`/`{at_b}` off `utts[1]`, so EVIDENCE ORDER IS
                    # LOAD-BEARING: evidence[0] is the earlier prescription, and the row reads
                    # chronologically. Asserted in the annex, not left to insertion order.
                    ka: str = srcs[i].at + "|" + actives[i].key;
                    kb: str = srcs[j].at + "|" + actives[j].key;
                    swap: bool = kb < ka;
                    lo: int = j if swap else i;
                    hi: int = i if swap else j;

                    two: list[str] = sorted([actives[i].key, actives[j].key]);
                    pk: str = "tox|" + here.key + "|" + two[0] + "|" + two[1];
                    if pk in self.rd_seen_pairs {
                        continue;
                    }
                    self.rd_seen_pairs.append(pk);

                    self.out.concerns.append(
                        Concern(
                            kind="additive_toxicity",
                            anchor=here.key,
                            evidence=[jid(srcs[lo]), jid(srcs[hi])],
                            # The LATER date. The convergence begins when the second drug lands;
                            # the first one on its own was never a concern, and dating the row to
                            # it would overstate how long this has been true.
                            since=srcs[hi].at,
                            action="ask"
                        )
                    );
                }
            }
        }

        # --- interaction: a curated pair with both sides on board ------------------------
        # Table stakes — a dictionary lookup does it (ARCHITECTURE §7). Built, never led with.
        if here.kind in ["ingredient", "food"] {
            mine: list[Utterance] = rd_regimen_source(here);
            if len(mine) > 0 {
                for x in rd_self_and_classes(here) {
                    for c in rd_touching_constraints(x) {
                        for r in rd_partner_candidates(c, x) {
                            if r.key == here.key {
                                continue;
                            }
                            rs: list[Utterance] = rd_regimen_source(r);
                            if len(rs) == 0 {
                                continue;
                            }

                            # `{new}` is the LATER-PRESCRIBED side — "{regimen_drug} is already on
                            # my list; {new} was added". Decided structurally from the two regimen
                            # dates, which needs no clock: `Recall` has no `today` (CONTRACTS §4),
                            # the same gap flagged on #9. Key breaks a same-day tie so the answer
                            # is deterministic, and computing it from the pair rather than from
                            # `here` is what makes both arrival directions agree.
                            mk: str = mine[0].at + "|" + here.key;
                            rk: str = rs[0].at + "|" + r.key;
                            newer: bool = rk > mk;
                            new_key: str = r.key if newer else here.key;
                            new_src: Utterance = rs[0] if newer else mine[0];

                            two: list[str] = sorted([here.key, r.key]);
                            pk: str = "int|" + two[0] + "|" + two[1] + "|" + jid(c);
                            if pk in self.rd_seen_pairs {
                                continue;
                            }
                            self.rd_seen_pairs.append(pk);

                            cite: list[Utterance] = rd_latest_source(c);
                            if len(cite) == 0 {
                                self.rd_notes.append(
                                    "uncitable interaction constraint (no DerivedFrom): "
                                    + c.claim
                                );
                                continue;
                            }

                            # evidence[0] is the NEW substance's own utterance: `pg_slots` fills
                            # `{role}`/`{at}` from `utts[0]`, and the template says
                            # "{new} was added ({role}, {at})". The constraint's citation follows,
                            # carrying the label provenance.
                            self.out.concerns.append(
                                Concern(
                                    kind="interaction",
                                    anchor=new_key,
                                    evidence=[jid(new_src), jid(cite[0])],
                                    since=new_src.at,
                                    action="ask"
                                )
                            );
                        }
                    }
                }
            }
        }
    }

    # --- Anchor entry, channel A (#15): score About + Shortcut, visit top `beam` ---------
    # A SEPARATE ability from `rd_anchor` above, not a branch inside it — multiple abilities
    # declared for the same node type all fire, in declaration order (the two `Root entry`
    # abilities above already rely on this). Keeping channel A in its own ability is what makes
    # "channel B byte-identical with channel A enabled and disabled" (#15 acceptance line 5)
    # actually true: this ability never touches `self.out.violations`, `self.out.concerns`,
    # `self.rd_hard_hit`, or `self.out.allowed`, and `rd_anchor` above is untouched by its
    # presence, run order, or absence.
    can rd_anchor_soft with Anchor entry {
        if not self.rd_channel_a_on {
            return;
        }
        if self.rd_soft_taken >= self.budget {
            return;
        }

        candidates: list[Belief] = [];
        scores: dict[str, float] = {};

        # `[here <-:About:<-]` returns `Preference`/`Constraint` subclass instances too — the
        # same gotcha `rd_regimen_beliefs` documents above. Constraints are channel B's exclusive
        # domain; Preferences are exactly channel A's domain ("soft: preferences, conventions",
        # #15's own framing), so only Constraint is excluded here.
        for b in [here <-:About:<-] {
            if isinstance(b, Constraint) {
                continue;
            }
            bid: str = jid(b);
            if bid in self.rd_seen_soft_beliefs {
                continue;
            }
            superseders: list[Belief] = [b <-:Supersedes:<-];
            if len(superseders) > 0 {
                continue;
            }
            eff: float = rd_effective(b.strength, b.last_used, self.rd_now_cached);
            if eff < RD_WATERLINE {
                continue;
            }
            candidates.append(b);
            scores[bid] = eff;
        }

        # Shortcut belongs here, not at the Belief step — see the schema-correction note above
        # `rd_now`. `edge Shortcut: Anchor --> Belief` makes this the only node type it can be
        # read from at all.
        for b in [here ->:Shortcut:->] {
            if isinstance(b, Constraint) {
                continue;
            }
            bid2: str = jid(b);
            if bid2 in self.rd_seen_soft_beliefs {
                continue;
            }
            sup2: list[Belief] = [b <-:Supersedes:<-];
            if len(sup2) > 0 {
                continue;
            }
            eff2: float = rd_effective(b.strength, b.last_used, self.rd_now_cached);
            if eff2 < RD_WATERLINE {
                continue;
            }
            if bid2 not in scores {
                candidates.append(b);
                scores[bid2] = eff2;
            }
        }

        top: list[Belief] = rd_top_beam(candidates, scores, self.beam);
        visit top;
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

    # --- Belief entry, channel A (#15): superseded -> skip; budget; else collect + expand -
    # Fires on `Constraint`/`Preference` visits too (ISA dispatch — both are `Belief` subclasses,
    # same as the `<-:About:<-` gotcha above). The `isinstance` guard is the FIRST statement,
    # before any `self.` mutation, so a `Constraint` visit — queued by channel B's `rd_anchor`
    # via `visit governed;`/`visit excluded;`, sharing this walker's one visit queue — is a true
    # no-op here. That is what keeps channel B's traversal byte-identical regardless of this
    # ability's presence, per #15 acceptance line 5.
    can rd_belief_soft with Belief entry {
        if isinstance(here, Constraint) {
            return;
        }
        if not self.rd_channel_a_on {
            return;
        }

        bid: str = jid(here);
        if bid in self.rd_seen_soft_beliefs {
            return;
        }
        self.rd_seen_soft_beliefs.append(bid);

        superseders: list[Belief] = [here <-:Supersedes:<-];
        if len(superseders) > 0 {
            return;
        }

        # Budget is spent on ARRIVAL. See the header note above `rd_now` for why exhaustion is an
        # early `return` scoped to this ability, not the walker-global `disengage` #15's text
        # names — the latter would abort channel B's still-queued visits on any interleaved
        # topology, which the acceptance line rules out.
        if self.rd_soft_taken >= self.budget {
            return;
        }

        self.rd_soft_taken = self.rd_soft_taken + 1;
        self.out.soft.append(here.claim);
        self.rd_soft_trail_beliefs.append(here);

        candidates: list[Belief] = [];
        scores: dict[str, float] = {};
        relates_edges: dict[str, Relates] = {};

        for b in [here ->:Relates:->] {
            if isinstance(b, Constraint) {
                continue;
            }
            cbid: str = jid(b);
            if cbid in self.rd_seen_soft_beliefs {
                continue;
            }
            sup: list[Belief] = [b <-:Supersedes:<-];
            if len(sup) > 0 {
                continue;
            }
            rel_edges: list[Relates] = [edge here ->:Relates:-> b];
            rel_w: float = 1.0;
            if len(rel_edges) > 0 {
                rel_w = rel_edges[0].weight;
                relates_edges[cbid] = rel_edges[0];
            }
            eff: float = rd_effective(b.strength, b.last_used, self.rd_now_cached) * rel_w;
            if eff < RD_WATERLINE {
                continue;
            }
            candidates.append(b);
            scores[cbid] = eff;
        }

        top: list[Belief] = rd_top_beam(candidates, scores, self.beam);
        for t in top {
            tid: str = jid(t);
            if tid in relates_edges {
                self.rd_soft_trail_relates.append(relates_edges[tid]);
            }
        }
        visit top;
    }

    # --- Root exit: reinforce the channel-A trail only (A9) -------------------------------
    # Order relative to `rd_finish` below does not matter for correctness — reinforcement is a
    # side effect on the persisted graph, not part of the reported `Verdict` — but declared first
    # for reading order (reinforce, then report).
    can rd_soft_reinforce with Root exit {
        if not self.rd_channel_a_on {
            return;
        }
        for b in self.rd_soft_trail_beliefs {
            rd_reinforce_belief(b, self.rd_now_cached);
        }
        for e in self.rd_soft_trail_relates {
            rd_reinforce_relates(e, self.rd_now_cached);
        }
    }

    # --- Root exit: assemble and report exactly once -------------------------------------
    can rd_finish with Root exit {
        self.out.allowed = not self.rd_hard_hit;
        report self.out;
    }
}


# ==========================================================================================
# `Vigil` — unprompted checks on app open (#21)
# ==========================================================================================
#
# Spawned on app open before any input exists (`root spawn Vigil(today=…)` from the cl { } block).
# `:pub` for the same reason as `Recall` (#34) — a plain `walker` answers Unauthorized. It is pure
# CALENDAR ARITHMETIC over the provenance floor (`Observation`/`Utterance`) and parsed instruction
# `Constraint`s: ZERO `by llm()`, and A9 read-only — it never scores, reinforces, decays, or writes
# an edge. Every concern it raises is `mention`, the alert-fatigue ceiling (S6): Vigil surfaces,
# it never alarms. `today` is handed in, never a wall clock, so a run is reproducible (the demo is
# byte-identical). Alert-fatigue by design: it can surface one thing and stay silent about others.

# Whole days from `earlier` to `later` (ISO YYYY-MM-DD). Calendar arithmetic, not `by llm()` — this
# is the "phase is subtraction over a parsed date" line of ARCHITECTURE §3, applied to check-ins.
def rd_days_between(earlier: str, later: str) -> int {
    d0: date = date.fromisoformat(earlier);
    d1: date = date.fromisoformat(later);
    delta: any = d1 - d0;   # jac:ignore[W1037] — timedelta from stdlib; .days is the whole-day count
    return delta.days;
}


# The most-recent `Utterance` behind a set of `Observation`s, as a 0-or-1 list (same 0-or-1 idiom as
# rd_latest_source / rd_regimen_source). An `Observation` carries `DerivedFrom` to its `Utterance`
# (graph.jac §3), so this is the patient's own words to quote back — S2's citation for the row.
def rd_symptom_voice(obs: list[Observation]) -> list[Utterance] {
    best: list[Utterance] = [];
    for o in obs {
        for u in [o ->:DerivedFrom:->] {
            if len(best) == 0 or u.at > best[0].at {
                best = [u];
            }
        }
    }
    return best;
}


walker:pub Vigil {
    has today: str;
    has out: Verdict = Verdict();

    # Internal only — feeds the activity panel / #16 eval (CONTRACTS §4). Not a wire field.
    has rd_notes: list[str] = [];

    can rd_open with Root entry {
        # Depth 1 from root, matching rd_start / rd_emergency / main.jac's pg_status. If the seed
        # attaches these deeper this surfaces nothing and reports an empty Verdict — no error, and
        # rd_notes stays empty; flagged to the seed loader (#7), same assumption as Recall.
        utts: list[Utterance] = [here -->[?:Utterance]];
        anchors: list[Anchor] = [here -->[?:Anchor]];

        # ---- silence: the record has gone quiet ----
        # The patient's own most-recent check-in is both the clock and the citation. This is the one
        # Vigil check that fires on what ISN'T there — the exact failure the `silence` class exists
        # to catch (ARCHITECTURE §5): a graph that stops accumulating goes undetectable otherwise.
        last: list[Utterance] = [];
        for u in utts {
            if u.role == "patient" or u.role == "caregiver" {
                if len(last) == 0 or u.at > last[0].at {
                    last = [u];
                }
            }
        }
        if len(last) > 0 {
            gap: int = rd_days_between(last[0].at, self.today);
            if gap >= VIGIL_SILENCE_DAYS {
                self.out.concerns.append(
                    Concern(
                        kind="silence",
                        anchor="daily-check-in",
                        evidence=[jid(last[0])],
                        since=last[0].at,
                        action="mention"
                    )
                );
            }
        }

        # ---- supportive-care gap: a symptom recurs with no instruction covering it ----
        # A symptom the patient keeps reporting for which NOTHING in the record is an instruction
        # (`Governs`/`Excludes` from a `Constraint`). Absence of a finding is "not in your record",
        # never "safe" (S3) — worth mentioning, never an alarm (S6 => `mention`).
        for a in anchors {
            if a.kind != "symptom" {
                continue;
            }
            sym_obs: list[Observation] = [a <-:Reports:<-];
            dates: list[str] = rd_distinct_dates(sym_obs);
            if len(dates) < VIGIL_RECUR_DAYS {
                continue;
            }
            # An instruction already touches this symptom -> not a gap.
            if len(rd_touching_constraints(a)) > 0 {
                continue;
            }
            cite: list[Utterance] = rd_symptom_voice(sym_obs);
            if len(cite) == 0 {
                # S2: no `Utterance` to quote -> pg_row would drop the row. Record, don't fabricate.
                self.rd_notes.append("supportive-care gap with no citable check-in: " + a.key);
                continue;
            }
            ev: list[str] = [jid(cite[0])];
            for o in sym_obs {
                ev.append(jid(o));
            }
            self.out.concerns.append(
                Concern(
                    kind="supportive_care_gap",
                    anchor=a.key,
                    evidence=ev,
                    since=dates[0],
                    action="mention"
                )
            );
        }

        # ---- adherence_gap and phase transition: DEFERRED, on purpose ----
        # Both are pure arithmetic too, but they read conventions that are not yet locked in the
        # seed, so shipping them now would be unverifiable detection in a file that tests everything:
        #   - adherence_gap is "silent absence" (#3/#7): a regimen ingredient anchor with zero record
        #     since its prescription. There is no `taken` metric — absence is the signal — so this
        #     needs the seed's adherence design (#7) fixed to assert against.
        #   - phase transition needs the `phase` anchors / `cycle_days` that #4 computes at
        #     regimen-parse time. `rd_days_between(regimen_date, today)` vs `cycle_days` is the whole
        #     check; it just needs a parsed regimen to run against.
        # Both slot into this same `rd_open` with one loop each once #7/#4 land. Tracked on #21.
    }

    can rd_close with Root exit {
        # A9: strictly read-only. `allowed` stays True — Vigil never blocks, and by S6 it never
        # reaches `ask` or `escalate`; everything it appended above is `mention`.
        report self.out;
    }
}
