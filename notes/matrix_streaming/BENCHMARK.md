# Practical matrix streaming: measurement record

## Candidate and boundaries

Runtime candidate: `d7232f800190e1c1cb78af0e4591fa53e9003087`, descended
from core `96cbf880109a2c1fa110ed1a185169c90ed00899`. Unmodified pack pins:
scwbRNA `151dd29211b219343dce6247c5e48fc932b4c83d` and
scwbRepresentation `be51127ca0d7c11a0667be826c24449a5c7e8912`.
Unmodified PyBench peer: `e724f55f709c5f1f3e99e1afc5cf83301c7a86bd`.
No standard-profile repin, push, merge, image build or scientific parameter
change was performed. The original interrupted experiment was not modified.

All measurements use Linux x86_64, R 4.4.1, Intel Core i7-1360P,
16 visible logical CPUs, approximately 31 GiB host RAM and ext4
(`/dev/mapper/data-root`). Source, scratch and output share this filesystem.
Execution is sequential and uses approximately one CPU per active R process;
this is not the original approximately 860 GB cluster node. Preliminary and
final development processes sometimes overlap; these are not isolated-machine
microbenchmarks. The reported cluster eight-hour timeout is unmatched and is
not a denominator for a claimed speedup.

Raw logs, numeric exit sidecars, profiles and fixtures are retained under
`/tmp/scwb-matrix-streaming-forge-20261018`. Reproducible harnesses are beside
this report. Compressed evidence in this directory preserves selected raw
logs; unsuccessful trials are distinguished below, not relabeled as passes.

## Root cause and retained guarantees

The old source-fragment schedule requested a complete fragment and constructed
a dense matrix, then an R list and canonical JSON record for every nonzero.
The public sparse conversion also tested `methods::is(x, "S4")`, which is
false for the actual BPCells object despite `isS4(x)` being true. This selected
the dense fallback. In addition, per-chunk full authentication repeatedly
scanned source bytes, and feature-partitioned access repeatedly decoded
column-major data. Large metadata snapshots exposed quadratic suffix copying
in strict JSON validation; scalar-by-scalar R numeric formatting was another
measured cost in downstream receipts.

The repair emits the **same** `matrix_slice.content.v1` coordinate preimage
incrementally (128 columns, 8192 coordinates per native append), then hashes
its bytes with the existing SHA-256 implementation. It does not create a
whole-fragment dense matrix or one R list/string per nonzero. The bounded
trusted-R reader opens physical sources once and builds an invocation-local
row-major scratch index for feature partitioning. This does not split the
logical input fragment. Cleanup runs on both normal and failed dispatch.

Controller explicitly approved boundary authentication for trusted in-process
R packs: full content authentication at request creation, dispatch and
publication, with relevant registry/file checks before and after chunk reads.
Persistent changes abort and roll back. A transient mutation restored before
final content authentication is **not guaranteed detected**. This is a
documented trust-model change, not immutable-input memoization. The supervised
Python broker retains its existing per-read full authentication policy.
Declared axes, selection, coverage, partition discipline, provenance, receipts
and atomic publication remain enforced. Canonical JSON's unique-key and
strict-grammar rules remain intact; no identity scheme or protocol changed.

There are three full source-content boundary checks in the small five-chunk
normalization test, not checks proportional to chunk count. A semantic parent
identity pass and the computation pass also remain. Feature-oriented reads
have a fixed index-build phase (BPCells sorting may use several physical
passes), followed by partitioned reads. Per-chunk metadata/file inventory work
remains; it is not a full numeric-source scan. Canonical coordinate hashing
still requires a sequential temporary byte stream and associated scratch I/O.

## Bounded, identity-preserving measurements

| Measurement | Before | After | Equality evidence |
| --- | ---: | ---: | --- |
| 800 x 160 sparse identity, 12,302 nonzeros | 4.143 s | 0.027 s | identical `47907725d50f84296111b6be4d44e8716a5df8608e3d419c20a308ee56f3e2b7` |
| Real source, 31,535 features x 8 cells identity | 11.735 s | 0.744 s | identical `71c110d77c01f44f5c5cbb572a8db7e30c162f891544edf7b1ea15848293205c` |
| 2000 x 2000 intermediate native string emitter vs buffered direct emitter | 5.488 s | 2.829 s | identical `347be5d4a883b770c94785564d727ae99cb31b158a2db2492f6f6e3b55fa7178` |
| 100,000 raw numeric canonical scalars | 23.951 s | 0.706 s | identical `af2c1149a62afecde7f0e6952298a88d6549a206ebb927d92d16343aec751c26` |
| Strict JSON, 100 rows / 9,310 bytes | 0.362 s | 0.056 s | original scanner outcomes identical |
| Strict JSON, 500 rows / 46,910 bytes | 5.490 s | 0.156 s | original scanner outcomes identical |

