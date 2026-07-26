# page.cl.jac — "Questions for your care team" (the deliverable) + the daily check-in.
#
# Owner: Laksh (T3). This is the surface. It HMR-reloads on its own, and at submission its
# body concatenates into main.jac (CONTRACTS.md §1a). Every rule below keeps that merge mechanical:
#   - private helpers are pg_-prefixed; components keep real (globally-unique) names.
#   - all server calls are `root spawn` (never sv import / never function RPC).
#   - one styles/global.css (pg-* classes), no .style.css annex.
#   - types come only from graph.jac; this file never imports read.jac/write.jac.
#
# STUB-FIRST (CONTRACTS.md §7, CONTRIBUTING §7): the render path is driven by an inline fixture
# (pg_stub_model) so the page renders every section with no server. When Prepare/Remember/Investigate
# exist, `root spawn` supersedes the fixture on the live path. Nothing here calls a model — S8 is
# structural on the read path: every care sentence is a template-filled string off PageModel, or a
# verbatim quoted Utterance. The UI chrome ("Ask about these", "Why it came up") is not care prose.
#
# main.jac must, in its cl { } block:  import from .page { ConcernsPage }  and  app() returns
# <ConcernsPage />; and once, at the top of that block:  import ".styles.global.css";
#
# CONTRACT NOTE for #23: Investigate(concern_kind, anchor) needs an anchor, but Row (CONTRACTS §4)
# exposes only `id`. This file passes anchor=row.id, i.e. it assumes Prepare sets Row.id to the
# Concern's anchor key. If that is not the intent, Row needs an `anchor` slot — surfaced, not resolved.

import from .graph { PageModel, Row, Citation, CaseFile, TimelineEntry }

# ---- module state (not reactive) ------------------------------------------------------------------

glob _pg_rec: any = None;   # jac:ignore[W1037]  (live SpeechRecognition instance)
glob _PG_MONTHS: list[str] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

# Inspector (#26, cut-candidate) fixture: the retrieval claim made visible.
glob _PG_COSINE: list[dict] = [
    {"score": "0.91", "text": "nausea after chemo — ondansetron helps", "miss": False},
    {"score": "0.88", "text": "how do I manage a sinus infection", "miss": False},
    {"score": "0.85", "text": "is afternoon fatigue normal on imatinib", "miss": False},
    {"score": "0.83", "text": "what to eat before taking my pills", "miss": False},
    {"score": "0.79", "text": "ondansetron dose for nausea", "miss": False},
    {"score": "0.41", "text": "grapefruit ⇄ imatinib interaction  (ranked 11th)", "miss": True},
];
glob _PG_TRAVERSAL: list[str] = [
    "grapefruit",
    "→ CYP3A4 inhibitor",
    "→ CYP3A4 substrate",
    "→ imatinib   ✓ reached in 3 hops",
];

# ---- pg_ helpers ----------------------------------------------------------------------------------

def pg_today -> str {
    d = new(Date);   # jac:ignore[W2001, W6002]
    iso = d.toISOString();
    return iso[0:10];
}

def pg_fmt_date(at: str) -> str {
    if not at { return ""; }
    parts = at.split("-");
    if len(parts) != 3 { return at; }
    mi = int(parts[1]);
    if mi < 1 or mi > 12 { return at; }
    return _PG_MONTHS[mi - 1] + " " + str(int(parts[2]));
}

def pg_role_label(role: str) -> str {
    if role == "patient" { return "you"; }
    if role == "oncologist" { return "your oncology team"; }
    if role == "pharmacist" { return "your pharmacist"; }
    if role == "label" { return "pharmacy label"; }
    if role == "caregiver" { return "your caregiver"; }
    return role;
}

def pg_cite_quote(c: Citation) -> str {
    if c.role == "patient" or c.role == "caregiver" { return "“" + c.text + "”"; }
    return c.text;
}

def pg_cite_meta(c: Citation) -> str {
    return "— " + pg_role_label(c.role) + " · " + pg_fmt_date(c.at);
}

def pg_cite_detail(c: Citation) -> str {
    return pg_cite_quote(c) + "  — recorded as " + pg_role_label(c.role) + " on " + pg_fmt_date(c.at) + ".";
}

def pg_join(base: str, fin: str) -> str {
    return (base + " " + fin) if base else fin;
}

