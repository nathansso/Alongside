# Alongside

A longitudinal treatment companion for cancer patients, built end to end in **Jac** and deployed on **JacHammer**. _Relevance is reachability, not similarity._

## Inspiration

My grandfather has been in an extended bout with cancer. He lives in the UK, so I see him every few years, and every time the difference is stark.

He doesn't notice.

That is not denial, and it is not memory failure. It is that he is living the slope. Day to day the change sits under the threshold of perception, and the person on the inside of a gradual decline is the last one positioned to see it. I only see the endpoints, which is exactly why the change is obvious to me and invisible to him.

The same blind spot runs through his care. Cancer patients collect prescriptions from oncology, primary care, and urgent care: clinicians who do not share notes. Two doctors each prescribe something safe. Nobody was in both rooms. Together they are not safe, and no system catches it. Meanwhile the symptoms that matter most happen between visits, go under-reported, and arrive at the appointment compressed into "I've been okay, I guess."

We wanted to build the thing that sees the endpoints and the slope at once: not to diagnose, and not to talk to anyone's doctor, but to help a patient advocate for himself with a record he actually has.

## The scale of the problem

This is not a niche inconvenience; it is a systemic failure that touches nearly every cancer patient, and it compounds with age.

- **The burden is enormous and rising.** There were about **20 million new cancer cases and 9.7 million deaths worldwide in 2022** ([GLOBOCAN 2022, via UICC](https://www.uicc.org/news-and-updates/news/globocan-2022-latest-global-cancer-data-shows-rising-incidence-and-stark); [Bray et al., _CA: A Cancer Journal for Clinicians_, 2024](https://acsjournals.onlinelibrary.wiley.com/doi/full/10.3322/caac.21834)).
- **Older patients carry the most medications.** Polypharmacy, five or more concurrent drugs, is found in roughly **38%** of older cancer patients in one meta-analysis and in **over 60%** of some cohorts ([Frontiers in Pharmacology, 2022](https://www.frontiersin.org/journals/pharmacology/articles/10.3389/fphar.2022.1044885/full); [_The Oncologist_ meta-analysis](https://academic.oup.com/oncolo/article/25/1/e94/6443068)).
- **The combinations are dangerous, and nobody is watching them together.** Among patients on oral anticancer drugs, **46% had at least one potential drug interaction and 16% a major one**; across studies the rate runs **27% to 58%** ([van Leeuwen et al., _British Journal of Cancer_, 2013](https://www.nature.com/articles/bjc201348)).
- **The between-visit signal is lost.** In a multicenter European study, physicians underestimated **fatigue in 51%** of patients, **muscle cramps in 49%**, and **musculoskeletal pain in 42%** ([Laugsand et al., _Health and Quality of Life Outcomes_, 2010](https://link.springer.com/article/10.1186/1477-7525-8-104)).
- **Cost quietly rewrites the regimen.** Between **17% and 30%** of patients report nonadherence to oral cancer therapy, higher financial burden roughly **doubles** the odds, and in one survey **22% did not fill a prescription because of cost** ([Bestvina et al., _JCO Oncology Practice_](https://ascopubs.org/doi/10.1200/JOP.2014.001406); [NCI Financial Toxicity PDQ](https://www.cancer.gov/about-cancer/managing-care/track-care-costs/financial-toxicity-hp-pdq)).

And capturing that signal is not a soft benefit. In a randomized trial, patients who self-reported symptoms during chemotherapy lived a **median 31.2 months versus 26.0**, about **five months longer**, with better quality of life and fewer emergency visits ([Basch et al., _JAMA_, 2017](https://jamanetwork.com/journals/jama/fullarticle/2630810); [ASCO Post](https://ascopost.com/issues/june-25-2017/online-self-reporting-of-symptoms-improves-quality-of-life-extends-survival/)).

Every one of these numbers describes a signal that exists but never arrives in the room. Alongside exists to carry that signal in.

## What it does

### The daily check-in, by typing or by voice

Alongside checks in every day. Typing is the default; voice is a one-tap option, because the days when typing is hardest, fatigue, nausea, neuropathy, are precisely the days the entry matters most, and a tired day should not become a missing day. Voice runs through the browser's own speech API, with the transcript dropped into an editable field so a mis-hearing can be fixed before it is saved. It adds no model call.

### The graph is the memory

It asks how you are doing and turns the vague, half-remembered answer into structure. A tingling hand becomes a dated observation. "The copay was rough" becomes the reason you skipped Tuesday, which is a completely different clinical conversation from skipping because of a side effect, and the second is what tends to get assumed.

Those check-ins are not stored to be searched later. They are wired into a graph, and the wiring is the memory. Everything you say attaches to the medications, symptoms, and instructions it is actually about. Remembering is a walk across those connections, not a guess at what reads similar, so every finding arrives with the path it came down and the sentence it came from.

### Two findings that similarity search cannot produce

Formally, Alongside surfaces a concern when it is _reachable_ from the anchor a check-in touches, whereas a vector index can only return the `k` nearest items by cosine similarity, \\( \{\, d : \cos(q,d)\ \text{in the top } k \,\} \\), a set that by definition cannot contain a fact that is not there:

$$\text{surfaced}(c)\ \iff\ \exists\ \text{path}(a \to c)\ \text{in the graph } G$$

That one difference buys two classes of finding that top-`k` cannot produce at any `k`:

- **Convergence.** Two drugs, from two prescribers, reaching one toxicity through a shared vocabulary node. A triangle nobody was standing in the right room to see. The load-bearing example is a three-hop path a keyword or embedding search would never assemble:

```jac
# Channel B: exhaustive, unscored, decay-exempt. Only a Supersedes edge kills a hard constraint.
# grapefruit -> CYP3A4 inhibitor -> CYP3A4 substrate -> imatinib
visit [-->:Member:->];              # walk the vocabulary lattice, deterministically
# a hard Constraint reached from the new anchor is a hit, every time:
report Concern(kind="interaction", anchor=here.key, action="ask");
```

- **Absence.** A symptom with no attributing edge, a prescription with no adherence record, a gap in the check-in chain. _A retriever cannot rank a document that does not exist_; a graph can point at the edge that is missing.

### The page you carry

The output is a page, not a message: **"Questions for your care team,"** a standing document that accumulates and drains. The severity ladder becomes the layout:

- An **emergency** match is a full-screen "contact your team now," shown before the page, because escalations do not wait.
- **"Ask about these"** holds the hard, channel-B-backed concerns.
- **"Worth mentioning"** holds the softer, absence-class ones.
- **"Also tracking,"** collapsed, holds everything below the waterline; one click proves that going quiet is not the same as being deleted.

Every row shows the question in the patient's voice, why it came up, what has been noticed with dates, and where it came from, with each citation clicking through to the exact `Utterance` it quotes. An activity panel makes the autonomy visible, and a judge-facing inspector puts the cosine ranking (blocking fact at rank 11, indistinguishable from absent) next to the three-hop traversal that actually reaches it. Expanding a row assembles a lazy case file: the observation chain walked back to first onset, compared against regimen-change dates, with the counterfactual named.

When the patient records what their team said, that answer re-enters the graph as the highest-authority source in the system and can harden into a constraint the next traversal must respect. The system never sends anything to anyone. You carry it.

## The caregiver view

This is the part of the roadmap that comes straight from the inspiration, and it is the honest adoption path.

Most cancer patients are older, and the person best positioned to see the slope is frequently not the patient but the caregiver who sees the endpoints: the daughter on a video call, the grandson who visits every few years. The caregiver view is a **read-only window** onto the same standing page, granted with the patient's consent, so the person who notices the change can help carry the record without ever taking it over. It introduces **no new outbound path**: it is another reader of the graph, never a sender. Designed, not yet shipped; it is first on the list below.

## How we built it

**Jac end to end:** graph, walkers, LLM calls, and UI in one language, deployed on JacHammer.

### The graph: three layers, deliberately separated

A **provenance floor** (`Utterance`, `Observation`) that is never scored or decayed; a **ground-truth anchor layer** resolved deterministically from a curated vocabulary, never inferred; and a **belief layer** that is the only thing scored. That separation is what lets old beliefs sink below a retrieval waterline without ever touching the record of what was actually said.

### Two retrieval channels with different physics

**Channel A** (soft preferences and conventions) is a scored, beam-limited, decaying traversal. **Channel B** (hard constraints) is exhaustive, unscored, and exempt from decay, beam, budget, and waterline. Only an explicit `Supersedes` edge kills a Channel B constraint. A safety-critical fact must not compete for a slot with a preference about ginger tea. Corroboration between the channels can only **promote** severity, never lower it, and an emergency criterion is evaluated **first**, before any scoring.

### Six walkers, and only two model calls

- **`Vigil`** runs unprompted on app open, so detection happens before you type a word.
- **`Remember`** is the write path: it extracts free text into a typed schema (`by llm()` site one) and links it to deterministically parsed anchors.
- **`Recall`** runs both channels, the four detection mechanisms (interaction and additive toxicity, the absence class, thresholds and contradictions, cross-prescriber conflict), corroboration, the emergency bypass, and usage reinforcement.
- **`Consolidate`** does a self-budgeted rewrite, using joint satisfiability of two natural-language constraints (`by llm()` site two).
- **`Investigate`** assembles the case file lazily, all graph traversal and date arithmetic, with no model call.
- **`Prepare`** renders the page from templates.

Dismissal mutes a concern, it never deletes it, and a dismissed concern resurfaces if the anchor set changes, so dismissal can never quietly void the guarantee. Roughly **fifty tests** cover the read path, MockLLM-first, so the suite never makes a network call.

### One organizing rule: autonomy on the write path, determinism on the read path

Exactly **two `by llm()` sites** exist in the entire system, both on the write path. The read path has **zero**. Every sentence the patient reads about their care is a template with graph-read slots, or a verbatim quote. We also **refused a primitive on purpose**: `visit [-->] by llm()`, letting the model choose where to walk, would have made retrieval probabilistic and voided the Channel B guarantee outright. It stays out.

### Jac: the safety claim and the code are the same object

We did not reach for Jac to write a normal app faster. We reached for it because our entire thesis is only expressible in a language where the graph and the walk over it are first-class.

- **Object-Spatial Programming** made retrieval a `visit` traversal that carries its own provenance, so "relevance is reachability" is the literal control flow of `Recall`, not a slogan. Every other paradigm would have forced the safety property to live in a library _next to_ the code. Jac let it live _in_ the code.
- **`by llm()`** turned a two-call autonomy budget into a greppable invariant. "Keep the model on a leash" stops being a code-review aspiration and becomes `grep 'by llm('` returning exactly two hits.
- **`jac check`** type-checks the client and server seam, so a walker signature change lights up the exact client `root spawn` that drifted. It caught cross-boundary contract drift that a conventional TypeScript and mypy stack sees nothing of.
- **Policy lives on the graph, not in a loop.** `Recall` contains no `while` loop; scoring, gating, and the two channels are node-type abilities with inheritance, so one ability serves every belief subtype while a constraint ability hard-overrides.

### JacHammer: one artifact, one history, one language

JacHammer is why this is a single deployable thing instead of a stack. It gave us a **git-native, browser-based full-stack runtime** where graph, walkers, model calls, and UI deploy as one artifact, against the same history a human commits to; a whole four-day, three-person fan-out lived in it without fracturing. `main.jac` is a genuine single-file vertical slice: the data model, both `by llm()` sites, a real multi-hop traversal, the template registry, and the browser UI, in one file, with **no separate frontend and no separate Python service**. Configuration lives in project-scoped environment variables, `DEMO_MODE` among them, sourced at process start; the client surface hot-reloads while the server modules stay put; and per-patient isolation is a **language property**, not a tenancy layer we built, because patient graphs cannot reach each other when there is no query surface on which they could. JacHammer took "single-file full-stack" from a slogan to the actual shape of the deliverable.

## What's real vs. seeded

We keep this honest, the way a safety tool should.

| Piece | Status |
|---|---|
| Six walkers, two-channel traversal, detection mechanisms 1 to 4, corroboration, emergency bypass | **Real.** Built and covered by the read-path test suite. |
| `Investigate` case file and `Prepare` page render | **Real.** Pure graph traversal and templates, no model call. |
| The page UI: sections, rows, citations, activity panel, inspector, typed and voice check-in | **Real.** Renders from the live `PageModel`. |
| Deterministic regimen parse, anchor vocabulary, curated interaction table | **Real.** |
| The two `by llm()` sites on the demo path | **Seeded.** `DEMO_MODE` returns precomputed extraction and satisfiability keyed to the seeded patient's exact utterances, so the demo makes **zero live model calls**. Unset it for live behavior. |
| The patient | **Synthetic.** A seeded adversarial case (the day-9 QT convergence) with a known ground truth for both convergence and absence. |
| Permanent deploy | **Pending.** Sandbox deploys run today; the always-on deploy is next. |
| Caregiver view | **Designed, not shipped.** Roadmap, below. |

## Challenges we ran into

### Editing the schema is a landmine, and there is no shell to defuse it

Changing a persisted `node` or `edge` archetype invalidates existing graph data, and JacHammer's browser IDE has no shell to clear it. So freezing the schema became genuinely blocking; it could not land until we had proven and documented a reset path. We front-loaded the freeze, batched every schema change behind one label, and announced resets. The lesson: treat the archetypes as a constitution, ratified once.

### Three people, one deliverable file

JacHammer rewards single-file full-stack apps, and three people cannot type one file at once. Jac's own answer, develop in five files and ship one, only works if four merge disciplines hold from the first commit: home-prefixed helpers, `root spawn` only, one stylesheet, and satellites importing solely from the schema module. We rehearsed the merge at the midpoint on a throwaway branch rather than discovering the problems at hour 22. We still hit a merge race and a branch tangle in the shared clone, and every single time the thing that told us exactly which line drifted was `jac check`.

### Refusing the easy sentence, every time

The strongest temptation in a system like this is that when a row of page copy reads awkwardly, you reach for `by llm()`. We never did, not once; awkward copy got fixed in the template. Holding a hard cap of two model calls took real discipline, and Jac is what made it enforceable rather than aspirational, because every model call is the literal token `by llm()`.

### Testing a thing that is not there

Half of what Alongside catches is absence, and you cannot fixture the document that does not exist. So we built a seeded adversarial patient where both convergence and absence have a known ground truth, and wrote the read-path suite against it.

## Accomplishments that we're proud of

- **The entire application is one file, in one language.** `main.jac` is the graph schema, both `by llm()` sites, a real multi-hop traversal, the template registry, and the browser UI. Jac collapsed a stack that is normally five technologies into one, and we tagged the single-file artifact so it is citable.
- **The safety claim is structural, not promised.** Because Object-Spatial Programming makes traversal first-class, the central product claim and the implementation are the same object, and a missing edge is inspectable rather than silently absent.
- **Two classes of finding similarity cannot produce:** convergence and absence, both falling directly out of modeling the domain as a graph in Jac instead of an index.
- **Autonomy that is auditable, not trust-me:** two `by llm()` sites, read path zero, provable because Jac marks every model call in the syntax, and one primitive deliberately refused.
- **A record that fails visibly,** the whole point of the grandfather story: it surfaces the slope by holding the endpoints, and it says "not in your record" instead of "safe."

## What we learned

- **The endpoints-and-the-slope problem is the whole product.** The person inside a gradual change is the last to see it; a record that holds the endpoints is a form of advocacy.
- **Object-Spatial Programming changes what retrieval means.** Once traversal is a language primitive, you ask "is it connected?", a question that fails visibly instead of silently. For a safety tool, visible failure is the entire game, and Jac is the first environment we used where the safe answer was also the idiomatic one.
- **Marking LLM calls in the syntax turns a vibe into an invariant.** A two-site cap is a rule the whole team can hold because delegation to a model is a first-class, visible construct.
- **`jac check` across the full-stack seam is a different kind of safety net,** and we leaned on it as the merge gate.
- **Develop-in-five, ship-one is a methodology, not a hack,** because Jac archetypes are flat within a module, so the final merge is concatenation plus deleting import lines.

## What's next for Alongside

- **The caregiver view.** A consented, read-only window for the person who sees the endpoints; a reader of the graph, never a sender.
- **A permanent deploy.** The standing document a patient carries cannot expire in seven days.
- **Closing the loop all the way,** so a recorded answer becomes a hard constraint the next traversal must respect.
- **More vocabulary, real labels:** broaden the anchor vocabulary and interaction table, and ingest printed pharmacy labels and visit summaries directly, so authority always lives in the artifact, never in the model.
- **Gentle trajectory surfacing over longer arcs,** making the slope itself visible without ever crossing into alarm or diagnosis.
- **The one thing that never ships: an outbound path.** Alongside renders a page and the patient carries it. It will never message a clinician, and that stays a non-negotiable.

## Built With

`jac`, `jachammer`, object-spatial-programming, `by-llm`, web-speech-api, react (via Jac client codespaces), sqlite (Jac persistence).
