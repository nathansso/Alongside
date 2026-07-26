# write.jac — the write path: vocabulary, interaction table, regimen parse, seed patient,
# Remember, Consolidate, DEMO_MODE. Owned solely by T1 (Bryan) — CONTRACTS.md §1,
# CONTRIBUTING.md §1.
#
# MERGE DISCIPLINE (CONTRACTS.md §1a — read before adding a helper):
#   - Prefix every private helper `wr_`. Archetypes/walkers keep real names.
#   - Import only from graph.jac. Never from read.jac or main.jac — they don't know this file
#     exists, and it must not know about them.
#   - `root spawn` only, everywhere this file's walkers are called from. No `sv import`, no
#     function RPC.
#
# Both of the project's two `by llm()` sites live in this file (#5, #6). Exactly two exist in
# the whole app; a third requires human approval (ARCHITECTURE.md §2, §8).
#
# Section order mirrors the merge order in CONTRACTS.md §1a: globs -> write walkers.

import re;

# ===== VOCABULARY — Issue #2 =====
#
# A1 is the whole point of this file: the vocabulary decides what exists. Nothing outside
# VOCAB_ANCHORS may create an Anchor; nothing outside VOCAB_MEMBERS may create a Member edge.
#
# Anchor.kind is a closed set: ingredient | class | symptom | lab | phase | food
# (CONTRACTS.md §2). `phase` anchors are computed arithmetically at regimen-parse time (#4),
# not seeded here.
#
# Member.via is closed: class_member | toxicity_of. Direction convention — read.jac's Member
# expansion should traverse both directions, not just forward:
#   class_member : the specific anchor --> the class it belongs to   (ingredient/food -> class)
#   toxicity_of  : the anchor carrying a risk --> the anchor that risk lands on
# The demo chain (ARCHITECTURE.md §3) grapefruit -> CYP3A4-inhibitor -> CYP3A4-substrate ->
# imatinib is therefore NOT one directed path under this convention — it's class_member,
# toxicity_of, then class_member reversed. "Expand Member, collect all" (§4) must read the edge
# as undirected, or this traversal breaks.
#
# Data-only: keys, kinds, and (frm, to, via) triples. Wiring this into real `Anchor(...)` /
# `Member(...)` nodes against graph.jac's now-frozen archetypes is the next task on this file.
#
# Sources: RxNorm (ingredient identity), ATC/EPC (class membership) — ARCHITECTURE.md §16.
# Exact RxCUI/ATC codes are not asserted here since they are unverified against the primary
# source; only the identity/classification claims needed for the demo path are.

glob VOCAB_ANCHORS: list[dict] = [
    # ingredient — RxNorm ingredient identity; brand -> ingredient normalization happens at
    # regimen-parse time (#4), not here.
    {"key": "imatinib",              "kind": "ingredient"},  # oncology: CYP3A4 substrate
    {"key": "ondansetron",           "kind": "ingredient"},  # oncology: antiemetic, QT-prolonging
    {"key": "levofloxacin",          "kind": "ingredient"},  # urgent care: fluoroquinolone, QT-prolonging
    {"key": "naproxen",              "kind": "ingredient"},  # NSAID
    {"key": "ibuprofen",             "kind": "ingredient"},  # NSAID
    {"key": "docusate",              "kind": "ingredient"},  # #7 seed: supportive-care drug with
                                                              # deliberately zero adherence record

    # ingredient — added for #3's curated interaction pairs (recognizable archetypes plus the
    # St John's Wort / CYP3A4-induction demo path)
    {"key": "st_johns_wort", "kind": "ingredient"},  # herbal supplement, CYP3A4 inducer
    {"key": "warfarin",      "kind": "ingredient"},
    {"key": "methotrexate",  "kind": "ingredient"},
    {"key": "tamoxifen",     "kind": "ingredient"},
    {"key": "paroxetine",    "kind": "ingredient"},
    {"key": "azathioprine",  "kind": "ingredient"},
    {"key": "allopurinol",   "kind": "ingredient"},
    {"key": "capecitabine",  "kind": "ingredient"},

    # class — ATC / EPC
    {"key": "CYP3A4-substrate", "kind": "class"},
    {"key": "CYP3A4-inhibitor", "kind": "class"},
    {"key": "CYP3A4-inducer",   "kind": "class"},  # #3: opposite effect from CYP3A4-inhibitor —
                                                    # lowers substrate levels, not an additive-
                                                    # toxicity relationship, so it is NOT wired
                                                    # with Member(toxicity_of) like the inhibitor
                                                    # class. See INTERACTION TABLE below.
    {"key": "QT-prolonging",    "kind": "class"},
    {"key": "NSAID",            "kind": "class"},

    # symptom — CTCAE terms. qt_prolongation and gi_bleed double as toxicity-convergence
    # targets that two independently-prescribed drugs reach via Member(toxicity_of).
    {"key": "qt_prolongation",       "kind": "symptom"},  # CTCAE: ECG QTc interval prolonged
    {"key": "gi_bleed",              "kind": "symptom"},  # CTCAE: gastrointestinal hemorrhage
    {"key": "nausea",                "kind": "symptom"},  # CTCAE: nausea
    {"key": "peripheral_neuropathy", "kind": "symptom"},  # CTCAE: peripheral sensory neuropathy
    {"key": "diarrhea",              "kind": "symptom"},  # CTCAE: diarrhea
    {"key": "fever",                 "kind": "symptom"},  # #4: the canonical "call if fever over
                                                            # 100.4" neutropenic-fever instruction

    # food — small closed set (ARCHITECTURE.md §3)
    {"key": "grapefruit", "kind": "food"},
    {"key": "alcohol",    "kind": "food"},
    {"key": "calcium",    "kind": "food"},
];

