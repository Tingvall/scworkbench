# Frozen-before-measurement graph working-memory procedure

Development plan; no performance acceptance is claimed yet. The exact candidate,
script hashes, admitted grants and fixture roots will be recorded before the
measured qualification. No retrospective increase of these budgets is allowed.

## Admission and accounting

- Working allocation budget: 8 MiB beyond a measured loaded-runtime baseline.
- Explicit baseline variation allowance: 4 MiB, separate from the working
  budget. Pass requires peak RSS <= baseline maximum + 8 MiB + 4 MiB.
- SQLite cache: 2 MiB; encoded graph partition: 256 KiB, at most 256 rows.
  These are included in the working allocation, not additional RSS allowances.
- Small collection/native-adapter cap: 4 MiB; the large fixture never collects.
- Independently declared staged/publication, journal/WAL and spill budgets:
  8 GiB each for the measured fixtures. Budget failures are typed resource
  failures with cleanup, not structural graph-invalid judgments.
- After the baseline run, freeze the admitted total-process budget as baseline
  maximum + 8 MiB working allocation + 4 MiB variation allowance. Data scales:
  exact canonical graph bytes >=2x and >=8x THAT TOTAL budget, not merely 8x
  the incremental working allocation. Retain the baseline-dependent exact
  byte targets before running either scale. Counts, sizes and roots are measured,
  not estimated from source-file size. Chunking must not change any identity.
- Before fixture creation, verify available disk for staging, destination,
  relocation, token/temp/journal peak and an 8 GiB reserve. Run scales sequentially
  and clean only owned temporary fixtures after retaining their evidence. Do not
  delete other worktrees, caches, frozen evidence or runtime artifacts for space.

## Baseline and subprocesses

Use the exact installed candidates, identical library paths/environment,
identical loaded packages and GC procedure for all subprocesses. Measure three
baseline processes with `/usr/bin/time -v`. Baseline warms the entire graph
write/validate/hash/seal/promotion/finalization/read path with an empty graph,
loads the same fixture-source schema and invokes GC. Retain each literal command,
numeric exit and maximum RSS; use the largest baseline RSS, not a convenient
lower value. Run the two scale subprocesses with the same setup, GC and fixed
budget. Retain total elapsed time and independently collected peak RSS.

Fixture-source setup is separately recorded and checksummed. It may use the
existing public scalable source importer but may not preload a complete source
axis into the measured process. Complete authenticated axis scans, mapping
checks, metadata verification and all graph work occur inside the measured
subprocess. Report fixture-setup memory separately, never as graph streaming
evidence. The operator driver itself must not hold whole graph/axis arrays.

## Measured lifecycle and fixture composition

Generate bounded records incrementally through the public pack writer. Include
one huge hyperedge spanning many partitions (including repeated participation),
isolated nodes, dense typed attributes across multiple fields, a large mapping
and a complete authenticated source axis. Include nonlexicographic semantic
order. Finish the writer once; independently validate, hash and seal; publish
inside the ordinary mixed-output transaction; promote/finalize; relocate; replace
the process; reopen pack-free and read bounded components/rehash. Verify the
content/binding/descriptor roots and complete source certificate across stages.

## Disk and failure gates

Record baseline, live peak and final logical/allocated disk bytes for owned
SQLite main/WAL/SHM/journal, canonical-token spill and SQLite temporary files.
Sample during operations, not merely before/after. Identify unlinked SQLite
spill through process file descriptors where available; never assume absence
of directory entries means zero spill. State platform limitations explicitly.

Inject interruption/resource exhaustion during append, validation/token spill,
seal, receipt insertion and payload/row publication. Each failure must remove
only owned staging/spill state, leave no durable artifact/run/registry/receipt
residue and permit retry. Check source-only destination validity and exact
inventory identity. Include collect/native-adapter over-budget rejection while
bounded reads still work. Never enlarge the collect cap to qualify a fixture.

Any exceedance fails this predeclared procedure. Diagnose and improve bounded
implementation before rerunning an affected gate; do not relabel an exceedance
or silently change the baseline, allowance or working budget.
