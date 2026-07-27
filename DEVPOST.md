# Alongside

A longitudinal treatment companion for cancer patients, built end to end in **Jac** and deployed on **JacHammer**. _Relevance is reachability, not similarity._

## Inspiration

My grandfather has cancer. I see him every few years, and the change is always stark. He doesn't notice, because he is living the slope: day to day the change sits below the threshold of perception, and the person inside a gradual decline is the last one positioned to see it. I only see the endpoints, which is exactly why the change is obvious to me and invisible to him.

The same blind spot runs through his care. Patients collect prescriptions from oncology, primary care, and urgent care, clinicians who do not share notes. Two doctors each prescribe something safe; nobody was in both rooms; together they are not safe, and nothing catches it. Meanwhile the symptoms that matter most happen between visits and arrive compressed into "I've been okay, I guess."

Alongside is built to see the endpoints and the slope at once: not to diagnose, not to talk to anyone's doctor, but to help a patient advocate for himself with a record he actually has.

## The scale of the problem

A systemic failure that touches nearly every cancer patient, and compounds with age:

- **20 million** new cancer cases and **9.7 million** deaths worldwide in 2022 ([GLOBOCAN 2022](https://www.uicc.org/news-and-updates/news/globocan-2022-latest-global-cancer-data-shows-rising-incidence-and-stark); [Bray et al., _CA Cancer J Clin_ 2024](https://acsjournals.onlinelibrary.wiley.com/doi/full/10.3322/caac.21834)).
- Polypharmacy (five or more drugs) affects **~38% to 60%+** of older cancer patients ([Frontiers 2022](https://www.frontiersin.org/journals/pharmacology/articles/10.3389/fphar.2022.1044885/full); [_The Oncologist_](https://academic.oup.com/oncolo/article/25/1/e94/6443068)).
- On oral anticancer drugs, **46%** have a potential drug interaction and **16%** a major one ([van Leeuwen et al., _Br J Cancer_ 2013](https://www.nature.com/articles/bjc201348)).
- Physicians underestimate **fatigue in 51%** of patients, and other symptoms nearly as often ([Laugsand et al. 2010](https://link.springer.com/article/10.1186/1477-7525-8-104)).
- Cost quietly rewrites the regimen: **17% to 30%** report nonadherence, and **22%** skip filling a script over cost ([Bestvina et al., _JCO OP_](https://ascopubs.org/doi/10.1200/JOP.2014.001406); [NCI PDQ](https://www.cancer.gov/about-cancer/managing-care/track-care-costs/financial-toxicity-hp-pdq)).

Capturing that between-visit signal is not soft: in a randomized trial, patients who self-reported symptoms lived a **median 31.2 vs 26.0 months**, about five months longer, with better quality of life and fewer ER visits ([Basch et al., _JAMA_ 2017](https://jamanetwork.com/journals/jama/fullarticle/2630810)). Every number above is a signal that exists but never reaches the room. Alongside carries it in.

## What it does

**Checks in daily, by typing or voice.** Typing is the default; voice is one tap for the days typing is the barrier (fatigue, nausea, neuropathy), because a tired day should not become a missing day. Voice uses the browser speech API into an editable field, and adds no model call.

**Turns the answer into structure.** A tingling hand becomes a dated observation. "The copay was rough" becomes the reason you skipped Tuesday, a completely different conversation from skipping over side effects, and the second is what gets assumed.

**The graph is the memory.** Check-ins are not stored to be searched; they are wired to the medications, symptoms, and instructions they are about. Remembering is a walk across those connections, so every finding carries the path it came down and the sentence it came from.

Formally, Alongside surfaces a concern when it is _reachable_ from the anchor a check-in touches, whereas a vector index can only return the `k` nearest items by \\( \cos(q,d) \\), a set that cannot contain a fact that is not there:

$$\text{surfaced}(c)\ \iff\ \exists\ \text{path}(a \to c)\ \text{in the graph } G$$

That buys two findings top-`k` cannot produce at any `k`:

- **Convergence:** two drugs, two prescribers, one toxicity through a shared node. A three-hop path a keyword or embedding search would never assemble:

```jac
# Channel B: exhaustive, unscored, decay-exempt. Only a Supersedes edge kills a hard constraint.
# grapefruit -> CYP3A4 inhibitor -> CYP3A4 substrate -> imatinib
visit [-->:Member:->];
report Concern(kind="interaction", anchor=here.key, action="ask");
```

- **Absence:** a symptom with no attributing edge, a script with no adherence record, a gap in the check-in chain. _A retriever cannot rank a document that does not exist_; a graph points at the missing edge.

**The output is a page, not a message:** "Questions for your care team," a standing document that accumulates and drains. The severity ladder is the layout: an **emergency** is a full-screen "contact your team now" shown first; **"Ask about these"** holds the hard, channel-B concerns; **"Worth mentioning"** the softer ones; **"Also tracking,"** collapsed, holds what sank below the waterline, proving that going quiet is not deletion. Every row shows the question, why it came up, what was noticed with dates, and a citation that clicks through to the exact quote; expanding a row builds a lazy case file back to first onset. When a patient records what their team said, that answer re-enters the graph as the highest-authority source. The system never sends anything to anyone. You carry it.

## The caregiver view

Straight from the inspiration, and the honest adoption path: the person best positioned to see the slope is often the caregiver who sees the endpoints. A **read-only** window onto the same page, granted with the patient's consent, is another reader of the graph and **never a sender**. Designed, not yet shipped.

## How we built it

**Jac end to end:** graph, walkers, LLM calls, and UI in one language on JacHammer.

- **Three node layers:** a provenance floor (`Utterance`, `Observation`) never scored or decayed, a deterministic anchor layer, and a belief layer that is the only thing scored, so old beliefs can sink below a waterline without touching what was actually said.
- **Two channels, different physics.** Channel A (soft preferences) is scored, beam-limited, and decaying. Channel B (hard constraints) is exhaustive, unscored, and exempt from decay, beam, budget, and waterline; only a `Supersedes` edge kills it. Corroboration only promotes severity, and an emergency is evaluated first.
- **Six walkers, two model calls.** `Vigil` (unprompted on open), `Remember` (write path, extraction: `by llm()` one), `Recall` (both channels, detection mechanisms 1 to 4, corroboration, emergency bypass, reinforcement), `Consolidate` (self-budgeted rewrite, satisfiability: `by llm()` two), `Investigate` (lazy case file, no model call), `Prepare` (renders the page). Dismissal mutes but never deletes, and resurfaces if the anchor set changes. Roughly **fifty MockLLM tests** cover the read path.
- **One rule: autonomy on write, determinism on read.** Exactly two `by llm()` sites, both on write; the read path has zero. Every sentence is a template slot or a verbatim quote. We refused `visit [-->] by llm()` on purpose: letting the model pick the path would void the Channel B guarantee.

### Why Jac, and why JacHammer

- **Object-Spatial Programming** makes traversal first-class, so "relevance is reachability" is the literal control flow of `Recall`, not a slogan. The safety property lives _in_ the code, not in a library beside it.
- **`by llm()`** makes a two-call autonomy budget a greppable invariant, and **`jac check`** type-checks the client and server seam, catching contract drift a TypeScript plus mypy stack cannot see. Policy lives on node abilities, so `Recall` needs no `while` loop.
- **JacHammer** deploys graph, walkers, model calls, and UI as **one git-native artifact** against the same history a human commits to, with hot reload on the client and `DEMO_MODE` in a project env var. `main.jac` is a real single-file full-stack slice: no separate frontend, no separate Python service. Per-patient isolation is a language property, because there is no query surface on which two patient graphs could reach each other.

## What's real vs. seeded

| Piece | Status |
|---|---|
| Six walkers, two-channel traversal, mechanisms 1 to 4, corroboration, emergency bypass | **Real**, covered by the read-path tests |
| `Investigate` case file, `Prepare` page render, the full page UI (sections, citations, activity panel, inspector, typed and voice check-in) | **Real**, no model call on the read path |
| Regimen parse, anchor vocabulary, curated interaction table | **Real** |
| The two `by llm()` sites on the demo path | **Seeded:** `DEMO_MODE` returns precomputed results keyed to the seeded patient, so the demo makes **zero live model calls** |
| The patient | **Synthetic:** a seeded adversarial case (the day-9 QT convergence) |
| Permanent deploy, caregiver view | **Pending / designed**, on the roadmap below |

## Challenges we ran into

- **No shell to reset a graph.** Editing a persisted archetype invalidates data, and JacHammer's browser IDE has no shell, so we had to prove and document a reset path before freezing the schema, then treat the archetypes as a constitution ratified once.
- **Three people, one deliverable file.** Jac's "develop in five files, ship one" only works if four merge disciplines hold from commit one. We rehearsed the merge at the midpoint; when a merge race and a branch tangle still hit, `jac check` pointed at the exact drifted line every time.
- **Refusing the easy sentence.** Awkward page copy got fixed in the template, never generated. A hard cap of two model calls held because Jac makes every call the literal token `by llm()`.
- **Testing absence.** You cannot fixture a document that does not exist, so we built a seeded adversarial patient with known ground truth for both convergence and absence.

## Accomplishments that we're proud of

- **One file, one language:** `main.jac` is the schema, both `by llm()` sites, a real multi-hop traversal, the templates, and the UI, with a tagged single-file artifact.
- **A structural safety claim:** the product thesis and the implementation are the same object, and a missing edge is inspectable rather than silently absent.
- **Two findings similarity cannot produce,** convergence and absence, straight out of modeling the domain as a graph.
- **Auditable autonomy:** two `by llm()` sites, read path zero, and one primitive deliberately refused.
- **A record that fails visibly:** it surfaces the slope by holding the endpoints, and says "not in your record" instead of "safe."

## What we learned

- The endpoints-and-the-slope problem is the whole product: a record that holds the endpoints is a form of advocacy.
- Object-Spatial Programming changes what retrieval means: you ask "is it connected?", which fails visibly instead of silently. For a safety tool, that is the entire game.
- Marking LLM calls in the syntax turns "keep the model on a leash" from an aspiration into an invariant.
- `jac check` across the full-stack seam is a different kind of safety net, and it was our merge gate.

## What's next for Alongside

- **The caregiver view:** a consented, read-only reader of the graph, never a sender.
- **A permanent deploy:** a standing page cannot expire in seven days.
- **Closing the loop,** so a recorded answer hardens into a constraint the next traversal must respect.
- **More vocabulary and real labels,** ingesting pharmacy labels and visit summaries so authority always lives in the artifact.
- **The one thing that never ships: an outbound path.** Alongside renders a page and the patient carries it.

## Built With

`jac`, `jachammer`, object-spatial-programming, `by-llm`, web-speech-api, react (Jac client codespaces), sqlite (Jac persistence).
