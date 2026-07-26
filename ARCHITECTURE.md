# ARCHITECTURE

Build specification for **myCancerPal**. Written to be read by an implementing agent.

This file is **authoritative**. Where it disagrees with anything in `old_docs/`, this file wins and
the disagreement should be reported to a human.

**Target:** JacHacks SF. Tracks: Social Impact, Agentic AI, Best JacHammer.
**Deployment:** jachammer — a full-stack Jac web app running in the browser IDE.

---

## 1. What is being built

A **longitudinal treatment companion** for cancer patients and caregivers.

The patient checks in daily — **typed, or spoken aloud** — about how they feel and what they took. A
persistent Jac graph accumulates those check-ins as typed beliefs linked to deterministically-parsed
anchors. Two things run off that graph:

1. **An interaction gate.** Before any new substance enters the regimen, a mandatory graph
   traversal runs. If a hard constraint is violated, the action is blocked.
2. **Unprompted concern surfacing.** Every app open and every check-in re-runs detection and
   returns structurally detected concerns, each with a graded action.

**The deliverable is a page, not a message.** "Questions for your care team" is a standing
document that accumulates and drains — the thing the patient brings to their appointment. The
system never sends anything, never contacts a clinician, and never drafts outbound prose.

### The retrieval claim

**Relevance is reachability, not similarity.**

Top-k retrieval fails *silently*: a blocking fact ranked 11th is indistinguishable from a fact
that does not exist. Graph traversal fails *visibly*: if a constraint is connected to the anchor
it is reached, and if it is not reached the edge is missing — and a missing edge is inspectable.

This makes the central claim a **safety property**, not a retrieval improvement.

### The organizing rule

> **Autonomy on the write path. Determinism on the read path.**

The model decides what enters the graph. It never decides which path the traversal takes, and it
never writes a sentence the patient reads about their care. There are no exceptions to either.

---

## 2. Invariants

These are not preferences. An implementation that violates any of them is wrong regardless of
whether it runs. If satisfying a request would require violating one, **stop and report**.

### 2.1 Safety

| # | Invariant |
|---|---|
| S1 | The graph never originates a clinical fact. Authority lives in the parsed artifact: pharmacy label, printed instructions, visit summary. |
| S2 | Every `Violation` and every escalating `Concern` cites an `Utterance`. No source, no verdict. |
| S3 | Absence of a finding yields **"not in your record"**. Never "safe". |
| S4 | No dosing judgments. No substitutions. No dose calculations. No recommending discontinuation. |
| S5 | Emergency criteria are evaluated before scoring, drafting, or beam. Output is a full-screen "contact your team now", not a `Verdict`. |
| S6 | Channel A can never escalate. Soft beliefs shape output; they never alarm. |
| S7 | **No outbound communication path exists.** The system renders a page. The patient carries it. Nothing is drafted, sent, or transmitted to a clinician. |
| S8 | **Every sentence the patient reads about their care is a template with graph-read slots, or a verbatim quoted `Utterance`. Never generated.** This is what makes S1 structural rather than prompt-enforced. |
| S9 | **Dismissal mutes, never deletes.** A dismissed channel-B concern is hidden from the page but retained, and resurfaces if the anchor set changes. Otherwise dismissal becomes a way to void the guarantee. |

### 2.2 Architectural

| # | Invariant |
|---|---|
| A1 | **Anchors are never invented by `by llm()`.** Anchor creation requires vocabulary membership. A miss writes `needs_review = True` and creates no anchor. |
| A2 | **Channel B is unscored, unpruned, exempt from decay, beam, budget, and waterline.** The only thing that kills a channel B constraint is `Supersedes`. |
| A3 | **The model never selects a traversal path.** No `visit [-->] by llm()` anywhere. |
| A4 | **Embeddings appear only in the eval module.** No walker imports it. |
| A5 | **Corroboration promotes only.** Convergence may raise severity. It may never lower it. A channel B hit reaches `ask` uncorroborated, every time. |
| A6 | **Occlusion is never deletion.** Cold nodes keep `DerivedFrom` edges and sit below the waterline. |
| A7 | **`Observation` is never scored, occluded, or decayed.** It is reported fact on the provenance floor. |
| A8 | **The gate is mandatory, not a tool.** `Recall` runs before any action touching an anchor. It is not exposed as an optional ReAct tool. |
| A9 | **Only `Recall` reinforces.** `Vigil`, `Investigate`, and `Prepare` are strictly read-only. Reinforcement must be a function of usage, not of how many walkers we happened to write. |

**Exactly two `by llm()` sites exist** (section 8). Adding a third requires human approval.

---

## 3. Archetypes

Signatures are indicative. Section 12 governs syntax pitfalls.

```jac
node Utterance   { has text: str; has at: str; has role: str; }
node Anchor      { has key: str; has kind: str; }
node Observation { has metric: str; has value: float; has at: str; }
node Belief      { has claim: str; has strength: float = 1.0;
                   has last_used: str; has uses: int = 0;
                   has needs_review: bool = False; }
node Preference(Belief) { has polarity: float = 0.0; }   # -1 avoid .. +1 prefer
node Constraint(Belief) { has hard: bool = True; }
node Raised      { has kind: str; has anchor_key: str;
                   has status: str; has at: str; }        # open | asked | answered | dismissed
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
edge Regarding:   Raised      --> Anchor     { }
```

`Observation` also carries a `DerivedFrom` edge to its `Utterance`.

**Three node layers**, separated so the scored layer can be occluded without touching the others:

