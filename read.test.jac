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
# 3. THE #9 TESTS ARE ORDER-SENSITIVE AND THE PREFIXES DO NOT PROTECT THEM. The emergency scan is
#    deliberately NOT filtered by `self.anchors` (S5 — see `rd_emergency`), so it sees every
#    emergency `Constraint` at root regardless of which anchors a test queries. The instant one
#    test seeds an emergency that FIRES, every later spawn in this file takes the bypass. So the
#    `e*_` tests below run non-firing fixtures first and firing fixtures last, and the firing ones
#    assert "a concern for MY anchor exists" rather than an exact concern count. This is a real
#    property of the design, not a test smell: a fired emergency really does pre-empt everything.
#
# The annex sees `read.jac`'s own declarations but NOT its imports, so the archetypes it builds
# fixtures out of have to be imported again here. Omitting the edges fails with E2018 in connect
# position — and only under `jac check .`, since `jac check read.jac` alone does not pull the annex.

import from graph {
    Anchor, Belief, Constraint, Observation, Preference, Utterance,
    About, DerivedFrom, Governs, Excludes, Member, Reports, Supersedes, Relates
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


# ==========================================================================================
# #10 — detection mechanism 1. THESE MUST STAY ABOVE THE #9 BLOCK.
#
# From `e6_` down an emergency FIRES, and the bypass `disengage`s before `rd_start` — so a
# mechanism-1 test placed after it would spawn a walker that never resolves an anchor, never
# visits one, and returns an emergency verdict. It would not error; it would just quietly assert
# nothing. Appending these to the end of the file is the obvious thing to do and it is wrong.
#
# They self-guard: every assertion below is "a concern of MY kind, on MY anchor, exists". If the
# bypass ever pre-empts them, the only concern in the verdict is `kind="emergency"` and these go
# red rather than silently passing.
# ==========================================================================================

# ACCEPTANCE (#10), and the headline detection. Two prescribers, one shared toxicity, nobody
# compared them because nobody was in both rooms. Topology is the real one from `write.jac`'s
# VOCAB_MEMBERS — note that it is TWO hops, `ingredient --class_member--> class --toxicity_of-->
# symptom`, and not the one-hop shape ARCHITECTURE §7 describes.
test "two independently prescribed drugs converging on one symptom raise one additive_toxicity" {
    t = "m1_";
    onda = Anchor(key=t + "ondansetron", kind="ingredient");
    levo = Anchor(key=t + "levofloxacin", kind="ingredient");
    qtc = Anchor(key=t + "QT-prolonging", kind="class");
    qtp = Anchor(key=t + "qt_prolongation", kind="symptom");
    root ++> onda;
    root ++> levo;
    root ++> qtc;
    root ++> qtp;
    onda +>:Member(via="class_member"):+> qtc;
    levo +>:Member(via="class_member"):+> qtc;
    qtc +>:Member(via="toxicity_of"):+> qtp;

    # Two prescribers, four months apart. The prescriber IS `Utterance.role` and the regimen date
    # IS `Utterance.at` — graph.jac's definition of active regimen, verbatim.
    u_onda = Utterance(text="Ondansetron 8mg for the nausea.", at="2026-02-10", role="oncologist");
    u_levo = Utterance(
        text="Levofloxacin 500mg twice daily for the infection.",
        at="2026-05-03",
        role="pharmacist"
    );
    root ++> u_onda;
    root ++> u_levo;

    b_onda = Belief(claim="regimen: ondansetron");
    b_levo = Belief(claim="regimen: levofloxacin");
    root ++> b_onda;
    root ++> b_levo;
    b_onda +>:About:+> onda;
    b_onda +>:DerivedFrom:+> u_onda;
    b_levo +>:About:+> levo;
    b_levo +>:DerivedFrom:+> u_levo;

    r = root spawn Recall(anchors=[t + "ondansetron"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 1, f"expected exactly one Concern, got {len(v.concerns)}";
    con = v.concerns[0];
    assert con.kind == "additive_toxicity";
    assert con.anchor == t + "qt_prolongation", "the concern is ABOUT the shared symptom";
    assert con.action == "ask", "CONTRACTS §3 ceiling — S6 reserves escalate for rd_emergency";

    # "Both prescriber roles and both dates in its evidence" — they ride on these two Utterances,
    # and the ORDER is load-bearing: pg_slots reads {role_a}/{at_a} off utts[0] and {role_b}/{at_b}
    # off utts[1], so evidence[0] must be the earlier prescription for the row to read forward.
    assert len(con.evidence) == 2, f"expected two Utterances, got {len(con.evidence)}";
    assert con.evidence[0] == jid(u_onda), "evidence[0] is the EARLIER prescription (Feb 10)";
    assert con.evidence[1] == jid(u_levo), "evidence[1] is the later one (May 3)";

    # Resolved the way `pg_cites` will resolve them, so the acceptance criterion is checked
    # literally and not by proxy: two DIFFERENT prescribers, two DIFFERENT dates.
    e0 = jobj(con.evidence[0]);
    e1 = jobj(con.evidence[1]);
    assert e0.role == "oncologist" and e0.at == "2026-02-10", "prescriber A and date A";
    assert e1.role == "pharmacist" and e1.at == "2026-05-03", "prescriber B and date B";

    # The convergence begins when the SECOND drug lands. Dating this to February would claim the
    # patient had been at risk for three months when they had not been.
    assert con.since == "2026-05-03", "since is the LATER regimen date, not the earlier";

    # No constraint anywhere in this fixture: the triangle is found from vocabulary structure
    # alone, which is the point. Nothing here would ever appear in a top-k retrieval.
    assert len(v.violations) == 0;
    assert v.allowed;
}


# Acceptance check 4. The patient could have asked about either drug; the triangle is one fact.
test "the same triangle reached from the other arm is the same single concern" {
    t = "m1_";
    r = root spawn Recall(anchors=[t + "levofloxacin"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 1, f"reached from levofloxacin: expected 1, got {len(v.concerns)}";
    con = v.concerns[0];
    assert con.kind == "additive_toxicity";
    assert con.anchor == t + "qt_prolongation";
    # Identical, not mirrored. The pair is ordered by regimen date, not by arrival direction.
    assert con.evidence[0] == jid([root -->[?:Utterance, at == "2026-02-10"]][0]);
    assert con.since == "2026-05-03";
}


# Both arms in ONE spawn — the case where the walker really could emit twice. `rd_seen_anchors`
# processes the shared symptom once and `rd_seen_pairs` is the second guard.
test "both arms queried at once still yields one concern" {
    t = "m1_";
    r = root spawn Recall(anchors=[t + "ondansetron", t + "levofloxacin"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 1, f"expected 1 concern from both arms, got {len(v.concerns)}";
}


# Discontinuation is `Supersedes` and nothing else (graph.jac). A third QT drug the patient has
# STOPPED must not pair with either of the other two — otherwise the page grows a row every time
# a prescription ends, which is the opposite of what stopping a drug should do.
test "a discontinued drug is not active regimen and forms no pair" {
    t = "m1_";
    found = [root -->[?:Anchor, key == t + "QT-prolonging"]];
    assert len(found) == 1, "fixture precondition: the m1_ class anchor is still there";

    sota = Anchor(key=t + "sotalol", kind="ingredient");
    root ++> sota;
    sota +>:Member(via="class_member"):+> found[0];

    u_old = Utterance(text="Sotalol 80mg twice daily.", at="2026-01-04", role="oncologist");
    u_new = Utterance(text="Stop the sotalol.", at="2026-04-01", role="oncologist");
    root ++> u_old;
    root ++> u_new;
    b_old = Belief(claim="regimen: sotalol");
    b_stop = Belief(claim="sotalol discontinued");
    root ++> b_old;
    root ++> b_stop;
    b_old +>:About:+> sota;
    b_old +>:DerivedFrom:+> u_old;
    b_stop +>:DerivedFrom:+> u_new;
    b_stop +>:Supersedes:+> b_old;

    r = root spawn Recall(anchors=[t + "ondansetron"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 1,
        f"a stopped drug must add no pair — expected 1 concern, got {len(v.concerns)}";
}


# The `isinstance` filter in `rd_regimen_beliefs`, which the spike showed is load-bearing:
# `[a <-:About:<-]` returns `Preference` and `Constraint` instances too. A drug the patient merely
# has an opinion about, or one an instruction names, is not a drug they are taking.
test "a Preference or Constraint About an anchor does not make it active regimen" {
    t = "m1_";
    found = [root -->[?:Anchor, key == t + "QT-prolonging"]];
    amio = Anchor(key=t + "amiodarone", kind="ingredient");
    root ++> amio;
    amio +>:Member(via="class_member"):+> found[0];

    u = Utterance(text="I'd rather not go back on amiodarone.", at="2026-03-02", role="patient");
    root ++> u;
    p = Preference(claim="prefers to avoid amiodarone", polarity=-1.0);
    c = Constraint(claim="amiodarone is contraindicated here", hard=False);
    root ++> p;
    root ++> c;
    p +>:About:+> amio;
    p +>:DerivedFrom:+> u;
    c +>:About:+> amio;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "ondansetron"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 1,
        f"an opinion is not a prescription — expected 1 concern, got {len(v.concerns)}";
}


# One active drug on a symptom is not a convergence. Guards the obvious over-fire: every regimen
# drug has SOME toxicity, and a page that says so about each one in isolation is noise.
test "a single active drug on a symptom raises nothing" {
    t = "m1b_";
    drug = Anchor(key=t + "capecitabine", kind="ingredient");
    cls = Anchor(key=t + "fluoropyrimidine", kind="class");
    sym = Anchor(key=t + "diarrhea", kind="symptom");
    root ++> drug;
    root ++> cls;
    root ++> sym;
    drug +>:Member(via="class_member"):+> cls;
    cls +>:Member(via="toxicity_of"):+> sym;

    u = Utterance(text="Capecitabine 1250mg twice daily.", at="2026-02-01", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: capecitabine");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "capecitabine"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 0, "one drug on a symptom is not a shared toxicity";
}


# ------------------------------------------------------------------------------------------
# Interaction — table stakes, built and never led with (ARCHITECTURE §7).
#
# FIXTURE ASSUMPTION, flagged to @bryanph4m on #10: `write.jac` says the INTERACTION_TABLE pair
# (CYP3A4-inducer, CYP3A4-substrate) becomes a `Constraint` in #4/#7 "once a patient's regimen
# actually contains both sides", and that wiring does not exist yet. This seeds the natural shape
# — one Constraint that `Excludes` the inducer (carrying `because`) and `Governs` the substrate.
# The rule scans both edge types from both sides, so a different wiring still fires; only this
# fixture would need a line changed.
# ------------------------------------------------------------------------------------------

# Acceptance check 3. "My neighbor gave me St John's Wort."
test "a new substance entering the regimen raises an interaction against the drug already on it" {
    t = "m1i_";
    sjw = Anchor(key=t + "st_johns_wort", kind="ingredient");
    ind = Anchor(key=t + "CYP3A4-inducer", kind="class");
    ima = Anchor(key=t + "imatinib", kind="ingredient");
    sub = Anchor(key=t + "CYP3A4-substrate", kind="class");
    root ++> sjw;
    root ++> ind;
    root ++> ima;
    root ++> sub;
    sjw +>:Member(via="class_member"):+> ind;
    ima +>:Member(via="class_member"):+> sub;

    u_lbl = Utterance(
        text="Avoid St John's Wort and other CYP3A4 inducers while on imatinib.",
        at="2026-01-05",
        role="label"
    );
    root ++> u_lbl;
    c = Constraint(claim="no CYP3A4 inducers on imatinib", hard=True);
    root ++> c;
    c +>:Excludes(
        because="CYP3A4 induction lowers substrate plasma levels, risking loss of efficacy"
    ):+> ind;
    c +>:Governs:+> sub;
    c +>:DerivedFrom:+> u_lbl;

    u_ima = Utterance(text="Imatinib 400mg daily.", at="2026-01-05", role="oncologist");
    u_sjw = Utterance(
        text="My neighbor gave me St John's Wort for the fatigue.",
        at="2026-06-18",
        role="patient"
    );
    root ++> u_ima;
    root ++> u_sjw;
    b_ima = Belief(claim="regimen: imatinib");
    b_sjw = Belief(claim="regimen: st_johns_wort");
    root ++> b_ima;
    root ++> b_sjw;
    b_ima +>:About:+> ima;
    b_ima +>:DerivedFrom:+> u_ima;
    b_sjw +>:About:+> sjw;
    b_sjw +>:DerivedFrom:+> u_sjw;

    r = root spawn Recall(anchors=[t + "st_johns_wort"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 1, f"expected one interaction Concern, got {len(v.concerns)}";
    con = v.concerns[0];
    assert con.kind == "interaction";
    assert con.action == "ask";
    # `{new}` is the LATER-prescribed side. Structural, not temporal — Recall has no `today`.
    assert con.anchor == t + "st_johns_wort", "the concern is about the substance just added";
    assert con.since == "2026-06-18";
    # evidence[0] is the new substance's OWN utterance: the template says "{new} was added
    # ({role}, {at})" and pg_slots reads both off utts[0].
    assert con.evidence[0] == jid(u_sjw), "evidence[0] must be the new substance's utterance";
    assert con.evidence[1] == jid(u_lbl), "the label citation follows";

    # Channel B agrees independently: the same constraint is a hard hit, so the verdict blocks.
    # Two representations of one fact — the Violation is the allowed/blocked answer, the Concern
    # is the page row.
    assert not v.allowed, "a hard constraint on the path still blocks (CONTRACTS §3)";
    assert len(v.violations) == 1;
}


# Acceptance check 4 for the other half. Asking about the drug you were already on finds the same
# interaction — and names St John's Wort as the new one, not imatinib. This is also the test that
# pins `rd_touching_constraints` scanning `Governs`: from imatinib the only way to reach the
# constraint is the Governs edge onto CYP3A4-substrate, and an Excludes-only scan finds nothing.
test "the same interaction reached from the regimen drug names the same new substance" {
    t = "m1i_";
    r = root spawn Recall(anchors=[t + "imatinib"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 1, f"reached from imatinib: expected 1, got {len(v.concerns)}";
    con = v.concerns[0];
    assert con.kind == "interaction";
    assert con.anchor == t + "st_johns_wort",
        "{new} is decided from the two regimen dates, not from which side the walker arrived on";
    assert con.since == "2026-06-18";
}


# A curated pair with only ONE side on board is not an interaction. The other half of the
# vocabulary is always present; what makes it a finding is that the patient is taking both.
test "a curated pair with only one side in the regimen raises nothing" {
    t = "m1j_";
    warf = Anchor(key=t + "warfarin", kind="ingredient");
    napr = Anchor(key=t + "naproxen", kind="ingredient");
    root ++> warf;
    root ++> napr;

    u_lbl = Utterance(
        text="NSAIDs impair platelet function on top of anticoagulation.",
        at="2026-01-01",
        role="label"
    );
    root ++> u_lbl;
    c = Constraint(claim="no NSAIDs with warfarin", hard=True);
    root ++> c;
    c +>:Excludes(because="additive bleeding risk"):+> napr;
    c +>:Governs:+> warf;
    c +>:DerivedFrom:+> u_lbl;

    # Only warfarin is actually prescribed. Naproxen exists in the vocabulary and nowhere else.
    u_w = Utterance(text="Warfarin 5mg daily.", at="2026-02-14", role="oncologist");
    root ++> u_w;
    b_w = Belief(claim="regimen: warfarin");
    root ++> b_w;
    b_w +>:About:+> warf;
    b_w +>:DerivedFrom:+> u_w;

    r = root spawn Recall(anchors=[t + "warfarin"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 0, "a pair the patient is not taking both sides of is not a finding";
    # Channel B still returns the constraint — unscored and exhaustive, exactly as A2 requires.
    assert len(v.violations) == 1, "channel B is unaffected by mechanism 1 finding nothing";
}


# ==========================================================================================
# #15 — Recall channel A: beam, budget, lazy decay, reinforcement. MUST STAY ABOVE THE #9
# BLOCK, same reason as the mechanism-1 tests above: once an emergency fires, `rd_start` (and
# every other Root-entry ability below it in declaration order) never runs, so channel A's own
# Root-entry work (`rd_now_cached`) would never execute either.
# ==========================================================================================

test "channel A budget limits soft collection to at most budget beliefs" {
    t = "ca1_";
    a = Anchor(key=t + "docusate", kind="ingredient");
    root ++> a;
    b1 = Belief(claim="regimen: docusate 1");
    b2 = Belief(claim="regimen: docusate 2");
    b3 = Belief(claim="regimen: docusate 3");
    root ++> b1;
    root ++> b2;
    root ++> b3;
    b1 +>:About:+> a;
    b2 +>:About:+> a;
    b3 +>:About:+> a;

    r = root spawn Recall(anchors=[t + "docusate"], budget=2, beam=5);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.soft) <= 2, f"budget=2 must deliver at most 2 beliefs, got {len(v.soft)}";
}


test "a superseded belief is skipped by channel A" {
    t = "ca2_";
    a = Anchor(key=t + "docusate", kind="ingredient");
    root ++> a;
    old = Belief(claim="regimen: docusate old");
    new = Belief(claim="regimen: docusate new");
    root ++> old;
    root ++> new;
    old +>:About:+> a;
    new +>:About:+> a;
    new +>:Supersedes:+> old;

    r = root spawn Recall(anchors=[t + "docusate"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert "regimen: docusate old" not in v.soft, "a superseded belief must not be collected";
    assert "regimen: docusate new" in v.soft, "the live belief must be collected";
}


test "channel A beam limits fanout at the Anchor step regardless of budget" {
    t = "ca5_";
    a = Anchor(key=t + "docusate", kind="ingredient");
    root ++> a;
    # Five candidates, distinct strengths so ranking is deterministic.
    b1 = Belief(claim=t + "b1", strength=5.0);
    b2 = Belief(claim=t + "b2", strength=4.0);
    b3 = Belief(claim=t + "b3", strength=3.0);
    b4 = Belief(claim=t + "b4", strength=2.0);
    b5 = Belief(claim=t + "b5", strength=1.0);
    for b in [b1, b2, b3, b4, b5] {
        root ++> b;
        b +>:About:+> a;
    }

    r = root spawn Recall(anchors=[t + "docusate"], budget=10, beam=2);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.soft) == 2, f"beam=2 must cap Anchor-step fanout at 2 regardless of budget=10, got {len(v.soft)}";
    assert (t + "b1") in v.soft and (t + "b2") in v.soft, "the two highest-strength candidates must be chosen";
}


# `Relates` is defined in graph.jac but nothing in write.jac creates one yet (grepped, confirmed
# empty) -- Consolidate's deferred Shortcut/reinforcement work (#57) is the natural home for that.
# This is therefore fixture-only coverage of the reinforcement acceptance line, not an end-to-end
# proof against real seed data -- flagged rather than implied.
test "an edge traversed twice by channel A has a higher weight than traversed once" {
    t = "ca3_";
    a = Anchor(key=t + "docusate", kind="ingredient");
    root ++> a;
    b1 = Belief(claim=t + "b1");
    b2 = Belief(claim=t + "b2");
    root ++> b1;
    root ++> b2;
    b1 +>:About:+> a;
    b1 +>:Relates(weight=1.0):+> b2;
    # `(a +>:Edge(...):+> b)[0]` returns the DESTINATION NODE, not the edge -- a real gotcha,
    # same family as `++>`'s. The `[edge ...]` query is the only way to get the edge reference.
    rel: Relates = [edge b1 ->:Relates:-> b2][0];

    initial_weight: float = rel.weight;

    root spawn Recall(anchors=[t + "docusate"], budget=5, beam=5);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    after_one: float = rel.weight;
    assert after_one > initial_weight, "one traversal must reinforce the Relates edge";

    root spawn Recall(anchors=[t + "docusate"], budget=5, beam=5);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    after_two: float = rel.weight;
    assert after_two > after_one, "a second traversal must reinforce it further";
}


# Acceptance line 5, made into an actual test rather than a code-review claim: `rd_channel_a_on`
# gates every channel-A ability, so this really does compare channel B running with and without
# channel A present, not just two runs that happen to agree.
test "channel B results are byte-identical with channel A enabled and disabled" {
    t = "ca4_";
    a = Anchor(key=t + "warfarin", kind="ingredient");
    root ++> a;
    u = Utterance(text="No warfarin with this combination.", at="2026-05-02", role="pharmacist");
    root ++> u;
    c = Constraint(claim="no warfarin on this regimen", hard=True);
    root ++> c;
    c +>:Governs:+> a;
    c +>:DerivedFrom:+> u;

    b = Belief(claim=t + "regimen: warfarin");
    root ++> b;
    b +>:About:+> a;

    r_on = root spawn Recall(anchors=[t + "warfarin"], rd_channel_a_on=True);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v_on = r_on.reports[0];

    r_off = root spawn Recall(anchors=[t + "warfarin"], rd_channel_a_on=False);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v_off = r_off.reports[0];

    assert len(v_on.violations) == len(v_off.violations), "violation count must match";
    for i in range(len(v_on.violations)) {
        assert v_on.violations[i].claim == v_off.violations[i].claim;
        assert v_on.violations[i].because == v_off.violations[i].because;
        assert v_on.violations[i].source == v_off.violations[i].source;
        assert v_on.violations[i].at == v_off.violations[i].at;
    }
    assert len(v_on.concerns) == len(v_off.concerns), "concern count must match";
    assert v_on.allowed == v_off.allowed, "allowed must match";

    # And channel A actually did something different when on -- proving the comparison above
    # isn't vacuously true because channel A never fired either way.
    assert len(v_on.soft) > 0, "precondition: channel A collected something when on";
    assert len(v_off.soft) == 0, "precondition: channel A collected nothing when off";
}


# ==========================================================================================
# #9 — the emergency bypass. EVERYTHING BELOW IS ORDER-SENSITIVE; see note 3 in the header.
# Non-firing fixtures first (e1–e5), firing fixtures last (e6–e8).
# ==========================================================================================

# Below the parsed threshold, an emergency `Constraint` is just an ordinary channel B hard
# constraint: no bypass, and the normal read path still returns it.
test "an emergency criterion below its threshold does not fire, and channel B runs" {
    t = "e1_";
    fever = Anchor(key=t + "fever", kind="symptom");
    root ++> fever;
    u = Utterance(
        text="Call me right away if your temperature goes over 100.4 during the nadir.",
        at="2026-03-01",
        role="oncologist"
    );
    root ++> u;
    c = Constraint(
        claim="fever over 100.4 during the nadir is an emergency",
        hard=True, emergency=True,
        threshold_level=100.4, threshold_days=0, threshold_metric="temperature"
    );
    root ++> c;
    c +>:Governs:+> fever;
    c +>:DerivedFrom:+> u;
    o = Observation(metric="temperature", value=99.1, at="2026-03-14");
    root ++> o;
    o +>:Reports:+> fever;

    r = root spawn Recall(anchors=[t + "fever"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 0, "99.1 is below 100.4 — the bypass must not fire";
    assert len(v.violations) == 1, "channel B must still run and return the constraint";
    assert not v.allowed, "it is still a hard constraint";
}


# THE REGRESSION THE `o.value <= 0.0` GUARD EXISTS FOR. An emergency criterion with no parsed
# numeric threshold (`threshold_level` 0.0, `threshold_metric` "") would otherwise be satisfied by
# EVERY observation on its anchor — including a value of 0, which on both pinned scales means the
# symptom is ABSENT. Without the guard, logging "no rash today" raises a full-screen
# "contact your care team now".
test "an observation of zero never fires an emergency criterion" {
    t = "e2_";
    rash = Anchor(key=t + "rash", kind="symptom");
    root ++> rash;
    u = Utterance(text="Call us if you get a rash.", at="2026-03-02", role="oncologist");
    root ++> u;
    c = Constraint(claim="a rash is a reason to call", hard=True, emergency=True);
    root ++> c;
    c +>:Governs:+> rash;
    c +>:DerivedFrom:+> u;
    # the patient checking in to say they are FINE
    o = Observation(metric="rash", value=0.0, at="2026-03-14");
    root ++> o;
    o +>:Reports:+> rash;

    r = root spawn Recall(anchors=[t + "rash"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 0, "reporting the ABSENCE of a symptom must not raise the alarm";
    assert len(v.violations) == 1, "channel B runs normally";
}


# A2's one carve-out, and it matters most here: a retracted emergency instruction that keeps firing
# is an interstitial nobody can turn off.
test "a superseded emergency constraint does not fire" {
    t = "e3_";
    nausea = Anchor(key=t + "nausea", kind="symptom");
    root ++> nausea;
    u = Utterance(text="Call if the nausea hits a 7.", at="2026-01-05", role="oncologist");
    root ++> u;
    c = Constraint(
        claim="nausea at 7 or above is a reason to call", hard=True, emergency=True,
        threshold_level=7.0, threshold_metric="nausea"
    );
    root ++> c;
    c +>:Governs:+> nausea;
    c +>:DerivedFrom:+> u;

    repl = Belief(claim="we have you on a standing antiemetic now; no need to call");
    root ++> repl;
    repl +>:Supersedes:+> c;

    o = Observation(metric="nausea", value=8.0, at="2026-03-14");
    root ++> o;
    o +>:Reports:+> nausea;

    r = root spawn Recall(anchors=[t + "nausea"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 0, "Supersedes kills an emergency constraint like any other";
    assert len(v.violations) == 0, "and channel B drops it too";
}


# `threshold_days` counts DISTINCT DATES, not observations. One date does not satisfy D = 2 — and
# three readings on that one afternoon still do not.
test "threshold_days requires that many distinct dates" {
    t = "e4_";
    pain = Anchor(key=t + "mouth-pain", kind="symptom");
    root ++> pain;
    u = Utterance(text="Call if it stays at 6 or worse for two days.", at="2026-02-10", role="oncologist");
    root ++> u;
    c = Constraint(
        claim="mouth pain at 6+ for two days is a reason to call", hard=True, emergency=True,
        threshold_level=6.0, threshold_days=2, threshold_metric="mouth_pain"
    );
    root ++> c;
    c +>:Governs:+> pain;
    c +>:DerivedFrom:+> u;

    for val in [7.0, 8.0, 6.5] {
        o = Observation(metric="mouth_pain", value=val, at="2026-03-14");
        root ++> o;
        o +>:Reports:+> pain;
    }

    r = root spawn Recall(anchors=[t + "mouth-pain"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert len(v.concerns) == 0, "three readings on one day is one day, not two";
}


# S2 again, at the worst possible stakes: no `DerivedFrom` means `pg_row` drops the row, so the
# interstitial would never render. The bypass therefore does NOT disengage — returning a blocked
# verdict with nothing in it is strictly worse for the patient than falling through to channel B.
test "an uncitable emergency constraint blocks, emits no Concern, and falls through to channel B" {
    t = "e5_";
    bleed = Anchor(key=t + "bleeding", kind="symptom");
    root ++> bleed;

    bad = Constraint(claim="any bleeding is a reason to call", hard=True, emergency=True);
    root ++> bad;
    bad +>:Governs:+> bleed;
    # deliberately no DerivedFrom edge

    o = Observation(metric="bleeding", value=3.0, at="2026-03-14");
    root ++> o;
    o +>:Reports:+> bleed;

    # an ordinary, properly cited constraint on the same anchor — its Violation is the proof that
    # channel B ran rather than being pre-empted
    u2 = Utterance(text="Let us know about any bruising.", at="2026-02-20", role="oncologist");
    root ++> u2;
    ok = Constraint(claim="report bruising at the next visit", hard=False);
    root ++> ok;
    ok +>:Governs:+> bleed;
    ok +>:DerivedFrom:+> u2;

    r = root spawn Recall(anchors=[t + "bleeding"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) == 0, "a Concern `pg_row` would drop must not be fabricated";
    assert not v.allowed, "the criterion was met — the blocking answer survives";
    assert len(v.violations) == 1, "no disengage: channel B must still have run";

    noted = False;
    for n in r.rd_notes {
        if "uncitable emergency constraint" in n {
            noted = True;
        }
    }
    assert noted, "an unrenderable emergency must be recorded, not dropped in silence";
}


# ==========================================================================================
# ACCEPTANCE (#9). From here down an emergency FIRES, so every later spawn in this file takes
# the bypass. Assertions below are scoped to their own anchor rather than to exact counts.
# ==========================================================================================

test "a febrile neutropenia crossing produces one escalate Concern, cited and reported once" {
    t = "e6_";
    fever = Anchor(key=t + "fever", kind="symptom");
    root ++> fever;
    u = Utterance(
        text="Call me right away if your temperature goes over 100.4 during the nadir.",
        at="2026-03-01",
        role="oncologist"
    );
    root ++> u;
    c = Constraint(
        claim="fever over 100.4 during the nadir is an emergency",
        hard=True, emergency=True,
        threshold_level=100.4, threshold_days=0, threshold_metric="temperature"
    );
    root ++> c;
    c +>:Governs:+> fever;
    c +>:DerivedFrom:+> u;
    o = Observation(metric="temperature", value=101.2, at="2026-03-14");
    root ++> o;
    o +>:Reports:+> fever;

    r = root spawn Recall(anchors=[t + "fever"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds

    # `rd_finish` never fires after `disengage`, so this also proves the escalate path does not
    # double-report.
    assert len(r.reports) == 1, "exactly one report on the escalate path";
    v = r.reports[0];

    assert len(v.concerns) == 1, f"expected one escalate Concern, got {len(v.concerns)}";
    con = v.concerns[0];
    assert con.kind == "emergency", "CONTRACTS §3 pinned kind";
    assert con.action == "escalate", "#9 contract line";
    assert con.anchor == t + "fever";
    assert con.since == "2026-03-14", "since is the earliest qualifying observation date";
    assert not v.allowed, "a hard emergency constraint blocks";

    # Evidence ORDER is load-bearing: `pg_slots` fills {criterion} from utts[0].text and {source}
    # from utts[0].role, and those are the only two slots the `emergency` template has. The
    # Utterance must come first or the interstitial renders the wrong headline.
    assert len(con.evidence) == 2, "one Utterance citation plus one Observation";
    assert con.evidence[0] == jid(u), "the Utterance must be evidence[0]";
    assert con.evidence[1] == jid(o), "the crossing Observation follows it";
}


# S5, AND THE TEST THAT PINS ABILITY DECLARATION ORDER. `rd_emergency` sits above `rd_start` in
# `read.jac`; move it below and the bypass stops pre-empting the read path — silently, with
# `jac check` clean and every other test in this file still green. This is the only thing that
# catches that. Do not delete it.
test "channel B does not run on the escalate path" {
    t = "e7_";
    # a perfectly ordinary hard constraint, citable, sitting on the anchor being queried.
    # Channel B would certainly return it — if channel B ran at all.
    a = Anchor(key=t + "warfarin", kind="ingredient");
    root ++> a;
    u = Utterance(text="No warfarin with this combination.", at="2026-05-02", role="pharmacist");
    root ++> u;
    c = Constraint(claim="no warfarin on this regimen", hard=True);
    root ++> c;
    c +>:Governs:+> a;
    c +>:DerivedFrom:+> u;

    r = root spawn Recall(anchors=[t + "warfarin"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    assert len(v.concerns) > 0, "precondition: the e6_ emergency is still live and must fire";
    assert len(v.violations) == 0,
        "S5: an escalate must pre-empt channel B entirely — a violation here means `rd_emergency` "
        "no longer runs first";
    assert not v.allowed;
}


# The other half of e4_: a second qualifying DATE satisfies D = 2 and the criterion fires.
test "a second qualifying date satisfies threshold_days and fires" {
    t = "e4_";
    found: list[Anchor] = [root -->[?:Anchor, key == t + "mouth-pain"]];
    assert len(found) == 1, "fixture precondition: the e4_ anchor is still there";

    o = Observation(metric="mouth_pain", value=6.0, at="2026-03-15");
    root ++> o;
    o +>:Reports:+> found[0];

    r = root spawn Recall(anchors=[t + "mouth-pain"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    hit = False;
    for con in v.concerns {
        if con.anchor == t + "mouth-pain" {
            hit = True;
            assert con.action == "escalate";
            assert con.since == "2026-03-14", "since is the EARLIEST qualifying date, not the last";
        }
    }
    assert hit, "two distinct dates at 6.0+ satisfies threshold_days = 2";
}
