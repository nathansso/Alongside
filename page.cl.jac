# page.cl.jac — Alongside: the five-view companion (Landing / Log / Visualize / Advocate / Profile).
#
# Owner: Laksh (T3). This is the surface. It HMR-reloads on its own, and at submission its
# body concatenates into main.jac (CONTRACTS.md §1a). Every rule below keeps that merge mechanical:
#   - private helpers are pg_-prefixed; components keep real (globally-unique) names.
#   - all server calls are `root spawn` (never sv import / never function RPC).
#   - one styles/global.css (pg-* classes), no .style.css annex.
#   - types come only from graph.jac; this file never imports read.jac/write.jac.
#
# This is a rebuild of the design handoff (design_handoff_mycancerpal/): a landing page plus four
# product surfaces behind a tabbed shell. Client-side view state routes between them (no server
# router). The Advocate surface stays wired to the live read path: `root spawn Prepare` assembles
# the page and `root spawn Remember` records a check-in. S8 holds structurally on the read path —
# every care sentence is a template-filled string off a PageModel Row, or a verbatim quoted
# Citation; nothing here is model-generated. S7 holds: the only "outbound" action is a browser
# print (the patient carries the page in). The Landing / Log / Visualize / Profile surfaces are
# design fixtures + local UI state, mirroring the prototype's client state.

import from .graph { PageModel, Row, Citation }

# ---- module state (not reactive) ------------------------------------------------------------------

glob _pg_rec: any = None;   # jac:ignore[W1037]  (live SpeechRecognition instance)
glob _PG_MONTHS: list[str] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

# Visualize fixture: your words → parsed label → link found → outcome. Coordinates in viewBox units
# (0..1360 × 0..600); hand-placed for the demo set — replace with a layered layout in production.
glob _PG_NODES: list[dict[str, str]] = [
    {"id": "w1", "kind": "your words · Jul 20", "label": "“urgent care gave me something for a sinus thing”", "meta": "check-in", "x": "150", "y": "100", "thread": "interaction"},
    {"id": "w2", "kind": "your words · Jul 11–23", "label": "“my hands are tingling again”", "meta": "6 mentions", "x": "150", "y": "300", "thread": "tingling"},
    {"id": "w3", "kind": "your words · Jul 15", "label": "“skipped Tuesday, short on the copay”", "meta": "check-in", "x": "150", "y": "500", "thread": "cost"},
    {"id": "a1", "kind": "parsed label", "label": "levofloxacin 500 mg", "meta": "urgent care · Jul 20", "x": "520", "y": "80", "thread": "interaction"},
    {"id": "a2", "kind": "parsed label", "label": "ondansetron 8 mg", "meta": "oncology · Jul 3", "x": "520", "y": "220", "thread": "interaction"},
    {"id": "a3", "kind": "parsed label", "label": "imatinib 400 mg, daily", "meta": "active · 4 doses not logged", "x": "520", "y": "420", "thread": "cost"},
    {"id": "g1", "kind": "link found", "label": "Both prolong QT interval", "meta": "2 prescribers, no overlap check", "x": "880", "y": "150", "thread": "interaction"},
    {"id": "g2", "kind": "link found", "label": "Symptom not listed for any active drug", "meta": "unexplained · 6 days", "x": "880", "y": "320", "thread": "tingling"},
    {"id": "g3", "kind": "link found", "label": "Missed doses follow a cost mention", "meta": "affordability, not tolerance", "x": "880", "y": "500", "thread": "cost"},
    {"id": "o1", "kind": "on your page", "label": "Is it okay to take these together?", "meta": "Bring this up", "x": "1210", "y": "150", "thread": "interaction"},
    {"id": "o2", "kind": "watching", "label": "Needs 1 more week before surfacing", "meta": "or add it yourself", "x": "1210", "y": "320", "thread": "tingling"},
    {"id": "o3", "kind": "on your page", "label": "I've been skipping doses because of cost", "meta": "Bring this up", "x": "1210", "y": "500", "thread": "cost"},
];

glob _PG_EDGES: list[list[str]] = [
    ["w1", "a1", "interaction"], ["a1", "g1", "interaction"], ["a2", "g1", "interaction"], ["g1", "o1", "interaction"],
    ["w2", "a3", "tingling"], ["w2", "g2", "tingling"], ["g2", "o2", "tingling"],
    ["w3", "a3", "cost"], ["a3", "g3", "cost"], ["g3", "o3", "cost"],
];

glob _PG_THREADS: list[dict[str, str]] = [
    {"id": "interaction", "label": "Medication interaction"},
    {"id": "tingling", "label": "Tingling — tracking only"},
    {"id": "cost", "label": "Cost and missed doses"},
];