glob VOCAB_MEMBERS: list[dict] = [
    # the CYP3A4 chain — the load-bearing demo traversal, ARCHITECTURE.md §3
    {"frm": "grapefruit",       "to": "CYP3A4-inhibitor", "via": "class_member"},
    {"frm": "imatinib",         "to": "CYP3A4-substrate", "via": "class_member"},
    {"frm": "CYP3A4-inhibitor", "to": "CYP3A4-substrate", "via": "toxicity_of"},

    # St John's Wort is a class_member of CYP3A4-inducer like any other vocabulary fact. The
    # inducer -> substrate link itself is a curated Excludes-style pair (INTERACTION TABLE
    # below), not a Member(toxicity_of) edge — induction is an efficacy-loss mechanism, not an
    # additive-toxicity one, so it doesn't belong in this glob.
    {"frm": "st_johns_wort", "to": "CYP3A4-inducer", "via": "class_member"},

    # the QT convergence — two prescribers, one shared toxicity anchor, demo beat 3
    {"frm": "ondansetron",   "to": "QT-prolonging",   "via": "class_member"},
    {"frm": "levofloxacin",  "to": "QT-prolonging",   "via": "class_member"},
    {"frm": "QT-prolonging", "to": "qt_prolongation", "via": "toxicity_of"},

    # NSAID coverage — additive GI-bleed risk, same triangle shape as the QT case
    {"frm": "naproxen",  "to": "NSAID",    "via": "class_member"},
    {"frm": "ibuprofen", "to": "NSAID",    "via": "class_member"},
    {"frm": "NSAID",     "to": "gi_bleed", "via": "toxicity_of"},
];

with entry {
    print("vocab: " + str(len(VOCAB_ANCHORS)) + " anchors, " + str(len(VOCAB_MEMBERS)) + " member edges");
}
# ===== END VOCABULARY =====

# ===== INTERACTION TABLE — Issue #3 =====
#
# NLM retired the RxNav drug-interaction API in early 2024 (ARCHITECTURE.md §16); this is a
# hand-curated table of oncology-relevant pairs sourced from FDA labels, inlined as a `glob`.
# Every pair has a non-empty `source` and a `because` reason string — `because` is what
# `Excludes.because` carries onto the page (S2: no source, no verdict).
#
# **Citations are label-section descriptions, not verified URLs or edition numbers.** The
# underlying interactions are well-documented pharmacology; the exact citation text should still
# be spot-checked against the primary label before anything here is quoted in the pitch
# (ARCHITECTURE.md §16 makes the same demand of the Basch citation).
#
# Data-only, same deferral as VOCABULARY above: this is (a, b, because, source) data only. Each
# pair's `a`/`b` may be a specific ingredient key or a class key — Member(class_member) expansion
# (vocabulary, above) is what lets a class-level pair cover every drug in that class. No
# `Constraint`/`Excludes` construction happens here; that's wired once a patient's regimen (#4,
# #7) actually contains both sides of a pair.
#
# Distinct from Member(toxicity_of) above: that glob encodes additive-toxicity convergence
# (two classes independently raising the same risk). This table encodes explicit, one-off,
# label-documented contraindications and efficacy-loss interactions — including ones that would
# never be additive-toxicity pairs, like CYP3A4 induction lowering a substrate's plasma level.
# Both funnel into Concern.kind="interaction" (CONTRACTS.md §3, mechanism 1, ceiling `ask`).

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
    print("interaction table: " + str(len(INTERACTION_TABLE)) + " pairs");
}
# ===== END INTERACTION TABLE =====

