# Observational model-repair planner: absolute-cost check

Installed source `a726aee794ca3a700076103b74d899feb9cf5d58`, observed using
the unchanged fixture at source
`4d5e7ae915076be38ec4817509ab933e84c836d9`; the installed runtime is the
authoritative runtime pin. Installed DLL SHA256:
`ba885cadc1f17f3aed6b74cd7d64e68925e371045eef6a4e55e13762c5f7136d`.

```sh
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/model_planner_a726_measurement.log /tmp/scwb-engine-simplification-forge-20261018/model_planner_a726_measurement.exit -- /usr/bin/time -v -o /tmp/scwb-engine-simplification-forge-20261018/model_planner_a726_measurement.time Rscript --vanilla /tmp/scwb-engine-simplification-forge-20261018/measure_model_planner_boundary.R /tmp/scwb-engine-simplification-forge-20261018/combined_a726_install/library /home/dirk/Projects/.scworkbench-worktrees/engine-invocation-consolidation-forge-20261018 /tmp/scwb-engine-simplification-forge-20261018/model_planner_a726_measurement
```

Exit0. Five consecutive public `dry_run=TRUE` calls took respectively
0.015/0.014/0.012/0.013/0.013 seconds, each below the previously declared
0.1-second small-fixture budget. Exact returned plans, all file SHA256/size
inventories (including SQLite SHM), SQL `total_changes` and `data_version`
remain identical. The SQL observer is established before the initial file
inventory, avoiding the previously diagnosed observer-induced SHM change.
Fixture creation, observer queries and file inventories are outside the timer.
This is a same-process small-fixture absolute check, not a cold-start,
large-history or whole-workflow performance claim. The separately qualified
three planner contracts retain their migration/publication-call spies.
