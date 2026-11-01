# Public synthetic graph example. No patient facts or model calls.
import from graph { Anchor, Constraint, Utterance, Member, Excludes, DerivedFrom }
import from read { Recall }
import from json { dumps }
with entry {
    item = Anchor(key="fictional-demo-item", kind="substance");
    category = Anchor(key="fictional-demo-category", kind="class");
    root ++> item;
    root ++> category;
    item +>:Member(via="class_member"):+> category;
    source = Utterance(text="Fictional instruction: do not add items in this category.", at="2026-11-01", role="fictional instruction author");
    root ++> source;
    rule = Constraint(claim="Fictional category is excluded", hard=True);
    root ++> rule;
    rule +>:Excludes(because="Synthetic public demonstration rule"):+> category;
    rule +>:DerivedFrom:+> source;
    result = root spawn Recall(anchors=["fictional-demo-item"]);
    verdict = result.reports[0];
    violations = [];
    for violation in verdict.violations {
        violations.append({"claim":violation.claim,"because":violation.because,"source":violation.source,"at":violation.at});
    }
    print(dumps({"allowed":verdict.allowed,"violations":violations,"scope":"Original Jac Recall walker on a fictional two-hop category constraint. No medical advice, model calls or patient records."}));
}
