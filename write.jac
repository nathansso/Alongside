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

import re;

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

    // ingredient — added for #3's curated interaction pairs (recognizable archetypes plus the
    // St John's Wort / CYP3A4-induction demo path)
    {"key": "st_johns_wort", "kind": "ingredient"},  // herbal supplement, CYP3A4 inducer
    {"key": "warfarin",      "kind": "ingredient"},
    {"key": "methotrexate",  "kind": "ingredient"},
    {"key": "tamoxifen",     "kind": "ingredient"},
    {"key": "paroxetine",    "kind": "ingredient"},
    {"key": "azathioprine",  "kind": "ingredient"},
    {"key": "allopurinol",   "kind": "ingredient"},
    {"key": "capecitabine",  "kind": "ingredient"},

    // class — ATC / EPC
    {"key": "CYP3A4-substrate", "kind": "class"},
    {"key": "CYP3A4-inhibitor", "kind": "class"},
    {"key": "CYP3A4-inducer",   "kind": "class"},  // #3: opposite effect from CYP3A4-inhibitor —
                                                    // lowers substrate levels, not an additive-
                                                    // toxicity relationship, so it is NOT wired
                                                    // with Member(toxicity_of) like the inhibitor
                                                    // class. See INTERACTION TABLE below.
    {"key": "QT-prolonging",    "kind": "class"},
    {"key": "NSAID",            "kind": "class"},

    // symptom — CTCAE terms. qt_prolongation and gi_bleed double as toxicity-convergence
    // targets that two independently-prescribed drugs reach via Member(toxicity_of).
    {"key": "qt_prolongation",       "kind": "symptom"},  // CTCAE: ECG QTc interval prolonged
    {"key": "gi_bleed",              "kind": "symptom"},  // CTCAE: gastrointestinal hemorrhage
    {"key": "nausea",                "kind": "symptom"},  // CTCAE: nausea
    {"key": "peripheral_neuropathy", "kind": "symptom"},  // CTCAE: peripheral sensory neuropathy
    {"key": "diarrhea",              "kind": "symptom"},  // CTCAE: diarrhea
    {"key": "fever",                 "kind": "symptom"},  // #4: the canonical "call if fever over
                                                            // 100.4" neutropenic-fever instruction

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

    // St John's Wort is a class_member of CYP3A4-inducer like any other vocabulary fact. The
    // inducer -> substrate link itself is a curated Excludes-style pair (INTERACTION TABLE
    // below), not a Member(toxicity_of) edge — induction is an efficacy-loss mechanism, not an
    // additive-toxicity one, so it doesn't belong in this glob.
    {"frm": "st_johns_wort", "to": "CYP3A4-inducer", "via": "class_member"},

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

// ===== INTERACTION TABLE — Issue #3 =====
//
// NLM retired the RxNav drug-interaction API in early 2024 (ARCHITECTURE.md §16); this is a
// hand-curated table of oncology-relevant pairs sourced from FDA labels, inlined as a `glob`.
// Every pair has a non-empty `source` and a `because` reason string — `because` is what
// `Excludes.because` carries onto the page (S2: no source, no verdict).
//
// **Citations are label-section descriptions, not verified URLs or edition numbers.** The
// underlying interactions are well-documented pharmacology; the exact citation text should still
// be spot-checked against the primary label before anything here is quoted in the pitch
// (ARCHITECTURE.md §16 makes the same demand of the Basch citation).
//
// Same stub-first deferral as VOCABULARY above: this is (a, b, because, source) data only. Each
// pair's `a`/`b` may be a specific ingredient key or a class key — Member(class_member) expansion
// (vocabulary, above) is what lets a class-level pair cover every drug in that class. No
// `Constraint`/`Excludes` construction happens here; that's wired once a patient's regimen (#4,
// #7) actually contains both sides of a pair.
//
// Distinct from Member(toxicity_of) above: that glob encodes additive-toxicity convergence
// (two classes independently raising the same risk). This table encodes explicit, one-off,
// label-documented contraindications and efficacy-loss interactions — including ones that would
// never be additive-toxicity pairs, like CYP3A4 induction lowering a substrate's plasma level.
// Both funnel into Concern.kind="interaction" (CONTRACTS.md §3, mechanism 1, ceiling `ask`).

