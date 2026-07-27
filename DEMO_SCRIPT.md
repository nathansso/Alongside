# Alongside — 2-minute demo narration script

A voiceover script timed to `alongside-demo.mp4` (a silent ~1:53 screen recording of the
rebuilt five-view app). Read it live over the video. Timestamps are approximate; the video is
paced with pauses on each view so you have room to talk. Target pace is roughly 150 words per
minute, so each segment's script is sized to fit its window.

Structure: the narration carries **the problem**, then **the solution**, with **the backend
explanation** folded in where the Visualize view makes it concrete. A deeper standalone backend
section follows at the end for Q&A or a longer cut.

---

## Cold open (say before you hit play, ~5s)

> "My grandfather has cancer. I see him every few years, so I see the endpoints. He lives the
> slope, and the person inside a gradual decline is the last one positioned to see it. Alongside
> is built for that gap."

---

## Segment 1 — Landing · the problem  (0:00–0:11)

**On screen:** the landing page. Hero, the "8 days later" card, "How it works."

> "Cancer patients collect prescriptions from oncology, primary care, and urgent care, from
> clinicians who don't share notes. Two doctors each prescribe something safe; nobody was in
> both rooms; together they aren't. And the symptoms that matter most happen between visits, then
> get compressed into 'I've been okay, I guess.' Alongside's whole job is to hold that signal."

*Talking point if you have a beat:* nearly half of patients on oral cancer drugs carry a potential
drug interaction, and no one is watching for them.

---

## Segment 2 — Log · the daily check-in  (0:11–0:24)

**On screen:** the Log view. A sentence is typed into the composer, a quick tag is tapped, the
entry saves into "Today so far."

> "It starts with one question a day. Type it, or tap Speak for the days typing is the barrier,
> fatigue, nausea, neuropathy, because a tired day shouldn't become a missing day. Your words are
> stored exactly as you said them and quoted back to you, never rewritten. 'The copay was rough'
> becomes the reason you skipped a dose, which is a completely different conversation from skipping
> over a side effect, and the second one is what usually gets assumed."

*Backend note (say if pacing allows):* voice uses the browser speech API into an editable field
and adds no model call.

---

## Segment 3 — Visualize · the solution and the backend  (0:24–1:02)

**On screen:** the graph. The interaction thread is lit; then the Tingling and Cost filters
re-weight it; then the detail and tracking panels scroll into view.

> "Here is the idea that makes Alongside different. Check-ins aren't stored to be searched later;
> they're wired to the medications, symptoms, and instructions they're about. Remembering is a
> walk across those connections. So a concern surfaces only when it is *reachable* from an anchor a
> check-in touched. Relevance is reachability, not similarity."

**On the interaction thread:**

> "This top thread is the case a search engine can't build: two prescribers, two drugs, one shared
> cardiac effect, assembled across three hops. Nobody typed that connection; the graph found it."

**As you click the Cost and the Tingling filters:**

> "Reachability buys two findings that top-k similarity cannot produce at any k. Convergence, the
> thread you just saw. And absence: the tingling here isn't listed as a side effect of any active
> drug, so it stays in tracking, watched but not yet a question. A vector index can't rank a
> document that doesn't exist. A graph can point at the missing edge."

**On the tracking panel:**

> "Nothing here is a diagnosis. It's a gap, shown with the exact quotes and dates it came from, and
> the patient decides what to do with it."

---

## Segment 4 — Advocate · the deliverable  (1:02–1:27)

**On screen:** "Questions for your care team." Scrolling from "Ask about these" through "Worth
mentioning" to "Also tracking."

> "The output is a page, not a message. 'Questions for your care team,' a standing document that
> fills up and drains. The layout *is* the severity ladder: an emergency would be a full-screen
> alert shown first; 'Ask about these' holds the hard concerns, 'Worth mentioning' the softer ones,
> and 'Also tracking,' below the line, holds what sank, because going quiet is not deletion. Every
> row cites the exact quote it came from. You print it and carry it in. Alongside never sends
> anything to anyone."

*Talking point:* capturing this between-visit signal isn't soft. In a randomized trial it extended
median survival by about five months.

---

## Segment 5 — Profile · grounding the record  (1:27–1:49)

**On screen:** the Profile view. Fields, the stage chip toggling, meds with their provenance.

> "The profile is what keeps the page accurate and prints a header a care team recognizes:
> diagnosis in the patient's own words, the care team, and the current medications, each tagged
> with where it came from, a pharmacy label or the patient. It stays on the device. Nothing is
> shared unless you print it or hand it over."

---

## Close  (1:49–end)

> "One page the patient owns, built from their own words, that fails visibly by saying 'not in your
> record' instead of 'safe.' That's Alongside."

---

## Standalone backend explanation (for Q&A or a longer cut)

Use these in order; each is one or two sentences.

1. **One language, one file.** Graph schema, walkers, the two model calls, and the React UI are all
   Jac, in one `main.jac`, deployed on JacHammer as a single artifact. No REST layer we wrote, no
   `fetch`, no separate frontend host or Python service. The client and server share the same typed
   archetypes, so the contract between them is the type system, and one `jac check` type-checks
   across the whole seam.

2. **Three node layers.** A provenance floor (`Utterance`, `Observation`) that is never scored or
   decayed, so what was actually said is never lost; a deterministic anchor layer (medications,
   symptoms, labs) that is never inferred; and a belief layer that is the only thing scored, so old
   beliefs sink below a waterline without touching the record underneath.

3. **Two channels.** Channel A, soft preferences, is scored, beam-limited, and decays. Channel B,
   hard constraints like interactions and dosing instructions, is exhaustive, unscored, and exempt
   from decay and budget; only a `Supersedes` edge can kill one, and emergency criteria are
   evaluated first on every open.

4. **Six walkers, two model calls.** `Vigil` runs unprompted on open; `Remember` writes and does
   the extraction; `Recall` runs both channels, detection, corroboration, and the emergency bypass;
   `Consolidate` rewrites within a budget; `Investigate` builds the case file with no model call;
   `Prepare` renders the page. There are exactly two `by llm()` sites, both on the write path; the
   read path has zero. `grep 'by llm('` returns two hits, so "keep the model on a leash" is an
   invariant you can point at, not an aspiration.

5. **The refusal is the point.** Jac offers `visit [-->] by llm()`, letting the model choose where
   to walk. We refused it: if the model picked the path, the Channel B reachability guarantee would
   be void. The model never decides what the patient reads or where the search walks.

6. **Safety by construction, not by policy.** Node and edge archetypes persist automatically,
   rooted per user on SQLite, so per-patient isolation is total, there's no query surface where two
   patients' graphs could meet. Every patient-facing sentence is a fixed template with graph-read
   slots or a verbatim quoted utterance; awkward copy gets fixed in the template, never generated.
   And there is no outbound path anywhere in the code. The product thesis and the implementation are
   the same object.

---

## What is real vs. seeded (say if asked)

- Real: the six walkers, two-channel traversal, detection, corroboration, emergency bypass, case
  file, and the full page UI, covered by about fifty read-path tests with no model call on read.
- Seeded: the two `by llm()` sites run precomputed results under `DEMO_MODE`, so the demo makes zero
  live model calls. The patient is a synthetic, adversarial case (the day-9 QT convergence).
- Pending/designed: a permanent deploy, and a consented read-only caregiver view (another reader of
  the graph, never a sender).

## Sources for the stats

- ~half of oral-cancer-drug patients carry a potential interaction: van Leeuwen et al., 2013.
- Between-visit symptom monitoring extended median survival ~5 months: Basch et al., JAMA 2017.
