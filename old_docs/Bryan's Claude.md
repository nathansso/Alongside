# CLAUDE.md

Auto-loaded context. Keep this file short; it is read at the start of every session.

## Project

Longitudinal treatment companion for cancer patients. A persistent Jac graph accumulates daily
check-ins as typed beliefs linked to deterministically-parsed anchors. Retrieval is graph
traversal, not similarity search. Built for JacHacks SF, July 26 2026.

**Tracks:** Social Impact, Agentic AI, Best JacHammer.

## Doc map

| File | Read when | Authority |
|---|---|---|
| `PROPOSAL.md` | before writing any code | **authoritative** for invariants, walker contracts, build order |
| `RUBRIC-GAPS.md` | now | the current work queue |
| `DECISIONS.md` | when questioning a design choice | rationale only, not binding |
| `memory-as-topology.md` | engine semantics | superseded by `PROPOSAL.md` on conflict |
| `cancer-domain-instantiation.md` | domain vocabulary | superseded by `PROPOSAL.md` on conflict |

## Non-negotiables

Full list in `PROPOSAL.md` section 2. These are the ones most likely to get broken by accident:

- **A1** Anchors are never invented by `by llm()`. Anchor creation requires vocabulary membership.
  A miss writes `needs_review = True` and creates no anchor.
- **A2** Channel B is unscored, unpruned, exempt from decay, beam, budget, and waterline. Only
  `Supersedes` kills a channel B constraint.
- **A3** The model never selects a traversal path. No `visit [-->] by llm()` anywhere in
  `walkers/`.
- **A4** Embeddings appear only in `eval/`. Nothing in `walkers/` imports `eval/baseline.jac`.
- **A5** `Synthesize` corroboration promotes severity only. Never demotes. A channel B hit reaches
  `draft` alone.
- **S3** Absence of a finding yields "not in your record". Never "safe".
- **S4** No dosing judgments, substitutions, dose calculations, or discontinuation advice.
- **S7** No autonomous outbound communication. The system drafts; the patient sends.

Exactly three `by llm()` calls exist. Adding a fourth requires human approval.

If a request would require violating any of these, do not implement it. Report the conflict.

## Jac gotchas

These cost an hour each if hit cold.

- **Editing archetypes corrupts the local graph.** `jac run` persists to cwd `.jac/`. Changing a
  node or edge definition between runs gives `NodeAnchor ... is not a valid reference!`. Reflex:
  `rm -rf .jac/data/` and restart.
- **Edge abilities are a silent no-op.** `can ... with Walker entry` inside an `edge` compiles
  clean and never fires. All scoring lives in walker node abilities reading `[edge ...]`.
- **`++>` returns a list.** `b = (anchor ++> Belief(claim=c))[0];`. A missing `[0]` fails somewhere
  else entirely.
- **Typed edge deletion needs `[edge ...]` plus iterate-`del`.** `del [a ->:Supersedes:-> b];`
  passes `jac check` and fails at runtime with E5043.
- **`by llm()` returns `obj`, never `node`.** Extract into an obj, copy into the node.
- **Type the report channel.** `has verdict: Verdict = Verdict();`. Omitting the default makes it a
  required spawn parameter and every spawn fails E1050.
- **Declare endpoints on every edge.** Untyped edges yield `Unknown`-typed nodes that pass
  `jac check` and fail later.
- **Report once from `with Root exit`.** Per-node reporting scatters N tiny reports.

## Conventions

- All application code is Jac. Python appears only as libraries imported into Jac.
- No separate Python service. No separate React app. UI is `.cl.jac`.
- `data/*.json` are the only non-Jac artifacts.
- No scheduler, cron, or background sweep. `Vigil` on app open is the trigger.
- `walkers/recall.jac` must contain no `while` loop. Policy lives on node-type abilities.

## Working agreement

- Work the queue in `RUBRIC-GAPS.md` in the stated order unless told otherwise.
- Do not start a new task while a prior one has a failing acceptance check.
- Surface the open decisions in `PROPOSAL.md` section 14 rather than resolving them.
- When reporting, state which task is done, which acceptance check passed, and any invariant
  currently violated even temporarily.
