# graph.jac — the graph schema. Owner: T3 Laksh. graph.jac imports from nothing.
#
# Three sections (CONTRACTS.md §1): node archetypes, edge archetypes, transient report objs.
#
#   #1  — node + edge archetypes (below). PERSISTED and FROZEN on merge. Editing a persisted
#         archetype corrupts every existing graph; the reset path (#30) is `jac clean --force`,
#         or delete `.jac/data/<project>.db`, or the in-app reset walker. After this merges,
#         everyone resets their graph.
#   #29 — report objs (bottom). TRANSIENT, never persisted, need no reset. `contract`-governed.
#
# The archetypes below reconcile ARCHITECTURE.md §3 / CONTRACTS.md §2 with Nathan's pre-freeze
# schema review (issue #1) and Bryan's answers, plus two compile fixes found by building the
# pinned shapes on Jac 0.34.5. Every deviation from the previously-pinned text is tagged inline.

# ─── Node archetypes — three layers ─────────────────────────────────────────────────
# Provenance floor (never scored/occluded/decayed): Utterance, Observation
# Ground truth (deterministic, never inferred):       Anchor
# Scored layer (the only decayed/occluded layer):     Belief, Preference, Constraint
# Raised is a persisted status marker, joined on render (not scored).

node Utterance {
    has text: str;
    has at: str;                             # ISO 8601 YYYY-MM-DD
    has role: str;                           # closed set: patient|caregiver|oncologist|pharmacist|label
}

node Anchor {
    has key: str;
    has kind: str;                           # closed set: ingredient|class|symptom|lab|phase|food
    has cumulative: bool = False;            # [+#1 review §3] label-marked cumulative toxicity — trajectory (#12)
    has cycle_days: int = 0;                 # [+#1 review §6] regimen cycle length — phase (#21). Bryan: distinct from threshold_days
}

node Observation {
    has metric: str;
    has value: float;
    has at: str;
    has scale: str = "patient_selfreport";   # [+#1 review §7] closed set: patient_selfreport|ctcae_grade
}

node Belief {
    has claim: str;
    has strength: float = 1.0;
    has last_used: str = "";                 # [fix E2004] pinned shape had no default here, but a required
                                             # field cannot follow a defaulted one; "" is semantically fine.
    has uses: int = 0;
    has needs_review: bool = False;          # A1 guard: a vocabulary miss sets this and creates no anchor.
}

node Preference(Belief) {
    has polarity: float = 0.0;               # -1 avoid .. +1 prefer
}

node Constraint(Belief) {
    has hard: bool = True;                   # hard==True only if DerivedFrom Utterance.role in {oncologist,pharmacist,label}
    has emergency: bool = False;             # [+#1 review §1] S5/#9 — parsed by #4, never inferred
    has threshold_level: float = 0.0;        # [+#1 review §2] L — persistence (#12)
    has threshold_days: int = 0;             # [+#1 review §2] D — days at/above L
    has threshold_metric: str = "";          # [+#1 review §2] which Observation.metric L applies to
}

node Raised {
    has kind: str;
    has anchor_key: str;                     # denormalized convenience for the PRIMARY anchor only — see Regarding
    has status: str;                         # closed set: open|asked|answered|dismissed
    has at: str;
}

# ─── Edge archetypes — endpoints declared on every one ──────────────────────────────
#
# ACTIVE REGIMEN (#1 review §5, confirmed by Bryan — load-bearing for #10/#11/#14/#21, and
# easy to silently drift from): an Anchor is *active regimen* iff reachable by [here <-:About:<-]
# from a regimen Belief that has NO incoming Supersedes. regimen date = that Utterance.at;
# prescriber = that Utterance.role; discontinuation = Supersedes. Resolved by traversal, no field.

edge DerivedFrom: Node --> Utterance {}   # [fix Q1] source broadened Belief->Node: BOTH Belief AND
                                          # Observation carry DerivedFrom to their Utterance (§3, S2).
                                          # A Belief-typed source mistypes Observation sources and fails
                                          # on any reverse read (passes `jac check`, dies later).
edge Reports:     Observation --> Anchor {}
edge About:       Belief --> Anchor { has weight: float = 1.0; }
edge Relates:     Belief --> Belief { has weight: float = 1.0; has co_uses: int = 0;
                                      has last_used: str = ""; }   # [fix E2004] defaulted, same reason as Belief.last_used
edge Supersedes:  Belief --> Belief {}
edge Shortcut:    Anchor --> Belief { has hops: int = 2; has weight: float = 1.0; }
edge Governs:     Constraint --> Anchor {}
edge Excludes:    Constraint --> Anchor { has because: str; }
edge Conflicts:   Belief --> Belief { has derived_at: str; }
edge Examined:    Belief --> Belief { has at: str;
                                      has conflicting: bool = False; }   # [+#1 review §4] Consolidate skip-marker (#6), per-pair
edge Member:      Anchor --> Anchor { has via: str; }   # closed set: class_member|toxicity_of

# S9: Regarding is the AUTHORITATIVE multi-anchor carrier. One Raised fans out to every anchor in
# the concern (e.g. the additive_toxicity triangle: 2 ingredient + 1 symptom). anchor_key above is
# NOT authoritative — implementing S9's "resurface if the anchor set changes" by comparing anchor_key
# alone makes dismissal permanent for every triangle, which is exactly the S9 failure mode.
edge Regarding:   Raised --> Anchor {}

# ─── Report objects — CONTRACTS.md §3 (Verdict path) ────────────────────────────────
# Transient, not frozen. Fields the contract leaves without a default stay REQUIRED at
# construction: a Violation with no `source`/`at` must be unconstructable, making S2
# ("no source, no verdict") structural rather than a runtime check.

obj Violation {
    has claim: str;
    has because: str;
    has source: str;
    has at: str;
}

obj Concern {
    has kind: str;
    has anchor: str;
    has evidence: list[str];
    has since: str;
    has action: str;
}

obj Verdict {
    has allowed: bool = True;
    has violations: list[Violation] = [];
    has soft: list[str] = [];
    has conflicts: list[str] = [];
    has concerns: list[Concern] = [];
}

# ─── Report objects — CONTRACTS.md §4 (Investigate + Prepare paths) ──────────────────

obj TimelineEntry {
    has at: str;
    has what: str;
    has source: str;
}

obj CaseFile {
    # `onset` defaulted to "" — CONTRACTS.md §4 pins the Investigate report channel as
    # `has out: CaseFile = CaseFile();`, which constructs CaseFile() arg-free. Without a
    # default here that spawn dies E1050 at runtime (passes `jac check`, fails on spawn).
    # "" matches the sibling string fields and touches no safety invariant. This diverges
    # from the literal §4 text (onset shown with no default) — flagged for a `contract`
    # reconciliation of §4; harmless because CaseFile is transient (an ack, not a reset).
    has onset: str = "";
    has timeline: list[TimelineEntry] = [];
    has counterfactual: str = "";
    has existing_instruction: str = "";
    has citations: list[str] = [];
}

obj Citation {
    has text: str;
    has role: str;
    has at: str;
}

obj Row {
    has id: str;
    has kind: str;
    has question: str;
    has why: str;
    has noticed: list[str] = [];
    has citations: list[Citation] = [];
    has status: str = "open";
}

obj PageModel {
    has escalate: list[Row] = [];
    has ask: list[Row] = [];
    has mention: list[Row] = [];
    has log: list[Row] = [];
    has activity: list[str] = [];
}
