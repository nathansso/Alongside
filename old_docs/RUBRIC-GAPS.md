# RUBRIC-GAPS.md

Work queue. Seven tasks, ordered by value over cost. Each has an acceptance check.

Derived from the official judging rubric. This file supersedes the priority ordering in
`PROPOSAL.md` section 9 for the next several hours; the build stages there still define what
"done" means for the underlying system.

---

## Scorecard as of handoff

| Criterion | Status | Gap |
|---|---|---|
| Technical Execution | **weak** | scope inflated to 9 stages + 7 walkers + eval + inspector in one day |
| Use of Jac and Jaseci | strong | one direct miss: "single-file full-stack development" |
| Creativity and Innovation | strong | saturated category, the hook carries it |
| Presentation and Demo | **weak** | beat list is not a script; jargon-dense |
| Impact and Novelty | good | no grounded number anywhere |
| Depth of Agentic Behavior | good in code | mostly invisible in a 3-minute demo |

Four of six are fine. Two are not. The queue below targets the two weak ones plus the invisible
one.

---

## T1. `DEMO_MODE` flag

**Criterion:** Technical Execution.
**Estimate:** 30 min.
**Priority:** highest. Do this first.

When `DEMO_MODE` is set, the app runs entirely off the seeded graph with **zero live LLM calls**.
Extraction, `Conflicts` derivation, and message drafting all return pre-computed results keyed to
the seeded utterances.

**Why:** the demo currently depends on network latency and a model returning well-formed JSON in
front of judges. Sentinel's writeup (1st place, Spring) names demo performance as its single
biggest challenge, a 10-minute pipeline that was unusable live and had to be cut to under 2.

**Where:** an env var or config read at spawn. The three `by llm()` call sites branch on it.

**Acceptance:**
- With the flag set and the network disconnected, the full demo spine runs end to end.
- Output is byte-identical across three consecutive runs.
- With the flag unset, live behavior is unchanged.

---

## T2. Pitch script

**Criterion:** Presentation and Demo.
**Estimate:** 30 min plus rehearsal.
**Priority:** high. Not a code task, but nobody has written it.

Currently there is a beat list, not a script. The rubric asks whether someone who knows nothing
about the project would understand it.

**Hard rule: no architecture vocabulary before beat 3 lands.** Say "the two things your doctors
each prescribed separately," not "two ingredient anchors converging on a symptom anchor." Anchors,
channels, walkers, and the primitive census all belong in beat 5, after the judge already
understands what happened.

**Opening line**, roughly:

> Two doctors each prescribed something safe. Nobody was in both rooms. Together they are not
> safe, and there is no system that catches that.

**Closing line:**

> Most agents decide how to search. This one decides what to tell you before you ask.

**Also prepare three answers.** These will be asked:
1. Why not a vector database?
2. How many curated interaction pairs, and sourced from where?
3. What happens when the drug is not in your vocabulary?

