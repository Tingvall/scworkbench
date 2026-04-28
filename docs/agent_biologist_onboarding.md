# Agent Biologist Onboarding

Role: run analyses and generate biologically useful, reproducible outputs.

## Responsibilities

- Define analysis question and comparisons.
- Execute ops through engine contracts.
- Interpret results with explicit caveats.
- Produce provenance-linked reports.

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
- Include plots and interpretation.
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
