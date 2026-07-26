# DECISIONS: what changed and why

Companion to `PROPOSAL.md`. That file says what to build. This file says what moved from the
original design and what the argument was, so the reviewer can disagree with a specific decision
rather than the whole package.

Every change below is listed with its cost and whether it is reversible. Nothing here is settled.

**Read order for a reviewing agent:** this file for context, then `PROPOSAL.md` for the contract.
`PROPOSAL.md` is authoritative where they conflict.

---

## 0. Summary

| Change | Cost | Reversible |
|---|---|---|
| C1. Domain-neutral framing dropped as the pitch | none | yes |
| C2. Evaluation moved from non-goal to build stage | ~1 hour | yes |
| C3. Walker set expanded from 3 to 7 | ~2 hours, more surface to break | yes, per walker |
| C4. `Invoke` admitted on the write path | ~45 min, small risk to A1 | yes |
| C5. Corroboration made promotion-only | none | no, this one is a correctness fix |
| C6. Build order reordered | none | yes |
| C7. Traversal inspector kept, patient charts cut | ~1 hour | yes |
| C8. Demo cut to 3 minutes, `Vigil` added as beat 2 | none | yes |

---

## 1. Evidence base

Reviewed both prior JacHacks editions: Winter (Ann Arbor, April 2026, 70 projects) and Spring
(global online, May 2026, 81 projects, 13 winners). Read the full writeups for GraphClaw (1st,
Agentic AI, Winter) and Sentinel (1st, Fintech, Spring).

Four patterns held across every track winner:

1. **Every track winner was an application with a named user.** CivicMesh, MediGraph, Sentinel,
   Killbill, Nourish, PolyWatch, SybilScope, GhostWatch. The only infrastructure-flavored projects
   that placed won special awards, not track firsts: Ori (a Jac template) took Best Use of Jac,
   Jac in the Block (a learning toolkit) took a second place.
2. **Winners quantify aggressively.** Sentinel leads with 98% precision, 39 of 40 flags confirmed,
   $50.6M exposure, and a perf fix from 10 minutes to under 2.
3. **One killer example carries the thesis.** Sentinel's is a patient at two hospitals on
   overlapping dates, framed as something no statistical model catches but graph traversal with
   date arithmetic does.
4. **Visualization is not optional.** ChainViz won Best Use of Jac for a 3D render. Sentinel used
   D3 force-directed graphs with SSE streaming. PairUp won Best Demo outright.

---

## 2. C1: the domain-neutral framing was a liability

**Was:** the spec opened by declaring itself domain-neutral, with no application on top.

**Now:** the engine stays domain-neutral. The pitch is the companion. Domain neutrality is
demonstrated in fifteen seconds at the end (swap the anchor parser and the constraint vocabulary,
same walkers run) rather than led with.

**Why:** zero track winners across two editions were infrastructure. A memory layer with no
application caps out at the $500 JacHammer award. With an application it competes for Social
Impact 1st at $1,500 plus Agentic AI plus JacHammer, and those are not in tension because the
same artifact supports all three.

**Cost:** none. **Reversible:** yes, it is framing.

---

## 3. C2: evaluation moved from non-goal to build stage

**Was:** "benchmark or eval harness" and "no baseline comparison" were both explicit non-goals.

**Now:** stage 5 builds a cosine baseline and reports `recall@constraint`.

