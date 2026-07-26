// write.jac — the write path: vocabulary, interaction table, regimen parse, seed patient,
// Remember, Consolidate, DEMO_MODE. Owned solely by T1 (Bryan) — CONTRACTS.md §1,
// CONTRIBUTING.md §1.
//
// MERGE DISCIPLINE (CONTRACTS.md §1a — read before adding a helper):
//   - Prefix every private helper `wr_`. Archetypes/walkers keep real names.
//   - Import only from graph.jac. Never from read.jac or main.jac — they don't know this file
//     exists, and it must not know about them.
//   - `root spawn` only, everywhere this file's walkers are called from. No `sv import`, no
//     function RPC.
//
// Both of the project's two `by llm()` sites live in this file (#5, #6). Exactly two exist in
// the whole app; a third requires human approval (ARCHITECTURE.md §2, §8).
//
// Section order mirrors the merge order in CONTRACTS.md §1a: globs -> write walkers.

// ===== VOCABULARY — Issue #2 =====
//
// A1 is the whole point of this file: the vocabulary decides what exists. Nothing outside
// VOCAB_ANCHORS may create an Anchor; nothing outside VOCAB_MEMBERS may create a Member edge.
//
// Anchor.kind is a closed set: ingredient | class | symptom | lab | phase | food
// (CONTRACTS.md §2). `phase` anchors are computed arithmetically at regimen-parse time (#4),
// not seeded here.
//
// Member.via is closed: class_member | toxicity_of. Direction convention — read.jac's Member
// expansion should traverse both directions, not just forward:
//   class_member : the specific anchor --> the class it belongs to   (ingredient/food -> class)
//   toxicity_of  : the anchor carrying a risk --> the anchor that risk lands on
// The demo chain (ARCHITECTURE.md §3) grapefruit -> CYP3A4-inhibitor -> CYP3A4-substrate ->
// imatinib is therefore NOT one directed path under this convention — it's class_member,
// toxicity_of, then class_member reversed. "Expand Member, collect all" (§4) must read the edge
// as undirected, or this traversal breaks.
//
// #1 (graph.jac, node/edge archetypes) is still blocked on #30 and does not exist yet. This
// section is deliberately data-only: keys, kinds, and (frm, to, via) triples — no `Anchor(...)`
// / `Member(...)` construction and no `import from graph.jac`. Wiring this data into real nodes
// is a follow-up once graph.jac lands and freezes (CONTRACTS.md §7, stub-first rule).
//
// Sources: RxNorm (ingredient identity), ATC/EPC (class membership) — ARCHITECTURE.md §16.
// Exact RxCUI/ATC codes are not asserted here since they are unverified against the primary
// source; only the identity/classification claims needed for the demo path are.

glob VOCAB_ANCHORS: list[dict] = [
    // ingredient — RxNorm ingredient identity; brand -> ingredient normalization happens at
    // regimen-parse time (#4), not here.
    {"key": "imatinib",              "kind": "ingredient"},  // oncology: CYP3A4 substrate
    {"key": "ondansetron",           "kind": "ingredient"},  // oncology: antiemetic, QT-prolonging
    {"key": "levofloxacin",          "kind": "ingredient"},  // urgent care: fluoroquinolone, QT-prolonging
    {"key": "naproxen",              "kind": "ingredient"},  // NSAID
    {"key": "ibuprofen",             "kind": "ingredient"},  // NSAID

    // class — ATC / EPC
    {"key": "CYP3A4-substrate", "kind": "class"},
    {"key": "CYP3A4-inhibitor", "kind": "class"},
    {"key": "QT-prolonging",    "kind": "class"},
    {"key": "NSAID",            "kind": "class"},

    // symptom — CTCAE terms. qt_prolongation and gi_bleed double as toxicity-convergence
    // targets that two independently-prescribed drugs reach via Member(toxicity_of).
    {"key": "qt_prolongation",       "kind": "symptom"},  // CTCAE: ECG QTc interval prolonged
    {"key": "gi_bleed",              "kind": "symptom"},  // CTCAE: gastrointestinal hemorrhage
    {"key": "nausea",                "kind": "symptom"},  // CTCAE: nausea
    {"key": "peripheral_neuropathy", "kind": "symptom"},  // CTCAE: peripheral sensory neuropathy
    {"key": "diarrhea",              "kind": "symptom"},  // CTCAE: diarrhea

    // food — small closed set (ARCHITECTURE.md §3)
    {"key": "grapefruit", "kind": "food"},
    {"key": "alcohol",    "kind": "food"},
    {"key": "calcium",    "kind": "food"},
];

