# Agent Playbook

Operational workflow for reliable analysis and code changes.

## Recipient read-only audit

Mount a bundle read-only and open it explicitly with
`wb_open_bundle(path, read_only = TRUE, validate = TRUE)`. This mode never
migrates SQLite or writes WAL/journal/staging state. Use normal getters,
`wb_prov_bundle_dag()`, `wb_kg_provenance_graph()`,
`wb_art_birth_certificate()`, `wb_prov_run_details()`, and
`wb_prov_source_inputs()` for the recipient audit. Mutation, session, and
promotion APIs fail before attempting a write.

For external inputs, use `source_identity$inputs` entries with `sha256` (the
canonical SHA-256 field), optional `path`/`uri`, `role`, and `format`.
`wb_prov_source_inputs()` normalizes these to `checksum_algorithm`,
`checksum_value`, and `checksum_status`. In `wb_prov_bundle_dag()` the node
classification column is `node_type`; filter `node_type == "external_source"`
and `edge_type == "CONSUMES"` to inspect source-to-ingestion edges.

Before transferring a writable bundle, run `wb_finalize_recipient_bundle(b)`
and confirm `wb_recipient_readiness(path)$ready`. The supported container audit
is `containers/apptainer/recipient_readonly_audit.sh IMAGE BUNDLE_DIR`; it
uses `singularity --bind BUNDLE_DIR:/bundle:ro` and never clones the bundle.

Current phase note:
- Before adding new features, prioritize hardening/bugfixing. See `docs/next_pass_hardening_notes.md`.

## A. When Running Analysis

1. Verify inputs
- Resolve required sets/matrix/space/namespace names.
- Confirm coverage counts before expensive ops.

2. Execute with session
- Use `wb_session_new()` + `wb_session_run_op()` chain.
- Keep notes fields meaningful.
- Session outputs are staged and ephemeral until promotion. Inspect staged
  matrices/spaces with `wb_session_view(session)`; do not expect them in the
  portable bundle before promotion.

3. Promote selectively
- Use `wb_session_promote_current(outputs = ...)` for intended terminal
  outputs only. Required ancestors become internal committed provenance, not
  public artifacts.
- `wb_op_interface(op)$produces[[name]]` is machine-readable: only outputs
  with `promotable_directly=TRUE` are valid `outputs=` terminals. Outputs with
  `durability_role="materialization"` are committed transitively by the listed
  `materialized_by_terminals`.
- If promotion fails, discard the private session workspace with
  `wb_session_discard(session)` before retrying. Never delete an existing
  bundle target to clear a collision: use a new output ID unless ownership of
  the abandoned private workspace is established.

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
