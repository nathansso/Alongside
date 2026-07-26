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
    Anchor, Belief, Concern, Constraint, Observation, Preference, Utterance,
    About, Conflicts, DerivedFrom, Governs, Excludes, Member, Reports, Supersedes
}


# 4. EXACT `len(v.concerns)` ASSERTIONS DIED WITH #11, and this is why.
#
# Mechanism 2 fires on ABSENCE, and the set of things absent from a fixture is always larger than
# the set of things present in it. A regimen drug with no `Observation` is a real `adherence_gap`
# even in a fixture built to test the QT triangle; a symptom nothing attributes is a real
# `unattributed_symptom` even in one built to test an emergency threshold. Both are correct
# findings and both would make a total count meaningless.
#
# So every count below is KIND-SPECIFIC. That is sharper than the totals it replaced — a test that
# said "one concern" now says "one `additive_toxicity` concern" — but it does mean a new mechanism
# can no longer break these tests by firing where they were not looking. The suite compensates
# with `no mechanism ever emits above its ceiling`, which is a total assertion over every concern
# any fixture in this file produces.
def rd_kind_count(cons: list[Concern], kind: str) -> int {
    hits: list[str] = [];
    for c in cons {
        if c.kind == kind {
            hits.append(c.anchor);
        }
    }
    return len(hits);
}


# The one concern of a given kind on a given anchor, or None.
def rd_pick(cons: list[Concern], kind: str, anchor: str) -> Concern | None {
    for c in cons {
        if (c.kind == kind) and (c.anchor == anchor) {
            return c;
        }
    }
    return None;
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

    assert rd_kind_count(v.concerns, "additive_toxicity") == 1,
        f"expected exactly one additive_toxicity Concern, got {v.concerns}";
    con = rd_pick(v.concerns, "additive_toxicity", t + "qt_prolongation");
    assert con is not None, "the concern is ABOUT the shared symptom";
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

    assert rd_kind_count(v.concerns, "additive_toxicity") == 1,
        f"reached from levofloxacin: expected 1, got {v.concerns}";
    con = rd_pick(v.concerns, "additive_toxicity", t + "qt_prolongation");
    assert con is not None;
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
    assert rd_kind_count(v.concerns, "additive_toxicity") == 1,
        f"expected 1 additive_toxicity from both arms, got {v.concerns}";
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
    assert rd_kind_count(v.concerns, "additive_toxicity") == 1,
        f"a stopped drug must add no pair — got {v.concerns}";
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
    assert rd_kind_count(v.concerns, "additive_toxicity") == 1,
        f"an opinion is not a prescription — got {v.concerns}";
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
    assert rd_kind_count(v.concerns, "additive_toxicity") == 0,
        "one drug on a symptom is not a shared toxicity";
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

    assert rd_kind_count(v.concerns, "interaction") == 1,
        f"expected one interaction Concern, got {v.concerns}";
    con = rd_pick(v.concerns, "interaction", t + "st_johns_wort");
    assert con is not None;
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

    assert rd_kind_count(v.concerns, "interaction") == 1,
        f"reached from imatinib: expected 1, got {v.concerns}";
    con = rd_pick(v.concerns, "interaction", t + "st_johns_wort");
    assert con is not None,
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
    assert rd_kind_count(v.concerns, "interaction") == 0,
        "a pair the patient is not taking both sides of is not a finding";
    # Channel B still returns the constraint — unscored and exhaustive, exactly as A2 requires.
    assert len(v.violations) == 1, "channel B is unaffected by mechanism 1 finding nothing";
}


# ==========================================================================================
# #12 — mechanism 3, `persistence`. ALSO ABOVE THE #9 BLOCK, for the same reason as #10.
#
# The non-emergency half of "a stated threshold was crossed". Shares `rd_threshold_dates` with
# `rd_emergency`, so these tests and the `e*_` ones are pinning one piece of arithmetic from two
# sides — an emergency at `escalate`, an ordinary instruction at `ask`.
# ==========================================================================================

