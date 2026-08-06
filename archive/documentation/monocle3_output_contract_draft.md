# `monocle3_fit` Output Contract (Draft)

Status: draft (design discussion)

Goal: define a hybrid monocle3 output contract for scworkbench without forcing monocle3 into slingshot semantics.

## Principles

- Separation of compute and display.
- Primitives stay primitive; civilization lives in birth certificates.
- Do not force one method's semantics into another method's primitive shape.

## Scope (v1)

This draft is for `monocle3_fit` only.

`monocle3_fit` should be monocle3-driven but space-hybrid:
- scworkbench supplies the coordinates used for monocle3 graph learning / ordering
- monocle3 performs clustering / partitioning / graph learning on that supplied space
- rooting is explicit and reproducible

Curve overlays (`path_2d_family`) are out of scope for v1 unless graph-to-curve extraction is validated.

## Proposed Outputs

`monocle3_fit` returns:

1. `model` (`model_ref`)
- `kind = "model_ref"`
- `engine = "monocle3"`
- in-session payload may carry ephemeral CDS / graph internals needed for continuation
- promotion of monocle3 model artifacts may be deferred initially

2. `branch_membership` (`relation_family`)
- primary branch ambiguity representation
- one row per `(cell_id, lineage_key)` weighted relation
- `weight` captures branch/lineage membership strength / probability-like score
- optional `value` may later carry lineage-specific pseudotime, but v1 should not require it

3. `pseudotime` (`cell_vector`)
- rooted global pseudotime from monocle3 (`order_cells()` / `pseudotime(cds)`)
- continuous scalar per cell
- used for simple downstream analyses and coloring

## Why This Contract

Monocle3 commonly yields a branched principal graph with shared trunk and ambiguous branch membership near splits, including when run on a user-supplied atlas/latent space.

Therefore:
- `cell_vector` alone is insufficient (one scalar per cell)
- `cell_vector_family` is not ideal as the primary branch representation because it does not make weights first-class

`relation_family` is the correct semantic home for branch ambiguity.

Global pseudotime remains useful and should be emitted separately as `cell_vector`.

## `branch_membership` Semantics (`relation_family`)

Proposed semantics for v1:
- `key`: lineage / branch identifier (method-defined, reproducible within run)
- `weight`: membership strength for `(cell_id, key)`
- rows may overlap across keys for the same `cell_id` (shared trunk / ambiguity)

Normalization:
- preferred but not required in primitive contract
- if normalized per cell (`sum(weight)=1`), declare this in `run$params`
- if not normalized, declare scoring semantics in `run$params`

Optional future columns:
- `value` (lineage-specific pseudotime)
- `distance` (distance to branch/path)

## `pseudotime` Semantics (`cell_vector`)

- rooted global pseudotime returned by monocle3 after `order_cells()`
- one scalar per cell in the fitted cell universe
- values may contain `NA` for cells not assigned / unreachable depending on monocle behavior

This output is intentionally separate from branch membership weights.

## Key Invariants

`branch_membership` (`relation_family`)
- non-empty `cell_id`, `key`
- finite `weight` values (unless explicitly permitting `NA`)
- duplicate `(cell_id,key)` rows handled deterministically (prefer no duplicates)

`pseudotime` (`cell_vector`)
- names/cell ids align to fitted cell universe
- `value_type = "continuous"`

Cross-output invariants
- all cells in `pseudotime` should be within the fitted `cell_set` / `cell_ids`
- all cells in `branch_membership` should be within the fitted `cell_set` / `cell_ids`
- overlap between `pseudotime$cell_id` and `branch_membership$cell_id` should be explicit and test-covered

## Birth Certificate / Provenance Requirements

`run$params` must record enough to replay and interpret outputs:

- monocle3 version
- preprocess params (`method`, `num_dim`, normalization/scaling)
- reduction params (UMAP settings)
- source space mapping
  - resolved scworkbench `space_id`
  - note that scworkbench coordinates may be injected into monocle3's `"UMAP"` slot for compatibility
- clustering params (`k`, method, resolution, partition_qval, seed)
- graph params (`use_partition`, `close_loop`, graph controls)
- rooting inputs and resolved rooting
  - provided `root_cells` and/or `root_pr_nodes`
  - resolved `root_pr_nodes` used by monocle3
- branch membership semantics
  - weighting method / normalization policy
  - lineage key generation policy

## Coexistence With Slingshot

Slingshot should remain unchanged:
- `pseudotime` = `cell_vector_family`
- `curves` = `path_2d_family`

Monocle3 should not be forced into slingshot-shaped outputs.

Client ergonomics should be solved via trajectory capability discovery (what outputs are present), not by flattening method semantics.

## Trajectory Capability View (Future, Client/Engine Helpers)

A method-neutral helper can describe trajectory outputs by capability:

- pseudotime-capable (`cell_vector` or `cell_vector_family`)
- branch-membership-capable (`relation_family`)
- overlay-capable (`path_2d_family`)

This avoids method-specific UI branching in Shiny.

## Deferred (v2+)

- `monocle3_project` / `monocle3_curves` producing `path_2d_family` (if reliable graph-to-curve mapping exists)
- graph/branch diagnostic tables (optional `obs_table` outputs)
- optional `pseudotime_by_branch` (`cell_vector_family`) convenience output
- promotion/storage schema for `relation_family`
- plot wranglers for weighted branch memberships / ambiguity

## Open Questions

1. Should `branch_membership$weight` be normalized per cell in v1?
2. Should `branch_membership$value` (lineage-specific pseudotime) be included in v1 or deferred?
3. What is the lineage key policy for monocle3 branches (stable naming)?
4. Do we emit additional diagnostics (`obs_table`) summarizing branch graph / root / partitions in v1?
