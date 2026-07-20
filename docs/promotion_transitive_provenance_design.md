# Transitive Promotion Provenance Design

Status: proposed design for Controller review. This document does not change
runtime behavior or the current bundle schema.

## Decision

scworkbench has two intentional lifetimes:

1. A session is an exploratory workspace. Analysts and agents can run, branch,
   and discard work without permanently recording every attempt in a bundle.
2. Promotion is an explicit commit of a useful result to the portable bundle.
   Promotion commits the selected result and its complete required ancestral
   provenance closure. It is not an acceptance-only label.

The closure contains ordered successful runs, operation identities and versions,
parameters, resolved typed inputs, symbolic inputs, selected cell and feature
identities, output identities, parent edges, and materializations required to
inspect or replay the selected result after the session is gone.

Intermediate closure runs are durable provenance records. They are not
individually promoted artifacts unless the caller explicitly selects their
outputs for promotion. Abandoned session branches are not committed.

The first implementation must prove this contract for the release workflow:

```text
10x counts -> log normalize -> HVG -> PCA
                                      |  \\
                                      v   v
                                    UMAP Leiden -> markers
```

It is not sufficient to implement only table or vector outputs. The staged
matrix and space chain required by this workflow is part of the first vertical
slice.

## Current State And Gap

The engine already has useful pieces of the required model:

- `wb_session_run_op()` records in-memory `wb_run` objects with resolved input
  snapshots in `R/session_context.R`.
- `wb_promote_analysis()` finds the ancestor closure of a supplied head in
  `R/promote_primitives.R`.
- `.wb_prov_write_snapshot()` persists the ordered closure in `prov_heads`,
  `prov_runs`, `prov_run_edges`, and `prov_run_outputs` in
  `R/provenance_store.R`.
- `wb_prov_dag()`, `wb_prov_run_details()`, and replay helpers can inspect the
  resulting snapshot.

The current promotion implementation is not the desired contract. It walks the
closure and promotes every output declared `promotable` before writing the
snapshot. Consequently, an intermediate output becomes a public artifact only
because it was needed by a terminal result. The current lineage status also
counts promoted parent outputs, which encodes this coupling.

There is a second, separate gap. Some operations register matrix or space state
directly in the bundle while running. Such an operation is not ephemeral even
when its `wb_run` is session-local. The new contract must not describe those
side effects as scratch work until they are staged.

## Target Execution Model

### Session staging

Each session that may produce promotable output receives a bundle-adjacent,
non-public staging workspace. It is owned by the session and is removable when
the session is discarded. A staged run records:

- a stable session run id and parent run ids;
- the registered operation name and an operation implementation/version
  fingerprint;
- declared parameters, symbolic inputs, and resolved typed inputs;
- exact effective cell and feature identities, or a content-addressed persisted
  selection snapshot where the identities are large;
- output primitive identities, summaries, and content digests;
- staged payload locations and digests for outputs that need materialization;
- references to already committed bundle inputs, including immutable identity
  information sufficient to validate the reference later.

The session object remains the interactive view of these records. No successful
staged run appears in the bundle-level provenance DAG before promotion.

Staging belongs to the session, not to the portable bundle. After a successful
commit, staged payloads may be removed only after the committed copy/move has
passed digest validation. Abandoned staging is removed through explicit
`wb_session_discard()` or close semantics and a separately invoked garbage
collection command. The initial implementation must not introduce silent
time-based deletion.

### Parent identity invariant

A session-produced value retains its producing-run identity even when a caller
uses a convenient matrix, space, or output name. A string such as
`"RNA_log_normalized"` or `"pca"` must never silently downgrade a
session-produced value to an unrelated committed bundle object with the same
name.

The canonical ergonomic route is **unambiguous session-active resolution**:

- `wb_session_run_op()` records every produced output in `session$active` as a
  typed `wb_ref_run(run_id, output)` reference.
- An input name may resolve through that active binding only when it identifies
  exactly one compatible session output.
- A caller may always use an explicit `wb_ref_run(run_id, output)` reference.
- If a string is both a compatible committed bundle identifier and an active
  session output, resolution fails and asks for an explicit typed reference.

The resolved-input snapshot stores the producing `run_id` and `output` for a
session value. The promotion closure uses that identity to create the parent
edge. Names remain usability aliases, never lineage identifiers.

