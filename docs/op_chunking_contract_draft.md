# Op Chunking Contract Draft

Status: implemented first pass, still expanding

Purpose: define the generic engine-owned chunking surface used for ops that are
safe to execute in partitions, so large bundles remain operable without pushing
batching logic into clients, notebooks, or one-off scripts.

Closure criteria for this track live in:

- `docs/signal_family_and_chunking_closure_checklist.md`

Observed `ucell` benchmark notes live in:

- `docs/ucell_chunking_benchmark_note.md`

This is a hardening document.

It is not a license to add ad hoc batching to random ops.

Current implementation state:

- chunking metadata exists in the op catalog and `wb_op_interface()`
- a generic internal chunk helper exists
- `ucell` is migrated through the generic helper for cell-axis chunking
- some feature-axis ops still use op-local chunking and are documented as such

## 1. Problem Statement

`scworkbench` already supports bundles that can exceed the comfortable memory
limits of a single workstation.

Some current ops already contain local chunking logic, especially over
features. But there is no general engine contract for:

- declaring an op chunk-safe
- specifying the axis along which chunking is legal
- executing the op in chunks
- merging chunk outputs back into canonical primitives
- recording chunked execution in provenance

This gap becomes visible in large-bundle workflows such as:

- `ucell` over tens of thousands of cells
- large per-feature summary scans
- other per-cell or per-feature computations that are analytically separable

Without an engine contract, users and agents are pushed toward:

- manual batching in scripts
- client-specific workarounds
- inconsistent provenance
- duplicated merge logic

That violates the thin-client principle.

## 2. Core Principle

Chunking is an execution strategy owned by the engine.

Chunking is not a separate scientific method.

So the engine must preserve:

- op semantics
- primitive contracts
- provenance clarity
- client independence

Clients may request chunked execution through normal op inputs or defaults, but
they should not define the batching semantics themselves.

## 3. Scope

This contract is only for ops that are analytically separable across a declared
axis.

Initial legal axes:

- `cells`
- `features`

Possible later axes:

- `groups`
- `lineages`

Out of scope for the first pass:

- arbitrary multidimensional chunk plans
- distributed execution
- client-owned merge logic
- chunking ops whose semantics depend on a full global view unless an explicit
  equivalence argument exists

## 4. Chunkability Rules

An op is chunkable only if all of the following are true:

1. The op result over all chunks can be merged into the same output contract as
   the unchunked run.
2. Chunking does not change the scientific meaning of the result.
3. The merge rule is explicit and deterministic.
4. Provenance can state clearly that chunking was an execution strategy rather
   than a semantic change.

Examples:

- `ucell` is chunkable across `cells`
  - each cell score depends on that cell's gene ranks
  - cells do not depend on one another
  - full feature universe must still be used inside each cell chunk
- `trajectory_de` is already effectively chunkable across `features`
  - features are tested independently after pseudotime is fixed
- PCA fitting is not chunkable by default in this sense
  - chunking would change the estimation procedure unless a dedicated algorithm
    is introduced

## 5. Contract-Level Metadata

Ops can declare optional chunking metadata in the op catalog.

Current field shape:

- `chunkable`
  - boolean
- `axis`
  - `"cells"` or `"features"`
- `chunk_size_param`
  - input parameter name if caller can tune chunk size
- `chunk_size_default`
  - engine default when chunking is enabled
- `merge`
  - named list describing how each output is merged
- `status`
  - implementation note such as `"planned"` or `"implemented_op_local"`

Example shape:

```r
chunking = list(
  chunkable = TRUE,
  axis = "cells",
  chunk_size_param = "chunk_size",
  chunk_size_default = 2000L,
  merge = list(
    signature_scores = "row_bind_family",
    signature_summary = "recompute_summary"
  )
)
```

This metadata lives with the op contract, not in Shiny and not in external
wrappers.

## 6. Execution Model

High-level execution model:

1. `wb_session_run_op()` resolves normal inputs and `effective_cells`.
2. The dispatcher determines whether chunking is requested or required.
3. If not chunked, the existing runner path is used unchanged.
4. If chunked, the engine:
   - partitions the legal axis
   - invokes the same runner repeatedly with chunk-specific scope
   - merges outputs using declared merge rules
   - records chunk metadata in the op params or run metadata

Important:

- chunking is a wrapper around the existing op runner contract, not a
  second parallel op system
- the runner should not have to know whether it is part of a chunked plan unless
  it needs chunk-specific controls

Current implementation note:

- the generic helper is internal
- chunked runs currently record chunk metadata in run params
- `ucell` recomputes `signature_summary` from merged `signature_scores` rather
  than merging per-chunk summaries directly

## 7. Merge Semantics

The current implementation intentionally supports only a conservative set of
merge-safe primitive kinds.

Current merge-safe targets:

- `cell_vector`
- `cell_vector_family`
- `feature_table`
- `obs_table`

Current merge strategies:

- row-bind by cell/key or feature/entity with deterministic ordering
- recompute summary from merged low-level outputs when summary correctness would
  otherwise depend on chunk boundaries
- attach chunk metadata only in params, not embedded into scientific values

Examples:

### `cell_vector`

- merge by concatenating values aligned to unique `cell_id`
- final ordering should respect canonical cell order