# Per-thread detail panel for the focused graph thread (kicker/title/body + numbered hops + pill tone).
glob _PG_DETAILS: dict[str, dict] = {
    "interaction": {
        "kicker": "3 hops · Jul 20 → today",
        "title": "Two prescribers, one heart rhythm",
        "body": "Nothing here is a diagnosis. It is a gap: two clinicians prescribed drugs with the same cardiac effect and neither chart mentions the other.",
        "tone": "clay",
        "pill": "On your page · Bring this up",
        "hops": [
            {"n": "hop 1", "text": "Your check-in named a new medication from urgent care.", "src": "“urgent care gave me something for a sinus thing” · Jul 20"},
            {"n": "hop 2", "text": "The pharmacy label resolved it to levofloxacin 500 mg.", "src": "parsed label · Jul 20"},
            {"n": "hop 3", "text": "Levofloxacin and your ondansetron share a QT-prolongation effect.", "src": "ondansetron 8 mg · oncology · Jul 3"},
        ],
    },
    "tingling": {
        "kicker": "2 hops · tracking since Jul 11",
        "title": "A symptom nothing on your list explains",
        "body": "Six mentions across twelve days, and no active medication names it as an expected effect. It stays here until it reaches the bar — or until you decide it matters now.",
        "tone": "track",
        "pill": "Tracking · not on your page",
        "hops": [
            {"n": "hop 1", "text": "Tingling described in your own words on 6 separate days.", "src": "check-ins · Jul 11, 13, 14, 17, 19, 22"},
            {"n": "hop 2", "text": "Checked against every active drug — not a listed effect of any.", "src": "3 parsed labels"},
        ],
    },
    "cost": {
        "kicker": "3 hops · Jul 15 → today",
        "title": "Missed doses that aren't about side effects",
        "body": "Framing matters: if the team reads this as intolerance they change the drug. Read as cost, they can bring in assistance instead.",
        "tone": "clay",
        "pill": "On your page · Bring this up",
        "hops": [
            {"n": "hop 1", "text": "You mentioned the copay directly.", "src": "“skipped Tuesday, short on the copay” · Jul 15"},
            {"n": "hop 2", "text": "Imatinib went unlogged on 4 days afterwards.", "src": "parsed label · daily schedule"},
            {"n": "hop 3", "text": "The gaps cluster after the cost mention, not after side-effect days.", "src": "check-ins · Jul 15–23"},
        ],
    },
};

# Watched patterns below the surfacing bar. Mirrored on Advocate ("Also tracking") and Visualize
# (the dashed tracking panel) so the gap is visible from both sides. Per-pattern counts/thresholds
# are a not-yet-built backend channel (handoff README, "Real data needed"); fixture until then.
glob _PG_WATCHING: list[dict[str, str]] = [
    {"title": "Tingling in both hands", "why": "6 mentions since Jul 11, not listed for any active drug. Surfaces at 8 mentions or if it spreads.", "pct": "75%", "count": "6 / 8"},
    {"title": "Mouth sores after infusion days", "why": "3 mentions, all within 48 hours of infusion — expected, so it only surfaces if severity rises.", "pct": "38%", "count": "3 / 8"},
    {"title": "Grapefruit juice at breakfast", "why": "Mentioned twice. Affects the same pathway as imatinib, but not yet often enough to be a pattern.", "pct": "25%", "count": "2 / 8"},
];

glob _PG_TAGS: list[dict[str, str]] = [
    {"label": "Nausea", "sentence": "Felt nauseous today."},
    {"label": "Tingling", "sentence": "Hands tingling again."},
    {"label": "Tired", "sentence": "Very tired, slept most of the afternoon."},
    {"label": "Sore mouth", "sentence": "Mouth is sore."},
    {"label": "Slept badly", "sentence": "Didn't sleep well."},
    {"label": "Skipped a dose", "sentence": "Skipped a dose today."},
];

glob _PG_MEDS: list[dict[str, str]] = [
    {"name": "Imatinib 400 mg", "meta": "once daily, within 30 min after food", "source": "label · Jul 1"},
    {"name": "Ondansetron 8 mg", "meta": "as needed for nausea", "source": "label · Jul 3"},
    {"name": "Levofloxacin 500 mg", "meta": "7-day course, started Jul 20", "source": "label · Jul 20"},
    {"name": "Metformin 500 mg", "meta": "twice daily — added by you", "source": "you · Jun 12"},
];

glob _PG_BAR_DELAYS: list[str] = ["0s", "0.11s", "0.22s", "0.33s", "0.44s", "0.55s", "0.66s"];

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

def pg_join(base: str, fin: str) -> str {
    b: str = base.strip();
    return (b + " " + fin) if b else fin;
}

def pg_speech_supported -> bool {
    g: any = globalThis;   # jac:ignore[W2001, W6002, W1051, W1037]
    return bool(g.SpeechRecognition or g.webkitSpeechRecognition);
}

# True once any section carries a row. Prepare (#18) reads derived concerns from a stub until the
# Recall->Prepare handoff is wired, so a live spawn returns a shape-valid but EMPTY PageModel. Treat
# empty as "not ready yet" and keep the fixture, so the demo never blanks (stub-first, CONTRACTS §7).
def pg_nonempty(m: PageModel) -> bool {
    return (len(m.escalate) + len(m.ask) + len(m.mention) + len(m.log)) > 0;
}

# Graph geometry: a cubic bezier from a source right-port to a target left-port (ports at node.x±105).
def pg_edge_path(x1: int, y1: int, x2: int, y2: int) -> str {
    mx: int = (x1 + x2) // 2;
    return "M " + str(x1) + " " + str(y1) + " C " + str(mx) + " " + str(y1) + ", "
        + str(mx) + " " + str(y2) + ", " + str(x2) + " " + str(y2);
}

def pg_node_by_id(nid: str) -> dict[str, str] {
    for n in _PG_NODES {
        if n["id"] == nid { return n; }
    }
    return {};
}

# Edge/node stroke colour by thread: grey = tracking-only, clay = surfaced, pine = asked/answered.
def pg_stroke_for(thread: str) -> str {
    if thread == "tingling" { return "#a29e94"; }
    if thread == "interaction" { return "#b0653f"; }
    return "#2f6d64";
}

def pg_rule_for(kind: str, thread: str) -> str {
    if kind[0:10] == "your words" { return "#c9c6bd"; }
    return pg_stroke_for(thread);
}

# (pill className, pill label) for an Advocate concern by its persisted status (CONTRACTS §2, S9).
def pg_pill_for(status: str) -> list[str] {
    if status == "asked" { return ["pg-pill pg-pill-slate", "Asked"]; }
    if status == "answered" { return ["pg-pill pg-pill-pine", "Answered"]; }
    if status == "dismissed" { return ["pg-pill pg-pill-track", "Set aside"]; }
    return ["pg-pill pg-pill-clay", "Bring this up"];
}

