# Sparse public getter and selected-reader component measurement

This is a bounded component result, not a new full-workflow or full-HVG pass.
Runtime source `a0e88e5931fcd0d4ff3a08add277666e81c31459`; subsequent
`fe7cfa4c0f7ecb901c1d0b7bd4f48ba4a12ab9a4` changes tests only. The root
integration checkpoint was `a7568b2421e9b0326f8ea8cbd6b0521508b4e2d4`.
Old runtime is `76e217a1342ade29b427bbbcba03e595861d474d`. Actual installed
libraries and R database/DLL hashes are retained in the result directories.
New DLL SHA is `f045d2e642b42ee0822bc132c924993785d5d60570ad66a6f9778732e5c02fa2`.

`T` = `/tmp/scwb-engine-simplification-forge-20261018`;
measurement root `T/selected_getter_a0_measurement`.

## Measurement protocol and literal results

After installed focused retry2 passed18/18 across four files, one detached
supervisor ran only: new public128-cell read, old selected256-feature reader,
new selected256-feature reader, then strict comparison. Both earlier focused
16/18 fixture failures remain retained; their correction did not change R code.
No concurrent runtime job, parameter/threshold change, cache or scientific
operation execution was used. Original finalized76 bundle was opened read-only;
every component checks a complete pre/post source-file SHA inventory.

The same default256MiB guard, BPCells0.3.1 double storage and exact cell/feature
order apply to all reads. Each selected-reader plan admits the entire31,535-
feature universe (the real HVG invocation's selection), builds its row-major
index once, then reads the same256×13,199 block three predetermined times.
Plan/index construction, correctness checks, semantic hashing and close are
outside the read timers. No arithmetic is inside those timers.

| Quantity | Old76 | Newa0 | Predeclared criterion | Result |
| --- | ---: | ---: | --- | --- |
| Public31,535×128 read |2.920s retained profile|.296s profile|≥3× and≤1s|PASS9.865×|
| Reader256×13,199 trial1 |.486s|.083s|three fixed repetitions|retained|
| Trial2 |.672s|.060s|same|retained|
| Trial3 |.414s|.063s|same|retained|
| Median read |.486s|.063s|≥50% reduction|PASS87.037%|
| Plan/index preparation |2.333s|2.308s|reported separately|not an assembly speed claim|
| Whole reader-process RSS |724,124KiB|725,332KiB|no separate per-read RSS claim|+0.167% process maximum|

New public-probe process peak739,000KiB includes package loading, full source
fingerprints, RO open and independent reference checks; its21.95s process wall
is not the .296s read time. Old/new reader processes took25.89/24.82s; those
also include source fingerprints, reference loading and semantic encoding.
Read syscall rchar is3,859,333bytes for every trial in both implementations;
physical read_bytes=0 under warm OS caches. These are syscall counters, not
full-source scientific verification counts. Index preparation rchar645,730,020
and wchar548,395,551 match across versions. No default memory limit was raised.

Exact ordered axes, actual numeric values, double storage and the complete
Matrix object agree. Both return `dgCMatrix`. Semantic identity:

```
scheme: scworkbench.operation_pack.matrix_slice.content.v1
sha256: fac5f16b87f0bab5812882972433f4b41bb2d6c959b50f0374070fb3118d7ed8
```

All three execution sidecars00/01/02 are0; source inventories are unchanged.
No warnings appear in those three raw execution logs. This is not new evidence
for104-block timing≤120s, full-HVG duration or end-to-end Xenopus throughput.
The existing76 full-workflow performance miss remains in POST_WORKFLOW_ATTRIBUTION_76.md.

## Strict comparator correction, without changing its assertions

The original03 comparator exited1 at `identical(dimnames(old$value),
dimnames(new$value))`. The outer supervisor therefore remains **FAILED exit1**.
That failure is preserved, not relabeled as an initially clean sequence.

Formal fresh-process probe03a exits0 and proves the cause: Matrix namespace
was absent; raw `@Dimnames` slots already matched. First `dimnames(old$value)`
triggered Matrix loading but returned NULL; the second call dispatched the now-
loaded S4 method and returned proper axes. Subsequent dimnames, whole Matrix
objects and semantic identities are strictly identical. There was no engine
dimname difference, source mutation or relaxed numerical comparison.

Retry03b explicitly loads the pinned Matrix1.7.0 before sourcing the **original
unchanged comparator**. It exits0 with all original strict identity/value
assertions and all predeclared budgets unchanged. The original comparator,
all four measurement harnesses and supervisor retain matching before/after
SHA inventories; all five hash checks passed after the wrapper-only correction.

Raw evidence: `logs/03_compare.log/.exit=1`,
`logs/03a_matrix_autoload_probe.log/.exit=0`,
`logs/03b_compare_matrix_retry.log/.exit=0`,
`public_budget_comparison.csv`, `budget_comparison.csv`,
`old_new_comparison.csv`, per-process `timings.csv`/`result.json`/time records,
and `T/selected_getter_a0_supervisor/harnesses_{before,after}.sha256`.
The wrapper is `T/compare_selected_reader256_matrix.R`; it does not modify the
frozen failing comparator or any measured output.

## Retained boundaries and limitations

Public coverage/selection diagnostics, overlap precedence, duplicate/empty
selection behavior and zero/NA semantics remain focused-test obligations.
Sparse reads avoid dense replacement while preserving original axes and values;
the selected-reader fast path concatenates one bounded sparse block at a time,
not a retained list of every fragment. Resource claims concern the unchanged
admission ledger and scoped carriers, not an OS/native hard quota. Repeated
concatenation still copies growing sparse carriers for very many fragments.
This seven-fragment fixture does not qualify every layout, backend or scale.
