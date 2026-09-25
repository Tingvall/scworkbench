# Phase 5 S2 retained old-core bundle

`phase5_s2_retained_old_core_bundle.tar.gz` was produced with an isolated install
of scworkbench `c897c93bdb88ac0f78a1ca37e31a1ab2c047c695`, before the six
S2 operations left its production catalog. SHA-256:
`e6b2a277b2ff614d44f04ab8bbb80fbd3339f82886df8b0168d437733d67051b`.

The fixture contains small synthetic terminal tables promoted under the old
`trajectory_de`, `trajectory_smooth`, `trajectory_geneset_dynamics`, and
`trajectory_signal_dynamics` definitions. It did not execute those scientific
methods. It tests read-only inspection, unchanged historical `source_op` and
`table_type` values, and navigation after migration. Current core must not
translate the stored names into active operation definitions.

Construction used `git archive c897c93 | tar -x` into a temporary source tree,
`R CMD INSTALL --no-test-load` into a temporary library, then old-core
`wb_init_bundle()`, `wb_new_run()` with typed synthetic terminals, and
`wb_promote_analysis()` before `wb_close_bundle()`. The frozen archive is the
input to `test_phase5_s2_core_ownership_contract` and `test_navigation_contract`.
