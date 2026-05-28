# Agent Playbook

Operational workflow for reliable analysis and code changes.

Current phase note:
- Before adding new features, prioritize hardening/bugfixing. See `docs/next_pass_hardening_notes.md`.

## A. When Running Analysis

1. Verify inputs
- Resolve required sets/matrix/space/namespace names.
- Confirm coverage counts before expensive ops.

2. Execute with session
- Use `wb_session_new()` + `wb_session_run_op()` chain.
- Keep notes fields meaningful.

3. Promote selectively
- Use `wb_session_promote_current()` for intended outputs only.

4. Emit provenance artifacts
- Save report markdown/html.
- Save run context JSON.
- Save DAG nodes/edges.
- Save replay script.

5. Report with IDs
- Every result claim should map to run/artifact IDs.

## B. When Adding Engine Features

1. Define/confirm primitive contract first.
2. Add op in one canonical registration path (`op_catalog`).
3. Ensure runner + interface + promotable outputs are coherent.
4. Add contract tests.
5. Validate with real bundle smoke test.

If the change is not an op, place it in the correct engine surface:

- display dataset mapping -> plot wrangler / plot contract
- artifact human summary -> identity-card issuer
- cross-panel or cross-artifact handoff -> navigation contract
- storage/query access -> getter layer

For motif/regulatory work, keep the contracts distinct:

- matrix genome metadata on the peak matrix
- motif library / motif definition registry
- motif-match materialization as its own registry surface
- chromVAR and related compute consuming those contracts

Reference:

- `docs/motif_contracts_and_chromvar.md`

Do not solve these in the client first.

## C. When Updating Thin Clients

- Never re-implement engine logic in client.
- Client should pass symbolic inputs and render engine outputs.
- Keep UX helpers separate from core analysis semantics.
- If a client needs a new friendship between views, treat that as a navigation
  contract request, not a client-only shortcut.

## D. Deletion / Mutating Operations

- Prefer plan APIs first (e.g. delete plan/dependencies).
- Expose dangerous actions with preview + explicit confirmation.
- Keep recursive/force modes explicit.

## E. Quality Bar For Reports

Minimum:
- Methods
- Results
- 2-3 plots
- Artifact and run IDs
- Caveats and next steps

Preferred:
- Alternative biological hypotheses
- Confound checks proposed
- Additional validation plan
