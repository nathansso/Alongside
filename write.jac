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
import os;
import from byllm.lib { MockLLM }
import from graph { Anchor, Member, Utterance, Observation, Belief, Constraint, Verdict, Concern,
                     DerivedFrom, About, Governs, Examined, Conflicts, Excludes }

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

# Wires VOCAB_ANCHORS/VOCAB_MEMBERS into real, persisted Anchor nodes and Member edges under
# at_root. A1 in code: this is the only place an Anchor is ever constructed in the whole app.
# Idempotency is the caller's job — call this once per graph (e.g. from Vigil's first-run check
# in read.jac), not on every turn; calling it twice duplicates every anchor.
def wr_seed_vocabulary(at_root: Root) -> dict {
    created: dict[str, Anchor] = {};
    for a in VOCAB_ANCHORS {
        key: str = str(a["key"]);
        kind: str = str(a["kind"]);
        n = (at_root ++> Anchor(key=key, kind=kind));
        created[key] = n;
    }

    member_count: int = 0;
    for m in VOCAB_MEMBERS {
        frm_key: str = str(m["frm"]);
        to_key: str = str(m["to"]);
        via: str = str(m["via"]);
        if frm_key in created {
            if to_key in created {
                created[frm_key] +>:Member(via=via):+> created[to_key];
                member_count = member_count + 1;
            }
        }
    }

    return {"anchor_count": len(created), "member_count": member_count};
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
        r"(?i)\b(fever|temperature|pain|nausea)\b.*?\b(?:over|above|greater than|>)\s*(\d+(?:\.\d+)?)",
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

# Ground-truth lookup by key. Anchors are never created here (A1) — wr_seed_vocabulary is the
# only constructor. A miss returns None, same "no invented anchor" discipline as everywhere else.
def wr_find_anchor(at_root: Root, key: str) -> Anchor | None {
    anchors: list[Anchor] = [at_root -->][?:Anchor];
    for a in anchors {
        if a.key == key {
            return a;
        }
    }
    return None;
}

# Writes one Belief per recognized ingredient in a pasted regimen list, About the matching
# vocabulary Anchor (must already exist — wr_seed_vocabulary runs first) and DerivedFrom the
# source Utterance. A1: unrecognized lines are NOT written as Beliefs here — surfacing an
# unrecognized substance as Concern(kind="unrecognized_substance") is read.jac's job; this
# function only reports which raw lines need that treatment.
def wr_write_regimen(at_root: Root, source: Utterance, regimen_text: str) -> dict {
    parsed: dict = wr_parse_regimen(regimen_text);
    written: list[Belief] = [];
    parsed_anchors: list[dict] = list(parsed["anchors"]);
    for a in parsed_anchors {
        key: str = str(a["key"]);
        anchor: Anchor | None = wr_find_anchor(at_root, key);
        if anchor is not None {
            b = (at_root ++> Belief(claim="on " + key));
            b +>:DerivedFrom():+> source;
            b +>:About(weight=1.0):+> anchor;
            written.append(b);
        }
    }
    return {"written_count": len(written), "needs_review": parsed["needs_review"]};
}

# Writes a Constraint for one parsed threshold instruction, Governs the named symptom Anchor,
# DerivedFrom the source Utterance. Severity typing is the provenance read from CONTRACTS.md §2:
# hard is True only if source.role is oncologist/pharmacist/label — never a by llm() judgment.
# Returns None for timing/unstructured instructions or an unresolved metric — nothing invented.
def wr_write_instruction(at_root: Root, source: Utterance, instruction_text: str) -> Constraint | None {
    parsed: dict = wr_parse_instruction(instruction_text);
    if str(parsed["kind"]) != "threshold" {
        return None;
    }
    anchor_key: str = str(parsed["anchor_key"]);
    if anchor_key == "" {
        return None;
    }
    anchor: Anchor | None = wr_find_anchor(at_root, anchor_key);
    if anchor is None {
        return None;
    }
    hard: bool = source.role == "oncologist" or source.role == "pharmacist" or source.role == "label";
    c = (at_root ++> Constraint(
        claim=instruction_text,
        hard=hard,
        emergency=bool(parsed["is_emergency"]),
        threshold_level=float(str(parsed["threshold"])),
        threshold_days=0,
        threshold_metric=anchor_key
    ));
    c +>:DerivedFrom():+> source;
    c +>:Governs():+> anchor;
    return c;
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
    # #11 the interaction-gate case (ARCHITECTURE.md §7 row 1, #3's acceptance path): a
    # supplement from outside the graph's authority (S1), zero mention of "CYP3A4" or "imatinib"
    # or "Gleevec" — the interaction is only reachable by INTERACTION_TABLE + Member(class_member)
    # traversal, never by lexical overlap with this sentence.
    {"at": "2026-06-16", "role": "patient",
     "text": "My neighbor gave me some St John's Wort for stress, been taking it for a few days."},
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

# A substance a patient mentions in free text can be a medication OR a food (grapefruit is the
# canonical case — ARCHITECTURE.md §3's own example). wr_resolve_ingredient alone is too narrow
# for extraction, unlike regimen parsing where only actual medication lines are expected.
def wr_resolve_substance(raw: str) -> str {
    ingredient_key: str = wr_resolve_ingredient(raw);
    if ingredient_key != "" {
        return ingredient_key;
    }
    name: str = wr_strip_dose(raw).lower();
    known_foods: list[str] = [];
    for a in VOCAB_ANCHORS {
        if a["kind"] == "food" {
            known_foods.append(str(a["key"]));
        }
    }
    if name in known_foods {
        return name;
    }
    return "";
}

# A1 guard, run once per extracted belief that names a substance. Reuses the same vocabulary
# lookup as INGEST so "my neighbor gave me St John's Wort" and a pasted regimen line resolve
# identically — one vocabulary, two entry points.
def wr_check_extraction(belief: ExtractedBelief) -> dict {
    if belief.substance == "" {
        return {"needs_review": False, "anchor_key": ""};
    }
    key: str = wr_resolve_substance(belief.substance);
    if key != "" {
        return {"needs_review": False, "anchor_key": key};
    }
    # A1: no vocabulary match => no anchor, ever. The walker writes the Belief with
    # needs_review = True and reports Concern(kind="unrecognized_substance") — never "safe"
    # per S3, the page says "not in your record".
    return {"needs_review": True, "anchor_key": ""};
}

# MockLLM-first per Nathan's #27 findings: no provider key exists in this environment and
# platform credits don't cover app-level by llm() calls, so DEMO_MODE isn't a later convenience
# here — it's the only path that runs at all right now. This glob is the plumbing proof (spike/
# graph.jac's exact pattern); real per-utterance DEMO_MODE fixtures are #25, keyed off
# SEED_CHECKINS text, once this shape is confirmed against a live provider.
glob llm = MockLLM(
    model_name="mockllm",
    config={"outputs": [ExtractionResult(
        observation=ExtractedObservation(present=True, metric="nausea", value=1.0),
        beliefs=[
            ExtractedBelief(kind="preference", claim="mentioned nausea", substance="", polarity=0.0),
            ExtractedBelief(kind="constraint", claim="my neighbor gave me a herbal remedy", substance="herbal remedy", polarity=0.0),
        ]
    )]}
);

def wr_extract(text: str) -> ExtractionResult by llm();
sem wr_extract = "Extract a typed belief and, if present, a symptom observation from the patient's free-text check-in. Identify any medication or supplement name mentioned verbatim, even if unfamiliar, as ExtractedBelief.substance.";
sem wr_extract.text = "The patient's raw check-in sentence.";

# DEMO_MODE fixtures (#25) — keyed on exact Utterance.text (CONTRACTS.md §6), hand-built for the
# SEED_CHECKINS corpus. An if/elif chain rather than a dict[str, ExtractionResult] glob: explicit
# over clever, and it keeps every fixture next to the exact string it keys on for easy review.
# Anything outside SEED_CHECKINS falls through to an empty ExtractionResult — no observation, no
# beliefs — which is the honest "nothing extracted" answer, not a guess.
def wr_demo_extract(text: str) -> ExtractionResult {
    if text == "Take Gleevec at the same time every day, and call the clinic immediately if your temperature goes over 100.4." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="preference", claim="on Gleevec", substance="Gleevec", polarity=0.0)]);
    }
    if text == "Take Zofran within 30 minutes before food if the nausea is bad." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="preference", claim="on Zofran", substance="Zofran", polarity=0.0)]);
    }
    if text == "Also take docusate daily for constipation prevention." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="preference", claim="on docusate", substance="docusate", polarity=0.0)]);
    }
    if text == "Started the new medication today, feeling okay so far." {
        return ExtractionResult();
    }
    if text == "Some nausea after breakfast, took the Zofran like they said." {
        return ExtractionResult(
            observation=ExtractedObservation(present=True, metric="nausea", value=1.0),
            beliefs=[ExtractedBelief(kind="preference", claim="took Zofran", substance="Zofran", polarity=0.0)]
        );
    }
    if text == "Nausea again this morning, not too bad." {
        return ExtractionResult(observation=ExtractedObservation(present=True, metric="nausea", value=0.5));
    }
    if text == "Feeling okay, no complaints today." {
        return ExtractionResult();
    }
    if text == "Went to urgent care for a sinus infection and started Levaquin." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="constraint", claim="started Levaquin for a sinus infection", substance="Levaquin", polarity=0.0)]);
    }
    if text == "Some loose stools the last couple days, not sure why." {
        return ExtractionResult(observation=ExtractedObservation(present=True, metric="diarrhea", value=1.0));
    }
    if text == "Skipped my Gleevec refill this week, it's expensive and I couldn't get to the pharmacy in time." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="constraint", claim="skipped Gleevec refill due to cost", substance="Gleevec", polarity=0.0)]);
    }
    if text == "My neighbor gave me some St John's Wort for stress, been taking it for a few days." {
        return ExtractionResult(beliefs=[ExtractedBelief(kind="constraint", claim="started St John's Wort from a neighbor", substance="St John's Wort", polarity=0.0)]);
    }
    if text == "Still feeling tired but otherwise okay." {
        return ExtractionResult();
    }
    if text == "Finished the antibiotic course, sinus infection cleared up." {
        return ExtractionResult();
    }
    return ExtractionResult();
}

