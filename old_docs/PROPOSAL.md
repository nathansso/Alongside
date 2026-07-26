# PROPOSAL: Longitudinal Treatment Companion

Build specification. Written to be read by an implementing agent.

**Status:** proposed, not approved. Do not begin implementation until the human reviewer has
signed off. See `DECISIONS.md` for what changed and why.

**Companion documents**
- `memory-as-topology.md`: the domain-neutral engine spec. Authoritative for archetypes,
  channel semantics, scoring, and consolidation.
- `cancer-domain-instantiation.md`: the domain binding. Authoritative for anchor vocabulary,
  concern classes, and the severity ladder.
- This file: the implementation contract and build order. Where this file and the two above
  disagree, **this file wins**, and the disagreement should be reported to the human.

**Target:** JacHacks SF, July 26 2026. Tracks: Social Impact, Agentic AI, Best JacHammer.

---

## 1. What is being built

A longitudinal treatment companion for cancer patients and caregivers. The patient checks in
daily about how they feel and what they took. A persistent Jac graph accumulates those check-ins
as typed beliefs linked to deterministically-parsed anchors.

Two things run off that graph:

1. **An interaction gate.** Before any new substance enters the regimen, a mandatory graph
   traversal runs. If a hard constraint is violated, the action is blocked.
2. **Unprompted concern surfacing.** Every app open and every check-in re-runs detection against
   the symptom anchor set and returns structurally detected concerns with a graded action.

The output artifact is a **drafted message the patient sends**. The system never sends anything
autonomously and never contacts a clinician.

### The retrieval claim

Relevance is reachability, not similarity. Top-k retrieval fails silently: a blocking fact
ranked 11th is indistinguishable from a fact that does not exist. Graph traversal fails visibly:
if a constraint is connected to the anchor it is reached, and if it is not reached the edge is
missing and that is inspectable.

---

## 2. Invariants

These are not preferences. An implementation that violates any of them is wrong regardless of
whether it runs. If satisfying a request would require violating one, stop and report.

### 2.1 Safety invariants

| # | Invariant |
|---|---|
| S1 | The graph never originates a clinical fact. Authority lives in the parsed artifact: pharmacy label, printed instructions, visit summary. |
| S2 | Every `Violation` and every escalating `Concern` cites an `Utterance`. No source, no verdict. |
| S3 | Absence of a finding yields "not in your record". **Never** "safe". |
| S4 | No dosing judgments. No substitutions. No dose calculations. No recommending discontinuation. |
| S5 | Emergency criteria are evaluated before scoring, drafting, or beam. Output is "contact your team now", not a `Verdict`. |
| S6 | Channel A can never escalate. Soft beliefs shape output; they never alarm. |
| S7 | No autonomous outbound communication. The system drafts; the patient sends. |

### 2.2 Architectural invariants

| # | Invariant |
|---|---|
| A1 | **Anchors are never invented by `by llm()`.** Anchor creation requires vocabulary membership. |
| A2 | **Channel B is unscored, unpruned, exempt from decay, beam, budget, and the waterline.** The only thing that kills a channel B constraint is `Supersedes`. |
| A3 | **The model never selects a traversal path.** No `visit [-->] by llm()` anywhere in `walkers/`. |
| A4 | **Embeddings appear only in `eval/`.** Nothing under `walkers/` may import `eval/baseline.jac`. |
| A5 | **Corroboration promotes only.** `Synthesize` may raise severity. It may never lower it. A channel B hit reaches `draft` alone. |
| A6 | **Occlusion is never deletion.** Cold nodes keep `DerivedFrom` edges and sit below the waterline. |
| A7 | **`Observation` is never scored, occluded, or decayed.** It is reported fact on the provenance floor. |
| A8 | **The gate is mandatory, not a tool.** `recall()` runs before any action touching an anchor. It is not exposed as an optional ReAct tool. |

### 2.3 The organizing rule

> **Autonomy on the write path. Determinism on the read path.**

The model may decide what enters the graph and what to say about a finished verdict. It never
decides which path the traversal takes.

---

## 3. Archetypes

Signatures are indicative. Section 8 governs syntax pitfalls.

```jac
node Utterance   { has text: str; has at: str; has role: str; }
node Anchor      { has key: str; has kind: str; }
node Observation { has metric: str; has value: float; has at: str; }
node Belief      { has claim: str; has strength: float = 1.0;
                   has last_used: str; has uses: int = 0;
                   has needs_review: bool = False; }
node Preference(Belief) { has polarity: float = 0.0; }
node Constraint(Belief) { has hard: bool = True; }
```

