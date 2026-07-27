# Handoff: myCancerPal — landing + Log / Visualize / Advocate / Profile

## Overview
myCancerPal is a longitudinal companion for people in cancer treatment. Daily check-ins (typed or spoken)
are stored verbatim and linked to clinical anchors parsed deterministically from pharmacy labels. Graph
traversal — not similarity search — surfaces a standing "Questions for your care team" page the patient
prints and carries into an appointment. The app never sends anything outbound on the patient's behalf.

This bundle redesigns the whole flow: a landing page, then three product tabs plus a profile.

## About the design files
The two `.dc.html` files are **design references written in HTML** — prototypes that show intended look,
copy, and behavior. They are not production code to paste in. Recreate them in the target codebase
(currently a Jac backend + web front end) using its existing components and patterns. If no front-end
convention exists yet, pick one (React + CSS modules or Tailwind is a safe default) and implement there.

- `myCancerPal App.dc.html` — the interactive prototype. Open in a browser; all navigation works.
- `myCancerPal UI Proposal.dc.html` — the design-system sheet: palette, type scale, component atoms,
  mobile screen specs, and a written rationale for each change from the current build.

## Fidelity
**High fidelity.** Colors, type, spacing, copy, and interaction states are final-intent. Recreate
pixel-closely. The only deliberately schematic part is the graph canvas geometry (see Visualize below):
the coordinates are hand-placed for the demo data set and should be replaced by a layout function.

## Design tokens

Color
| Token | Hex | Use |
|---|---|---|
| paper | #F7F6F3 | app background |
| card | #FDFCFA | raised surfaces |
| hairline | #DAD8D1 | dividers, card borders |
| hairline-soft | #E3E1DB | inner dividers |
| ink | #1C2321 | primary text |
| ink-muted | #5A635F | secondary text |
| ink-faint | #8A918D | mono meta text |
| body | #3D4643 | long-form body copy |
| pine | #2F6D64 | primary actions, "you said" data |
| pine-dark | #255751 | button hover |
| pine-soft-bg | #EAF0EE / border #D2E1DC / text #2A5F57 | answered state, listening bar |
| clay | #8C4526 (text) / #B0653F (graph stroke) | "raise with a clinician" ONLY |
| clay-soft-bg | #F6EDE7 / border #E8D5C8 | urgent card + pill |
| slate | #35536F / bg #EAF0F5 / border #D3E0EA | already-asked state |
| grey-dashed | #A29E94 | tracked-but-not-surfaced edges |
| control-border | #C9C6BD | secondary buttons, chips |

Rule: clay never appears for decoration. One accent per meaning. No gradients anywhere.

Type — Google Fonts: Newsreader (400/500), IBM Plex Sans (400/500/600), IBM Plex Mono (400/500)
| Role | Font / size / line-height |
|---|---|
| Page title | Newsreader 400, 38px, 1.15, -0.015em |
| Hero (landing) | Newsreader 400, 52px, 1.1 |
| Card question | Newsreader 400, 25px / 23px, 1.25 |
| Body | Plex Sans 400, 17px, 1.6 |
| Secondary body | Plex Sans 400, 15–16px, 1.55 |
| Section label | Plex Mono 400, 12px, uppercase, 0.08em, ink-muted |
| Evidence quote | Plex Mono 400, 14px, 1.5, body color |
| Evidence source | Plex Mono 400, 12px, ink-faint |
Body copy never below 15px; primary reading text is 17px. Serif = anything the patient reads aloud to a
clinician; sans = interface; mono = quoted evidence and metadata only.

Geometry
- Radii: 10px controls/inputs, 12px primary buttons, 14–18px cards, 20–26px large panels, 999px pills.
- Spacing scale: 4 / 8 / 10 / 14 / 18 / 22 / 28 / 32 / 48 px.
- Content widths: 720px (Log, Advocate), 760px (Profile), 1080px (landing), 1240px (Visualize).
- Shadow: essentially none — `0 1px 3px rgba(28,35,33,0.05)` at most. Depth comes from hairlines.
- Every sibling group uses flex/grid + gap.

## Screens

