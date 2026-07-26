# SPIKE entry module. Archetypes + report objs live in graph.jac, mirroring
# the five-file layout in CONTRACTS.md section 1a.
import from graph { SpikeNote, SpikeLink, SpikeReport, SpikeWrite, SpikeRead, SpikeEnv, SpikeReset }

# ---------------------------------------------------------------- assumption 2
# `root spawn Walker(field=value)` from inside a cl { } block, reading
# result.reports back out. This is the only call path the UI uses.
cl {
    def:pub app() -> JsxElement {
        has out: str = "(nothing yet)";
        has busy: bool = False;

        async def do_write(_e: MouseEvent) {
            busy = True;
            result = root spawn SpikeWrite(label="from-client");
            if result.reports and len(result.reports) > 0 {
                r = result.reports[0];
                out = "WRITE ok - nodes now: " + str(r.node_count);
            } else {
                out = "WRITE returned no reports";
            }
            busy = False;
        }

        async def do_read(_e: MouseEvent) {
            busy = True;
            result = root spawn SpikeRead();
            if result.reports and len(result.reports) > 0 {
                r = result.reports[0];
                out = (
                    "READ ok - nodes: " + str(r.node_count)
                    + " | labels: " + ", ".join(r.labels)
                    + " | edge notes: " + ", ".join(r.edge_notes)
                    + " | two hops out: " + r.two_hops_out
                    + " | DEMO_MODE: " + r.demo_mode
                    + " | by llm(): " + r.llm_claim + " (hard=" + str(r.llm_hard) + ")"
                );
            } else {
                out = "READ returned no reports";
            }
            busy = False;
        }

        return (
            <div style={{"fontFamily": "monospace", "padding": "24px", "lineHeight": "1.6"}}>
                <h1>spike #30</h1>
                <p>five assumptions, one ugly page</p>
                <button id="btn-write" onClick={do_write} disabled={busy}>1. write node + typed edge</button>
                {" "}
                <button id="btn-read" onClick={do_read} disabled={busy}>2. read back (restart-safe?)</button>
                <pre id="spike-out" style={{"whiteSpace": "pre-wrap", "marginTop": "16px"}}>{out}</pre>
            </div>
        );
    }
}