def pg_speech_supported -> bool {
    g: any = globalThis;   # jac:ignore[W2001, W6002, W1051, W1037]
    return bool(g.SpeechRecognition or g.webkitSpeechRecognition);
}

def pg_kind_for(m: PageModel, rid: str) -> str {
    for r in m.escalate { if r.id == rid { return r.kind; } }
    for r in m.ask { if r.id == rid { return r.kind; } }
    for r in m.mention { if r.id == rid { return r.kind; } }
    for r in m.log { if r.id == rid { return r.kind; } }
    return "";
}

# ---- fixtures (dev / HMR path; superseded by root spawn when walkers exist) -----------------------

def pg_stub_model -> PageModel {
    m = PageModel();
    m.ask = [
        Row(id="anchor:levofloxacin", kind="interaction",
            question="Is it okay that I'm taking ondansetron and levofloxacin at the same time?",
            why="Both can affect heart rhythm. Your oncology team prescribed ondansetron on Jul 3. "
                + "Urgent care prescribed levofloxacin on Jul 20. Neither prescription mentions the other.",
            noticed=[],
            citations=[
                Citation(text="ondansetron 8 mg — take as needed for nausea", role="label", at="2026-07-03"),
                Citation(text="urgent care gave me something for a sinus thing", role="patient", at="2026-07-20"),
            ],
            status="open"),
    ];
    m.mention = [
        Row(id="anchor:neuropathy", kind="unattributed_symptom",
            question="What's causing the tingling in my hands?",
            why="You've mentioned this 6 times since Jul 11. Nothing on your current medication list names "
                + "it as a known effect — which is why it's worth asking about rather than assuming it's expected.",
            noticed=["Jul 11", "Jul 13", "Jul 14", "Jul 17", "Jul 19", "Jul 22"],
            citations=[Citation(text="my hands are tingling again", role="patient", at="2026-07-22")],
            status="asked"),
        Row(id="anchor:imatinib-cost", kind="adherence_gap",
            question="I've been skipping doses because of cost.",
            why="You mentioned the copay on Jul 15. You haven't logged taking imatinib on 4 days since. "
                + "There may be assistance options — but they can't offer them if they think it's a side-effect problem.",
            noticed=[],
            citations=[Citation(text="skipped Tuesday, short on the copay", role="patient", at="2026-07-15")],
            status="open"),
        Row(id="anchor:imatinib-timing", kind="instruction_drift",
            question="Am I taking this the right way?",
            why="Your instructions say within 30 minutes after food. On 5 days you described taking it on an empty stomach.",
            noticed=[],
            citations=[
                Citation(text="take within 30 minutes after food", role="label", at="2026-07-01"),
                Citation(text="took it before breakfast again, empty stomach", role="patient", at="2026-07-18"),
            ],
            status="open"),
    ];
    m.log = [
        Row(id="anchor:fatigue", kind="trajectory",
            question="Afternoon fatigue.",
            why="Logged and tracked. Nothing on your record currently links it to a cause that needs "
                + "attention — kept here in case the pattern changes.",
            noticed=["Jul 12", "Jul 16", "Jul 20"],
            citations=[Citation(text="pretty wiped out after lunch", role="patient", at="2026-07-20")],
            status="open"),
    ];
    m.escalate = [];
    m.activity = [
        "On open: traversed 5 anchors, evaluated emergency criteria first — none met.",
        "Re-ran the interaction gate after your Jul 20 check-in.",
        "Channel B reached: grapefruit → CYP3A4 inhibitor → CYP3A4 substrate → imatinib.",
        "Consolidate rewrote 2 beliefs within its budget of 6.",
        "Every line on this page is a fixed template or your own quoted words — none was generated.",
    ];
    return m;
}

def pg_stub_escalate -> list[Row] {
    return [
        Row(id="anchor:fever", kind="emergency",
            question="",
            why="You logged a temperature of 38.6 °C. Your care team's printed instructions say to call "
                + "right away for any fever at or above 38.0 °C during this cycle.",
            noticed=[],
            citations=[Citation(text="call us for any fever at or above 38.0 °C", role="label", at="2026-07-01")],
            status="open"),
    ];
}

