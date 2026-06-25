# Trajectory Segment Join Contract

## Purpose

`trajectory_segment_join` creates an auditable composite trajectory from
separately fitted trajectory segments.

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

Each segment may also provide:

- `model`: model artifact/ref/primitive.
- `lineage_weights`: `cell_vector_family` membership weights.
- `path`: projected `path_2d_family`.
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

Within each segment, trajectory-derived artifacts must belong to the same
`trajectory_fit_id`.

This is enforced for the available segment-local artifacts:

- `model`
- `pseudotime`
- `lineage_weights`
- `path`

Across segments, different `trajectory_fit_id` values are allowed and expected.
The composite receives its own `trajectory_composite_id`.

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
- `local_pseudotime`
- `local_pseudotime_scaled`
- `local_weight`
- `segment_role`
- `composite_candidate`

A waypoint cell can appear twice, once as arrival in the upstream segment and
once as departure in the downstream segment.

## Composite One-Cell Pseudotime

The op also produces `composite_pseudotime`, a `cell_vector_family` with one
value per cell for the selected `composite_key`.

The default and currently only join policy is:

```text
waypoint_collapse
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
composite_pseudotime = segment_index - 1 + local_pseudotime_scaled
```

Cells present in two adjacent segments are declared waypoint cells and receive
the boundary value:

```text
segment 1 + segment 2 overlap -> composite_pseudotime = 1
segment 2 + segment 3 overlap -> composite_pseudotime = 2
```

The values are not averaged. This avoids fake precision at biological waypoints.

## Overlap Rules

Supported in v1:

- Cells unique to one segment.
- Cells shared by exactly two adjacent segments.

Rejected in v1:

- Cells shared by non-adjacent segments.
- Cells shared by more than two segments.

Those cases require a more explicit biological policy and should not be silently
collapsed.

## Outputs

`trajectory_segment_join` produces:

- `composite_pseudotime`: `cell_vector_family`, promotable.
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

Downstream trajectory dynamics may use promoted `composite_pseudotime` as a
pseudotime coordinate when the segmented route is the intended biological axis.

Reports should state that the pseudotime is a segmented composite, not a single
model-derived pseudotime.

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

Path stitching is deferred in v1. Parent path artifact IDs can be recorded in
the manifest, but no `composite_path` output is produced yet.

Only `waypoint_collapse` is implemented. Future policies may add weighted
handoff windows or explicit waypoint cell-set anchoring, but those should be
separate, named policies with tests and documentation.
