# Prospective unchanged-publication witness

Baseline exact e9e561c940b482138456854f67970eca256966e7. Before implementation:
unchanged assembly close/writer tail should perform zero registry snapshots;
prospective warm witness guard target <=0.1 s for the existing small mixed fixture.
The <=2 s complete mixed overhead budget remains MISS, not waived. No performance
jobs here: only bounded installed correctness tests.

The witness is private connection-local publication metadata, not scientific
content authentication or a persisted registry fingerprint. Reuse requires the
same live connection reference and actual writer token, exact SQL counters,
actual main/TEMP/attached schema definitions and attachment identity, plus the
actually published manifest SHA. Read epoch before AND after the SHA observation.
Explicit public refresh and migration remain fresh. Publication errors clear the
witness before retry. Recovery/backup restore must clear this private witness.

## Implementation boundaries

`R/manifest_publication_witness.R` observes total_changes, data_version and actual
schema SQL/versions for main, TEMP and every attachment. Counter values must be
exact finite nonnegative scalar numerics <=2^53-1. Before/after reuse observations
bracket the actual manifest SHA. The private writer returns its generated UTF-8
payload SHA as an attribute on the existing TRUE result; only matching actual
published bytes can establish a witness. No JSON/header/content identity changes.

Explicit public refresh and bundle migration force a fresh build. Other writer
tails retain existing raw assembly lock nesting behavior; they may reuse only a
matching successful witness. Assembly close checks before forgetting observations,
then clears its witness and disconnects. The fresh helper now rejects an active
SQLite transaction, including close: disconnect rolls back, old manifest bytes
remain unchanged and the error propagates rather than publishing uncommitted rows.

**Integration prerequisite:** root commit
`8dd3509e5e93141975fb0c3f5e65383833f6da39` additionally clears
`con@ref$wb_manifest_publication_witness` in `.wb_session_source_forget` for recovery,
backup/restore and migration. That separate root-owned helper change is NOT copied
into this isolated e9-based patch. Verify source-forget invalidation again on the
assembled installed candidate. The standalone prototype is not release accepted.

## Focused development evidence

Own actual installed library only:
`/tmp/scwb-engine-simplification-forge-20261018/library_publication_witness_v2`.
No runtime namespace patch or source-patched authority used. Complete raw commands,
logs and atomic numeric sidecars are retained under the same temporary task root.

```sh
R CMD INSTALL --no-multiarch --no-test-load -l /tmp/scwb-engine-simplification-forge-20261018/library_publication_witness_v2 .
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/publication_witness_final_focused.log /tmp/scwb-engine-simplification-forge-20261018/publication_witness_final_focused.exit -- Rscript -e '.libPaths(c("/tmp/scwb-engine-simplification-forge-20261018/library_publication_witness_v2",.libPaths())); library(scworkbench); source("tests/test_engine_publication_witness_contract.R"); for(n in ls(pattern="^test_engine_publication_witness_")){cat("RUN ",n,"\n",sep=""); stopifnot(isTRUE(get(n)())); cat("PASS ",n,"\n",sep="")}'
```

Prior raw failures remain preserved: `publication_witness_focused.exit=1` and
`publication_witness_sql_debug.exit=1` exposed an overstrict test requiring an
immediate witness after TEMP create/drop. Existing graph temp_store restoration
can reset an empty TEMP schema's version during the fresh build. The conservative
epoch miss is retained; a subsequent explicit refresh must observe stable state,
not falsely certify the previous epoch. `publication_witness_focused2.exit=1`
exposed an overstrict reconnect assertion: writable open legitimately performs
fresh migration/publication on its NEW connection. Corrected tests reject old
connection/owner inheritance instead. `publication_witness_focused3.exit=0` passed
the prior three contracts; its two Already disconnected warnings were test
cleanup double-closes, fixed with dbIsValid checks, not warning suppression.

No complete suite, final performance job, scientific workflow or container job ran
for this prototype. Sable's exact source review and the coordinated installed
integration checks remain distinct from these development contracts.

Final focused installed result: **4 executed, 4 passed, 0 skipped, 0 failed**,
numeric exit **0**, no cleanup warnings. Covers unchanged close and ordinary nested
assembly tail publication counts; explicit refresh/migration counts; actual direct
SQL after finalization forcing close publication; active TX/DML rollback; resettable
schema_version with real SQL changes; TEMP/attachment/external attached writes;
exact-byte manifest replacement; generated-versus-observed publication bytes;
before-rename fault preserving old manifest and retry; reconnect/new-owner
invalidation; close-with-open-transaction rollback and finalized read-only reopen.
`git diff --check`: exit0. Prospective performance budgets remain unmeasured.
