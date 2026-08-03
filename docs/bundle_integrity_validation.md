# Bundle integrity validation

`wb_bundle_validation_report()` is the structured, read-only integrity API.
`wb_validate_bundle()` retains the established `TRUE`-or-error contract and
uses content validation by default; `read_only = TRUE` selects recipient
validation.

The levels are cumulative:

- `structural` proves that the supported manifest and SQLite schema open
  read-only, required registries exist, cached manifest counts and inventories
  agree with SQLite, identities are well formed, and durable paths exist with
  the declared file type inside the bundle. It does not prove payload bytes or
  provenance content identities.
- `content` additionally runs SQLite `integrity_check`; verifies exact ordered
  matrix feature/cell identities, normalized fragment memberships, fragment
  coverage, space coordinates, model loadability, artifact payload ownership,
  source declarations, provenance runs/outputs/bindings/DAG edges, commits,
  materializations, registry mutations, lifecycle/tombstone history, and every
  locally verifiable SHA-256 claim. Matrix values are never densified. Table
  artifact identities are folded from ordered JSON rows in bounded chunks.
  Durable R-object identities use a typed canonical JSON representation, so
  validation is stable across supported R runtime versions.
  Unavailable external (non-bundled) sources are warnings and explicitly remain
  unverifiable.
- `recipient` adds finalized-transfer invariants: no active writer, pending
  workspace, failed ingestion marker, or SQLite WAL/SHM/journal sidecar; a
  successful immutable SQLite open; and equal pre/post filesystem fingerprints.

Every diagnostic is a row with a stable code and severity, check class, entity
kind/ID, path/table, expected/observed value, and message. Reports also contain
completed levels, explicitly skipped checks, elapsed time per check class, and
peak R memory evidence. `ok = TRUE` means every requested check completed
without an error; warnings remain visible in `status = "ok_with_warnings"`.

The default is `content`. It is compatible with the former validator's habit of
opening every matrix, while avoiding the inaccurate claim that a dimensional
smoke test establishes content integrity. Use explicit `structural` only for a
fast registry preflight and explicit `recipient` for transferred/finalized
copies.

## Measured compatibility boundary

Read-only content validation was exercised on 2026-08-03 against the three
published bundle shapes without rewriting them:

| Bundle | Cells | Runtime | Peak R memory | Compatibility result |
|---|---:|---:|---:|---|
| Honeybee RC9 | 120,895 | 96.306 s | 806.8 MiB | Legacy cached manifest disagreement and nine pre-canonical 10x fragments whose BPCells column names retain raw barcodes while their registry declares prefixed canonical IDs. |
| scPerturb RC22 clone | 30,707 | 33.682 s | 1008.4 MiB | Legacy cached manifest disagreement and two table artifacts recorded with the pre-streamed R-object hash scheme. |
| Aztekin SCE (manifest 2.0.0) | 13,199 | 14.223 s | 525.8 MiB | Four cached manifest inventory/count disagreements; the older 2.0 manifest is supported read-only and was not migrated. |

Pre/post filesystem fingerprints were identical for all three final read-only
runs. Those findings are reported, not repaired in place. Fresh bundles use canonical
10x payload names, refresh the transfer manifest only after committed promotion,
and record streamed durable table identities, so the valid promoted PBMC
vertical-slice regression passes all three levels. The disposable corruption
suite covers manifest, matrix/fragment, space, model, artifact, source,
provenance, lifecycle, path-containment, pending-state, active-writer, and WAL
diagnostics.