glob INTERACTION_TABLE: list[dict] = [
    {
        "a": "CYP3A4-inducer", "b": "CYP3A4-substrate",
        "because": "CYP3A4 induction lowers substrate plasma levels, risking loss of efficacy",
        "source": "Gleevec (imatinib) FDA label, Drug Interactions — CYP3A4 inducers",
    },
    {
        "a": "warfarin", "b": "naproxen",
        "because": "additive bleeding risk: NSAIDs impair platelet function on top of anticoagulation",
        "source": "Warfarin (Coumadin) FDA label, Drug Interactions — NSAIDs",
    },
    {
        "a": "warfarin", "b": "ibuprofen",
        "because": "additive bleeding risk: NSAIDs impair platelet function on top of anticoagulation",
        "source": "Warfarin (Coumadin) FDA label, Drug Interactions — NSAIDs",
    },
    {
        "a": "warfarin", "b": "levofloxacin",
        "because": "fluoroquinolones can potentiate warfarin's anticoagulant effect, raising INR",
        "source": "Levofloxacin FDA label, Drug Interactions — Warfarin",
    },
    {
        "a": "methotrexate", "b": "naproxen",
        "because": "NSAIDs reduce renal methotrexate clearance, raising toxicity risk",
        "source": "Methotrexate FDA label, Drug Interactions — NSAIDs",
    },
    {
        "a": "methotrexate", "b": "ibuprofen",
        "because": "NSAIDs reduce renal methotrexate clearance, raising toxicity risk",
        "source": "Methotrexate FDA label, Drug Interactions — NSAIDs",
    },
    {
        "a": "methotrexate", "b": "alcohol",
        "because": "alcohol increases risk of methotrexate-associated hepatotoxicity",
        "source": "Methotrexate FDA label, Warnings and Precautions — Hepatotoxicity",
    },
    {
        "a": "tamoxifen", "b": "paroxetine",
        "because": "potent CYP2D6 inhibition blocks conversion to endoxifen, tamoxifen's active metabolite, reducing efficacy",
        "source": "Tamoxifen FDA label, Drug Interactions — CYP2D6 inhibitors",
    },
    {
        "a": "tamoxifen", "b": "warfarin",
        "because": "tamoxifen potentiates warfarin's anticoagulant effect, raising bleeding risk",
        "source": "Tamoxifen FDA label, Drug Interactions — Coumarin anticoagulants",
    },
    {
        "a": "azathioprine", "b": "allopurinol",
        "because": "allopurinol blocks the enzyme that clears azathioprine's active metabolite, causing severe myelosuppression",
        "source": "Azathioprine (Imuran) FDA label, Drug Interactions — Allopurinol",
    },
    {
        "a": "capecitabine", "b": "warfarin",
        "because": "capecitabine potentiates warfarin, raising INR and bleeding risk, sometimes with delayed onset",
        "source": "Capecitabine (Xeloda) FDA label, Drug Interactions — Coumarin anticoagulants",
    },
    {
        "a": "imatinib", "b": "warfarin",
        "because": "imatinib may potentiate warfarin; low-molecular-weight heparin is often used instead",
        "source": "Gleevec (imatinib) FDA label, Drug Interactions — Warfarin",
    },
    {
        "a": "levofloxacin", "b": "calcium",
        "because": "divalent cations chelate fluoroquinolones in the gut, reducing absorption and efficacy — separate dosing by several hours",
        "source": "Levofloxacin FDA label, Drug Interactions — Multivalent cation-containing products",
    },
];

with entry {
    print(f"interaction table: {len(INTERACTION_TABLE)} pairs");
}
// ===== END INTERACTION TABLE =====

// ===== INGEST — Issue #4 =====
//
// Deterministic regimen and instruction parsing. **No `by llm()` anywhere in this section, per
// A1** — brand -> ingredient is a vocabulary lookup, never a guess, and threshold/timing values
// are parsed, never recalled by a model (ARCHITECTURE.md §8's "seven places that must not have
// one": anchor resolution, threshold evaluation).
//
// Same stub-first deferral as VOCABULARY/INTERACTION TABLE: these functions return plain dicts,
// not `Anchor(...)` / `Constraint(...)` / `Governs(...)`. Wiring parsed output into real nodes
// and edges — including the severity-typing rule (`Constraint.hard` from `Utterance.role`) — is
// a follow-up once graph.jac (#1) lands; that rule needs a live `Utterance`, which doesn't exist
// until #5 (`Remember`) writes one.
//
// The emergency flag is *set* here, from parsed text, per #4's acceptance. It is *evaluated* in
// `Recall` (read.jac, Nathan's file, S5) before scoring or drafting anything — this file only
// produces the flag, never acts on it.

glob BRAND_ALIASES: dict[str, str] = {
    "gleevec": "imatinib",
    "zofran": "ondansetron",
    "levaquin": "levofloxacin",
    "aleve": "naproxen",
    "advil": "ibuprofen",
    "motrin": "ibuprofen",
    "coumadin": "warfarin",
    "jantoven": "warfarin",
    "rheumatrex": "methotrexate",
    "trexall": "methotrexate",
    "nolvadex": "tamoxifen",
    "paxil": "paroxetine",
    "imuran": "azathioprine",
    "azasan": "azathioprine",
    "zyloprim": "allopurinol",
    "xeloda": "capecitabine",
    "st john's wort": "st_johns_wort",
    "st johns wort": "st_johns_wort",
};

