# Practical matrix streaming — completed local candidate

Branch: `fix/practical-matrix-streaming-forge-20261018`.
Tested runtime commit: `d7232f800190e1c1cb78af0e4591fa53e9003087`.
The handoff/evidence descendant changes no runtime code. Local commits only:
**no push, merge, profile repin or image build**. Primary repositories remain
clean at the starting pins. RNA, Representation and PyBench exact pins and
host details are in [BENCHMARK.md](BENCHMARK.md).

## Repair and contract

Whole-fragment dense authentication plus per-nonzero R record construction
made preparation unbounded. Incorrect S4 detection selected dense fallback;
per-chunk full hashes and repeated column-major feature scans multiplied work.
Profiled downstream numeric formatting and strict JSON suffix copying were
also expensive.

Core now streams the existing canonical identity bytes, uses bounded physical
read plans and invocation-local row-major scratch indices, fixes S4 sparse
coercion, skips an unused lineage snapshot, and removes equivalent formatting/
strict-parser representation work. No scientific operation, protocol, identity
scheme, source fragment layout or official pack changed. Pack interfaces are
unchanged; core still owns alignment, selections, coverage, receipts,
provenance and atomic publication. See the SDK guide's trusted-R section.

Controller approved full source-content authentication at request creation,
dispatch and publication, with relevant registry/file checks between trusted
R chunk reads. Persistent mutation rejects and rolls back; **transient mutation
restored before final authentication is not guaranteed detected**. Python's
supervised per-read policy is unchanged. No mutable cross-run content cache
or new executor was introduced.

## Acceptance results

- Focused runner: `files=4 discovered=18 executed=18 passed=18 skipped=0
  failed=0 excluded=0 accounted=18`; 25 tests were available in the selected
  files, 18 deliberately selected. This is not package-wide discovery.
- Small normalize → HVG → PCA → UMAP → promote → finalize → read-only reopen:
  **PASS**, including zero-library cell, reordered axes, independent numerical
  reference and three boundary authentications for five normalization chunks.
- Strict-parser old/new differential: **160 identical outcomes**, including
  invalid/duplicate-key inputs; no grammar relaxation.
- Real Xenopus exact-parameter durable baseline: **PASS**, exit 0,
  `BASELINE_PROMOTED_FINALIZED_READONLY_OK`. Operation timings: normalization
  336.811 s, HVG 385.406 s, PCA 319.805 s, UMAP 234.071 s. Every normalized
  value agrees with independently aligned source-RDS CP10k/log1p to <1e-14.
- End-to-end **33:59.96**, peak RAM **5,175,008 KiB** (~4.94 GiB), sampled
  working-file disk peak **1,728,999,424 bytes** (lower bound); final bundle
  **847,949,824 allocated bytes**. Promotion 417.841 s; finalization 10.370 s;
  validated read-only reopen 3.811 s. Default dense guard unchanged at 256 MB.
- Subsequent finalized read-only raw audit: **PASS**, exit 0, every source
  value/type/ordered read/named sum, 13,199 cells x 31,535 features / 104 blocks.
- Parse and `git diff --check`: **PASS**. No complete core suite, fullstack,
  package check or image qualification was run, as agreed.

The real trace has nine full matrix-content boundary checks (three per matrix
operation), not checks proportional to chunks. Bounded semantic slice hashing
still costs 280.547 s across 147 fragment/chunk calls. Fixed read-plan/index
preparation totals 3.979 s; seven fragment writes 2.386 s. Remaining full
semantic passes, fixed BPCells sorting passes, metadata/provenance work and
the independent reference are disclosed in the benchmark.

Matched bounded comparisons retain exact digests: small old R projection
4.143 → 0.027 s; real 31,535-feature x 8-cell identity 11.735 → 0.744 s.
Feature-indexed reads reduce repeated approximately 272 MB rchar to approximately
2 MB per measured block after fixed preparation. No speedup ratio against the
unmatched eight-hour cluster timeout is claimed.

## Literal final commands and evidence

Working directory is this isolated worktree; `E` and `L` below expand to the
exact retained chamber and installed library:

```sh
E=/tmp/scwb-matrix-streaming-forge-20261018
L=$E/verified-library
inst/ci/run_logged_gate "$E/verified_focused.log" "$E/verified_focused.exit" -- Rscript notes/matrix_streaming/run_focused.R "$L"
inst/ci/run_logged_gate "$E/verified_small.log" "$E/verified_small.exit" -- Rscript notes/matrix_streaming/small_workflow.R "$L"
inst/ci/run_logged_gate "$E/verified_strict_repro.log" "$E/verified_strict_repro.exit" -- Rscript notes/matrix_streaming/profile_strict_json.R "$L"
inst/ci/run_logged_gate "$E/verified_baseline.log" "$E/verified_baseline.exit" -- /usr/bin/time -v Rscript notes/matrix_streaming/xenopus_workflow.R baseline "$E/verified-xenopus" "$L"
inst/ci/run_logged_gate "$E/verified_raw_all_finalized.log" "$E/verified_raw_all_finalized.exit" -- /usr/bin/time -v Rscript notes/matrix_streaming/verify_raw_all.R "$E/verified-xenopus" "$L"
git diff --check
```

All five final command sidecars are **0**. Compressed complete logs, numeric
sidecars, phase CSV, disk samples, Rprof, environment, input checksum and native
library checksum are in [evidence](evidence/), covered by `SHA256SUMS`.
Original raw logs and own interrupted checkpoints remain under `E`.

## Limitations and follow-up

The earlier unequal column sums are **not reproduced**: explicit names, axes,
types and all values now agree, including the original 2,000-cell total
23,590,431. Their original cause is not asserted to be an attribute difference.
The separate SQLite probe reproduces the reported copy error inside an active
write transaction, but does not establish the original cluster cause. Fresh
durable backup succeeds; no speculative lifecycle repair was made.

Historical monolithic normalization is contextual, not an equivalence pass:
9.688 s on a counts-only fixture, but strict numerical comparison fails by up
to 6.584032e-07 due to BPCells SIMD log1p downcasting. The current pack matches
the R double reference. Its old runtime/full baseline is not matched. Failed
and intentionally interrupted development trials are explicitly retained in
the benchmark and are never counted as final passes.

No blocking item remains for this work order. Controller can review the local
candidate; any deployment/profile/image action remains separate authorization.
