Fixes #

**Acceptance:**
<!-- Paste the actual output proving the check passed. Not "it works". -->

**Invariants touched:** none
<!-- S1-S9 / A1-A9 in ARCHITECTURE.md section 2. "none" is the expected answer.
     Anything else needs the `safety` label and a second reader before merge. -->

**New `by llm()` sites:** none
<!-- Hard cap is two, both on the write path. A third requires human approval. -->

---

- [ ] `jac check .` is clean
- [ ] No pinned shape in `CONTRACTS.md` changed (or: `contract` label applied and acked)
- [ ] `graph/archetypes.jac` untouched (or: `schema` label applied, team told to reset graphs)
- [ ] Commented on the issue thread with what changed
