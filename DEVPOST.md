# Alongside

A longitudinal treatment companion for cancer patients, built end to end in Jac and deployed on JacHammer. Relevance is reachability, not similarity.

## Inspiration

My grandfather has been in an extended bout with cancer. He lives in the UK, so I see him every few years, and every time the difference is stark.

He doesn't notice.

That is not denial, and it is not memory failure. It is that he is living the slope. Day to day the change sits under the threshold of perception, and the person on the inside of a gradual decline is the last one positioned to see it. I only see the endpoints, which is exactly why the change is obvious to me and invisible to him.

The same blind spot runs through his care. Cancer patients collect prescriptions from oncology, primary care, and urgent care: clinicians who do not share notes. Two doctors each prescribe something safe. Nobody was in both rooms. Together they are not safe, and no system catches it. Meanwhile the symptoms that matter most happen between visits, go under-reported, and arrive at the appointment compressed into "I've been okay, I guess."

We wanted to build the thing that sees the endpoints and the slope at once: not to diagnose, and not to talk to anyone's doctor, but to help a patient advocate for himself with a record he actually has.

## The scale of the problem

This is not a niche inconvenience; it is a systemic failure that touches nearly every cancer patient, and it compounds with age.

### Fragmented care and dangerous combinations

- In 2022 there were roughly 20 million new cancer cases and about 9.7 million cancer deaths worldwide (GLOBOCAN 2022); in the United States alone there are about 2 million new diagnoses a year and roughly 18 million survivors living with the aftermath.
- The majority of new cancers occur in adults 65 and older, the same population most likely to be on many medications at once.
- Polypharmacy (five or more concurrent medications) is documented in a large share of older adults with cancer; systematic reviews commonly report prevalence above 40 percent, and some cohorts as high as 80 percent.
- Studies of cancer outpatients find that roughly one in four to nearly one in two carry at least one potentially significant drug interaction, and the prescribers who created them frequently cannot see one another's notes.

### Symptoms that never reach the visit

- Clinicians systematically under-detect what patients experience between appointments; research comparing clinician records to patient self-report finds a large fraction of symptoms, often cited near half, simply go unrecorded.
- This is not cosmetic. In a landmark randomized trial reported in JAMA, having patients report symptoms systematically during chemotherapy improved quality of life, reduced emergency visits, and extended median overall survival by roughly five months. The intervention was, in essence, capturing the between-visit signal that Alongside is built to capture.

### Adherence, cost, and the wrong assumption

- Adherence to oral anticancer therapy frequently falls below recommended levels, and financial burden is one of the leading drivers: a substantial share of patients report cost-related hardship that changes whether and how they take their medication.
- The clinical consequence of the wrong assumption is the whole point: skipping a dose because of cost is a completely different conversation from skipping because of a side effect, and the second is what tends to get assumed when the first goes unsaid.

Every one of these numbers describes a signal that exists but never arrives in the room. Alongside exists to carry that signal in.

## What it does

Alongside checks in every day, by typing or by voice, because the days when typing is hardest, fatigue, nausea, neuropathy, are precisely the days the entry matters most, and a tired day should not become a missing day.

It asks how you are doing and turns the vague, half-remembered answer into structure. A tingling hand becomes a dated observation. "The copay was rough" becomes the reason you skipped Tuesday, which, as above, is a completely different clinical conversation from skipping because of side effects.

Those check-ins are not stored to be searched later. They are wired into a graph, and the wiring is the memory. Everything you say attaches to the medications, symptoms, and instructions it is actually about. Remembering is a walk across those connections, not a guess at what reads similar, so every finding arrives with the path it came down and the sentence it came from.

That is the whole architectural bet, and it buys two classes of finding that similarity search cannot produce at any k:

### Convergence

Two drugs, from two prescribers, reaching the same toxicity through a shared vocabulary node. A triangle nobody was standing in the right room to see. The load-bearing example: `grapefruit -> CYP3A4 inhibitor -> CYP3A4 substrate -> imatinib`, a three-hop path that a keyword or embedding search would never assemble.

### Absence

A symptom with no attributing edge, a prescription with no adherence record, a gap in the check-in chain. A retriever cannot rank a document that does not exist; a graph can point at the edge that is missing.

