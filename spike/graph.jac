# SPIKE — issue #30. Throwaway. Not in the demo, not in the merge.
# Converts five platform assumptions into facts. Keep it ugly.

import os;
import from byllm.lib { MockLLM }

# ---------------------------------------------------------------- assumption 3
# `by llm()` must return a typed obj we can read fields off.
# MockLLM proves the plumbing without a network call or an API key.
obj Extracted {
    has claim: str;
    has kind: str;
    has hard: bool = False;
}

glob llm = MockLLM(
    model_name="mockllm",
    config={"outputs": [Extracted(claim="grapefruit interacts", kind="constraint", hard=True)]}
);

def extract(text: str) -> Extracted by llm();
sem extract = "Extract a typed belief from patient free text.";
sem extract.text = "The patient's raw check-in sentence.";

# ---------------------------------------------------------------- assumption 1
# A node and an edge must survive a process restart.
node SpikeNote {
    has label: str;
    has emergency: bool = False;   # <-- ARCHETYPE CHANGE, mid-experiment
}

edge SpikeLink {
    has hops: int = 2;   # <-- EDGE ARCHETYPE CHANGE
    has note: str = "";
}

obj SpikeReport {
    has kind: str = "";
    has node_count: int = 0;
    has labels: list[str] = [];
    has edge_notes: list[str] = [];
    has two_hops_out: str = "";
    has demo_mode: str = "";
    has llm_claim: str = "";
    has llm_hard: bool = False;
}

walker:pub SpikeWrite {
    has label: str = "seed";
    has out: SpikeReport = SpikeReport();
    has reports: list[SpikeReport] = [];

    can write with Root entry {
        a = (here ++> SpikeNote(label=self.label))[0];
        a +>:SpikeLink(note="hop-1"):+> SpikeNote(label=self.label + "-child");
        self.out.kind = "write";
        # NOTE: `len([root -->][?:SpikeNote])` inline fails JS codegen with E5016
        # when the walker is reachable from a cl { } block. Bind it first.
        attached: list[SpikeNote] = [root -->][?:SpikeNote];
        self.out.node_count = len(attached);
    }

    can done with Root exit {
        report self.out;
    }
}

# Reads back everything, two hops out, over a TYPED edge.
walker:pub SpikeRead {
    has out: SpikeReport = SpikeReport();
    has reports: list[SpikeReport] = [];

    can start with Root entry {
        self.out.kind = "read";
        self.out.demo_mode = os.getenv("DEMO_MODE", "<unset>");
        visit [-->];
    }

    can seen with SpikeNote entry {
        self.out.labels.append(here.label);
        for e in [edge here ->:SpikeLink:->] {
            self.out.edge_notes.append(e.note);
        }
        for child in [here ->:SpikeLink:->][?:SpikeNote] {
            self.out.two_hops_out = child.label;
        }
        visit [-->];
    }

    can finish with Root exit {
        self.out.node_count = len(self.out.labels);
        ex = extract("my neighbour gave me grapefruit juice");
        self.out.llm_claim = ex.claim;
        self.out.llm_hard = ex.hard;
        report self.out;
    }
}

# ---------------------------------------------------------------- assumption 4
# A project-scoped env var must be readable AT RUNTIME (not just at boot).
walker:pub SpikeEnv {
    has out: SpikeReport = SpikeReport();
    has reports: list[SpikeReport] = [];

    can check with Root entry {
        self.out.kind = "env";
        self.out.demo_mode = os.getenv("DEMO_MODE", "<unset>");
    }

    can done with Root exit {
        report self.out;
    }
}

# ------------------------------------------------------- the graph reset path
# There is no shell on jachammer, so `rm -rf .jac/data/` does not exist there.
# This is the in-app equivalent: a walker that deletes every node of every
# persisted type. Filter `del` BY NODE TYPE — an unfiltered `del [-->]` walks
# into root's own anchors and raises EdgeAnchor errors.
walker:pub SpikeReset {
    has out: SpikeReport = SpikeReport();
    has reports: list[SpikeReport] = [];

    has doomed: list[SpikeNote] = [];

    can wipe with Root entry {
        self.out.kind = "reset";
        visit [-->];
    }

    # Collect at EVERY depth. `[root -->][?:SpikeNote]` alone reaches depth 1
    # only, which orphans everything further out instead of deleting it.
    can mark with SpikeNote entry {
        self.doomed.append(here);
        visit [-->];
    }

    can done with Root exit {
        self.out.node_count = len(self.doomed);
        for n in self.doomed {
            del n;
        }
    }

    can emit with Root exit {
        report self.out;
    }
}