- **Provenance floor** — `Utterance`, `Observation`. Never scored, never occluded, never decayed.
- **Ground truth** — `Anchor`. Deterministically resolved, never inferred.
- **Belief** — `Belief`, `Preference`, `Constraint`. The only scored layer.

Node inheritance is load-bearing: one `can score with Belief entry` serves every subtype, while
`can gate with Constraint entry` hard-overrides.

`Member.via` is `"class_member"` or `"toxicity_of"`. `Member` is anchor-layer vocabulary structure:
unscored, unpruned, no decay, traversed in channel B as pure expansion. It exists because the
load-bearing traversal is `grapefruit → CYP3A4 inhibitor → CYP3A4 substrate → imatinib`, and the
hop is the demonstration.

### Report objects

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

`Concern.action` is one of `escalate | ask | mention | log`.

`Concern` is **derived fresh every turn**, so the page is always true and never stale. Status
persists separately as a `Raised` node, joined on render. A concern that stops being derivable
simply stops showing; its `Raised` marker stays as history.

### Anchor vocabulary

Resolved deterministically from vocabulary. None are invented by `by llm()`.

| `Anchor.kind` | Source | Example |
|---|---|---|
| `ingredient` | RxNorm ingredient RxCUI; brand→ingredient is a lookup | imatinib |
| `class` | ATC / EPC | `CYP3A4-substrate`, `NSAID`, `QT-prolonging` |
| `symptom` | CTCAE term | peripheral neuropathy |
| `lab` | LOINC / ICD-10 | neutropenia |
| `phase` | computed arithmetically from regimen start date | cycle day 10–14 |
| `food` | small closed set | grapefruit, alcohol, calcium |

`phase` is subtraction over a parsed date, not reasoning. It stays inside the "no temporal
reasoning beyond `Supersedes`" non-goal.

### Severity typing is deterministic

> A `Constraint` may be `hard == True` only if its `DerivedFrom` `Utterance` has `role` in
> `{oncologist, pharmacist, label}`. Patient- and caregiver-sourced beliefs default to soft,
> allergies excepted.

Severity is a **provenance read**, never a `by llm()` judgment. This structurally fixes the
highest-severity failure mode in the design — a `Constraint` mis-typed as a `Preference`, which
would silently downgrade channel B to channel A.

Consequence: `Preference.polarity` earns its place. "Ginger tea made it worse" (−1) and "cold
things help" (+1) are distinct facts. The cautionary case is oxaliplatin cold sensitivity — a
genuine hard constraint that presents as a temperature preference, and exactly the
misclassification the rule above prevents.

---

## 4. The six walkers

One topology, six behaviors, nothing in between them.

| Walker | Kind | `by llm()` | Reinforces |
|---|---|---|---|
| `Vigil` | read, unprompted, on app open | 0 | no |
| `Remember` | write, on check-in | #1 extraction | no |
| `Recall` | read — two channels, detection, corroboration | 0 | **yes — only this one** |
| `Consolidate` | rewrite, self-budgeted | #2 satisfiability | n/a |
| `Investigate` | read, case file, lazy per row | 0 | no |
| `Prepare` | read, renders the page | 0 | no |

**Turn sequence:**

```
app open   →  Vigil  →  Prepare  →  page
check-in   →  Remember  →  Consolidate  →  Recall  →  Prepare  →  page
row expand →  Investigate  →  case file
```

Sequential, single-threaded. This is deliberate: it eliminates reinforcement double-counting and
the read-after-write hazard between `Consolidate`'s budgeted `Conflicts` derivation and any
reader of those edges.

### `Vigil` — read, unprompted

- **Trigger:** app open, before any user input exists. Nobody asked for it.
- **Reads:** `Observation` timestamps, regimen anchor dates, instruction `Constraint`s.
- **LLM calls:** zero. Pure arithmetic.
- **Emits:** `Concern` at `mention` for adherence gap, silence, supportive-care gap, `phase`
  transition crossed.
- **Must not:** read beliefs, score anything, call `by llm()`, reinforce.

`Vigil` also dissolves the no-scheduler deployment constraint: opening the app is the trigger,
and opening the app is not a request.

### `Remember` — write

- **Trigger:** patient check-in submitted.
- **Input:** the check-in text comes from the check-in surface (§5) — **typed, or optionally dictated
  via the browser Web Speech API.** `Remember` receives a `str`; speech-to-text is a browser API,
  **not** a `by llm()` site (§8).
- **Writes:** `Utterance` (always), `Observation` (if a symptom value is present), `Belief` nodes
  from extraction, `DerivedFrom` and `About` edges.
- **LLM calls:** `by llm()` #1 — free-text patient language into a typed schema.
- **Guard (A1):** an extracted substance creates an `Anchor` only if it is present in the loaded
  vocabulary. On a miss: no anchor, belief written with `needs_review = True`, surfaced at
  `mention`, and the page states the substance was not recognized.
- **Also the loop-closure entry point.** When the patient records what their doctor said, that
  answer enters as an `Utterance` with `role = "oncologist"` — and under the severity-typing rule
  becomes eligible to be a hard `Constraint`. See section 5.

### `Recall` — read, the two-channel traversal

The file to open first when reviewing. Detection and corroboration live here, in node-type
abilities — not in separate walkers.

| Channel | Traverses | Beam | Budget | Decay | Occlusion | `Supersedes` |
|---|---|---|---|---|---|---|
| **A** — soft: preferences, conventions | `About`, `Relates`, `Shortcut` | yes | counted | yes | yes | yes |
| **B** — hard constraints | `Governs`, `Excludes`, `Member` expansion | **exhaustive, unpruned** | **exempt** | **exempt** | **exempt** | yes |