glob VOCAB_MEMBERS: list[dict] = [
    // the CYP3A4 chain — the load-bearing demo traversal, ARCHITECTURE.md §3
    {"frm": "grapefruit",       "to": "CYP3A4-inhibitor", "via": "class_member"},
    {"frm": "imatinib",         "to": "CYP3A4-substrate", "via": "class_member"},
    {"frm": "CYP3A4-inhibitor", "to": "CYP3A4-substrate", "via": "toxicity_of"},

    // the QT convergence — two prescribers, one shared toxicity anchor, demo beat 3
    {"frm": "ondansetron",   "to": "QT-prolonging",   "via": "class_member"},
    {"frm": "levofloxacin",  "to": "QT-prolonging",   "via": "class_member"},
    {"frm": "QT-prolonging", "to": "qt_prolongation", "via": "toxicity_of"},

    // NSAID coverage — additive GI-bleed risk, same triangle shape as the QT case
    {"frm": "naproxen",  "to": "NSAID",    "via": "class_member"},
    {"frm": "ibuprofen", "to": "NSAID",    "via": "class_member"},
    {"frm": "NSAID",     "to": "gi_bleed", "via": "toxicity_of"},
];

with entry {
    print(f"vocab: {len(VOCAB_ANCHORS)} anchors, {len(VOCAB_MEMBERS)} member edges");
}
// ===== END VOCABULARY =====

// ===== INTERACTION TABLE — Issue #3, not started. Blocked by #1. =====
// Curated Excludes pairs. Cite a source per pair; state the pair count (ARCHITECTURE.md §16).
// ===== END INTERACTION TABLE =====

// ===== INGEST — Issue #4, not started. Blocked by #1, #2. =====
// Deterministic regimen parse: pasted med list -> ingredient anchors. Zero anchors created
// outside VOCAB_ANCHORS (A1): a miss writes needs_review = True and creates no anchor.
// ===== END INGEST =====

// ===== SEED — Issue #7, not started. Blocked by #1, #2, #4. =====
// 3 weeks of check-ins, 4-6 ingredient anchors from two prescribers, the adversarial QT
// convergence (sinus-infection check-in, shared symptom anchor two Member hops out, no lexical
// overlap between input text and the constraint it corroborates).
// ===== END SEED =====

// ===== REMEMBER walker — Issue #5, by llm() site #1. Not started. Blocked by #1, #2. =====
// walker Remember { has text: str; has role: str; has at: str; has out: Verdict = Verdict(); }
// Writes Utterance (always) + Observation (if a symptom value) + extracted beliefs with
// DerivedFrom/About. Severity typing is a provenance read off Utterance.role — never an
// by llm() judgment.
// ===== END REMEMBER =====

// ===== CONSOLIDATE walker — Issue #6, by llm() site #2. Not started. Blocked by #1, #5. =====
// walker Consolidate { has budget: int = 6; has out: Verdict = Verdict(); }
// Self-budgeted Conflicts derivation; persistent queue across turns; never deletes a node.
// ===== END CONSOLIDATE =====

// ===== DEMO_MODE — Issue #25, not started. Blocked by #7. =====
// Both by llm() sites (REMEMBER, CONSOLIDATE) branch on it and return fixtures keyed to exact
// Utterance.text. Fixtures live in the SEED section above.
// ===== END DEMO_MODE =====