def pg_stub_casefile(_rid: str) -> CaseFile {
    cf = CaseFile();
    cf.onset = "2026-07-11";
    cf.timeline = [
        TimelineEntry(at="2026-07-11", what="First mentioned tingling in both hands", source="you"),
        TimelineEntry(at="2026-07-14", what="Mentioned again, worse in the morning", source="you"),
        TimelineEntry(at="2026-07-22", what="Still present; asked whether to worry", source="you"),
    ];
    cf.counterfactual = "If your medication list named this as a known effect, it would sit in "
        + "“Also tracking” instead. It doesn't — so it's worth raising rather than assuming.";
    cf.existing_instruction = "";
    cf.citations = [];
    return cf;
}

# ---- components -----------------------------------------------------------------------------------

def:pub CitationButton(idx: int, cite: Citation, onPick: Callable[[int], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onPick(idx); }
    return <button className="pg-cite" onClick={handle}>
        <span className="pg-cite-quote">{pg_cite_quote(cite)}</span>
        {" "}
        <span className="pg-cite-meta">{pg_cite_meta(cite)}</span>
    </button>;
}

def:pub CaseFileView(cf: CaseFile) -> JsxElement {
    return <div>
        {if cf.onset {
            <p className="pg-cf-block"><span className="pg-b">First seen:</span>{" " + pg_fmt_date(cf.onset)}</p>
        }}
        {if len(cf.timeline) > 0 {
            <div className="pg-casefile-h">Timeline</div>
            <ul className="pg-timeline">
                {for (i, t) in enumerate(cf.timeline) {
                    <li key={str(i)}>
                        <span className="pg-tl-at">{pg_fmt_date(t.at)}</span>
                        <span className="pg-tl-what">{t.what}{" "}<span className="pg-tl-src">{"(" + t.source + ")"}</span></span>
                    </li>
                }}
            </ul>
        }}
        {if cf.counterfactual {
            <p className="pg-cf-block"><span className="pg-b">Why it's worth asking:</span>{" " + cf.counterfactual}</p>
        }}
        {if cf.existing_instruction {
            <p className="pg-cf-block"><span className="pg-b">Existing instruction:</span>{" " + cf.existing_instruction}</p>
        }}
    </div>;
}

def:pub ConcernRow(row: Row, sev: str, expanded: bool, caseFile: CaseFile | None,
                   onToggle: Callable[[str], None], onRecordAnswer: Callable[[str, str], None]) -> JsxElement {
    has open_cite: int = -1;
    has show_answer: bool = False;
    has answer_text: str = "";

    def toggle_expand(_e: MouseEvent) { onToggle(row.id); }
    def toggle_answer(_e: MouseEvent) { show_answer = not show_answer; }
    def on_answer_change(e: ChangeEvent) { answer_text = e.target.value; }
    def pick_cite(idx: int) { open_cite = (-1 if open_cite == idx else idx); }
    async def send_answer -> None {
        if not answer_text { return; }
        onRecordAnswer(row.id, answer_text);
        answer_text = "";
        show_answer = False;
    }

    return <article className={"pg-row pg-row-" + sev}>
        <div className="pg-row-top">
            <h3 className="pg-row-q" onClick={toggle_expand}>{row.question if row.question else "(needs a question template)"}</h3>
        </div>
        <p className="pg-row-why">{row.why}</p>

        {if len(row.noticed) > 0 {
            <p className="pg-noticed"><span className="pg-noticed-label">What I've noticed</span></p>
            <div className="pg-chiprow">
                {for (i, d) in enumerate(row.noticed) { <span key={str(i)} className="pg-chip">{d}</span> }}
            </div>
        }}

        {if len(row.citations) > 0 {
            <div className="pg-cites">
                <div className="pg-cite-label">Where this came from</div>
                {for (i, c) in enumerate(row.citations) {
                    <CitationButton key={str(i)} idx={i} cite={c} onPick={pick_cite} />
                }}
                {if open_cite >= 0 and open_cite < len(row.citations) {
                    <div className="pg-cite-open">{pg_cite_detail(row.citations[open_cite])}</div>
                }}
            </div>
        }}

        <div className="pg-row-foot">
            <span className={"pg-status pg-status-" + row.status}>{row.status}</span>
            {if row.status != "answered" and row.status != "dismissed" {
                <button className="pg-btn pg-btn-ghost" onClick={toggle_answer}>{"Cancel" if show_answer else "Record what your team said"}</button>
            }}
        </div>

        {if show_answer {
            <div className="pg-answerbox">
                <div className="pg-answerbox-label">Record what your care team said</div>
                <textarea className="pg-textarea" value={answer_text} onChange={on_answer_change}
                    placeholder="e.g. Dr. Okafor said it's fine to take both, will recheck the ECG next visit." />
                <div className="pg-checkin-actions">
                    <button className="pg-btn pg-btn-primary" onClick={send_answer} disabled={not answer_text}>Save to record</button>
                </div>
                <p className="pg-answerbox-note">Saved as your care team's words (the highest-authority source in your record). Nothing is sent to anyone.</p>
            </div>
        }}

        {if expanded {
            <div className="pg-casefile">
                {if caseFile is None {
                    <p className="pg-casefile-loading">Opening the case file…</p>
                } else {
                    <CaseFileView cf={caseFile} />
                }}
            </div>
        }}
    </article>;
}

