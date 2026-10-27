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

## Numeric storage fidelity

New `wb_prim_feature_table()` and `wb_prim_obs_table()` values declare a
`table_storage` version and column types. Promotion stores this declaration in
a versioned envelope in the existing `artifact_tables.meta_json`, selected by a
writer-owned `table_storage` marker in artifact provenance JSON; user metadata
remains inside the envelope and getters return it as `meta`. Ordinary integer,
double, logical and character columns retain their types, including empty and
all-missing columns. Doubles use 17-digit JSON encoding. Numeric missing values
are JSON null; the declared double type also distinguishes the supported NaN,
Inf and -Inf encodings from character values with those spellings. Display
formatting does not define persisted scientific precision.

Column declarations are part of content identity. Construct a new primitive
when changing column names or types. New identities use
`scworkbench.content.table.typed-row-json-fold.v1`, with a
`scworkbench.payload.table.stream.v2` header. Historical primitives without a
storage declaration and historical table metadata retain their existing reader
and `scworkbench.content.table.row-json-fold.v1` preimage. No historical precision
is recovered or rewritten. Replaying an old method with a new constructor can
produce a new scheme; equality across these schemes is not asserted.

Attributed columns keep their historical projection rather than acquiring an
R class-preservation guarantee: factors and Dates reopen as their JSON labels.
List and matrix columns have no supported scalar round-trip contract and new
publication rejects them explicitly. Empty attributed columns remain unsupported.
Ordinary numeric columns alongside supported attributed columns retain the new
precision and missingness guarantees.

The paired PyBench implementation reads this format through
`pybench.artifact_table(bundle, artifact_id)`. It returns ordered column names,
declared types, metadata and row dictionaries; this explicit getter materializes
the requested table. JSON null becomes Python `None`, distinct from double NaN.
Factor and Date columns retain only the legacy label projection described above.

Protocol-v2 Python table outputs opt in with an R-issued output specification:
`table_storage = list(format = "scworkbench.table.typed-json.v1", columns =
list(names = c("feature_id", "p_adj"), types = c("character", "double")))`.
Core preregisters the storage marker and checks the returned schema and content
before publication. Python writes only its existing scoped payload tables, not
artifact provenance. Its payload writer receives the same declaration through
`table_storage`; omitting it retains legacy storage. Supported Python writer
types are integer (R's non-missing 32-bit range), double, logical and character.
Construct a new output declaration when changing the ordered column schema.

## Artifact discovery and retained provenance

`wb_art_list(bundle)` now returns discovery metadata without the
`provenance_json` column. Its SQL excludes that field; it does not load a
payload or deserialize provenance. Artifact IDs, type/name/description,
source operation, input references, provenance snapshot/lineage references,
and lifecycle fields remain available. Ordering is `created_at` descending,
then `artifact_id` descending for ties; type/history filters retain their meaning.

Use `wb_art_list(bundle, include_provenance = TRUE)` when full registry rows
are needed. Existing callers that read `provenance_json` must opt in explicitly.
Omission is not an assertion that provenance is absent. Typed and legacy
artifact loading/slicing is unchanged. Full provenance and user-provided
names/descriptions can still be large; this API change does not bound retained
storage, explicit detailed inspection, or arbitrary user metadata. Python's
listing still returns full registry rows by default; R/Python default parity
is not claimed.

Public table queries (`wb_art_table_slice()` and `wb_art_table_distinct()`) accept
stored column names unchanged, including punctuation and Unicode. Member paths
use JSON string escaping and SQL parameter binding; selection values are also
bound parameters. Unknown columns are errors. Typed tables validate names against
their column declaration, including empty tables; legacy tables use the first
stored row's keys (an empty legacy table has no declared queryable columns).

Omitting `filters` (NULL or `list()`) leaves a query unrestricted. Each named
selection is an IN condition, combined with AND. An empty selection, including
NULL or a selection containing only NA, matches no rows. Mixed NA/value
selections ignore NA and retain the other values; this does not introduce SQL
NULL matching. Filter containers must be lists with unique, non-empty column
names. Empty selections use a constant-false SQL predicate without loading table
payloads.
