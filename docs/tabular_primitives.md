# Tabular Primitives and Artifact Promotion

This document defines the engine contract for tabular analysis outputs.

## Why

Many ops produce tabular outputs that are neither per-cell vectors nor geometry:

- differential expression tables
- marker tables
- QC summaries
- pathway/sample/cluster summaries
- trajectory DE tables
- trajectory-smoothed summary tables

To avoid ad-hoc output kinds, the engine supports two canonical tabular primitives.

## Primitive Kinds

## `feature_table`

Use for feature-indexed outputs (rows are genes/features).

Required:

- `kind = "feature_table"`
- `table` is a `data.frame`
- `table` includes `feature_id`

Optional:

- `table_type` (e.g. `de_wilcox`, `markers_topn`)
- `meta` list

Constructor:

- `wb_prim_feature_table(table, table_type = "generic", meta = list())`

## `obs_table`

Use for generic entity-indexed outputs (sample, cluster, pathway, etc.).

Required:

- `kind = "obs_table"`
- `table` is a `data.frame`

Optional:

- `table_type` (e.g. `qc_summary`)
- `entity_kind` (e.g. `sample`, `cluster`, `pathway`, `generic`)
- `meta` list

Constructor:

- `wb_prim_obs_table(table, table_type = "generic", entity_kind = "generic", meta = list())`

## Artifact Storage

Promoted tabular primitives are persisted using:

- `artifacts` (core metadata row; `type` is `feature_table` or `obs_table`)
- `artifact_tables` (table metadata)
- `artifact_table_rows` (row-wise JSON payload, ordered by `row_idx`)

This keeps the promotion path generic while preserving provenance in `artifacts`.

Trajectory outputs intentionally use these existing primitive kinds rather than
introducing trajectory-specific primitive types.

Examples:

- `trajectory_de` -> `feature_table`
- `trajectory_smooth` -> `obs_table`
- `trajectory_signature_smooth` -> `obs_table`
- `trajectory_geneset_dynamics` -> `obs_table`
- `trajectory_signal_dynamics` -> `obs_table`

What makes them trajectory-specific is:

- `table_type`
- table column schema
- `meta`
- provenance / source op

## Loading

`wb_art_load(bundle, artifact_id, expected_kind=...)` reconstructs:

- `feature_table` -> `wb_prim_feature_table(...)`
- `obs_table` -> `wb_prim_obs_table(...)`

## Wrangler (Client Display)

For outward display/export, use the table wrangler layer:

- `wb_primitive_to_table(prim, key = NULL, include_context = TRUE)`
- `wb_client_load_table(bundle, ref, ...)`

This returns normalized `data.frame` output with stable ordering:

- feature tables: `feature_id` first
- obs tables: entity-like id columns first when present
- vector-family tables: `key`, `cell_id`, `value`

`include_context=TRUE` appends display-safe context columns like `kind`,
`table_type`, and `entity_kind`.

Clients should treat `table_type` as an important contract signal. Primitive kind
alone is usually not enough for the right display or navigation behavior.

## Promotion Rules

- Operators promote registered session outputs with
  `wb_session_promote_current()`, selecting only declared promotable terminals
  and respecting the complete linked closure. `wb_promote_analysis()` and
  internal promoter maps are engine mechanisms, not pack-runner write authority.
- `feature_table` and `obs_table` use the generic engine promotion kernel.
- `feature_table` requires `feature_id` column at promotion time.

## Current Ops

- `scwbstatistics::de_wilcox` -> output `de_table` (`feature_table`, promotable;
  requires explicit `scwbStatistics` activation)
- `scwbstatistics::markers_topn` -> output `markers` (`feature_table`, promotable;
  requires explicit `scwbStatistics` activation)
- `scwbtrajectory::trajectory_de` -> `de_table` (`feature_table`, promotable)
- `scwbtrajectory::trajectory_smooth` -> `trend_table` (`obs_table`, promotable)
- `scwbtrajectory::trajectory_signature_smooth` -> `signature_table` (`obs_table`, promotable)
- `scwbtrajectory::trajectory_geneset_dynamics` -> `signature_table`, `dynamics_table`, `top_sets`, `driver_table`, `driver_curve_table`, `fit_summary` (`obs_table`, promotable)
- `scwbtrajectory::trajectory_signal_dynamics` -> `signal_table`, `dynamics_table`, `top_signals`, `fit_summary` (`obs_table`, promotable)

The model-backed dynamics operations require a retained model. Their separate
`scwbtrajectory::trajectory_geneset_dynamics_explicit` and
`scwbtrajectory::trajectory_signal_dynamics_explicit` counterparts take typed
pseudotime and an explicit key. Activate the pack before either route.
