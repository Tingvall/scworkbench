# Bundle State Contract

`wb_manifest()` is the public dynamic current-state summary. On every call it
reads the authoritative SQLite registries and returns current matrix, space,
and artifact listings plus their counts. `wb_bundle_overview()` uses the same
public manifest identity and live getters, so its registry tables agree after
close/reopen.

Immutable creation facts live in `wb_manifest(bundle)$creation`: bundle id,
name, creation time, and identifier policy. The legacy top-level creation
fields remain for backwards compatibility. `manifest.json` is a portable cache
and bootstrap record, not an authority for mutable registry state; bundles
written before this contract are upgraded lazily when opened.

This separation prevents a registry mutation from committing a stale public
manifest summary. A failed mutation leaves the SQLite registries unchanged,
and the next dynamic manifest read therefore reports the same public state.

`wb_ingest_reports()` returns one row for every supported generic or container
ingestion report. Its stable fields are `artifact_id`, `name`, `description`,
`created_at`, `created_by`, `source_op`, `cell_set`, `report_type`,
`entity_kind`, and `meta_json`; ordering is newest `created_at` first, then
descending `artifact_id`.

Container feature metadata is an ingestion substep. It has its own persisted
provenance snapshot and promoted feature-table artifact, so it is discoverable
through public artifact and provenance interfaces after reopen without being
misrepresented as a separate scientific analysis operation.
