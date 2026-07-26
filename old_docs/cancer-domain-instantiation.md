# Cancer / Consumer-Health Instantiation

Companion to `memory-as-topology.md`. That document is the domain-neutral spec; this one binds it
to a single domain. Section names below refer to the spec — read it first, this assumes its
vocabulary (`Anchor`, `Belief`, channel A/B, `Verdict`, the five consolidation operations).

Nothing here changes the thesis. It supplies the domain's anchor vocabulary, names the concern
classes the topology can detect, and lists three deltas the domain forces on the spec.

## The application

A longitudinal treatment companion. The patient (or caregiver) checks in daily about how they
feel and what they took. Two things run off that graph:

1. **The interaction gate** — before any new substance enters the regimen, `Recall` runs as a
   mandatory gate, not a ReAct tool. `allowed == false` blocks.
2. **Concern surfacing** — every check-in re-runs `Recall` against the symptom anchor set and
   returns structurally detected concerns with a severity-graded action.

The output artifact is a **drafted message the patient sends**, never an autonomous outbound
message to a clinician.

### Why longitudinal, not one-shot

A single-session gate does not need a memory graph; a vector store approximates it well enough
that the difference has to be argued rather than shown. Three weeks of check-ins is where
reinforcement, decay, and occlusion stop being decoration. It is also what produces
absence-class detection (below), which has no analogue in a transcript.

## Safety posture

Non-negotiable. These are constraints on the implementation, not framing.

- **This is a recall layer over what the care team already said.** The graph never originates a
  clinical fact. Authority lives in the parsed artifact — pharmacy label, printed instructions,
  visit summary — not in the model and not in the implementer's recollection.
- **Every `Violation` and every escalating `Concern` must cite an `Utterance`.** No source, no
  verdict. Absence yields *"not in your record"* — never *"safe."*
- **No dosing judgments, ever.** The system may surface that a symptom crossed a threshold the
  care team itself set, and may draft the question. It may not answer it. Never render "you may
  be overdosed" or any equivalent.
- **No substitutions, no dose calculations, no recommending discontinuation.**
- **Emergency criteria bypass everything.** Evaluated before scoring, drafting, or beam. Output
  is "contact your team now," not a `Verdict` object.
- **Channel A can never escalate.** Regardless of score. Soft beliefs shape; they do not alarm.

## Anchor vocabulary

Anchors are resolved deterministically from vocabulary, per the spec's *anchor layer is ground
truth* rule. None are invented by `by llm()`.

| `Anchor.kind` | Source | Example |
|---|---|---|
| `ingredient` | RxNorm ingredient RxCUI; brand→ingredient is a lookup | imatinib |
| `class` | ATC / EPC | `CYP3A4-substrate`, `NSAID`, `QT-prolonging` |
| `symptom` | CTCAE term | peripheral neuropathy |
| `lab` | LOINC / ICD-10 | neutropenia |
| `phase` | **computed arithmetically** from regimen start date | cycle day 10–14 |
| `food` | small closed set | grapefruit, alcohol, calcium |

`phase` is subtraction over a parsed date, not reasoning. It stays inside the spec's *no temporal
reasoning beyond `Supersedes`* non-goal.

## Spec deltas

Three changes. Reconcile these against your copy of `memory-as-topology.md` before building.

### Delta 1 — a ninth edge: `Member`

```jac
edge Member: Anchor --> Anchor { has via: str; }   # via: "class_member" | "toxicity_of"
```

Vocabulary structure, so it belongs to the anchor layer: **unscored, unpruned, no decay,
traversed in channel B** as pure expansion.

Required because the load-bearing traversal is
`grapefruit → CYP3A4 inhibitor → CYP3A4 substrate → imatinib`, and the spec's eight edges have no
`Anchor --> Anchor`. The alternative — expanding class membership inside the `Root` resolution
ability — preserves the edge count but hides the hop, and the hop is the demonstration.

`via="toxicity_of"` reuses the same edge for drug→adverse-event, which is the same category of
fact (published on the label) and enables the additive-toxicity triangle below.

### Delta 2 — `Conflicts` widens to `Belief --> Belief`

```jac
edge Conflicts: Belief --> Belief { has derived_at: str; }   # was Constraint --> Constraint
```

Instruction drift is a soft behavior `Belief` contradicting a hard `Constraint` — "I take it
whenever I remember" against "within 30 minutes after food." Node inheritance already supports
the widening; the narrow endpoint typing is the only thing blocking it.

