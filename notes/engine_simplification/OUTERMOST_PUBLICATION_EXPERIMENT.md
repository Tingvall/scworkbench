# Outermost publication route: not selected

Isolated source `0e4302af1f76d4b8e5289635cdf79c6cd3fde318` is preserved,
not integrated. The experiment passes the actual live bundle handle to the
existing publication-witness route at a qualified outermost mutation boundary;
nested ownership and uncertain connections retain their previous route. It does
not change publication identities or source authority.

```sh
SCWB_OUTERMOST_0E_RETRY_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_outermost_live_0e_qualification_retry.sh
```

Terminal exit0: four focused tests passed, zero skips/failures. Three actual
unchanged top-level boundary cycles had median elapsed5.971s old /5.933s new:
0.636% improvement, **MISS** the prospective25% requirement. Peak RSS240052 /
236268KiB passes the+10% limit. Separate instrumented censuses and exact table,
state, public-surface and source-filesystem comparisons passed. No whole-workflow
speed improvement follows from this experiment. The additional routing condition
is not justified by the measured benefit and is excluded from the assembly.

The initial `outermost_0e4302_qualification` install failed (numeric exit1): its
harness replaced `R_LIBS_USER` and hid existing dependencies. The separately
named retry retains normal dependency discovery, captures the actual dependency
paths/versions, and installs both Git-derived sources cleanly. The first failure
and all raw logs, commands, status sidecars, installed hashes, timing and census
records remain unchanged; they are not relabeled as passing evidence.
