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
  **On jachammer there is no shell.** The reset path is being established in issue #30 — check that
  issue for the answer, and if it is still open, do not start schema work.
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
- **No** → **use `.style.css` annex files.** Zero dependencies, no build plugin, no `jac install`.

**Do not add Tailwind to a non-shadcn project here.** That path needs
`jac add --npm --dev tailwindcss @tailwindcss/vite` plus a `[plugins.client.vite]` block, and
**editing `[dependencies.npm]` installs nothing on its own — `jac install` must run after.** Whether
jachammer runs `jac install` on a `jac.toml` change is not documented anywhere in its platform docs.
Not a risk worth taking for styling.

### `.style.css` annexes — the default, and why they suit three people

A CSS file with the **same base name** as a component is auto-scoped to that module. No import — the
compiler pairs them, hashes each declared class, and rewrites the matching `className` literals.

```jac
# components/ConcernRow.cl.jac
def:pub ConcernRow(row: Row) -> JsxElement {
    return <div className="row"><h3 className="row-q">{row.question}</h3></div>;
}
```
```css
/* components/ConcernRow.style.css — paired by base name; do NOT import it */
.row { padding: 1rem; border: 1px solid #ddd; }
.row-q { font-weight: 600; }
:global(body) { margin: 0; }   /* :global() opts out of scoping */
```

`className="row"` compiles to `row-1419142b`, so **two people can both declare `.row` and never
collide.** Each component is one owner, two files, and there is no shared global stylesheet to fight
over — which is the whole reason this is the default rather than a compromise.

- Base name must match **exactly**: `ConcernRow.cl.jac` ↔ `ConcernRow.style.css`.
- Undeclared class tokens pass through untouched, so scoped and utility classes can mix.
- Plain-CSS projects **may** use a `*` reset. Tailwind projects may not — it collapses spacing
  utilities by conflicting with Preflight.

## Conventions

- **All application code is Jac.** Python only as libraries imported into Jac. No separate Python
  service, no separate React app.
- **Zero non-Jac artifacts.** The vocabulary and curated interaction table are inline `glob`s, not
  JSON files — jachammer has no filesystem.
- **`main.jac` is the spine, owned by T3 (Laksh) alone. Do not edit it** — see `CONTRACTS.md` §1a. In #17 it
  is the literal single-file vertical slice (inline archetypes + `Remember` + `Prepare` + the page
  UI), and that commit is tagged `single-file-slice`. After that it shrinks to `include` lines plus
  the `cl { }` entry. Contributions reach it as modules; you comment the `include` line on #17.
- **Never refactor the `cl { }` block out of `main.jac`.** Server and client in one mixed-context
  entry file is a scored rubric property. Sub-components live in `components/*.cl.jac`.
- **`walkers/recall.jac` contains no `while` loop.** Policy lives on node-type abilities.
- **No scheduler, cron, or background sweep.** `Vigil` on app open is the trigger.
- **Never cut `Prepare` or the concerns page.** It is the deliverable. Drop order is `Shortcut`,
  then channel-A reinforcement, then `Investigate` step 3, then channel A.

## Working agreement

- Work from an issue. Branch, PR, and label conventions are in `CONTRIBUTING.md`.
- **Check `CONTRACTS.md` before changing any shared shape**, and follow the announcement rule there
  if you must.
- **Two files are single-owner. Do not edit either on a feature branch.** `graph/archetypes.jac`
  (frozen after stage 1 — open a `schema` issue) and `main.jac` (T3's — comment the `include` line
  you need on #17).
- Do not start a new task while a prior one has a failing acceptance check.
- Surface the open decisions in `ARCHITECTURE.md` section 18 rather than resolving them.
- When reporting, state: which issue, which acceptance check passed, and any invariant currently
  violated even temporarily.
