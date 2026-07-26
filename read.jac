# read.jac — the read path. Owner: T2 Nathan.
#
# Imports only from `graph.jac` (CONTRACTS §1a discipline 4). It does not know `write.jac` or
# `main.jac` exist. Every private helper is prefixed `rd_` (discipline 1) so the collapse into
# `main.jac` at submission is a concatenation with no rename.
#
# Contents today: `Recall` channel B (#8), the emergency bypass (#9), all four detection
# mechanisms (#10, #11, #12), corroboration (#13), and `Investigate` (#14). Channel A (#15) and
# `Vigil` (#21) land in later issues.
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
#   S3  absence yields "not in your record", never "safe". Mechanism 2 (#11) is this invariant
#       made operational — the whole class exists so that a gap is a finding, not a silence.
#   S4  `trajectory` (#12) is where dose concern legitimately lives, and the output is "worth
#       raising at the next visit, here is the record". No dosing conclusion, ever.
#   S6  no detection mechanism emits above its per-kind ceiling (`RD_CEILINGS`), and corroboration
#       (#13) promotes only up to it. `escalate` is reachable from exactly one place in this
#       file, `rd_emergency`.
#   A5  corroboration PROMOTES ONLY. There is no code path in this file that lowers an `action`.
#
# `Recall` contains no `while` loop. Policy lives on node-type abilities and the visit queue.

# The EDGE archetypes have to be imported alongside the nodes. Without them every typed traversal
# below infers `any` — and because the locals here are annotated, that surfaces as five E1001s
# instead of passing `jac check` and dying at the first field read. Import the edges you traverse.
import datetime;

import from graph {
    Anchor, Belief, CaseFile, Concern, Constraint, Observation, Preference, TimelineEntry,
    Utterance, Verdict, Violation,
    About, Conflicts, DerivedFrom, Governs, Excludes, Member, Reports, Supersedes
}


# ==========================================================================================
# Severity ladder and per-kind ceilings — CONTRACTS §3, ARCHITECTURE §6
# ==========================================================================================
#
# The ladder as an ordered list, so "one rung up" is an index step and cannot be fat-fingered into
# a two-rung jump. Corroboration (#13) is the only thing that moves a concern along it.
glob RD_LADDER: list[str] = ["log", "mention", "ask", "escalate"];

# THE CEILING TABLE IS A SAFETY SURFACE, not a lookup convenience. CONTRACTS §3 pins every one of
# these, and "ceiling is a hard cap, not a default" — corroboration may promote up to the value
# here and no further. A kind missing from this table is treated as capped at `mention`, which is
# the conservative direction: a new kind cannot reach the top of the page by being forgotten.
glob RD_CEILINGS: dict[str, str] = {
    "interaction": "ask",
    "additive_toxicity": "ask",
    "unattributed_symptom": "mention",
    "supportive_care_gap": "mention",
    "adherence_gap": "mention",
    "silence": "mention",
    "persistence": "ask",
    "trajectory": "mention",
    "emergency": "escalate",
    "instruction_drift": "mention",
    "cross_prescriber_conflict": "ask",
    "nonadherence_cause": "mention",
    "unrecognized_substance": "mention",
};

# Days without an `Observation` referencing a regimen anchor before it counts as an adherence gap
# (#11). A module constant rather than a walker field: `Recall`'s signature is pinned by
# CONTRACTS §4 and this is not worth widening it for.
glob RD_ADHERENCE_DAYS: int = 7;

