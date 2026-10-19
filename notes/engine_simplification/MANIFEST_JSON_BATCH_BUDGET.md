# Manifest registry JSON batch experiment: preimplementation budget

Prepared before algorithm changes or new measurements on 2026-10-19.

## Exact parent and scope

- Base: `fb47df4b451561793e3176213261ca1b25f14236` (I/E lineage).
- Sole added runtime/test change before this note: original cursor cleanup commit `746066b26851f4e778f0f36d5e2c4b94193c3705`, cherry-picked as `a809764`. It clears an owned manifest source cursor before restoring connection resources; it does not change registry batching or identity.
- Branch: `perf/manifest-json-batch-forge-20261019`.
- No graph handoff or rejected same-owner registry reuse is included.

This checkpoint is for a clean parent install and baseline, not a selected optimization. No JSON batching algorithm has been implemented. The bounded algorithm and source review remain pending the actual parent measurements and coordinator instructions.

## Unchanged contracts

Keep `registry.v1` identities byte-exact, including the existing 5000-row ordered fold. A future internal metadata JSON batch may be independent of the present minimum 512 / graph `partition_rows` choice, but must not change those identity fold boundaries, query order, serializer arguments, nullable values, or decoding semantics.

Preserve the same partition ceiling `8P`, existing carrier plus `8 * encoded bytes` admission, token/source-observation protections, graph wire partition limits and all current resource policies. No larger public limits, caches, authority shortcuts, source-history omissions or altered failure/recovery contracts are authorized. Preallocation and constant-state bounded traversal must avoid repeated growth or an O(N^2) accumulation scheme. The future intentional update to the internal batch-size assertion in `test_manifest_stream_identity.R:143` is not permission to weaken identity/admission checks.

## Measurements required BEFORE implementation

Use the exact clean parent checkpoint produced by this preparation, immutable installed library/DLL and hash-locked harness. Collect three fresh plain processes for the same large 46-table / 487202-row snapshot, with setup outside the timed boundary and unchanged input/source guards. Collect the tiny 46-table case separately. Plain measurements must not contain census spies. Record actual SQL/scientific state and registry identities, source/library/harness hashes, all numeric exits, elapsed time and process peak RSS. Preserve all failures and prior evidence.

Freeze the measured parent medians, RSS and corresponding absolute ceilings in an append-only result before ANY batching implementation. No parent values or numerical absolute ceilings are invented in this note.

## Prospective acceptance gates

1. Large complete registry snapshot median: candidate <= 0.85 * fresh matched parent median (at least 15% faster).
2. Process peak RSS: candidate <= 1.10 * matched parent peak RSS.
3. Tiny 46-table snapshot median: candidate <= 1.10 * fresh matched parent median + 0.02 seconds.
4. Exact independent old registry bytes/fingerprints and every existing fold/admission/error/cleanup invariant; positive evidence the actual large path uses the intended internal batch, not a silently unchanged fallback.

All gates must pass; no retiming or threshold revision to erase a miss. A component result is not a whole-engine result. The original whole-snapshot 3x target remains unwaived wherever previously missed.

## Other frozen budgets remain unchanged

The historical E graph reference retains run 14.4336 seconds, whole 36.5904 seconds and RSS 737664.4 KiB as supplied by the coordinator; these are context, not new measurements by this experiment. The original direct +3-second graph requirement and all whole-workflow rejected budgets remain unwaived. This experiment does not promise graph or Xenopus gains from a metadata component result.

## Current status

PREPARATION ONLY. Clean parent/source and this budget note may be installed/profiled only on coordinator release. No new tests, installation, benchmark or profiling execution occurred while preparing this note. Algorithm design, exact-source review and qualification are pending.