Strict JSON differential coverage includes 160 valid/invalid outcomes with
both compiled and standalone-source index lookup. The independently frozen
old validator is used as oracle. A real 1,944,542-byte feature snapshot
(`12b7e15a8531447ac1488823a30a3cf18d4037b63e79e2625d2f4a0bb635afe1`)
validates in 6.441 s with the indexed standalone implementation.

Two consecutive 256-feature x 13,199-cell reads with the old getter took
2.912 / 0.540 s and read approximately 289 / 272 MB (`/proc/self/io` rchar).
Building the private row-major index took 2.930 s, approximately 815 MB rchar
and 254,724 KiB allocated index storage. Indexed reads took 0.328 / 0.027 s
and approximately 1.75 / 2.37 MB rchar. These counters include library/cache
effects and demonstrate the repeated decode reduction, not physical disk
throughput. The index build's fixed passes are explicitly included.

Independent normalization kernel profiling on all source cells, excluding
engine dispatch, publication and provenance: sparse-to-dense chunk conversion
3.207 s; CP10k/log1p arithmetic 17.724 s. Authentication, serialization,
metadata validation and publication must therefore be measured separately
from arithmetic rather than attributed to the scientific method.

## Alignment and scientific reference

Approved source: `aztekin_tail_2019_sce.rds`, SHA-256
`7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280`.
Counts are 31,535 x 13,199 with 29,297,098 nonzeros (`dgCMatrix`, double).
The first 2,000-cell comparison checks explicit cell/feature identities,
names, order, numerical values, storage class/type and named column sums.
Every comparison is exact; the total is 23,590,431. The reported original
unequal column sums are not reproduced. A synthetic permutation demonstrates
why equal totals alone are insufficient, but does **not** establish the cause
of the original cluster observation. Its exact returned vectors/runtime
details are unavailable; no attribute-only explanation is claimed.

The full workflow uses an independent source-RDS CP10k/log1p reference,
aligned by explicit axes in 128-cell blocks, checking every normalized value
with maximum absolute error below 1e-14. Small fixtures also include a
zero-library cell and exact ordered-axis/legacy-identity checks.

After finalization, the independent read-only raw audit passes for **every**
31,535 x 13,199 source value, named column sum, cell/feature identity and double
storage type in 104 blocks. Its literal result is
`RAW_ALL_VALUES_AND_NAMED_SUMS_EXACT cells=13199 features=31535 parts=104`.
This separate audit takes 32.39 s, peak RSS 1,455,824 KiB, exit 0. The approved
source checksum is unchanged after the workflow.

## Frozen-candidate scientific phases

The approved exact parameters are executable in `xenopus_workflow.R`:
normalization scale 10,000/chunk 2,000; HVG vst/2,000 features/chunk 256/seed 1;
PCA irlba/50 components/center/scale/chunk 256/seed 1/max_dense_gb 8;
UMAP PCA dimensions 1:30/neighbors 30/min_dist .3/spread 1/euclidean/
nndescent/seed 1. The default dense guard stays at 256 MB. Only the two
necessary pinned packs are activated; the standard profile is not changed.

| Exact d7232f8 phase | Wall seconds | User seconds | System seconds |
| --- | ---: | ---: | ---: |
| Normalization | 336.811 | 314.203 | 22.063 |
| HVG | 385.406 | 379.541 | 4.703 |
| PCA | 319.805 | 316.944 | 2.586 |
| UMAP | 234.071 | 232.913 | 0.602 |

Scientific-operation wall time totals 1,276.093 s (21:16.093), including
authentication and durable checkpoint work. Nested request/write/publication
timings in the CSV must **not** be summed as independent phases. Normalization
materialization publication is 8.441 s; its seven fragment-write calls are
individually recorded. PCA materialization publication is 21.562 s; UMAP's is
0.873 s. The fixed source-preparation and hashing calls are separately traced.

Across the real four-operation run, the trace records four private reader-plan
constructions (3.979 s), seven matrix fragment writes (2.386 s), nine complete
matrix-source boundary authentications (22.335 s: three each for normalization,
HVG and PCA), and 147 bounded fragment/chunk semantic identity calls
(280.547 s). The latter are **not 147 full-source passes**. The four enclosing
request phases total 195.880 s and materialization-publication phases total
30.876 s; they overlap nested work above. Durable SQLite backup succeeds in
0.357 s. These are traced wall times, distinct from the sampled profile and
the independent arithmetic-only measurement.

Rprof samples cover only these four operation calls, 1,275.36 sampled seconds,
not the later independent reference or promotion. Remaining dominant sampled
work includes stream-identity generation (149.64 self / 281.76 inclusive s),
multi-fragment `replCmat4` assembly (64.96 self s), hashing and canonical strings.
These are overlapping sampled call-stack attributions, not disjoint wall-time
accounting. Retained table provenance hashing/JSON serialization before later
operations is also observable; it remains enforced. No second executor,
operation-name exception, or scientific-parameter change masks these costs.