Answer 3 is a strength. Make sure the demo surfaces it (see T7 in `PROPOSAL.md` section 11, "do
demo deliberately").

**Acceptance:**
- Script written, presenter assigned.
- Rehearsed twice with a stopwatch, lands under 3:00.
- Beats 1 through 4 contain zero instances of: anchor, channel, walker, traversal, node, edge.

---

## T3. Agent activity panel

**Criterion:** Depth of Agentic Behavior.
**Estimate:** 20 min.
**Priority:** high.

`Consolidate` planning and `Synthesize` corroboration are the strongest depth stories and both are
currently invisible. A judge cannot watch a budget get spent.

Add a small panel that logs, after each turn, what the system did without being asked:

```
Vigil ran before input: 3 checks, 1 finding
Consolidate examined 6 of 34 constraint pairs, 28 queued
Synthesize promoted 1 finding on corroboration
Investigate assembled a case file across 9 observations
```

**Why:** makes four autonomous behaviors visible in one glance without adding a demo beat. The
rubric's phrasing is "show us real autonomous behavior," and "wrapping an API call doesn't count."

**Where:** `ui/App.cl.jac`, fed from walker report payloads. Do not add new walker logic to
produce these numbers; they should already exist as internal state.

**Acceptance:**
- Panel renders after every turn with live counts.
- Counts are read from walker output, not hardcoded.
- Panel is visible during demo beat 2 and beat 4.

---

## T4. One single-file vertical slice

**Criterion:** Use of Jac and Jaseci.
**Estimate:** 45 min.
**Priority:** medium-high.

The rubric names four things: `by llm()`, walkers, graph-native data modeling, and **single-file
full-stack development**. The first three are covered well. The fourth is not: the repo map has 17
files, which is good engineering and fails to demonstrate the exact property being scored.

Make one file a genuine vertical slice: walker, graph traversal, and UI in the same `.jac` file.
`ui/Inspector.cl.jac` is the natural candidate.

**Why:** at demo beat 5, open that file and say "this file is the backend, the frontend, and the
AI." You do not need to restructure the repo. You need one file that proves the claim.

**Acceptance:**
- One file contains a walker definition, a graph traversal, and rendered UI.
- It runs standalone.
- It is the file opened at beat 5.

---

## T5. Time gates

**Criterion:** Technical Execution.
**Estimate:** 5 min.
**Priority:** medium-high. Costs almost nothing and prevents the worst outcome.

Write these down and honor them. Decisions made now beat decisions made at 5:30 PM under partial
submission pressure.

| Gate | If not met |
|---|---|
| Stage 4 (`Recall` channel B) passing by **2:30 PM** | Cut `Prepare`, `Shortcut`, `ThresholdAgent` immediately |
| Inspector rendering by **4:30 PM** | Split pane becomes two static screenshots; eval numbers read aloud, not run live |
| Anything not working by **5:30 PM** | It is not in the demo. Submit the partial at 5:50 regardless. |

Standing drop order from `PROPOSAL.md`: `Prepare`, then `Shortcut`, then channel A reinforcement,
then channel A entirely. Dropping all four leaves the gate, the guarantee, the measurement, and
the demo intact.

**Acceptance:** gates are visible to the whole team, not just in this file.

---

## T6. One grounded statistic

**Criterion:** Impact and Novelty.
**Estimate:** 20 min.
**Priority:** medium.

The pitch currently opens with no number. Sentinel opened with $100 billion in annual Medicare
fraud and it framed everything that followed.

Find one citable statistic on multi-prescriber cancer patients, polypharmacy in oncology, or
interaction-driven adverse events. Put it in the first fifteen seconds of the pitch and cite the
source on the Devpost writeup.

**Acceptance:**
- One number, one named source, in the opening.
- Source is a primary one (journal, government agency, professional body), not an aggregator or a
  content-marketing page.

---

## T7. Jaseci platform features in the writeup

**Criterion:** Use of Jac and Jaseci.
**Estimate:** 10 min.
**Priority:** low, but nearly free.

Nothing currently mentions that walkers auto-expose as REST endpoints, or that `def:priv` scopes
every walker to the caller's root. The criterion says "Jac and Jaseci," and this is the Jaseci
half.

For a health product the line is strong and costs nothing:

> Patient graphs cannot reach each other because there is no query surface on which they could.
> Per-patient isolation is a language property, not a tenancy layer we built.

**Acceptance:** appears in the Devpost writeup and in beat 5 if time allows.

---

## Verify before claiming

Three things asserted in the docs that have not been checked. Do not say any of them on stage
until confirmed.

1. **The 40% Jac floor.** `PROPOSAL.md` assumes Python-as-imported-library counts toward the Jac
   share because of the superset relationship. Confirm how the organizers actually measure it.
2. **Jaseci primitive names.** Generate, Extract, Invoke, Route, Pipe, Loop, Spawn are taken from
   the Jaseci agentic-AI tutorial repo. Confirm against current workshop material.
3. **Native OSP persistence.** GraphClaw (1st place, Winter) fell back to a JSON store because OSP
   property-graph persistence was not stable on their Jac build. If this build runs on native OSP,
   that is a real JacHammer differentiator. Verify before saying it.

---

## Ordering

```
T1  DEMO_MODE flag              30 min   Technical Execution
T2  Pitch script                30 min   Presentation
T3  Agent activity panel        20 min   Agentic Depth
T4  Single-file vertical slice  45 min   Use of Jac
T5  Time gates                   5 min   Technical Execution
T6  Grounded statistic          20 min   Impact
T7  Jaseci platform line        10 min   Use of Jac
```

T1 through T3 are under 90 minutes combined and move the two weakest criteria plus the invisible
one. If only three tasks get done, do those three.
