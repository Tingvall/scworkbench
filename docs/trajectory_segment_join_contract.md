# Trajectory Segment Join Contract

## Purpose

`trajectory_segment_join` creates an auditable composite trajectory from ordered
trajectory segments. New segments should follow the generic contract in
`docs/trajectory_segment_contract.md`. Existing fitted-model segment specs
remain valid.

This is needed when one automated start/end trajectory does not follow the
biological route of interest. The motivating T-cell case is:

```text
STHSC/root -> DN3 waypoint -> distal CD4 endpoint
```

The route is fitted as separate segments, for example:

```text
segment 1:  STHSC/root -> DN3
segment 2:  DN3 -> distal CD4 endpoint
```

The operation then derives a composite pseudotime coordinate from the segment
outputs while preserving the segment-local trajectory truth.

## Non-Goal: Model Merging

The op does not merge, edit, average, or fake-merge parent trajectory model RDS
objects.

A segmented composite trajectory is not a single Slingshot, Monocle, Palantir,
or other fitted model. It is a derived scworkbench object that references parent
segment artifacts.

The parent segment artifacts remain separate and inspectable.

## Inputs

The op accepts at least two segment specifications through `segments`.

Each segment must provide:

- `segment_id`: stable segment label.
- `pseudotime`: artifact/ref/primitive for a `cell_vector_family`.
- `lineage`: lineage key to use inside that segment, for example `L1`.
- `order`: segment order along the composite route.
- `source_kind`: recommended for new specs; defaults to `fitted_model`.
- `source_engine`: recommended for new specs; defaults from `source_kind` when
  possible.

Each segment may also provide:

- `model`: model artifact/ref/primitive.
- `lineage_weights`: `cell_vector_family` membership weights.
- `membership`: cell-vector artifact/ref, cell set, or cell IDs restricting
  segment cells.
- `confidence`: cell-vector or cell-vector-family segment support values.
- `path`: projected `path_2d_family`.
- `segment_manifest`: adapter manifest artifact/ref.
- `start_label`: human-readable biological start.
- `end_label`: human-readable biological end.

Example:

```r
segments <- list(
  list(
    segment_id = "segment1_sthsc_to_dn3",
    model = wb_ref_artifact("model_artifact_1", "model"),
    pseudotime = wb_ref_artifact("pseudotime_artifact_1", "pseudotime"),
    lineage_weights = wb_ref_artifact("weights_artifact_1", "lineage_weights"),
    lineage = "L1",
    order = 1,
    start_label = "STHSC/root",
    end_label = "DN3"
  ),
  list(
    segment_id = "segment2_dn3_to_cd4",
    model = wb_ref_artifact("model_artifact_2", "model"),
    pseudotime = wb_ref_artifact("pseudotime_artifact_2", "pseudotime"),
    lineage_weights = wb_ref_artifact("weights_artifact_2", "lineage_weights"),
    lineage = "L1",
    order = 2,
    start_label = "DN3",
    end_label = "distal CD4 endpoint"
  )
)
```

## Fit-Family Compatibility

Within fitted-model segments, trajectory-derived artifacts must belong to the
same `trajectory_fit_id`.

This is enforced for the available segment-local artifacts:

- `model`
- `pseudotime`
- `lineage_weights`
- `path`

Across segments, different `trajectory_fit_id` values are allowed and expected.
Non-fitted segments such as `space_path_bridge` may have no `trajectory_fit_id`,
but must declare `source_kind`, `source_engine`, and caveats. The composite
receives its own `trajectory_composite_id`.

Lineage names are not treated as globally comparable across fits. `L1` in
segment 1 and `L1` in segment 2 are used only after the user explicitly declares
the ordered segment route.

## Segment-Local Truth

The op produces `segment_local_table`, an `obs_table` with
`table_type = "trajectory_segment_local_membership"`.

This table has one row per cell per segment and preserves local segment values:

- `trajectory_composite_id`
- `cell_id`
- `segment_id`
- `segment_order`
- `segment_index`
- `lineage_id`
- `source_kind`
- `source_engine`
- `raw_pseudotime`
- `local_pseudotime`
- `local_pseudotime_scaled`
- `local_pseudotime_0_1`
- `local_weight`
- `confidence`
- `segment_role`
- `composite_candidate`

A waypoint cell can appear twice, once as arrival in the upstream segment and
once as departure in the downstream segment.

## Composite One-Cell Pseudotime

The op produces two `cell_vector_family` pseudotime coordinates with one value
per cell for the selected `composite_key`:

- `composite_pseudotime_unit_segment`: canonical audit coordinate with exact
  integer segment boundaries.
- `composite_pseudotime_cell_weighted_0_1`: display/comparison coordinate
  normalized to `[0, 1]` where segment lengths are weighted by segment-local
  cell counts.

The supported join policy is:

```text
exact_boundary_collapse
```

For each segment:

1. Local pseudotime is scaled to `[0, 1]` using segment-local min/max.
2. Ordered segments are mapped onto the composite scale:

```text
segment 1: 0 -> 1
segment 2: 1 -> 2
segment 3: 2 -> 3
```