# ===== INGEST — Issue #4 =====
#
# Deterministic regimen and instruction parsing. **No `by llm()` anywhere in this section, per
# A1** — brand -> ingredient is a vocabulary lookup, never a guess, and threshold/timing values
# are parsed, never recalled by a model (ARCHITECTURE.md §8's "seven places that must not have
# one": anchor resolution, threshold evaluation).
#
# These functions return plain dicts, not `Anchor(...)` / `Constraint(...)` / `Governs(...)`.
# Wiring parsed output into real nodes and edges — including the severity-typing rule
# (`Constraint.hard` from `Utterance.role`) — is a follow-up; that rule needs a live `Utterance`,
# which doesn't exist until #5 (`Remember`) writes one.
#
# The emergency flag is *set* here, from parsed text, per #4's acceptance. It is *evaluated* in
# `Recall` (read.jac, Nathan's file, S5) before scoring or drafting anything — this file only
# produces the flag, never acts on it.

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

# Strips dose/frequency/route tokens off a pasted regimen line: "Imatinib 400mg daily" ->
# "Imatinib". Keeps letters, spaces, hyphens, and apostrophes so multi-word names like
# "St John's Wort" survive; stops at the first digit or other token that isn't part of a name.
def wr_strip_dose(raw: str) -> str {
    m: any = re.match(r"^[A-Za-z][A-Za-z\-' ]*", raw.strip());
    if m {
        return str(m.group(0)).strip();
    }
    return raw.strip();
}

# Vocabulary-only lookup (A1): brand alias first, then a direct match against
# VOCAB_ANCHORS' ingredient keys. Returns "" — never a guessed key — on a miss.
def wr_resolve_ingredient(raw: str) -> str {
    name: str = wr_strip_dose(raw).lower();
    if name in BRAND_ALIASES {
        return BRAND_ALIASES[name];
    }
    known: list[str] = [];
    for a in VOCAB_ANCHORS {
        if a["kind"] == "ingredient" {
            known.append(str(a["key"]));
        }
    }
    if name in known {
        return name;
    }
    return "";
}

# Same vocabulary-only discipline for the metric a parsed threshold names — "fever" resolves
# to the seeded symptom anchor; anything not in VOCAB_ANCHORS comes back "" (needs_review at
# wiring time, exactly like an unrecognized ingredient).
def wr_resolve_symptom(metric: str) -> str {
    known: list[str] = [];
    for a in VOCAB_ANCHORS {
        if a["kind"] == "symptom" {
            known.append(str(a["key"]));
        }
    }
    if metric in known {
        return metric;
    }
    return "";
}

# One line per medication in, one classification out. A1: a miss produces no anchor, only a
# needs_review entry carrying the original text.
def wr_parse_regimen(text: str) -> dict {
    anchors: list[dict] = [];
    needs_review: list[str] = [];
    raw_lines: list[str] = text.split("\n");
    lines: list[str] = [];
    for ln in raw_lines {
        stripped: str = ln.strip();
        if stripped != "" {
            lines.append(stripped);
        }
    }
    for line in lines {
        key: str = wr_resolve_ingredient(line);
        if key != "" {
            anchors.append({"key": key, "kind": "ingredient", "raw": line});
        } else {
            needs_review.append(line);
        }
    }
    return {"anchors": anchors, "needs_review": needs_review};
}