def:pub ConcernSection(title: str, rows: list[Row], sev: str, collapsible: bool, expandedId: str,   # jac:ignore[W3030]
                       caseFiles: dict[str, CaseFile], onToggle: Callable[[str], None],
                       onRecordAnswer: Callable[[str, str], None]) -> JsxElement {
    has open: bool = False;
    def toggle_open(_e: MouseEvent) { open = not open; }
    shown: bool = (not collapsible) or open;
    return <section className="pg-section">
        <div className="pg-section-head">
            <h2 className="pg-section-title">{title}</h2>
            <span className="pg-section-count">{str(len(rows))}</span>
            {if collapsible {
                <button className="pg-btn pg-btn-ghost pg-section-toggle" onClick={toggle_open}>{("Hide" if open else "Show") + " (" + str(len(rows)) + ")"}</button>
            }}
        </div>
        {if shown {
            if len(rows) == 0 {
                <p className="pg-empty">Nothing in this section — nothing matched in your record.</p>
                skip;
            }
            for r in rows {
                <ConcernRow key={r.id} row={r} sev={sev}
                    expanded={r.id == expandedId}
                    caseFile={caseFiles[r.id] if r.id in caseFiles else None}
                    onToggle={onToggle} onRecordAnswer={onRecordAnswer} />
            }
        }}
    </section>;
}

def:pub ActivityPanel(lines: list[str]) -> JsxElement {
    return <section className="pg-activity">
        <div className="pg-activity-h">What the system did</div>
        <ul className="pg-activity-list">
            {for (i, l) in enumerate(lines) { <li key={str(i)}>{l}</li> }}
        </ul>
    </section>;
}

def:pub Inspector() -> JsxElement {   # jac:ignore[W3005]
    return <div className="pg-inspector">
        <div className="pg-inspector-split">
            <div className="pg-pane pg-pane-cosine">
                <div className="pg-pane-h">Cosine top-k — what similarity retrieves</div>
                {for (i, rk) in enumerate(_PG_COSINE) {
                    <div key={str(i)} className={"pg-rank" + (" pg-rank-miss" if rk["miss"] else "")}>
                        <span className="pg-rank-score">{rk["score"]}</span>
                        <span>{rk["text"]}</span>
                    </div>
                }}
            </div>
            <div className="pg-pane pg-pane-traversal">
                <div className="pg-pane-h">Graph traversal — what reachability finds</div>
                {for (i, hop) in enumerate(_PG_TRAVERSAL) {
                    <div key={str(i)} className="pg-hop">{hop}</div>
                }}
            </div>
        </div>
        <div className="pg-inspector-note">The blocking fact ranks 11th by cosine — indistinguishable from absent. Traversal reaches it in 3 hops, and a missing edge would be inspectable. Relevance is reachability, not similarity.</div>
    </div>;
}

def:pub EscalateInterstitial(rows: list[Row], onDismiss: Callable[[], None]) -> JsxElement {
    return <div className="pg-escalate">
        <div className="pg-escalate-card">
            <h1 className="pg-escalate-h">Contact your care team now</h1>
            <p className="pg-escalate-body">Your recent check-in matches a criterion your team gave you to call about right away. This is not a diagnosis — it is an instruction from your own record.</p>
            <div className="pg-escalate-crit">
                {for r in rows { <p key={r.id}>{r.why}</p> }}
            </div>
            <button className="pg-btn pg-btn-primary" onClick={lambda (_e: MouseEvent) { onDismiss(); }}>I've contacted them — show my questions page</button>
        </div>
    </div>;
}

