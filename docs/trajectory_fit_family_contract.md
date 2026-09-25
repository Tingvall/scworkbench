# Trajectory Fit-Family Contract

Trajectory lineage labels are scoped to one trajectory fit. A label such as
`L1` is not globally meaningful and must not be used to combine artifacts from
different fits.

## Fit Identity

Trajectory-producing ops should record a `trajectory_fit_id` on run params and
trajectory-derived primitives/artifacts. For Slingshot this identity binds:

- `model_ref`
- `pseudotime` (`cell_vector_family`)
- `lineage_weights` (`cell_vector_family`)
- projected `curves` (`path_2d_family`)

New Slingshot fits are produced by the explicitly activated scwbTrajectory
operation pack. Its `scwbtrajectory::slingshot_fit` operation derives the fit
identity from the contained fitted model bytes; the same identity is
propagated by `scwbtrajectory::slingshot_project` and
`scwbtrajectory::slingshot_lineage_weights`. Historical core runs remain
inspectable without activating the pack; they are not reinterpreted as pack
runs.

## Compatibility Rule

Trajectory-derived artifacts are compatible only when they share:

- the same `trajectory_fit_id`
- the same trajectory engine when recorded
- the same lineage keys when both artifacts expose keys
- compatible cell universes when both artifacts expose cell IDs

Shared lineage labels alone are not sufficient. `L1` from fit X and `L1` from
fit Y must be treated as different biological/geometric objects unless a future
explicit mapping operation records equivalence.

## Validation API

Use:

```r
wb_trajectory_fit_info(bundle, artifact_or_primitive)
wb_trajectory_assert_fit_compatible(bundle, pseudotime, lineage_weights, model, curves)
```

By default, missing `trajectory_fit_id` is conservative and invalid for
cross-artifact trajectory operations. `allow_legacy = TRUE` exists only for
explicit review of old artifacts and emits a warning.

## Safe Slingshot Weight Backfill

Do not backfill accepted lineage weights by refitting. Use the existing accepted
Slingshot `model_ref`:

```r
wb_session_run_op(
  session,
  bundle,
  "scwbtrajectory::slingshot_lineage_weights",
  inputs = list(model = wb_ref_artifact(model_artifact_id, "model"))
)
```

This extracts `slingshot::slingCurveWeights()` from the accepted model payload,
preserving the original `trajectory_fit_id` and lineage mapping.