# "call if fever over 100.4" -> {metric, anchor_key, operator, threshold, raw}. Returns {} if
# the text doesn't carry a comparable threshold — that's a timing instruction, or unstructured.
def wr_parse_threshold(text: str) -> dict {
    m: any = re.search(
        r"(?i)\b(fever|temperature|pain|nausea)\b.*?\b(?:over|above|greater than|>)\s*([\d.]+)",
        text
    );
    if not m {
        return {};
    }
    metric: str = str(m.group(1)).lower();
    if metric == "temperature" {
        metric = "fever";
    }
    return {
        "metric": metric,
        "anchor_key": wr_resolve_symptom(metric),
        "operator": ">",
        "threshold": float(str(m.group(2))),
        "raw": text,
    };
}

# "within 30 minutes after food" -> {window_minutes, relation, raw}. Returns {} on no match.
def wr_parse_timing(text: str) -> dict {
    m: any = re.search(r"(?i)within\s+(\d+)\s*(minutes?|hours?)\s*(before|after)\s+food", text);
    if not m {
        return {};
    }
    window: int = int(str(m.group(1)));
    unit: str = str(m.group(2)).lower();
    if unit.startswith("hour") {
        window = window * 60;
    }
    return {
        "window_minutes": window,
        "relation": str(m.group(3)).lower() + "_food",
        "raw": text,
    };
}

def wr_contains_emergency_phrase(text: str) -> bool {
    low: str = text.lower();
    for phrase in EMERGENCY_PHRASES {
        if phrase in low {
            return True;
        }
    }
    return False;
}

# Classifies one instruction sentence. `is_emergency` is the flag #4 asks for — set from parsed
# text only, never evaluated here (that's Recall's job, read.jac, S5).
def wr_parse_instruction(text: str) -> dict {
    is_emergency: bool = wr_contains_emergency_phrase(text);

    threshold: dict = wr_parse_threshold(text);
    if threshold {
        threshold["kind"] = "threshold";
        threshold["is_emergency"] = is_emergency;
        return threshold;
    }

    timing: dict = wr_parse_timing(text);
    if timing {
        timing["kind"] = "timing";
        timing["is_emergency"] = is_emergency;
        return timing;
    }

    return {"kind": "unstructured", "raw": text, "is_emergency": is_emergency};
}
# ===== END INGEST =====

# ===== SEED — Issue #7 =====
#
# One synthetic patient, three weeks, hand-built (not extracted live). This is the narrative
# content only — (at, role, text) triples, exactly the `str` shape `Remember` takes as input
# (CONTRACTS.md §4). Turning this into a loaded graph means running each entry through
# `Remember` once #5 exists; `DEMO_MODE` fixtures (#25) key off this exact text and can't be
# written until Remember's real `by llm()` #1 output shape exists to key against.
#
# Four ingredient anchors from two prescriber contexts, both parseable by INGEST above:
# imatinib, ondansetron, docusate (oncologist-instructed) and levofloxacin (patient-reported,
# from an urgent-care visit outside the graph's authority — S1: the graph never originates a
# clinical fact, so this enters as a patient utterance like everything else self-reported).
#
# Required elements, one per entry below:
#   - #1 loop-closure + hard-constraint-eligible instruction (oncologist role, fever threshold)
#   - #2 timing instruction (oncologist role)
#   - #3 a regimen anchor seeded with zero adherence record anywhere else in the corpus
#   - #8 the adversarial case: sinus-infection check-in, names Levaquin (brand -> levofloxacin),
#     zero lexical overlap with "QT"/"heart"/"ondansetron" — the shared qt_prolongation anchor is
#     two Member hops from levofloxacin and two from ondansetron, reachable only by traversal
#   - #6 -> #7 a 4-day observation gap (2026-06-04 -> 2026-06-08) for the `silence` mechanism
#   - #9 a symptom (diarrhea) with no Member(toxicity_of) edge from any active drug in this
#     vocabulary — the `unattributed_symptom` absence-class case
#   - #10 a cost-related nonadherence utterance — distinct from #3's silent absence: this one is
#     an explicit stated cause, for `nonadherence_cause`

