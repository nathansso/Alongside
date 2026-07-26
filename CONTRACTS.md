# CONTRACTS

Pinned shapes. **This file is what makes parallel work possible.**

If a shape is pinned here, you may build against it before its producer exists. If you need to
change one, follow the amendment rule at the bottom — do not just edit it and push.

**Rule:** a PR that changes anything in this file must carry the `contract` label and must be
announced in the issue thread before merge. Everything downstream of a silently-changed contract
breaks at runtime, not at `jac check`.

---

## 1. Ownership

**Three people, five files — split 3 / 1 / 1.** Laksh owns three (`graph.jac` + the surface); Bryan
and Nathan own one deep walker module each. Person↔track: T1 Bryan · T2 Nathan · T3 Laksh.

**Five files during the build. One file at submission.** See section 1a for the merge.

| File | Owner | Holds |
|---|---|---|
| `graph.jac` | **T3 Laksh** — nodes/edges frozen after #1 | nodes, edges, report objs |
| `main.jac` | **T3 Laksh** | `Prepare`, templates, imports, `cl { }` mounting the page |
| `page.cl.jac` | **T3 Laksh** | the concerns page, rows, activity panel, typed + voice check-in surface |
| `write.jac` | **T1 Bryan** | `Remember`, `Consolidate`, vocab `glob`, regimen parse, seed patient, `DEMO_MODE` |
| `read.jac` | **T2 Nathan** | `Recall` (both channels, detection, corroboration), `Vigil`, `Investigate`, eval harness, quarantined baseline |
| `jac.toml`, `styles/global.css` | **T3 Laksh** | config and the one stylesheet |

**Every file has exactly one owner.** Laksh three (`graph.jac`, `main.jac`, `page.cl.jac`), Bryan one
(`write.jac`), Nathan one (`read.jac`). Nobody has a reason to open someone else's file, so merge
conflicts are impossible by construction rather than by convention.

**The report objs live in `graph.jac`, which Laksh owns** — the track that also consumes them most.
Laksh owns the schema, the page, and the merge target (`graph.jac`, `page.cl.jac`, `main.jac`) end to
end, and all three collapse into `main.jac` at submission. Every obj is fully specified in sections 3
and 4, so Bryan and Nathan build against the pinned shape regardless of who typed it.

**Why the work sits where it does.** `DEMO_MODE` is Bryan's because both `by llm()` sites it branches
live in `write.jac`. The platform chores are Nathan's because it is his jachammer account. Laksh owns
the schema and the surface top to bottom — `graph.jac` through the rendered row — coherent because all
three Laksh files merge into `main.jac`. **Consequence to accept:** Laksh now owns #1 (the schema
freeze), the blocking first task, so #1 lands before Laksh's surface work — and Nathan, the heaviest
schema consumer, still reviews the #1 completeness checklist first (`CONTRIBUTING.md` §1a).

**`page.cl.jac` exists for one reason: HMR reloads only `.cl.jac` files.** Server modules need a full
restart. The page is the file that gets iterated on most, so it stays where the fast reload is until
the final merge.

### The freeze covers persisted archetypes only, and that distinction is load-bearing

Only `node` and `edge` archetypes are graph-persisted. Changing one invalidates every existing
`NodeAnchor` and forces a reset for every collaborator, so the **nodes and edges** in `graph.jac` are
**frozen after #1**: changes go through an issue labeled `schema`, are batched, and are announced —
everyone else resets their graph after.

**`obj` archetypes are transient values** constructed per walker run. Changing `Verdict` or `Row`
corrupts nothing and requires no reset. They share `graph.jac` for merge simplicity and are **not
frozen** — changing one costs an ack, not a graph reset — but Laksh applies the change, because Laksh
owns `graph.jac`.

Not frozen is not unowned. Report objs are pinned below, and changing one needs the `contract` label
plus an ack, because all three tracks build against them.

---

## 1a. Develop in five files, ship one

The hackathon rewards single-file full-stack development. Three people cannot write one file at once.
Both are satisfiable, because **the claim is about the deliverable, not the git history.**

So: five files while building, collapsed into `main.jac` before submission. Jac archetypes are flat
within a module — a `walker Recall { ... }` pasted from `read.jac` into `main.jac` needs no wrapper,
no re-indentation, no nesting. The merge is concatenation plus deleting import lines.

**It is only that easy if all four rules below hold from the first commit. Retrofitting them at hour
20 is where this goes wrong.**

### The four merge disciplines

**1. Prefix every private helper with its home file.** `wr_parse_dose`, `rd_score_edge`,
`pg_fmt_date`. Archetypes and walkers keep their real names — they are globally unique by design. A
duplicate helper name is the only collision a merge can actually produce, and this eliminates it.

**2. `root spawn` only. Never `sv import`, never function RPC.** Already required by section 4, but
it is load-bearing for the merge: **an `sv import` inside the entry module's own `cl { }` block does
not register the endpoint.** A page built on `sv import` works in `page.cl.jac` and breaks the moment
its body moves into `main.jac`. Walker spawn is immune.

