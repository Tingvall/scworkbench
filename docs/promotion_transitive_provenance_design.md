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

### Operation side effects

The desired default is that a session op writes new mutable payloads only into
its staging workspace. Bundle registry mutation and final payload paths happen
at promotion time.

Migration must classify operations before changing behavior:

- **stage-capable**: tabular/vector/model/path payloads can be materialized in
  staging and promoted through the commit path.
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

The current `prov_runs` JSON fields are a useful base, but operation version
and output materialization identity are not yet a complete replay contract.

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

The exact argument name for explicit output selection is an implementation
decision. It must make terminal selection explicit and must default safely:

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

1. Add a narrow contract test for terminal-only promotion of a two- or
   three-run session closure. Assert all runs persist, only selected outputs are
   public artifacts, and replay/audit can traverse the closure after reopening.
2. Add transaction/commit metadata and change provenance snapshot writing to
   record closure completeness independently of public artifacts.
3. Stage primitive payload promotion for existing in-memory primitive kinds.
4. Migrate one eager side-effect family at a time, beginning with the matrix and
   space operations used in the PBMC workflow.
5. Add crash/recovery tests and compatibility readers for legacy snapshots.
6. Update DAG, identity-card, semantic catalog, fullstack, and consumer
   contracts only after the engine transaction is proven.

## Non-Goals

- Persisting every successful exploratory operation immediately.
- Treating promotion as a mere accepted/current label.
- Making every intermediate output a public artifact.
- Reconstructing lost provenance from pre-migration bundles.
- Allowing arbitrary external filesystem references as replay dependencies.

## Controller Decisions Still Needed

1. Is the first implementation allowed to support only stage-capable primitive
   outputs and reject eager matrix/space operations, or must it migrate the
   PBMC matrix/space chain in the same release?
2. Should `wb_session_promote_current()` require explicit output names whenever
   a head run has multiple promotable outputs, or use a documented terminal-head
   default?
3. What retention policy applies to completed session staging work after a
   successful commit and to abandoned session work after a timeout?
4. Which runtime fingerprints are mandatory for a result to be labelled
   `replayable` rather than `inspectable_only`?