Channel B is affordable because constraint fan-out per anchor is small and bounded by the domain,
not by conversation length.

Note the last column. The carve-out covers decay, beam, and the waterline — **never**
`Supersedes`. A retracted constraint must still die, or the graph cannot be corrected.

Channel A is a greedy beam *per node*, not global best-first (the visit queue appends; candidates
get sorted inside each ability):

- at `Root` — resolve the anchor set deterministically from the request; visit each
- at `Anchor` — channel B: read `[edge here <-:Governs:<-]` and `<-:Excludes:<-`, expand `Member`,
  collect **all**, unscored. Channel A: read `[edge here <-:About:<-]`, score, visit top `beam`
- at `Belief` — superseded → `skip`; `budget -= 1`; exhausted → `disengage`; else collect, score
  `[edge here ->:Relates:->]` + `->:Shortcut:->`, visit top `beam`
- at `Root exit` — run detection, apply corroboration, assemble the `Verdict`, reinforce the
  **channel-A** trail only, `report` once

Channel B edges carry no weight, so there is nothing to reinforce on them. Exit abilities fire
LIFO post-order, so bottom-up aggregation comes free.

**Corroboration** (A5): two detection mechanisms converging on the same anchor promote severity by
one rung. Never demote. A channel B hit reaches `ask` alone, every time — requiring corroboration
before escalating a hard constraint would be a silent-failure generator, which is precisely what
the two-channel split exists to eliminate.

**Must not:** contain a `while` loop. Policy lives on node-type abilities.

### `Consolidate` — rewrite, self-budgeted

- **Trigger:** after `Remember`, same turn.
- **Plans its own work.** Conflict derivation is n² pairs at one LLM call each. It cannot run
  exhaustively and must not run randomly. Given a per-turn call budget, rank candidate pairs by:
  shared `Anchor` > reinforced this turn > cold. Skip pairs carrying a persisted `last_examined`
  marker. Spend until budget is exhausted. **Queue the remainder for the next turn.**
- **LLM calls:** `by llm()` #2 — joint satisfiability of two natural-language constraints, up to
  budget.
- **Writes:** `Conflicts` edges. Also reinforce bookkeeping, `Shortcut` promotion, occlusion.
- **Must not:** delete a node. Every consolidation operation is additive or marks state.

Bounded, self-directed, and persistent across runs. This is the strongest autonomy story in the
system and it is invisible unless surfaced — see the activity panel in section 7.

### `Investigate` — read, case-file assembly

Spawns **lazily**, when the patient expands an `ask`-level row. Steps, in order:

1. Walk the `Observation` chain back to first onset of the implicated `symptom` anchor.
2. Compare onset against regimen change dates.
3. Look for the counterfactual: days the drug was absent from the record, and whether the symptom
   was absent too.
4. Check for an existing instruction `Constraint` on that anchor. If one exists, the row changes
   from "report this" to "the instruction you were given covers this".
5. Assemble a dated timeline with every `Utterance` citation attached.

All graph traversal and date arithmetic. **No LLM call.** This is the difference between a
detector and a companion.

### `Prepare` — read, renders the page

Walks derived concerns, joins `Raised` status, groups by anchor, orders by the severity ladder,
and emits the page model. Zero LLM calls.

---

## 5. The concerns page

**"Questions for your care team."** This is the product.

The page is a **render of the graph**, not a generation from it. Every row is a `Concern` with its
evidence chain already attached, and the explanation is a template keyed on `Concern.kind` with
slots filled from the traversal.

Five consequences, all load-bearing:

1. **Zero LLM calls on the output path**, which is what makes "determinism on the read path"
   literally true with no exceptions.
2. **S7 is structural.** There is no outbound path to misuse — not even a drafted one.
3. **The severity ladder becomes visible UI hierarchy** rather than an internal enum.
4. **The patient page and the judge-facing traversal inspector are the same artifact** with a
   toggle.
5. `Prepare` goes from the first thing we would cut to the deliverable.

### The check-in surface — typing, with a voice option

Getting data *in* is where this product lives or dies. Every detection in section 7 — absence,
trajectory, the day-9 convergence — depends on the patient checking in **daily**, and the patient is
fatigued, nauseated, cognitively foggy, and sometimes has neuropathy that makes typing painful.
Lowering the cost of a check-in is therefore load-bearing, not cosmetic: it is the difference between
a graph that accumulates and one that goes silent — which is the exact failure the `silence` class in
section 7 exists to catch.

So the daily check-in **defaults to typing, with a one-tap voice option** for the days typing is the
barrier: a mic toggle, a live interim transcript, and on the final result the verbatim text is handed
to `Remember(text=…, role="patient", at=today)` — the same path a typed check-in takes.

