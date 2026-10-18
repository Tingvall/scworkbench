# Python transport matrix-read budget (before implementation)

The repaired R broker's bundle-matrix source method performs two complete
grant/current-source authentications per control read. This is separate from
the R adapter repair and must not be described as already bounded in source
verification cost. A private selected projection is also fully revalidated
and reread for each control read. Quill and Sable were asked to review moving
these checks to the trusted broker lifetime; no protocol or identity change is
proposed.

Measure eight and thirty-two ordered cell blocks against one unchanged source,
including explicit source/grant preparation separately. Target one complete
source authentication per grant at broker initialization, zero whole-source
authentications during ordinary delivery, and unchanged parent prepublication
authentication. Partition count must not multiply full source scans. Source
startup plus delivery target <=0.4 times the previous two-check-per-block cost
+0.05 seconds, with identical ordered numerical values and slice identities.
RSS must not exceed the repaired baseline +10 MiB for the small fixture.

Retain exact allowed axes, selection limits, partition discipline, response-byte
checks, MatrixMarket/file hashes, acknowledgements, observed slice identities,
final closure, enduring mutation rejection and publication rollback. Scoped
file/registry observations are supplementary, not timestamp content authority.
A transient modification restored before final content authentication is not
promised detectable under the Controller's trusted scientific-pack model.
Explicit one-off source reads and recovery must not inherit stale observations.

Development probes do not qualify live Python transport; the coordinated final
gate must include compatible-PyBench execution with a real broker and retained
rollback evidence. No Python scientific implementation is changed by this
R-side consolidation.

## Implemented candidate boundary

For requests without graph grants, each broker grant starts one source lifetime: authenticate the stage-visible
matrix once, retain a private selected-axis reader, inspect scoped registry/path
evidence before and after blocks, close on completion/error/timeout. Explicit
one-off source calls construct a fresh lifetime and do not inherit old state.
The full parent prepublication check is unchanged; supplementary file metadata
is not a content identity or a hostile-code defense.

Private Matrix Market projections validate once. A conservative aggregate
reservation admits retained matrices only within half the existing dense-memory
allowance (and applicable graph memory reservation). Otherwise the verified
matrix is written to a disposable **double-valued, uncompressed** BPCells spill,
with an optional row-major index for feature partitions. It never reloads an
altered original projection on a later block. Both original file/axes and owned
spill have supplementary guards. Close/error removes only its own scratch root.

The initial Matrix Market parse remains the existing whole-object startup
boundary: this is **not an end-to-end bounded-startup-memory claim**. Postparse
spill construction checks working memory, aggregate reservation and conservative
disk build peak/headroom. Ordinary spill requires measurable POSIX `df -Pk`
capacity; unavailable capacity fails cleanly. It does not silently select the
old per-block whole-source-verification path. Disk admission cannot reserve free
space against unrelated writers; a later write failure must still clean up and
abort publication.

Sable reviews: `f32fb67f77ba17ab71230f997cd26a96757d82ea` (broker lifetime)
and `3c850251` (post-validation spill). They are conditional design inputs, not
final implementation acceptance.

## Explicit mixed graph/matrix exception

Following Sable's `d0a3d04a` disposition, the candidate preserves the previous
per-block delivery whenever a request has any graph read/write grant and a typed
matrix grant. The coordinator conservatively extends the private-projection
exclusion to backed matrices as well, because feature-oriented readers can also
create new row-index scratch. No retained projection cache, new reader plan,
row index or BPCells spill is introduced on this branch, even with a zero cache
allowance. Supported mixed execution is not rejected solely by the new spill
admission rules.

Backed mixed reads retain two full source authentications and `wb_slice` per
block; private mixed reads retain full private-file validation, parsing and
authenticated axes per block. These costs are intentionally not optimized.
Mixed peak resources remain unchanged/unmeasured, not newly bounded or accounted
by the nonmixed spill design. Thus **not every typed block avoids whole-source
verification**: the constant-source-scan claim applies to optimized nonmixed
execution only. Parent graph/source checks, receipts and publication rollback
remain in force. No graph page or policy-accounting framework was added.

Three focused mixed tests passed via source patch on immutable `library_dev5`:
old-oracle values/semantic identities at forced-zero cache with no new BPCells
scratch; source mutation rejection; actual main routing from both positive
graph-read and graph-write grant fields for backed and private sources; and an
existing publication-fault seam leaving the original source-only destination
unchanged and its SQLite quick-check OK. The main routing/fault tests stub graph
cursors to isolate branch selection: they do **not** qualify real graph payload
authentication or substitute for a combined live Python publication/rollback
gate. Broader parent fault and live-transport evidence remain coordinator-owned.

## Matched callback measurements

Both modes use the immutable intermediate `library_dev1`: its unchanged old
broker callback versus the source-patched new lifetime. Other candidate helpers
are shared. This isolates the broker change; it is **not** a whole-library
`8f53e950` performance comparison. The complete repaired-revision workflow
baseline is retained separately by the coordinating qualification.

| Partitions | Old delivery s | New preparation s | New delivery s | Old full source checks | New full source checks |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 | 12.859 | 0.675 | 0.051 | 16 | 1 |
| 32 | 53.283 | 0.612 | 0.123 | 64 | 1 |

Every selected block exactly matched numerical values and ordered axes.
Preparation plus delivery is 5.65% / 1.38% of old delivery respectively;
the predeclared `0.4 * baseline + 0.05 s` budget is met. Maximum process RSS
was 626,332 KiB before and 616,568 KiB after; the +10 MiB budget is met.
Process-wide high-water marks include imports/fixture setup, not per-function
allocations. Common grant construction is outside the table's timed intervals;
these counts concern the broker source lifetime, not every parent/request hash.

Commands (run sequentially):

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/broker_before.log /tmp/scwb-engine-simplification-forge-20261018/broker_before.exit -- /usr/bin/time -v Rscript notes/engine_simplification/profile_broker_streaming.R baseline /tmp/scwb-engine-simplification-forge-20261018/library_dev1
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/broker_after.log /tmp/scwb-engine-simplification-forge-20261018/broker_after.exit -- /usr/bin/time -v Rscript notes/engine_simplification/profile_broker_streaming.R candidate /tmp/scwb-engine-simplification-forge-20261018/library_dev1
```

Both numeric sidecars are 0. The original before probe briefly overlapped the
aggregate-admission fixture setup; treat wall timings as bounded development
probes rather than isolated cold-cache hardware measurements. Scan counts and
exact values are independently asserted. Real broker/Python execution, parent
publication rollback and combined final qualification remain coordinator-owned.