### 1. Landing (`view === "landing"`)
Purpose: explain the product, then send the user into it.
- Top bar: 20px pine rounded square + "myCancerPal" (Newsreader 19px), right-side "Open the app" link.
- Hero: 2-col grid (1.05fr / 0.95fr), 64px gap, max 1080px, 56px top padding.
  - Left: mono eyebrow "FOR PEOPLE IN TREATMENT"; h1 "You'll remember it. We'll write it down.";
    19px body paragraph; two buttons (pine "Start today's check-in" → Log, outline "See an example page"
    → Advocate); hairline rule then the privacy line ("Nothing is sent to your care team on your behalf…").
  - Right: a card demonstrating the product's whole thesis — a Jul 15 quote, a "8 days later" divider,
    the resulting question in Newsreader 22px, and a "Bring this up" pill.
- "How it works" — 3-col grid, one column per tab: 01 Log / 02 Visualize / 03 Advocate, each with a mono
  number, Newsreader 25px title, 16px body.

### 2. App shell (all non-landing views)
Sticky top bar on paper background, bottom hairline, inner max-width 1080px, 32px horizontal padding.
Left: logo → landing. Center: tabs Log / Visualize / Advocate, 16px 500, 18px padding, 2px bottom border
(ink when active, transparent otherwise; ink text active, ink-muted inactive). Advocate carries a count
badge (mono 12px, clay text on clay-soft-bg, 999px). Right: avatar chip — 26px circle with initials
(pine-soft palette) + mono "Maya R. · day 41", opens Profile; border becomes #C9C6BD when profile is active.

### 3. Log (`view === "log"`) — 720px column
- Header: mono date, h2 "How are you doing today, Maya?", 17px subhead ("A sentence is plenty…").
- Composer card: 18px radius, hairline border.
  - Textarea 5 rows, 18px/1.6, paper background, focus border pine.
  - When recording: pine-soft bar with 7 animated 3px bars (`@keyframes pulse`, 1s, staggered 0.11s) and
    the line "Listening — say it however it comes out."
  - Buttons: outline "Speak instead" (dot turns clay while recording, label becomes "Stop and review")
    and pine "Add to today's check-in". Below: "Saved exactly as written and quoted back to you."
  - Stopping recording appends a canned transcript to the same editable draft — the patient always edits
    before saving. Do not auto-commit transcription.
- Quick tags: 6 pills (Nausea, Tingling, Tired, Sore mouth, Slept badly, Skipped a dose). Tapping appends
  a plain sentence to the draft rather than storing a code — the patient's text stays the record.
- "Today so far": entry cards with mono timestamp, 17px text, and mono link chips showing what the entry
  connected to. New entries animate in with `fadeUp` 0.28s.

### 4. Visualize (`view === "visualize"`) — 1240px column
Turns the traversal log into a graph. Four columns, left → right:
your words → parsed label → link found → outcome (on your page / watching).

- Canvas: card with `overflow-x: auto`; inner layer `min-width: 1180px; height: 580px; position: relative`.
- Edges: one SVG, `viewBox="0 0 1360 600"`, `preserveAspectRatio="none"`, absolutely filling the layer.
  Each edge is a cubic bezier from source right port to target left port:
  `M x1 y1 C mx y1, mx y2, x2 y2` where `mx = (x1+x2)/2`, ports are `node.x ± 105`.
  Stroke: clay #B0653F = surfaced on the page; pine #2F6D64 = asked/answered; #A29E94 dashed "7 6" =
  tracking, not surfaced. Active thread stroke-width 2.4, inactive 1.4 and opacity 0.22.
- Nodes: absolutely positioned divs, `left: (x/1360)*100%`, `top: (y/600)*100%`, `width: 15.4%`,
  `transform: translate(-50%,-50%)`. 10px radius, 1px hairline border, 3px left rule colored by thread
  (grey for patient words, clay/pine/grey by outcome). Inside: mono 10px uppercase kind, 14px label,
  mono 11px meta. Inactive nodes drop to opacity 0.35.
  Demo coordinates (x,y in viewBox units) — replace with a layered layout function in production:
  words x=150 (y 100/300/500), labels x=520 (y 80/220/420), links x=880 (y 150/320/500),
  outcomes x=1210 (y 150/320/500). Column gap must exceed node width + ~30 units.
- Filter chips above the canvas (own row): Medication interaction / Tingling — tracking only /
  Cost and missed doses. Active chip is ink-filled. Clicking any node also focuses its thread.
- Legend strip below the canvas inside the same card, plus the standing line
  "emergency criteria evaluated first on every open — none met".