The output is a page, not a message: "Questions for your care team," a standing document that accumulates and drains. Every row cites the exact sentence it came from. The system never sends anything to anyone. You carry it.

## How we built it

Jac end to end: graph, walkers, LLM calls, and UI in one language, deployed on JacHammer.

### The graph is the memory

Three node layers, deliberately separated. A provenance floor (`Utterance`, `Observation`) that is never scored or decayed; a ground-truth anchor layer resolved deterministically from a curated vocabulary; and a belief layer that is the only thing scored. That separation is what lets old beliefs sink below a retrieval waterline without ever touching the record of what was actually said.

### Two retrieval channels with different physics

Channel A, soft preferences and conventions, is a scored, beam-limited, decaying traversal. Channel B, hard constraints, is exhaustive, unscored, and exempt from decay, beam, budget, and waterline. Only an explicit `Supersedes` edge kills a Channel B constraint. A safety-critical fact must not compete for a slot with a preference about ginger tea.

### One organizing rule: autonomy on the write path, determinism on the read path

Exactly two `by llm()` sites exist in the entire system, both on the write path: extraction of free-text check-ins into a typed schema, and joint satisfiability of two natural-language constraints. The read path has zero. Every sentence the patient reads about their care is a template with graph-read slots, or a verbatim quote. The model never selects a traversal path, and it never writes prose about anyone's care.

We also refused a primitive on purpose. `visit [-->] by llm()`, letting the model choose where to walk, would have made retrieval probabilistic and voided the Channel B guarantee outright. It stays out.

### Shipped and tested

`Remember` (write path, extraction), `Recall` (two-channel traversal, detection mechanisms 1 through 4, corroboration, emergency bypass), `Investigate` (lazy case-file assembly: it walks the observation chain back to first onset, compares against regimen change dates, and looks for the counterfactual, all graph traversal and date arithmetic with no LLM call), and `Prepare` (renders the page). Roughly fifty tests cover the read path, MockLLM-first, so the suite never makes a network call.

### Jac and JacHammer: why the safety claim and the code are the same object

We did not reach for Jac to write a normal app faster; we reached for it because our entire thesis is only expressible in a language where the graph and the walk over it are first-class.

- Object-Spatial Programming made "retrieval" a `visit` traversal that carries its own provenance, so "relevance is reachability" is the literal control flow of `Recall`, not a slogan. Every other paradigm we considered would have forced the safety property to live in a library next to the code; Jac let it live in the code.
- The `by llm()` construct turned a two-call autonomy budget into a greppable invariant. "Keep the model on a leash" stops being a code-review aspiration and becomes `grep 'by llm('` returning exactly two hits.
- `jac check` type-checks the client and server seam, so a walker signature change lights up the exact client `root spawn` that drifted. It is the reason a three-person parallel build merged into one file mechanically instead of catastrophically, and it caught cross-boundary contract drift that a conventional TypeScript and mypy stack sees nothing of.
- Policy lives on the graph, not in a loop. `Recall` contains no `while` loop; scoring, gating, and the two channels are node-type abilities with inheritance, so behavior hangs off the node types themselves.
- JacHammer's git-native, browser-based runtime deployed graph, walkers, model calls, and UI as a single artifact, with no separate frontend and no separate Python service, against the same history a human works on. `main.jac` is a genuine single-file vertical slice: the data model, a real multi-hop traversal, a `by llm()` call, and the page UI, all in one file.

## Challenges we ran into

### Editing the schema is a landmine, and there is no shell to defuse it

In Jac, changing a persisted `node` or `edge` archetype invalidates existing graph data, and JacHammer's browser IDE has no shell to clear it. So freezing the schema became genuinely blocking: it could not land until we had proven and documented a reset path (the `jac clean --force` route, deleting the single SQLite graph file, and an in-app reset walker as a last resort). We front-loaded the freeze, batched every schema change behind one label, and announced resets. The lesson: treat the archetypes as a constitution, ratified once.

### Three people, one deliverable file

JacHammer rewards single-file full-stack apps, and three people cannot type one file at once. Jac's own answer, develop in five files and ship one, only works if four merge disciplines hold from the first commit: home-prefixed helpers, `root spawn` only, one stylesheet, and satellites importing solely from the schema module. We rehearsed the merge at the midpoint on a throwaway branch rather than discovering the problems at hour 22. We still hit a merge race and a branch tangle in the shared clone, and every single time the thing that told us exactly which line drifted was `jac check`.

