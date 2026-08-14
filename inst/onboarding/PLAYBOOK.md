# Agent Playbook

Operational workflow for reliable analysis and code changes.

## Auditable-Transformation Law

Every scientifically meaningful transformation, selection, statistical test,
model fit, or derived diagnostic must be performed through a registered
operation or provenance-aware wrangler and leave an auditable trail in the
bundle. Reports may summarize recorded evidence; they may not create
unrecorded scientific results.

Apply this to ingestion, normalization, filtering, cell-set derivation,
feature selection, embeddings, model fitting, DE, enrichment, scoring, and
metadata diagnostics. When a table or plot supports a conclusion, create it
through a provenance-aware plot or wrangler contract and retain its input
artifacts and specification. Cosmetic report formatting does not need an
engine operation, but any computation that changes a scientific value,
membership, test, or interpretation-relevant summary does.

An unsupported generic capability is a stop-and-report condition: report the
gap with the attempted interface and needed contract. Do not use an external
unrecorded script as a substitute.

## Recipient read-only audit

Mount a bundle read-only and open it explicitly with
`wb_open_bundle(path, read_only = TRUE, validate = TRUE)`. This mode never
migrates SQLite or writes WAL/journal/staging state. Use normal getters,
`wb_prov_bundle_dag()`, `wb_kg_provenance_graph()`,
`wb_entity_certificate()`, `wb_prov_run_details()`, and
`wb_prov_source_inputs()` for the recipient audit. Mutation, session, and
promotion APIs fail before attempting a write.

For external inputs, construct explicit `public_file`/`external_file` entries
with `wb_source_input()` and dry-run the complete identity with
`wb_source_preflight()`. These require source ID, accession, role, format,
path or URI, and canonical SHA-256 identity.
`wb_prov_source_inputs()` normalizes these to `checksum_algorithm`,
`checksum_value`, and `checksum_status`. In `wb_prov_bundle_dag()` the node
classification column is `node_type`; filter `node_type == "external_source"`
and `edge_type == "CONSUMES"` to inspect source-to-ingestion edges.
Automatic assembly events have no external-source node. Genuine object inputs
use the distinct `in_memory_source` node type and remain explicitly nonportable.

### Entity provenance certificates

The composed DAG is authoritative. `wb_entity_certificate()` is a deterministic,
read-only node-focused projection over that DAG, typed run bindings, output
identities, lifecycle records, and entity registries; a certificate is never a
separately persisted source of truth. Generate one for any durable scientific
entity:

```r
wb_entity_certificate(b, "matrix", "RNA_counts")
wb_entity_certificate(b, "space", "rna.pca")
wb_entity_certificate(b, "artifact", artifact_id)
wb_entity_certificate(b, "run", run_id)
```

The common schema is `scworkbench.provenance.entity_certificate.v1`. Missing,
unverified, corrupt, and not-applicable evidence is stated explicitly. Space
views distinguish `source_space_id` from `output_space_id`; they never expose
coordinates. Storage paths are bundle-relative, and certificates never embed
matrix, coordinate, model, or artifact payloads. Use `wb_matrix()`, `wb_space()`,
`wb_art_load()`, and the model getters when scientific data are actually needed.

## Executable target reproduction

Build a minimal replay closure with `wb_target_reproduction_plan()` and emit a
portable installed-package script with `wb_target_emit_r_script()`. Emitted
scripts call only `wb_target_execute_plan()`, the public mutation boundary that
requires one existing source-only writable clone. It rejects the inspected
source, filesystem-read-only recipients, missing or changed immutable source
boundaries, analytical state or durable output collisions, and ambiguous
plans before replay or promotion. Runs execute in their declared topological
order inside a private session overlay; terminal semantic/loadable equivalence
is checked before selected outputs are promoted. The complete verified receipt
set is inserted inside the same private promotion transaction and payload
workspace as outputs, artifacts, snapshots, bindings, and materializations. A
failed check, receipt write, SQLite commit, or payload publication discards the
whole attempt and creates no promoted claim.

Do not edit generated scripts to call package internals. Supply the destination
clone when emitting the script and execute it in a fresh process with the
installed package.

