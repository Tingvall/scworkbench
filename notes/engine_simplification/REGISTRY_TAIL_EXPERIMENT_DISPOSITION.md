# Same-owner registry-tail experiment: not selected

Preserve the isolated clean checkpoint
`9954387ae998a5de0463330da0e1849afacd7ffe` (test-only descendant of installed
runtime `b643b90dee20978918926d6f4b8c3022e1a96e96`). Do not incorporate its
private observation machinery into this assembled candidate: the measured
complete-operation benefit did not meet its prospective cost/complexity budget.
The ordinary independent directory-publication snapshot remains in place.

Evidence root `T=/tmp/scwb-engine-simplification-forge-20261018`.
The original197 focused run remains33 executed/27 passed/6 failed. Corrected
b643 remains33 executed/32 passed/1 failed, not a manufactured33/33. Its last
test assumed an observation survived the actual empty TEMP schema cookie reset
2->0 during snapshot resource restoration. The runtime correctly declined it.
A test-only correction explicitly verifies that decline, then creates a fresh
stable observation. Its separate one-test retry passed with no skips/failures:
`T/registry_tail_9954387_corrected_retry/corrected_one.log`, SHA256
`100dc2bcc7a3c5130076db35fbfe30c5c0a67a1d7fce820a8e716c59c8c08181`.
No TEMP guard was removed and runtime R/src did not change for this retry.

The six fresh matched plain public durable-HVG trials all exited0, including
actual output identities/reloads, complete receipts, checkpoint and source
filesystem/SQL guards. There were no instrumentation spies inside timing.
All18 outer gates are retained:17 exited0; the final budget comparison and
supervisor exited1. Do not label this experiment performance-qualified.

| Metric | Fresh parent | Candidate | Original fixed ceiling | Result |
|---|---:|---:|---:|---|
| Complete public HVG, median seconds | 1.464 | 1.273 | 1.0872 | MISS |
| Whole-process peak RSS, KiB | 703016 | 721088 | 792664.4 | PASS |
| Unaffected-operation ceiling, seconds | 1.464 | 1.273 | 1.5149 | PASS |

The pre-implementation parent median was1.359 seconds. The observed candidate
improves that by about6.3%, and the fresh matched parent by13.0%; neither meets
the fixed20% target. These are small-fixture whole-operation observations, not
estimates of Xenopus savings, a direct independent algorithm comparison or
proof of a statistically significant speedup. Six normal BPCells compression
warnings remain visible. No retiming or posthoc threshold revision is used.

Actual CSVs in `T/registry_tail_9954387_matched_component/`:

- `UNCHANGED_FIXED_PROSPECTIVE_BUDGET_RESULTS.csv`, SHA256
  `c481cf57a47cfd67cdd24a6773cb0dac3522fb7e2485e93080d0981ab23e5a83`.
- `all_six_fresh_plain_timings.csv`, SHA256
  `6546aa7d2614c10a667ac1ba2d3abb1305efbe14265ddcd38d6ccc631e126bfc`.

Raw supervisor log SHA256:
`77ee73b45d5fb1cdb95635021a1c7742518bd3b8e3fc813e734d045825758953`.
All original failures, diagnostics, source reviews, exact installations, logs
and sidecars remain untouched. This disposition is not a waiver of any other
budget or acceptance requirement, and is not a final handoff.
