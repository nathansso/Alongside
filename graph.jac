# graph.jac — the graph schema. Owner: T3 Laksh. graph.jac imports from nothing.
#
# This file holds three things (CONTRACTS.md §1): node archetypes, edge archetypes,
# and the transient report objs. Two of the three are landed in separate issues:
#
#   #1  — node + edge archetypes. PERSISTED and FROZEN after merge (CONTRACTS.md §1,
#         "The freeze covers persisted archetypes only"). BLOCKED: #1 cannot start
#         until #30 records and performs the graph-reset path (there is no shell on
#         jachammer, and editing a persisted archetype corrupts every existing graph).
#         See ARCHITECTURE.md §9 "Still unresolved" and the CLAUDE.md gotcha.
#
#   #29 — report objs (this file, below). TRANSIENT values constructed per walker run;
#         they never persist, corrupt nothing, and need no reset — so #29 is explicitly
#         unblocked and does not wait on the freeze (CONTRIBUTING.md §1a). Not frozen,
#         but contract-governed: changing one needs the `contract` label + an ack, and
#         Laksh applies it (CONTRACTS.md §1).
#
# Shapes below are pinned in CONTRACTS.md §3 and §4 and reproduced verbatim. Fields the
# contract leaves without a default stay REQUIRED at construction — that is deliberate:
# Violation with no `source`/`at` must be unconstructable, which is what makes S2
# ("no source, no verdict") structural rather than a runtime check.

# ─── Report objects — CONTRACTS.md §3 (Verdict path) ────────────────────────────────

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
