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

### The graph reset path — resolved by #30

**Three paths, in order of preference. All verified on Jac 0.16.7 locally.**

1. **`jac clean --force`** — removes `.jac/data/` and nothing else. This is the CLI reset.
2. **Delete one file.** The whole persisted graph is a single SQLite file, `.jac/data/<project>.db`.
   Any file explorer can delete it — **no shell required.** This is the jachammer path if its file
   tree shows dotfolders.
3. **An in-app reset walker**, if neither of the above is reachable. Works anywhere, needs nothing.
   See `spike/graph.jac` → `SpikeReset`. Two rules: **filter `del` by node type** (an unfiltered
   `del [-->]` walks into root's own anchors and raises EdgeAnchor errors), and **collect
   transitively before deleting** — `[root -->][?:Type]` reaches depth 1 only, so anything further
   out gets orphaned rather than deleted.

### Archetype edits are far less dangerous than we assumed

`NodeAnchor ... is not a valid reference!` **did not reproduce on Jac 0.16.7.** What actually
happens, measured:

| Change | Behaviour |
|---|---|
| add a field to a node | `SqliteMemory: schema drift ... attempting best-effort load` — data loads, new field defaults |
| change a field's type | same — best-effort load, surviving fields keep their values |
| remove a field | same |
| add a field to an **edge** | same, and the edge and its attributes survive |
| **rename/remove an archetype** | `Refused to deserialize unregistered class` → anchor moved to `anchors_quarantine`, connected edges cascade-quarantined, **app keeps running** with those nodes absent |

So a schema change costs a **re-seed**, not a recovery. It is still silent data loss — best-effort
load and quarantine both drop what no longer maps — so the freeze and the announce-on-merge rule in
`CONTRIBUTING.md` §6 still stand. But nobody's graph "corrupts", and nobody loses an hour to it.

**Caveat: this was measured locally on 0.16.7 with the SQLite backend.** Confirm the Jac version in
jachammer before relying on it.

## Gotchas that cost an hour each
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

### Found in #30 — all cost an hour each, all reproducible in `spike/`

- **A walker the client spawns must be `walker:pub`.** A plain `walker` returns
  `{"error": "Unauthorized"}` from `/walker/<name>`, and the client surfaces it as an
  unhelpful `Walker X failed:` with an empty reason. `CONTRACTS.md` §4 currently pins all six
  walkers without `:pub` — they all need it.
- **Declaring an `obj` in the same module as the `cl { }` block that receives it breaks the client
  build.** The compiler emits the class twice — once as an interop wire stub, once transpiled —
  and esbuild fails with `The symbol "X" has already been declared`. Moving the objs to a separate
  module fixes it. **This is a direct hazard to the single-file merge in `CONTRACTS.md` §1a**, which
  puts the report objs and the `cl { }` block in one file. Test it at the rehearsal merge.
- **`len([root -->][?:Type])` written inline fails JS codegen with `E5016`** when the walker is
  reachable from a `cl { }` block. Bind the list to a typed local first, then `len()` it.
- **Removing a `.jac` file does not clear its compiled JS.** `.jac/client/compiled/` keeps the stale
  output and the old error persists. `rm -rf .jac/client/compiled` and restart.
- **`jac check` passes on all of the above.** None of these are type errors; they surface at the
  Vite build or at runtime in the browser.

## Using jachammer

The deployment target is a browser IDE. Confirmed from its docs, see `ARCHITECTURE.md` section 9:

- **Every project is a real git repository** — branches, commits, remotes, push/pull. You and
  JacCoder work against the same history. Work against the GitHub remote, not a separate copy.
- **Config goes in environment variables**, project or global scope, sourced into the app's running
  process for preview and deploys. `DEMO_MODE` is a **project-scoped** variable. There is no shell,
  so there is nowhere else to put it.
- **Sandbox deploys expire after 7 days.** The submission link must be a permanent deploy (#28).
- **No `jac browse`.** UI verification is manual in the preview pane. Do not write acceptance checks
  that assume a headless driver.
### Styling — resolved, do not wait on #30

**We never need a network package install.** The decision is a 10-second check in the editor:

**Open `jac.toml`. Does it have a `[jac-shadcn]` section?**

- **Yes** → Tailwind and shadcn are already wired by the template. Use them. Import primitives from
  `components/ui/`, use `cn()` from `lib/utils.cl.jac`, and use semantic tokens
  (`text-muted-foreground`, `bg-card`, `border`) rather than hardcoded grays. `jac add --shadcn
  <name>` is **bundled and offline** — no network — so pulling in a missing primitive should work
  even if npm installs don't. Never hand-write a primitive that exists in `components/ui/`.
- **No** → **one `styles/global.css`**, imported once inside `main.jac`'s `cl { }` block. Zero
  dependencies, no build plugin, no `jac install`.

**Do not add Tailwind to a non-shadcn project here.** That path needs
`jac add --npm --dev tailwindcss @tailwindcss/vite` plus a `[plugins.client.vite]` block, and
**editing `[dependencies.npm]` installs nothing on its own — `jac install` must run after.** Whether
jachammer runs `jac install` on a `jac.toml` change is not documented anywhere in its platform docs.
Not a risk worth taking for styling.

### Do NOT use `.style.css` annex files

Jac supports them and they are genuinely nice: a CSS file with the same **base name** as a component
is auto-scoped, classes are hashed, no import needed. **They are still wrong for this project.**

**The annex pairs to its component by base name.** When `page.cl.jac`'s body moves into `main.jac` at
the final merge (`CONTRACTS.md` §1a), `page.style.css` orphans and every style silently disappears —
no error, no `jac check` warning, just an unstyled page found late.

So: **one `styles/global.css`, hand-prefixed class names** (`pg-row`, `pg-row-q`). We give up
compiler-hashed scoping and get a merge that cannot break. Since Laksh owns every file that has any
CSS in it, there is no one to collide with anyway.

A plain-CSS project **may** use a `*` reset. A Tailwind project may not — it collapses spacing
utilities by conflicting with Preflight.

## Conventions

- **All application code is Jac.** Python only as libraries imported into Jac. No separate Python
  service, no separate React app.
- **Zero non-Jac artifacts.** The vocabulary and curated interaction table are inline `glob`s, not
  JSON files — jachammer has no filesystem.
- **Five files during the build, one at submission.** `graph.jac` (frozen) · `write.jac` (Bryan) ·
  `read.jac` (Nathan) · `main.jac` + `page.cl.jac` (Laksh). They collapse into `main.jac` before the
  deadline. **Read `CONTRACTS.md` §1a before writing a line** — four disciplines have to hold from the
  first commit or the merge stops being mechanical.
- **The four merge disciplines, in short:** prefix private helpers by home file (`wr_`, `rd_`, `pg_`);
  `root spawn` only, never `sv import` or function RPC; one `styles/global.css`, no `.style.css`
  annexes; satellites import only from `graph.jac`, never from each other.
- **Stay in your own file.** Do not "helpfully" edit another track's file. The no-conflict guarantee
  is structural, and it only holds if nobody crosses.
- **`Recall` contains no `while` loop.** Policy lives on node-type abilities.
- **No scheduler, cron, or background sweep.** `Vigil` on app open is the trigger.
- **Never cut `Prepare` or the concerns page.** It is the deliverable. Drop order is `Shortcut`,
  then channel-A reinforcement, then `Investigate` step 3, then channel A.

## Working agreement

- Work from an issue. Branch, PR, and label conventions are in `CONTRIBUTING.md`.
- **Check `CONTRACTS.md` before changing any shared shape**, and follow the announcement rule there
  if you must.
- **Stay in your own file.** Bryan owns `write.jac`, Nathan owns `read.jac`, Laksh owns `main.jac`
  and `page.cl.jac`. `graph.jac` is frozen after #1 — its nodes and edges need a `schema` issue.
- Do not start a new task while a prior one has a failing acceptance check.
- Surface the open decisions in `ARCHITECTURE.md` section 18 rather than resolving them.
- When reporting, state: which issue, which acceptance check passed, and any invariant currently
  violated even temporarily.
