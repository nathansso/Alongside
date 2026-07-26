# Memory as Topology

Agent memory built as a persistent graph, where retrieving what matters is a traversal
rather than a similarity search.

Specification for the memory layer. Domain-neutral: nothing below assumes a particular
application on top.

## One-liner

Every memory system answers "which of the user's beliefs matter here?" with cosine distance.
This answers it with a traversal. **Relevance is reachability, not similarity.**

The consequence that matters most: top-k retrieval fails **silently** — a blocking fact that
ranks 11th is indistinguishable from a blocking fact that does not exist. Traversal fails
**visibly** — if a constraint is connected to the anchor, it is reached, and if it is not
reached the edge is missing and that is inspectable. This makes the system's central claim a
safety property rather than a retrieval improvement.

## The system

A persistent memory graph. Input is extracted into atomic beliefs as nodes, linked to
ground-truth anchors and to each other. Every later request walks the graph from a resolved
anchor set to assemble context, reinforcing the edges it used and letting the rest decay.

## The unifying insight

Retrieval, importance, and forgetting are the same operation. A traversal reads the graph, and
the act of traversing *is* the importance signal — edges on an accepted path strengthen,
unused ones decay below the retrieval waterline. No separate ranking model, no separate
eviction policy, no reward model. One walker, run repeatedly, produces all three.

Loop: **extract → traverse → reinforce → occlude.**

## Structure

Three node layers — provenance, ground truth, and belief — separated so the scored layer can be
occluded without touching the other two:

```jac
node Utterance  { has text: str; has at: str; has role: str; }        # provenance floor, never scored
node Anchor     { has key: str; has kind: str; }                      # ground truth, never inferred
node Belief     { has claim: str; has strength: float = 1.0;
                  has last_used: str; has uses: int = 0; }
node Preference(Belief) { has polarity: float = 0.0; }                # -1 avoid .. +1 prefer
node Constraint(Belief) { has hard: bool = True; }                    # allergy, budget, deadline
```

Node inheritance is load-bearing: one `can score with Belief entry` serves every subtype,
while `can gate with Constraint entry` hard-overrides.

### The anchor layer is ground truth, not inference

`Anchor` nodes must be resolvable **deterministically** from the domain's own artifacts — a
parsed identifier, a canonical entity key, a structured field. They are never invented by
`by llm()`.

This is a correctness property, not a convenience. An LLM-selected entry point puts extraction
error at the head of every traversal, so a single bad anchor corrupts every path through it.
With parsed anchors, extraction is responsible only for beliefs and edges, and a bad
extraction costs one node.

Corollary: anchor **resolution** at query time is also deterministic — a lookup from the
entities the request references, not a guess about which anchors seem relevant.

### Edges

Eight edges, **endpoints declared on all of them** — an untyped edge yields `Unknown`-typed
nodes that pass `jac check` and fail later:

```jac
edge DerivedFrom: Belief     --> Utterance  { }
edge About:       Belief     --> Anchor     { has weight: float = 1.0; }
edge Relates:     Belief     --> Belief     { has weight: float = 1.0; has co_uses: int = 0;
                                              has last_used: str; }
edge Supersedes:  Belief     --> Belief     { }
edge Shortcut:    Anchor     --> Belief     { has hops: int = 2; has weight: float = 1.0; }
edge Governs:     Constraint --> Anchor     { }
edge Excludes:    Constraint --> Anchor     { has because: str; }
edge Conflicts:   Constraint --> Constraint { has derived_at: str; }
```

`DerivedFrom` is what makes every belief auditable — any node can be walked back to the exact
sentence it came from, which is also what makes a belief safely deletable. `Governs` /
`Excludes` are the unscored constraint channel (below). `Conflicts` is derived, never asserted.

## Three walkers, one topology

Same graph, three behaviors, nothing in between them.

| Walker | Role | Shape |
|---|---|---|
| `Remember` | write | attach `Utterance`, `by llm()` extract beliefs, link to anchors |
| `Recall` | read + reinforce | two-channel traversal, returns a verdict |
| `Consolidate` | rewrite | shortcut edges, conflict derivation, occlusion |

## Recall: two-channel traversal

A single scored beam cannot carry the safety claim. A hard `Constraint` sitting two hops out
on a cold edge is pruned by the beam or sunk below the waterline, which reintroduces exactly
the silent-failure mode that motivates the design. So retrieval splits into two channels with
different guarantees.

| Channel | Traverses | Beam | Budget | Decay | Occlusion | `Supersedes` |
|---|---|---|---|---|---|---|
| **A** — soft: preferences, conventions | `About`, `Relates`, `Shortcut` | yes | counted | yes | yes | yes |
| **B** — hard constraints | `Governs`, `Excludes` | **exhaustive, unpruned** | **exempt** | **exempt** | **exempt** | yes |

