# Exact focused proposal (not executed)

New file tests/test_engine_empty_capsule_recovery_contract.R has5literal tests:

- no_work_and_public_open: actual zero builder/publisher/checkpoint, strict FS
  and scientific SQL state for no-root/empty-root; public open retains1migration
  builder/publisher and original visible two-field result.
- actual_cleanup_and_empty_pending: empty.pending is work even with0/0result
  counts; real pending+valid self-identifying orphan removal; forceTRUE while
  lockheld and one best-effort checkpoint; SQL unchanged.
- invalid_paths_and_unlink_failure: foreign pending/orphan/bad manifest reject
  without deletion; partial cleanup error has no success publication; external
  symlink target untouched; lexical unlink failures for ordinary and empty-root
  cleanup reject and leave lock retryable. No production test hook.
- nested_transaction_and_readonly: exact outer token/depth retained; nested
  caller TX stays active; outermost caller TX retains the old acquire-before-TX
  rejection before any publisher, without commit/rollback; RO rejects with strict
  FS unchanged.
- publication_failure_and_explicit_retry: actual cleanup remains deleted after
  failed atomic manifest publication; old manifest and SQL intact; outer token/
  depth restored; explicit refresh and no-op recovery retry; no caller lock leak.

Namespace spies restore in reverse order before fixture teardown. Strict FS
observation starts after establishing the SQL observer, so that observer's first
SHM effect is not falsely attributed to no-op recovery. Raw failures must remain.

Proposed installed-focused union: the new5 plus existing registration1,
atomicity_security1, process_death1 and recipient_validation2 =10tests/5files.
Use contract_test_discover/execute from inst/tests with an explicitly pinned NEW
immutable installed library and exact source/DLL/test hashes. No source-sourced
runtime replacement. Preserve skips/warnings literally; no full suite.

Prepared external driver: /tmp/scwb-engine-simplification-forge-20261018/
run_capsule_empty_recovery_focused.R. Command after exact source approval and
serial release: Rscript DRIVER NEW_LIBRARY EXACT_SOURCE_ROOT EXPECTED_DLL_SHA.
Then reuse the frozen baseline's separate plain/census geometry against matched
baseline/new installs after coordinator review; current baseline driver is pinned
old-only and must NOT be silently overwritten or claimed candidate-compatible.
No focused/install/benchmark job has run for this candidate.
