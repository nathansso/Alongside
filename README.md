# myCancerPal

A longitudinal treatment companion for cancer patients, built on a persistent Jac graph.

**Relevance is reachability, not similarity.**

---

## The problem

Two doctors each prescribe something safe. Nobody was in both rooms. Together they are not safe,
and no system catches that.

Cancer patients move between medical oncology, primary care, and urgent care, collecting
prescriptions from people who cannot see each other's notes. Meanwhile the symptoms that matter
most happen *between* visits, get under-reported, and arrive at the next appointment compressed
into "I've been okay, I guess."

## What it does

The patient checks in daily about how they feel and what they took. A persistent graph accumulates
those check-ins as typed beliefs linked to deterministically-parsed medication anchors. Two things
run off it:

- **An interaction gate.** Before a new substance enters the regimen, a mandatory graph traversal
  runs. A hard constraint violation blocks.
- **Unprompted concern surfacing.** Opening the app runs detection before you type anything.

The output is **"Questions for your care team"** — a standing page that accumulates and drains, the
thing you bring to your appointment. Every row cites the exact sentence it came from.

## Why a graph

Top-k retrieval fails **silently**: a blocking fact ranked 11th is indistinguishable from a fact
that does not exist. Graph traversal fails **visibly**: if a constraint is connected to the anchor
it is reached, and if it is not reached, the edge is missing — and a missing edge is inspectable.

That turns the central claim into a *safety* property rather than a retrieval improvement.

It also makes two classes of finding possible that a similarity index cannot produce at any *k*:

- **Convergence** — two drugs from two prescribers reaching the same toxicity through a shared
  vocabulary node. A triangle nobody was positioned to see.
- **Absence** — a symptom with no attributing edge, a prescription with no adherence record, a gap
  in the check-in chain. *A retriever cannot rank a document that does not exist.*

## Safety posture

This is a recall layer over what the care team already said. It is not a clinician.

- The graph never originates a clinical fact. Authority lives in the parsed artifact.
- Every finding cites a source. Absence yields **"not in your record"** — never *"safe."*
- No dosing judgments, substitutions, or discontinuation advice, ever.
- **No outbound path exists.** The system renders a page. The patient carries it.
- Every sentence the patient reads is a template filled from the graph or a verbatim quote. The
  model never writes prose about anyone's care.

## Stack

Jac end to end — graph, walkers, LLM calls, and UI in one language. Deployed on
[jachammer](https://jachammer.ai).

`main.jac` is a genuine single-file vertical slice: the data model, a walker with a real traversal,
an `by llm()` call, and the page UI, all in one file.

Per-patient isolation is a language property, not a tenancy layer we built — patient graphs cannot
reach each other because there is no query surface on which they could.

## Docs

| File | What |
|---|---|
| `ARCHITECTURE.md` | **Start here.** Invariants, walkers, build order, demo spine |
| `CONTRACTS.md` | Pinned shapes — read before changing anything shared |
| `CONTRIBUTING.md` | Tracks, labels, branch/PR conventions |
| `CLAUDE.md` | Auto-loaded agent context and Jac usage notes |
| `old_docs/` | Superseded. Do not build from these. |

Built for JacHacks SF. Tracks: Social Impact, Agentic AI, Best JacHammer.
