# `monocle3_fit` Input Contract (Draft)

Status: draft (design discussion)

Companion to:
- `docs/monocle3_output_contract_draft.md`

Goal: define an advanced, hybrid (space-driven) monocle3 input/interface contract for `monocle3_fit` that is reproducible and suitable for non-interactive engine execution.

## Principles

- Monocle3 graph/order logic on a scworkbench-supplied space (hybrid approach).
- Explicit rooting for reproducibility (non-interactive safe).
- Advanced but disciplined: expose meaningful controls, not every internal knob.
- Birth certificates must capture enough to replay and interpret results.

## Scope (v1)

`monocle3_fit` runs the monocle3 pipeline end-to-end inside the engine:

1. build ephemeral `cell_data_set` (CDS)
2. inject scworkbench coordinates into monocle3 reducedDims slot (typically `"UMAP"`)
3. cluster cells / partitions on injected coordinates
4. learn principal graph
5. order cells (rooted)
6. emit primitives

No curve overlay output in v1 (unless separately validated).

## Required Engine-Level Inputs (scworkbench)

These are standard session/op inputs and should remain explicit:

- `space` (`space_2d`) (v1 recommended)
  - scworkbench coordinates used by monocle3 clustering / graph / ordering
  - injected into monocle3 reducedDims (likely `"UMAP"` slot for compatibility)
- `cell_set` / `cell_ids`
  - cell universe to fit on (same pattern as other ops)

Optional in v1 (implementation-dependent):
- `matrix` (`matrix`)
  - used to build a richer CDS backing object if needed
  - may be omitted in a minimal hybrid implementation that uses a dummy assay

Notes:
- `space` must align to the fitted cell universe.
- `cell_set` and `cell_ids` semantics should follow existing `wb_session_run_op()` behavior.
- Effective fitted cells are part of run provenance.

## Rooting (Required in v1)

Monocle3 `order_cells()` requires rooting for non-interactive reproducibility.

### Accepted root inputs (mutually exclusive)

1. `root_cells`
- character vector of cell ids
- preferred ergonomic path in scworkbench

2. `root_pr_nodes`
- character vector of monocle3 principal graph node ids (for example `Y_21`)
- advanced/low-level path

### Contract rules

- exactly one of `root_cells` or `root_pr_nodes` must be supplied
- both supplied: error
- neither supplied: error (v1)
- resolved root nodes used by monocle3 must be recorded in `run$params`

## Monocle3 Pipeline Parameters (Proposed v1)

### 1) Reduction Slot / Coordinate Injection

Monocle3 in the installed version appears to expect `"UMAP"` for `order_cells()` in practice.

v1 hybrid contract recommendation:
- inject scworkbench coordinates into monocle3 `reducedDims(cds)$UMAP`
- run monocle3 with `reduction_method = "UMAP"`

Proposed parameters:
- `monocle_reduction_slot` (default `"UMAP"`, effectively fixed to `"UMAP"` in v1)
- `source_space_id` (recorded resolved value, not user free-text)

### 2) Clustering / Partitions (monocle3-native)

- `cluster_k` (maps to monocle3 `k`)
- `cluster_method` (`"leiden"` or `"louvain"`)
- `cluster_num_iter`
- `partition_qval`
- `cluster_resolution` (nullable)
- `cluster_random_seed`

Notes:
- monocle3 clustering/partitioning is part of the method; not optional in v1.
- external cluster labels are not required in v1.

### 3) Graph Learning

- `use_partition` (default `TRUE`)
- `close_loop` (default `TRUE`)
- `learn_graph_control` (named list passthrough, optional)

Notes:
- if exposing `learn_graph_control`, record the exact sanitized list in `run$params`.

## Optional Helper Inputs (Not Core Semantics)

These may be useful later but are not required for v1:

- external cluster labels (`cell_vector`)
  - for QC/annotation only, not graph-learning substrate
- root selector (symbolic selector spec)
  - engine resolves to concrete `root_cells`, which are then recorded

Recommendation:
- keep v1 strict and explicit (concrete `root_cells` / `root_pr_nodes`)

## Validation Rules (v1)

Input-level validation before running monocle3:

- `space` resolves to valid `space_2d` primitive/source
- fitted cell universe non-empty
- injected coordinate matrix has expected dimensions (2D in v1)
- root input present and mutually exclusive (`root_cells` xor `root_pr_nodes`)
- all `root_cells` are in fitted cell universe
- all `root_pr_nodes` strings non-empty (full existence validation may occur after graph learning)
- numeric params finite and within sane ranges (e.g. `cluster_k >= 2`)

Method-stage validation:

- monocle3 clustering / graph / ordering stages succeed in order
- learned graph exists before `order_cells()`
- pseudotime extraction succeeds after ordering

## Provenance / Birth Certificate Requirements (`run$params`)

Must include:

- monocle3 version
- all clustering/graph params (resolved values)
- coordinate injection details:
  - source `space_id`
  - monocle3 reduction slot used (for example `"UMAP"`)
- rooting inputs provided (`root_cells` or `root_pr_nodes`)
- resolved `root_pr_nodes` actually used by monocle3
- fitted cell count
- space id / source references
- matrix id if used to construct CDS backing assay

Should include (if available):

- partition / cluster summary counts
- branch key generation policy metadata
- weighting semantics for `branch_membership`

## Interface Shape in `wb_op_interface()` (Draft)

Produces (from companion output contract):
- `model` -> `model_ref`
- `branch_membership` -> `relation_family`
- `pseudotime` -> `cell_vector`

Inputs (high-level UI/agent schema categories):
- source:
  - `space`
  - `cell_set` / `cell_ids`
  - optional `matrix`
- rooting:
  - `root_cells` xor `root_pr_nodes`
- coordinate injection:
  - (mostly fixed in v1) monocle3 `"UMAP"` slot + resolved `space_id`
- clustering:
  - k/method/resolution/seed/partition_qval
- graph:
  - `use_partition`, `close_loop`, `learn_graph_control`

## Coexistence With Slingshot (Reminder)

Slingshot requires labeled input clusters and should remain unchanged.

Monocle3 should not inherit that requirement in the input contract.

This is a method difference, not a UI inconsistency.

## Open Questions

1. Do we require `space_2d` in v1, or support higher-dimensional `space` with a separate display/projection later?
2. Is `matrix` required for CDS construction, or can v1 use a minimal dummy assay + injected coordinates?
3. Do we expose `learn_graph_control` as a structured schema or a passthrough list?
4. Do we support root selector refs in v1, or only concrete `root_cells` / `root_pr_nodes`?
5. How much of monocle3 clustering metadata should be emitted as additional tables in v1?
