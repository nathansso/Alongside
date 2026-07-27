"""main.jac — Alongside vertical slice (Track 3, Laksh).

The single code file the rubric scores for "single-file full-stack development." At submission
`graph.jac`, `write.jac`, `read.jac`, and `page.cl.jac` collapse into this file (CONTRACTS §1a).
Today it carries the surface half of the slice:

  - the template registry           (issue #19) — every patient-facing sentence is a template
                                                   with graph-read slots. Never model-generated (S8).
  - the `Prepare` walker             (issue #18) — read-only page assembly (A9), zero model calls.
  - the `cl { }` block               (issue #17) — mounts the concerns page; client→server is
                                                   `root spawn` only (CONTRACTS §1a discipline #2).

Merge disciplines held from commit one: private helpers are `pg_`-prefixed (#1); the client reaches
the server only through `root spawn` (#2); styling is one `styles/global.css`, no `.style.css`
annex (#3); this module imports only from `graph.jac` (#4).

There are ZERO model-call sites in this file, by design. The two the app is allowed live on the
write path (`write.jac`). If page copy reads awkwardly, fix the template — never reach for a model.
"""

# Import the transient report objs (the surface's contract seam, CONTRACTS §3/§4) and the persisted
# node archetypes now that #1 has frozen them. Evidence/status resolution narrows against the real
# node types (isinstance / [?:Raised]) instead of jobj+hasattr duck-typing (#46).
import from graph { Concern, Citation, Row, PageModel, Utterance, Observation, Raised }


# ==========================================================================================
# Template registry — issue #19.  CONTRACTS §5.
# Concern.kind -> {question, why} format strings with named slots filled from the traversal.
# All 13 kinds in CONTRACTS §3 have an entry; a missing kind or an unfilled slot raises loudly
# (pg_render / pg_apply) rather than rendering an empty row. S8: template-or-quote, never generated.
# S4: no dosing-judgment or discontinuation vocabulary appears in any patient-facing string below.
# ==========================================================================================

glob PG_TEMPLATES: dict[str, dict[str, str]] = {
    "interaction": {
        "question": "Is it okay that I'm taking {new} and {regimen_drug} at the same time?",
        "why": "Both are {class}. {regimen_drug} is already on my list; {new} was added ({role}, {at}). {because} Neither prescription mentions the other.",
    },
    "additive_toxicity": {
        "question": "Is it a concern to be on {drug_a} and {drug_b} together?",
        "why": "Both can contribute to {symptom}. {drug_a} came from {role_a} on {at_a}; {drug_b} came from {role_b} on {at_b}. They were prescribed separately.",
    },
    "unattributed_symptom": {
        "question": "What's causing the {symptom}?",
        "why": "I've mentioned this {count} times since {since}. Nothing on my current medication list names it as a known effect — which is why it's worth asking about rather than assuming it's expected.",
    },
    "supportive_care_gap": {
        "question": "Is there something that would help with the {symptom}?",
        "why": "I've been describing {symptom} since {since}. My instructions cover {instruction}, but nothing addresses this directly.",
    },
    "adherence_gap": {
        "question": "Am I keeping up with {drug} the way I should?",
        "why": "I haven't logged taking {drug} on {days} days since {since}.",
    },
    "silence": {
        "question": "Should I be checking in more often?",
        "why": "There hasn't been a check-in for {days} days, since {since}. Gaps make it harder to catch changes early.",
    },
    "persistence": {
        "question": "Is the {symptom} something to act on now?",
        "why": "I've reported {symptom} at {level} for {days} days. {threshold_source} suggests this is worth raising.",
    },
    "trajectory": {
        "question": "Is the {symptom} changing over time?",
        "why": "It's come up across {cycles} — the pattern is worth showing my team.",
    },
    "emergency": {
        "question": "{criterion}",
        "why": "{source} lists this as a reason to contact my team right away.",
    },
    "instruction_drift": {
        "question": "Am I taking this the right way?",
        "why": "My instructions say {instruction}. On {days} days I described {observed}.",
    },
    "cross_prescriber_conflict": {
        "question": "My {role_a} and {role_b} seem to have said different things — which should I follow?",
        "why": "{role_a} said: {claim_a}. {role_b} said: {claim_b}.",
    },
    "nonadherence_cause": {
        "question": "Can we talk about what's making {drug} hard to keep up with?",
        "why": "I mentioned {cause} on {at}. I haven't logged {drug} on {missed_days} days since. There may be options, but only if they know the real reason.",
    },
    "unrecognized_substance": {
        "question": "I've been taking {substance} — is that alright with my treatment?",
        "why": "I mentioned {substance} on {at}. It isn't in a form that matched my record, so it's worth flagging.",
    },
};


