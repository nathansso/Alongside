# CLAUDE.md

Auto-loaded context, read at the start of every session. Keep it short.

## Project

**myCancerPal** — a longitudinal treatment companion for cancer patients. A persistent Jac graph
accumulates daily check-ins as typed beliefs linked to deterministically-parsed anchors. Retrieval
is graph traversal, not similarity search.

The deliverable is **a page, not a message**: "Questions for your care team", a standing document
that accumulates and drains. The system never sends anything to anyone.

**Deployment:** jachammer — a full-stack Jac web app. Browser IDE, no shell, no filesystem.
**Tracks:** Social Impact, Agentic AI, Best JacHammer.

## Doc map

| File | Read when | Authority |
|---|---|---|
| `ARCHITECTURE.md` | before writing any code | **authoritative** — invariants, walkers, build order |
| `CONTRACTS.md` | before changing any shared shape | **authoritative** — pinned wire shapes |
| `CONTRIBUTING.md` | before opening a branch | the collaboration protocol |
| `old_docs/*` | never, unless archaeology | **superseded. Do not build from these.** |

`old_docs/` describes an earlier architecture with eleven walkers, a drafted outbound message, and
a `Synthesize` walker. None of that exists. If you find yourself citing those files, stop.

## Non-negotiables

Full list in `ARCHITECTURE.md` section 2. These are the ones most likely to get broken by accident:

- **S7** No outbound path exists. The system renders a page; the patient carries it. Nothing is
  drafted, sent, or transmitted. Do not add email, messaging, portal integration, or MCP send.
- **S8** Every sentence the patient reads about their care is a **template with graph-read slots**
  or a **verbatim quoted `Utterance`**. Never generated. If page copy reads awkwardly, fix the
  template — do not reach for `by llm()`.
- **S9** Dismissal mutes, never deletes. A dismissed channel-B concern resurfaces if the anchor set
  changes.
- **S3** Absence of a finding yields "not in your record". Never "safe".
- **S4** No dosing judgments, substitutions, dose calculations, or discontinuation advice.
- **A1** Anchors are never invented by `by llm()`. Anchor creation requires vocabulary membership;
  a miss writes `needs_review = True` and creates no anchor.
- **A2** Channel B is unscored, unpruned, exempt from decay, beam, budget, and waterline. Only
  `Supersedes` kills a channel B constraint.
- **A3** The model never selects a traversal path. No `visit [-->] by llm()` anywhere.
- **A5** Corroboration promotes severity only, never demotes. A channel B hit reaches `ask` alone.
- **A9** Only `Recall` reinforces. `Vigil`, `Investigate`, and `Prepare` are strictly read-only.

**Exactly two `by llm()` sites exist** — extraction in `Remember`, satisfiability in `Consolidate`.
Both on the write path. Adding a third requires human approval.

If a request would require violating any of these, **do not implement it. Report the conflict.**

## Six walkers

`Vigil` (unprompted, on open) · `Remember` (write) · `Recall` (two-channel read + detection) ·
`Consolidate` (self-budgeted rewrite) · `Investigate` (case file, lazy) · `Prepare` (renders page)

There are **no detection walkers**. Detection lives in `Recall`'s node abilities. There is no
`Synthesize`; corroboration is a rule in `Recall`'s `Root exit`.

---

## Using Jac

Load the guides before writing code: `jac guide <name>`, or read `~/.claude/skills/jac-*`.
Start with `jac-core-cheatsheet` and `jac-types`. Then, by task:

| Task | Guide |
|---|---|
| walkers, abilities, traversal | `jac-walker-patterns`, `jac-node-edge-patterns` |
| `by llm()` and `sem` | `jac-by-llm` |
| the full-stack wiring | `jac-fullstack-patterns` |
| `.cl.jac` UI components | `jac-cl-components`, `jac-cl-organization`, `jac-cl-styling` |
| server endpoints | `jac-sv-endpoints`, `jac-sv-persistence` |
| typed `has` state | `jac-has-fields`, `jac-types` |
| anything misbehaving | `jac-debugging` |

**Validate every edit with `jac check .`** It catches cross-boundary contract drift at the exact
stale line — a conventional type-checker sees nothing across that seam.

### Full-stack mechanics

