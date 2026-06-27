# Generic Trajectory Segment Contract

## Purpose

Composite trajectories are assembled from ordered trajectory-like segments.
The segment contract defines the common interface that lets fitted models,
space-path bridges, imported pseudotime, manual pseudotime, graph paths, and
future engines participate in a composite without pretending they came from one
merged model.

The contract is deliberately engine-neutral. Slingshot, Monocle3, Palantir,
space paths, and curated bridges may all supply segments when they expose the
same segment-local fields and provenance.

## What Is A Trajectory Segment?

A trajectory segment is a local, directed developmental interval with:

- one segment identity,
- one ordering position in a composite,
- one cell-level local pseudotime coordinate,
- optional membership/confidence values,
- optional display geometry,
- explicit source provenance and caveats.

A segment is not required to be a fitted model. A segment can be a fitted
lineage, a path-scored bridge, an imported coordinate, or a manually curated
coordinate, provided the source is declared.

## Source Kinds

Allowed `source_kind` values:

- `fitted_model`: segment derived from trajectory artifacts such as model_ref,
  pseudotime, lineage weights, and projected paths.
- `space_path_bridge`: segment derived from a `space_path_family` and
  path-relative cell scores.
- `graph_path_bridge`: segment derived from graph traversal or graph distances.
- `imported_pseudotime`: segment imported from an external table/source.
- `manual_pseudotime`: segment curated explicitly by a user or script.
- `composite`: segment derived from an already existing composite trajectory.

Allowed `source_engine` values:

- `slingshot`
- `monocle3`
- `palantir`
- `space_path`
- `manual`
- `imported`
- `graph`
- `unknown`

The engine does not infer source kind from labels. The segment-producing adapter
must declare it.

## Required Fields

Every normalized segment must expose:

- `segment_id`
- `segment_order`
- `source_kind`
- `source_engine`
- `lineage_id` or key
- `cell_id`
- `raw_pseudotime`
- `local_pseudotime_0_1`
- `membership_value`
- `start_label`
- `end_label`
- `normalization_rule`
- `boundary_policy`
- `parent_artifacts`
- `caveats`

The local segment table stores one row per cell per segment. A cell can appear
in multiple segment-local rows when it is part of a waypoint overlap.

## Optional Fields

Segments may also expose:

- `source_pseudotime_key`
- `source_path_key`
- `trajectory_fit_id`
- `trajectory_composite_id`
- `raw_pseudotime_units`
- `confidence`
- `confidence_rule`
- `distance_to_path`
- `distance_threshold`
- `path_progress`
- `display_path`
- `path_artifact_id`
- `model_artifact_id`
- `pseudotime_artifact_id`
- `membership_artifact_id`
- `confidence_artifact_id`
- `manifest_artifact_id`

Optional fields must remain explicit. Missing display geometry must not prevent
analytical pseudotime joining, and missing model metadata must not be silently
invented.

## Coordinate Model

Each segment preserves three coordinate layers:

1. `raw_pseudotime`

Native/source coordinate. For fitted models this is model pseudotime. For
space-path bridges this is arclength progress along the path. It is never
overwritten.

2. `local_pseudotime_0_1`

Segment-local normalized coordinate. The v1 default is min-max scaling over the
finite segment cells. For space-path bridges, path progress is already in
`[0, 1]`, so the rule is `path_progress_0_1`.

3. `composite_pseudotime_unit_segment`

Canonical audit coordinate after joining:

```text
segment 1: 0 -> 1
segment 2: 1 -> 2
segment 3: 2 -> 3
```

This coordinate preserves exact waypoint boundaries and is the canonical
coordinate for auditability.

An optional future coordinate,
`composite_pseudotime_cell_weighted_0_1`, may normalize the whole composite by
cell count or declared biological length. It is display/analysis convenience,
not the canonical audit coordinate.

## Boundary Policy

The v1 boundary policy is:

```text
exact_boundary_collapse
```

Rules:

- A cell in one segment receives that segment's unit-segment mapped coordinate.
- A cell in two adjacent segments collapses to the exact shared boundary.
- A cell in non-adjacent segments errors.
- A cell in more than two segments errors.
- No averaging or interpolation is performed in v1.

This is the formal version of the previous `waypoint_collapse` behavior.
`waypoint_collapse` remains an accepted alias for compatibility.

## Space-Path Bridge Segments

A space-path bridge segment is created from:

- `space_path_family`
- path-relative scores from `space_path_score`
- optional candidate cell universe or membership
- optional distance threshold or distance quantile
- segment labels and identity
- optional projected `path_2d_family`

Canonical bridge pseudotime is:

```text
progress_along_path = nearest_path_arclength / total_path_arclength
```

This is emitted as raw pseudotime and local pseudotime. Cell rank is not the
canonical bridge coordinate.

Bridge membership is transparent:

- `distance_to_path <= distance_threshold`, or
- `distance_to_path <= quantile(distance_to_path, distance_quantile)`

Bridge confidence is distance-derived. V1 stores confidence for inspection and
filtering, but downstream statistics are not silently weighted by confidence.

## Display Geometry

Analytical pseudotime and display geometry are separate.

- `space_path_family` is analytical high-dimensional geometry.
- `path_2d_family` is display geometry for overlays.
- A composite display path can be derived from segment display paths.

Path-only display geometry must not be treated as analytical pseudotime unless a
segment adapter explicitly computes cell-level pseudotime.

## Downstream Consumers

The resulting composite remains compatible with:

- `trajectory_geneset_dynamics` explicit-pseudotime mode.
- `trajectory_signal_dynamics` explicit-pseudotime mode.
- UMAP/path overlay workflows through `path_2d_family`.
- future explicit-pseudotime trajectory smoothing ops.

Downstream consumers should depend on `cell_vector_family` pseudotime and
manifest metadata, not engine-specific model internals.

## Allowed Claims

Allowed:

- A composite trajectory substrate was assembled from heterogeneous segment
  sources.
- A bridge segment was curated, space-path-derived, graph-derived, imported, or
  manual, when declared in the manifest.
- Downstream dynamics were evaluated along the composite pseudotime coordinate.
- Segment-local truth and parent artifacts are auditable.

Forbidden:

- Claiming a composite is one fitted model.
- Hiding curated/manual guidance.
- Treating display-only path geometry as analytical pseudotime.
- Silently mixing incompatible segment sources without manifests.
- Treating lineage labels from different fits as globally interchangeable.

## V1 Implementation Shape

V1 uses existing primitives:

- segment pseudotime: `cell_vector_family`
- segment membership: `cell_vector`
- segment confidence: `cell_vector_family` or `cell_vector`
- segment manifest: `obs_table`
- composite pseudotime: `cell_vector_family`
- composite membership: `cell_vector`
- composite local table: `obs_table`
- display geometry: `path_2d_family`

No new primitive is required in v1. The contract is enforced through adapter
outputs, manifest fields, and join validation.

## Migration From Existing Segment Join

Existing `trajectory_segment_join` list specs remain valid as fitted-model
segment specs. They are normalized internally into the generic contract.

New source kinds should be introduced as adapters rather than by extending the
join op with engine-specific branches. The join op should consume normalized
segment-local tables and manifests regardless of source.
