# Development checkpoint before coordinated qualification

Baseline is the completed repaired core 8f53e950, not the untouched primary
96cbf880. This isolated branch changes no pack, profile or shared protocol file.
The agreed Python candidate is 0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e.
Source/byte rules and conditional Sable review boundaries are in SOURCE_COVERAGE,
the 36-row inventory and prospective budget files. Final acceptance is not
inferred from these development results.

Fresh immutable core library: `/tmp/scwb-engine-simplification-forge-20261018/library_dev6`.
Installation exited 0. The combined focused command was:

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/dev6_focused_lifecycle.log /tmp/scwb-engine-simplification-forge-20261018/dev6_focused_lifecycle.exit -- /usr/bin/time -v Rscript notes/engine_simplification/run_focused.R /tmp/scwb-engine-simplification-forge-20261018/library_dev6 lifecycle
```

Literal terminal accounting:
`CONTRACT TEST SUMMARY files=17 discovered=72 executed=72 passed=72 skipped=0 failed=0 excluded=0 accounted=72`.
Exit 0, wall 12:00.63, peak RSS 795512 KiB. Logs retain warnings, including
intentionally missing/corrupt checkpoint fixtures; no warning is a silent pass
substitution. Earlier failed development logs remain at the task root, including
the fixed table row-name/lazy-fold defects and a concurrent-reinstallation
harness mistake. They are not relabeled as successful gates.

The assembled bounded development lifecycle command was:

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/dev6_bounded_workflow.log /tmp/scwb-engine-simplification-forge-20261018/dev6_bounded_workflow.exit -- /usr/bin/time -v Rscript notes/engine_simplification/bounded_development_workflow.R /tmp/scwb-engine-simplification-forge-20261018/library_dev6 /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/dev6-bounded-workflow
```

Exit 0, `BOUNDED_DEVELOPMENT_DURABLE_FOUR_OP_PROMOTE_FINALIZE_READONLY_OK`,
wall 88.92 s, peak RSS 962896 KiB, default dense guard 256 MB. Earlier assembled
development wall was 173.43 s; this is a 48.7% reduction on that reduced fixture,
NOT a comparison to the full repaired Xenopus workflow or equivalent direct
execution. Phase times: normalization 4.484, HVG 9.811, PCA 20.001, UMAP 9.939,
promotion 26.834, finalize 2.795, reopen .780 s. Normalization and the zero-library
cell matched the independent reference. The harness's extra final close emitted
an already-disconnected warning, retained in the log. Installed library hashes
were unchanged. Profiling shows remaining canonical, provenance and publication
costs; do not claim these reduced-fixture results meet the real-world budgets.

Compressed complete logs, numeric sidecars and timing/census CSVs are retained in
`development_evidence/`. The final supervisor uses a separate immutable installed
library and fresh evidence/chambers. It must preserve actual discovery, named
fixture skips and performance misses, and complete the real fresh import through
recipient validation before any final disposition.