# ---- fixture (dev / HMR path; superseded by root spawn Prepare when it yields concerns) ------------

def pg_stub_model -> PageModel {
    m = PageModel();
    m.ask = [
        Row(id="anchor:levofloxacin", kind="interaction",
            question="Is it okay that I'm taking ondansetron and levofloxacin at the same time?",
            why="Both can affect heart rhythm. Your oncology team prescribed one on Jul 3 and urgent care "
                + "prescribed the other on Jul 20 — neither prescription mentions the other.",
            noticed=[],
            citations=[
                Citation(text="ondansetron 8 mg, as needed for nausea", role="label", at="2026-07-03"),
                Citation(text="urgent care gave me something for a sinus thing", role="patient", at="2026-07-20"),
            ],
            status="open"),
    ];
    m.mention = [
        Row(id="anchor:imatinib-cost", kind="adherence_gap",
            question="I've been skipping doses because of the cost.",
            why="You mentioned the copay on Jul 15 and imatinib went unlogged on 4 days since. Said plainly, "
                + "this reads as a cost problem — there may be assistance for it. Read as a side effect, they "
                + "may change the drug instead.",
            noticed=[],
            citations=[Citation(text="skipped Tuesday, short on the copay", role="patient", at="2026-07-15")],
            status="open"),
        Row(id="anchor:imatinib-timing", kind="instruction_drift",
            question="Am I taking the imatinib the right way?",
            why="Your label says within 30 minutes after food. On 5 days you described taking it on an empty stomach.",
            noticed=[],
            citations=[
                Citation(text="take within 30 minutes after food", role="label", at="2026-07-01"),
                Citation(text="took it before breakfast again, empty stomach", role="patient", at="2026-07-18"),
            ],
            status="open"),
        Row(id="anchor:neuropathy", kind="unattributed_symptom",
            question="What's causing the tingling in my hands?",
            why="Six mentions since Jul 11. Nothing on your medication list names it as a known effect — which "
                + "is why it's worth asking rather than assuming it's expected.",
            noticed=["Jul 11", "Jul 13", "Jul 14", "Jul 17", "Jul 19", "Jul 22"],
            citations=[Citation(text="my hands are tingling again", role="patient", at="2026-07-22")],
            status="asked"),
    ];
    m.log = [];
    m.escalate = [];
    m.activity = [];
    return m;
}

# ---- Landing --------------------------------------------------------------------------------------

def:pub LandingView(onNav: Callable[[str], None]) -> JsxElement {
    def go_log(_e: MouseEvent) { onNav("log"); }
    def go_adv(_e: MouseEvent) { onNav("advocate"); }

    return <div className="pg-landing">
        <div className="pg-land-bar">
            <div className="pg-brand" onClick={go_log}>
                <div className="pg-brand-mark"></div>
                <div className="pg-brand-name">Alongside</div>
            </div>
            <button className="pg-link" onClick={go_log}>Open the app</button>
        </div>

        <div className="pg-hero">
            <div className="pg-hero-left">
                <div className="pg-hero-eyebrow">For people in treatment</div>
                <h1 className="pg-hero-h1">You'll remember it. We'll write it down.</h1>
                <p className="pg-hero-body">Tell Alongside how the day went, in your own words. Between appointments it keeps one page of questions worth asking — each one showing the check-in or pharmacy label it came from.</p>
                <div className="pg-hero-actions">
                    <button className="pg-btn pg-btn-primary" onClick={go_log}>Start today's check-in</button>
                    <button className="pg-btn pg-btn-outline" onClick={go_adv}>See an example page</button>
                </div>
                <div className="pg-hero-privacy">Nothing is sent to your care team on your behalf. No alerts, no messages. You decide what to bring in.</div>
            </div>

            <div className="pg-hero-card">
                <div className="pg-hero-card-meta">Tuesday, Jul 15 · your words</div>
                <div className="pg-hero-quote">“skipped Tuesday, short on the copay”</div>
                <div className="pg-hero-divider"><span>8 days later</span></div>
                <div className="pg-hero-q">“I've been skipping doses because of the cost.”</div>
                <div className="pg-hero-caption">Waiting on your questions page — so the team hears it as a cost problem, not a side effect.</div>
                <span className="pg-pill pg-pill-clay">Bring this up</span>
            </div>
        </div>

        <div className="pg-how">
            <div className="pg-how-label">How it works</div>
            <div className="pg-how-grid">
                <div className="pg-how-col">
                    <div className="pg-how-num">01 · Log</div>
                    <div className="pg-how-title">Say how today went</div>
                    <div className="pg-how-body">Type it or speak it — a sentence is enough. Your words are stored exactly as you said them and quoted back to you, never rewritten.</div>
                </div>
                <div className="pg-how-col">
                    <div className="pg-how-num">02 · Visualize</div>
                    <div className="pg-how-title">See what connects to what</div>
                    <div className="pg-how-body">Check-ins link to medications parsed from your labels. When two things interact, the connection between them is drawn — and you can follow it hop by hop.</div>
                </div>
                <div className="pg-how-col">
                    <div className="pg-how-num">03 · Advocate</div>
                    <div className="pg-how-title">Walk in with a page</div>
                    <div className="pg-how-body">Concerns collect into one printable page of questions, each with its date and source. It empties as things get answered.</div>
                </div>
            </div>
        </div>
    </div>;
}

# ---- App shell nav --------------------------------------------------------------------------------