# ACCEPTANCE (#12). Note the fixture sets `threshold_days` explicitly: `wr_write_instruction`
# hardcodes it to 0 (write.jac:493), so on real parsed data this degrades to "crossed at least
# once". Raised on #4 — the rule is right, the parser does not feed it yet.
test "a non-emergency threshold crossed for D days produces persistence at ask" {
    t = "p1_";
    sym = Anchor(key=t + "mouth-pain", kind="symptom");
    root ++> sym;

    u = Utterance(
        text="If the mouth pain stays at 4 or higher for a couple of days, tell me at your visit.",
        at="2026-02-10",
        role="oncologist"
    );
    root ++> u;
    c = Constraint(
        claim="mouth pain at 4+ for two days is worth raising",
        hard=True,
        emergency=False,
        threshold_level=4.0,
        threshold_days=2,
        threshold_metric="mouth_pain"
    );
    root ++> c;
    c +>:Governs:+> sym;
    c +>:DerivedFrom:+> u;

    for d in ["2026-03-01", "2026-03-02"] {
        o = Observation(metric="mouth_pain", value=5.0, at=d);
        root ++> o;
        o +>:Reports:+> sym;
    }

    r = root spawn Recall(anchors=[t + "mouth-pain"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    hit = None;
    for con in v.concerns {
        if con.kind == "persistence" and con.anchor == t + "mouth-pain" { hit = con; }
    }
    assert hit is not None, f"expected a persistence Concern, got {v.concerns}";
    assert hit.action == "ask", "CONTRACTS §3 ceiling — never escalate, that is S6's carve-out";
    assert hit.since == "2026-03-01", "since is the EARLIEST qualifying date — it is a duration";
    # The constraint's citation leads so `{threshold_source}` resolves; crossings follow so
    # `{days}` and `{level}` do.
    assert hit.evidence[0] == jid(u), "evidence[0] is the instruction that set the threshold";
    assert len(hit.evidence) == 3, f"one citation + two crossings, got {len(hit.evidence)}";
}


# One criterion, one severity. An emergency constraint is `rd_emergency`'s alone — emitting it here
# too would put the same sentence on the page twice, once as a full-screen interstitial and once as
# an ordinary row.
test "an emergency constraint does not also emit persistence" {
    t = "p2_";
    sym = Anchor(key=t + "fever", kind="symptom");
    root ++> sym;
    u = Utterance(text="Call if your temperature goes over 100.4.", at="2026-02-01", role="oncologist");
    root ++> u;
    c = Constraint(
        claim="fever over 100.4 is a reason to call", hard=True, emergency=True,
        threshold_level=100.4, threshold_days=0, threshold_metric="fever"
    );
    root ++> c;
    c +>:Governs:+> sym;
    c +>:DerivedFrom:+> u;

    # Deliberately BELOW the threshold, so `rd_emergency` does not fire and disengage — this test
    # has to reach the persistence block to prove that the block skips it.
    o = Observation(metric="fever", value=99.1, at="2026-03-01");
    root ++> o;
    o +>:Reports:+> sym;

    r = root spawn Recall(anchors=[t + "fever"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    for con in v.concerns {
        assert con.kind != "persistence", "an emergency criterion belongs to rd_emergency alone";
    }
}


# A constraint with no parsed threshold is an ordinary channel B hit and nothing more. Without
# this guard every plain instruction becomes a persistence row the moment any observation exists.
test "a constraint with no parsed threshold emits no persistence" {
    t = "p3_";
    sym = Anchor(key=t + "nausea", kind="symptom");
    root ++> sym;
    u = Utterance(text="Let me know if the nausea gets worse.", at="2026-02-05", role="oncologist");
    root ++> u;
    c = Constraint(claim="report worsening nausea", hard=False, emergency=False);
    root ++> c;
    c +>:Governs:+> sym;
    c +>:DerivedFrom:+> u;

    o = Observation(metric="nausea", value=7.0, at="2026-03-05");
    root ++> o;
    o +>:Reports:+> sym;

    r = root spawn Recall(anchors=[t + "nausea"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    for con in v.concerns {
        assert con.kind != "persistence", "no L and no metric is not a threshold";
    }
    assert len(v.violations) == 1, "channel B still returns it, unscored — A2";
}


# ==========================================================================================
# #11 — mechanism 2, the absence class. ABOVE THE #9 BLOCK, same reason as #10 and #12.
# ==========================================================================================

# ACCEPTANCE (#11). A symptom the patient keeps reporting that NOTHING on the current list
# explains. New and unexplained is MORE worth asking about, not less — the row is emitted, never
# suppressed for being unattributable.
test "a symptom no active drug attributes raises unattributed_symptom at mention" {
    t = "a1_";
    sym = Anchor(key=t + "diarrhea", kind="symptom");
    root ++> sym;
    # No Member(toxicity_of) into this anchor from anywhere: the absence IS the finding.
    for d in ["2026-06-13", "2026-06-16"] {
        u = Utterance(text="Some loose stools again.", at=d, role="patient");
        root ++> u;
        o = Observation(metric="diarrhea", value=2.0, at=d);
        root ++> o;
        o +>:Reports:+> sym;
        o +>:DerivedFrom:+> u;
    }

    r = root spawn Recall(anchors=[t + "diarrhea"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "unattributed_symptom", t + "diarrhea");
    assert con is not None, f"expected unattributed_symptom, got {v.concerns}";
    assert con.action == "mention", "CONTRACTS §3 ceiling — an absence never reaches ask alone";
    assert con.since == "2026-06-13", "since is the first time they described it";
    # S2: the observations' own Utterances lead, or `pg_row` drops the row and `{count}` is 0.
    assert len(con.evidence) >= 2, f"needs citations plus observations, got {con.evidence}";
}


# The other side of the same helper. `rd_toxicity_contributors` answers mechanism 1 by being
# non-empty and mechanism 2 by being empty, so the two can never disagree about what explains what.
test "a symptom an active drug does attribute raises no unattributed_symptom" {
    t = "a2_";
    drug = Anchor(key=t + "ondansetron", kind="ingredient");
    cls = Anchor(key=t + "QT-prolonging", kind="class");
    sym = Anchor(key=t + "qt_prolongation", kind="symptom");
    root ++> drug;
    root ++> cls;
    root ++> sym;
    drug +>:Member(via="class_member"):+> cls;
    cls +>:Member(via="toxicity_of"):+> sym;

    u = Utterance(text="Ondansetron 8mg.", at="2026-02-10", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: ondansetron");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;

    uo = Utterance(text="Heart felt fluttery.", at="2026-06-01", role="patient");
    root ++> uo;
    o = Observation(metric="qt_prolongation", value=2.0, at="2026-06-01");
    root ++> o;
    o +>:Reports:+> sym;
    o +>:DerivedFrom:+> uo;

    r = root spawn Recall(anchors=[t + "qt_prolongation"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];
    assert rd_pick(v.concerns, "unattributed_symptom", t + "qt_prolongation") is None,
        "an attributed symptom is explained — that is not the absence class";
}


# The prescription that was never filled (ARCHITECTURE §7). An instruction covering this symptom
# names a drug, and there is no record of the patient ever taking it.
test "an instruction whose named drug has no adherence record raises supportive_care_gap" {
    t = "a3_";
    sym = Anchor(key=t + "constipation", kind="symptom");
    drug = Anchor(key=t + "docusate", kind="ingredient");
    root ++> sym;
    root ++> drug;

    uo = Utterance(text="Constipated again this week.", at="2026-06-05", role="patient");
    root ++> uo;
    o = Observation(metric="constipation", value=3.0, at="2026-06-05");
    root ++> o;
    o +>:Reports:+> sym;
    o +>:DerivedFrom:+> uo;

    ui = Utterance(text="Also take docusate daily for constipation prevention.",
                   at="2026-06-01", role="oncologist");
    root ++> ui;
    c = Constraint(claim="take docusate daily", hard=True);
    root ++> c;
    c +>:Governs:+> sym;
    c +>:Excludes(because="supportive care"):+> drug;
    c +>:DerivedFrom:+> ui;
    # docusate deliberately has ZERO Observations anywhere — seed element #3's shape.

    r = root spawn Recall(anchors=[t + "constipation"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "supportive_care_gap", t + "constipation");
    assert con is not None, f"expected supportive_care_gap, got {v.concerns}";
    assert con.action == "mention";
    # `{instruction}` resolves from the first authority-role citation, so it has to lead.
    assert con.evidence[0] == jid(ui), "the instruction's citation leads";
}


# ACCEPTANCE (#11). A regimen drug with no adherence record for longer than the window.
# BOTH ENDS ARE DATES IN THE GRAPH — the regimen date and the end of the record. No clock.
test "a regimen drug with no record for longer than the window raises adherence_gap" {
    t = "a4_";
    drug = Anchor(key=t + "imatinib", kind="ingredient");
    root ++> drug;
    u = Utterance(text="Imatinib 400mg daily.", at="2026-05-01", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: imatinib");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;
    # The record continues well past the regimen date, and nothing references the drug.
    tail = Utterance(text="Still feeling tired but otherwise okay.", at="2026-06-18", role="patient");
    root ++> tail;

    r = root spawn Recall(anchors=[t + "imatinib"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "adherence_gap", t + "imatinib");
    assert con is not None, f"expected adherence_gap, got {v.concerns}";
    assert con.action == "mention";
    assert con.since == "2026-05-01", "the gap starts at the last thing we knew about the drug";
}


# ACCEPTANCE (#11): the seeded 4-day gap. Tested on the helper directly, because `silence` is the
# one global kind and is wired into `Vigil` (#21), not `Recall` — see the plan on #11. A root scan
# inside `Recall` would staple "you haven't checked in for 4 days" onto every query.
test "a bounded gap in the check-in chain is found, and only for patient utterances" {
    t = "a5_";
    # A gap bracketed on both sides: 4 days with nothing between — the seed's exact shape
    # (2026-06-04 -> 2026-06-08).
    #
    # DATED IN SEPTEMBER ON PURPOSE. `silence` is the one rule that reads at ROOT rather than from
    # the queried anchor, so unlike every other test here the `a5_` prefix protects nothing: a
    # patient utterance any other fixture happens to write inside June lands *inside* the intended
    # gap and splits it. The first version of this test used June and failed for exactly that
    # reason. September is empty in this file.
    for d in ["2026-09-01", "2026-09-02", "2026-09-06"] {
        u = Utterance(text="check-in " + d, at=d, role="patient");
        root ++> u;
    }
    gaps = rd_silence_gaps(3);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    found = False;
    for g in gaps {
        if g[0] == "2026-09-02" and g[1] == "2026-09-06" { found = True; }
    }
    assert found, f"expected the 09-02 -> 09-06 gap, got {gaps}";

    # And clinician documents are not silence. Every gap returned must be between two dates that
    # are patient check-ins — a label dated in January is a document, not four months of quiet.
    checkins = rd_checkin_dates();  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    for g in gaps {
        assert g[0] in checkins and g[1] in checkins,
            f"a gap endpoint that is not a patient check-in: {g}";
    }
}


# ==========================================================================================
# #12 — the rest of mechanisms 3 and 4.
# ==========================================================================================

# S4 IS THE POINT OF THIS ONE. Trajectory is where dose concern legitimately lives, and the output
# is "worth raising at the next visit, here is the record" — never a dosing conclusion.
test "monotone worsening on a cumulative anchor raises trajectory with no dosing language" {
    t = "b1_";
    drug = Anchor(key=t + "oxaliplatin", kind="ingredient", cumulative=True);
    sym = Anchor(key=t + "peripheral_neuropathy", kind="symptom");
    root ++> drug;
    root ++> sym;
    drug +>:Member(via="toxicity_of"):+> sym;

    u = Utterance(text="Oxaliplatin every three weeks.", at="2026-01-10", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: oxaliplatin");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;

    # Three points, rising. Two would be a line, not yet a pattern.
    vals = [{"at": "2026-02-01", "v": 2.0}, {"at": "2026-03-01", "v": 4.0},
            {"at": "2026-04-01", "v": 6.0}];
    for row in vals {
        o = Observation(metric="peripheral_neuropathy", value=row["v"], at=row["at"]);
        root ++> o;
        o +>:Reports:+> sym;
    }

    r = root spawn Recall(anchors=[t + "peripheral_neuropathy"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "trajectory", t + "peripheral_neuropathy");
    assert con is not None, f"expected trajectory, got {v.concerns}";
    assert con.action == "mention", "S4/CONTRACTS §3 — trajectory never reaches ask on its own";
    assert con.since == "2026-02-01";

    # ACCEPTANCE (#12): zero dosing language. Two halves, and this annex can only reach one of
    # them — `PG_TEMPLATES` lives in `main.jac`, which an annex to `read.jac` does not see
    # (`NameError` if referenced). So:
    #
    #   HERE: the concern this rule emits carries no prose the read path invented. Every string in
    #   it is a graph-read key, a date, or a ladder rung. That is the half `read.jac` owns, and it
    #   is what S4 asks of a detection rule — report a shape, never a conclusion.
    #
    #   NOT HERE: the rendered row. `Prepare` builds it from a template in `main.jac` and the
    #   Recall->Prepare handoff is not wired (`pg_derived_concerns` is a stub). That grep belongs
    #   to the integration test in #16, against the registry, not to this file.
    banned = ["dose", "dosage", "too much", "overdose", "reduce", "stop taking", "increase"];
    emitted = (con.kind + " " + con.anchor + " " + con.since + " " + con.action).lower();
    for word in banned {
        assert word not in emitted, f"S4: dosing language '{word}' emitted by the read path";
    }
}


# A record that improves is not a trajectory. Without this the rule fires on any symptom with
# three readings, which is every symptom.
test "a non-monotone record raises no trajectory" {
    t = "b2_";
    drug = Anchor(key=t + "capecitabine", kind="ingredient", cumulative=True);
    sym = Anchor(key=t + "hand_foot", kind="symptom");
    root ++> drug;
    root ++> sym;
    drug +>:Member(via="toxicity_of"):+> sym;
    u = Utterance(text="Capecitabine 1250mg.", at="2026-01-10", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: capecitabine");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;
    for row in [{"at": "2026-02-01", "v": 5.0}, {"at": "2026-03-01", "v": 2.0},
                {"at": "2026-04-01", "v": 6.0}] {
        o = Observation(metric="hand_foot", value=row["v"], at=row["at"]);
        root ++> o;
        o +>:Reports:+> sym;
    }
    r = root spawn Recall(anchors=[t + "hand_foot"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert rd_pick(r.reports[0].concerns, "trajectory", t + "hand_foot") is None,
        "it got better in the middle — that is not monotone worsening";
}


# ACCEPTANCE (#12). Plausibly the highest-value row the system produces: missed for cost and
# missed for toxicity lead to different clinical action, and the second is what gets assumed.
# Detected structurally — no claim text is read — and the row then quotes the patient verbatim.
test "a stated reason plus a missing adherence record raises nonadherence_cause" {
    t = "b3_";
    drug = Anchor(key=t + "imatinib", kind="ingredient");
    root ++> drug;
    ur = Utterance(text="Imatinib 400mg daily.", at="2026-05-01", role="oncologist");
    root ++> ur;
    br = Belief(claim="regimen: imatinib");
    root ++> br;
    br +>:About:+> drug;
    br +>:DerivedFrom:+> ur;

    uc = Utterance(
        text="Skipped my Gleevec refill this week, it's expensive and I couldn't get to the pharmacy.",
        at="2026-06-15",
        role="patient"
    );
    root ++> uc;
    bc = Belief(claim="skipped Gleevec refill due to cost");
    root ++> bc;
    bc +>:About:+> drug;
    bc +>:DerivedFrom:+> uc;

    r = root spawn Recall(anchors=[t + "imatinib"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "nonadherence_cause", t + "imatinib");
    assert con is not None, f"expected nonadherence_cause, got {v.concerns}";
    assert con.action == "mention";
    # ACCEPTANCE: the cause string is carried into the evidence, and it leads — `pg_slots` fills
    # `{cause}` and `{at}` from the first patient-role citation.
    assert con.evidence[0] == jid(uc), "the patient's own sentence leads the evidence";
    assert con.since == "2026-06-15";
}


# Mechanism 4 reads `Conflicts` edges written by #6. `Consolidate`'s body has not landed, so
# nothing writes them on `main` yet — these fixtures write them directly. Raised on #6.
test "two clinicians' conflicting instructions raise cross_prescriber_conflict at ask" {
    t = "b4_";
    a = Anchor(key=t + "naproxen", kind="ingredient");
    root ++> a;
    u1 = Utterance(text="Avoid NSAIDs entirely while on treatment.", at="2026-03-01", role="oncologist");
    u2 = Utterance(text="Naproxen twice daily is fine for the joint pain.", at="2026-04-01", role="pharmacist");
    root ++> u1;
    root ++> u2;
    c1 = Constraint(claim="no NSAIDs during treatment", hard=True);
    c2 = Constraint(claim="naproxen twice daily is acceptable", hard=True);
    root ++> c1;
    root ++> c2;
    c1 +>:Governs:+> a;
    c2 +>:Governs:+> a;
    c1 +>:DerivedFrom:+> u1;
    c2 +>:DerivedFrom:+> u2;
    c1 +>:Conflicts(derived_at="2026-04-02"):+> c2;

    r = root spawn Recall(anchors=[t + "naproxen"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "cross_prescriber_conflict", t + "naproxen");
    assert con is not None, f"expected cross_prescriber_conflict, got {v.concerns}";
    assert con.action == "ask", "CONTRACTS §3 ceiling";
    # `{claim_a}/{role_a}` come off utts[0] and `{claim_b}/{role_b}` off utts[1], ordered by date
    # so the row reads the same whichever constraint the walker reached first.
    assert con.evidence[0] == jid(u1) and con.evidence[1] == jid(u2), "ordered by date";
    # Exactly one, not one per direction of the edge read.
    assert rd_kind_count(v.concerns, "cross_prescriber_conflict") == 1;
}


# One clinician restating themselves is not a disagreement between clinicians. Emitting it as one
# would put a fabricated conflict on the page.
test "two constraints from the same role raise no cross_prescriber_conflict" {
    t = "b5_";
    a = Anchor(key=t + "ibuprofen", kind="ingredient");
    root ++> a;
    u1 = Utterance(text="No ibuprofen.", at="2026-03-01", role="oncologist");
    u2 = Utterance(text="Actually ibuprofen is fine occasionally.", at="2026-04-01", role="oncologist");
    root ++> u1;
    root ++> u2;
    c1 = Constraint(claim="no ibuprofen", hard=True);
    c2 = Constraint(claim="occasional ibuprofen acceptable", hard=True);
    root ++> c1;
    root ++> c2;
    c1 +>:Governs:+> a;
    c2 +>:Governs:+> a;
    c1 +>:DerivedFrom:+> u1;
    c2 +>:DerivedFrom:+> u2;
    c1 +>:Conflicts(derived_at="2026-04-02"):+> c2;

    r = root spawn Recall(anchors=[t + "ibuprofen"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert rd_kind_count(r.reports[0].concerns, "cross_prescriber_conflict") == 0,
        "same prescriber twice is a revision, not a cross-prescriber conflict";
}


# ACCEPTANCE (#12): drift between a soft behaviour Belief and a hard Constraint.
test "an instruction conflicting with a patient behaviour raises instruction_drift" {
    t = "b6_";
    a = Anchor(key=t + "ondansetron", kind="ingredient");
    root ++> a;
    ui = Utterance(text="Take Zofran within 30 minutes before food.", at="2026-06-01", role="oncologist");
    ub = Utterance(text="I just take it whenever I remember.", at="2026-06-14", role="patient");
    root ++> ui;
    root ++> ub;
    c = Constraint(claim="take within 30 minutes before food", hard=True);
    beh = Belief(claim="takes it whenever they remember");
    root ++> c;
    root ++> beh;
    c +>:Governs:+> a;
    c +>:DerivedFrom:+> ui;
    beh +>:About:+> a;
    beh +>:DerivedFrom:+> ub;
    c +>:Conflicts(derived_at="2026-06-15"):+> beh;

    r = root spawn Recall(anchors=[t + "ondansetron"]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    v = r.reports[0];

    con = rd_pick(v.concerns, "instruction_drift", t + "ondansetron");
    assert con is not None, f"expected instruction_drift, got {v.concerns}";
    assert con.action == "mention", "CONTRACTS §3 ceiling";
    # `{instruction}` resolves from the first AUTHORITY citation and `{observed}` from the first
    # PATIENT one, so the evidence must carry one of each or the row says the instruction twice.
    assert con.evidence[0] == jid(ui), "the instruction (authority role) leads";
    assert con.evidence[1] == jid(ub), "the behaviour (patient role) follows";
}


# ==========================================================================================
# #13 — corroboration. A5: promotes only, never demotes.
#
# Tested against `rd_corroborate` directly. Through a fixture the case that matters most — a
# concern sitting BELOW its ceiling — is unreachable, because every mechanism in `read.jac` emits
# at its ceiling today. That makes corroboration currently inert on real data, which is the safe
# direction and is worth pinning rather than hiding.
# ==========================================================================================

# ACCEPTANCE (#13): two mechanisms on one anchor promote exactly one rung, and stop at the ceiling.
test "two mechanisms on one anchor promote exactly one rung and stop at the ceiling" {
    # `trajectory` caps at mention, `persistence` at ask. Both start at log, both share an anchor.
    cons = [
        Concern(kind="trajectory", anchor="z", evidence=[], since="2026-01-01", action="log"),
        Concern(kind="persistence", anchor="z", evidence=[], since="2026-01-01", action="log"),
    ];
    moved = rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert moved == 2, f"both should move exactly once, got {moved}";
    assert cons[0].action == "mention", "log -> mention is one rung, and mention is its ceiling";
    assert cons[1].action == "mention", "one rung only — persistence does NOT jump log -> ask";

    # Run it again: `trajectory` is now AT its ceiling and must not move; `persistence` has one
    # rung left. This is the "stop at the ceiling" half, and it is where an unguarded assignment
    # would show up.
    moved2 = rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert moved2 == 1, f"only persistence has headroom left, got {moved2}";
    assert cons[0].action == "mention", "trajectory is capped at mention and stays there";
    assert cons[1].action == "ask", "persistence reaches its ceiling and stops";

    moved3 = rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert moved3 == 0, "both at their ceilings — nothing left to promote";
    assert cons[1].action == "ask", "and nothing above it, ever";
}


# A5, as a property rather than a spot check. Every action out is at or above the action in, for
# every kind at every rung. This is the test that fails if someone replaces the guarded step with
# an unconditional assignment to a computed target.
test "corroboration never lowers an action, for any kind at any rung" {
    for kind in ["emergency", "interaction", "persistence", "trajectory", "silence",
                 "cross_prescriber_conflict", "nonadherence_cause", "unrecognized_substance"] {
        for start in RD_LADDER {  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
            cons = [
                Concern(kind=kind, anchor="y", evidence=[], since="", action=start),
                Concern(kind="adherence_gap", anchor="y", evidence=[], since="", action="log"),
            ];
            rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
            before = RD_LADDER.index(start);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
            after = RD_LADDER.index(cons[0].action);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
            assert after >= before, f"A5 VIOLATED: {kind} went {start} -> {cons[0].action}";
            assert after <= before + 1, f"more than one rung: {kind} {start} -> {cons[0].action}";
        }
    }
}


# THE ONE THIS ISSUE EXISTS TO PROTECT. Corroboration is additive, never a precondition. Prior art
# raised precision by REQUIRING corroboration before escalating; that turns the two-channel split
# into a silent-failure generator. A lone channel B hit reaches `ask` on its own.
test "a single uncorroborated channel B hit still reaches ask" {
    cons = [Concern(kind="interaction", anchor="solo", evidence=[], since="", action="ask")];
    moved = rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert moved == 0, "nothing corroborates it, so nothing moves";
    assert cons[0].action == "ask", "and it is STILL ask — corroboration is not a gate";
}


# Two rows from ONE mechanism are not two mechanisms agreeing. Without the distinct-kind check, a
# symptom with two additive-toxicity pairs would promote itself.
test "two concerns of the same kind on one anchor do not corroborate each other" {
    cons = [
        Concern(kind="additive_toxicity", anchor="w", evidence=[], since="", action="log"),
        Concern(kind="additive_toxicity", anchor="w", evidence=[], since="", action="log"),
    ];
    moved = rd_corroborate(cons);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    assert moved == 0, "one mechanism finding two pairs is still one mechanism";
}


# S6/CONTRACTS §3 as a TOTAL assertion over every concern any fixture in this file produces. This
# is what compensates for the kind-specific counts elsewhere: a new mechanism that emits above its
# ceiling gets caught here even though no other test was looking at it.
test "no mechanism ever emits above its ceiling" {
    for key in ["m1_ondansetron", "m1i_st_johns_wort", "a1_diarrhea", "a4_imatinib",
                "b1_peripheral_neuropathy", "b3_imatinib", "b4_naproxen", "b6_ondansetron"] {
        r = root spawn Recall(anchors=[key]);  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
        for c in r.reports[0].concerns {
            ceil = RD_CEILINGS.get(c.kind, "mention");  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
            assert RD_LADDER.index(c.action) <= RD_LADDER.index(ceil),  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
                f"{c.kind} emitted at {c.action}, above its ceiling {ceil}";
            assert (c.action != "escalate") or (c.kind == "emergency"),
                f"S6: {c.kind} reached escalate — that rung is rd_emergency's alone";
        }
    }
}


# ==========================================================================================
# #14 — Investigate. Lazy, read-only, zero LLM.
# ==========================================================================================

# ACCEPTANCE (#14): onset date, at least 3 timeline entries, every entry carrying a source.
test "expanding a row returns a case file with onset, timeline, and a source on every entry" {
    t = "i1_";
    drug = Anchor(key=t + "ondansetron", kind="ingredient");
    cls = Anchor(key=t + "QT-prolonging", kind="class");
    sym = Anchor(key=t + "qt_prolongation", kind="symptom");
    root ++> drug;
    root ++> cls;
    root ++> sym;
    drug +>:Member(via="class_member"):+> cls;
    cls +>:Member(via="toxicity_of"):+> sym;

    ur = Utterance(text="Ondansetron 8mg for the nausea.", at="2026-02-10", role="oncologist");
    root ++> ur;
    b = Belief(claim="regimen: ondansetron");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> ur;

    for d in ["2026-03-01", "2026-03-08", "2026-03-15"] {
        uo = Utterance(text="Heart felt fluttery again.", at=d, role="patient");
        root ++> uo;
        o = Observation(metric="qt_prolongation", value=3.0, at=d);
        root ++> o;
        o +>:Reports:+> sym;
        o +>:DerivedFrom:+> uo;
    }

    r = root spawn Investigate(concern_kind="additive_toxicity", anchor=t + "qt_prolongation");  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    cf = r.reports[0];

    assert cf.onset == "2026-03-01", f"onset is first observation, got {cf.onset}";
    assert len(cf.timeline) >= 3, f"expected >= 3 timeline entries, got {len(cf.timeline)}";
    for e in cf.timeline {
        assert e.source != "", f"S2: a timeline entry with no source: {e.what}";
        assert e.at != "", f"an undated timeline entry: {e.what}";
    }
    # Step 2: the regimen change is on the timeline next to the onset, which is the whole point.
    starts = [];
    for e in cf.timeline { if "started" in e.what { starts.append(e.at); } }
    assert "2026-02-10" in starts, f"the regimen change should be on the timeline, got {starts}";
    assert len(cf.citations) > 0, "every case file is citable or it is not shown";
    # Chronological and stable.
    ats = [];
    for e in cf.timeline { ats.append(e.at); }
    assert ats == sorted(ats), f"timeline out of order: {ats}";
}


# Step 4: an existing instruction changes the row from "report this" to "you were already told".
# The instruction comes back VERBATIM (S8) — a summary of a clinician's sentence is generated text.
test "an anchor with an existing instruction returns the already-covered variant" {
    t = "i2_";
    sym = Anchor(key=t + "fever", kind="symptom");
    root ++> sym;
    ui = Utterance(text="Call the clinic immediately if your temperature goes over 100.4.",
                   at="2026-06-01", role="oncologist");
    root ++> ui;
    c = Constraint(claim="fever over 100.4 is a reason to call", hard=True,
                   threshold_level=100.4, threshold_metric="fever");
    root ++> c;
    c +>:Governs:+> sym;
    c +>:DerivedFrom:+> ui;

    r = root spawn Investigate(concern_kind="persistence", anchor=t + "fever");  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    cf = r.reports[0];
    assert cf.existing_instruction == "Call the clinic immediately if your temperature goes over 100.4.",
        f"verbatim, not summarised — got {cf.existing_instruction}";
}


# Step 3, the counterfactual: days the drug was absent from the record, and whether the symptom
# was absent too. Named the drop candidate in #14 if the schedule slipped.
test "the counterfactual finds a stretch with no record of the drug" {
    t = "i3_";
    drug = Anchor(key=t + "capecitabine", kind="ingredient");
    root ++> drug;
    u = Utterance(text="Capecitabine 1250mg twice daily.", at="2026-01-05", role="oncologist");
    root ++> u;
    b = Belief(claim="regimen: capecitabine");
    root ++> b;
    b +>:About:+> drug;
    b +>:DerivedFrom:+> u;
    # Logged, then a three-week hole, then logged again.
    for d in ["2026-02-01", "2026-02-02", "2026-02-25"] {
        uo = Utterance(text="took it", at=d, role="patient");
        root ++> uo;
        o = Observation(metric="capecitabine", value=1.0, at=d);
        root ++> o;
        o +>:Reports:+> drug;
        o +>:DerivedFrom:+> uo;
    }

    r = root spawn Investigate(concern_kind="adherence_gap", anchor=t + "capecitabine");  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    cf = r.reports[0];
    assert "2026-02-02" in cf.counterfactual and "2026-02-25" in cf.counterfactual,
        f"expected the 02-02 -> 02-25 hole, got '{cf.counterfactual}'";
}


# S3: an anchor that is not in the record returns an empty case file, not a reassuring one.
test "Investigate on an unknown anchor returns an empty case file" {
    r = root spawn Investigate(concern_kind="persistence", anchor="i4_not_a_real_anchor");  # jac:ignore[W2001] — annex name resolution; `jac test` proves it binds
    cf = r.reports[0];
    assert cf.onset == "", "no onset for something that is not in the record";
    assert len(cf.timeline) == 0;
    assert cf.existing_instruction == "";
    # Exactly one report, even on the disengage path.
    assert len(r.reports) == 1, f"expected one report, got {len(r.reports)}";
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

    assert rd_kind_count(v.concerns, "emergency") == 0, "99.1 is below 100.4 — the bypass must not fire";
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

    assert rd_kind_count(v.concerns, "emergency") == 0,
        "reporting the ABSENCE of a symptom must not raise the alarm";
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

    assert rd_kind_count(v.concerns, "emergency") == 0,
        "Supersedes kills an emergency constraint like any other";
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
    assert rd_kind_count(v.concerns, "emergency") == 0, "three readings on one day is one day, not two";
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

    assert rd_kind_count(v.concerns, "emergency") == 0,
        "a Concern `pg_row` would drop must not be fabricated";
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
