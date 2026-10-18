# Selected-axis scratch projection budget (before implementation)

Target: private feature-partitioned matrix reader. Starting semantic behavior
and identities remain unchanged. Resolve complete allowed feature/cell axes
before scratch index construction; retain their declared order and lazily
subset the BPCells source. Do not materialize the selected complete matrix.
Default NULL axes keep existing behavior for parent semantic hashing.

Fixture: repaired read-only Xenopus bundle, matrix `RNA_log_norm`; exact 2,000
rank-ordered PCA features and 13,199 cells from the direct-v3 reference. Compare
all eight feature partitions (256 maximum) before/after including index setup.

Budgets fixed before editing:

- Sum `/proc/self/io` rchar for preparation plus eight selected reads <= 50%
  of baseline, with baseline-reference comparisons outside measured intervals.
- Preparation plus read wall time <= 1.1x baseline on this host.
- Every numerical value, ordered feature/cell ID, shape and storage semantics
  identical to repaired baseline. No identity-scheme/backend-support changes.
- Scratch indices cleaned up on normal close and constructor failure.
- A selected-axis reader cannot silently serve foreign/out-of-projection axes.

The kernel rchar counter measures bytes returned by read-family calls, not
physical device traffic or a cold-cache disk claim. This is a bounded reader
probe, not the complete analytical workflow.

## Measurements

| Phase | Baseline seconds | Candidate seconds | Baseline rchar | Candidate rchar |
| --- | ---: | ---: | ---: | ---: |
| Index preparation | 3.429 | 2.384 | 662,584,188 | 397,597,184 |
| Eight selected reads | 3.534 | 3.158 | 2,894,337,144 | 24,439,212 |
| Total | 6.963 | 5.542 | 3,556,921,332 | 422,036,396 |

Total candidate rchar is 11.9% of baseline and total wall time 79.6%; both
budgets met. All eight returned blocks were `identical()` to the corresponding
saved baseline block, including values, types and ordered dimnames. Peak block
height stayed <= 256. Both normal reader roots disappeared after close.

Preparation retains one pass over source backing bytes as needed by BPCells;
it does not promise physical I/O proportional only to the selected values.
Once the lazy selection is physically indexed, subsequent rank-ordered blocks
no longer decode the unrelated 29,535 features. No dense complete selected
matrix is constructed by the private planner.

Commands:

```
Rscript notes/engine_simplification/profile_selected_axis.R baseline /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/selected-axis-probe
Rscript notes/engine_simplification/profile_selected_axis.R candidate /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/selected-axis-probe
```

The baseline command intentionally rejects existing block files to preserve its
reference. For a new rerun choose a fresh third argument directory. Candidate
loads only the current getter file into a private environment parented by the
repaired baseline namespace. The original finalized bundle is opened read-only;
baseline reference blocks and measurement CSVs go only into the probe directory.