The composed DAG is canonical across provenance snapshots: each durable entity
or globally unique run appears once by `nodes$id`. Repeated snapshot evidence is
the ordered JSON array `snapshot_ids`; `snapshot_id` is present only when the
evidence belongs to one snapshot. Edges are unique by `semantic_key`, defined
over `from`, `to`, `edge_type`, semantic `label`, and typed `binding`. Conflicting labels,
kinds, producers, lifecycle states, or edge bindings fail closed. Focused
lineage and provenance KG views use the same stable identities.

For a historical run, pass the `snapshot_id` returned with its public
provenance record, for example each unique `snapshot_id`/`run_id` pair from
`wb_prov_source_inputs()`. A run-only `wb_prov_run_details()` lookup searches
all snapshots and succeeds only when the match is unique; ambiguity is an
explicit error rather than an implicit current-head lookup.

Before transferring a writable bundle, run `wb_finalize_recipient_bundle(b)`
and confirm `wb_recipient_readiness(path)$ready`. The supported container audit
is `containers/apptainer/recipient_readonly_audit.sh IMAGE BUNDLE_DIR`; it
uses `singularity --bind BUNDLE_DIR:/audit_bundle:ro`, obtains historical
run/snapshot pairs from public provenance getters, and never clones the bundle.

For writable container work, bind the directory that contains the bundle and
open the bundle below that mount. The exclusive writer lock is a sibling of
the bundle, so `--bind BUNDLE_DIR:/bundle` is not a valid writable topology:
it would require creating `/.bundle.scworkbench-writer-lock` under the
container root. A timeout with `owner_status=absent` and a root-level lock path
means the parent mount is not writable, not that a stale owner exists. Rebind
the parent; do not invoke lock recovery. Direct bundle binding with `:ro`
remains correct for recipient inspection.

Committed writers are serialized by the sibling lock protocol documented in
`docs/bundle_writer_lock.md`. Recipient read-only open refuses an active writer;
inspect ownership with `wb_bundle_writer_lock_info()` and recover a verified
stale lock only through `wb_recover_bundle_writer_lock()`.

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

### Long-running operation safety

Use `wb_session_new()` only for bounded work that is cheap to repeat. scVI,
PeakVI, large embeddings, and other long-running chains belong in a
machine-persistent `wb_session_create()` workspace. Each successful operation
is checkpointed before the next; a detached service does not replace that
checkpoint. After a downstream input/script failure or process replacement,
call `wb_session_resume()` and continue from the last complete operation.

For a sibling branch from bundle provenance, use
`wb_prov_run_replay_inputs()` to obtain operation-aware typed inputs.
`wb_prov_run_details()` remains the exact stored inspection representation and
must not be manually coerced into an execution contract.

`wb_session_run_op()` returns `session`, `run`, and `result`. Its `run` value
is a structured `wb_run`, not a `data.frame`/`data.table`; never coerce or
serialize it wholesale between execution and promotion. For expensive runs,
immediately retain `session <- result$session`, identify terminal outputs with
`wb_op_interface()`, and promote them. Write reports, JSON, CSVs, plots,
identity cards, and diagnostics only after successful promotion. Before that,
extract only stable scalar IDs and use `wb_session_view(session)` to inspect
staged state.

```r
session <- wb_session_new()
result <- wb_session_run_op(
  session, bundle, "hvg_select",
  inputs = list(matrix = "RNA_counts", n_features = 2000L)
)
session <- result$session
promotion <- wb_session_promote_current(bundle, session, outputs = "selected_features")

# Post-promotion inspection and reporting use durable bundle state.
artifacts <- wb_art_list(bundle)
run_details <- wb_prov_run_details(bundle, result$run$run_id)
```

3. Promote selectively
- Use `wb_session_promote_current(outputs = ...)` for intended terminal
  outputs only. Required ancestors become internal committed provenance, not
  public artifacts.
- `wb_op_interface(op)$produces[[name]]` is machine-readable: only outputs
  with `promotable_directly=TRUE` are valid `outputs=` terminals. Outputs with
  `durability_role="materialization"` are committed transitively by the listed
  `materialized_by_terminals`.
- When two staged runs share a terminal name, qualify it with the existing
  typed reference: `wb_session_promote_current(bundle, session, outputs =
  list(wb_ref_run(hvg_run_id, "fit_summary"), wb_ref_run(pca_run_id,
  "fit_summary"), "model"))`. Plain names remain intentionally ambiguous
  unless the active head produces the requested terminal.
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