- Below, 1.1fr / 0.9fr grid:
  - Detail panel for the focused thread: mono kicker ("3 hops · Jul 20 → today"), Newsreader title,
    body, then numbered hops (hop 1/2/3) each with a plain-language line and a mono source line;
    footer pill + "Open on Advocate →".
  - **Tracking panel** (dashed border — the visual language for "not a question yet"): watched patterns
    with a why-line, a 5px progress bar (#A9C4BD on #EFEEE9) and mono "6 / 8" count toward the surfacing
    threshold, and "Add to my questions". This is the requested view of what is tracked but not yet
    surfaced on Advocate.

### 5. Advocate (`view === "advocate"`) — 720px column
The printable page.
- Header: h2 "Questions for your care team", subhead naming the date range and next appointment, plus
  "Print for my visit" (pine) and "Show how these were found" (outline → Visualize).
- Group "Ask about these" (clay label + clay rule): cards with clay-soft border, Newsreader 25px question,
  17px explanation, then an evidence block behind a 2px clay-soft left rule — each source is a mono quote
  with a mono "source · date" line beneath. Footer: "Bring this up" pill + "Log the answer".
- Group "Worth mentioning" (neutral): same card at 23px title, hairline rule, pill varies
  ("Bring this up" clay / "Asked · Jul 22" slate).
- Footer block, dashed border: "Also tracking — not questions yet", each with a mono count, and
  "See these on the graph →". Mirrors the Visualize tracking panel so the gap is visible from both sides.

### 6. Profile (`view === "profile"`) — 760px column
Reached from the avatar chip. Sections are a mono label + hairline rule, fields in a 2-col grid (18/20 gap).
- About you: first, last, DOB, age, pronouns (full width); chip set "Sex recorded on your chart"
  (Female / Male / Intersex / Prefer not to say) with the note that chart and identity may differ.
- Diagnosis: diagnosis (full width, free text — quoted back, never interpreted), diagnosed on,
  treatment center; chip set for stage/phase including "Not sure".
- Care team and contacts: oncologist, nurse line, emergency contact, their phone.
- Current medications: read-only rows, name + dosing meta + mono provenance ("label · Jul 3" or "you · Jun 12"),
  then "Add a medication by photographing the label".
- Allergies and other conditions: textarea.
- Footer: "Save profile" + status text ("Changes stay on this device." → "Saved on this device just now.").
Inputs: 17px, card background, hairline border, 10px radius, 13px 14px padding, focus border pine,
label 15px/500 above and 13px hint below.

## Interactions & behavior
- Navigation is client-side view state: landing | log | visualize | advocate | profile.
- Speak toggle: start → listening state; stop → append transcript text to the editable draft.
- Save check-in: trims the draft, appends an entry with time "just now", clears the draft; empty draft is a no-op.
- Tag chip: appends a sentence to the draft (never replaces it).
- Graph focus: node click or filter chip sets the focused thread; all edges/nodes re-weight opacity.
- Profile: every field edit clears the saved flag; Save sets it.
- Hover states: pine buttons darken to #255751; outline controls move border to ink; tags/links move to pine.
- Responsive: single column below ~900px; the graph canvas scrolls horizontally below 1180px.
- Motion is minimal — `pulse` for the listening bars, `fadeUp` 0.28s for new entries. Nothing else animates.

## State
```
view: "landing" | "log" | "visualize" | "advocate" | "profile"
draft: string
recording: boolean
entries: [{ time, text, links: string[] }]
focus: "interaction" | "tingling" | "cost"     // graph thread
profile: { first, last, pronouns, dob, age, sex, diagnosis, stage,
           diagnosedOn, center, oncologist, nurseLine, contactName, contactPhone, notes }
saved: boolean
```
Real data needed from the backend: check-in entries, parsed label anchors, graph nodes/edges with a thread
id and a surfaced/watching status, per-pattern mention counts and thresholds, and the question list with
status (open / asked / answered).

## Assets
None. No images, no icon set — the only graphics are the pine rounded square logo mark, the SVG bezier
edges, and the animated bars. Fonts load from Google Fonts.

## Files
- `myCancerPal App.dc.html` — interactive prototype, all five views.
- `myCancerPal UI Proposal.dc.html` — token sheet, mobile screens, and the rationale for each change.
