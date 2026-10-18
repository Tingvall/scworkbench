# Prospective manifest snapshot resource consolidation

Baseline exact `e9e561c940b482138456854f67970eca256966e7`. Before implementation:
target >=4x registry snapshot speed for 46 empty/tiny tables; at most three new
simultaneous SQLite connections for the entire snapshot (native observer,
readonly admission window, and transient API initializer), not per-table setup.
The mixed complete-storage <=2 s overhead goal remains MISS and is not waived.
No performance run is authorized for this prototype; focused correctness only.

Share invocation-local observer/window/budget scope, never persisted fingerprints
or cross-invocation state. Preserve registry-table.v1 and registry-state.v1 bytes,
logical hash chunks, SQL type promotion, DATE/BLOB/deferred fields and native
source-change detection. Preserve transaction/in-memory fallback unchanged.
Finish the shared observer once after the full snapshot; errors close resources
and restore caller connection policy. Empty tables return the exact schema-header
identity after count/admission without constructing row projections/cursors.

## Focused installed development results

Own install only: `R CMD INSTALL --no-multiarch --no-test-load -l
/tmp/scwb-engine-simplification-forge-20261018/library_manifest_snapshot .`:
exit0. No shared/frozen library overwritten.

`manifest_snapshot_focused.log` / `.exit` under that temporary task root:
three new contracts executed, three passed, zero skipped/failed, exit0. Covers
46 tables and exact independent materialized table/state identities; one resource
constructor/finish/close per snapshot; no cross-call verdict reuse; exact graph
policy/cache restoration; SQL late promotion, DATE/TIMESTAMP, deferred TEXT/BLOB;
transaction/in-memory fallback; external WAL mutation between tables rejected;
injected table failure leaves no cursor/snapshot and the next snapshot retries.

`manifest_snapshot_existing_focused.log` / `.exit`: existing scalar SQL type
parity, late mutation/transaction, and extended types/mixed BLOB contracts all
passed (3 executed, 3 passed, zero skipped/failed), exit0. Existing logical-chunk
boundary/huge-field tests are retained, not rerun in this tiny prototype check.

Commands use `inst/ci/run_logged_gate ... -- Rscript -e` with `.libPaths` explicitly
set to the own installed library, then source the relevant test file and call the
named contract functions. Complete literal commands and output are retained in
the parent task transcript. `git diff --check`: exit0.

Source review was requested directly from Sable. Preliminary disposition accepts
invocation-local sharing in principle, conditional on full-loop native epoch
finish, per-table cursor cleanup, source coherence and fallback authority. The
WAL-between-table test exercises that final authority explicitly: mixed provisional
reads must reject and can never escape as a successful fingerprint. Final exact
commit source review remains separate. No measured speedup or budget pass is
claimed; performance is reserved for the coordinated root checkpoint.