# Substitute {slot} tokens; a leftover token means an unfillable slot — raise, never blank.
def pg_apply(tpl: str, slots: dict[str, str]) -> str {
    out: str = tpl;
    for k in slots {
        out = out.replace("{" + k + "}", slots[k]);
    }
    if "{" in out {
        raise ValueError("Unfilled template slot in rendered copy: " + out);
    }
    return out;
}


# (question, why) for a concern kind. Unknown kind raises — Prepare fails loudly (#19).
def pg_render(kind: str, slots: dict[str, str]) -> list[str] {
    if kind not in PG_TEMPLATES {
        raise ValueError("No template registered for concern kind: " + kind);
    }
    tpl: dict[str, str] = PG_TEMPLATES[kind];
    return [pg_apply(tpl["question"], slots), pg_apply(tpl["why"], slots)];
}


# ==========================================================================================
# Slot / evidence resolution — read-only graph reads.  All slot values are strings read off the
# graph (CONTRACTS §5); nothing is fabricated. Evidence jids resolve to Utterance (-> citations,
# the "where this came from" line) and Observation (-> "what I've noticed" dates) nodes.
# ==========================================================================================

# Utterance evidence -> Citations. S2: a row with no Utterance citation cannot be shown.
# An Utterance node is duck-typed by its text + role fields (no node-type import; see #1 note above).
def pg_cites(c: Concern) -> list[Citation] {
    cites: list[Citation] = [];
    for ev in c.evidence {
        n = jobj(ev);
        if isinstance(n, Utterance) {   # #1 archetypes landed: narrow instead of duck-typing
            cites.append(Citation(text=n.text, role=n.role, at=n.at));
        }
    }
    return cites;
}


# Observation evidence -> sorted distinct dates for the "what I've noticed" line.
# An Observation node is duck-typed by its metric field (it carries no text, so it is not a citation).
def pg_noticed(c: Concern) -> list[str] {
    dates: list[str] = [];
    for ev in c.evidence {
        n = jobj(ev);
        if isinstance(n, Observation) {   # #1 archetypes landed: narrow instead of duck-typing
            if n.at not in dates { dates.append(n.at); }
        }
    }
    return sorted(dates);
}


# Most-recent Observation value among the evidence, as a string ({level} slot).
def pg_latest_level(c: Concern) -> str {
    latest_at: str = "";
    val: str = "";
    for ev in c.evidence {
        n = jobj(ev);
        if isinstance(n, Observation) {   # #1 archetypes landed: narrow instead of duck-typing
            if n.at >= latest_at { latest_at = n.at; val = str(n.value); }
        }
    }
    return val;
}


