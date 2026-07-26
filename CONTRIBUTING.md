# CONTRIBUTING

How we chunk work across members and parallelize development.

**Sized for a one-day build.** Everything here is either a naming convention or a one-line label —
if any of it starts costing more than a few seconds per issue, drop it and say so.

---

## 0. The three rules that actually prevent collisions

Everything else in this file is detail. These three do the work:

1. **One issue owns one file.** The repo layout is one file per walker precisely so that issues map
   to files. If your issue needs two files in two tracks, it is two issues.
2. **`graph/archetypes.jac` is frozen after stage 1** and owned by one person. Editing it on a
   feature branch corrupts everyone's persisted graph on merge.
3. **Build against `CONTRACTS.md`, not against other people's code.** If the producer doesn't exist
   yet, stub it (§7 of `CONTRACTS.md`). Nobody waits.

---

## 1. Tracks

Work splits five ways. **Track A blocks everything; B, C, D, and E run in parallel after it.**

| Track | Owns | Depends on |
|---|---|---|
| **A — Graph & ingest** | `graph/archetypes.jac`, `graph/vocab.jac`, `ingest/regimen.jac`, `seed/patient.jac` | nothing. **Do this first.** |
| **B — Read path** | `walkers/recall.jac`, `walkers/investigate.jac` | A |
| **C — Write path** | `walkers/remember.jac`, `walkers/consolidate.jac` | A |
| **D — Surface** | `main.jac`, `walkers/prepare.jac`, `walkers/vigil.jac`, `render/templates.jac`, `components/*.cl.jac` | contracts only — **start on stubs immediately** |
| **E — Demo & eval** | `eval/*`, `DEMO_MODE` branches, pitch script, activity panel wiring | fixtures from A |

Track D is deliberately unblocked. The concerns page is the deliverable and it can be built entirely
against the `PageModel` contract before a single traversal is real.

---

## 2. Labels

| Label | Meaning |
|---|---|
| `track:a` … `track:e` | which track owns it |
| `stage:1` … `stage:10` | which build stage from `ARCHITECTURE.md` §11 |
| `schema` | touches `graph/archetypes.jac`. **Serialize these. Announce on merge.** |
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
**Track:** D
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
<track>: <what changed>            e.g. D: Vigil emits silence Concern on observation gap

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