### Operation side effects

The desired default is that a session op writes new mutable payloads only into
its staging workspace. Bundle registry mutation and final payload paths happen
at promotion time.

Migration must classify operations before changing behavior:

- **stage-capable**: tabular/vector/model/path payloads can be materialized in
  staging and promoted through the commit path.
- **PBMC vertical-slice capable**: matrix normalization, HVG feature table,
  PCA space, UMAP space, Leiden vector, and marker table are staged and linked
  through the parent-identity invariant. These are mandatory in the first
  implementation.
- **eager bundle mutation**: the operation currently writes a matrix, space,
  registry row, or other final bundle state while it runs.
- **external materialization**: output is produced by a Python tool, cluster
  job, or another managed runtime and needs an immutable staged receipt.

Until an eager operation is migrated, it must be explicitly marked as eager in
its run receipt and cannot claim discardable-session semantics. The safe interim
policy is to reject transitive promotion of an untracked eager side effect, or
require it to be recorded as a committed materialization with its producing run
in the same promotion transaction. Silent direct mutation is not acceptable.

## Transactional Transitive Promotion

Promotion has two caller-controlled selections:

- **heads**: one or more terminal session run outputs to commit as public
  artifacts;
- **closure**: the successful ancestor runs required by those heads. The
  closure is derived, not separately selected.

The transaction performs the following steps:

1. Resolve the run closure in topological order. Fail if a required parent run
   is absent, unless it resolves to a verified committed bundle dependency.
2. Validate every closure run: operation contract/version availability,
   primitive kind, resolved input identity, selection snapshot, and staged
   payload digest.
3. Build a promotion manifest in a temporary commit directory. It records the
   terminal artifact requests, all closure runs, dependency identities, and
   planned destination paths.
4. Copy or move required staged payloads into a bundle-local transaction staging
   area. Validate final primitive payloads before they are visible from the
   registry.
5. In one SQLite transaction, register the selected terminal artifacts, write
   the complete provenance closure, link all run outputs, and record the
   promotion manifest/commit state.
6. Atomically publish staged payload paths into their final bundle locations,
   then mark the commit complete. A crash-recovery routine can either finish a
   validated pending commit or remove an uncommitted staging directory.

SQLite cannot make filesystem moves atomic by itself. The implementation must
therefore use a transaction journal/manifest with checksummed staged payloads;
metadata must never reference a payload that has not passed final validation.
The exact publish ordering and recovery state machine require implementation
tests for interruption between filesystem and SQLite steps.

`fail_fast` promotion of one requested head is all-or-nothing for that promotion
transaction. A multi-head API may later offer independent transactions, but it
must not silently commit a partial closure under one snapshot id.

### PBMC vertical-slice data flow

The required first vertical slice has this data flow. `S:` denotes session
staging, `C:` a committed internal materialization, and `A:` a public artifact.

Persisted composition uses typed `prov_run_entity_bindings` rows rather than
payload decoding: runs `CONSUME` matrices, spaces, model references, and
artifacts; they `MATERIALIZE` matrices/spaces/model references and `PRODUCE`
artifacts. An ingest-report run materializes the initial raw matrix. Thus a
composed bundle DAG can trace markers through Leiden, PCA, normalized matrix
and HVGs to `RNA_counts` and its ingest run, while UMAP remains a sibling
PCA-consuming branch that materializes both its 2D space and model reference.

