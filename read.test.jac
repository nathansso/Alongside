# read.test.jac — tests for the read path. Owner: T2 Nathan. Annex to `read.jac`.
#
# Run with `jac test read.jac`. This is an ANNEX: it pairs to `read.jac` by base name and sees its
# declarations without importing them. It ships nothing.
#
# TWO THINGS TO KNOW BEFORE RUNNING
#
# 1. `jac clean --force` first. Tests in a file run in declaration order against ONE shared,
#    PERSISTED root. Without a clean the fixtures below are re-created on every run and the strict
#    violation counts go red on the second pass — that is the documented behaviour, not a flake.
#
# 2. The fixture is temporary and belongs to #8 only. #7 owns the real seeded patient. When it
#    lands this fixture is deleted, not merged into it — the `Recall` code does not change.
#    At the single-file merge (CONTRACTS §1a) this annex is DELETED, not moved: base-name pairing
#    means a `read.test.jac` with no `read.jac` fails with `No module named 'read'`.
#
# Every test keys its anchors with a per-test prefix so the shared root cannot leak one test's
# topology into the next.
#
# The annex sees `read.jac`'s own declarations but NOT its imports, so the archetypes it builds
# fixtures out of have to be imported again here. Omitting the edges fails with E2018 in connect
# position — and only under `jac check .`, since `jac check read.jac` alone does not pull the annex.

import from graph {
    Anchor, Constraint, Utterance,
    DerivedFrom, Governs, Excludes, Member, Supersedes
}


# ==========================================================================================
# The acceptance case: a blocking constraint two hops out on a cold edge, 10 spawns out of 10.
# Topology is the real one from `write.jac`'s VOCAB_MEMBERS —
#   grapefruit --class_member--> CYP3A4-inhibitor --toxicity_of--> CYP3A4-substrate
# with the constraint sitting on the far end, reachable only by expanding `Member` twice.
# ==========================================================================================