def:pub AppNav(view: str, initials: str, navName: str, advCount: int,
               onNav: Callable[[str], None]) -> JsxElement {
    def go_home(_e: MouseEvent) { onNav("landing"); }
    def go_log(_e: MouseEvent) { onNav("log"); }
    def go_viz(_e: MouseEvent) { onNav("visualize"); }
    def go_adv(_e: MouseEvent) { onNav("advocate"); }
    def go_prof(_e: MouseEvent) { onNav("profile"); }

    return <div className="pg-nav">
        <div className="pg-nav-inner">
            <div className="pg-nav-brand" onClick={go_home}>
                <div className="pg-brand-mark"></div>
                <div className="pg-brand-name">Alongside</div>
            </div>
            <div className="pg-nav-tabs">
                <button className={"pg-tab pg-tab-active" if view == "log" else "pg-tab"} onClick={go_log}>Log</button>
                <button className={"pg-tab pg-tab-active" if view == "visualize" else "pg-tab"} onClick={go_viz}>Visualize</button>
                <button className={"pg-tab pg-tab-active" if view == "advocate" else "pg-tab"} onClick={go_adv}>Advocate{if advCount > 0 { <span key="badge" className="pg-tab-badge">{str(advCount)}</span> }}</button>
            </div>
            <button className={"pg-avatar pg-avatar-active" if view == "profile" else "pg-avatar"} onClick={go_prof}>
                <span className="pg-avatar-circle">{initials}</span>
                <span className="pg-avatar-name">{navName + " · day 41"}</span>
            </button>
        </div>
    </div>;
}

# ---- Log ------------------------------------------------------------------------------------------

def:pub TagChip(label: str, sentence: str, onAdd: Callable[[str], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onAdd(sentence); }
    return <button className="pg-tag" onClick={handle}>{label}</button>;
}

def:pub EntryCard(item: dict) -> JsxElement {
    time: str = item["time"] as str;
    text: str = item["text"] as str;
    links: list[str] = item["links"] as list[str];
    return <div className="pg-entry">
        <div className="pg-entry-time">{time}</div>
        <div className="pg-entry-text">{text}</div>
        {if len(links) > 0 {
            <div key="links" className="pg-entry-links">
                {for (i, l) in enumerate(links) { <span key={str(i)} className="pg-entry-link">{l}</span> }}
            </div>
        }}
    </div>;
}