Channel B is affordable because constraint fan-out per anchor is small and bounded by the
domain, not by conversation length.

Note the last column. The carve-out covers decay, beam, and the waterline — **never**
`Supersedes`. A retracted constraint must still die, or the graph cannot be corrected.

Channel A is a greedy beam *per node*, not global best-first (the visit queue appends;
candidates get sorted inside each ability):

- at `Root` — resolve the anchor set deterministically from the request; visit each
- at `Anchor` — channel B: read `[edge here <-:Governs:<-]` and `<-:Excludes:<-`, collect
  **all**, unscored. Channel A: read `[edge here <-:About:<-]`, score, visit top `beam`
- at `Belief` — superseded → `skip`; `budget -= 1`; exhausted → `disengage`;
  else collect, score `[edge here ->:Relates:->]` + `->:Shortcut:->`, visit top `beam`
- at `Root exit` — assemble the verdict, reinforce the **channel-A** trail only, `report` once

Channel B edges carry no weight, so there is nothing to reinforce on them. Exit abilities fire
LIFO post-order, so bottom-up aggregation comes free.

### Recall returns a verdict, not a list

Returning `list[str]` of claims pushes interpretation back onto the model and discards the
distinction the two channels just established. `Recall` reports a decision plus the evidence
that produced it:

```jac
obj Violation { has claim: str; has because: str;
                has source: str; has at: str; }        # source/at from DerivedFrom
obj Verdict   { has allowed: bool = True;
                has violations: list[Violation] = [];  # channel B hits
                has soft: list[str] = [];              # channel A collection
                has conflicts: list[str] = []; }       # Conflicts among collected constraints
```

`allowed` is false iff channel B produced at least one hit on a `Constraint` with
`hard == True`. Soft beliefs never block; they shape.

Every `Violation` carries its provenance inline, so an explanation is a field read rather than
a second query.

## Scoring

```
effective(e) = e.weight * 0.5 ** (days_since(e.last_used) / half_life)
```

**This governs channel A only.** Channel B is unscored by construction — applying a weight to
a hard constraint is what would make its retrieval probabilistic again.

Past the anchor step there is no semantic term in channel A — relevance is purely structural.
Not a shortcut; it's the thesis.

## Consolidation: five operations, ascending risk

| | What | Cost | Risk |
|---|---|---|---|
| **Reinforce** | edges on an accepted channel-A trail get `weight += α`, `co_uses += 1` | free | none |
| **Decay** | computed lazily at read time from `last_used` | free | none |
| **Shortcut** | path `Anchor→A→B` traversed together ≥N times ⇒ write `Shortcut: Anchor --> B, hops=2` | free, no LLM | none |
| **Occlude** | effective weight below waterline, or incoming `Supersedes` ⇒ walker `skip`s | free | none |
| **Derive conflicts** | jointly-unsatisfiable constraint pairs ⇒ write `Conflicts` | 1 LLM call | false positives are visible and cheap |

Four rules:

- **Decay lazily.** A sweep walker is the obvious design and it's wrong — second walker, needs
  a scheduler, mutates state out from under readers. Store `last_used`, compute on score.
- **Occlusion is never deletion.** Cold nodes keep their `DerivedFrom` edges and sit below the
  waterline. This is what lets a caller distinguish "everything known" from "what was used,"
  and makes a wrongly-cooled belief recoverable — it warms back up the next time it is reached.
- **Hard constraints never sink.** The waterline does not apply to channel B. Occluding a hard
  constraint silently voids the guarantee that is the point of the system.
- **Every operation is non-destructive.** Four of the five are pure structure, LLM-free, and
  reversible; the fifth only ever *adds* an edge. Nothing in consolidation discards a belief,
  which is what makes the channel-B guarantee hold over time rather than only at write time.

`Conflicts` is derived output, not user assertion: it surfaces a contradiction between two
constraints the user stated separately and never compared. This is the class of result a
similarity index cannot produce at any *k*, because it has no representation of two facts
being related-and-inconsistent.

## Integration surface

`Recall` is exposed to the model as a callable:

```jac
def recall(anchors: list[str]) -> Verdict {
    return (root spawn Recall(anchors=anchors)).verdict;
}
sem recall = "Check the memory graph for constraints and preferences bearing on these entities.";
```

Two viable wirings, and the choice is a real one:

- **ReAct tool** — `by llm(tools=[recall], max_react_iterations=4)`. The model decides when to
  consult memory, and each consultation reinforces the graph. Retrieval becomes an action the
  model takes, and taking it changes the structure.