**3. One `styles/global.css`. No `.style.css` annex files.** Annexes pair to a component by *base
name*; when `page.cl.jac`'s content moves into `main.jac`, the pairing orphans and the styles
silently vanish. Prefix classes by hand (`pg-row`, `pg-row-q`) and import the single stylesheet once
inside the `cl { }` block. We trade compiler-hashed scoping for a merge that cannot break.

**4. Satellites import only from `graph.jac`, never from each other.** `read.jac` and `write.jac` do
not know each other exists. The merge is then a concatenation in a fixed order with no dependency
untangling and no circular-import surprises.

### Merge order

```
archetypes  ->  report objs  ->  globs  ->  write walkers
            ->  read walkers  ->  Prepare  ->  templates  ->  cl { }
```

End state: `main.jac` + `jac.toml` + `styles/global.css`.

### Merge twice

The classic failure is merging at hour 22 and finding a problem with no time to fix it.

**Rehearsal merge at the midpoint.** Throwaway branch, one person, thirty minutes, the moment all
five files compile together. `jac check .` is the gate. Delete the branch afterward — its only job is
to surface every mechanical problem while fixing them is still cheap.

**Then the real merge near the end** is a repeat of something already done once.

**Tag the merge commit** so the single-file artifact is citable:

```
git tag -a single-file -m "Whole app in main.jac: archetypes, walkers, by llm(), traversal, UI"
git push origin single-file
```

### What to claim, and what not to

**True and worth saying:** `main.jac` is the entire application — graph schema, both `by llm()`
sites, a real multi-hop traversal, and the browser UI, in one file, in one language, with no separate
frontend and no separate Python service.

**Do not imply the history was one file.** Developing in modules and consolidating is ordinary
engineering, and the deliverable is what gets judged.

---

## 2. Node and edge schema

**Persisted and frozen.** Lives in `graph.jac`, built in #1. Source of truth is
`ARCHITECTURE.md` section 3; this is the wire-relevant subset.

```jac
node Utterance   { has text: str; has at: str; has role: str; }
node Anchor      { has key: str; has kind: str; }
node Observation { has metric: str; has value: float; has at: str; }
node Belief      { has claim: str; has strength: float = 1.0;
                   has last_used: str; has uses: int = 0;
                   has needs_review: bool = False; }
node Preference(Belief) { has polarity: float = 0.0; }
node Constraint(Belief) { has hard: bool = True; }
node Raised      { has kind: str; has anchor_key: str; has status: str; has at: str; }
```

**Field vocabularies — pinned, closed sets:**

| Field | Allowed values |
|---|---|
| `Utterance.role` | `patient` · `caregiver` · `oncologist` · `pharmacist` · `label` |
| `Anchor.kind` | `ingredient` · `class` · `symptom` · `lab` · `phase` · `food` |
| `Member.via` | `class_member` · `toxicity_of` |
| `Raised.status` | `open` · `asked` · `answered` · `dismissed` |
| `Concern.action` | `escalate` · `ask` · `mention` · `log` |
| `at` (everywhere) | ISO 8601 date string, `YYYY-MM-DD` |

`Utterance.role` is **authority-bearing**: a `Constraint` may be `hard == True` only if its
`DerivedFrom` `Utterance` has a role in `{oncologist, pharmacist, label}`. Adding a value to that
set is a safety change, not a schema change.

---

## 3. Report objects

**Transient, not frozen.** Lives in `graph.jac` alongside the archetypes, built in #29 by Laksh. Safe to iterate; still needs
the `contract` label to change, because three tracks consume these.

```jac
obj Violation { has claim: str; has because: str; has source: str; has at: str; }
obj Concern   { has kind: str; has anchor: str; has evidence: list[str];
                has since: str; has action: str; }
obj Verdict   { has allowed: bool = True;
                has violations: list[Violation] = [];
                has soft: list[str] = [];
                has conflicts: list[str] = [];
                has concerns: list[Concern] = []; }
```

- `Violation.source` / `.at` are read off `DerivedFrom`. **Never empty** — S2.
- `Concern.evidence` is a list of `jid` strings for `Observation` and `Utterance` nodes.
- `allowed` is false **iff** channel B produced at least one hit on a `Constraint` with
  `hard == True`.

**`Concern.kind` — pinned, closed set.** Adding one requires a matching template (section 5).

| kind | Mechanism | Ceiling |
|---|---|---|
| `interaction` | 1 — path exists that should not | `ask` |
| `additive_toxicity` | 1 | `ask` |
| `unattributed_symptom` | 2 — path missing that should exist | `mention` |
| `supportive_care_gap` | 2 | `mention` |
| `adherence_gap` | 2 | `mention` |
| `silence` | 2 | `mention` |
| `persistence` | 3 — threshold crossed | `ask` |
| `trajectory` | 3 | `mention` |
| `emergency` | 3 | `escalate` |
| `instruction_drift` | 4 — two stated things contradict | `mention` |
| `cross_prescriber_conflict` | 4 | `ask` |
| `nonadherence_cause` | 4 | `mention` |
| `unrecognized_substance` | A1 guard miss | `mention` |