- `main.jac` is a **mixed-context** file: server code at top level (server is the default context),
  client code inside a `cl { ... }` block. `.cl.jac` files need no wrapper — the extension sets
  client context. **Rule of thumb: wrapper in `.jac`, no wrapper in `.cl.jac`.**
- **Call walkers from the client with `root spawn`, using kwargs:**
  `result = root spawn Prepare(anchors=a);` → kwargs map to the walker's `has` fields, and reports
  land in `result.reports` (a list; use `len()`, not `.length`).
- **Do not use function RPC in `main.jac`'s `cl { }` block.** Function RPC is **positional-only**
  (kwargs → `422 Field required`), and an `sv import` inside the entry module's own `cl { }` block
  does *not* register the endpoint. Walker spawn sidesteps both problems.
- In a `.cl.jac` file, server imports use `sv import from ..services.X { fn, Types }` — the prefix
  is required and the dot count is how many folders up to the target. **Always `await`** those
  calls; the stubs are async.
- **Type `has` state with the imported types.** `list[any]` loses the element type and attribute
  access in loops fails `E1032: Type is Unknown`.
- **Reader responses are cached 60s.** After a write, re-call every reader whose data it changed
  and assign the fresh reports into state. A "stale" read is usually the cache, not your code.
- Client entry is `def:pub app()` — lowercase, not `App()`.
- `[serve] base_route_app = "app"` in `jac.toml` serves the client at `/`.

### Gotchas that cost an hour each

- **Editing archetypes corrupts the persisted graph.** Changing a node or edge definition between
  runs gives `NodeAnchor ... is not a valid reference!`. Locally the reflex is `rm -rf .jac/data/`.
  **On jachammer there is no shell — find the reset mechanism before stage 1.**
- **Edge abilities are a silent no-op.** `can ... with Walker entry` inside an `edge` compiles clean
  and never fires. All scoring lives in walker node abilities reading `[edge ...]`.
- **`++>` returns a list.** `b = (anchor ++> Belief(claim=c))[0];`. A missing `[0]` fails somewhere
  else entirely.
- **Typed edge deletion needs `[edge ...]` plus iterate-`del`.** `del [a ->:Supersedes:-> b];`
  passes `jac check` and fails at runtime with E5043.
- **`by llm()` returns `obj`, never `node`.** Extract into an obj, copy into the node.
- **Type the report channel.** `has verdict: Verdict = Verdict();`. Omitting the default makes it a
  required spawn parameter and every spawn fails E1050.
- **Report once from `with Root exit`.** Per-node reporting scatters N tiny reports.
- **Declare endpoints on every edge.** Untyped edges yield `Unknown`-typed nodes that pass
  `jac check` and fail later.
- **Walker `has` state is global to the walker, not per-branch.** Memoize per node in a dict;
  decaying a walker field directly corrupts across branches.

## Conventions

- **All application code is Jac.** Python only as libraries imported into Jac. No separate Python
  service, no separate React app.
- **Zero non-Jac artifacts.** The vocabulary and curated interaction table are inline `glob`s, not
  JSON files — jachammer has no filesystem.
- **`main.jac` is the single-file vertical slice**: archetypes + `Remember` + `Prepare` + the page
  UI in one file. This is deliberate and demonstrates a scored rubric property. Do not refactor the
  UI out of it. Other components live in `components/*.cl.jac`.
- **`walkers/recall.jac` contains no `while` loop.** Policy lives on node-type abilities.
- **No scheduler, cron, or background sweep.** `Vigil` on app open is the trigger.
- **Never cut `Prepare` or the concerns page.** It is the deliverable. Drop order is `Shortcut`,
  then channel-A reinforcement, then `Investigate` step 3, then channel A.

## Working agreement

- Work from an issue. Branch, PR, and label conventions are in `CONTRIBUTING.md`.
- **Check `CONTRACTS.md` before changing any shared shape**, and follow the announcement rule there
  if you must.
- **`graph/archetypes.jac` is owned and frozen after stage 1.** Do not edit it on a feature branch —
  open a `schema` issue.
- Do not start a new task while a prior one has a failing acceptance check.
- Surface the open decisions in `ARCHITECTURE.md` section 18 rather than resolving them.
- When reporting, state: which issue, which acceptance check passed, and any invariant currently
  violated even temporarily.