```jac
edge DerivedFrom: Belief      --> Utterance  { }
edge Reports:     Observation --> Anchor     { }
edge About:       Belief      --> Anchor     { has weight: float = 1.0; }
edge Relates:     Belief      --> Belief     { has weight: float = 1.0; has co_uses: int = 0;
                                               has last_used: str; }
edge Supersedes:  Belief      --> Belief     { }
edge Shortcut:    Anchor      --> Belief     { has hops: int = 2; has weight: float = 1.0; }
edge Governs:     Constraint  --> Anchor     { }
edge Excludes:    Constraint  --> Anchor     { has because: str; }
edge Conflicts:   Belief      --> Belief     { has derived_at: str; }
edge Member:      Anchor      --> Anchor     { has via: str; }
```

`Observation` also carries a `DerivedFrom` edge to its `Utterance`.

`Member.via` is `"class_member"` or `"toxicity_of"`. `Member` is anchor-layer vocabulary
structure: unscored, unpruned, no decay, traversed in channel B as pure expansion.

```jac
obj Violation { has claim: str; has because: str; has source: str; has at: str; }
obj Concern   { has kind: str; has anchor: str; has evidence: list[str];
                has since: str; has action: str; }
obj Verdict   { has allowed: bool = True;
                has violations: list[Violation] = [];
                has soft: list[str] = [];
                has conflicts: list[str] = [];
                has concerns: list[Concern] = []; }
```

`Concern.action` is one of `escalate | draft | mention | log`.

### Anchor vocabulary

| `Anchor.kind` | Source |
|---|---|
| `ingredient` | RxNorm ingredient RxCUI; brand to ingredient is a lookup |
| `class` | ATC / EPC, e.g. `CYP3A4-substrate`, `NSAID`, `QT-prolonging` |
| `symptom` | CTCAE term |
| `lab` | LOINC / ICD-10 |
| `phase` | computed arithmetically from regimen start date |
| `food` | small closed set: grapefruit, alcohol, calcium |

### Severity typing is deterministic

A `Constraint` may be `hard == True` only if its `DerivedFrom` `Utterance` has `role` in
`{oncologist, pharmacist, label}`. Patient- and caregiver-sourced beliefs default to soft,
allergies excepted. Severity is a provenance read, never a `by llm()` judgment.

---

## 4. Walker contracts

Seven walkers, one topology. All traverse the same graph with the same archetypes.

### `Vigil`: read, unprompted

- **Trigger:** app open, before any user input.
- **Reads:** `Observation` timestamps, regimen anchor dates, instruction `Constraint`s.
- **LLM calls:** zero. Pure arithmetic.
- **Emits:** `Concern` at `mention` for adherence gap, silence, supportive-care gap, `phase`
  transition crossed.
- **Must not:** read beliefs, score anything, call `by llm()`.

### `Remember`: write

- **Trigger:** patient check-in submitted.
- **Writes:** `Utterance` (always), `Observation` (if a symptom value is present), `Belief` nodes
  from extraction, `DerivedFrom` and `About` edges.
- **LLM calls:** `by llm()` #1 (Extract, typed schema). Plus one ReAct/Invoke loop for
  vocabulary resolution when an unrecognized substance appears.
- **Guard (A1):** a returned identifier creates an `Anchor` only if it is already present in the
  loaded vocabulary. On a miss: no anchor, belief written with `needs_review = True`, surfaced at
  `mention`, drafted message states the substance was not recognized.
- **Then:** spawns `Consolidate`, then the detection set.

### `Recall`: read, the two-channel traversal

Unchanged from `memory-as-topology.md`. This is the file to open first when reviewing.

- **Channel B:** `[edge here <-:Governs:<-]`, `<-:Excludes:<-`, `Member` expansion. Exhaustive,
  unscored, unpruned. Exempt from beam, budget, decay, waterline.
- **Channel A:** `[edge here <-:About:<-]`, `->:Relates:->`, `->:Shortcut:->`. Scored, beam per
  node, budget counted, decay applied.
- `effective(e) = e.weight * 0.5 ** (days_since(e.last_used) / half_life)`. Channel A only.
- Reinforces the channel A trail on `root exit`. Reports once.
- **Must not:** contain a `while` loop. Policy lives on node-type abilities.

### `Consolidate`: rewrite, self-budgeted

- **Trigger:** after `Remember`, same turn.
- **Plans its own work.** Conflict derivation is n^2 pairs at one LLM call each. Given a per-turn
  call budget, rank candidate pairs by: shared `Anchor` > reinforced this turn > cold. Skip pairs
  carrying a persisted `last_examined` marker. Spend until budget is exhausted. Queue the
  remainder for the next turn.
