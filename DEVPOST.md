# Alongside

A longitudinal treatment companion for cancer patients, built end to end in **Jac** and deployed on **JacHammer**. _Relevance is reachability, not similarity._

## Inspiration

My grandfather has cancer. I see him every few years, and the change is always stark. He doesn't notice, because he is living the slope: day to day the change sits below the threshold of perception, and the person inside a gradual decline is the last one positioned to see it. I only see the endpoints.

The same blind spot runs through his care. Patients collect prescriptions from oncology, primary care, and urgent care, clinicians who do not share notes. Two doctors each prescribe something safe; nobody was in both rooms; together they are not safe. Nearly half of patients on oral cancer drugs carry a potential interaction ([van Leeuwen et al., 2013](https://www.nature.com/articles/bjc201348)), and no one is watching for them. Meanwhile the symptoms that matter most happen between visits and arrive compressed into "I've been okay, I guess."

Alongside sees the endpoints and the slope at once: not to diagnose, not to talk to anyone's doctor, but to help a patient advocate for himself with a record he actually has.

## What it does

**Checks in daily, by typing or voice.** Typing is the default; voice is one tap for the days typing is the barrier (fatigue, nausea, neuropathy), because a tired day should not become a missing day. Voice uses the browser speech API into an editable field, and adds no model call.

**Turns the answer into structure.** A tingling hand becomes a dated observation. "The copay was rough" becomes the reason you skipped Tuesday, a completely different conversation from skipping over side effects, and the second is what gets assumed.

**The graph is the memory.** Check-ins are wired to the medications, symptoms, and instructions they are about, not stored to be searched. Remembering is a walk across those connections, so a concern surfaces only when it is _reachable_ from the anchor a check-in touches, where a vector index can only return the `k` nearest items by \\( \cos(q,d) \\), a set that cannot contain a fact that is not there:

$$\text{surfaced}(c)\ \iff\ \exists\ \text{path}(a \to c)\ \text{in the graph } G$$

That buys two findings top-`k` cannot produce at any `k`:

- **Convergence:** two drugs, two prescribers, one toxicity through a shared node. A three-hop path keyword or embedding search would never assemble:

```jac
# Channel B: exhaustive, unscored. Only a Supersedes edge kills a hard constraint.
# grapefruit -> CYP3A4 inhibitor -> CYP3A4 substrate -> imatinib
visit [-->:Member:->];
report Concern(kind="interaction", anchor=here.key, action="ask");
```

- **Absence:** a symptom with no attributing edge, a script with no adherence record, a gap in the check-in chain. _A retriever cannot rank a document that does not exist_; a graph points at the missing edge.

**The output is a page, not a message:** "Questions for your care team," a standing document that accumulates and drains. The severity ladder is the layout: an emergency is a full-screen alert shown first; "Ask about these" holds the hard concerns, "Worth mentioning" the softer ones, and "Also tracking," collapsed, holds what sank below the waterline (going quiet is not deletion). Every row cites the exact quote it came from, and expands into a case file back to first onset. When a patient records what their team said, that answer re-enters the graph as the highest-authority source. The system never sends anything to anyone. You carry it. Capturing that between-visit signal is not soft: in a randomized trial it extended median survival by about five months ([Basch et al., _JAMA_ 2017](https://jamanetwork.com/journals/jama/fullarticle/2630810)).

## The caregiver view

The person best positioned to see the slope is often the caregiver who sees the endpoints. A consented, **read-only** window onto the same page is another reader of the graph and **never a sender**. Designed, not yet shipped.

## How we built it

**Jac end to end:** graph, walkers, LLM calls, and UI in one language on JacHammer.

- **Three node layers:** a provenance floor (`Utterance`, `Observation`) never scored, a deterministic anchor layer, and a belief layer that is the only thing scored, so old beliefs sink below a waterline without touching what was actually said.
- **Two channels.** Channel A (soft preferences) is scored, beam-limited, decaying. Channel B (hard constraints) is exhaustive, unscored, and exempt from decay and budget; only a `Supersedes` edge kills it, and emergencies are evaluated first.
- **Six walkers, two model calls.** `Vigil` (unprompted on open), `Remember` (write, extraction), `Recall` (both channels, detection, corroboration, emergency bypass), `Consolidate` (self-budgeted rewrite, satisfiability), `Investigate` (lazy case file, no model call), `Prepare` (renders the page). Exactly two `by llm()` sites, both on the write path; the read path has zero. We refused `visit [-->] by llm()` on purpose: letting the model pick the path would void the Channel B guarantee. Roughly fifty MockLLM tests cover the read path.

**Why Jac, and why JacHammer.** Object-Spatial Programming makes traversal first-class, so "relevance is reachability" is the literal control flow, not a slogan; the safety property lives _in_ the code. `by llm()` makes a two-call autonomy budget a greppable invariant, and `jac check` catches client-and-server contract drift a TypeScript plus mypy stack cannot see. JacHammer deploys graph, walkers, model calls, and UI as **one git-native artifact**: `main.jac` is a real single-file full-stack slice, no separate frontend, no separate Python service, and per-patient isolation is a language property because there is no query surface on which two patient graphs could reach each other.

## What's real vs. seeded

| Piece | Status |
|---|---|
| Six walkers, two-channel traversal, detection, corroboration, emergency bypass, case file, page UI (typed and voice) | **Real**, covered by ~50 read-path tests, no model call on read |
| The two `by llm()` sites on the demo path | **Seeded:** `DEMO_MODE` returns precomputed results keyed to the seeded patient, so the demo makes zero live model calls |
| The patient | **Synthetic:** a seeded adversarial case (the day-9 QT convergence) |
| Permanent deploy, caregiver view | **Pending / designed** |

## Challenges we ran into

- **No shell to reset a graph.** Editing a persisted archetype invalidates data, and JacHammer's browser IDE has no shell, so we proved a reset path before freezing the schema and treated the archetypes as a constitution.
- **Three people, one deliverable file.** Jac's "develop in five files, ship one" only works if four merge disciplines hold from commit one; when a merge race hit anyway, `jac check` pointed at the exact drifted line.
- **Refusing the easy sentence.** Awkward page copy got fixed in the template, never generated; the two-call cap held because Jac makes every model call the literal token `by llm()`.
- **Testing absence.** You cannot fixture a document that does not exist, so we built a seeded patient with known ground truth for both convergence and absence.

## Accomplishments that we're proud of

- **One file, one language:** `main.jac` is the schema, both `by llm()` sites, a real traversal, the templates, and the UI.
- **A structural safety claim:** the product thesis and the implementation are the same object, and a missing edge is inspectable rather than silently absent.
- **Two findings similarity cannot produce,** convergence and absence, straight out of modeling the domain as a graph.
- **A record that fails visibly:** it says "not in your record" instead of "safe."

## What we learned

- The endpoints-and-the-slope problem is the whole product: a record that holds the endpoints is a form of advocacy.
- Object-Spatial Programming changes what retrieval means: you ask "is it connected?", which fails visibly instead of silently, and for a safety tool that is the entire game.
- Marking LLM calls in the syntax turns "keep the model on a leash" from an aspiration into an invariant, and `jac check` was our merge gate.

## What's next for Alongside

- **The caregiver view:** a consented, read-only reader of the graph, never a sender.
- **A permanent deploy:** a standing page cannot expire in seven days.
- **Closing the loop,** so a recorded answer hardens into a constraint the next traversal must respect.
- **The one thing that never ships: an outbound path.** Alongside renders a page and the patient carries it.

## Built With

`jac`, `jachammer`, object-spatial-programming, `by-llm`, web-speech-api, react (Jac client codespaces), sqlite (Jac persistence).