The final durable lifecycle passes with
`BASELINE_PROMOTED_FINALIZED_READONLY_OK`, exit **0**:

| Remaining phase | Wall seconds |
| --- | ---: |
| Independent full normalization reference | 263.584 |
| Promotion | 417.841 |
| Recipient finalization | 10.370 |
| Read-only reopen and validation | 3.811 |

GNU time reports **33:59.96** end-to-end, user 2,001.65 s, system 35.18 s,
peak RSS **5,175,008 KiB** (approximately 4.94 GiB), no swaps. This includes
startup/source loading, activation, session creation, independent reference,
promotion and reopen; the additional 32.39 s raw audit is separate. Promotion
and retained-output validation remain material costs, not hidden by the
21-minute operation-only number.

The 1 Hz sampler records 1,990 observations and maximum reachable regular-file
allocation **1,728,999,424 bytes** (logical 1,728,917,353) across the dedicated
fixture chamber and discovered process R temporary root. This is a **sampled
lower bound**, not a guaranteed instantaneous maximum: transient/open-unlinked
files and unrelated host storage are not included. Retained fixture chamber
allocation is 1,415,323,648 bytes (logical 1,414,704,118), including source,
final bundle, durable workspace and profiles. The final bundle alone occupies
847,949,824 allocated bytes (logical 847,649,558). GNU time also reports
25,013,096 filesystem-output units; those are I/O accounting, not retained
disk allocation.

The frozen final candidate therefore completes the exact baseline through
promotion/finalization/read-only reopen without the old whole-fragment dense
authentication path. It does not approach the historical monolithic timing;
canonical identity/provenance and durable lifecycle overhead still dominate
arithmetic. This remaining cost is disclosed rather than called solved.

## Historical monolithic context — not a numerical acceptance pass

A clean detached old source at
`d95d8df9955f08f0732feb653cbe9be9a6869d26` was installed separately. Its
counts-only normalization on the same source/hardware/current BPCells took
9.688 s. The strict numerical comparison **failed**: maximum log1p error was
6.584032e-07. Library sums and pre-log scaled values were exact. The old
BPCells lazy log1p calls SIMD downcast implementation
(`r/R/transforms.R:51-58`, `r/src/bpcells-cpp/matrixTransforms/Log1p.cpp:26-28`
in the local BPCells source). The new pack's double-precision R result is
checked against R's independent double reference, not retrofitted to the old
approximation. Historical source/runtime and imported metadata differ, and
this is only normalization, not a matched full baseline. No equivalent
historical end-to-end speedup is claimed. No old code or evidence was changed.

## Separate SQLite diagnostic

`sqlite_copy_probe.R` reproduces exactly `Failed to copy all data:\nnot an error`
when RSQLite backs up a connection inside an active write transaction.
Committed backup succeeds; rollback followed by retry succeeds. The original
cluster transaction state and filesystem are unavailable, so this is a
plausible reproducer, **not** a proven diagnosis of that incident. Fresh
durable/small workflows exercise successful SQLite backup. No speculative
SQLite lifecycle repair is included.

## Trial accounting

The original cluster timeout remains untouched. Own initial streaming trial
`5cdce03` was deliberately interrupted after 22:30.78 (exit 1), normalization
572.350 s, peak RSS 6,988,148 KiB. Own `e56dda0` trial was deliberately
interrupted after 7:52.59 (exit 1), normalization 325.029 s, peak RSS
5,382,604 KiB. Their logs/checkpoints remain retained; neither is a final
workflow pass. A separate `3fa470c` trial isolates the prior strict-parser
cost and is not substituted for the exact final candidate. It was deliberately
interrupted during promotion after 43:49.62 (exit 1; peak RSS 5,182,148 KiB),
having completed normalization 287.779 s, HVG 671.463 s, PCA 324.929 s,
UMAP 236.024 s and the full independent normalization reference 273.194 s.
This bounds the preliminary parser investigation; its failed/interrupted
promotion is not presented as an accepted lifecycle.

Initial harness errors (manual test namespace isolation, missing sparse
numeric skeleton, and source-ingest handle reuse) are preserved in raw logs.
The sparse skeleton was repaired in product code; the other two were harness
corrections. Final acceptance uses the canonical contract runner and fresh
installed-library process. No failed command is counted as passed.

The first all-cell raw read-only audit was invoked while the final baseline
still had an active writable connection. It correctly rejected unresolved
WAL sidecars (exit 1). This is a harness sequencing error, not a bypassed
finalization requirement; the acceptance audit must run after finalization.