**Why:** those were the two things the winning writeups spent the most words on. More
importantly, the central claim of this project is comparative ("traversal reaches what top-k
misses") and an unmeasured comparative claim is an assertion. It takes roughly an hour.

**The embeddings non-goal survives intact.** Invariant A4 keeps the baseline in `eval/` and
forbids `walkers/` from importing it. Embeddings stay out of the retrieval path. The baseline is
a measurement instrument that runs beside the system.

**Lead metric is absence-class recall, not overall recall.** On mechanism 1 a tuned vector store
will do respectably and the gap is a percentage argument. On mechanism 2 the baseline has no
move at all, because a retriever cannot rank a document that does not exist. That is a cleaner
claim.

**Cost:** ~1 hour. **Reversible:** yes.

**Reviewer should push back if:** you think the hour is better spent on the interaction gate.
The counter-argument is that the gate without a number is the same demo everyone else has.

---

## 4. C3: the walker set expanded from three to seven

**Was:** `Remember`, `Recall`, `Consolidate`. Detection mechanisms lived inside `Recall`'s
abilities. The domain doc explicitly said "no fourth walker".

**Now:** seven. Added `Vigil`, `Investigate`, `Synthesize`, and split detection into four
walkers.

**Why:** the judging criteria include *Depth of Agentic Behavior*, phrased as "planning, memory,
tool use, or multi-agent coordination" with "wrapping an API call doesn't count" called out
explicitly. The original design deliberately refuses autonomy at the decision point (mandatory
gate, no Route, no Invoke at the gate). That is correct engineering and it reads on first glance
as *less* agentic. A judge scoring six boxes will not do the reconciliation work.

The fix is not to add autonomy back into retrieval. It is to point at where autonomy already
lives:

- **`Vigil`** runs on app open, before any input exists. Nobody triggered it. This is the
  strongest single change in the package, and it is nearly free: pure arithmetic over
  `Observation` timestamps, no beliefs read, no LLM call. It also solves the deployment problem
  that there is no scheduler, because opening the app is the trigger and opening the app is not a
  request.
- **`Consolidate` planning.** Conflict derivation is n^2 pairs at one LLM call each. It cannot run
  exhaustively and should not run randomly, so it ranks, spends a budget, persists a
  `last_examined` marker, and queues the remainder. Bounded, self-directed, persistent across
  runs.
- **`Investigate`** turns a flag into a case file: onset, correlation with regimen changes,
  counterfactual days, existing-instruction check, cited timeline. This is Sentinel's exact
  winning move, which was that a 98% precise model is worthless if the investigator cannot act on
  the result.
- **Four detection walkers plus `Synthesize`** is Sentinel's five-agents-on-one-graph structure.

**The framing line for the pitch:**

> The agent's autonomy is in what it does to its own memory and what it notices unprompted, not in
> guessing which path to walk. Most agents decide how to search. This one decides what to tell you
> before you ask.

**Cost:** roughly two hours, and seven walkers is more surface to break than three. *Technical
Execution* explicitly scores demo stability, so this is a real trade. Mitigation: most of these
are re-siting logic already specified in *Concern classes* rather than new logic, and the build
order gives a two-walker minimum (`Vigil` + `Investigate`) that carries the depth claim alone.

**Reversible:** yes, per walker.

**Reviewer should push back if:** you think stability matters more than the depth criterion. A
defensible smaller version is `Vigil` + `Investigate` only, leaving detection inside `Recall`.

---

## 5. C4: `Invoke` admitted, on the write path only

**Was:** Invoke refused everywhere, on the grounds that a ReAct loop that *may* call `recall()`
cannot support a guarantee.

**Now:** the gate stays mandatory (invariant A8). But `Remember` uses a ReAct loop to resolve
unrecognized substances against RxNorm.

**Why:** ingestion is a different problem from retrieval. When a patient writes "my neighbor gave
me St. John's Wort", resolving that to an identifier is genuine tool use against an authoritative
vocabulary, and it sits on the write path where a wrong answer costs one node rather than one
path. It also directly answers the "tool use" clause of the agentic criterion, which was
otherwise the weakest of the four categories for this design.

**The guard is what makes this acceptable and it is not optional.** A returned identifier creates
an `Anchor` only if it is already present in the loaded vocabulary. A miss creates no anchor,
writes the belief with `needs_review`, and the drafted message says the substance was not
recognized. The spec's "anchors are never invented by `by llm()`" rule survives: the model chooses
what to look up, the vocabulary decides what exists.

**This is the change most likely to be wrong.** It moves some risk back toward anchor resolution,
which the original design deliberately made deterministic. If the guard is not implemented
exactly, invariant A1 is broken and every traversal downstream is compromised.

**Resulting census:** six of seven Jaseci primitives used, Route refused on principle. That is a
better line than seven of seven, and it is the only version that is true.

**Cost:** ~45 minutes. **Reversible:** yes. **Recommendation if uncertain:** skip it. Losing the
tool-use clause is cheaper than losing A1.

---

## 6. C5: corroboration promotes only

**Was:** not specified.

**Now:** `Synthesize` may raise severity when two detection walkers converge on the same anchor.
It may never lower it. A channel B hit reaches `draft` uncorroborated.

**Why this is a correctness fix, not a preference:** Sentinel's synthesis agent requires
corroborating evidence before escalating to HIGH, and that drove its precision to 98%. Copying
that pattern directly would be wrong here. Applied to a hard constraint, requiring corroboration
before escalating is a silent-failure generator: a real interaction goes unreported because only
one walker happened to find it. That is exactly the failure mode the two-channel split exists to
eliminate.

Promotion only. The guarantee is not subject to a vote.

**Cost:** none. **Reversible:** no. If this is reversed, the channel B guarantee is void.

---

## 7. C6: build order reordered

**Was:** seven stages, `Shortcut` at 6 and `Conflicts` at 7.

**Now:** nine stages. Baseline at 5, `Conflicts` at 6, channel A at 7, inspector at 8, `Shortcut`
at 9.

**Why:** stage 4 before channel A was already correct and is unchanged, because the safety
property is the contribution and the scored beam is an optimization over the part allowed to be
lossy. What changed is that `Conflicts` moved ahead of `Shortcut`. `Conflicts` produces the
additive-toxicity triangle, which is the headline demonstration. `Shortcut` is a traversal-cost
optimization invisible from outside the system. If the schedule slips, `Shortcut` should be the
thing that dies.

**Cost:** none. **Reversible:** yes.

---

## 8. C7: patient charts cut, traversal inspector kept

**Was:** "cut trend charts and visualizations entirely".

**Now:** patient-facing trend charts and timeline scrolls stay cut. The two-pane traversal
inspector is added at stage 8.

**Why:** these are different artifacts serving different audiences. The charts show the patient
their data, cost real time, and invite the dosing question the safety posture forbids. The
inspector shows a judge the algorithm, and the graph is the argument. ChainViz won Best Use of Jac
on a render; Sentinel used D3 for its investigation graphs. A graph-native project with no visible
graph leaves a lot on the table.

**Implementation note:** keep it in `.cl.jac` rather than a separate React app. Frontend, backend,
and AI in one language is the property the stack claims about itself, and a Jac frontend both
exercises that claim and keeps the Jac share high.

**Cost:** ~1 hour. **Reversible:** yes.

---

## 9. C8: demo cut to three minutes, `Vigil` added as beat 2

**Was:** four minutes, with a "normal check-in" beat establishing the alert-fatigue control before
showing an alert.

**Now:** three minutes. The normal check-in is cut; `Vigil` speaking first takes its place.

**Why:** the hacker guide allots 4-minute demos, the judging criteria say 3-minute pitch. Build to
the shorter number. `Vigil` is the cheapest point in the demo and makes the autonomy claim in five
seconds rather than arguing it in thirty.

**What was lost:** the alert-fatigue setup was doing real work. If seconds are available, fold it
into beat 2 by having `Vigil` surface one thing and stay silent about four others.

**Cost:** none. **Reversible:** yes.

---

## 10. Risks the reviewer should weigh

### 10.1 GraphClaw already won with an adjacent idea

GraphClaw took 1st in Agentic AI at JacHacks Winter with "memory lives in a property graph, agents
are graph walkers", including typed fact nodes with confidence decaying 1% per day, tombstoning at
~90 days, and a background walker doing revalidation and pruning. That is the extract, decay,
prune loop, already awarded, by an organization with likely overlapping judges.

Three deltas, in descending order of weight:

1. **The two-channel split.** A single scored store, however well it decays, answers "what is
   probably relevant". It cannot answer "what must not be violated", because any weight on a hard
   constraint makes its retrieval probabilistic.
2. **`Conflicts` derivation.** Two separately-stated constraints being jointly unsatisfiable is
   not a result a decaying graph or a vector index produces.
3. **Provenance as a correctness property.** `DerivedFrom` on every belief, source and timestamp
   inline on every `Violation`, so an explanation is a field read.

One implementation delta worth checking before claiming: GraphClaw fell back to a JSON store with
graph semantics layered on top, because full OSP property-graph persistence was not stable on the
Jac build available to them. If this build runs on native OSP persistence, that is a concrete
JacHammer differentiator. **Verify it before saying it.**

### 10.2 The MediGraph collision is on our weakest mechanism

MediGraph (2nd, Agentic AI, Spring) checked medication safety by reasoning through drug chemistry
rather than a lookup table. Section 13 of `PROPOSAL.md` commits to a hand-curated interaction
table, which is precisely what MediGraph positioned itself against.

**Do not compete there.** The pairwise interaction check is the least interesting mechanism in the
design and it is table stakes. The delta is absence-class detection, which has no analogue in
either MediGraph or CONSILIUM because both are single-encounter systems. A symptom with no
attributing edge, a prescription with no adherence record, a gap in the check-in chain: none of
those are findable in a transcript at any model quality, because the signal is a thing that is not
there.

If the demo leads with a pairwise interaction check, this gets scored as MediGraph with extra
steps.

### 10.3 Health is the saturated category

Spring had two health winners out of thirteen. This enters a crowded field. The safety posture
also forbids the most dramatic possible output: no dosing conclusions, ever. That is a trade of
demo drama for defensibility, which is the right trade with clinicians in the room and still a
real cost.

### 10.4 Unverified claims in the proposal

Three things asserted that should be checked before they are said out loud:

1. **The 40% Jac floor.** `PROPOSAL.md` assumes Python-as-imported-library counts as Jac because
   of the superset relationship. Confirm how the organizers actually measure the ratio.
2. **The Jaseci primitive names.** Generate, Extract, Invoke, Route, Pipe, Loop, Spawn are taken
   from the Jaseci agentic-AI tutorial repo. Confirm against current workshop material before
   using them in the writeup.
3. **Native OSP persistence.** See 10.1.

---

## 11. What is not up for negotiation

Everything above is a decision that can be reversed by the reviewer. These are not:

- The safety invariants S1 through S7 in `PROPOSAL.md` section 2.1.
- Invariant A1 (anchors never invented) and A2 (channel B unscored).
- Invariant A5 (corroboration promotes only), for the reason in section 6 above.

If a change would require relaxing any of these, the right answer is to cut the feature.