glob SEED_CHECKINS: list[dict] = [
    {"at": "2026-06-01", "role": "oncologist",
     "text": "Take Gleevec at the same time every day, and call the clinic immediately if your temperature goes over 100.4."},
    {"at": "2026-06-01", "role": "oncologist",
     "text": "Take Zofran within 30 minutes before food if the nausea is bad."},
    {"at": "2026-06-01", "role": "oncologist",
     "text": "Also take docusate daily for constipation prevention."},
    {"at": "2026-06-02", "role": "patient",
     "text": "Started the new medication today, feeling okay so far."},
    {"at": "2026-06-03", "role": "patient",
     "text": "Some nausea after breakfast, took the Zofran like they said."},
    {"at": "2026-06-04", "role": "patient",
     "text": "Nausea again this morning, not too bad."},
    # -- 4-day observation gap: no entries 2026-06-05 through 2026-06-07 --
    {"at": "2026-06-08", "role": "patient",
     "text": "Feeling okay, no complaints today."},
    {"at": "2026-06-11", "role": "patient",
     "text": "Went to urgent care for a sinus infection and started Levaquin."},
    {"at": "2026-06-13", "role": "patient",
     "text": "Some loose stools the last couple days, not sure why."},
    {"at": "2026-06-15", "role": "patient",
     "text": "Skipped my Gleevec refill this week, it's expensive and I couldn't get to the pharmacy in time."},
    {"at": "2026-06-18", "role": "patient",
     "text": "Still feeling tired but otherwise okay."},
    {"at": "2026-06-21", "role": "patient",
     "text": "Finished the antibiotic course, sinus infection cleared up."},
];

with entry {
    last_idx: int = len(SEED_CHECKINS) - 1;
    print("seed: " + str(len(SEED_CHECKINS)) + " check-ins, " + str(SEED_CHECKINS[0]["at"]) + " to " + str(SEED_CHECKINS[last_idx]["at"]));
}
# ===== END SEED =====

# ===== REMEMBER walker — Issue #5, by llm() site #1 =====
# walker Remember { has text: str; has role: str; has at: str; has out: Verdict = Verdict(); }
# Writes Utterance (always) + Observation (if a symptom value) + extracted beliefs with
# DerivedFrom/About. Severity typing is a provenance read off Utterance.role — never a by llm()
# judgment.
#
# The walker body is blocked by #1 (`Utterance`/`Observation`/`Belief`/`Anchor` +
# `DerivedFrom`/`About` from graph.jac) and #29 (`Verdict` for `has out`). What has no graph
# dependency — the `by llm()` #1 output schema, and the A1 guard that reads it — is below,
# ready for the walker to call the moment #1 lands.
#
# **A1 boundary, made structural by this split:** the LLM's job stops at "what kind of
# statement is this, and what free-text substance/metric did it name." It never decides whether
# that name is real — `wr_check_extraction` re-resolves every name through VOCAB_ANCHORS
# (INGEST, above) exactly like a regimen line. A name the LLM invents or mishears fails the same
# lookup a real one passes; there is no code path where "the model was convincing" creates an
# Anchor.

obj ExtractedObservation {
    has present: bool = False;   # does this check-in report a symptom value at all
    has metric: str = "";        # free text, e.g. "nausea" — not yet vocabulary-checked
    has value: float = 0.0;
}

obj ExtractedBelief {
    has kind: str = "preference";  # "preference" | "constraint" — the LLM's read of statement type
    has claim: str = "";           # normalized natural-language claim text
    has substance: str = "";       # free-text substance name mentioned, "" if none
    has polarity: float = 0.0;     # Preference.polarity; meaningful only when kind == "preference"
}

# `by llm()` #1 returns this. CLAUDE.md gotcha: `by llm()` returns an obj, never a node — the
# walker copies these fields into real Utterance/Observation/Belief nodes once #1 exists.
obj ExtractionResult {
    has observation: ExtractedObservation = ExtractedObservation();
    has beliefs: list[ExtractedBelief] = [];
}