# Days between consecutive patient check-ins before the gap is `silence` (#11). The seeded gap is
# 2026-06-04 -> 2026-06-08, so anything above 4 would miss the case the corpus was built for.
glob RD_SILENCE_DAYS: int = 3;


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
#
# Typed `Node`, not `Belief`, since #11: graph.jac deliberately broadened `DerivedFrom` to
# `Node --> Utterance` because BOTH `Belief` and `Observation` carry it (S2), and
# `unattributed_symptom` needs an observation's citation. A `Belief`-typed parameter here
# reproduces exactly the mistype that comment warns about, one call site further out.
def rd_latest_source(b: Node) -> list[Utterance] {
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


# Does a `Constraint`'s parsed threshold fire on this anchor, and on which dates?
#
# THE SHARED CROSSING TEST. #9's emergency bypass and #12's `persistence` are the same arithmetic
# over the same parsed fields, distinguished only by `Constraint.emergency` and therefore by
# ceiling — `escalate` for one, `ask` for the other. Keeping the test in one place is what stops
# the emergency and non-emergency halves of "a stated threshold was crossed" from drifting apart.
#
# Returns the qualifying dates, ascending, or [] when the criterion is not met.
#
# `threshold_days` is honored as `max(1, D)`. `wr_write_instruction` hardcodes `D = 0`
# (write.jac:493 — the parser extracts L and never D), so this currently degrades to "crossed at
# least once" rather than to "never fires". That is the right failure direction for an emergency,
# where a single crossing IS the emergency; for persistence "for D days" is the whole content of
# the finding, and it is under-testing the rule until #4 parses a duration. Raised on #4.
def rd_threshold_dates(c: Constraint, a: Anchor) -> list[str] {
    hits: list[Observation] = rd_crossings(c, a);
    dates: list[str] = rd_distinct_dates(hits);
    need: int = c.threshold_days if c.threshold_days > 1 else 1;
    if len(dates) < need {
        return [];
    }
    return dates;
}


# ==========================================================================================
# Mechanism 2/3/4 helpers (#11, #12) — dates, observation chains, conflicts
# ==========================================================================================

# Whole days between two ISO dates, or 0 if either is unparseable. Every gap in mechanism 2 is a
# subtraction between two dates that are BOTH already in the graph — see the note on
# `rd_record_end` for why that distinction is the whole reason this needs no clock.
def rd_days_between(a: str, b: str) -> int {
    if (a == "") or (b == "") {
        return 0;
    }
    try {
        # `.toordinal()` rather than subtracting the dates: an `any`-typed `date - date` gives the
        # checker no `timedelta` to find `.days` on, and fails E1055/E1032 at `jac check`.
        da: int = int(datetime.date.fromisoformat(a).toordinal());
        db: int = int(datetime.date.fromisoformat(b).toordinal());
        return abs(db - da);
    } except Exception {
        # A malformed date is a write-path defect, not a reason to raise on the read path.
        return 0;
    }
}


# Distinct dates on which this anchor was observed, ascending.
def rd_observation_dates(a: Anchor) -> list[str] {
    obs: list[Observation] = [a <-:Reports:<-];
    return rd_distinct_dates(obs);
}


# The last dated `Utterance` in the record.
#
# THIS IS NOT A STAND-IN FOR TODAY, and the distinction is the reason mechanism 2 needs no clock.
# A gap here is the interval between two things that are BOTH written down — "you last logged this
# on the 4th and the record continues to the 21st". That is a question entirely inside the record.
#
# The question this deliberately CANNOT answer is "and it is now the 26th, so you have been silent
# for five more days". That one is genuinely relative to now, and using this value for it would
# freeze the moment the patient stops writing — which is precisely the `silence` failure mode the
# design leads with. `Vigil` (#21) has `today` in its pinned signature and owns that half.
def rd_record_end() -> str {
    utts: list[Utterance] = [root -->[?:Utterance]];
    best: str = "";
    for u in utts {
        if u.at > best {
            best = u.at;
        }
    }
    return best;
}


# Patient check-in dates, ascending. `role == "patient"` ONLY: a label dated 2026-01-01 and an
# oncologist note dated 2026-06-01 are not a five-month silence, they are two documents. Silence is
# about the patient writing, and only the patient can be silent.
def rd_checkin_dates() -> list[str] {
    utts: list[Utterance] = [root -->[?:Utterance]];
    dates: list[str] = [];
    for u in utts {
        if u.role != "patient" {
            continue;
        }
        if u.at not in dates {
            dates.append(u.at);
        }
    }
    return sorted(dates);
}


# BOUNDED gaps in the check-in chain — every consecutive pair more than `min_days` apart, returned
# as [start, end]. Bounded on both sides by construction, so the trailing gap (last check-in to
# now) is absent by design and belongs to `Vigil`. See `rd_record_end`.
def rd_silence_gaps(min_days: int) -> list[list[str]] {
    dates: list[str] = rd_checkin_dates();
    gaps: list[list[str]] = [];
    for i in range(1, len(dates)) {
        if rd_days_between(dates[i - 1], dates[i]) > min_days {
            gaps.append([dates[i - 1], dates[i]]);
        }
    }
    return gaps;
}


# Is this anchor's observation record monotone non-decreasing, with at least one strict increase,
# over at least `min_points` distinct dates? One value per date — the WORST reading that day, so a
# good afternoon after a bad morning does not read as improvement.
#
# `trajectory` (#12), and S4 lives here: this returns a shape, not a conclusion. The row it feeds
# says "it has come up across {cycles} — the pattern is worth showing my team". It does not say
# what to do about it, and no caller may make it say so.
def rd_is_worsening(a: Anchor, min_points: int) -> bool {
    dates: list[str] = rd_observation_dates(a);
    if len(dates) < min_points {
        return False;
    }
    obs: list[Observation] = [a <-:Reports:<-];
    peaks: list[float] = [];
    for d in dates {
        # Collected then `max`ed rather than tracked in a running variable: a reassignment inside
        # the inner loop reads as dead to the checker and raises W2003.
        vals: list[float] = [0.0];
        for o in obs {
            if o.at == d {
                vals.append(o.value);
            }
        }
        peaks.append(max(vals));
    }
    rose: bool = False;
    for i in range(1, len(peaks)) {
        if peaks[i] < peaks[i - 1] {
            return False;
        }
        if peaks[i] > peaks[i - 1] {
            rose = True;
        }
    }
    return rose;
}


# Everything a belief `Conflicts` with, read in BOTH directions. `Conflicts` is directed
# `Belief --> Belief` by schema but the relation it encodes is symmetric — two statements are
# jointly unsatisfiable or they are not — so reading one direction finds half the pairs depending
# on which one `Consolidate` happened to write first.
#
# A3: reading these is deterministic. The satisfiability judgement that CREATES them is `by llm()`
# site #2, on the write path, where the two-site cap already accounts for it. Nothing here calls a
# model.
def rd_conflict_partners(b: Belief) -> list[Belief] {
    out: list[Belief] = [b ->:Conflicts:->];
    for x in [b <-:Conflicts:<-] {
        out.append(x);
    }
    return out;
}


# Is this utterance authority-bearing? CONTRACTS §2 pins the set, and calls adding to it a safety
# change rather than a schema change.
def rd_is_authority(u: Utterance) -> bool {
    return u.role in ["oncologist", "pharmacist", "label"];
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
# Corroboration (#13) — A5: PROMOTES ONLY, NEVER DEMOTES
# ==========================================================================================
#
# Two DISTINCT detection mechanisms converging on one anchor promote every concern on that anchor
# by exactly ONE rung, capped at the per-kind ceiling in `RD_CEILINGS`. Mutates in place and
# returns how many it moved, for the activity panel (#24).
#
# A5 IS ABSOLUTE AND THIS IS THE FUNCTION WHERE IT GETS BROKEN BY ACCIDENT. There is exactly one
# assignment to `action` in this file, it is below, and it is guarded by `idx > cur` so it can only
# move an index upward. A future edit that computes a target rung and assigns it unconditionally
# reintroduces demotion silently — the ladder still looks right in every test where the target
# happens to be the higher value.
#
# A CHANNEL B HIT REACHES `ask` UNCORROBORATED, EVERY TIME. Nothing here is a precondition for
# severity, only an addition to it. Prior art in this space drove precision up by REQUIRING
# corroboration before escalating; copying that would turn the two-channel split into the
# silent-failure generator it exists to eliminate.
#
# A module-level `def` rather than a walker ability so the annex can hand it concerns at any rung
# and check the arithmetic directly. Reachable only through a fixture, the one case that matters
# most — a concern sitting BELOW its ceiling — is currently unreachable, because every mechanism
# in this file emits at its ceiling. Which means this promotes nothing today: the safe direction,
# since an inert promoter cannot hurt anyone and a demoting one could. Its real customer is
# channel A (#15), whose concerns sit below `mention` and which S6 caps there regardless.
def rd_corroborate(cons: list[Concern]) -> int {
    kinds_by_anchor: dict[str, list[str]] = {};
    for c in cons {
        if c.anchor not in kinds_by_anchor {
            kinds_by_anchor[c.anchor] = [];
        }
        if c.kind not in kinds_by_anchor[c.anchor] {
            kinds_by_anchor[c.anchor].append(c.kind);
        }
    }

    moved: list[str] = [];
    for c in cons {
        # DISTINCT KINDS, not concern count. Two `additive_toxicity` rows on one symptom are one
        # mechanism finding two pairs, not two mechanisms agreeing with each other.
        if len(kinds_by_anchor.get(c.anchor, [])) < 2 {
            continue;
        }
        if c.action not in RD_LADDER {
            continue;
        }
        cur: int = RD_LADDER.index(c.action);
        ceil_name: str = RD_CEILINGS.get(c.kind, "mention");
        ceil: int = RD_LADDER.index(ceil_name) if ceil_name in RD_LADDER else 1;

        # ONE rung, and `min` is what makes "stop at the ceiling" true rather than "usually stop
        # at the ceiling". A kind absent from `RD_CEILINGS` caps at `mention` — a new kind cannot
        # reach the top of the page by being forgotten.
        idx: int = min(cur + 1, ceil);
        if idx > cur {
            moved.append(c.anchor);
            c.action = RD_LADDER[idx];
        }
    }
    return len(moved);
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

    # How many concerns corroboration promoted (#13). Walker internal state, not a wire field —
    # CONTRACTS §4 has the activity panel read producer-walker state, and #24 reads this.
    has rd_promotions: int = 0;

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
                # Extracted to `rd_threshold_dates` in #12 so `persistence` cannot drift from this.
                # Behaviour is unchanged: `threshold_days` honored where parsed, and the emergency
                # case is 0 because a single crossing IS the emergency.
                dates: list[str] = rd_threshold_dates(c, a);
                if len(dates) == 0 {
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

        # ===== MECHANISM 2 (#11) — a path is missing that should exist ====================
        # S3 made operational. Absence of an EDGE is inspectable; absence of a top-k hit is not,
        # and a retriever cannot rank a document that does not exist. Everything here is set
        # difference against the parsed regimen: what should be happening is ground truth, what is
        # happening is observed, and the finding is the gap.
        #
        # ALL FOUR CAP AT `mention`. An absence is real evidence and it is not a reason to put a
        # row at the top of the page on its own; corroboration (#13) may lift it, capped.
        #
        # Every gap below is bounded on BOTH sides by dates already in the graph — see
        # `rd_record_end`. The trailing "and nothing since, and it is now July" half needs a clock
        # and is `Vigil`'s (#21).

        # --- unattributed symptom: reported, and nothing on the list explains it ----------
        # New and unexplained means MORE urgent, not less. This is `rd_toxicity_contributors`
        # from #10 read for emptiness — the same helper answers mechanism 1 by being non-empty and
        # mechanism 2 by being empty, so the two can never disagree about what attributes what.
        if here.kind == "symptom" {
            odates: list[str] = rd_observation_dates(here);
            if len(odates) > 0 {
                # Collected rather than flagged: a `bool` set inside a branch reads as dead to the
                # checker (W2003), and the keys are worth having when this is being debugged.
                attributed: list[str] = [];
                for cnd in rd_toxicity_contributors(here) {
                    if len(rd_regimen_source(cnd)) > 0 {
                        attributed.append(cnd.key);
                    }
                }
                ukey: str = "unattr|" + here.key;
                if (len(attributed) == 0) and (ukey not in self.rd_seen_pairs) {
                    self.rd_seen_pairs.append(ukey);
                    # `{count}` counts the Utterance citations, so the observations' own sources
                    # lead. Without them `pg_row` drops the row for having no citation (S2).
                    uev: list[str] = [];
                    for o in [here <-:Reports:<-] {
                        for su in rd_latest_source(o) {
                            if jid(su) not in uev {
                                uev.append(jid(su));
                            }
                        }
                    }
                    for o in [here <-:Reports:<-] {
                        uev.append(jid(o));
                    }
                    if len(uev) == 0 {
                        self.rd_notes.append("uncitable symptom observations: " + here.key);
                    } else {
                        self.out.concerns.append(
                            Concern(
                                kind="unattributed_symptom", anchor=here.key, evidence=uev,
                                since=odates[0], action="mention"
                            )
                        );
                    }
                }
            }
        }

        # --- supportive-care gap: the prescription that was never filled ------------------
        # ARCHITECTURE §7's caption, implemented literally: the patient is describing a symptom,
        # an instruction covering it exists, and the substance that instruction names has no
        # adherence record at all.
        if here.kind == "symptom" {
            sdates: list[str] = rd_observation_dates(here);
            if len(sdates) > 0 {
                for c in rd_touching_constraints(here) {
                    named: list[Anchor] = rd_partner_candidates(c, here);
                    if len(named) == 0 {
                        # An instruction that names no substance cannot be un-filled.
                        continue;
                    }
                    followed: list[str] = [];
                    for d in named {
                        if len(rd_observation_dates(d)) > 0 {
                            followed.append(d.key);
                        }
                    }
                    if len(followed) > 0 {
                        continue;
                    }
                    gkey: str = "scgap|" + here.key + "|" + jid(c);
                    if gkey in self.rd_seen_pairs {
                        continue;
                    }
                    self.rd_seen_pairs.append(gkey);

                    cite: list[Utterance] = rd_latest_source(c);
                    if len(cite) == 0 {
                        self.rd_notes.append(
                            "uncitable supportive-care instruction: " + c.claim
                        );
                        continue;
                    }
                    # `{instruction}` resolves from the first AUTHORITY-role utterance, so the
                    # constraint's citation must be present; `{since}` is when the patient started
                    # describing the symptom, which is the observations'.
                    sev: list[str] = [jid(cite[0])];
                    for o in [here <-:Reports:<-] {
                        sev.append(jid(o));
                    }
                    self.out.concerns.append(
                        Concern(
                            kind="supportive_care_gap", anchor=here.key, evidence=sev,
                            since=sdates[0], action="mention"
                        )
                    );
                }
            }
        }

        # --- adherence gap: a regimen drug with no record of being taken -----------------
        # Interval from the last thing we know about this drug — its most recent observation, or
        # its regimen date if it has never been observed — to the end of the record. Both ends are
        # dates in the graph.
        if here.kind in ["ingredient", "food"] {
            reg: list[Utterance] = rd_regimen_source(here);
            if len(reg) > 0 {
                adates: list[str] = rd_observation_dates(here);
                last_seen: str = adates[-1] if len(adates) > 0 else reg[0].at;
                end: str = rd_record_end();
                if (end != "") and (rd_days_between(last_seen, end) > RD_ADHERENCE_DAYS) {
                    akey: str = "adh|" + here.key;
                    if akey not in self.rd_seen_pairs {
                        self.rd_seen_pairs.append(akey);
                        aev: list[str] = [jid(reg[0])];
                        for o in [here <-:Reports:<-] {
                            aev.append(jid(o));
                        }
                        self.out.concerns.append(
                            Concern(
                                kind="adherence_gap", anchor=here.key, evidence=aev,
                                since=last_seen, action="mention"
                            )
                        );
                    }
                }
            }
        }

        # --- nonadherence cause: the same absence, plus a stated reason -------------------
        # PLAUSIBLY THE HIGHEST-VALUE ROW THE SYSTEM PRODUCES (#12). Missed for cost or transport
        # and missed for toxicity lead to different clinical action, and the second is what gets
        # assumed when nobody asks.
        #
        # Detected STRUCTURALLY, not by reading the claim text: an active-regimen drug, no
        # observation of it since its regimen date, and the patient saying something about it
        # afterwards. Nothing marks a `Belief` as "this is why I stopped" — and nothing needs to,
        # because the row then quotes the patient verbatim, which is S8's stronger half.
        if here.kind in ["ingredient", "food"] {
            nreg: list[Utterance] = rd_regimen_source(here);
            if len(nreg) > 0 {
                ndates: list[str] = rd_observation_dates(here);
                since_reg: list[str] = [];
                for d in ndates {
                    if d >= nreg[0].at {
                        since_reg.append(d);
                    }
                }
                if len(since_reg) == 0 {
                    for b in [here <-:About:<-] {
                        if isinstance(b, Constraint) or isinstance(b, Preference) {
                            continue;
                        }
                        for bu in rd_latest_source(b) {
                            if bu.role != "patient" {
                                continue;
                            }
                            if bu.at < nreg[0].at {
                                continue;
                            }
                            nkey: str = "ncause|" + here.key + "|" + jid(bu);
                            if nkey in self.rd_seen_pairs {
                                continue;
                            }
                            self.rd_seen_pairs.append(nkey);
                            # The PATIENT utterance leads: `pg_slots` fills `{cause}` and `{at}`
                            # from the first `role == "patient"` citation, and the whole point of
                            # this row is that the reason is in the patient's own words.
                            self.out.concerns.append(
                                Concern(
                                    kind="nonadherence_cause", anchor=here.key,
                                    evidence=[jid(bu), jid(nreg[0])],
                                    since=bu.at, action="mention"
                                )
                            );
                        }
                    }
                }
            }
        }

        # ===== MECHANISM 3 (#12) — accumulated Observation crosses a stated threshold =====
        # The NON-emergency half. `rd_emergency` takes `emergency == True` at `escalate`; this
        # takes the rest at `ask`, over the same parsed fields and the same crossing test. Both
        # call `rd_threshold_dates`, which is the only reason they cannot drift apart.
        #
        # ARCHITECTURE §8 lists threshold evaluation among the seven places that must never hold a
        # `by llm()`. L and D are parsed by #4 from the patient's own instructions and are never
        # recalled by a model; everything below is arithmetic over what #4 wrote.
        if here.kind in ["symptom", "lab"] {
            for c in rd_touching_constraints(here) {
                # `emergency == True` is `rd_emergency`'s, and it has already run and disengaged if
                # it fired. Re-emitting it here at `ask` would put the same criterion on the page
                # twice at two severities.
                if c.emergency {
                    continue;
                }
                if c.threshold_level <= 0.0 and c.threshold_metric == "" {
                    # No parsed threshold at all — an ordinary constraint, already channel B's.
                    continue;
                }

                dates: list[str] = rd_threshold_dates(c, here);
                if len(dates) == 0 {
                    continue;
                }

                pkey: str = "pers|" + jid(c) + "|" + here.key;
                if pkey in self.rd_seen_pairs {
                    continue;
                }
                self.rd_seen_pairs.append(pkey);

                cite: list[Utterance] = rd_latest_source(c);
                if len(cite) == 0 {
                    self.rd_notes.append(
                        "uncitable threshold constraint (no DerivedFrom): " + c.claim
                    );
                    continue;
                }

                # `pg_slots` fills `{threshold_source}` from the first AUTHORITY-role utterance and
                # `{level}` from the most recent Observation among the evidence, so the constraint's
                # citation leads and the crossings follow.
                ev: list[str] = [jid(cite[0])];
                for o in rd_crossings(c, here) {
                    ev.append(jid(o));
                }

                self.out.concerns.append(
                    Concern(
                        kind="persistence",
                        anchor=here.key,
                        evidence=ev,
                        # EARLIEST qualifying date — "I've reported this at {level} for {days}
                        # days" is a duration, and it starts when the crossing started.
                        since=dates[0],
                        action="ask"
                    )
                );
            }
        }

        # --- trajectory: monotone worsening on a cumulative-toxicity anchor --------------
        # S4 IS THE POINT OF THIS RULE, not a side condition. ARCHITECTURE §7 names trajectory as
        # the place dose concern legitimately lives, and the output is "worth raising at the next
        # visit, here is the record". The rule reports a SHAPE — non-decreasing with a rise — and
        # never a cause, a dose, or a recommendation. Neither the template nor anything below
        # contains dosing vocabulary, and the acceptance check greps for it.
        #
        # NO DATA SOURCE ON MAIN TODAY: nothing in `write.jac` ever sets `Anchor.cumulative`, so
        # this fires only on a fixture. The rule is right and the vocabulary does not feed it yet.
        if here.kind == "symptom" {
            for src in rd_toxicity_contributors(here) {
                if not src.cumulative {
                    continue;
                }
                drug_src: list[Utterance] = rd_regimen_source(src);
                if len(drug_src) == 0 {
                    continue;
                }
                # Three points, because two is a line and not yet a pattern.
                if not rd_is_worsening(here, 3) {
                    continue;
                }
                tkey: str = "traj|" + here.key + "|" + src.key;
                if tkey in self.rd_seen_pairs {
                    continue;
                }
                self.rd_seen_pairs.append(tkey);

                # `{cycles}` resolves from `pg_slots`' observation-date count, so the observations
                # have to be in the evidence for the row to say anything. The regimen utterance
                # leads so S2 has a citation to render.
                tev: list[str] = [jid(drug_src[0])];
                for o in [here <-:Reports:<-] {
                    tev.append(jid(o));
                }
                odates: list[str] = rd_observation_dates(here);
                self.out.concerns.append(
                    Concern(
                        kind="trajectory", anchor=here.key, evidence=tev,
                        since=odates[0], action="mention"
                    )
                );
            }
        }

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

        # ===== MECHANISM 4 (#12) — two stated things contradict ==========================
        # One traversal over `Conflicts`, classified by what sits at the far end. The edges are
        # written by `Consolidate` (#6), whose satisfiability judgement is `by llm()` site #2 on
        # the WRITE path — reading them here is deterministic and adds no site (A3).
        #
        # NO DATA SOURCE ON MAIN TODAY: `Consolidate`'s walker body has not landed, so nothing
        # writes a `Conflicts` edge and both kinds below fire only on a fixture. Raised on #6.
        #
        # Placed after the citation check deliberately: a superseded or uncitable constraint has
        # already `skip`ped, and a contradiction we cannot cite cannot be shown either (S2).
        for other in rd_conflict_partners(here) {
            osrc: list[Utterance] = rd_latest_source(other);
            if len(osrc) == 0 {
                self.rd_notes.append("uncitable conflict partner (no DerivedFrom): " + other.claim);
                continue;
            }
            ou: Utterance = osrc[0];

            two: list[str] = sorted([cid, jid(other)]);
            ckey: str = "conf|" + two[0] + "|" + two[1];
            if ckey in self.rd_seen_pairs {
                continue;
            }
            self.rd_seen_pairs.append(ckey);

            # The anchor a conflict is ABOUT. `Row.id` feeds `Investigate`, so a conflict with no
            # anchor is a row the patient cannot expand; skip rather than emit an unopenable row.
            subjects: list[Anchor] = [here ->:Governs:->];
            for x in [here ->:Excludes:->] {
                subjects.append(x);
            }
            if len(subjects) == 0 {
                self.rd_notes.append("conflict on an anchorless constraint: " + here.claim);
                continue;
            }

            if isinstance(other, Constraint) {
                # Two INSTRUCTIONS that cannot both be followed. Only a cross-PRESCRIBER conflict
                # if the two authorities differ — one clinician restating themselves is not a
                # conflict between clinicians, and putting it on the page as one would be a
                # fabricated disagreement.
                if not (rd_is_authority(u) and rd_is_authority(ou)) {
                    continue;
                }
                if u.role == ou.role {
                    continue;
                }
                # Ordered by (date, jid) so both arrival directions agree. `pg_slots` fills
                # `{claim_a}`/`{role_a}` from utts[0] and `{claim_b}`/`{role_b}` from utts[1].
                mine_k: str = u.at + "|" + cid;
                other_k: str = ou.at + "|" + jid(other);
                first: Utterance = u if mine_k <= other_k else ou;
                second: Utterance = ou if mine_k <= other_k else u;
                self.out.concerns.append(
                    Concern(
                        kind="cross_prescriber_conflict", anchor=subjects[0].key,
                        evidence=[jid(first), jid(second)],
                        since=first.at, action="ask"
                    )
                );
            } else {
                # An INSTRUCTION against a BEHAVIOUR: "within 30 minutes after food" versus
                # "whenever I remember". `pg_slots` fills `{instruction}` from the first
                # authority-role citation and `{observed}` from the first patient-role one, so the
                # evidence must carry ONE OF EACH or the row says the instruction twice.
                if not rd_is_authority(u) {
                    continue;
                }
                if ou.role != "patient" {
                    continue;
                }
                dev: list[str] = [jid(u), jid(ou)];
                # `{days}` counts observation dates in the evidence; without these the row reads
                # "On 0 days I described ...".
                for o in [subjects[0] <-:Reports:<-] {
                    dev.append(jid(o));
                }
                self.out.concerns.append(
                    Concern(
                        kind="instruction_drift", anchor=subjects[0].key, evidence=dev,
                        since=ou.at, action="mention"
                    )
                );
            }
        }
    }

    # --- Root exit: corroboration (#13), then assemble and report exactly once ------------
    can rd_finish with Root exit {
        self.rd_promotions = rd_corroborate(self.out.concerns);
        self.out.allowed = not self.rd_hard_hit;
        report self.out;
    }
}


# ==========================================================================================
# `Investigate` — the case file (#14)
# ==========================================================================================
#
# THE DIFFERENCE BETWEEN A DETECTOR AND A COMPANION. Spawned LAZILY, when the patient expands an
# `ask` row — not on every finding. A detector says "these two drugs share a risk"; a companion
# says "here is when it started, here is what changed that week, and here is what you were already
# told about it".
#
# Signature pinned by CONTRACTS §4. `:pub` because `page.cl.jac` spawns it from a row expansion.
#
# A9: STRICTLY READ-ONLY. `Recall` is the only walker that reinforces, and this one writes nothing
# at all — no `strength`, no `uses`, no `last_used`, no edge weight, no node. Zero `by llm()`.
walker:pub Investigate {
    has concern_kind: str;
    has anchor: str;
    has out: CaseFile = CaseFile();

    can rd_investigate with Root entry {
        known: list[Anchor] = [here -->[?:Anchor]];
        found: list[Anchor] = [];
        for a in known {
            if a.key == self.anchor {
                found.append(a);
            }
        }
        if len(found) == 0 {
            # S3: absence is "not in your record", never "safe". An empty CaseFile with no onset
            # renders as exactly that rather than as an empty reassurance.
            report self.out;
            disengage;
        }
        subject: Anchor = found[0];

        # --- step 1: walk the Observation chain back to first onset ----------------------
        odates: list[str] = rd_observation_dates(subject);
        self.out.onset = odates[0] if len(odates) > 0 else "";

        entries: list[TimelineEntry] = [];
        cites: list[str] = [];

        # --- step 2: compare onset against regimen change dates -------------------------
        # Every drug whose toxicity reaches this anchor, plus the anchor itself when it is a drug.
        # A regimen date near the onset date is the whole point of the case file: the thing that
        # changed the week the symptom started.
        drugs: list[Anchor] = rd_toxicity_contributors(subject);
        if subject.kind in ["ingredient", "food"] {
            drugs.append(subject);
        }
        for d in drugs {
            dsrc: list[Utterance] = rd_regimen_source(d);
            if len(dsrc) == 0 {
                continue;
            }
            entries.append(
                TimelineEntry(at=dsrc[0].at, what=d.key + " started", source=dsrc[0].role)
            );
            if jid(dsrc[0]) not in cites {
                cites.append(jid(dsrc[0]));
            }
        }

        # --- step 3: the counterfactual -------------------------------------------------
        # Days the drug was absent from the record, and whether the symptom was absent too. The
        # honest form of this: a symptom that stops when the drug stops is a different
        # conversation from one that does not, and neither is a conclusion the system draws.
        #
        # Named the drop candidate in #14 if the schedule slipped. It did not.
        gaps: list[list[str]] = [];
        for d in drugs {
            dd: list[str] = rd_observation_dates(d);
            if len(dd) < 2 {
                continue;
            }
            for i in range(1, len(dd)) {
                if rd_days_between(dd[i - 1], dd[i]) > RD_ADHERENCE_DAYS {
                    gaps.append([dd[i - 1], dd[i]]);
                }
            }
        }
        if len(gaps) > 0 {
            quiet: list[str] = [];
            for g in gaps {
                sym_in_gap: list[str] = [];
                for od in odates {
                    if (od > g[0]) and (od < g[1]) {
                        sym_in_gap.append(od);
                    }
                }
                if len(sym_in_gap) == 0 {
                    quiet.append(g[0] + " to " + g[1]);
                }
            }
            if len(quiet) > 0 {
                self.out.counterfactual = (
                    "no record of " + subject.key + " between " + quiet[0]
                    + ", which is also a stretch with no record of the drug"
                );
            }
        }

        # --- step 4: an existing instruction changes what the row says -------------------
        # "Report this" becomes "the instruction you were given covers this". This is the line
        # that stops the page telling a patient to raise something they were already told about.
        for c in rd_touching_constraints(subject) {
            csrc: list[Utterance] = rd_latest_source(c);
            if len(csrc) == 0 {
                continue;
            }
            if self.out.existing_instruction == "" {
                # S8: the clinician's own sentence, verbatim. Not a summary of it.
                self.out.existing_instruction = csrc[0].text;
            }
            entries.append(
                TimelineEntry(at=csrc[0].at, what=c.claim, source=csrc[0].role)
            );
            if jid(csrc[0]) not in cites {
                cites.append(jid(csrc[0]));
            }
        }

        # --- step 5: the dated timeline, every entry carrying a source -------------------
        for o in [subject <-:Reports:<-] {
            osrc: list[Utterance] = rd_latest_source(o);
            # An observation with no citation cannot carry a source, and a timeline entry without
            # one is exactly what S2 forbids. Dropped rather than shown with an empty attribution.
            if len(osrc) == 0 {
                continue;
            }
            entries.append(
                TimelineEntry(
                    at=o.at,
                    what=subject.key + " reported at " + str(o.value),
                    source=osrc[0].role
                )
            );
            if jid(osrc[0]) not in cites {
                cites.append(jid(osrc[0]));
            }
        }

        # Chronological. Sorted on a composed key rather than by `at` alone so two entries on one
        # date come back in a stable order — a case file that reshuffles between two expansions of
        # the same row reads as a bug even when both orders are correct.
        keyed: list[str] = [];
        by_key: dict[str, TimelineEntry] = {};
        for e in entries {
            k: str = e.at + "|" + e.what + "|" + e.source;
            if k not in by_key {
                by_key[k] = e;
                keyed.append(k);
            }
        }
        for k in sorted(keyed) {
            self.out.timeline.append(by_key[k]);
        }
        self.out.citations = cites;
    }

    can rd_case_done with Root exit {
        report self.out;
    }
}
