# Historical S5 Monocle3 G2 2D dimension mismatch

This is a diagnostic captured at scworkbench `f2270926c85475bbea02c3fc48ee7b4ba7f2cd97`, before the generic G2 repair. The failure and pending-work statements below describe that historical checkpoint, not the final candidate.

The migration order starts from scworkbench `a7c5b7f3a8eb8f70a5a3731c0d1144994c881218` and scwbTrajectory `d189cf8a3c1a84febd28cb7354a6ed5242f96c86`. The old-core Monocle3 oracle uses a two-dimensional source named `d1,d2`. A candidate registered pack fit reached `writers$declare_derived_fitted_axis()` and failed with `Derived fitted-cell selected dimensions changed or disappeared.` before any terminal write. The same error occurs with the independent `scwbV3Phase5::fit_derived_axis_relation` G2 fixture, so it does not depend on Monocle3 computation or relation sealing.

## Reproducer

After installing the historical `f227092` core and `tests/fixtures/operation-pack-v3-phase5` into one temporary R library, the following command reproduced the failure:

```sh
R_LIBS=/tmp/forge2-s5-m3/lib Rscript --vanilla tests/fixtures/phase5_s5_g2_2d_dimension_reproducer.R
```

At that historical checkpoint, the command exited **1**. Its output was:

```text
wb_space labels: cell_id,x,y
durable matrix labels: dim1,dim2
durable artifact rows: 0
Error: Derived fitted-cell selected dimensions changed or disappeared.
```

A control using the same fixture and a three-dimensional `d1,d2,d3` source with the same selected `dims = 1:2` succeeds and emits three relation rows (exit 0). Raw logs are `/tmp/forge2-s5-m3/g2-2d-reproducer.log` and `/tmp/forge2-s5-m3/g2-three-dimensional.log`.

At `f227092`, the G2 grant retained selected labels `x,y` for the typed two-dimensional source. `R/operation_pack_v3_derived_fitted_axis.R` then reopened its durable parent through `.wb_as_coord_matrix(wb_space(...))`, where the labels were `dim1,dim2`; `.wb_operation_pack_v3_dfa_parent_assert_current()` rejected the mismatch. Runtime tracing confirmed `SELECTED_LABELS x,y DURABLE_LABELS dim1,dim2`. The generic G2 parent snapshot and recheck needed one canonical dimension-label projection for two-dimensional spaces. Renaming or copying the Monocle3 source in the pack would have bypassed the accepted source authority and changed the frozen oracle input.

At `f227092`, no method ownership had changed and the attempted pack registration was withdrawn. Monocle3 migration and qualification were pending the generic G2 repair.

## Resolution

The generic repair in scworkbench `d8feee3b3da96c9a7616dd654e7387da681f2c32` authenticates the durable `dim1,dim2` labels consistently. The reproducer now exits 0. The final qualified Monocle3 candidate pair is scworkbench `6401a00da4512da6145d05d62dc3a5c66c7661bc` with scwbTrajectory `7e8c3fc907b1069478a0ef3b4851d2ea6feddb87`; both methods have moved to the pack in that candidate. Phase 5 remains 19/24 until independent acceptance and Controller integration.