### `cell_vector_family`

- merge by row-binding `(key, cell_id, value)` records
- final ordering should preserve canonical key and cell order where possible

### `feature_table`

- merge by row-binding tested features
- if p-value adjustment is global, recompute it after merge rather than trusting
  per-chunk values

### `obs_table`

- merge only when table semantics are chunk-stable
- otherwise require a recompute-summary strategy

Not merge-safe by default:

- `space`
- `space_2d`
- `model_ref`
- graph structures
- clustering/model-fit outputs

These may become chunk-aware later, but are not included in the current generic
merge layer.

### Internal Helper Semantics

The current internal helper surface consists of:

- `.wb_chunk_partition()`
  - partitions an ordered vector into deterministic chunk lists
- `.wb_merge_chunked_output()`
  - merges one output across chunk results using an explicit merge strategy
- `.wb_merge_chunked_outputs()`
  - merges a named output set across all chunk results
- `.wb_run_op_in_chunks()`
  - runs one existing runner over chunk partitions and returns merged outputs

Current supported merge strategies:

- `row_bind_cell_vector`
- `row_bind_cell_vector_family`
- `row_bind_feature_table`
- `row_bind_obs_table`

Current non-goal:

- no hidden inference of merge rules
- every merged output should have an explicit declared strategy

## 8. Provenance Requirements

Chunked execution must remain auditable.

Minimum provenance expectations:

- the run still appears as one op run, not as arbitrary client-generated
  fragments
- run params should record:
  - chunking enabled or not
  - chunk axis
  - chunk size
  - number of chunks
- replay should remain possible from engine-owned inputs

The chunk plan is execution metadata, not a change to the scientific contract.

## 9. API Shape

The first implementation should stay minimal.

Recommended caller-facing inputs:

- `chunk_size = NULL`
  - `NULL` means default op behavior
  - positive integer enables chunking for chunk-safe ops
- optionally later:
  - `chunk_axis = NULL`
  - only if an op legally supports more than one axis

Strong recommendation:

- do not introduce a new top-level public function first
- extend the normal op/session path so chunking is part of ordinary execution

This keeps client and agent ergonomics simple.

Current implemented public behavior:

- `ucell` accepts `chunk_size`
- `ucell` also accepts:
  - `ncores`
  - `parallel_backend = "auto" | "serial"`

The serial backend is important for constrained systems where socket-based
parallel backends are unreliable.

## 10. Initial Target Ops

### First Target: `ucell`

Why first:

- it exposed a real bundle-scale pain point
- it is clearly chunk-safe across `cells`
- it produces merge-friendly outputs
- it is directly relevant to the signal-family toolkit

Important semantic note:

- `ucell` must still see the full feature universe within each cell chunk
- chunking by feature would not preserve UCell semantics

Expected merge:

- `signature_scores`
  - row-bind across cells
- `signature_summary`
  - recompute from merged scores and existing signature metadata

### Good Early Follow-Ups

- `addmodulescore`
- selected expression-summary ops
- existing feature-chunked trajectory ops if a shared helper simplifies them

### Later / More Careful Candidates

- `chromvar`
- kNN-based ops
- trajectory smoothing variants

These need explicit semantic review before joining the generic chunking surface.

## 11. Current Supported Surface

Today the chunking story is:

- generic metadata exists
- generic helper exists
- generic migrated ops exist:
  - `ucell`
  - `feature_trend_spearman`
- several feature-chunked ops still use op-local chunking:
  - `trajectory_de`
  - `trajectory_smooth`

So the truthful current claim is:

- the chunking surface is real
- but the migrated generic-op set is still intentionally small

## 12. Recommended Implementation Order

### Phase 1: Document The Contract

- finalize this draft
- reference it from workflow docs that depend on large-bundle execution

### Phase 2: Add Catalog Metadata

- extend op catalog entries with optional chunking metadata
- no behavior change yet

### Phase 3: Add Generic Chunk Helper

- partition a declared axis
- rerun the same runner over chunks
- merge a conservative set of primitive outputs
- emit chunk metadata in params

### Phase 4: Migrate `ucell`

- add chunk metadata to the `ucell` catalog entry
- implement merged summary recomputation
- add chunked-vs-unchunked equivalence tests on a small bundle

### Phase 5: Expand Selectively

- migrate additional chunk-safe ops
- only after proving that the helper is stable and worth generalizing

## 13. Testing Requirements

Every chunked op should have at least:

- a contract test for unchunked execution
- a chunked-vs-unchunked equivalence test on a small bundle
- a smoke test on a larger realistic bundle or subset

Generic chunk helper tests should cover:

- cell-axis partitioning
- feature-axis partitioning
- merge ordering
- summary recomputation
- provenance metadata recording

## 14. Non-Goals

Do not use this contract to:

- make every op chunkable by default
- hide semantic changes behind an execution flag
- move merge logic into clients
- create a parallel registry or separate workflow system
- weaken primitive contracts to make merging easier

## 15. Immediate Next Step

The next concrete implementation target should be:

- add chunking metadata support in the op catalog
- implement a conservative cell-axis chunk helper
- migrate `ucell` first

That is the smallest useful hardening increment that solves a real problem while
staying faithful to the engine design.