### Delta 3 — an `Observation` layer, and `Concern` on the `Verdict`

```jac
node Observation { has metric: str; has value: float; has at: str; }
edge Reports:     Observation --> Anchor    { }   # symptom anchor
edge DerivedFrom: Observation --> Utterance { }   # the sentence they typed
```

`Observation` extends the **provenance floor**, not the belief layer. It is reported fact, not
claim: never scored, never occluded, never decayed. "Nausea 6/10 on the 14th" must not become
less true because it was not recently traversed.

```jac
obj Concern { has kind: str; has anchor: str;
              has evidence: list[str];   # Observation + Utterance ids
              has since: str;
              has action: str; }         # escalate | draft | mention | log
```

Added to the existing `Verdict` as `has concerns: list[Concern] = [];`. Not a second report
object — the gate and the daily review differ only in which anchor set `Recall` resolves, which
is the spec's *three walkers, one topology* claim doing real work.

**No fourth walker.** After `Remember` writes today's `Observation`, it re-spawns `Recall` on the
symptom anchor set. The daily check-in is the trigger, which satisfies the deployment
constraint that there is no scheduler available for a sweep.

## Concern classes

Every class is detected structurally. If a concern can only be found by asking a model whether
something sounds bad, it is channel A and it caps at `mention`.

### Mechanism 1 — a path exists that should not

| Concern | Patient input | Signature |
|---|---|---|
| **Interaction** | "my neighbor gave me St. John's Wort" | new anchor → `Member(class_member)` → active regimen anchor, with `Excludes` on the path |
| **Additive toxicity** | *(nothing — invisible to the patient)* | two active `ingredient` anchors both → `Member(toxicity_of)` → the **same** `symptom` anchor |

Additive toxicity is a triangle. Two prescribers, one shared toxicity, no one compared them
because no one was in both rooms. This is the spec's `Conflicts` derivation pointed at toxicity
rather than interaction — same operation, second payoff, and a class of result a similarity
index cannot produce at any *k*.

### Mechanism 2 — a path is missing that should exist

Unique to this design: absence of an edge is inspectable, absence of a top-k hit is not.

| Concern | Signature | Note |
|---|---|---|
| **Unattributed symptom** | `symptom` anchor with **no** `toxicity_of` edge from any active drug | new and unexplained ⇒ *more* urgent, not less |
| **Supportive-care gap** | `symptom` anchor has an incoming instruction `Constraint` but no `Observation` of adherence | the prescription that was never filled |
| **Adherence gap** | regimen anchor with no `Observation` referencing it for N days | |
| **Silence** | gap in the `Observation` chain | a patient who feels worst stops writing |

Expectation comes from the **parsed regimen**, not inference: what should be happening is ground
truth, what is happening is observed, the gap is set difference. No new archetype needed.

`Silence` is the spec's silent-failure argument in the time dimension — missing check-ins look
identical to improvement, and only the structure makes that visible.

### Mechanism 3 — accumulated `Observation` crosses a stated threshold

| Concern | Signature |
|---|---|
| **Persistence** | symptom ≥ level L for D days, where L and D are parsed from the patient's own instructions into a `Constraint` on that anchor |
| **Trajectory** | monotone worsening across cycles on an anchor the label marks cumulative |
| **Emergency** | `Constraint` on a symptom/lab anchor flagged emergency; evaluated first, bypasses everything |

Thresholds are parsed, never recalled by the model. **Trajectory** is where dose concern
legitimately lives: the output is *"worth raising at the next visit, here is the record,"* and
never a dosing conclusion.

### Mechanism 4 — two stated things contradict

| Concern | Example |
|---|---|
| **Instruction drift** | regimen says "within 30 minutes after food"; patient says "whenever I remember" |
| **Cross-prescriber conflict** | two `Constraint`s from two clinicians, jointly unsatisfiable |
| **Cause of nonadherence** | "I skipped Tuesday, I was short on the copay" |

Nonadherence cause is not a footnote. *Missed for cost or transport* and *missed for toxicity*
lead to different clinical action, and the second is what gets assumed. Carrying the cause into
the drafted message is plausibly the highest-value line the system produces.

## Severity ladder

```
escalate  → channel B hit flagged emergency        → "contact your team now"; no draft, no scoring
draft     → channel B hit, non-emergency           → message to send, provenance inline
mention   → channel A, or any absence-class hit    → appointment-prep list
log       → everything else                        → written to the graph, shown to no one
```