```text
Committed bundle
  matrix: RNA_counts
        |
        | resolved committed input identity
        v
S:<session>/runs/r_norm/matrix/RNA_log_normalized
  matrix_log_normalize (run r_norm)
        |
        | session-active typed reference: wb_ref_run(r_norm, "matrix")
        v
S:<session>/runs/r_hvg/table/selected_features
  hvg_select (run r_hvg)
        |
        | wb_ref_run(r_norm, "matrix"), wb_ref_run(r_hvg, "selected_features")
        v
S:<session>/runs/r_pca/space/pca
  pca_fit (run r_pca)
        |-------------------------------+
        |                               |
        | wb_ref_run(r_pca, "space")    | wb_ref_run(r_pca, "space")
        v                               v
S:<session>/runs/r_umap/space_2d/umap  S:<session>/runs/r_leiden/vector/clusters
  umap_fit (run r_umap)                  leiden (run r_leiden)
        |                               |
        | [optional terminal selection]  | wb_ref_run(r_norm, "matrix"),
        |                                | wb_ref_run(r_leiden, "clusters")
        |                                v
        |                        S:<session>/runs/r_markers/table/markers
        |                          markers_topn (run r_markers)
        |                               |
        |                               | [optional terminal selection]
        +-------------------------------+
================ promotion transaction boundary ================
  C:matrix/RNA_log_normalized     C:feature-table/selected_features
  C:space/pca
  internal provenance runs r_norm -> r_hvg -> r_pca -> r_leiden -> r_markers
  optional internal/public UMAP branch: r_pca -> r_umap
  A:cell_vector/clusters (only if selected)
  A:feature_table/markers (only if selected)
  A:space_2d/umap (only if selected)
===============================================================
        |
        v
Reopened bundle
  wb_prov_artifact_lineage(A:markers) or wb_prov_bundle_dag()
  returns every committed run and parent edge, while internal materializations
  remain distinct from public artifacts.
```

Promotion of Leiden selects `A:clusters` and commits the closure through
`r_leiden`; promotion of markers selects `A:markers` and commits the complete
closure through `r_markers`. If a portable UMAP display is also wanted, the
caller explicitly selects the UMAP `space_2d` as another terminal output. The
resulting closure is the union of the true ancestors of all selected terminals.
If only markers are selected, the sibling UMAP branch is not committed. No
other output is public merely because it is an ancestor.

## Materialization And Replay Boundary

Every closure output is classified as one of:

- **public artifact**: explicitly selected terminal output, registered in
  `artifacts` with a loadable payload;
- **internal materialization**: an output required to recreate or inspect a
  selected result, stored bundle-locally and linked from its provenance run but
  not listed as a public artifact;
- **replayable reference**: an immutable reference to committed bundle state;
- **unpromotable dependency**: an output that lacks either a valid staged
  materialization or a verified immutable reference. Promotion fails with a
  precise error.

The closure is sufficient for two distinct tasks:

- **audit/inspection**: explain what was run, with which exact inputs and
  outputs;
- **replay**: invoke the registered operations in dependency order against the
  recorded resolved inputs.

Replay is not a guarantee of bitwise identity unless the operation and runtime
are deterministic and their recorded environment/dependency fingerprints still
resolve. The provenance validator should report reproducibility grades such as
`replayable`, `inspectable_only`, or `missing_materialization`; it must not
overstate replayability.

Every committed closure must record at minimum:

- installed `scworkbench` package version and source revision when available;
- R version;
- operation implementation/version fingerprint;
- relevant package and runtime fingerprint; and
- container image digest when the execution is known to have occurred in a
  Singularity/Apptainer image.

The current `prov_runs` JSON fields are a useful base, but operation version,
runtime fingerprint, and output materialization identity are not yet a complete
replay contract. A closure is labelled `replayable` only when its required
inputs/materializations and all required fingerprints validate. Otherwise it is
labelled `inspectable_only` with the unmet conditions recorded.

## Proposed Schema Migration

The existing `prov_*` tables remain the authoritative run-closure registry; do
not create a second parallel run registry. The migration should add fields or
normalized companion tables only where the current snapshot cannot express the
commit contract.

Required additions to the provenance schema:

| Concern | Proposed storage | Purpose |
| --- | --- | --- |
| Promotion transaction | `prov_commits` | Commit id, state, timestamps, actor, selected heads, manifest digest, recovery status. |
| Snapshot ownership | `prov_heads.commit_id` | Bind a complete closure snapshot to one committed promotion. |
| Operation identity | `prov_runs.op_version` and `runtime_fingerprint_json` | Detect semantic/runtime drift during replay. |
| Resolved selection | `prov_run_inputs` or content-addressed selection records | Store exact cells/features without relying only on symbolic names. |
| Output identity | extend `prov_run_outputs` | Add primitive summary/digest, materialization class, and optional internal materialization id. |
| Internal payloads | `prov_materializations` | Bundle-relative path, payload digest, primitive kind, lifecycle state, and producing run/output. |
| External/committed dependencies | `prov_dependencies` | Stable bundle artifact/object reference plus digest and validation status. |
| Public terminal selection | `prov_commit_artifacts` | Explicitly distinguish requested public artifacts from internal closure outputs. |

