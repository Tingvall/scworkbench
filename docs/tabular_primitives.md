# Tabular Primitives and Artifact Promotion

This document defines the engine contract for tabular analysis outputs.

## Why

Many ops produce tabular outputs that are neither per-cell vectors nor geometry:

- differential expression tables
- marker tables
- QC summaries
- pathway/sample/cluster summaries

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

## Loading

`wb_art_load(bundle, artifact_id, expected_kind=...)` reconstructs:

- `feature_table` -> `wb_prim_feature_table(...)`
- `obs_table` -> `wb_prim_obs_table(...)`

## Promotion Rules

- Only outputs declared in op `promotable` are promoted by `wb_promote_analysis()`.
- `feature_table` and `obs_table` are supported by promotion kernel mapping in `.wb_promoters_by_kind()`.
- `feature_table` requires `feature_id` column at promotion time.

## Current Ops

- `de_wilcox` -> output `de_table` (`feature_table`, promotable)
- `markers_topn` -> output `markers` (`feature_table`, promotable)