Only channel B may produce `escalate` or `draft`. This is the spec's channel-B carve-out applied
to the output side, and it is the alert-fatigue control: if everything surfaces, nothing does.

## Severity typing is deterministic, not extracted

The spec names its highest-severity failure mode as a `Constraint` mis-typed as a `Preference`,
silently downgrading channel B to channel A. This domain lets that be fixed structurally rather
than caveated:

> A `Constraint` may be `hard == True` only if its `DerivedFrom` `Utterance` has a clinical
> `role` — `oncologist`, `pharmacist`, or `label`. Patient- and caregiver-sourced beliefs default
> to soft, allergies excepted.

`Utterance.role` becomes an authority signal, and severity becomes a function of provenance read
off an existing edge rather than a judgment `by llm()` makes.

Consequence worth stating: `Preference.polarity` earns its place here. "Ginger tea made it worse"
(−1) and "cold things help" (+1) are distinct facts. The cautionary case is oxaliplatin cold
sensitivity — a genuine hard constraint that presents as a temperature preference, and exactly
the misclassification the rule above is designed to prevent.

## Worked trace

1. Pharmacy label parsed → `Anchor(ondansetron)` + `Member(toxicity_of) → Anchor(qt_prolongation)`.
2. Day 9, patient writes *"urgent care gave me something for a sinus thing."*
   `Remember` extracts a `Belief`, resolves it to an `ingredient` anchor, and the vocabulary
   lookup attaches that drug's own `toxicity_of` edge — to the same `qt_prolongation` anchor.
3. Same turn: `Consolidate` sees two active `ingredient` anchors converging on one `symptom`
   anchor and writes `Conflicts`. `Recall` returns
   `Concern(kind="additive_toxicity", action="draft")`.

The patient never mentioned their heart, never mentioned ondansetron, and asked about a sinus
infection. No query resembling the input retrieves this.

## Build order

Maps onto the spec's seven stages; domain work in bold.

| Spec stage | This domain |
|---|---|
| 1. Archetypes + persistence | add `Observation`; `Member`; widen `Conflicts` |
| 2. Anchor ingestion | **parse a pasted med list → `ingredient` anchors; load vocabulary JSON → `Member` edges** |
| 3. `Remember` | daily check-in: `Utterance` + `Observation` + belief extraction |
| 4. `Recall` channel B | **interaction gate + emergency bypass.** Guarantee lands before scoring exists |
| 5. `Recall` channel A | preferences, beam, reinforcement |
| 6. `Shortcut` | — |
| 7. `Conflicts` | **additive toxicity + cross-prescriber conflict** |

Stage 4 before 5 is the spec's ordering and holds here for the same reason. Absence-class
detection (mechanism 2) can be built any time after stage 3; it is arithmetic over the parsed
regimen, not traversal.

Scope guidance: ship the daily check-in, the interaction gate, and the drafted message. Emergency
bypass is small and cannot responsibly be omitted from anything with a chat surface. Cut trend
charts and visualizations entirely.

## Data sources

- **RxNorm** (public) for ingredient RxCUIs and brand→ingredient normalization.
- **ATC / EPC** for class membership.
- **Interactions:** NLM retired the RxNav drug-interaction API in early 2024. Plan on a
  hand-curated table of oncology-relevant pairs sourced from labels, bundled as passed-in JSON.
  State the count and cite a source per pair. A vague claim of using a live interaction API
  invites a question with no good answer.
- **Thresholds and instructions:** parsed from the patient's own artifact only.
- Per the spec's deployment section, all of the above must arrive as passed-in content. No
  local-path reads.

## Domain-specific limits

- **The regimen parse bounds everything.** A drug absent from the parsed list has no anchor, so
  no path reaches it. This is the spec's *guarantee is conditional on the edge existing* limit
  with a concrete failure surface.
- **Curated interaction coverage is partial by construction.** The system must not imply that
  silence means no interaction exists.
- **Patient-reported severity is unvalidated.** `Observation.value` is self-rating, not a
  clinician-assigned CTCAE grade, and thresholds parsed from instructions were written assuming
  the latter.
- **Absence-class detection assumes engagement.** Silence detection mitigates but does not solve
  this; a patient who stops using the app entirely is outside the system.
- **No baseline comparison.** Carried over from the spec.

## Open

- Whether `Concern` and `Violation` should merge. They differ mainly in whether the trigger was a
  proposed action or an accumulated observation.
- Whether `mention`-level concerns should decay. They are channel A, so scoring says yes, but an
  unresolved appointment-prep item arguably should not cool off before the appointment.