test "channel B returns a constraint two hops out, on every one of ten runs" {
    t = "t1_";
    gf = Anchor(key=t + "grapefruit", kind="food");
    inh = Anchor(key=t + "CYP3A4-inhibitor", kind="class");
    sub = Anchor(key=t + "CYP3A4-substrate", kind="class");
    root ++> gf;
    root ++> inh;
    root ++> sub;
    gf +>:Member(via="class_member"):+> inh;
    inh +>:Member(via="toxicity_of"):+> sub;

    u = Utterance(
        text="Avoid anything that raises your imatinib levels.",
        at="2026-03-14",
        role="pharmacist"
    );
    root ++> u;
    c = Constraint(claim="avoid raising CYP3A4 substrate exposure", hard=True);
    root ++> c;
    c +>:Excludes(because="FDA label section 7, drug interactions"):+> sub;
    c +>:DerivedFrom:+> u;

    for i in range(10) {
        r = root spawn Recall(anchors=[t + "grapefruit"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds

        assert len(r.reports) == 1, f"run {i}: expected exactly one report";
        v = r.reports[0];

        # A stable count across ten spawns also proves the `has out: Verdict = Verdict()` default
        # is not a shared mutable instance accumulating across runs.
        assert len(v.violations) == 1, f"run {i}: expected 1 violation, got {len(v.violations)}";

        viol = v.violations[0];
        assert viol.claim == "avoid raising CYP3A4 substrate exposure", f"run {i}: wrong claim";
        assert viol.source == "pharmacist", f"run {i}: S2 source";
        assert viol.at == "2026-03-14", f"run {i}: S2 at";
        assert viol.because == "FDA label section 7, drug interactions", f"run {i}: because";
        assert not v.allowed, f"run {i}: a hard constraint must block";
    }
}


# S2, restated as a property rather than a spot check: nothing channel B emits may carry an empty
# source or at, whatever the topology.
test "every Violation carries a non-empty source and at" {
    r = root spawn Recall(anchors=["t1_grapefruit"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.violations) > 0, "fixture precondition: expected at least one violation";
    for viol in v.violations {
        assert viol.source != "", "S2: empty source";
        assert viol.at != "", "S2: empty at";
    }
}


# ==========================================================================================
# `Supersedes` is the ONLY thing that kills a channel B constraint (A2).
# ==========================================================================================

test "a superseded constraint is dropped and its replacement survives" {
    t = "t2_";
    a = Anchor(key=t + "naproxen", kind="ingredient");
    root ++> a;

    u_old = Utterance(text="Stop the naproxen for now.", at="2026-01-05", role="oncologist");
    u_new = Utterance(
        text="You can restart the naproxen, but not alongside ibuprofen.",
        at="2026-02-20",
        role="oncologist"
    );
    root ++> u_old;
    root ++> u_new;

    old = Constraint(claim="no naproxen", hard=True);
    new = Constraint(claim="no naproxen alongside ibuprofen", hard=True);
    root ++> old;
    root ++> new;
    old +>:Governs:+> a;
    new +>:Governs:+> a;
    old +>:DerivedFrom:+> u_old;
    new +>:DerivedFrom:+> u_new;
    new +>:Supersedes:+> old;

    r = root spawn Recall(anchors=[t + "naproxen"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    claims = [x.claim for x in v.violations];
    assert "no naproxen alongside ibuprofen" in claims, "the live constraint must be returned";
    assert "no naproxen" not in claims, "a superseded constraint must not be returned";
    assert len(v.violations) == 1, f"expected 1 violation, got {len(v.violations)}";

    # `Governs` carries no `because` by schema — the claim is its own reason.
    assert v.violations[0].because == "", "Governs hit should have an empty because";
}


# ==========================================================================================
# Cycle safety. `Member` is not guaranteed acyclic by the schema and the visit queue does not
# dedupe, so without the seen-set guards this test hangs rather than fails.
# ==========================================================================================

test "a Member cycle terminates and dedupes to one violation" {
    t = "t3_";
    x = Anchor(key=t + "x", kind="class");
    y = Anchor(key=t + "y", kind="class");
    z = Anchor(key=t + "z", kind="class");
    root ++> x;
    root ++> y;
    root ++> z;
    x +>:Member(via="class_member"):+> y;
    y +>:Member(via="class_member"):+> z;
    z +>:Member(via="class_member"):+> x;

    u = Utterance(text="Nothing from that class.", at="2026-04-01", role="oncologist");
    root ++> u;
    c = Constraint(claim="avoid class z", hard=True);
    root ++> c;
    c +>:Governs:+> z;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "x"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.violations) == 1, f"expected 1 violation, got {len(v.violations)}";
    assert not v.allowed;
}


# A constraint reachable from two different requested anchors is one constraint, not two.
test "a constraint reached from two anchors emits one Violation" {
    t = "t4_";
    a1 = Anchor(key=t + "ondansetron", kind="ingredient");
    a2 = Anchor(key=t + "levofloxacin", kind="ingredient");
    cls = Anchor(key=t + "QT-prolonging", kind="class");
    root ++> a1;
    root ++> a2;
    root ++> cls;
    a1 +>:Member(via="class_member"):+> cls;
    a2 +>:Member(via="class_member"):+> cls;

    u = Utterance(
        text="Watch the QT interval with anything in that class.",
        at="2026-05-02",
        role="oncologist"
    );
    root ++> u;
    c = Constraint(claim="monitor QT-prolonging exposure", hard=True);
    root ++> c;
    c +>:Excludes(because="two prescribers, one shared risk"):+> cls;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "ondansetron", t + "levofloxacin"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.violations) == 1, f"expected 1 deduped violation, got {len(v.violations)}";
}


# ==========================================================================================
# The two cases the read path deliberately does NOT render.
# ==========================================================================================

# A hard constraint with no `DerivedFrom` cannot become a `Violation` (S2 makes it structurally
# unconstructable) and cannot become a citable `Concern` either. The BLOCKING half still has to
# survive — that is the whole point of setting `allowed` on the hit rather than on the citation.
test "an uncitable hard constraint still blocks and yields no Violation" {
    t = "t5_";
    a = Anchor(key=t + "alcohol", kind="food");
    root ++> a;
    c = Constraint(claim="no alcohol on this regimen", hard=True);
    root ++> c;
    c +>:Governs:+> a;
    # deliberately no DerivedFrom edge

    r = root spawn Recall(anchors=[t + "alcohol"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.violations) == 0, "S2: unconstructable without a citation";
    assert not v.allowed, "the blocking answer must survive an uncitable constraint";

    noted = False;
    for n in r.rd_notes {
        if "uncitable constraint" in n {
            noted = True;
        }
    }
    assert noted, "an uncitable constraint must be recorded, not dropped in silence";
}


# S3: absence is "not in your record", never "safe". The read path records it rather than
# fabricating a Concern it knows `pg_row` would drop for having no citation.
test "an unresolved anchor key is recorded, not fabricated into a Concern" {
    r = root spawn Recall(anchors=["t6_never_heard_of_this"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.violations) == 0;
    assert len(v.concerns) == 0, "the read path must not fabricate an uncitable concern";

    noted = False;
    for n in r.rd_notes {
        if ("not in your record" in n) and ("t6_never_heard_of_this" in n) {
            noted = True;
        }
    }
    assert noted, "S3: absence must be recorded as 'not in your record'";
}


# `allowed` is false IFF channel B hit a Constraint with hard == True (CONTRACTS §3). A soft one
# is still collected — channel B collects all, unscored — but it does not block.
test "a soft constraint is collected but does not set allowed false" {
    t = "t7_";
    a = Anchor(key=t + "calcium", kind="food");
    root ++> a;
    u = Utterance(
        text="I'd rather you took the calcium at a different time of day.",
        at="2026-06-11",
        role="patient"
    );
    root ++> u;
    c = Constraint(claim="separate calcium from the morning dose", hard=False);
    root ++> c;
    c +>:Excludes(because="timing preference, not a contraindication"):+> a;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "calcium"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.violations) == 1, "channel B collects soft constraints too";
    assert v.allowed, "only a hard constraint sets allowed false";
}


# `rd_latest_source` picks the most recent citation when a constraint was restated.
test "a restated constraint is cited to its most recent Utterance" {
    t = "t8_";
    a = Anchor(key=t + "ibuprofen", kind="ingredient");
    root ++> a;
    u1 = Utterance(text="No ibuprofen while your platelets are low.", at="2026-02-01", role="oncologist");
    u2 = Utterance(text="Still no ibuprofen — same reason as before.", at="2026-04-18", role="oncologist");
    root ++> u1;
    root ++> u2;
    c = Constraint(claim="no ibuprofen", hard=True);
    root ++> c;
    c +>:Governs:+> a;
    c +>:DerivedFrom:+> u1;
    c +>:DerivedFrom:+> u2;

    r = root spawn Recall(anchors=[t + "ibuprofen"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.violations) == 1;
    assert v.violations[0].at == "2026-04-18", "should cite the restatement, not the original";
}


# Member expansion is OUTGOING only. A constraint on a class must not bind a sibling ingredient in
# that class — otherwise "no grapefruit" silently becomes "no CYP3A4 inhibitors".
test "Member expansion does not walk backwards into sibling members" {
    t = "t9_";
    cls = Anchor(key=t + "NSAID", kind="class");
    sib = Anchor(key=t + "sibling-nsaid", kind="ingredient");
    asked = Anchor(key=t + "asked-nsaid", kind="ingredient");
    root ++> cls;
    root ++> sib;
    root ++> asked;
    sib +>:Member(via="class_member"):+> cls;
    asked +>:Member(via="class_member"):+> cls;

    u = Utterance(text="Not that particular one.", at="2026-07-01", role="oncologist");
    root ++> u;
    c = Constraint(claim="no sibling-nsaid specifically", hard=True);
    root ++> c;
    c +>:Governs:+> sib;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "asked-nsaid"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.violations) == 0, "a constraint on one class member must not bind its siblings";
    assert v.allowed;
}