All new payload paths must be relative to the bundle. Existing absolute
`model_ref` behavior is already being repaired separately and should not be
copied into this design.

Migration is additive. Existing snapshots retain their current schema version
and are readable as legacy snapshots. They cannot be relabeled as fully
transitive commits when their payload/materialization closure was not captured.
Backfill may link known existing artifacts to producing snapshots, but it must
not invent missing session runs, selections, or side-effect lineage.

## Public API Direction

The user model remains deliberately small:

```r
s <- wb_session_new()
s <- wb_session_run_op(s, b, "...", inputs = list(...))$session
wb_session_promote_current(b, s, outputs = c("terminal_result"))
```

The `outputs` argument selects public terminal outputs. Its default is defined
as follows:

- if the selected head has exactly one public/promotable terminal output, it
  may be selected by default;
- if the selected head has more than one public/promotable terminal output,
  `outputs=` is required and the error lists available choices;
- no implicit promotion of every ancestor output;
- no implicit omission of a required internal materialization;
- a clear result separating `public_artifacts`, `internal_materializations`,
  `snapshot_id`, and `commit_id`.

`wb_promote_analysis()` remains the lower-level engine entry point. It should
accept an explicit terminal-output selection rather than treating the full
ancestor `promotable` set as the promotion set.

## Consumer And DAG Behavior

The bundle-level DAG represents committed branches only:

- a promotion/commit node identifies the atomic boundary;
- a provenance snapshot node represents the captured closure;
- internal run nodes are shown because they explain a committed public result;
- public artifact nodes are shown only for explicitly promoted outputs;
- internal materialization nodes may be available in detailed/audit views but
  are visually distinct from public artifacts;
- committed bundle dependencies connect to the consuming run;
- discarded session runs do not appear.

`wb_prov_bundle_dag()` and `wb_prov_artifact_lineage()` should expose a default
consumer view that is readable, with options to expand internal materializations
and resolved selections for audit. Shiny, Lumen, KG export, and `scwb-agent`
consume this engine view; they must not infer promotion status from missing
intermediate artifact nodes.

The existing `lineage_status` logic based on the number of *promoted parent
outputs* must be replaced. Under this design, closure completeness means every
required parent run and materialization/reference is present and verified, not
that every parent output is a public artifact.

## Failure And Recovery Semantics

- Failed operations create no successful staged-run output record.
- Discarded sessions leave no committed provenance node.
- Failed validation before commit leaves the bundle unchanged and the staging
  workspace inspectable or removable according to session policy.
- Interrupted promotion leaves a recoverable pending commit record only when
  required to reconcile staged filesystem payloads; it never exposes a normal
  completed artifact or closure.
- A completed commit cannot have an opaque missing parent edge. If a dependency
  cannot be represented as a verified materialization or immutable reference,
  promotion fails.

## Implementation Sequence

1. Implement the PBMC vertical slice: stage the normalized matrix, HVG result,
   PCA space, UMAP space, Leiden vector, and marker table in one session.
   Regression tests must consume the normalized matrix, PCA space, and UMAP
   space through the canonical session-active route and verify their producer-
   run edges survive close/reopen. The graph is branched: PCA is the true input
   to UMAP and Leiden; markers consumes normalized expression plus Leiden
   clusters.
2. Add terminal-only promotion and transaction/commit metadata. Assert that a
   promoted Leiden or markers result has the complete ancestry closure but only
   selected terminal outputs are public artifacts.
3. Change provenance snapshot writing to record closure completeness
   independently of public artifacts, including resolved selections and replay
   fingerprints.
4. Add crash/recovery tests and compatibility readers for legacy snapshots.
5. Migrate other eager side-effect families one at a time. Before migration,
   they must clearly fail or be classified as eager/unavailable for discardable
   session mode.
6. Update DAG, identity-card, semantic catalog, fullstack, and consumer
   contracts only after the engine transaction is proven.

## Non-Goals

- Persisting every successful exploratory operation immediately.
- Treating promotion as a mere accepted/current label.
- Making every intermediate output a public artifact.
- Reconstructing lost provenance from pre-migration bundles.
- Allowing arbitrary external filesystem references as replay dependencies.

## Controller Decisions Still Needed

The Controller decisions above resolve the first implementation boundary,
terminal selection, staging retention, and minimum replayability fingerprint.
Implementation remains paused pending review of this amended design.
