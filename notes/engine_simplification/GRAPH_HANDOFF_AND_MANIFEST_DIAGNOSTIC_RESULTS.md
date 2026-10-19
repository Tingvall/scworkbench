# Graph handoff experiment and subsequent manifest diagnosis

`T` = `/tmp/scwb-engine-simplification-forge-20261018`. This is evidence
reconciliation, not a final handoff or an optimization acceptance. No graph
handoff runtime change is selected into this branch by this note.

## Fresh native graph handoff: correctness qualified, timing targets missed

Experimental source `b1dcb52599d26f75de7e2ca2d00f3cf647ea55d9` independently
imports/validates the native output once and privately retains that exact stage
for output construction. Fresh original request/receipt, full closure, effective
resource admission and original physical byte proofs remain independent.
Recovery, transfer, Python and unsupported closures retain the original path.
Sable's source disposition cleared corrected b1, not a performance claim.

Actual clean installed focused run: 10 files, 39 discovered/executed/passed,
zero skipped/failed, `T/graph_handoff_b1dcb52_install/focused.log`, all eight
numeric gates and outer exit zero. Elapsed 11:07.05; the forced small-resource
case alone took 470.687 seconds. Ten unique `Already disconnected` warning
entries were printed twice (explicit `warnings()` plus automatic printing),
not twenty independent warnings; their cause remains unassigned. BPCells
compression warning retained. This run is not warning-free.

Test-only descendant `649c740592d62eac7eb7fadbaa6020e7044e9784` ensures each
fixture-owned temporary root disappears before its test returns (outer
`tryCatch(..., finally=...)`), correcting reliance on eventual process cleanup.
A distinct installed six-test retry passed, zero skips/failures, eight gates
and outer exit zero: `T/graph_handoff_649c740_cleanup_retry/corrected_six.log`.
Runtime R/src bytes are unchanged. This is not a fabricated fresh 45-test run.
The same ten warning entries remain unassigned.

Three fresh plain public graph lifecycles plus a separate census:
`T/public_abi4_graph_649c740_candidate_measurement`. Ten gates exited zero;
the final fixed-budget gate and outer supervisor exited one. All science,
promotion, recipient, SDK/source filesystem and identity checks passed.

| Criterion | Frozen parent | Candidate | Fixed ceiling | Result |
| --- | ---: | ---: | ---: | --- |
| Public run median seconds | 18.042 | 15.562 | 14.4336 | MISS |
| Complete lifecycle median seconds | 40.656 | 37.559 | 36.5904 | MISS |
| Maximum peak RSS KiB | 670604 | 669800 | 737664.4 | PASS |

Run observations 15.562/15.654/14.523; complete 37.559/38.391/35.280.
Every direct-plus-three-second observation still misses. Separate census:
run imports/stages 2/3 to 1/2; promotion remains 1/1. Instrumented import
durations are not additive plain-run savings. Fixed result CSV SHA-256:
`22889487c4fedcd0f4160620f01285fd85413ec0e4b75277ecc59a3f8f48d727`.
The experiment remains unselected; no retiming or budget relaxation.

## Manifest diagnosis: original failure retained, explicit posthoc correction

`T/manifest_b1_current_owned_diagnosis` retains exit one. Its actual single
profiled snapshot matched the independent 46-table / 487202-row oracle and
owned-file/SQL checks, but the final source inventory `identical()` compared
CSV-inferred integer size with `file.info()` double size. Exact path, byte
count and SHA were equal; no source bytes changed. The requested 2ms Rprof
interval was increased by the platform to **10ms**, as the raw header states.
The original 2ms-derived summary is not valid timing evidence.

`T/manifest_b1_current_owned_diagnosis_correction` exited zero (ten gates plus
outer), without rerunning the profile. Its posthoc independently compares
actual fields and uses the raw 10ms interval. The profiled observation was
5.58 elapsed seconds / 5.56 sampled seconds, not a fresh budget median.
Disjoint sampled buckets: JSON sanitization/serialization 2.22s; SQL 1.70s;
token stream 1.33s; R carrier work .12s; other .12s; resource .06s; hashing .01s.
Inclusive token hash 3.45s / emitter 3.20s / JSON 2.12s overlap, not extra costs.

A **separate** census, no profiler or namespace replacement, reports 983
scalar-batch events: fragment features 500/250000 rows, features 126/63070,
cell-set membership 258/118791, cells 27/13199, matrix cells 20/10000,
fragment cells 50/25000 and space payloads 2/2. Eighteen small-whole-chunk
events cover further admitted rows. These are hook observations, not kernel
I/O or full-source pass counts. All originals were copied without SQL opening;
only owned immutable SQLite copies were queried, and full pre/post inventories
were unchanged. This source diagnosis motivates the separately budgeted internal
metadata batch experiment; it does not establish a gain or whole-engine pass.
