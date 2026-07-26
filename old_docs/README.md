# old_docs — superseded

**Do not build from anything in this folder.** `ARCHITECTURE.md` in the repo root is authoritative.

Kept for design lineage and rationale only. Every file here predates the consolidation and
describes an architecture that no longer exists.

| File | What it was | Why it's here, not live |
|---|---|---|
| `memory-as-topology.md` | the domain-neutral engine spec | engine semantics survive in `ARCHITECTURE.md`; the rest is superseded |
| `cancer-domain-instantiation.md` | first domain binding | anchor vocabulary and concern classes were absorbed |
| `PROPOSAL.md` | first build contract | described 11 walkers, a drafted outbound message, and `Synthesize` |
| `DECISIONS.md` | rationale for the changes in `PROPOSAL.md` | still the best record of *why*; never binding |
| `RUBRIC-GAPS.md` | judging-rubric work queue | T4 named an impossible file; T5's drop order cut the deliverable |
| `Bryan's Claude.md` | earlier auto-loaded agent context | replaced by `CLAUDE.md` |
| `ISSUE.md` | issue resolution flow | absorbed into `CONTRIBUTING.md` |

## What specifically changed

- **Eleven walkers → six.** The four detection walkers were folded back into `Recall`'s node
  abilities; `Synthesize` became a corroboration rule in `Recall`'s `Root exit`. This eliminated a
  reinforcement double-counting bug and a read-after-write hazard against `Consolidate`'s budgeted
  `Conflicts` derivation.
- **Drafted outbound message → the concerns page.** Nothing is drafted and nothing is sent. S7 is
  now structural: there is no outbound path to misuse.
- **Three `by llm()` sites → two.** Both on the write path. Page copy is template-or-quote (S8).
- **`draft` rung renamed `ask`.** Nothing is drafted.
- **`Prepare` promoted from cut-first to the deliverable.**
- **Three invariants added:** A9 (only `Recall` reinforces), S8 (no generated page copy), S9
  (dismissal mutes, never deletes).
- **`main.jac` is the single-file vertical slice.** The old T4 named `ui/Inspector.cl.jac`, which
  cannot work — the `.cl.jac` extension sets client context, so a walker and a server-side traversal
  cannot live there.
- **Deployment pinned to jachammer**, which forbids a shell and a filesystem. The vocabulary moved
  from `data/*.json` to an inline Jac `glob`, leaving zero non-Jac artifacts.

Three open decisions in `PROPOSAL.md` §14 dissolved rather than being answered: parallel-vs-sequential
detection spawn (no detection walkers exist), `Vigil` placement (the page is the landing surface),
and whether `Concern` and `Violation` merge (`Violation` became evidence inside a `Concern`).
