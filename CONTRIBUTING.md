# CONTRIBUTING

How we chunk work across members and parallelize development.

**Sized for a one-day build.** Everything here is either a naming convention or a one-line label —
if any of it starts costing more than a few seconds per issue, drop it and say so.

---

## 0. The four rules that actually prevent collisions

Everything else in this file is detail. These four do the work:

1. **One issue owns one file.** The repo layout is one file per walker precisely so that issues map
   to files. If your issue needs two files in two tracks, it is two issues.
2. **`graph/archetypes.jac` is frozen after stage 1** and owned by T1. Editing it on a feature
   branch corrupts everyone's persisted graph on merge.
3. **`main.jac` is owned by T4 and nobody else opens it.** Your code goes in a module you own; you
   comment on #17 with the `include` line you need. See `CONTRACTS.md` §1a — this is the answer to
   "how do four people share one file", and the answer is that they don't.
4. **Build against `CONTRACTS.md`, not against other people's code.** If the producer doesn't exist
   yet, stub it (§7 of `CONTRACTS.md`). Nobody waits.

---

## 1. Tracks

Four people, four tracks. **T1's schema issue (#1) blocks the graph work; everything else starts in
hour one** — T2 on stubs, T3 on report objs, T4 on the platform smoke test.

| Track | Label | Owns | Hour one |
|---|---|---|---|
| **T1 — Graph & Write** | `track:graph-write` | `graph/archetypes.jac`, `graph/vocab.jac`, `ingest/regimen.jac`, `walkers/remember.jac`, `walkers/consolidate.jac`, `seed/patient.jac` | **#1**, once #30 reports the reset path |
| **T2 — Traversal & Eval** | `track:traversal-eval` | `walkers/recall.jac`, `walkers/investigate.jac`, `eval/*` | review #1's checklist, then stub `Recall` |
| **T3 — Page & Templates** | `track:page` | `graph/reports.jac`, `components/*.cl.jac`, `render/templates.jac` | **#29**, unblocked |
| **T4 — Spine & Platform** | `track:shell-platform` | **`main.jac`**, `jac.toml`, `walkers/prepare.jac`, `walkers/vigil.jac`, jachammer project, deploys | **#30**, first thing, blocks #1 |

**T3 is deliberately unblocked.** The concerns page is the deliverable and it can be built entirely
against the `PageModel` contract before a single traversal is real.

**T4 is the critical path in hour one and the integration point after.** #30 gates #1, and T4 owns
the only file every other track routes through.

**The producer/consumer split is intentional.** `Prepare` (T4) produces the `PageModel` the page
(T3) consumes; `Recall` (T2) produces the `Concern` list `Prepare` consumes. Each seam is a pinned
shape in `CONTRACTS.md` with a stub on the producing side, which is what lets all four move at once.

---

## 1a. Beginning implementation

Read `ARCHITECTURE.md` §2 (invariants) and `CONTRACTS.md` once. Then:

### Before anyone writes application code

**T4 runs #30 — issue zero.** Five platform assumptions become facts: node/edge persistence across a
preview restart, `root spawn` from inside `cl { }`, `by llm()` returning a typed obj, a project-scoped
env var readable at runtime, and a sandbox deploy serving a page. It also records **the graph reset
path**, which is what unblocks #1.

Two of those five failing would change the architecture rather than the schedule. That is why it is
first, and why nobody should be deep in a branch while it is still open.

### In parallel with #30, from minute one

- **T3 → #29.** Report objs. Explicitly unblocked, does not wait on #1.
- **T1 → #2.** The vocabulary glob is just anchor keys and `Member` pairs. Write the data now; wire
  the edges after #1 merges.
- **T2 → read #1's completeness checklist and push back on it.** T2 is the heaviest consumer of the
  schema and #1 freezes it. Thirty minutes spent here is cheaper than a mid-build `schema` issue that
  resets four graphs.

### Then

**#30 closes → #1 opens → #1 merges → the freeze lands.** Announce it. Everyone resets their graph.

After that all four tracks fan out against `CONTRACTS.md`, stubbing every producer that does not
exist yet (§7). T4 writes #17 and tags `single-file-slice`.