- **LLM calls:** `by llm()` #2 (Extract, jointly-unsatisfiable boolean plus reason), up to budget.
- **Writes:** `Conflicts` edges. Also reinforce, decay bookkeeping, `Shortcut`, occlusion.
- **Must not:** delete a node. Every consolidation operation is additive or marks state.

### Detection set: read, four walkers, spawned in parallel

| Walker | Traverses | Detects |
|---|---|---|
| `PathAgent` | `Anchor -Member-> Anchor`, `Excludes` | interaction, additive toxicity |
| `AbsenceAgent` | parsed regimen vs `Observation` set | unattributed symptom, adherence gap, silence |
| `ThresholdAgent` | `Observation` chains vs parsed `Constraint`s | persistence, trajectory, emergency |
| `ContradictionAgent` | `Conflicts` edges | instruction drift, cross-prescriber conflict |

`PathAgent` is channel B of `Recall` under a domain name. It should call into `Recall`, not
reimplement traversal.

**Additive toxicity is a triangle:** two active `ingredient` anchors both reaching the same
`symptom` anchor via `Member(toxicity_of)`. Two prescribers, one shared toxicity, no one compared
them. This is the headline detection.

### `Synthesize`: read, merge

- Groups findings by `Anchor`.
- Two detection walkers converging on the same anchor promotes severity by one rung.
- **A5 is absolute.** Never demotes. A channel B hit reaches `draft` uncorroborated, every time.

### `Investigate`: read, case-file assembly

Spawns behind any `draft`-level finding. Steps, in order:

1. Walk the `Observation` chain back to first onset of the implicated `symptom` anchor.
2. Compare onset against regimen change dates.
3. Look for the counterfactual: days the drug was absent from the record, and whether the symptom
   was absent too.
4. Check for an existing instruction `Constraint` on that anchor. If one exists, the message
   changes from "report this" to "the instruction you were given covers this".
5. Assemble a dated timeline with every `Utterance` citation attached.

All graph traversal and date arithmetic. No LLM call.

### `Prepare`: read, agenda

Walks accumulated `mention`-level concerns, groups by anchor, orders, produces an appointment
agenda. Consumes and marks them. `mention` concerns do **not** decay; they persist until
`Prepare` consumes them.

**Lowest priority. First thing to cut.**

---

## 5. Severity ladder

```
escalate  -> channel B hit flagged emergency   -> "contact your team now"; no draft, no scoring
draft     -> channel B hit, non-emergency      -> message to send, provenance inline
mention   -> channel A, or any absence-class   -> appointment-prep list
log       -> everything else                   -> written to the graph, shown to no one
```

Only channel B may produce `escalate` or `draft`. This is the alert-fatigue control: if
everything surfaces, nothing does.

---

## 6. Repo layout

```
graph/archetypes.jac      nodes, edges, Verdict/Concern/Violation objs
walkers/recall.jac        two-channel traversal; review this file first
walkers/remember.jac      Utterance + Observation write, by llm() #1, Invoke vocab resolution
walkers/consolidate.jac   self-budgeted Conflicts derivation, by llm() #2
walkers/vigil.jac         runs on open, elapsed-time only, no LLM
walkers/detect/path.jac
walkers/detect/absence.jac
walkers/detect/threshold.jac
walkers/detect/contradiction.jac
walkers/synthesize.jac    corroboration merge; promotes only
walkers/investigate.jac   case-file assembly
walkers/prepare.jac       appointment agenda
ingest/regimen.jac        deterministic med-list parse -> ingredient anchors
ingest/vocab.jac          vocabulary JSON -> Member edges
draft/message.jac         by llm() #3, gated on a decided Verdict
eval/harness.jac          recall@constraint over the seed set
eval/baseline.jac         cosine top-k. QUARANTINED. Never imported by walkers/.
ui/App.cl.jac             check-in surface
ui/Inspector.cl.jac       traversal render
data/*.json               vocabulary and curated pairs; the only non-Jac artifacts
```

**Jac share:** everything except `data/`. Python appears only as libraries imported into Jac.
Do not create a separate Python service or a separate React app. The UI is `.cl.jac`.

---

## 7. `by llm()` census

Exactly three calls. Adding a fourth requires human approval.

| # | Location | Why an LLM is correct |
|---|---|---|
| 1 | `walkers/remember.jac` | free-text patient language into a typed schema |
| 2 | `walkers/consolidate.jac` | joint satisfiability of two natural-language constraints |
| 3 | `draft/message.jac` | prose generation, downstream of a decided `Verdict` |

