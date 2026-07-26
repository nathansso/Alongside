# SPIKE probe — issue #30. Run in separate processes:
#   jac run probe.jac write     -> writes a node + a typed edge
#   jac run probe.jac read      -> reads them back in a FRESH process
#   jac run probe.jac env       -> reads DEMO_MODE at spawn time
#   jac run probe.jac reset     -> in-app graph reset, no shell (see SpikeReset)
# If the read run sees the write run's nodes, assumption 1 holds.

import sys;
import from main { SpikeWrite, SpikeRead, SpikeEnv, SpikeReset }

with entry {
    mode = sys.argv[1] if len(sys.argv) > 1 else "read";

    if mode == "write" {
        wr = root spawn SpikeWrite(label="seed");
        w = wr.reports[0];
        print("[write] nodes attached to root now: " + str(w.node_count));
    } elif mode == "env" {
        er = root spawn SpikeEnv();
        e = er.reports[0];
        print("[env] DEMO_MODE = " + e.demo_mode);
    } elif mode == "reset" {
        sr = root spawn SpikeReset();
        s = sr.reports[0];
        print("[reset] deleted " + str(s.node_count) + " SpikeNote nodes");
    } else {
        rr = root spawn SpikeRead();
        o = rr.reports[0];
        print("[read] node_count   = " + str(o.node_count));
        print("[read] labels       = " + str(o.labels));
        print("[read] edge notes   = " + str(o.edge_notes));
        print("[read] two hops out = " + o.two_hops_out);
        print("[read] DEMO_MODE    = " + o.demo_mode);
        print("[read] by llm()     = " + o.llm_claim + "  (typed obj, hard=" + str(o.llm_hard) + ")");
    }
}
