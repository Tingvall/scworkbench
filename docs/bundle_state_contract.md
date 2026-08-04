# Bundle State Contract

`manifest.json` is the portable authoritative snapshot of committed registry
state. `wb_manifest()` reads that durable file directly by default; it does not
hide a stale file behind live SQLite reconstruction. The manifest contains
current counts and inventories plus `current_state`, a versioned set of row
counts and canonical SHA-256 identities for every supported registry table.
`publication$state_source = "durable_manifest"` makes the source explicit.

Immutable creation facts live in `wb_manifest(bundle)$creation`: bundle id,
name, creation time, and identifier policy. The legacy top-level creation
fields remain for backwards compatibility. Current-state fields are replaced
after every successful committed writer route and are never used as creation
identity.

Use `wb_manifest(bundle, view = "reconstructed")` only for diagnosis. That
read-only view is rebuilt from SQLite and identifies itself with
`publication$state_source = "reconstructed_diagnostic"`; its
`durable_registry_agreement` flag says whether it matches the durable snapshot.

Manifest schema 2.2 uses `scworkbench.manifest.atomic.v1`: the writer lock is
acquired before mutation, payload and SQLite work commits first, a complete
same-directory temporary JSON file is written/flushed/closed and parsed, and a
single portable filesystem rename publishes it. If staging, validation, or replacement fails, the
previous complete manifest remains at `manifest.json`. The registry commit is
not misrepresented as rolled back: reconstructed diagnosis and integrity
validation report the recoverable manifest/registry disagreement until a
guarded refresh succeeds.

`wb_ingest_reports()` returns one row for every supported generic or container
ingestion report. Its stable fields are `artifact_id`, `name`, `description`,
`created_at`, `created_by`, `source_op`, `cell_set`, `report_type`,
`entity_kind`, and `meta_json`; ordering is newest `created_at` first, then
descending `artifact_id`.

Container feature metadata is an ingestion substep. It has its own persisted
provenance snapshot and promoted feature-table artifact, so it is discoverable
through public artifact and provenance interfaces after reopen without being
misrepresented as a separate scientific analysis operation.
