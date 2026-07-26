# CONTRACTS

Pinned shapes. **This file is what makes parallel work possible.**

If a shape is pinned here, you may build against it before its producer exists. If you need to
change one, follow the amendment rule at the bottom — do not just edit it and push.

**Rule:** a PR that changes anything in this file must carry the `contract` label and must be
announced in the issue thread before merge. Everything downstream of a silently-changed contract
breaks at runtime, not at `jac check`.

---

## 1. Ownership

**Three people, three tracks.** T1 Bryan · T2 Nathan · T3 Laksh.

| Area | Files | Owner |
|---|---|---|
| Graph schema — **persisted** | `graph/archetypes.jac` (nodes + edges) | **T1 — frozen after stage 1** |
| Vocabulary + ingest | `graph/vocab.jac`, `ingest/regimen.jac` | T1 |
| Write path | `walkers/remember.jac`, `walkers/consolidate.jac` | T1 |
| Seed graph + fixtures | `seed/patient.jac` | T1 |
| `DEMO_MODE` branches | both `by llm()` sites | T1 |
| Read path | `walkers/recall.jac`, `walkers/investigate.jac`, `walkers/vigil.jac` | T2 |
| Eval | `eval/*` | T2 |
| Platform + deploy | jachammer project, env vars, remote, deploys | T2 |
| **Spine** | **`main.jac`, `jac.toml`** | **T3 — single owner. Nobody else opens these files.** |
| `Prepare` | `walkers/prepare.jac` | T3 |
| Templates | `render/templates.jac` | T3 |
| Page UI | `components/*.cl.jac` + paired `*.style.css` | T3 |
| Report objects — **transient** | `graph/reports.jac` (objs) | T3; **not frozen**, `contract` label to change |

**Why the work sits where it does.** `DEMO_MODE` is T1's because both `by llm()` sites it branches
are T1's files. The platform chores are T2's because it is Nathan's jachammer account, and because
T2 is the only track with a free first hour — everything in it waits on #1. T3 owns the surface top
to bottom, from `Prepare` through the rendered row, which is what makes single ownership of
`main.jac` workable.

**Two files are single-owner, for different reasons.** `graph/archetypes.jac` because editing it
corrupts everyone's persisted graph. `main.jac` because it is the one file every track would
otherwise need to touch — see section 1a.

**The freeze covers persisted archetypes only, and that distinction is load-bearing.**

Only `node` and `edge` archetypes are graph-persisted. Changing one invalidates every existing
`NodeAnchor` and forces a reset for every collaborator, so `graph/archetypes.jac` is **frozen after
stage 1**: changes go through an issue labeled `schema`, are made by its owner, are batched, and are
announced — everyone else resets their graph after.

**`obj` archetypes are transient values** constructed per walker run. Changing `Verdict` or `Row`
corrupts nothing and requires no reset. They live in `graph/reports.jac`, are **not frozen**, and
Track 3 may iterate on them as the page teaches us what `Row` actually needs — which it will.

Not frozen is not unowned. Report objs are still pinned below, and changing one needs the `contract`
label plus an ack, because three tracks build against them.

---

## 1a. `main.jac` — how three people share one file

**They don't. T3 owns it for the entire build. T1 and T2 never open it.**

`main.jac` is the mixed-context entry point: server archetypes and walkers at top level, the browser
UI in a `cl { }` block. It is the file that carries the single-file claim, which means every track
has a reason to want to edit it, which means it is the single most likely source of merge conflicts
in the repo. So it is governed like archetypes, not like a shared workspace.

### The protocol

**Contributions arrive as modules, not as edits.**

Your code lives in a file you own — `walkers/recall.jac`, `graph/vocab.jac`,
`walkers/consolidate.jac`. When it needs to be reachable from the spine, you **comment on #17 with
the exact line to add**, and T3 adds it. You do not push a commit that touches `main.jac`. Ever.

```
# comment on #17
walkers/recall.jac is on main as of #8. Add:
    include walkers.recall;
```

That reduces the shared surface of `main.jac` to a single alphabetically-ordered `include` list. Two
people adding a line at once is a one-line textual conflict with no semantics in it — trivial to
resolve, and it cannot break the build in a way that `jac check .` won't catch immediately.

### The two phases, and why the single-file claim survives

**Phase 1 — #17. `main.jac` is literally the whole app.** Inline archetypes, inline `Remember`,
inline `Prepare`, inline `cl { }` page. Around 150 lines. One author, one sitting, no coordination
cost because nothing else exists yet. This is the real vertical slice: check-in → graph write →
traversal → rendered page, all in one file, one language.

**Tag that commit.**

```
git tag -a single-file-slice -m "Full vertical slice: graph, walkers, and UI in one file"
git push origin single-file-slice
```

**Phase 2 — everything after.** As real modules land, T3 replaces inline bodies with `include`
lines. `main.jac` stays the entry point and stays under ~80 lines.

The tag is what makes both claims true at judging time. *"The entire app was one file"* is
demonstrable at a commit hash. *"The entry point is still one mixed-context file, server and client
together, no separate frontend and no separate Python service"* is true of `main`. Neither claim
needs three people editing one file, which is the thing that was never going to work.

### If you find yourself wanting to edit `main.jac`

That is the signal your work belongs in a module. Move it into one and comment on #17.

---

## 2. Node and edge schema

**Persisted and frozen.** Lives in `graph/archetypes.jac`, built in #1. Source of truth is
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

**Transient, not frozen.** Lives in `graph/reports.jac`, built in #29. Safe to iterate; still needs
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

`render/templates.jac` maps `Concern.kind` → two format strings, `question` and `why`, with named
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

**Fixture keying:** `seed/patient.jac` owns the fixtures. Key on exact `Utterance.text`. If you add
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

For `graph/archetypes.jac`, add: label `schema`, and tell everyone to reset their graph after
pulling — an archetype change corrupts every existing persisted graph.