# Assemble the slot dict from the concern plus its resolved evidence. Only graph-read strings.
# Multi-entity slots a single-anchor Concern cannot supply ({new}, {regimen_drug}, {class},
# {because}, {drug_b}) are intentionally left absent — a template needing one then raises in
# pg_apply, the correct "the detection rule owes richer evidence" signal (CONTRACTS §5), not a
# reason to invent prose. See the open decision surfaced on issue #18.
def pg_slots(c: Concern, cites: list[Citation]) -> dict[str, str] {
    utts: list[Citation] = cites;
    obs_dates: list[str] = pg_noticed(c);
    obs_count: int = len(obs_dates);

    first_txt: str = "";
    first_role: str = "";
    first_at: str = "";
    if len(utts) > 0 {
        first_txt = utts[0].text;
        first_role = utts[0].role;
        first_at = utts[0].at;
    }

    patient_txt: str = "";
    patient_at: str = "";
    auth_txt: str = "";
    for u in utts {
        if u.role == "patient" and patient_txt == "" {
            patient_txt = u.text;
            patient_at = u.at;
        }
        if (u.role in ["oncologist", "pharmacist", "label"]) and auth_txt == "" {
            auth_txt = u.text;
        }
    }

    slots: dict[str, str] = {
        "symptom": c.anchor,
        "drug": c.anchor,
        "drug_a": c.anchor,
        "substance": c.anchor,
        "since": c.since,
        "count": str(len(utts)),
        "days": str(obs_count),
        "missed_days": str(obs_count),
        "cycles": str(obs_count),
        "at": (first_at if first_at != "" else c.since),
        "role": first_role,
        "criterion": first_txt,
        "source": first_role,
        "cause": (patient_txt if patient_txt != "" else first_txt),
        "observed": (patient_txt if patient_txt != "" else first_txt),
        "instruction": (auth_txt if auth_txt != "" else first_txt),
        "threshold_source": (auth_txt if auth_txt != "" else first_txt),
    };
    if patient_at != "" and patient_txt != "" {
        slots["at"] = patient_at;
    }
    if len(utts) > 0 {
        slots["claim_a"] = utts[0].text;
        slots["role_a"] = utts[0].role;
        slots["at_a"] = utts[0].at;
    }
    if len(utts) > 1 {
        slots["claim_b"] = utts[1].text;
        slots["role_b"] = utts[1].role;
        slots["at_b"] = utts[1].at;
    }
    if obs_count > 0 {
        slots["level"] = pg_latest_level(c);
    }
    return slots;
}


# Join the persisted Raised status onto a freshly-derived concern (CONTRACTS §2, S9). Concerns are
# derived every turn; only status persists, as a Raised node keyed by kind + anchor_key. A Raised
# node is duck-typed by its anchor_key + status fields (no node-type import; see #1 note). Assumes
# Recall attaches Raised directly under root; if that wiring differs this returns "open" (safe
# default) — reconcile at the Recall integration.
def pg_status(c: Concern, at_root: Root) -> str {
    for r in [at_root -->[?:Raised]] {   # #1 archetypes landed: typed filter instead of duck-typing
        if r.kind == c.kind and r.anchor_key == c.anchor {
            return r.status;
        }
    }
    return "open";
}


# Stable group-by-anchor: rows about the same anchor sit together, anchors in first-seen order,
# insertion order within a group. Deterministic — no clock, no randomness (#18).
def pg_group_by_anchor(rows: list[Row]) -> list[Row] {
    order: list[str] = [];
    buckets: dict[str, list[Row]] = {};
    for r in rows {
        anchor: str = r.id;              # Row.id is the anchor key (see pg_row)
        if anchor not in buckets {
            buckets[anchor] = [];
            order.append(anchor);
        }
        buckets[anchor].append(r);
    }
    result: list[Row] = [];
    for anchor in order {
        for r in buckets[anchor] {
            result.append(r);
        }
    }
    return result;
}


# STUB SEAM — CONTRACTS §7. The real derived concerns come from Recall (read.jac, #8/#10-#13),
# which runs the two-channel traversal and reinforces. Prepare is read-only (A9) and must not run
# Recall itself. Until the Recall->Prepare handoff lands, this returns nothing, so a fresh graph
# renders an empty page — "not in your record", never "safe" (S3). The render harness and future
# integration supply concerns via the `given=` kwarg instead of this stub.
def pg_derived_concerns -> list[Concern] {
    return [];
}