# A1 guard, run once per extracted belief that names a substance. Reuses the same vocabulary
# lookups as INGEST (wr_resolve_ingredient) so "my neighbor gave me St John's Wort" and a pasted
# regimen line resolve identically — one vocabulary, two entry points.
def wr_check_extraction(belief: ExtractedBelief) -> dict {
    if belief.substance == "" {
        return {"needs_review": False, "anchor_key": ""};
    }
    key: str = wr_resolve_ingredient(belief.substance);
    if key != "" {
        return {"needs_review": False, "anchor_key": key};
    }
    # A1: no vocabulary match => no anchor, ever. The walker writes the Belief with
    # needs_review = True and reports Concern(kind="unrecognized_substance") — never "safe"
    # per S3, the page says "not in your record".
    return {"needs_review": True, "anchor_key": ""};
}
# ===== END REMEMBER =====

# ===== CONSOLIDATE walker — Issue #6, by llm() site #2 =====
# walker Consolidate { has budget: int = 6; has out: Verdict = Verdict(); }
# Self-budgeted Conflicts derivation; persistent queue across turns; never deletes a node.
#
# The walker body itself is blocked by #1 (needs `Belief`/`Conflicts` from graph.jac) and #5
# (needs real `Belief` pairs to rank). The self-budgeting *algorithm* — "plans its own work",
# the strongest autonomy story in the system (ARCHITECTURE.md §4) — has no graph dependency and
# is split out here so it's ready to call once the walker can supply real candidate pairs.
#
# Rank: shared Anchor > reinforced this turn > cold (ARCHITECTURE.md §4). A pair carrying a
# `last_examined` marker is skipped entirely — that's what makes next turn examine a different
# slice instead of the same `budget` pairs every time.
#
# **Schema note (2026-07-26):** graph.jac's frozen schema resolved this with
# `edge Examined: Belief --> Belief { has at: str; has conflicting: bool = False; }`. This
# function doesn't need to know that — it only reads `pair["last_examined"]` off whatever dict
# the walker builds from that edge.

# `by llm()` #2 returns this — joint satisfiability of two natural-language constraints.
obj SatisfiabilityResult {
    has jointly_satisfiable: bool = True;  # False => the pair conflicts, walker writes Conflicts
    has because: str = "";                 # reason string; empty only when jointly_satisfiable
}

# `pairs`: candidate Belief-pair descriptors — {"id": str, "shared_anchor": bool,
# "reinforced_this_turn": bool, "last_examined": str | None}. The walker builds this list from
# the graph; this function only ranks and slices it. Explicit tiered passes (not sorted+key) so
# the ranking logic stays a plain, easy-to-audit loop.
def wr_rank_conflict_candidates(pairs: list[dict], budget: int) -> dict {
    eligible: list[dict] = [];
    for p in pairs {
        marked: bool = False;
        if "last_examined" in p {
            if p["last_examined"] {
                marked = True;
            }
        }
        if not marked {
            eligible.append(p);
        }
    }

    tier0: list[dict] = [];
    tier1: list[dict] = [];
    tier2: list[dict] = [];
    for p in eligible {
        shared: bool = False;
        if "shared_anchor" in p {
            shared = p["shared_anchor"];
        }
        reinforced: bool = False;
        if "reinforced_this_turn" in p {
            reinforced = p["reinforced_this_turn"];
        }
        if shared {
            tier0.append(p);
        } elif reinforced {
            tier1.append(p);
        } else {
            tier2.append(p);
        }
    }

    ranked: list[dict] = [];
    for p in tier0 { ranked.append(p); }
    for p in tier1 { ranked.append(p); }
    for p in tier2 { ranked.append(p); }

    examine: list[dict] = [];
    queue: list[dict] = [];
    i: int = 0;
    for p in ranked {
        if i < budget {
            examine.append(p);
        } else {
            queue.append(p);
        }
        i = i + 1;
    }

    return {
        "examine": examine,
        "queue": queue,
        "examined_count": len(examine),
        "queued_count": len(queue),
    };
}
# ===== END CONSOLIDATE =====

# ===== DEMO_MODE — Issue #25, not started. Blocked by #7. =====
# Both by llm() sites (REMEMBER, CONSOLIDATE) branch on it and return fixtures keyed to exact
# Utterance.text. Fixtures live in the SEED section above.
#
# Per Nathan's #27 findings: read `os.getenv("DEMO_MODE")` INSIDE each walker's ability, never
# as a module-level glob — globs evaluate once at boot in jachammer and won't see a later change
# (and no live model access exists yet regardless, so DEMO_MODE is the only path that runs).
# ===== END DEMO_MODE =====