### Refusing the easy sentence, every time

The strongest temptation in a system like this is that when a row of page copy reads awkwardly, you reach for `by llm()`. We never did, not once; awkward copy got fixed in the template, not generated. Holding a hard cap of two model calls took real discipline, and Jac is what made it enforceable rather than aspirational, because every model call is the literal token `by llm()`.

### Testing a thing that is not there

Half of what Alongside catches is absence, and you cannot fixture the document that does not exist. So we built a seeded adversarial patient, the day-9 QT convergence, where both convergence and absence have a known ground truth, and wrote the read-path tests against it.

### Voice on the hardest days

We reached the browser Web Speech API through Jac's JavaScript interop with no npm dependency and no new `by llm()` site; transcription is a platform call, not a model call. The final transcript lands in an editable field on purpose, so a mis-hearing can be corrected before it becomes the `Utterance` quoted back to you.

## Accomplishments that we're proud of

### The entire application is one file, in one language

`main.jac` is the graph schema, both `by llm()` sites, a real multi-hop traversal, the template registry, and the browser UI: no separate React app, no separate Python service, no ORM, no glue. Jac collapsed a stack that is normally five technologies into one, and we tagged the single-file artifact so it is citable.

### The safety claim is structural, not promised

Because Object-Spatial Programming makes traversal first-class, the central product claim and the implementation are the same object. Every finding carries the path it came down and the sentence it came from, and a missing edge is inspectable rather than silently absent.

### Two classes of finding similarity cannot produce

Convergence and absence, both falling directly out of modeling the domain as a graph in Jac instead of an index.

### Autonomy that is auditable, not trust-me

Two `by llm()` sites, both on ingest, read path zero, and we can prove it because Jac marks every model call in the syntax. We even refused a primitive, `visit [-->] by llm()`, and being able to show we left it out is itself an accomplishment.

### A record that fails visibly

The whole point of the grandfather story: a system that surfaces the slope by holding the endpoints, and that says "not in your record" instead of "safe."

## What we learned

### The endpoints-and-the-slope problem is the whole product

The person inside a gradual change is the last to see it; a record that holds the endpoints is a form of advocacy. Everything we built serves that one asymmetry.

### Object-Spatial Programming changes what retrieval means

Once traversal is a language primitive, you stop reaching for an embedding index and start asking "is it connected?", a question that fails visibly instead of silently. For a safety tool, visible failure is the entire game, and Jac is the first environment we used where the safe answer was also the idiomatic one.

### Marking LLM calls in the syntax turns a vibe into an invariant

A two-site cap is a rule the whole team can hold precisely because delegation to a model is a first-class, visible construct.

### jac check across the full-stack seam is a different kind of safety net

It sees contract drift between client and server that a conventional type stack cannot, and we leaned on it as the merge gate.

### Develop-in-five, ship-one is a methodology, not a hack

It works because Jac archetypes are flat within a module, so the final merge is concatenation plus deleting import lines. Pinned contracts plus stubs on the producing side meant three tracks moved at full speed and nobody waited.

## What's next for Alongside

- A permanent deploy. Sandbox deploys on JacHammer expire after seven days; the standing document a patient carries cannot.
- Closing the loop all the way. When a patient records what their team said, it re-enters the graph as an oncologist-role `Utterance`, which under deterministic severity typing becomes a hard constraint. The page's own output becomes the highest-authority provenance in the system.
- More vocabulary, real labels. Broaden the anchor vocabulary and interaction table, and ingest printed pharmacy labels and visit summaries directly, so authority always lives in the artifact, never in the model.
- A caregiver window. The person who sees the endpoints, me every few years with my grandfather, should get a read-only view of the slope, with the patient's consent and no new outbound path.
- Gentle trajectory surfacing over longer arcs, making the slope itself visible without ever crossing into alarm or diagnosis.
- The one thing that never ships: an outbound path. Alongside renders a page and the patient carries it. It will never message a clinician, and that stays a non-negotiable.

## Built With

Jac, JacHammer, Object-Spatial Programming, `by llm()`, browser Web Speech API, React (via Jac client codespaces), SQLite (Jac persistence).