**Ceiling is a hard cap, not a default.** Corroboration may promote up to it and no further.
Channel A can never reach `ask` or `escalate` regardless of score (S6).

---

## 4. Walker call signatures

All client→server calls use **walker spawn with kwargs**. Reports land in `result.reports`.

```jac
walker Vigil       { has today: str;                              has out: Verdict = Verdict(); }
walker Remember    { has text: str; has role: str; has at: str;   has out: Verdict = Verdict(); }
walker Recall      { has anchors: list[str];                      has out: Verdict = Verdict(); }
walker Consolidate { has budget: int = 6;                         has out: Verdict = Verdict(); }
walker Investigate { has concern_kind: str; has anchor: str;      has out: CaseFile = CaseFile(); }
walker Prepare     { has include_log: bool = False;               has out: PageModel = PageModel(); }
```

**Every walker reports exactly once, from `with Root exit`.** One typed object. Not a list of
fragments.

**Voice check-in adds no walker and no shape.** The check-in surface in `page.cl.jac` captures a typed
check-in — or, optionally, dictation via the browser Web Speech API — and calls
`Remember(text=<check-in>, role="patient", at=<today>)`, the signature above, unchanged.
Speech-to-text is a browser API, not a `by llm()` site (`ARCHITECTURE.md` §8), and introduces nothing
to pin here.

```jac
obj CaseFile  { has onset: str; has timeline: list[TimelineEntry] = [];
                has counterfactual: str = ""; has existing_instruction: str = "";
                has citations: list[str] = []; }
obj TimelineEntry { has at: str; has what: str; has source: str; }

obj PageModel { has escalate: list[Row] = [];
                has ask: list[Row] = [];
                has mention: list[Row] = [];
                has log: list[Row] = [];
                has activity: list[str] = []; }
obj Row       { has id: str; has kind: str; has question: str; has why: str;
                has noticed: list[str] = []; has citations: list[Citation] = [];
                has status: str = "open"; }
obj Citation  { has text: str; has role: str; has at: str; }
```

`PageModel.activity` is the activity-panel lines. Read from walker internal state — **do not add
walker logic to produce them.**

---

## 5. Template registry

**S8: page copy is template-or-quote. No `by llm()` on the read path, ever.**

The template registry in `main.jac` maps `Concern.kind` → two format strings, `question` and `why`, with named
slots filled from the traversal. Every kind in section 3 must have an entry, or `Prepare` fails
loudly rather than rendering an empty row.

```
kind                   slots available
interaction            {new}, {regimen_drug}, {class}, {because}, {role}, {at}
additive_toxicity      {drug_a}, {drug_b}, {symptom}, {role_a}, {at_a}, {role_b}, {at_b}
unattributed_symptom   {symptom}, {count}, {since}
supportive_care_gap    {symptom}, {instruction}, {since}
adherence_gap          {drug}, {days}, {since}
silence                {days}, {since}
persistence            {symptom}, {level}, {days}, {threshold_source}
trajectory             {symptom}, {cycles}
emergency              {criterion}, {source}
instruction_drift      {instruction}, {observed}, {days}
cross_prescriber_conflict  {claim_a}, {claim_b}, {role_a}, {role_b}
nonadherence_cause     {drug}, {cause}, {at}, {missed_days}
unrecognized_substance {substance}, {at}
```

Slot values are **strings read off the graph**. A slot that cannot be filled is a bug in the
detection rule, not a reason to fall back to prose.

---

## 6. `DEMO_MODE`

A single config read at spawn. Both `by llm()` sites branch on it; nothing else does.

- Set → return pre-computed results keyed to the seeded `Utterance` text. Zero network calls.
- Unset → live behavior, unchanged.

The concerns page needs no branch. It never calls a model.

**Fixture keying:** the seed block in `write.jac` owns the fixtures. Key on exact `Utterance.text`. If you add
a seeded utterance, add its fixture in the same PR.

---

## 7. Stub-first rule

**You may not block on a walker that does not exist yet.**

Any unbuilt walker ships as a stub that returns a fixture from `seed/`, matching its pinned shape
above. Track D builds the entire page against `Prepare` stubs before `Recall` is real; Track E
builds `DEMO_MODE` and eval against stubs too.

A stub is done when it returns a shape-valid object and `jac check .` passes. Replacing a stub with
the real implementation is a separate issue, and it must not change the shape.

---

## 8. Amending a contract

1. Open an issue labeled `contract` describing the change and what breaks.
2. Comment on every open issue that consumes the shape.
3. Get one ack from an affected track.
4. Change this file **and** every consumer in the same PR.
5. Announce on merge.

For the nodes and edges in `graph.jac`, add: label `schema`, and tell everyone to reset their graph after
pulling — an archetype change corrupts every existing persisted graph.
