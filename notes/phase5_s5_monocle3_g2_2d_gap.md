# S5 Monocle3 migration: generic G2 2D dimension mismatch

The migration order starts from scworkbench `a7c5b7f3a8eb8f70a5a3731c0d1144994c881218` and scwbTrajectory `d189cf8a3c1a84febd28cb7354a6ed5242f96c86`. The old-core Monocle3 oracle uses a two-dimensional source named `d1,d2`. A candidate registered pack fit reached `writers$declare_derived_fitted_axis()` and failed with `Derived fitted-cell selected dimensions changed or disappeared.` before any terminal write. The same error occurs with the independent `scwbV3Phase5::fit_derived_axis_relation` G2 fixture, so it does not depend on Monocle3 computation or relation sealing.

## Reproducer

After installing this exact core and `tests/fixtures/operation-pack-v3-phase5` into one temporary R library, run:

```sh
R_LIBS=/tmp/forge2-s5-m3/lib Rscript --vanilla tests/fixtures/phase5_s5_g2_2d_dimension_reproducer.R
```

The command exits **1**. Its output is:

```text
wb_space labels: cell_id,x,y
durable matrix labels: dim1,dim2
durable artifact rows: 0
Error: Derived fitted-cell selected dimensions changed or disappeared.
```

A control using the same fixture and a three-dimensional `d1,d2,d3` source with the same selected `dims = 1:2` succeeds and emits three relation rows (exit 0). Raw logs are `/tmp/forge2-s5-m3/g2-2d-reproducer.log` and `/tmp/forge2-s5-m3/g2-three-dimensional.log`.

The G2 grant retains selected labels `x,y` for the typed two-dimensional source. `R/operation_pack_v3_derived_fitted_axis.R` then reopens its durable parent through `.wb_as_coord_matrix(wb_space(...))`, where the labels are `dim1,dim2`; `.wb_operation_pack_v3_dfa_parent_assert_current()` rejects the mismatch. Runtime tracing confirmed `SELECTED_LABELS x,y DURABLE_LABELS dim1,dim2`. The generic G2 parent snapshot and recheck need one canonical dimension-label projection for two-dimensional spaces. Renaming or copying the Monocle3 source in the pack would bypass the accepted source authority and would change the frozen oracle input.

No method ownership changed. The attempted pack registration was withdrawn. Monocle3 fit/project migration, terminal-oracle comparison, lifecycle tests, and full qualification remain pending a generic G2 repair and its focused two-dimensional fixture gate. Phase 5 remains 19/24.