Plus one ReAct/Invoke loop in `remember.jac` for vocabulary resolution, guarded per A1.

**Six places that must not have one:**

| Location | Why not |
|---|---|
| anchor resolution | vocabulary lookup; an LLM here puts extraction error at the head of every traversal |
| severity typing | read off `Utterance.role` |
| path selection | structural; violates A3 |
| threshold evaluation | arithmetic over parsed values |
| absence detection | set difference against the parsed regimen |
| emergency bypass | parsed flag, evaluated before anything else runs |

Call 3 runs only after `allowed` and `action` are decided. The model writes the sentence. It
never decides whether there is a sentence to write.

### Jaseci primitive usage

Used: Extract (x2), Generate, Invoke, Spawn, Pipe, Loop.
**Refused: Route.** `visit [-->] by llm()` would make retrieval probabilistic and void the
channel B guarantee. This refusal is deliberate and should be stated in the writeup, not fixed.

---

## 8. Jac implementation gotchas

Carried from `memory-as-topology.md`. Read before writing any Jac.

- **Edge abilities are a silent no-op.** `can ... with Walker entry` inside an `edge` compiles
  clean and never fires. All scoring lives in walker node abilities reading `[edge ...]`.
- **Editing archetypes corrupts the local graph.** `jac run` persists to cwd `.jac/`. Changing a
  node or edge definition between runs gives `NodeAnchor ... is not a valid reference!`. Reflex:
  `rm -rf .jac/data/`, restart.
- **`++>` returns a list.** `b = (anchor ++> Belief(claim=c))[0];`. A missing `[0]` fails
  somewhere else entirely.
- **Typed edge deletion needs `[edge ...]` plus iterate-`del`.** `del [a ->:Supersedes:-> b];`
  passes `jac check` and fails at runtime with E5043.
- **`by llm()` returns `obj`, never `node`.** Extract into an obj, copy into the node.
- **Report once from `with Root exit`.** Per-node reporting scatters N tiny reports.
- **Type the report channel:** `has verdict: Verdict = Verdict();`. Omitting the default makes it
  a required spawn parameter and every spawn fails E1050.
- **Declare endpoints on every edge.** An untyped edge yields `Unknown`-typed nodes that pass
  `jac check` and fail later.
- **Edge creation is where the intelligence lives.** Substring or keyword matching to link
  beliefs will look correct on the first three nodes and quietly poison every traversal after.

---

## 9. Build order

Nine stages plus an agentic layer. Each stage has an acceptance check. Do not advance until the
check passes.

| # | Stage | Acceptance check |
|---|---|---|
| 1 | Archetypes + persistence | Graph survives a process restart. Retrieval stubbed to "return every belief". |
| 2 | Anchor ingestion | Pasted med list produces correct `ingredient` anchors. Vocabulary JSON produces `Member` edges. Zero anchors created outside vocabulary. |
| 3 | `Remember` | Check-in writes `Utterance` + `Observation` + beliefs with `DerivedFrom` intact. Unknown substance produces `needs_review`, not an anchor. |
| 4 | `Recall` channel B | Seeded blocking constraint two hops out on a cold edge is returned every run. Emergency bypass fires before anything else. `allowed == false` blocks. |
| 5 | Seed + baseline + metric | `recall@constraint` reported for traversal vs cosine top-5 vs top-10 over ~30 seeded requests. |
| 6 | `Conflicts` | Additive-toxicity triangle detected on the seeded graph. Cross-prescriber conflict detected. |
| 7 | `Recall` channel A | Beam, budget, decay, reinforcement. Context size at or below the top-k baseline. |
| 8 | Inspection surface | Two-pane render: cosine vs traversal, same request, visible disagreement. Provenance click-through works. |
| 9 | `Shortcut` | Repeated path collapses to a `Shortcut` edge. |

**Agentic layer**, slotted by dependency:

| Walker | Earliest | Priority |
|---|---|---|
| `Vigil` | after 3 | **HIGH** |
| `AbsenceAgent` | after 3 | **HIGH** |
| `PathAgent` | after 4 | HIGH |
| `Investigate` | after 4 | **HIGH** |
| `ThresholdAgent` | after 4 | medium |
| `ContradictionAgent` | after 6 | medium |
| `Synthesize` | after two detection walkers exist | medium |
| `Prepare` | last | cut first |