def:pub LogView(name: str, entries: list[dict], onSave: Callable[[str], None],
                onNav: Callable[[str], None]) -> JsxElement {   # jac:ignore[W3005]
    has draft: str = "";
    has interim: str = "";
    has recording: bool = False;
    has supported: bool = True;
    has voice_error: str = "";

    can with entry {
        supported = pg_speech_supported();
    }

    def on_change(e: ChangeEvent) { draft = e.target.value; }
    def add_tag(sentence: str) { draft = pg_join(draft, sentence); }
    def go_viz(_e: MouseEvent) { onNav("visualize"); }

    def start_voice {   # jac:ignore[W3005]
        g: any = globalThis;   # jac:ignore[W2001, W6002, W1051, W1037]
        Rec = g.SpeechRecognition or g.webkitSpeechRecognition;   # jac:ignore[W2001, W6002]
        if not Rec { supported = False; return; }
        base = draft;
        _pg_rec = new(Rec);   # jac:ignore[W2001, W6002, E1053]
        rec = _pg_rec;
        rec.continuous = False;
        rec.interimResults = True;
        rec.lang = "en-US";
        rec.onresult = lambda (ev: any) {   # jac:ignore[W1037]
            fin = "";
            intr = "";
            i = 0;
            while i < (ev.results.length as int) {   # jac:ignore[W6004]
                seg: str = ev.results[i][0].transcript as str;
                is_final: bool = ev.results[i].isFinal as bool;
                if is_final { fin = fin + seg; }
                else { intr = intr + seg; }
                i = i + 1;
            }
            if fin { draft = pg_join(base, fin); base = draft; }
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
        t: str = draft.strip();
        if not t { return; }
        if recording { stop_voice(); }
        onSave(t);
        draft = "";
        interim = "";
    }

    return <div className="pg-view pg-view-720">
        <div className="pg-log-head">
            <div className="pg-log-date">Wednesday, Jul 23</div>
            <h2 className="pg-h2">{"How are you doing today, " + (name if name else "there") + "?"}</h2>
            <p className="pg-sub">A sentence is plenty. How you slept, what you took, anything that felt off.</p>
        </div>

        <div className="pg-composer">
            <textarea className="pg-textarea" value={draft} onChange={on_change} rows={5}
                placeholder="Type here, or tap Speak and edit before saving." />

            {if recording {
                <div key="listening" className="pg-listening">
                    <div className="pg-bars">
                        {for (i, dly) in enumerate(_PG_BAR_DELAYS) { <div key={str(i)} className="pg-bar" style={{"animationDelay": dly}}></div> }}
                    </div>
                    <div className="pg-listening-txt">{interim if interim else "Listening — say it however it comes out."}</div>
                </div>
            }}

            <div className="pg-composer-actions">
                {if supported {
                    <button key="speak" className="pg-speak" onClick={toggle_voice}>
                        <span className={"pg-speak-dot pg-rec" if recording else "pg-speak-dot"}></span>
                        {"Stop and review" if recording else "Speak instead"}
                    </button>
                } else {
                    <span key="unsup" className="pg-composer-hint">Voice unavailable here — type below.</span>
                }}
                {if voice_error and not recording { <span key="verr" className="pg-composer-err">{voice_error}</span> }}
                <div className="pg-composer-spacer"></div>
                <button className="pg-btn pg-btn-primary pg-btn-radius-sm" onClick={submit} disabled={not draft}>Add to today's check-in</button>
            </div>
            <div className="pg-composer-hint">Saved exactly as written and quoted back to you. Nothing is sent to anyone.</div>
        </div>

        <div className="pg-tags-block">
            <div className="pg-tags-intro">Or tap what fits — you can still add words.</div>
            <div className="pg-tags">
                {for (i, t) in enumerate(_PG_TAGS) { <TagChip key={str(i)} label={t["label"]} sentence={t["sentence"]} onAdd={add_tag} /> }}
            </div>
        </div>

        <div className="pg-today">
            <div className="pg-today-head">
                <div className="pg-today-label">Today so far</div>
                <button className="pg-link" onClick={go_viz}>See what this connected to →</button>
            </div>
            {for (i, e) in enumerate(entries) { <EntryCard key={str(i)} item={e} /> }}
        </div>
    </div>;
}

# ---- Visualize ------------------------------------------------------------------------------------

def:pub GraphNode(gnode: dict[str, str], onFocus: Callable[[str], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onFocus(gnode["thread"]); }
    return <div className="pg-gnode" onClick={handle}
        style={{"left": gnode["left"], "top": gnode["top"], "opacity": gnode["o"],
                "background": gnode["bg"],
                "borderTopColor": gnode["bd"], "borderRightColor": gnode["bd"],
                "borderBottomColor": gnode["bd"], "borderLeftColor": gnode["rule"]}}>
        <div className="pg-gnode-kind">{gnode["kind"]}</div>
        <div className="pg-gnode-label">{gnode["label"]}</div>
        <div className="pg-gnode-meta">{gnode["meta"]}</div>
    </div>;
}

def:pub FilterChip(threadId: str, label: str, active: bool, onFocus: Callable[[str], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onFocus(threadId); }
    return <button className={"pg-filter pg-filter-active" if active else "pg-filter"} onClick={handle}>{label}</button>;
}

def:pub VisualizeView(focus: str, onFocus: Callable[[str], None], onNav: Callable[[str], None]) -> JsxElement {   # jac:ignore[W3005]
    def go_adv(_e: MouseEvent) { onNav("advocate"); }

    edges_out: list[dict[str, str]] = [];
    for e in _PG_EDGES {
        a: dict[str, str] = pg_node_by_id(e[0]);
        b: dict[str, str] = pg_node_by_id(e[1]);
        thread: str = e[2];
        x1: int = int(a["x"]) + 105;
        y1: int = int(a["y"]);
        x2: int = int(b["x"]) - 105;
        y2: int = int(b["y"]);
        edges_out.append({
            "d": pg_edge_path(x1, y1, x2, y2),
            "stroke": pg_stroke_for(thread),
            "w": "2.4" if focus == thread else "1.4",
            "dash": "7 6" if thread == "tingling" else "0",
            "o": "1" if focus == thread else "0.22",
        });
    }

    nodes_out: list[dict[str, str]] = [];
    for n in _PG_NODES {
        thread2: str = n["thread"];
        active: bool = focus == thread2;
        kind: str = n["kind"];
        is_out: bool = kind == "on your page" or kind == "watching";
        nx: int = int(n["x"]);
        ny: int = int(n["y"]);
        nodes_out.append({
            "kind": kind,
            "label": n["label"],
            "meta": n["meta"],
            "thread": thread2,
            "left": str((nx / 1360) * 100) + "%",
            "top": str((ny / 600) * 100) + "%",
            "o": "1" if active else "0.35",
            "bg": "#fdf8f5" if (is_out and thread2 != "tingling") else "#fdfcfa",
            "bd": "#c9c6bd" if active else "#e3e1db",
            "rule": pg_rule_for(kind, thread2),
        });
    }

    d: dict = _PG_DETAILS[focus];
    kicker: str = d["kicker"] as str;
    title: str = d["title"] as str;
    body: str = d["body"] as str;
    tone: str = d["tone"] as str;
    pill: str = d["pill"] as str;
    hops: list[dict] = d["hops"] as list[dict];
    pill_cls: str = "pg-pill pg-pill-clay" if tone == "clay" else "pg-pill pg-pill-track";

    return <div className="pg-view pg-view-1240">
        <div className="pg-viz-head">
            <div className="pg-viz-intro">
                <h2 className="pg-viz-h2">What's connected to what</h2>
                <p className="pg-sub">Every check-in and every parsed label is a point. Lines are the links found between them — follow one to see how a question got onto your page.</p>
            </div>
            <div className="pg-viz-filters">
                {for (i, t) in enumerate(_PG_THREADS) { <FilterChip key={str(i)} threadId={t["id"]} label={t["label"]} active={focus == t["id"]} onFocus={onFocus} /> }}
            </div>
        </div>

        <div className="pg-canvas">
            <div className="pg-canvas-inner">
                <svg className="pg-graph-svg" viewBox="0 0 1360 600" preserveAspectRatio="none">
                    {for (i, e) in enumerate(edges_out) {
                        <path key={str(i)} d={e["d"]} fill="none" stroke={e["stroke"]} strokeWidth={e["w"]} strokeDasharray={e["dash"]} opacity={e["o"]} />   # jac:ignore[W1050]
                    }}
                </svg>
                {for (i, n) in enumerate(nodes_out) { <GraphNode key={str(i)} gnode={n} onFocus={onFocus} /> }}
            </div>
            <div className="pg-legend">
                <div className="pg-legend-item"><span className="pg-sw pg-sw-clay"></span>on your page</div>
                <div className="pg-legend-item"><span className="pg-sw pg-sw-pine"></span>answered or asked</div>
                <div className="pg-legend-item"><span className="pg-sw pg-sw-dash"></span>tracking, not surfaced yet</div>
                <div className="pg-legend-note">emergency criteria evaluated first on every open — none met</div>
            </div>
        </div>

        <div className="pg-viz-grid">
            <div className="pg-detail">
                <div className="pg-detail-kicker">{kicker}</div>
                <div className="pg-detail-title">{title}</div>
                <div className="pg-detail-body">{body}</div>
                <div className="pg-hops">
                    {for (i, h) in enumerate(hops) {
                        <div key={str(i)} className="pg-hop">
                            <div className="pg-hop-n">{h["n"] as str}</div>
                            <div className="pg-hop-col">
                                <div className="pg-hop-text">{h["text"] as str}</div>
                                <div className="pg-hop-src">{h["src"] as str}</div>
                            </div>
                        </div>
                    }}
                </div>
                <div className="pg-detail-foot">
                    <span className={pill_cls}>{pill}</span>
                    <button className="pg-link" onClick={go_adv}>Open on Advocate →</button>
                </div>
            </div>

            <div className="pg-track">
                <div className="pg-track-head">
                    <div className="pg-track-label">Tracking, not on your page yet</div>
                    <div className="pg-track-intro">Watched patterns that haven't met the bar to become a question. Add one yourself if it matters to you.</div>
                </div>
                {for (i, w) in enumerate(_PG_WATCHING) {
                    <div key={str(i)} className="pg-track-item">
                        <div className="pg-track-title">{w["title"]}</div>
                        <div className="pg-track-why">{w["why"]}</div>
                        <div className="pg-track-bar-row">
                            <div className="pg-track-bar"><div className="pg-track-bar-fill" style={{"width": w["pct"]}}></div></div>
                            <div className="pg-track-count">{w["count"]}</div>
                        </div>
                        <button className="pg-link" onClick={go_adv}>Add to my questions</button>
                    </div>
                }}
            </div>
        </div>
    </div>;
}

# ---- Advocate -------------------------------------------------------------------------------------

def:pub QCard(row: Row, clay: bool, onLog: Callable[[], None]) -> JsxElement {
    def handle_log(_e: MouseEvent) { onLog(); }
    pill: list[str] = pg_pill_for(row.status);
    return <div className={"pg-qcard pg-qcard-clay" if clay else "pg-qcard"}>
        <div className={"pg-qcard-q pg-qcard-q-lg" if clay else "pg-qcard-q pg-qcard-q-md"}>{row.question}</div>
        <div className="pg-qcard-body">{row.why}</div>
        {if len(row.citations) > 0 {
            <div key="ev" className={"pg-evidence pg-evidence-clay" if clay else "pg-evidence"}>
                {for (i, c) in enumerate(row.citations) {
                    <div key={str(i)} className="pg-ev">
                        <div className="pg-ev-quote">{pg_cite_quote(c)}</div>
                        <div className="pg-ev-meta">{pg_cite_meta(c)}</div>
                    </div>
                }}
            </div>
        }}
        <div className="pg-qcard-foot">
            <span className={pill[0]}>{pill[1]}</span>
            <button className="pg-link" onClick={handle_log}>Log the answer</button>
        </div>
    </div>;
}

def:pub AdvocateView(model: PageModel, onNav: Callable[[str], None]) -> JsxElement {
    def go_viz(_e: MouseEvent) { onNav("visualize"); }
    def do_print(_e: MouseEvent) { g: any = globalThis; g.print(); }   # jac:ignore[W2001, W6002, W1037, W1051]
    def log_answer { onNav("log"); }   # jac:ignore[W3005]

    return <div className="pg-view pg-view-720">
        <div className="pg-adv-head">
            <h2 className="pg-h2">Questions for your care team</h2>
            <p className="pg-sub">Built from your check-ins since Jun 12. Bring it to your Jul 29 appointment — it empties as things get answered. Nothing here is sent to anyone.</p>
            <div className="pg-adv-actions">
                <button className="pg-btn pg-btn-primary pg-btn-radius-sm" onClick={do_print}>Print for my visit</button>
                <button className="pg-btn pg-btn-outline pg-btn-radius-sm" onClick={go_viz}>Show how these were found</button>
            </div>
        </div>

        {if len(model.ask) > 0 {
            <div key="askg" className="pg-adv-group">
                <div className="pg-adv-group-head">
                    <div className="pg-adv-label pg-adv-label-clay">Ask about these</div>
                    <div className="pg-rule pg-rule-clay"></div>
                </div>
                {for r in model.ask { <QCard key={r.id} row={r} clay={True} onLog={log_answer} /> }}
            </div>
        }}

        {if len(model.mention) > 0 {
            <div key="meng" className="pg-adv-group">
                <div className="pg-adv-group-head">
                    <div className="pg-adv-label">Worth mentioning</div>
                    <div className="pg-rule"></div>
                </div>
                {for r in model.mention { <QCard key={r.id} row={r} clay={False} onLog={log_answer} /> }}
            </div>
        }}

        <div className="pg-adv-track">
            <div className="pg-adv-label">Also tracking — not questions yet</div>
            {for (i, w) in enumerate(_PG_WATCHING) {
                <div key={str(i)} className="pg-adv-track-item">
                    <div className="pg-adv-track-title">{w["title"]}</div>
                    <div className="pg-adv-track-count">{w["count"]}</div>
                </div>
            }}
            {for r in model.log {
                <div key={r.id} className="pg-adv-track-item">
                    <div className="pg-adv-track-title">{r.question}</div>
                    <div className="pg-adv-track-count">{str(len(r.noticed)) + " noted"}</div>
                </div>
            }}
            <button className="pg-link" onClick={go_viz}>See these on the graph →</button>
        </div>
    </div>;
}

# ---- Profile --------------------------------------------------------------------------------------

def:pub ProfileField(fieldKey: str, label: str, hint: str, placeholder: str, value: str,
                     onField: Callable[[str, str], None], span2: bool = False) -> JsxElement {
    def handle(e: ChangeEvent) { onField(fieldKey, e.target.value); }
    return <label className={"pg-field pg-field-span2" if span2 else "pg-field"}>
        <span className="pg-field-label">{label}</span>
        <input className="pg-field-input" value={value} onChange={handle} placeholder={placeholder} />
        {if hint { <span key="hint" className="pg-field-hint">{hint}</span> }}
    </label>;
}

def:pub ProfileChip(fieldKey: str, value: str, active: bool, onPick: Callable[[str, str], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onPick(fieldKey, value); }
    return <button className={"pg-chip pg-chip-active" if active else "pg-chip"} onClick={handle}>{value}</button>;
}

def:pub ProfileChips(label: str, fieldKey: str, current: str, options: list[str], hint: str,
                     onPick: Callable[[str, str], None]) -> JsxElement {
    return <div className="pg-prof-chips">
        <span className="pg-prof-chips-label">{label}</span>
        <div className="pg-chip-set">
            {for (i, o) in enumerate(options) { <ProfileChip key={str(i)} fieldKey={fieldKey} value={o} active={current == o} onPick={onPick} /> }}
        </div>
        {if hint { <span key="hint" className="pg-prof-chips-hint">{hint}</span> }}
    </div>;
}

def:pub ProfileView(profile: dict[str, str], saved: bool, onField: Callable[[str, str], None],
                    onPick: Callable[[str, str], None], onSave: Callable[[], None]) -> JsxElement {
    def handle_save(_e: MouseEvent) { onSave(); }
    def handle_notes(e: ChangeEvent) { onField("notes", e.target.value); }

    return <div className="pg-view pg-view-760">
        <div className="pg-prof-section">
            <h2 className="pg-h2">Your profile</h2>
            <p className="pg-sub">Used to make your questions page accurate and to print a header your care team recognises. Stored on this device — nothing is shared unless you print or hand it over.</p>
        </div>

        <div className="pg-prof-section">
            <div className="pg-prof-sec-head"><div className="pg-prof-sec-label">About you</div><div className="pg-rule"></div></div>
            <div className="pg-prof-grid">
                <ProfileField fieldKey="first" label="First name" hint="" placeholder="" value={profile["first"]} onField={onField} />
                <ProfileField fieldKey="last" label="Last name" hint="" placeholder="" value={profile["last"]} onField={onField} />
                <ProfileField fieldKey="dob" label="Date of birth" hint="Used to date the printed page." placeholder="" value={profile["dob"]} onField={onField} />
                <ProfileField fieldKey="age" label="Age" hint="" placeholder="" value={profile["age"]} onField={onField} />
                <ProfileField fieldKey="pronouns" label="Pronouns" hint="Appears on anything you print." placeholder="she / her" value={profile["pronouns"]} onField={onField} span2={True} />
            </div>
            <ProfileChips label="Sex recorded on your chart" fieldKey="sex" current={profile["sex"]}
                options={["Female", "Male", "Intersex", "Prefer not to say"]}
                hint="Some dosing and risk guidance differs. Tell us if your chart and your identity don't match — both can be printed."
                onPick={onPick} />
        </div>

        <div className="pg-prof-section">
            <div className="pg-prof-sec-head"><div className="pg-prof-sec-label">Diagnosis</div><div className="pg-rule"></div></div>
            <div className="pg-prof-grid">
                <ProfileField fieldKey="diagnosis" label="Diagnosis" hint="Write it as your team says it — we quote it back, we don't interpret it." placeholder="" value={profile["diagnosis"]} onField={onField} span2={True} />
                <ProfileField fieldKey="diagnosedOn" label="Diagnosed on" hint="Day 1 of your timeline." placeholder="" value={profile["diagnosedOn"]} onField={onField} />
                <ProfileField fieldKey="center" label="Treatment center" hint="" placeholder="" value={profile["center"]} onField={onField} />
            </div>
            <ProfileChips label="Stage or phase" fieldKey="stage" current={profile["stage"]}
                options={["Chronic phase", "Accelerated", "Blast crisis", "In remission", "Not sure"]}
                hint="Optional. Leave it blank if your team hasn't given you one."
                onPick={onPick} />
        </div>

        <div className="pg-prof-section">
            <div className="pg-prof-sec-head"><div className="pg-prof-sec-label">Care team and contacts</div><div className="pg-rule"></div></div>
            <div className="pg-prof-grid">
                <ProfileField fieldKey="oncologist" label="Oncologist" hint="" placeholder="" value={profile["oncologist"]} onField={onField} />
                <ProfileField fieldKey="nurseLine" label="Nurse line" hint="Shown on the emergency card, never dialled for you." placeholder="" value={profile["nurseLine"]} onField={onField} />
                <ProfileField fieldKey="contactName" label="Emergency contact" hint="" placeholder="" value={profile["contactName"]} onField={onField} />
                <ProfileField fieldKey="contactPhone" label="Their phone" hint="" placeholder="" value={profile["contactPhone"]} onField={onField} />
            </div>
        </div>

        <div className="pg-prof-section">
            <div className="pg-prof-sec-head"><div className="pg-prof-sec-label">Current medications</div><div className="pg-rule"></div></div>
            <div className="pg-meds">
                {for (i, m) in enumerate(_PG_MEDS) {
                    <div key={str(i)} className="pg-med">
                        <div className="pg-med-info">
                            <div className="pg-med-name">{m["name"]}</div>
                            <div className="pg-med-meta">{m["meta"]}</div>
                        </div>
                        <div className="pg-med-src">{m["source"]}</div>
                    </div>
                }}
                <div className="pg-med-add">Add a medication by photographing the label</div>
            </div>
        </div>

        <div className="pg-prof-section">
            <div className="pg-prof-sec-head"><div className="pg-prof-sec-label">Allergies and other conditions</div><div className="pg-rule"></div></div>
            <textarea className="pg-textarea" value={profile["notes"]} onChange={handle_notes} rows={3}
                placeholder="Penicillin allergy, type 2 diabetes, anything a new clinician should know." />
        </div>

        <div className="pg-prof-foot">
            <button className="pg-btn pg-btn-primary pg-btn-radius-sm" onClick={handle_save}>Save profile</button>
            <span className="pg-prof-saved">{"Saved on this device just now." if saved else "Changes stay on this device."}</span>
        </div>
    </div>;
}

# ---- Escalate interstitial (full-screen safety surface, before the app) ---------------------------

def:pub EscalateInterstitial(rows: list[Row], onDismiss: Callable[[], None]) -> JsxElement {
    def handle(_e: MouseEvent) { onDismiss(); }
    return <div className="pg-escalate">
        <div className="pg-escalate-card">
            <h1 className="pg-escalate-h">Contact your care team now</h1>
            <p className="pg-escalate-body">Your recent check-in matches a criterion your team gave you to call about right away. This is not a diagnosis — it is an instruction from your own record.</p>
            <div className="pg-escalate-crit">
                {for r in rows { <p key={r.id}>{r.why}</p> }}
            </div>
            <button className="pg-escalate-btn" onClick={handle}>I've contacted them — show my page</button>
        </div>
    </div>;
}

# ---- Top-level shell ------------------------------------------------------------------------------

def:pub AlongsideApp() -> JsxElement {   # jac:ignore[W3005]
    has view: str = "landing";
    has focus: str = "interaction";
    has entries: list[dict] = [
        {"time": "8:10 am", "text": "Took the imatinib after breakfast like the label says.", "links": ["imatinib", "timing"]},
        {"time": "2:45 pm", "text": "Hands tingling again, worse than yesterday.", "links": ["tingling", "6th mention"]},
    ];
    has profile: dict[str, str] = {
        "first": "Maya", "last": "Rodriguez", "pronouns": "she / her",
        "dob": "1979-03-14", "age": "47", "sex": "Female",
        "diagnosis": "Chronic myeloid leukemia (CML)", "stage": "Chronic phase",
        "diagnosedOn": "Jun 12, 2026", "center": "Ridgeline Cancer Center",
        "oncologist": "Dr. A. Reyes", "nurseLine": "(415) 555-0142",
        "contactName": "Luis Rodriguez (husband)", "contactPhone": "(415) 555-0188",
        "notes": "Penicillin allergy. Type 2 diabetes, metformin twice daily.",
    };
    has saved: bool = False;
    has model: PageModel = PageModel();
    has escalate_ack: bool = False;

    async can with entry {
        m = pg_stub_model();
        try {
            # `as any`: pre-merge the Prepare walker result is Unknown-typed; the cast keeps this file
            # jac-check-clean and is redundant (not wrong) once Prepare lands in main.jac.
            res: any = (root spawn Prepare(include_log=True)) as any;   # jac:ignore[W1051, W2001, W1037]
            if res and res.reports {   # truthy list; avoids len(<any>) -> Sized E1053
                pm2 = res.reports[0] as PageModel;
                if pg_nonempty(pm2) { m = pm2; }   # else keep the fixture (Prepare has no concerns yet)
            }
        } except Exception as e {
            console.log("[page] Prepare unavailable — rendering fixture:", e);   # jac:ignore[W2001, W6002]
        }
        model = m;
    }

    async def refresh {   # jac:ignore[W3005]
        try {
            res: any = (root spawn Prepare(include_log=True)) as any;   # jac:ignore[W1051, W2001, W1037]
            if res and res.reports {
                pm2 = res.reports[0] as PageModel;
                model = pm2 if pg_nonempty(pm2) else pg_stub_model();   # keep fixture until concerns flow
            }
        } except Exception as e {
            console.log("[page] Prepare refresh unavailable:", e);   # jac:ignore[W2001, W6002]
        }
    }

    def go(v: str) { view = v; }
    def set_focus(t: str) { focus = t; }

    def set_field(key: str, val: str) {
        # Manual copy loop (not {**profile}): the bare dict-spread mis-infers the value type (#46/#60).
        merged: dict[str, str] = {};
        for k in profile { merged[k] = profile[k]; }
        merged[key] = val;
        profile = merged;
        saved = False;
    }
    def set_pick(key: str, val: str) { set_field(key, val); }
    def save_profile { saved = True; }   # jac:ignore[W3005]
    def dismiss_escalate { escalate_ack = True; }   # jac:ignore[W3005]

    async def save_checkin(t: str) {
        entry: dict = {"time": "just now", "text": t, "links": ["saved in your words"]};
        entries = entries + [entry];
        try {
            root spawn Remember(text=t, role="patient", at=pg_today());   # jac:ignore[W1051, W2001]
        } except Exception as e {
            console.log("[page] Remember(patient) unavailable:", e);   # jac:ignore[W2001, W6002]
        }
        await refresh();
    }

    first: str = profile["first"];
    last: str = profile["last"];
    fi: str = first[0:1].upper() if len(first) > 0 else "";
    li: str = last[0:1].upper() if len(last) > 0 else "";
    initials: str = (fi + li) if (fi + li) != "" else "—";
    nav_name: str = (first + " " + (last[0:1] + "." if len(last) > 0 else "")) if len(first) > 0 else "Your profile";
    adv_count: int = len(model.ask) + len(model.mention);

    show_esc: bool = len(model.escalate) > 0 and not escalate_ack;
    if show_esc {
        return <EscalateInterstitial rows={model.escalate} onDismiss={dismiss_escalate} />;
    }

    if view == "landing" {
        return <LandingView onNav={go} />;
    }

    return <div className="pg-shell">
        <AppNav key="nav" view={view} initials={initials} navName={nav_name} advCount={adv_count} onNav={go} />
        {if view == "log" { <LogView key="log" name={first} entries={entries} onSave={save_checkin} onNav={go} /> }}
        {if view == "visualize" { <VisualizeView key="viz" focus={focus} onFocus={set_focus} onNav={go} /> }}
        {if view == "advocate" { <AdvocateView key="adv" model={model} onNav={go} /> }}
        {if view == "profile" { <ProfileView key="prof" profile={profile} saved={saved} onField={set_field} onPick={set_pick} onSave={save_profile} /> }}
    </div>;
}