Cells present in only one segment receive:

```text
composite_pseudotime_unit_segment = segment_index - 1 + local_pseudotime_scaled
```

Cells present in two adjacent segments are declared waypoint cells and receive
the boundary value:

```text
segment 1 + segment 2 overlap -> composite_pseudotime_unit_segment = 1
segment 2 + segment 3 overlap -> composite_pseudotime_unit_segment = 2
```

The values are not averaged. This avoids fake precision at biological waypoints.

## Space-Path Bridge Segments

`trajectory_space_path_segment` adapts `space_path_score` output into a formal
segment-compatible payload:

- `pseudotime`: `cell_vector_family`, derived from path arclength progress.
- `membership`: `cell_vector`, cells passing an explicit distance rule.
- `confidence`: `cell_vector_family`, distance-derived support.
- `segment_manifest`: `obs_table`, `trajectory_segment_manifest`.

Bridge pseudotime is path progress in `[0, 1]`, not a cell-rank coordinate.
The manifest records `source_kind = "space_path_bridge"` and
`source_engine = "space_path"` so reports cannot mistake it for a fitted model
segment.

For `composite_pseudotime_cell_weighted_0_1`, each segment occupies a fraction
of `[0, 1]` proportional to its segment-local cell count. Adjacent overlap cells
collapse to the corresponding weighted segment boundary.

## Overlap Rules

Supported by `exact_boundary_collapse`:

- Cells unique to one segment.
- Cells shared by exactly two adjacent segments.

Rejected:

- Cells shared by non-adjacent segments.
- Cells shared by more than two segments.

Those cases require a more explicit biological policy and should not be silently
collapsed.

## Outputs

`trajectory_segment_join` produces:

- `composite_pseudotime_unit_segment`: `cell_vector_family`, promotable.
- `composite_pseudotime_cell_weighted_0_1`: `cell_vector_family`, promotable.
- `segment_local_table`: `obs_table`, `trajectory_segment_local_membership`, promotable.
- `composite_manifest`: `obs_table`, `trajectory_segment_join_manifest`, promotable.
- `composite_membership`: `cell_vector`, promotable.

`composite_manifest` records:

- `trajectory_composite_id`
- parent `segment_id`
- segment order/index
- lineage key
- parent `trajectory_fit_id`
- parent model/pseudotime/weight/path artifact IDs where supplied
- biological labels
- join policy
- scaling rule
- overlap handling rule
- segment and waypoint counts
- caveats

## Downstream Use

Downstream trajectory dynamics may use either promoted composite pseudotime
coordinate when the segmented route is the intended biological axis. Use
`composite_pseudotime_unit_segment` when preserving exact segment boundaries is
more important than a normalized display range. Use
`composite_pseudotime_cell_weighted_0_1` when a `[0, 1]` coordinate weighted by
segment cell counts is desired.

Reports should state that the pseudotime is a segmented composite, not a single
model-derived pseudotime.

`trajectory_geneset_dynamics` and `trajectory_signal_dynamics` support this
explicit-pseudotime mode. Use `pseudotime` plus `pseudotime_key` instead of
`model`:

```r
wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "trajectory_geneset_dynamics",
  inputs = list(
    matrix = "RNA_log_norm",
    pseudotime = wb_ref_artifact("cell_vector_family_...", "composite_pseudotime_unit_segment"),
    pseudotime_key = "t_sthsc_dn3_distal_cd4",
    membership = wb_ref_artifact("cell_vector_...", "composite_membership"),
    namespace = "immune_gene_sets",
    n_bins = 50L
  )
)
```

The dynamics outputs record:

- `pseudotime_source_kind = "cell_vector_family"`
- `pseudotime_artifact_id`
- `pseudotime_key`
- `membership_artifact_id`
- `n_pseudotime_cells`
- `n_membership_cells`
- `n_cells_used`

The `segment_local_table` and `composite_manifest` should be kept with any
claim-supporting dynamics analysis because they explain:

- which parent fits contributed,
- which cells came from which segment,
- which cells were waypoint-collapsed,
- what local pseudotime and weights were available.

## When Not To Use

Do not use `trajectory_segment_join` when:

- the route ordering is not biologically justified,
- segment endpoints do not represent a coherent waypoint sequence,
- a single trajectory fit already represents the desired route cleanly,
- non-adjacent overlaps are biologically meaningful but unresolved,
- cross-fit lineage equivalence has not been explicitly chosen by the user.

## Current Limitations

`trajectory_segment_join` itself does not stitch paths. Display-geometry joining
is handled separately by `trajectory_segment_path_join`, which consumes ordered
parent `path_2d_family` artifacts and produces:

- `curves`: a derived `path_2d_family` for UMAP/embedding overlay.
- `path_manifest`: an audit table with parent path artifacts, segment order,
  point boundaries, labels, and caveats.

The joined path is explicitly display geometry. It is not a merged model and is
not evidence that a single continuous trajectory model was fitted across all
segments.

Only `exact_boundary_collapse` is implemented. Other policies are unsupported
and fail explicitly. Additional policies would need separate names, tests, and
documentation before use.