# One derived Concern -> one Row, or None when it must not be shown (no citation / dismissed).
def pg_row(c: Concern, at_root: Root) -> Row | None {
    cites: list[Citation] = pg_cites(c);
    if len(cites) == 0 {
        return None;                       # S2: no Utterance backs it -> never render it
    }
    status: str = pg_status(c, at_root);
    if status == "dismissed" {
        return None;                       # S9: dismissal mutes (the Raised node is retained)
    }
    parts: list[str] = pg_render(c.kind, pg_slots(c, cites));
    # Row.id IS the Concern's anchor key: page.cl.jac passes anchor=row.id into Investigate
    # (page.cl.jac header, CONTRACT NOTE for #23). Caveat, echoing the sibling's flag: this is not
    # unique when two concerns share an anchor. The durable fix is a dedicated Row.anchor slot — a
    # `contract` change to graph.jac's Row (Laksh applies), out of scope for main.jac. Surfaced.
    return Row(
        id=c.anchor,
        kind=c.kind,
        question=parts[0],
        why=parts[1],
        noticed=pg_noticed(c),
        citations=cites,
        status=status,
    );
}


# ==========================================================================================
# Prepare — issue #18.  Read-only page assembly (A9): joins Raised status, buckets by the
# severity ladder, groups by anchor, emits ONE PageModel, reports once from Root exit.
# Zero model calls. Zero edge-weight mutations. It never reinforces.
# ==========================================================================================

walker:pub Prepare {   # :pub — client-spawned (page.cl.jac `root spawn Prepare`); plain walker => Unauthorized (#34)
    has include_log: bool = False;
    has out: PageModel = PageModel();

    # Rendering seam (read-only): concerns supplied directly — e.g. Recall's Verdict.concerns —
    # take precedence; empty falls back to the pg_derived_concerns() stub. Additive and defaulted,
    # so the pinned spawn signature (include_log, out) still works unchanged. Whether this belongs
    # in the pinned contract is an OPEN DECISION (issue #18 / ARCHITECTURE §18) — surfaced here,
    # not resolved.
    has given: list[Concern] = [];

    can build with Root entry {
        source: list[Concern] = self.given if len(self.given) > 0 else pg_derived_concerns();
        esc: list[Row] = [];
        ask: list[Row] = [];
        men: list[Row] = [];
        logs: list[Row] = [];
        for c in source {
            row = pg_row(c, here);
            if row is not None {
                if c.action == "escalate" {
                    esc.append(row);
                } elif c.action == "ask" {
                    ask.append(row);
                } elif c.action == "mention" {
                    men.append(row);
                } else {
                    logs.append(row);
                }
            }
        }
        self.out.escalate = pg_group_by_anchor(esc);
        self.out.ask = pg_group_by_anchor(ask);
        self.out.mention = pg_group_by_anchor(men);
        # "Also tracking" is below the waterline — populated only on explicit request (#18).
        self.out.log = pg_group_by_anchor(logs) if self.include_log else [];
        # Activity-panel lines are read from producer-walker internal state (issue #24). Prepare is
        # read-only and never fabricates them (CONTRACTS §4) — it leaves the channel empty.
        self.out.activity = [];
    }

    can emit with Root exit {
        report self.out;                   # one typed object, once, from Root exit (CONTRACTS §4)
    }
}


# ==========================================================================================
# Client surface — issue #17.  Mounted at "/" via [serve] base_route_app = "app" (jac.toml).
# Client -> server is `root spawn` ONLY (CONTRACTS §1a #2) — no sv import, no function RPC. The
# concerns page itself lives in page.cl.jac (T3 Laksh) for HMR while the surface is iterated; per
# its header and issue #17, main.jac mounts it here and its body concatenates in at the final merge
# (the `import from .page` line is then deleted — CONTRACTS §1a). ConcernsPage `root spawn`s the
# Prepare walker above; the two files share types through graph.jac only.
# ==========================================================================================

cl {
    import "./styles/global.css";
    import from .page { AlongsideApp }

    def:pub app -> JsxElement {
        return <AlongsideApp />;
    }
}