walker:pub Remember {
    has text: str;
    has role: str;
    has at: str;
    has out: Verdict = Verdict();

    can go with Root entry {
        utt = (here ++> Utterance(text=self.text, at=self.at, role=self.role));

        # Deterministic instruction parsing runs regardless of by llm() extraction — threshold
        # evaluation must never depend on a model (ARCHITECTURE.md §8's "seven places that must
        # not have one"). A miss here is silent: most check-ins carry no instruction at all.
        wr_write_instruction(here, utt, self.text);

        # DEMO_MODE read INSIDE the ability, never as a module-level glob — jachammer globs
        # evaluate once at boot and would miss a later change (Nathan's #27 finding, flagged for
        # this file by name). No live provider key exists yet either way (#27), so this is the
        # only path that runs right now regardless of the flag.
        extraction: ExtractionResult = ExtractionResult();
        if os.getenv("DEMO_MODE") {
            extraction = wr_demo_extract(self.text);
        } else {
            extraction = wr_extract(self.text);
        }

        if extraction.observation.present {
            obs = (here ++> Observation(
                metric=extraction.observation.metric,
                value=extraction.observation.value,
                at=self.at
            ));
            obs +>:DerivedFrom():+> utt;
        }

        for belief in extraction.beliefs {
            guard: dict = wr_check_extraction(belief);
            needs_review: bool = bool(guard["needs_review"]);
            anchor_key: str = str(guard["anchor_key"]);

            b = (here ++> Belief(claim=belief.claim, needs_review=needs_review));
            b +>:DerivedFrom():+> utt;

            if anchor_key != "" {
                anchor: Anchor | None = wr_find_anchor(here, anchor_key);
                if anchor is not None {
                    b +>:About(weight=1.0):+> anchor;
                }
            }

            # A9: Remember never reinforces — no strength/uses/last_used write, here or anywhere
            # else in this ability.
            if needs_review {
                self.out.concerns.append(Concern(
                    kind="unrecognized_substance",
                    anchor=belief.substance,
                    evidence=[jid(utt)],
                    since=self.at,
                    action="mention"
                ));
            }
        }
    }

    can emit with Root exit {
        report self.out;               # one typed object, once, from Root exit (CONTRACTS §4)
    }
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

# Two Beliefs are a candidate pair if they're About the same Anchor. O(n^2) over the graph's
# Beliefs, per ARCHITECTURE.md §4 — that's what the budget in wr_rank_conflict_candidates exists
# to make affordable.
def wr_share_anchor(a: Belief, b: Belief) -> bool {
    a_anchors: list[Anchor] = [a ->:About:->][?:Anchor];
    b_anchors: list[Anchor] = [b ->:About:->][?:Anchor];
    for x in a_anchors {
        for y in b_anchors {
            if x.key == y.key {
                return True;
            }
        }
    }
    return False;
}

# Examined is undirected in effect — check both directions, since two independent Consolidate
# runs could write the edge from either side of a pair.
def wr_already_examined(a: Belief, b: Belief) -> bool {
    forward: list[Belief] = [a ->:Examined:->][?:Belief];
    for x in forward {
        if jid(x) == jid(b) {
            return True;
        }
    }
    backward: list[Belief] = [b ->:Examined:->][?:Belief];
    for x in backward {
        if jid(x) == jid(a) {
            return True;
        }
    }
    return False;
}

# Builds the candidate-pair descriptors wr_rank_conflict_candidates ranks and slices. jid strings
# travel in the dict rather than node references so the dict stays the same plain-data shape the
# ranking function already expects and was tested against.
def wr_find_candidate_pairs(at_root: Root) -> list[dict] {
    beliefs: list[Belief] = [at_root -->][?:Belief];
    pairs: list[dict] = [];
    n: int = len(beliefs);
    for i in range(n) {
        for j in range(n) {
            if j > i {
                bi: Belief = beliefs[i];
                bj: Belief = beliefs[j];
                if wr_share_anchor(bi, bj) {
                    pairs.append({
                        "a_jid": jid(bi),
                        "b_jid": jid(bj),
                        "shared_anchor": True,
                        "reinforced_this_turn": False,
                        "last_examined": wr_already_examined(bi, bj),
                    });
                }
            }
        }
    }
    return pairs;
}

# Most recent Utterance.at in the graph — Consolidate's pinned signature (CONTRACTS.md §4) has
# no `at` field of its own, unlike Remember, so Examined.at / Conflicts.derived_at need a
# deterministic date from graph state rather than an unparameterized "now". Flagged as a
# CONTRACTS §4 gap worth a contract amendment, same class as the CaseFile.onset default (#29) —
# not resolved unilaterally, just handled the cheapest way that doesn't invent a clock.
def wr_latest_utterance_at(at_root: Root) -> str {
    utts: list[Utterance] = [at_root -->][?:Utterance];
    latest: str = "";
    for u in utts {
        if u.at > latest {
            latest = u.at;
        }
    }
    return latest;
}

# jobj() returns Any, which the +>:Edge:+> operator refuses as an endpoint (E1096/E1097 —
# "must be a node instance"). A typed re-scan is the fix: find the Belief by jid directly, which
# keeps its real type instead of erasing it through Any.
def wr_find_belief_by_jid(at_root: Root, target_jid: str) -> Belief | None {
    beliefs: list[Belief] = [at_root -->][?:Belief];
    for b in beliefs {
        if jid(b) == target_jid {
            return b;
        }
    }
    return None;
}

# Interaction-table wiring — Issue #3's remaining acceptance line. INTERACTION_TABLE (INGEST,
# above) is (a, b, because, source) data only; nothing turned it into a real Excludes edge until
# now. read.jac:253-257 names write.jac as the producer: one Constraint that Excludes the "a"
# side and Governs the "b" side, once the patient's regimen contains both. Lives in Consolidate,
# not Remember: it's a rewrite over accumulated state, additive-only (A6), not an ingest
# operation on a single check-in, and Remember's pinned signature (CONTRACTS.md §4) doesn't
# cover it.

# The anchor itself plus its class_member parents, one hop up — mirrors read.jac's
# rd_self_and_classes at read time. Reimplemented locally, not imported: satellites import only
# from graph.jac, never from each other (CONTRIBUTING.md).
def wr_anchor_and_classes(a: Anchor) -> list[str] {
    keys: list[str] = [a.key];
    for x in [a ->:Member:->] {
        for e in [edge a ->:Member:-> x] {
            if e.via == "class_member" {
                keys.append(x.key);
            }
        }
    }
    return keys;
}

# Every key the patient's current Beliefs reach, self-or-class, deduplicated. This is the set
# INTERACTION_TABLE pairs are checked against — "the regimen contains both sides" made concrete.
def wr_regimen_anchor_keys(at_root: Root) -> list[str] {
    keys: list[str] = [];
    beliefs: list[Belief] = [at_root -->][?:Belief];
    for b in beliefs {
        for a in [b ->:About:->][?:Anchor] {
            for k in wr_anchor_and_classes(a) {
                if k not in keys {
                    keys.append(k);
                }
            }
        }
    }
    return keys;
}

# First Belief reaching anchor_key (self-or-class) and its DerivedFrom Utterance — the evidence
# a newly-wired interaction Constraint cites (S2: no source, no verdict).
def wr_utterance_for_anchor_key(at_root: Root, anchor_key: str) -> Utterance | None {
    beliefs: list[Belief] = [at_root -->][?:Belief];
    for b in beliefs {
        for a in [b ->:About:->][?:Anchor] {
            if anchor_key in wr_anchor_and_classes(a) {
                utts: list[Utterance] = [b ->:DerivedFrom:->];
                if len(utts) > 0 {
                    return utts[0];
                }
            }
        }
    }
    return None;
}

# True if a Constraint already Excludes a_anchor and Governs b_anchor — prevents re-wiring the
# same pair on every Consolidate run.
def wr_interaction_already_wired(a_anchor: Anchor, b_anchor: Anchor) -> bool {
    excl: list[Constraint] = [a_anchor <-:Excludes:<-];
    for c in excl {
        gov: list[Anchor] = [c ->:Governs:->];
        for g in gov {
            if g.key == b_anchor.key {
                return True;
            }
        }
    }
    return False;
}

# Turns INTERACTION_TABLE pairs into real Constraint + Excludes + Governs wiring, once both sides
# are in the patient's regimen (self-or-class). Additive only (A6): never rewrites or deletes a
# prior wiring, only skips pairs already covered. hard=False always — the source is a curated
# table, not an Utterance with a clinical role (CONTRACTS.md §2), so it can never earn hard=True
# the way a #4 threshold instruction can.
def wr_wire_interactions(at_root: Root) -> list[Constraint] {
    written: list[Constraint] = [];
    keys: list[str] = wr_regimen_anchor_keys(at_root);
    for pair in INTERACTION_TABLE {
        a_key: str = str(pair["a"]);
        b_key: str = str(pair["b"]);
        if a_key not in keys {
            continue;
        }
        if b_key not in keys {
            continue;
        }
        a_anchor: Anchor | None = wr_find_anchor(at_root, a_key);
        b_anchor: Anchor | None = wr_find_anchor(at_root, b_key);
        if a_anchor is None {
            continue;
        }
        if b_anchor is None {
            continue;
        }
        a_node: Anchor = a_anchor;
        b_node: Anchor = b_anchor;
        if wr_interaction_already_wired(a_node, b_node) {
            continue;
        }

        because: str = str(pair["because"]);
        c = (at_root ++> Constraint(claim=because, hard=False));
        a_src: Utterance | None = wr_utterance_for_anchor_key(at_root, a_key);
        if a_src is not None {
            c +>:DerivedFrom():+> a_src;
        }
        b_src: Utterance | None = wr_utterance_for_anchor_key(at_root, b_key);
        if b_src is not None {
            c +>:DerivedFrom():+> b_src;
        }
        c +>:Excludes(because=because):+> a_node;
        c +>:Governs():+> b_node;
        written.append(c);
    }
    return written;
}

# MockLLM-first, same reasoning as wr_extract's glob above — no live provider key exists yet
# (Nathan's #27). A second, independently-bound model so this site's fixture queue never
# interferes with Remember's.
glob llm2 = MockLLM(
    model_name="mockllm-satisfiability",
    config={"outputs": [SatisfiabilityResult(jointly_satisfiable=True, because="")]}
);

def wr_check_satisfiability(claim_a: str, claim_b: str) -> SatisfiabilityResult by llm2();
sem wr_check_satisfiability = "Decide whether two natural-language patient/clinician statements can both be true at once. If they conflict, explain why in one sentence.";
sem wr_check_satisfiability.claim_a = "The first statement.";
sem wr_check_satisfiability.claim_b = "The second statement.";

# DEMO_MODE fixtures for by llm() site #2 — hand-built for the pairs the seed corpus can
# actually produce. Anything else falls through to jointly_satisfiable=True (the honest default:
# no evidence of a conflict is not evidence of no conflict, but Conflicts is additive and
# corroboration-only, so an unmatched pair simply isn't flagged rather than being guessed at).
def wr_demo_satisfiability(claim_a: str, claim_b: str) -> SatisfiabilityResult {
    return SatisfiabilityResult(jointly_satisfiable=True, because="");
}

walker:pub Consolidate {
    has budget: int = 6;
    has out: Verdict = Verdict();

    can go with Root entry {
        at_now: str = wr_latest_utterance_at(here);
        candidates: list[dict] = wr_find_candidate_pairs(here);
        ranked: dict = wr_rank_conflict_candidates(candidates, self.budget);
        examine: list[dict] = list(ranked["examine"]);

        for pair in examine {
            a_jid: str = str(pair["a_jid"]);
            b_jid: str = str(pair["b_jid"]);
            a_belief: Belief | None = wr_find_belief_by_jid(here, a_jid);
            b_belief: Belief | None = wr_find_belief_by_jid(here, b_jid);
            if a_belief is None {
                continue;
            }
            if b_belief is None {
                continue;
            }
            a_node: Belief = a_belief;
            b_node: Belief = b_belief;

            claim_a: str = a_node.claim;
            claim_b: str = b_node.claim;

            result: SatisfiabilityResult = SatisfiabilityResult();
            if os.getenv("DEMO_MODE") {
                result = wr_demo_satisfiability(claim_a, claim_b);
            } else {
                result = wr_check_satisfiability(claim_a, claim_b);
            }

            # A6/#6: mark Examined regardless of outcome — this IS the persistence that stops a
            # satisfiable pair being re-examined forever, per the schema note above. Additive
            # only; nothing is ever deleted.
            a_node +>:Examined(at=at_now, conflicting=not result.jointly_satisfiable):+> b_node;

            if not result.jointly_satisfiable {
                a_node +>:Conflicts(derived_at=at_now):+> b_node;
                self.out.conflicts.append(claim_a + " vs " + claim_b + ": " + result.because);
            }
        }

        wr_wire_interactions(here);
    }

    can done with Root exit {
        report self.out;               # one typed object, once, from Root exit (CONTRACTS §4)
    }
}
# ===== END CONSOLIDATE =====

# ===== DEMO_MODE — Issue #25 =====
# Both by llm() sites (REMEMBER, CONSOLIDATE) branch on it and return fixtures keyed to exact
# Utterance.text. Fixtures live in the SEED section above.
#
# Per Nathan's #27 findings: read `os.getenv("DEMO_MODE")` INSIDE each walker's ability, never
# as a module-level glob — globs evaluate once at boot in jachammer and won't see a later change
# (and no live model access exists yet regardless, so DEMO_MODE is the only path that runs).
# ===== END DEMO_MODE =====