- **No new `by llm()` site.** Transcription is the browser Web Speech API (§8). `Remember` sees only
  the resulting `str`; extraction (`by llm()` #1) is unchanged.
- **`role` is set by the flow, never by voice.** The daily check-in is `role="patient"`. The
  loop-closure "record what your team said" box (below) is the only place a clinical role is set, and
  that is an explicit, separate action — a spoken word never earns an authority role by itself.
- **Verbatim capture strengthens provenance.** The patient's own words become the `Utterance` quoted
  back under "Where this came from," so voice makes S2/S8 *better*, not weaker.
- **Lives in `page.cl.jac`, collapses into `main.jac`.** No separate component file and no
  `.style.css` annex (`CONTRACTS.md` §1a); the Web Speech API is reached through browser interop with
  no npm dependency. Interop mechanics are in `CLAUDE.md`.

### Row anatomy

Five parts, all read off the graph:

| Part | Source |
|---|---|
| **The question** — one sentence, patient's voice | template, keyed on `Concern.kind` |
| **Why it came up** | template with slots from the traversal |
| **What I've noticed** | `Observation` evidence, dated |
| **Where this came from** | `Utterance` citations with `role` |
| **Status** | `Raised.status` |

### Example rows

> **Is it okay that I'm taking ondansetron and levofloxacin at the same time?**
> Both can affect heart rhythm. Your oncology team prescribed ondansetron on Jul 3. Urgent care
> prescribed levofloxacin on Jul 20. Neither prescription mentions the other.
> *Where this came from:* pharmacy label (Jul 3) · "urgent care gave me something for a sinus
> thing" (you, Jul 20)

> **What's causing the tingling in my hands?**
> You've mentioned this 6 times since Jul 11. Nothing on your current medication list names it as
> a known effect — which is why it's worth asking about rather than assuming it's expected.
> *What I've noticed:* Jul 11, 13, 14, 17, 19, 22

> **I've been skipping doses because of cost.**
> You mentioned the copay on Jul 15. You haven't logged taking imatinib on 4 days since. There may
> be assistance options — but they can't offer them if they think it's a side-effect problem.
> *Where this came from:* "skipped Tuesday, short on the copay" (you, Jul 15)

> **Am I taking this the right way?**
> Your instructions say within 30 minutes after food. On 5 days you described taking it on an
> empty stomach.

### Sections

- **`escalate` never appears on the page.** It is a full-screen interstitial rendered *before* the
  page — "contact your team now." The page is for things that wait; escalations do not wait.
- **"Ask about these"** — `ask` level. Channel-B backed, provenance inline.
- **"Worth mentioning"** — `mention` level.
- **"Also tracking"**, collapsed — `log` level, below the waterline. One click demonstrates that
  occlusion is never deletion.

### The loop closure

Status runs `open → asked → answered`. When the patient records what their doctor said, that
answer enters the graph as an `Utterance` with `role = "oncologist"` — which, under the
deterministic severity-typing rule, makes it eligible to become a `Constraint` with
`hard == True`.

**The page's output re-enters the graph as the highest-authority provenance in the system.**
Severity typing stops being an ingest detail and becomes the product loop: a concern raised and
answered doesn't just close, it strengthens the graph, and the next traversal through that anchor
finds the answer as a hard constraint. `Supersedes` handles the case where the answer contradicts
an earlier instruction.

Cheap to build — a text box on an answered row calling `Remember` with `role="oncologist"`.
Reuses an existing walker entirely.

**Day-one cut line:** ship the page stateless — derived concerns, no `Raised`, no status. Status
and the loop closure land only if stage 4 completes on schedule. They rank above `Shortcut`.

---

## 6. Severity ladder

```
escalate  → channel B hit flagged emergency   → full-screen "contact your team now"
ask       → channel B hit, non-emergency      → top of page, provenance inline
mention   → channel A, or any absence-class   → "worth mentioning" section
log       → everything else                   → written to the graph, collapsed by default
```

Only channel B may produce `escalate` or `ask`. This is the channel-B carve-out applied to the
output side, and it is the **alert-fatigue control**: if everything surfaces, nothing does. Alert
fatigue is the documented failure mode of clinical decision support, and a system that cries wolf
is worse than no system.

---

## 7. Concern classes

Every class is detected structurally. If a concern can only be found by asking a model whether
something sounds bad, it is channel A and it caps at `mention`.

### Mechanism 1 — a path exists that should not

| Concern | Patient input | Signature |
|---|---|---|
| **Interaction** | "my neighbor gave me St. John's Wort" | new anchor → `Member(class_member)` → active regimen anchor, with `Excludes` on the path |
| **Additive toxicity** | *(nothing — invisible to the patient)* | two active `ingredient` anchors both → `Member(toxicity_of)` → the **same** `symptom` anchor |

Additive toxicity is a **triangle**. Two prescribers, one shared toxicity, nobody compared them
because nobody was in both rooms. **This is the headline detection.** It is a class of result a
similarity index cannot produce at any *k*.

The pairwise interaction check is table stakes — a dictionary lookup does it. Build it; never lead
with it.

### Mechanism 2 — a path is missing that should exist

Unique to this design: absence of an edge is inspectable, absence of a top-k hit is not.

| Concern | Signature | Note |
|---|---|---|
| **Unattributed symptom** | `symptom` anchor with **no** `toxicity_of` edge from any active drug | new and unexplained ⇒ *more* urgent, not less |
| **Supportive-care gap** | `symptom` anchor has an incoming instruction `Constraint` but no `Observation` of adherence | the prescription that was never filled |
| **Adherence gap** | regimen anchor with no `Observation` referencing it for N days | |
| **Silence** | gap in the `Observation` chain | a patient who feels worst stops writing |

Expectation comes from the **parsed regimen**, not inference: what should be happening is ground
truth, what is happening is observed, and the gap is set difference.

`Silence` is the silent-failure argument in the time dimension — missing check-ins look identical
to improvement, and only the structure makes that visible. **A retriever cannot rank a document
that does not exist.** This is the mechanism to lead with.

### Mechanism 3 — accumulated `Observation` crosses a stated threshold

| Concern | Signature |
|---|---|
| **Persistence** | symptom ≥ level L for D days, where L and D are parsed from the patient's own instructions into a `Constraint` |
| **Trajectory** | monotone worsening across cycles on an anchor the label marks cumulative |
| **Emergency** | `Constraint` on a symptom/lab anchor flagged emergency; evaluated first, bypasses everything |

Thresholds are parsed, never recalled by the model. **Trajectory is where dose concern legitimately
lives**: the output is *"worth raising at the next visit, here is the record"* — never a dosing
conclusion.

### Mechanism 4 — two stated things contradict

| Concern | Example |
|---|---|
| **Instruction drift** | regimen says "within 30 minutes after food"; patient says "whenever I remember" |
| **Cross-prescriber conflict** | two `Constraint`s from two clinicians, jointly unsatisfiable |
| **Cause of nonadherence** | "I skipped Tuesday, I was short on the copay" |

Nonadherence cause is not a footnote. *Missed for cost or transport* and *missed for toxicity* lead
to different clinical action, and the second is what gets assumed. Carrying the cause onto the page
is plausibly the highest-value row the system produces.

---

## 8. `by llm()` census

**Exactly two sites.** A third requires human approval.

| # | Location | Why an LLM is correct |
|---|---|---|
| 1 | `Remember` | free-text patient language into a typed schema |
| 2 | `Consolidate` | joint satisfiability of two natural-language constraints |

Both are on the **write path**. Neither writes anything the patient reads.

Note on counting: site ≠ call. Site 2 runs up to its per-turn budget. State "two sites", not "two
calls" — the distinction will be checked.

### Seven places that must not have one

| Location | Why not |
|---|---|
| anchor resolution | vocabulary lookup; an LLM here puts extraction error at the head of every traversal |
| severity typing | read off `Utterance.role` |
| path selection | structural; violates A3 |
| threshold evaluation | arithmetic over parsed values |
| absence detection | set difference against the parsed regimen |
| emergency bypass | parsed flag, evaluated before anything else runs |
| **page copy** | **template-or-quote per S8. This is the one an agent will try to "improve".** |

**Note — speech-to-text is not an eighth site.** The voice check-in (§5) transcribes audio to a `str`
with the browser Web Speech API, a platform capability, not a model call. It is outside this census
and does not count against the two-site cap.

### Jaseci primitive usage

Used: Extract (×2), Spawn, Pipe, Loop.
**Refused: Route.** `visit [-->] by llm()` would make retrieval probabilistic and void the channel
B guarantee. This refusal is deliberate and belongs in the writeup — it is not a gap to fix.

---

## 9. Deployment — jachammer

Target is a **full-stack Jac web app** running in jachammer, Jaseci Labs' browser-based Jac IDE.

**The platform is `jachammer.ai`.** `jachammer.com` is an unrelated parked domain.
**Our project:** `https://jachammer.ai/project/db1341cc-5649-47d0-b5fb-15f8c00213ca`

### Verified on the live project (#27, #30)

Everything in this table was checked in the running IDE, not read from docs.

| Capability | Finding | Consequence for us |
|---|---|---|
| **Git** | Real git repo, `origin` wired to our GitHub repo, branches and remotes in the Source Control panel. **Full round trip verified in both directions** — a GitHub merge appears in the IDE's history, and an IDE commit (`33f3484`, which created `jac.toml`) reached `origin/main`. | **The `CONTRIBUTING.md` workflow works as written.** This was the biggest risk to the collaboration plan; it is resolved. |
| **GitHub auth is a separate step** | Adding the remote URL is *not* enough. Push needs an OAuth grant via **Connect GitHub** in the Sync panel. Before it, the panel shows a remote and still cannot push. | A half-wired remote looks identical to a working one until someone tries to push. Check for the account link, not just the remote. |
| **Environment variables** | **Project scope only** — the panel offers `PROJECT · Environment` and `USER · AI Keys`, and no global scope. Values are stored **encrypted**. Sourced into the process **at start**: saving prints *"STOP and START the preview for the changes to take effect."* | **`DEMO_MODE` has a clean home** and cannot leak across projects. **Never read it into a `glob`** — globs evaluate once at boot. Read it inside the ability, per `CONTRACTS.md` §6. |
| **Deploys** | **Sandbox**: free, 7-day TTL, shareable, available on the current plan. **Permanent** ("Production"): a public URL with scaling, and it is **gated behind a paid upgrade**. | The account is on **FREE**, not Pro. See the correction below. |
| **Client UI** | `cl { }` is available and the preview pane serves it. | The concerns page is buildable. |

**Correction to a load-bearing assumption.** This section previously stated "Pro allows 15 sandbox + 3
permanent". **The account is on the FREE plan** and Production reads *"Upgrade to deploy"* — there are
zero permanent deploys available today. The upgrade is now a hard prerequisite in #28 rather than a
background assumption.

**Correction on model access.** `USER · AI Keys` reports *"No provider keys saved."* Platform credits
appear to cover the JacHammer build assistant, **not `by llm()` calls from our running app**. Until a
provider key exists as a project env var, `DEMO_MODE` is not a convenience — it is the only way the
demo runs.

### Resolved since this section was written

| Was unresolved | Answer |
|---|---|
| **Graph reset with no shell** | **Three paths, all verified — see `CLAUDE.md`.** `jac clean --force`; or delete the single SQLite file `.jac/data/<project>.db` (no shell needed); or an in-app reset walker. **And it matters less than assumed:** archetype edits do *not* produce `NodeAnchor ... is not a valid reference!` on Jac 0.16.7 — field add/remove/retype and edge changes get a best-effort load, and a renamed archetype is quarantined while the app keeps running. A schema change costs a **re-seed**, not a recovery. |
| **npm deps / styling** | The live `jac.toml` has **no `[jac-shadcn]`** → the plain-CSS path is confirmed for #20. It also has **no `[serve]`, no `kind`, and no `[dependencies.npm]`**, which is a problem of its own: on a config like that the Vite dev server fails to start and **nothing is served**. See #17. |
| **Preview reload behavior** | **HMR is real** on `.cl.jac` files; server modules need a full restart. **Open decision 2 in §18 resolves in favour of keeping `page.cl.jac` split out** until the final merge. |

### Still unresolved

| Constraint | Effect |
|---|---|
| **Typed report objs across the `cl { }` seam** | `root spawn` reaches the walker and the server returns 200, but the browser client cannot hydrate the typed report obj. Declaring the obj beside the `cl { }` block emits the class twice and breaks the build; declaring it in a separate module leaves the client with nothing to hydrate into. **`spike/` is a live reproducer.** This is the top remaining build risk, and it also threatens the single-file merge in `CONTRACTS.md` §1a. |
| **No filesystem** | The vocabulary must be an inline `glob` in Jac. `data/*.json` cannot exist. A requirement, not a preference — and it leaves the repo with **zero non-Jac artifacts**. |
| **No local CLI** | `jac browse` is unavailable *inside jachammer*; UI verification there is manual in the preview pane. It does work against a local `jac start`, which is where acceptance checks should run. |

No scheduler, cron, or background sweep is available or needed. `Vigil` on app open is the trigger.

---

## 10. Repo layout

**Five files while building. One file at submission.** Ownership and the merge procedure are in
`CONTRACTS.md` sections 1 and 1a — read that before writing a line.

```
graph.jac       Laksh    nodes, edges, report objs. Nodes/edges FROZEN after #1.
write.jac       Bryan    Remember (by llm() #1), Consolidate (by llm() #2),
                         vocabulary glob, regimen parse, seed patient, DEMO_MODE
read.jac        Nathan   Recall (channel A + B, detection, corroboration), Vigil,
                         Investigate, eval harness, QUARANTINED cosine baseline
main.jac        Laksh    Prepare, template registry, imports, cl { } mounting the page
page.cl.jac     Laksh    concerns page, rows, activity panel, typed/voice check-in, inspector
jac.toml        Laksh    [serve] base_route_app = "app"
styles/global.css Laksh  the one stylesheet. No .style.css annexes — see CONTRACTS §1a.
```

**Every file has exactly one owner**, which is what makes merge conflicts structurally impossible
rather than merely discouraged. Every file is Jac. Python appears only as libraries imported into Jac.
No separate Python service, no separate React app.

`page.cl.jac` is split out for exactly one reason: **HMR reloads only `.cl.jac` files**, server
modules need a full restart, and the page is what gets iterated on most. It merges into `main.jac` at
the end.

**The quarantined baseline is a weak point of the collapse.** `eval/baseline.jac` used to be a
separate file so that "never imported by a walker" was structurally true. Inside `read.jac` alongside
`Recall` it becomes a comment fence. Fence it loudly; if it ever gets referenced from traversal code
the eval numbers are worthless.

### `main.jac` at submission is the vertical slice

The rubric names four things: `by llm()`, walkers, graph-native data modeling, and **single-file
full-stack development**. After the final merge, `main.jac` demonstrates all four **in one file**:

```
main.jac
├── archetypes            graph-native data modeling
├── Remember              a walker, carrying by llm() #1
├── Consolidate           a walker, carrying by llm() #2
├── Recall                a real multi-hop traversal with detection
├── Prepare               page-model assembly
└── cl { }                the concerns page UI
```

This is the genuine entry point, not a demo prop. Open it at the end of the demo and every word of
the claim is true of what is on screen.

**Claim the artifact, not the history.** Building in modules and consolidating before submission is
ordinary engineering; the deliverable is what gets judged. Do not imply the repo was ever one file
during development.

**Mechanics, verified against the Jac guides:**

- `main.jac` is a **mixed-context** file: server code at top level (server is the default
  context), client code inside a `cl { ... }` block.
- `def:pub` / `walker:pub` endpoints may live in `main.jac` — it is one of the three valid homes.
- The client calls a walker with `result = root spawn Prepare(...)`; **kwargs** map to the
  walker's `has` fields, and everything reported lands in `result.reports`.
- **Use walker spawn, not function RPC**, for client→server calls in this file. Function RPC is
  positional-only (kwargs → 422), and it is the path carrying the caveat that an `sv import` inside
  the entry module's own `cl { }` block does *not* register the endpoint. Walker spawn sidesteps
  that entirely.

Precision for the writeup: the claim is **one code file**, not one file on disk. `jac.toml` is
unavoidable — `[serve] base_route_app = "app"` is what serves the client at `/`.

---

## 11. Build order

Each stage has an acceptance check. Do not advance until it passes.

| # | Stage | Acceptance check |
|---|---|---|
| 1 | Archetypes + persistence | Graph survives a restart. Retrieval stubbed to "return every belief". |
| 2 | Anchor ingestion | Pasted med list produces correct `ingredient` anchors. Vocabulary `glob` produces `Member` edges. **Zero anchors created outside vocabulary.** |
| 3 | `Remember` | Check-in writes `Utterance` + `Observation` + beliefs with `DerivedFrom` intact. Unknown substance produces `needs_review`, not an anchor. |
| 4 | `Recall` channel B | Seeded blocking constraint two hops out on a cold edge is returned **every** run. Emergency bypass fires before anything else. `allowed == false` blocks. |
| 5 | `Prepare` + concerns page | Page renders `ask` / `mention` / `log` sections from derived concerns. Every row cites an `Utterance`. Zero LLM calls on render. |
| 6 | Seed + baseline + metric | `recall@constraint` reported for traversal vs cosine top-5 vs top-10 over ~30 seeded requests. |
| 7 | `Conflicts` | Additive-toxicity triangle detected on the seeded graph. Cross-prescriber conflict detected. |
| 8 | `Recall` channel A | Beam, budget, decay, reinforcement. Context size at or below the top-k baseline. |
| 9 | Inspector toggle | Two-pane render: cosine vs traversal, same request, visible disagreement. Provenance click-through works. |
| 10 | `Shortcut` | Repeated path collapses to a `Shortcut` edge. |

**Agentic walkers**, slotted by dependency:

| Walker | Earliest | Priority |
|---|---|---|
| `Vigil` | after 3 | **HIGH** — buys the autonomy claim for almost nothing |
| `Investigate` | after 4 | **HIGH** — the difference between a detector and a companion |
| `Raised` status + loop closure | after 5 | medium |

**Drop order if the schedule slips:** `Shortcut`, then channel-A reinforcement, then
`Investigate`'s counterfactual step (step 3), then channel A entirely.

**Never cut `Prepare` or the concerns page.** It is the deliverable.

---

## 12. Jac implementation gotchas

Read before writing any Jac. Fuller treatment in `CLAUDE.md`.

- **Edge abilities are a silent no-op.** `can ... with Walker entry` inside an `edge` compiles
  clean and never fires. All scoring lives in walker node abilities reading `[edge ...]`.
- **Editing archetypes costs a re-seed, not a recovery** (measured in #30 on Jac 0.16.7). Field
  add/remove/retype and edge changes get a `schema drift ... best-effort load`; a renamed archetype
  is quarantined and the app keeps running. **It is silent data loss, not a crash.** Reset with
  `jac clean --force`, or delete the one file `.jac/data/<project>.db` — which is the jachammer
  path, since it needs no shell. Three routes in `CLAUDE.md`.
- **`++>` returns a list.** `b = (anchor ++> Belief(claim=c))[0];`. A missing `[0]` fails somewhere
  else entirely.
- **Typed edge deletion needs `[edge ...]` plus iterate-`del`.** `del [a ->:Supersedes:-> b];`
  passes `jac check` and fails at runtime with E5043.
- **`by llm()` returns `obj`, never `node`.** Extract into an obj, copy into the node.
- **Report once from `with Root exit`.** Per-node reporting scatters N tiny reports.
- **Type the report channel:** `has verdict: Verdict = Verdict();`. Omitting the default makes it a
  required spawn parameter and every spawn fails E1050.
- **Declare endpoints on every edge.** Untyped edges yield `Unknown`-typed nodes that pass
  `jac check` and fail later.
- **Edge creation is where the intelligence lives.** Substring or keyword matching to link beliefs
  will look correct on the first three nodes and quietly poison every traversal after.

---

## 13. Evaluation

**Seed graph.** One synthetic patient, three weeks of check-ins, four to six `ingredient` anchors
from two prescribers, vocabulary slice sufficient for the `Member` hops. Hand-built, loaded at
start. **Not extracted live.**

**Adversarial case.** Seed the QT convergence so a similarity retriever cannot reach it: the
check-in text is about a sinus infection, the shared `symptom` anchor is two `Member` hops from
either drug, and there is no lexical overlap between input and constraint.

**Report:**

```
recall@constraint       traversal vs cosine top-5 vs top-10, ~30 seeded requests
absence-class recall    mechanism 2 only; the baseline scores structurally zero
context size            beliefs delivered per request
failure attribution     misses from a missing edge (inspectable) vs from rank (silent)
```

**Lead with absence-class recall.** A retriever cannot rank a document that does not exist.

**State the caveat in the same breath:** the seed set was built by the people who designed the
traversal, and the adversarial case was placed on purpose. It demonstrates a failure mode. It does
not establish general superiority.

---

## 14. Demo spine

Three minutes. **No architecture vocabulary until the last beat** — no anchor, channel, walker,
traversal, node, or edge before beat 5.

| # | Beat | Time |
|---|---|---|
| 1 | Regimen parse: the patient's medication list becomes structure | 25s |
| 2 | `Vigil` speaks first. Open the app to log nausea; the page already raises an adherence gap, unprompted | 20s |
| 3 | The sinus-infection check-in (typed by default; the voice toggle shown in passing). Split pane: similarity search finds nothing, traversal reaches the shared toxicity from two directions | 75s |
| 4 | Expand the row: `Investigate` case file, provenance click-through to source sentences | 30s |
| 5 | `main.jac` on screen. One file: the graph, the walkers, the AI, the UI. Primitive census, refusal of Route | 30s |

**Opening line:**

> Two doctors each prescribed something safe. Nobody was in both rooms. Together they are not
> safe, and there is no system that catches that.

**Closing line:**

> Most agents decide how to search. This one decides what to tell you before you ask.

**Demo deliberately:** a substance not in the vocabulary. The system must say *"not in your
record"*, never *"safe"*. This scores as graceful edge-case handling.

**Do not demo:** live extraction latency, trend charts, multi-week timeline scrolls, or any screen
where the model decides something safety-relevant.

### `DEMO_MODE`

With the flag set, the app runs entirely off the seeded graph with **zero live LLM calls**. Both
`by llm()` sites branch on it and return pre-computed results keyed to the seeded utterances. The
concerns page needs no branch — it never calls a model.

Acceptance: with the flag set and the network disconnected, the full demo spine runs end to end,
and output is byte-identical across three consecutive runs.

**Voice + `DEMO_MODE`.** The demo types the check-in by default — reliable on stage and offline. The
voice toggle is optional and needs connectivity (browser STT is a network call), so do **not** use it
during the offline byte-identical acceptance run. If you do demo voice live, the mic fills an
**editable** field; keep it editable so a mis-transcription can be corrected before submit —
`DEMO_MODE` keys fixtures on the exact canonical `Utterance.text`, so the submitted string must
match.

### Activity panel

`Consolidate`'s planning and the corroboration merge are the strongest depth stories and both are
invisible without this. After each turn, log what the system did unasked:

```
Vigil ran before input: 3 checks, 1 finding
Consolidate examined 6 of 34 constraint pairs, 28 queued
Corroboration promoted 1 finding
Investigate assembled a case file across 9 observations
```

Counts are read from walker report payloads. **Do not add walker logic to produce them** — they
already exist as internal state.

---

## 15. Do not build

- Patient-facing trend charts or timeline visualizations. They cost real time, invite the dosing
  question S4 forbids, and score nothing. The inspector toggle is a different artifact and is kept.
- **Any outbound path.** No email, no messaging, no portal integration, no MCP send. The page is
  the artifact. (Portal-ready formatting for copy-paste is fine; transmission is not.)
- A separate Python backend service. A separate React frontend.
- Any scheduler, cron, or background sweep.
- Multi-user or auth beyond the default per-root isolation.
- Lossy summarization or compression of beliefs. Occlusion and the channel-A budget already prune
  losslessly; summarization is the only operation capable of destroying a fact the guarantee
  depends on.
- Temporal reasoning beyond `Supersedes`.
- A live drug-interaction API integration. See section 16.
- Detection walkers. Detection lives in `Recall`'s node abilities.

---

## 16. Data sources

- **RxNorm** (public) for ingredient RxCUIs and brand→ingredient normalization.
- **ATC / EPC** for class membership.
- **Interactions:** NLM retired the RxNav drug-interaction API in early 2024. Use a hand-curated
  table of oncology-relevant pairs sourced from labels, inlined as a Jac `glob`. **State the pair
  count and cite a source per pair.** A vague claim of using a live interaction API invites a
  question with no good answer.
- **Thresholds and instructions:** parsed from the patient's own artifact only.
- All of the above arrive as passed-in content or inline `glob`s. No local-path reads — the
  deployment target has no filesystem guarantee.

### Domain grounding

The problem this targets is real and documented: patients systematically under-report toxicity
between visits, which is why the PRO-CTCAE instrument exists at all. There is a well-known
randomized trial (Basch et al.) showing web-based patient-reported symptom monitoring during
chemotherapy improved quality of life, reduced ER visits, and in follow-up improved overall
survival. **That is the evidence base the pitch should rest on. Verify the exact figures against
the primary source before quoting them** — the finding is real; the numbers must not come from
recollection.

Adjacent well-documented problems this design targets: fragmented prescribing across oncology,
primary care, and urgent care with no one holding the complete list; the shift to oral anticancer
agents making the patient the administrator; and financial toxicity as a driver of nonadherence
that gets misattributed to side effects.

---

## 17. Known limits

State these; do not hide them.

- **Belief extraction quality bounds the belief layer.** The anchor layer is parsed, so this no
  longer compounds through the entry point, but a belief that is never extracted is never reached.
- **The guarantee is conditional on the edge existing.** "If a constraint is connected to the
  anchor, it is reached" says nothing about a constraint that was never linked. Edge creation is
  where the risk concentrates.
- **The regimen parse bounds everything.** A drug absent from the parsed list has no anchor, so no
  path reaches it.
- **Curated interaction coverage is partial by construction.** The system must never imply that
  silence means no interaction exists.
- **Patient-reported severity is unvalidated.** `Observation.value` is a self-rating, not a
  clinician-assigned CTCAE grade, and thresholds parsed from instructions assumed the latter.
- **Absence-class detection assumes engagement.** Silence detection mitigates but does not solve
  this; a patient who stops using the app entirely is outside the system.
- **Channel A is a greedy beam, not optimal search.** Channel B is exhaustive and carries no such
  caveat.
- **Contradiction handling is one edge type, not a temporal model.** Proper bitemporal invalidation
  is a research problem; `Supersedes` is the cheap correct-looking version.
- **Voice sends audio off-device.** The browser Web Speech API transcribes via a third-party service
  (e.g. Google for Chrome). This is an accepted prototype tradeoff, not a clinician-outbound path, so
  S7 still holds; a production build would move to on-device transcription. State it; do not hide it.
- **Speech recognition is browser-dependent.** Web Speech API is supported in Chromium and Safari,
  not Firefox, and needs connectivity. The check-in surface must fall back to typing when it is
  unavailable.

---

## 18. Open decisions

Do not resolve these autonomously. Surface them and wait.

1. **How many curated interaction pairs** is enough to be credible without being a day of data
   entry.
2. **Whether the whole app collapses into `main.jac`** — depends on how jachammer's preview
   handles reloads (section 9).
3. **Whether `mention`-level concerns decay.** They are channel A, so scoring says yes, but an
   unresolved appointment-prep item arguably should not cool off before the appointment. Current
   answer: they do not decay; they persist until `Prepare` marks them consumed.

### Verify before claiming

Three things asserted in these docs that have not been checked. **Do not say any of them on stage
until confirmed.**

1. **The Jac share floor.** Confirm how the organizers measure the Jac ratio, and whether
   Python-as-imported-library counts.
2. **Jaseci primitive names.** Extract, Generate, Invoke, Route, Pipe, Loop, Spawn are taken from
   the Jaseci agentic-AI tutorial. Confirm against current workshop material.
3. **Native OSP persistence.** A prior winning project fell back to a JSON store because
   property-graph persistence was unstable on their Jac build. If ours runs on native OSP, that is
   a real differentiator — verify before saying it.