def:pub CheckInSurface(onSubmit: Callable[[str], None]) -> JsxElement {
    has text: str = "";
    has interim: str = "";
    has recording: bool = False;
    has supported: bool = True;
    has voice_error: str = "";

    can with entry {
        supported = pg_speech_supported();
    }

    def on_change(e: ChangeEvent) { text = e.target.value; }

    def start_voice {   # jac:ignore[W3005]
        g: any = globalThis;   # jac:ignore[W2001, W6002, W1051, W1037]
        Rec = g.SpeechRecognition or g.webkitSpeechRecognition;   # jac:ignore[W2001, W6002]
        if not Rec { supported = False; return; }
        base = text;
        _pg_rec = new(Rec);   # jac:ignore[W2001, W6002]
        rec = _pg_rec;
        rec.continuous = False;
        rec.interimResults = True;
        rec.lang = "en-US";
        rec.onresult = lambda (ev: any) {   # jac:ignore[W1037]
            fin = "";
            intr = "";
            i = 0;
            while i < ev.results.length {   # jac:ignore[W6004]
                seg = ev.results[i][0].transcript;
                if ev.results[i].isFinal { fin = fin + seg; }
                else { intr = intr + seg; }
                i = i + 1;
            }
            if fin { text = pg_join(base, fin); base = text; }
            interim = intr;
        };
        rec.onerror = lambda (ev: any) {   # jac:ignore[W1037]
            voice_error = ("Voice needs a network connection — type instead." if ev.error == "network" else "Voice input stopped — type instead.");
            recording = False;
        };
        rec.onend = lambda { recording = False; interim = ""; };
        rec.start();
        recording = True;
        voice_error = "";
    }

    def stop_voice {   # jac:ignore[W3005]
        rec = _pg_rec;
        if rec { rec.stop(); }
        recording = False;
    }

    def toggle_voice(_e: MouseEvent) {
        if recording { stop_voice(); }
        else { start_voice(); }
    }

    def submit(_e: MouseEvent) {
        if not text { return; }
        if recording { stop_voice(); }
        onSubmit(text);
        text = "";
        interim = "";
    }

    return <div className="pg-checkin">
        <div className="pg-checkin-head">
            <span className="pg-checkin-label">How are you feeling today?</span>
            {if supported {
                <button className={"pg-btn pg-mic" + (" pg-recording" if recording else "")} onClick={toggle_voice}>
                    <span className="pg-mic-dot"></span>
                    {" "}
                    {"Stop" if recording else "Speak"}
                </button>
            } else {
                <span className="pg-unavailable">Voice unavailable here — type below</span>
            }}
        </div>
        <textarea className="pg-textarea" value={text} onChange={on_change}
            placeholder="What did you take, and how do you feel? Type it, or tap Speak and edit before adding." />
        <div className="pg-checkin-actions">
            <span className={"pg-interim" + (" pg-live" if recording else "")}>{interim if recording else voice_error}</span>
            <button className="pg-btn pg-btn-primary" onClick={submit} disabled={not text}>Add to today's check-in</button>
        </div>
        <p className="pg-checkin-hint">Your words are saved exactly as written and quoted back to you — nothing is sent to anyone.</p>
    </div>;
}