**If only two agentic walkers get built: `Vigil` and `Investigate`.** `Vigil` buys the autonomy
claim for close to nothing. `Investigate` is the difference between a detector and a companion.

**Drop order if the schedule slips:** `Prepare`, then `Shortcut`, then channel A reinforcement,
then channel A entirely. Dropping all four leaves the gate, the guarantee, the measurement, and
the demo intact.

---

## 10. Evaluation

**Seed graph.** One synthetic patient, three weeks of check-ins, four to six `ingredient` anchors
from two prescribers, vocabulary slice sufficient for the `Member` hops. Hand-built, persisted,
loaded at start. **Not extracted live.**

**Adversarial case.** Seed the QT convergence so a similarity retriever cannot reach it: check-in
text is about a sinus infection, the shared `symptom` anchor is two `Member` hops from either
drug, no lexical overlap between input and constraint.

**Report:**

```
recall@constraint       traversal vs cosine top-5 vs top-10, ~30 seeded requests
absence-class recall    mechanism 2 only; baseline scores structurally zero
context size            beliefs delivered per request
failure attribution     misses from a missing edge (inspectable) vs from rank (silent)
```

Lead with absence-class recall. A retriever cannot rank a document that does not exist.

**State the caveat in the same breath:** the seed set was built by the people who designed the
traversal and the adversarial case was placed on purpose. It demonstrates a failure mode. It does
not establish general superiority.

---

## 11. Demo spine

Three minutes. Build to the shorter number; the hacker guide says four, the judging criteria say
three.

| # | Beat | Time |
|---|---|---|
| 1 | Regimen parse: anchors and `Member` edges appear | 25s |
| 2 | `Vigil` speaks first. Open the app to log nausea, system raises an adherence gap unprompted | 20s |
| 3 | The trace. Sinus-infection line. Split pane: cosine finds nothing, traversal reaches `qt_prolongation` from two directions | 75s |
| 4 | `Investigate` case file, provenance click-through to source sentences | 30s |
| 5 | `walkers/recall.jac` on screen. Ability set, no loop. Primitive census, refusal of Route | 30s |

**Do not demo:** live extraction latency, trend charts, multi-week timeline scroll, any screen
where the model decides something safety-relevant.

**Do demo deliberately:** a substance not in the vocabulary. The system must say "not in your
record", never "safe". This scores under Technical Execution as graceful edge-case handling.

---

## 12. Do not build

- Patient-facing trend charts or timeline visualizations. They cost real time, invite the dosing
  question S4 forbids, and score nothing. The stage 8 traversal inspector is a different artifact
  and is kept.
- A separate Python backend service.
- A separate React frontend.
- Any scheduler, cron, or background sweep. `Vigil` on app open is the trigger.
- Multi-user or auth beyond the default per-root isolation.
- Lossy summarization or compression of beliefs.
- Temporal reasoning beyond `Supersedes`.
- A live drug-interaction API integration. See section 13.

---

## 13. Data sources

- **RxNorm** (public) for ingredient RxCUIs and brand to ingredient normalization.
- **ATC / EPC** for class membership.
- **Interactions:** NLM retired the RxNav drug-interaction API in early 2024. Use a hand-curated
  table of oncology-relevant pairs sourced from labels, bundled as passed-in JSON. **State the
  pair count and cite a source per pair.** A vague claim of using a live interaction API invites a
  question with no good answer.
- **Thresholds and instructions:** parsed from the patient's own artifact only.
- All of the above must arrive as passed-in content. No local-path reads. The deployment target
  is a browser IDE with no filesystem guarantee.

---

## 14. Open decisions requiring human input

Do not resolve these autonomously. Surface them and wait.

1. **Parallel vs sequential detection spawn.** Parallel is the better `Spawn` demonstration and
   the worse debugging story on a one-day build. Recommendation: get `Synthesize` working
   sequentially first, parallelize only if time remains.
2. **`Vigil` findings before or alongside the check-in input.** Before is a stronger autonomy
   demonstration and a worse daily-use experience.
3. **Whether `Concern` and `Violation` should merge.** They differ mainly in whether the trigger
   was a proposed action or an accumulated observation.
4. **Curated interaction pair count.** How many pairs is enough to be credible without being a
   day of data entry.

---

## 15. Reporting contract

When reporting progress, state:

- Which stage from section 9 is complete and which acceptance check passed.
- Any invariant from section 2 that the implementation currently violates, even temporarily.
- Any place a fourth `by llm()` call was needed and why.
- Current `recall@constraint` numbers once stage 5 exists.

If a request would require violating an invariant, do not implement it. Report the conflict.
