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

**Why Jac, and why JacHammer.** Every load-bearing property of Alongside is a Jac language feature we leaned on directly, not a library we bolted on. The full, feature-by-feature account is in _How we use Jac_ below.

## How we use Jac

Jac is not the implementation detail of Alongside; it is the reason Alongside can make the claim it makes. We did not port a design onto Jac. The design _is_ a set of Jac features, and in any other stack the central safety guarantee would have been something we tested for rather than something the language enforces. Here is how, feature by feature.

### The graph is the program (Object-Spatial Programming)

We model the entire clinical record as **nodes and typed edges**, and every act of remembering as a **walker traversing them**. A check-in is an `Utterance`; a measurement is an `Observation`; a medication or symptom is an `Anchor`; what we infer is a `Belief`, with `Preference` and `Constraint` as subtypes. Relationships are first-class, typed, and carry their own attributes:

```jac
node Belief { has claim: str; has strength: float = 1.0; has uses: int = 0; }
node Constraint(Belief) { has hard: bool = True; }          # inherits Belief

edge About:      Belief    --> Anchor { has weight: float = 1.0; }
edge Member:     Anchor    --> Anchor { has via: str; }       # the vocabulary lattice
edge Governs:    Constraint --> Anchor {}
edge Supersedes: Belief    --> Belief {}                      # the only thing that kills a constraint
```

In a conventional stack the "graph" is rows in a table plus a query planner you do not control, and "relevance" is whatever the planner or the vector index decides. In Jac the graph is the data structure and `visit` is the query, so **"relevance is reachability" is not a metaphor, it is the literal semantics of the program.** The load-bearing demo, `grapefruit -> CYP3A4 inhibitor -> CYP3A4 substrate -> imatinib`, is three `Member` hops, and the fact that it is a path is the entire point.

### Walkers are the compute model, and policy lives on the nodes

Each of our six behaviors is a `walker` archetype with its own typed `has` state and `report` channel. A walker does not run a loop over rows; it moves through the graph, and the graph decides what happens when it arrives. That is expressed with **node-type abilities**, and Jac's inheritance makes the safety rules fall out of the type hierarchy:

```jac
node Belief {
    can score with Recall entry {          # every belief scores the same way
        here.uses += 1;
        # ... beam, decay, waterline ...
    }
}
node Constraint(Belief) {
    can gate with Recall entry {            # a hard constraint hard-overrides
        # reached exhaustively in Channel B; a hit is an "ask", every time,
        # uncorroborated, exempt from decay and budget
        report Concern(kind="interaction", anchor=here.claim, action="ask");
    }
}
```

Because the policy sits on the node types, **`Recall` contains no `while` loop and no branching over "what kind of belief is this"**: one ability serves every belief, a second overrides for constraints, and the traversal wires itself. `with entry` and `with exit` abilities, `visit`, `report`, `here`, and `disengage` are the whole vocabulary, and they were exactly the right vocabulary for a retrieval engine whose correctness is about _where you can walk_.

### `by llm()`: autonomy as a first-class, countable construct

The model touches Alongside in exactly **two places**, and both are a single Jac keyword. `by llm()` delegates a function body to a model and hands back a **typed object**, so we never hand-parse JSON and never let free text leak past the boundary:

```jac
"""Turn a raw check-in into typed structure. Anchors are resolved against the
closed vocabulary afterward; a miss sets needs_review and invents nothing."""
def extract(text: str, at: str) -> Extraction by llm();     # write-path site 1

def satisfiable(a: str, b: str) -> Conflict by llm();        # write-path site 2, in Consolidate
```

This is where Jac quietly won the safety argument for us. "Keep the model on a leash" is normally a code-review aspiration; in Jac it is `grep 'by llm('` returning **exactly two hits, both on the write path**. We prompt-tune with `sem` and docstrings, we test every one of them with **MockLLM** so the suite makes no network calls, and `DEMO_MODE` branches at these two sites alone, which is why the entire demo runs with **zero live model calls**. And the primitive we most wanted to avoid, `visit [-->] by llm()`, letting the model choose where to walk, is a thing Jac _offers_ and we _refused_; being able to point at its absence is only possible because the language makes model-driven control flow a visible, first-class thing.

### Typed state that crosses the wire for free

Every archetype carries typed `has` fields, and our report objects (`Verdict`, `Concern`, `PageModel`, `Row`, `Citation`) are ordinary Jac `obj`s that **hydrate into typed instances on the browser side** when a walker `report`s them. There is no DTO layer, no serializer, no client-side schema we keep in sync by hand. The shape the walker builds is the shape the page renders.

### The full stack, in one language and one file

`main.jac` is a **mixed-context** module: server archetypes and walkers at the top, the client UI inside a `cl { }` block. The page is React written in Jac, a `def:pub` returning `JsxElement`, and it talks to the server the one blessed way, by spawning a walker with kwargs and reading its typed reports:

```jac
def:pub ConcernsPage() -> JsxElement {
    has model: PageModel = PageModel();
    async can with entry {
        result = root spawn Prepare(include_log=True);   # kwargs -> walker `has` fields
        model = result.reports[0];                        # typed PageModel, hydrated
    }
    return <section>{ for r in model.ask { <Row row={r} /> } }</section>;
}
```

There is **no REST layer we wrote, no `fetch`, no GraphQL, no OpenAPI**. The client and server share the same archetypes, so the contract between them is the type system, not a hand-maintained schema. Even the voice check-in stays in Jac: we reach the browser Web Speech API through Jac's JS interop (`new(...)`, `.call(None, ...)`, `globalThis`, `glob` module state), so there is no npm dependency and no separate JavaScript file.

### `jac check`: one type system across a seam nothing else can see

A single `jac check` type-checks the graph schema, the server walkers, and the client together. Change a walker's signature and the **exact** client `root spawn` line lights up, a class of contract drift a conventional TypeScript-plus-mypy stack is blind to because the boundary is a network call to those tools. This is also what made our "develop in five files, ship one" workflow mechanical rather than terrifying: Jac archetypes are **flat within a module**, so collapsing five files into `main.jac` is concatenation plus deleting import lines, and `jac check` is the gate that proves it still holds together.

### Persistence and isolation come from the language, not from us

Node and edge archetypes **persist automatically**, rooted per user on the built-in SQLite backend. We wrote no migrations, no ORM, no tenancy layer, and yet **per-patient isolation is total**: one patient's graph is unreachable from another's because there is no query surface on which the two could meet. A property we would normally have to build, audit, and pray about is, in Jac, simply the default.

### JacHammer: the whole thing ships as a single artifact

JacHammer took "single-file full-stack" from a slogan to the literal shape of the deliverable. It is a **git-native browser IDE** where graph, walkers, `by llm()` calls, and UI deploy as **one artifact** against the same history a human commits to. Configuration is a project-scoped environment variable (`DEMO_MODE` lives there and is read at process start), the client surface hot-reloads while server modules stay put, and a three-person, four-day fan-out lived in that one project without fracturing. No separate frontend host, no separate Python service, no container to orchestrate: one language, one file, one deploy.

**In short:** Jac let us write, in one language and one file, a graph database, a multi-hop retrieval engine, a bounded two-call LLM layer, and a browser UI, and it turned our central promise, _the model never decides what the patient reads or where the search walks_, from something we merely test into something the language makes true. We have shipped full-stack apps before. We have never shipped one where the architecture and the safety guarantee were the same object.

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