glob EMERGENCY_PHRASES: list[str] = [
    "call 911", "call 999", "call 112", "go to the emergency room", "go to the er",
    "seek emergency care", "call your doctor immediately",
];

// Strips dose/frequency/route tokens off a pasted regimen line: "Imatinib 400mg daily" ->
// "Imatinib". Keeps letters, spaces, hyphens, and apostrophes so multi-word names like
// "St John's Wort" survive; stops at the first digit or other token that isn't part of a name.
def:pub wr_strip_dose(raw: str) -> str {
    m = re.match(r"^[A-Za-z][A-Za-z\-' ]*", raw.strip());
    if m {
        return m.group(0).strip();
    }
    return raw.strip();
}

// Vocabulary-only lookup (A1): brand alias first, then a direct match against
// VOCAB_ANCHORS' ingredient keys. Returns "" — never a guessed key — on a miss.
def:pub wr_resolve_ingredient(raw: str) -> str {
    name = wr_strip_dose(raw).lower();
    if name in BRAND_ALIASES {
        return BRAND_ALIASES[name];
    }
    known: list[str] = [a["key"] for a in VOCAB_ANCHORS if a["kind"] == "ingredient"];
    if name in known {
        return name;
    }
    return "";
}

// Same vocabulary-only discipline for the metric a parsed threshold names — "fever" resolves
// to the seeded symptom anchor; anything not in VOCAB_ANCHORS comes back "" (needs_review at
// wiring time, exactly like an unrecognized ingredient).
def:pub wr_resolve_symptom(metric: str) -> str {
    known: list[str] = [a["key"] for a in VOCAB_ANCHORS if a["kind"] == "symptom"];
    if metric in known {
        return metric;
    }
    return "";
}

// One line per medication in, one classification out. A1: a miss produces no anchor, only a
// needs_review entry carrying the original text.
def:pub wr_parse_regimen(text: str) -> dict {
    anchors: list[dict] = [];
    needs_review: list[str] = [];
    lines: list[str] = [ln.strip() for ln in text.split("\n") if ln.strip() != ""];
    for line in lines {
        key = wr_resolve_ingredient(line);
        if key != "" {
            anchors.append({"key": key, "kind": "ingredient", "raw": line});
        } else {
            needs_review.append(line);
        }
    }
    return {"anchors": anchors, "needs_review": needs_review};
}

// "call if fever over 100.4" -> {metric, anchor_key, operator, threshold, raw}. Returns {} if
// the text doesn't carry a comparable threshold — that's a timing instruction, or unstructured.
def:pub wr_parse_threshold(text: str) -> dict {
    m = re.search(
        r"(?i)\b(fever|temperature|pain|nausea)\b.*?\b(?:over|above|greater than|>)\s*([\d.]+)",
        text
    );
    if not m {
        return {};
    }
    metric = m.group(1).lower();
    if metric == "temperature" {
        metric = "fever";
    }
    return {
        "metric": metric,
        "anchor_key": wr_resolve_symptom(metric),
        "operator": ">",
        "threshold": float(m.group(2)),
        "raw": text,
    };
}

// "within 30 minutes after food" -> {window_minutes, relation, raw}. Returns {} on no match.
def:pub wr_parse_timing(text: str) -> dict {
    m = re.search(r"(?i)within\s+(\d+)\s*(minutes?|hours?)\s*(before|after)\s+food", text);
    if not m {
        return {};
    }
    window = int(m.group(1));
    if m.group(2).lower().startswith("hour") {
        window = window * 60;
    }
    return {
        "window_minutes": window,
        "relation": m.group(3).lower() + "_food",
        "raw": text,
    };
}

def:pub wr_contains_emergency_phrase(text: str) -> bool {
    low = text.lower();
    for phrase in EMERGENCY_PHRASES {
        if phrase in low {
            return True;
        }
    }
    return False;
}

// Classifies one instruction sentence. `is_emergency` is the flag #4 asks for — set from parsed
// text only, never evaluated here (that's Recall's job, read.jac, S5).
def:pub wr_parse_instruction(text: str) -> dict {
    is_emergency = wr_contains_emergency_phrase(text);

    threshold = wr_parse_threshold(text);
    if threshold {
        threshold["kind"] = "threshold";
        threshold["is_emergency"] = is_emergency;
        return threshold;
    }

    timing = wr_parse_timing(text);
    if timing {
        timing["kind"] = "timing";
        timing["is_emergency"] = is_emergency;
        return timing;
    }

    return {"kind": "unstructured", "raw": text, "is_emergency": is_emergency};
}
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
