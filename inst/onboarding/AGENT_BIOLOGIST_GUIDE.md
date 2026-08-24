# Agent Biologist Onboarding

Role: run analyses and generate biologically useful, reproducible outputs.

## Responsibilities

- Define analysis question and comparisons.
- Execute ops through engine contracts.
- Interpret results with explicit caveats.
- Produce provenance-linked reports.

## Auditable-Transformation Law

Every scientifically meaningful transformation, selection, statistical test,
model fit, or derived diagnostic must be performed through a registered
operation or provenance-aware wrangler and leave an auditable trail in the
bundle. Reports may summarize recorded evidence; they may not create
unrecorded scientific results.

This includes ingestion, normalization, filtering, cell-set derivation,
feature selection, embeddings, model fitting, DE, enrichment, scoring, and
metadata diagnostics. Interpretation-relevant tables and plots must use
provenance-aware contracts with their input artifacts and specifications
retained. Cosmetic report formatting is fine outside the engine; computation
that changes a scientific value, membership, test, or summary is not.

If the engine lacks a generic capability, stop and report the gap. An
unsupported capability never authorizes an external unrecorded script.

Core operations and explicitly activated operation-pack operations are both
registered engine paths. Installing a pack is inert; validation/loading is a
trust decision and conformance does not prove scientific validity. A recipient
can inspect and load retained promoted outputs without the pack, but replay or
continuation requires the exact compatible pack recorded by provenance. Use a
terminal capsule only for irreducibly question-specific output, and use adoption
for externally computed authoritative state. Repeated reusable capsule compute
is a candidate for a pack operation.

The protocol can recognize an R or Python pack even when the corresponding
execution runtime is not installed. Structural manifest acceptance is not
activation: a valid Python declaration remains non-executable until the audited
PyBench backend is available, and this never authorizes an external script or
direct bundle write.

## Analysis Workflow

1. Verify inputs
- Resolve set names, matrix/space IDs, namespace names.
- Confirm group sizes and feature universe.

2. Run compute
- Use session workflow (`wb_session_new`, `wb_session_run_op`).
- Keep notes clear and specific.

3. Promote intentionally
- Promote only outputs needed for traceable results.

4. Report reproducibly
- Include run IDs and artifact IDs.
- Include methods and thresholds.
- Include plots with retained contract inputs/specifications and interpretation.
- Emit replay script + run context + DAG exports.

## Interpretation Standard

Always provide:
- Marker-level patterns.
- Pathway/program-level interpretation.
- At least one alternative biological explanation.
- Confound/validation next steps.

## Claim Discipline

- Distinguish observed result vs speculation.
- Tie each key conclusion to concrete artifact/run outputs.
- Avoid unsupported mechanistic certainty.