- **Mandatory gate** — `recall()` runs before any action that touches an anchor, and
  `allowed == false` blocks. Costs the model's discretion.

These are not equivalent. A tool the model *may* call cannot support a guarantee; a gate can.
Use the tool wiring for soft beliefs and the gate wiring for anything where channel B's
guarantee is load-bearing.

Walkers auto-expose as REST endpoints; `def:priv` runs against the caller's `root`, so
per-user isolation is the default rather than something to build.

## Deployment

Deploys through **jachammer.ai**, Jaseci Labs' browser-based Jac IDE ("build, preview, and
version your projects in the browser").

Consequences for the codebase:

- Must build and run inside the browser IDE. No local-only toolchain steps.
- No assumptions about a local filesystem beyond what the IDE exposes; anchor ingestion must
  accept content passed in rather than read from arbitrary paths.
- No dependency on a shell, background scheduler, or cron. Reinforces the lazy-decay rule
  above: there is no place to put a sweep process.

## Build order

Dependency order, not a schedule. Each stage is independently demonstrable.

1. Archetypes + persistence. Retrieval stubbed to "return every belief" — ugly, working,
   end-to-end.
2. Anchor ingestion. Deterministic parse into `Anchor` nodes.
3. `Remember` — `by llm()` extraction, `DerivedFrom` + `About` edges.
4. `Recall` channel B — constraints, exhaustive, `Verdict`. The guarantee lands before any
   scoring exists.
5. `Recall` channel A — scoring, beam, budget, reinforcement.
6. `Shortcut` edges.
7. `Conflicts` derivation.

Stage 4 before stage 5 is deliberate. The safety property is the contribution; the scored beam
is an optimization over the part that is allowed to be lossy.

## Non-goals

- Embeddings anywhere in the retrieval path.
- **Lossy compression or summarization of beliefs.** Occlusion already prunes what gets
  traversed and channel A's `budget` already caps what reaches the model, both losslessly, so
  summarization would buy only storage footprint — at the cost of being the single operation
  in the system capable of destroying a fact the guarantee depends on. Excluded deliberately,
  not for time.
- Benchmark or eval harness.
- Temporal reasoning beyond `Supersedes`.
- Auth beyond the default per-user root.
- Multi-agent anything.

## Known limits

- **Belief extraction quality bounds the belief layer.** The anchor layer is parsed, so this no
  longer compounds through the entry point — but a belief that is never extracted is never
  reached, and a mis-typed `Preference` that should have been a `Constraint` silently downgrades
  from channel B to channel A. That misclassification is the highest-severity failure mode in
  the design.
- **Channel A is a greedy beam, not optimal search.** Approximates best-first; no optimality
  guarantee. Channel B is exhaustive and carries no such caveat.
- **The guarantee is conditional on the edge existing.** "If a constraint is connected to the
  anchor, it is reached" says nothing about a constraint that was never linked. Edge creation is
  where the risk concentrates.
- **No baseline comparison.** The compositional-retrieval claim is argued, not benchmarked
  against a vector store.
- **Contradiction handling is one edge type, not a temporal model.** Proper bitemporal
  invalidation is a research problem (cf. Graphiti); `Supersedes` is the cheap
  correct-looking version.

## Jac implementation gotchas

- **Edge abilities are a silent no-op.** `can ... with Walker entry` inside an `edge` compiles
  clean and never fires. All scoring lives in walker node abilities reading `[edge ...]`.
  Designed around this from the start.
- **Editing archetypes corrupts the local graph.** `jac run` persists to cwd `.jac/`; changing
  a node/edge definition between runs gives `NodeAnchor ... is not a valid reference!`. Reflex:
  `rm -rf .jac/data/`, restart.
- **`++>` returns a list.** `b = (anchor ++> Belief(claim=c))[0];` — a missing `[0]` fails
  somewhere else entirely.
- **Typed edge deletion needs `[edge ...]` + iterate-`del`.** `del [a ->:Supersedes:-> b];`
  passes `jac check`, fails at runtime (E5043). Applies to `Conflicts` rewrites during
  consolidation.
- **`by llm()` returns `obj`, never `node`.** Extract into an obj, copy into the node — the AI
  schema and the storage schema evolve independently.
- **Report once from `with Root exit`.** Per-node reporting scatters N tiny reports.
- **Type the report channel** — `has verdict: Verdict = Verdict();`. Omitting the default makes
  it a required spawn parameter and every spawn fails E1050.
- **Edge creation is where the intelligence lives.** Substring or keyword matching to link
  beliefs will look like it works on the first three nodes and quietly poison every traversal
  after that. Use `by llm()` or structural rules derived from the anchor layer.