def:pub ConcernsPage() -> JsxElement {   # jac:ignore[W3005]
    has model: PageModel = PageModel();
    has loaded: bool = False;
    has expanded_id: str = "";
    has case_files: dict[str, CaseFile] = {};
    has show_inspector: bool = False;
    has preview_escalate: bool = False;
    has escalate_ack: bool = False;

    async can with entry {
        m = pg_stub_model();
        try {
            # `as any`: pre-merge the Prepare walker (#18) is unbuilt, so the spawn result is
            # Unknown-typed. The cast keeps this file jac-check-clean now and is redundant (not
            # wrong) once Prepare lands in main.jac. The payload is re-asserted `as PageModel`.
            res: any = (root spawn Prepare(include_log=True)) as any;   # jac:ignore[W1051, W2001, W1037]
            if res and res.reports and len(res.reports) > 0 {
                m = res.reports[0] as PageModel;
            }
        } except Exception as e {
            console.log("[page] Prepare unavailable — rendering fixture:", e);   # jac:ignore[W2001, W6002]
        }
        model = m;
        loaded = True;
    }

    async def refresh {   # jac:ignore[W3005]
        try {
            res: any = (root spawn Prepare(include_log=True)) as any;   # jac:ignore[W1051, W2001, W1037]
            if res and res.reports and len(res.reports) > 0 {
                model = res.reports[0] as PageModel;
            }
        } except Exception as e {
            console.log("[page] Prepare refresh unavailable:", e);   # jac:ignore[W2001, W6002]
        }
    }

    async def submit_checkin(t: str) {
        try {
            root spawn Remember(text=t, role="patient", at=pg_today());   # jac:ignore[W1051, W2001]
        } except Exception as e {
            console.log("[page] Remember(patient) unavailable:", e);   # jac:ignore[W2001, W6002]
        }
        await refresh();
    }

    async def record_answer(_rid: str, ans: str) {
        try {
            root spawn Remember(text=ans, role="oncologist", at=pg_today());   # jac:ignore[W1051, W2001]
        } except Exception as e {
            console.log("[page] Remember(oncologist) unavailable:", e);   # jac:ignore[W2001, W6002]
        }
        await refresh();
    }

    async def toggle_row(rid: str) -> None {
        if expanded_id == rid {
            expanded_id = "";
            return;
        }
        expanded_id = rid;
        if rid in case_files { return; }
        cf = pg_stub_casefile(rid);
        try {
            k = pg_kind_for(model, rid);
            res: any = (root spawn Investigate(concern_kind=k, anchor=rid)) as any;   # jac:ignore[W1051, W2001, W1037]
            if res and res.reports and len(res.reports) > 0 {
                cf = res.reports[0] as CaseFile;
            }
        } except Exception as e {
            console.log("[page] Investigate unavailable — rendering fixture:", e);   # jac:ignore[W2001, W6002]
        }
        case_files = {**case_files, rid: cf};
    }

    def toggle_inspector(_e: MouseEvent) { show_inspector = not show_inspector; }
    def preview_escalate_click(_e: MouseEvent) { preview_escalate = True; escalate_ack = False; }
    def dismiss_escalate { escalate_ack = True; preview_escalate = False; }   # jac:ignore[W3005]

    if not loaded {
        return <div className="pg-app"><p className="pg-empty">Reading your record…</p></div>;
    }

    show_esc: bool = (len(model.escalate) > 0 and not escalate_ack) or preview_escalate;
    if show_esc {
        esc: list[Row] = model.escalate if len(model.escalate) > 0 else pg_stub_escalate();
        return <EscalateInterstitial rows={esc} onDismiss={dismiss_escalate} />;
    }

    return <div className="pg-app">
        <header className="pg-masthead">
            <h1 className="pg-title">Questions for your care team</h1>
            <p className="pg-subtitle">A standing page built from your daily check-ins. It fills up and drains — bring it to your next appointment. Nothing here is sent to anyone.</p>
            <div className="pg-checkin-actions">
                <button className="pg-btn pg-btn-ghost" onClick={toggle_inspector}>{("Hide" if show_inspector else "Show") + " how this was found"}</button>
                <button className="pg-btn pg-btn-ghost" onClick={preview_escalate_click}>Preview urgent alert</button>
            </div>
            {if show_inspector { <Inspector /> }}
        </header>

        <CheckInSurface onSubmit={submit_checkin} />

        {if len(model.activity) > 0 { <ActivityPanel lines={model.activity} /> }}

        <ConcernSection title="Ask about these" rows={model.ask} sev="ask" collapsible={False}
            expandedId={expanded_id} caseFiles={case_files} onToggle={toggle_row} onRecordAnswer={record_answer} />
        <ConcernSection title="Worth mentioning" rows={model.mention} sev="mention" collapsible={False}
            expandedId={expanded_id} caseFiles={case_files} onToggle={toggle_row} onRecordAnswer={record_answer} />
        <ConcernSection title="Also tracking" rows={model.log} sev="log" collapsible={True}
            expandedId={expanded_id} caseFiles={case_files} onToggle={toggle_row} onRecordAnswer={record_answer} />
    </div>;
}
