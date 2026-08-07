# Bundle integrity validation

`wb_bundle_validation_report()` is the structured, read-only integrity API.
`wb_validate_bundle()` retains the established `TRUE`-or-error contract and
uses content validation by default; `read_only = TRUE` selects recipient
validation.

`wb_bundle_validation_plan(level)` lists cumulative check classes and their
dominant scaling. `wb_bundle_validation_report(..., progress = TRUE)` emits
start/completion events with elapsed time, current RSS, and process peak RSS;
passing a callback retains the same structured events elsewhere. The returned
`resource_samples`, `process_peak_rss_mb`, and `elapsed_by_check_class` preserve
diagnostic evidence. Recipient validation fingerprints every contained file
before and after validation, so its filesystem work scales with bundle bytes;
matrix checks scale with ordered identities and fragment count, while external
files are never accessed.

The levels are cumulative:

- `structural` proves that the supported manifest and SQLite schema open
  read-only, required registries exist, authoritative manifest counts,
  inventories, per-table hashes, and the aggregate current-state fingerprint
  agree with SQLite, identities are well formed, and durable paths exist with
  the declared file type inside the bundle. It does not prove payload bytes or
  provenance content identities.
- `content` additionally runs SQLite `integrity_check`; verifies exact ordered
  matrix feature/cell identities, normalized fragment memberships, fragment
  coverage, space coordinates, model loadability, artifact payload ownership,
  source declarations, provenance runs/outputs/bindings/DAG edges, commits,
  materializations, registry mutations, lifecycle/tombstone history, and every
  locally verifiable SHA-256 claim. Persisted run validation parses all six
  run-contract JSON documents, recomputes `run_hash` and `contract_hash`, and
  resolves symbolic run/artifact ancestry, typed entity bindings, source
  identities, and artifact ancestry. Matrix values are never densified. Table
  artifact identities are folded from ordered JSON rows in bounded chunks.
  Durable R-object identities use a typed canonical JSON representation, so
  validation is stable across supported R runtime versions. Ordinary
  retraction/rejection tombstones do not authorize payload deletion: current,
  superseded, retracted, and rejected provenance-bound payloads remain
  physically present and content-verifiable.
  Unavailable external (non-bundled) sources are warnings and explicitly remain
  unverifiable.
- `recipient` adds finalized-transfer invariants: no active writer, pending
  workspace, failed ingestion marker, or SQLite WAL/SHM/journal sidecar; a
  successful immutable SQLite open; and equal pre/post filesystem fingerprints.

Content identities are typed and versioned. Current producers persist distinct
scheme identifiers for canonical objects, streamed tables, matrix fragment
trees, spaces, raw files, file trees, and registry values. Promotion,
materialization, replay-equivalence verification, lifecycle bindings, and
validation carry the same scheme. A 64-character digest without a scheme is a
legacy/unverifiable claim, never silently interpreted as a current hash. The
report's `content_coverage` table accounts for every bundle-owned durable
matrix, space, model, artifact, and provenance-bound registry entity as
`content_verified`, `structurally_checked_only`, `legacy_unverifiable`, or
`content_mismatch`; declared non-bundled sources can be
`externally_unavailable`. Missing baselines produce
`DURABLE_CONTENT_IDENTITY_MISSING`; unavailable non-bundled source inputs retain
their separate warning-only exception.

Path-only validation fails closed with
`SQLITE_ACTIVE_WAL_SNAPSHOT_REQUIRED` when a non-empty WAL is active. Even a
SQLite `mode=ro` connection can change shared-memory lock bytes, so the
validator does not open, restore, checkpoint, or rewrite an active WAL bundle.
Finalize it or provide a separately supported immutable snapshot. Pending
workspace diagnostics are recipient-only, matching the finalized-transfer
taxonomy.

Every diagnostic is a row with a stable code and severity, check class, entity
kind/ID, path/table, expected/observed value, and message. Reports also contain
completed levels, explicitly skipped checks, elapsed time per check class, and
peak R memory evidence. `ok = TRUE` means every requested check completed
without an error; warnings remain visible in `status = "ok_with_warnings"`.

Fresh manifests use schema 2.2 and identify the atomic publication protocol and
durable state source. `MANIFEST_REGISTRY_MISMATCH` is recoverable: it means a
committed registry change exists but the previous complete manifest was
preserved because publication did not reach its atomic rename. Validation is
read-only and never performs that repair.

The default is `content`. It is compatible with the former validator's habit of
opening every matrix, while avoiding the inaccurate claim that a dimensional
smoke test establishes content integrity. Use explicit `structural` only for a
fast registry preflight and explicit `recipient` for transferred/finalized
copies.

## Measured compatibility boundary

Read-only content validation was exercised again on 2026-08-04 against the three
published bundle shapes without rewriting them:

| Bundle | Cells | Runtime | Peak R memory | Compatibility result |
|---|---:|---:|---:|---|
| Honeybee RC9 | 120,895 | 97.942 s | 807.4 MiB | Legacy cached manifest disagreement, pre-canonical 10x physical names, and durable entities that predate baseline content identities. |
| scPerturb RC22 clone | 30,707 | 50.138 s | 1010.3 MiB | Legacy cached manifest disagreement, explicitly untagged pre-scheme artifact identities, and durable entities without baselines. |
| Aztekin SCE (manifest 2.0.0) | 13,199 | 9.670 s | 556.5 MiB | Four cached manifest disagreements plus legacy run rows that predate operation-version and typed input-binding claims; no read-only migration was attempted. |

Pre/post filesystem fingerprints were identical for all three final read-only
runs. Those findings are reported, not repaired in place. Fresh bundles use canonical
10x payload names, refresh the transfer manifest only after committed promotion,
and record streamed durable table identities, so the valid promoted PBMC
vertical-slice regression passes all three levels. The disposable corruption
suite additionally covers valid-JSON run tampering, all persisted input forms,
stale run/contract hashes, typed and symbolic ancestry, source identities,
artifact ancestry, retained retracted/rejected payloads, valid loadable payload
substitutions, untagged legacy hashes, missing baselines, and byte-identical
active-WAL failure.

On 2026-08-07 the immutable RC23 GSE270605 diagnostic bundle (120,895 cells,
569 MiB on disk) completed full recipient validation in 40.04 seconds. External
`/usr/bin/time -v` evidence recorded 831,340 KiB maximum RSS, 1,188,584
filesystem input blocks, zero swaps, no signal, and successful authoritative
validation (`ok_with_warnings`; warnings were the 30 intentionally uninspected
external files). All per-check timings completed and the pre/post fingerprints
were identical. This establishes a measured bounded-memory completion, not an
OOM inference.
