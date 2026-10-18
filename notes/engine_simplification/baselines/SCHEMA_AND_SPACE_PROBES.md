# Structural consolidation and selected-space measurements

Read Sable's complete SABLE_SCHEMA_STATUS_MEMO_REVIEW.md before implementing
the narrow schema change. Root owns other runtime files and lifecycle forget
hooks. No installed/shared library was modified by these probes.

## Implemented structural schema observation

R/schema_migrations.R only: `.wb_schema_status(con,verify_structure=FALSE)`
keeps ledger presence/rows/ordered-prefix/version decisions fresh. Only a
successful exact FK/nullability verdict is reusable in this live connection.
Key: fresh ordered exact main `(type,name,tbl_name,sql)` records over the
current FK-contract tables plus artifact_pseudotime, with explicit missing
entries. TEMP table/view shadows are checked case-insensitively; any relevant
shadow bypasses reuse and retains the original unqualified-PRAGMA semantics.
Graph-policy calls bypass reuse/key collection and retain original FK reads.
An explicit verify_structure=TRUE always performs full structural reads.
Public wb_bundle_schema_status signature is unchanged and invokes that full
path; migration admission/final checks do likewise. Existing migration
source_forget call was preserved. No row-data verdict, error or complete
schema-status result is cached. A failed fresh structural check clears old
success. Root's backup/restore/migration/close forget owner clears observation.

Focused source-patch-only gate: **exit0**, files1/discovered3/passed3/failed0,
wall19.88 seconds, RSS141,336 KiB. New tests cover repeated FK reuse with fresh
ledger reads, ledger DML, explicit/full-public reads, graph bypass, missing and
changed FKs, nullability, case-insensitive TEMP shadows of both relevant kinds,
DDL transaction rollback/schema-epoch reuse, new connections, source forget
and actual session-backup invalidation. All altered schemas are test-owned.

Repeated-status timing probe on the same existing synthetic fixture:

| Mode | Calls | Total seconds | Per call |
| --- | ---: | ---: | ---: |
| Repaired baseline | 50 | 5.756 | .11512 |
| Source patch cold | 1 | .174 | .17400 |
| Source patch repeated | 50 | .252 | .00504 |
| Source patch explicit full | 50 | 6.123 | .12246 |

Status values/messages are identical. Ordinary repeated structural work is
22.84x faster; explicit full verification remains intentionally expensive.
This component result is not the full synthetic-import <=17.3-second budget
gate, which root will measure against the assembled installed candidate.

## Selected-space and object descriptor probe (no runtime changes)

Exact repaired installed namespace, real independent PCA-derived 13,199x30
selected coordinates. `space_identity_probe.R` also constructs a separate
vectorized canonical oracle using sprintf scientific coefficients, independent
of the engine's numeric/JSON encoders; small zero/negative/extreme vectors and
the complete selected space have identical hashes. The oracle builds a single
string in this bounded component probe; it is NOT a proposed bounded large-space
production implementation.

- Scheme scworkbench.operation_pack.space_slice.content.v1
- SHA-256 `59010683b1f470c7d069baff4afc2af9d3ea3735ed0f6c52314204b60befac40`
- Canonical bytes8,237,398
- Existing selected-space projection2.806 seconds; independent oracle2.555
- Complete probe wall15.04 seconds, peakRSS275,832 KiB, exit0

| Primitive | Object provenance hash seconds | Input descriptor seconds |
| --- | ---: | ---: |
| 13,199-value cell_vector | .018 | 1.628 |
| 26,398-row cell_vector_family | .041 | 3.581 |
| 26,398-row relation_family | .041 | 3.568 |
| Tiny model_ref | .001 | .006 |

These use different existing identity schemes; no equality across schemes is
claimed. Full frozen identities are in space_identity_before.csv. Descriptor
hashing itself uses repeated canonical representations: input content plus
the same input/value wrapper for ancestry and payload manifest at
R/operation_pack_v2_transition.R:260–262. Invocation-local exact preimage reuse
is a plausible root-owned optimization; this probe implements none. Any future
encoder change must retain exact bytes/digest, bounded memory and existing
invalid-value rejection. Prospective >=3x encoder budget is in BUDGETS.md;
the independent oracle does NOT meet it and is not claimed to do so.

No model-tree audits, model loading, large families, Python execution, scientific
workflow or engine-wide performance qualification follows from these timings.
No source/runtime changes were made to space/object/model paths by this helper.

## Commands

All prefixed with `inst/ci/run_logged_gate LOG EXIT -- /usr/bin/time -v`:

```
Rscript notes/engine_simplification/run_schema_source_patch.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library
Rscript notes/engine_simplification/schema_status_probe.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/profile-synthetic-import/synthetic.bundle/db/app.sqlite /tmp/scwb-engine-simplification-forge-20261018/schema_status_probe.csv
Rscript notes/engine_simplification/baselines/space_identity_probe.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/direct-xenopus-v3 /tmp/scwb-engine-simplification-forge-20261018/space-identity-before
```

All numeric sidecars0. Parsing and git diff --check passed. Full import/pipeline
or complete-suite reruns, merge, push, profile changes and builds were not run.