**First integration checkpoint:** the seeded patient (#7) rendering real rows on the page (#20),
through whatever mix of stubs and real walkers exists at that moment. Get there early and keep it
green. It is the demo spine, and it is the thing that tells you which stubs still matter.

---

## 2. Labels

| Label | Meaning |
|---|---|
| `track:graph-write` `track:traversal-eval` `track:page` `track:shell-platform` | which track owns it |
| `stage:1` … `stage:10` | which build stage from `ARCHITECTURE.md` §11 |
| `schema` | touches `graph/archetypes.jac`. **Serialize these. Announce on merge.** |
| `spine` | needs a line in `main.jac`. **Do not edit it — comment the line on #17.** |
| `contract` | changes a pinned shape in `CONTRACTS.md`. Needs an ack before merge. |
| `safety` | touches anything governed by S1–S9 or A1–A9. Needs a second reader. |
| `status:blocked` | do not start. Body must name the blocker. |
| `stub` | ships a shape-valid placeholder, not the real thing |
| `cut-candidate` | first to go if the schedule slips |

`schema`, `contract`, and `safety` are the only three that change how a PR gets handled. The rest
are for sorting.

---

## 3. Issue shape

Title: imperative, names the file. *"Implement `Vigil` elapsed-time checks"* — not *"vigil stuff"*.

Body, five lines:

```markdown
**Track:** T4
**Files:** walkers/vigil.jac
**Contract:** consumes PageModel; produces Concern(kind=adherence_gap|silence|...)
**Blocked by:** #3 (archetypes)
**Acceptance:** on the seeded graph with a 4-day observation gap, Vigil emits
                exactly one `silence` Concern at `mention`, and zero LLM calls fire.
```

**The acceptance check is the point.** It is how we know an issue is done without reading the diff,
and it maps to the stage checks in `ARCHITECTURE.md` §11. An issue with no acceptance check is not
ready to pick up.

---

## 4. Picking up an issue

1. **Read the whole body and all comments** — especially cross-reference comments ("relates to
   #N"). Those exist to prevent duplicate or conflicting work.
2. **Check the labels.** Do not start a `status:blocked` issue until its blocker is closed.
3. **Read `CONTRACTS.md`** for any pinned shape your change touches.
4. **Read the relevant source before planning.** Don't guess at file locations or existing
   contracts.
5. **Keep the plan scoped to the issue.** No bundled refactors, no drive-by fixes in another track's
   files.
6. **Load the Jac guides for what you're writing** (see `CLAUDE.md` → Using Jac). The gotchas cost
   an hour each if hit cold.

---

## 5. Branch, commit, PR

**Branch off `main`:**

```
issue-<number>-<short-slug>        e.g. issue-12-vigil-silence-detection
```

**Commit messages:**

```
<track>: <what changed>            e.g. T4: Vigil emits silence Concern on observation gap

Refs #12
```

Commit incrementally. Push the branch as soon as it exists — a pushed branch is how everyone else
knows that file is taken.

**PR body — four lines, non-negotiable:**

```markdown
Fixes #12

**Acceptance:** <paste the actual output that proves the check passed>
**Invariants touched:** none
**New `by llm()` sites:** none
```

Those last two lines exist because this project has nine safety invariants and a hard cap of two
`by llm()` sites. "none" is the expected answer. Anything else needs a human to look before merge.

Use `Relates to #N` instead of `Fixes #N` when the PR doesn't fully close the issue.

**Comment on the issue itself** summarizing what changed and linking the PR, so the issue thread
stays a readable record for anyone not reading the diff.

**Do not close or merge other issues** that were cross-referenced as related — reference them only,
unless your change actually resolves them too.

---

## 6. Handling the three special labels

### `schema` — touching `graph/archetypes.jac`

The file corrupts every persisted graph when it changes. So:

1. Only its owner edits it.
2. Batch schema changes — don't merge three in a row.
3. On merge, comment in the team channel: **"schema changed, reset your graph."**
4. Everyone pulls, then clears their persisted graph (locally `rm -rf .jac/data/`; on jachammer,
   whatever the equivalent turns out to be — **find this before stage 1**).

Symptom of a missed reset: `NodeAnchor ... is not a valid reference!`

### `contract` — changing a pinned shape

Follow `CONTRACTS.md` §8. Short version: announce, get one ack from an affected track, change the
contract and every consumer in the same PR.

### `safety` — touching S1–S9 or A1–A9

Second reader required before merge. The reader's job is one question: *does this let a sentence
reach the patient that no `Utterance` supports?*

---

## 7. When you're blocked

**Don't wait. Stub it.**

Write the shape-valid placeholder from `CONTRACTS.md` §7, label the issue `stub`, and open a
follow-up issue for the real implementation. A stub is done when it returns the right shape and
`jac check .` passes.

This is what keeps four tracks moving on one graph.

---

## 8. Definition of done

An issue is done when **all four** hold:

- [ ] The acceptance check passes, and its output is pasted in the PR.
- [ ] `jac check .` is clean.
- [ ] No invariant is violated, even temporarily.
- [ ] The issue thread has a comment saying what changed.

Do not start a new issue while a prior one has a failing acceptance check.

---

## 9. Reporting

When you report progress — in the issue, the PR, or the channel — state:

- which issue, and which acceptance check passed
- any invariant currently violated, **even temporarily**
- any place a third `by llm()` site was needed, and why
- current `recall@constraint` numbers, once stage 6 exists

Surface the open decisions in `ARCHITECTURE.md` §18 rather than resolving them.
