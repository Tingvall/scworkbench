# Immutable entity history

Durable scientific identities are immutable after they participate in promoted
provenance. This applies to matrices, spaces, fitted models, promoted artifacts,
cell sets, feature sets, and other registry identities bound by a persisted run.
Changing an identifier in place would change the meaning of every historical
claim that referred to it, so the engine rejects that mutation before state is
written.

## Lifecycle state machine

New durable identities start as `current`. An unbound development identity may
be marked `ephemeral`. A current identity may become:

- `superseded`, through `wb_entity_supersede()` after a distinct successor ID
  has been created;
- `retracted`, through `wb_entity_retract()` or an API-specific compatibility
  wrapper such as `wb_art_delete()`;
- `rejected`, through `wb_entity_reject()` when a candidate is not accepted.

These historical states are terminal. Their registry and payload evidence stays
present. A successor-to-predecessor `SUPERSEDES` relationship records claim
replacement explicitly; creating a new identifier alone does not imply that
relationship.

`wb_entity_lifecycle()` returns all states and supports kind, ID, and state
filters. `wb_entity_supersessions()` returns explicit relationships. Registry
list getters default to current claims and accept `include_history = TRUE` where
applicable. Direct identity getters continue to resolve historical evidence by
ID. Artifact birth certificates include lifecycle state and supersessions.

## Schema

Writable bundle migration creates three SQLite tables:

- `entity_lifecycle`: one state row per immutable identity, including whether
  persisted provenance binds it;
- `entity_supersessions`: explicit successor/predecessor `SUPERSEDES` edges;
- `entity_tombstones`: retained retraction or rejection records and reasons.

The schema contract is `scworkbench.entity_lifecycle.v1`. The composed
provenance DAG sets entity-node `status`, `canonical`, and `superseded`, emits
`SUPERSEDES` edges, and honors `include_superseded = FALSE` as a current-claim
view. Bundle/provenance knowledge graphs carry lifecycle payloads and the same
relationships.

## Existing overwrite and deletion APIs

`overwrite = TRUE` remains useful only for unbound staging or development
identities. It cannot replace a provenance-bound matrix, space, model, cell set,
or feature set. Create a new ID, execute/promote it normally, then call
`wb_entity_supersede()` with a reason.

`wb_art_delete()` is a compatibility name for retraction. It keeps artifact
payload rows, model files, content SHA-256 evidence, birth certificates, and
provenance links. `recursive = TRUE` retracts the dependent closure. The former
destructive flags `force = TRUE` and `remove_model_file = TRUE` now fail with a
migration message.

Physical deletion is available only as
`wb_unsafe_purge_ephemeral_entity()`. It requires the exact confirmation string,
an explicit `ephemeral` lifecycle state, no provenance binding, and no
supersession reference. Matrix payload purge is deliberately unsupported; a
disposable development bundle should be removed as a unit instead. Internal
transaction rollback may still remove incomplete, never-committed staging rows;
that cleanup is not deletion of a durable scientific entity.

UMAP projection now accepts `space_id_out`. Projecting into an already promoted
fitted space is rejected because it would mutate that space's cell-coordinate
identity. Use a new output space ID; the fitted model remains the model input.

## Migration and clients

`wb_open_bundle()` runs lifecycle migration on writable bundles. Existing
matrix, space, model, artifact, set, and provenance-binding inventories are
registered without changing payloads. A legacy provenance binding whose
registry payload is already missing is represented as `retracted`, preserving
the historical claim instead of silently presenting it as current. Read-only
legacy bundles are not modified; reopen writable once to persist the migration.

Clients should render current claims by default, offer an explicit history
view, label rejected/retracted evidence, and never translate an overwrite
failure into an automatic new name. The caller must choose the successor ID and
declare the supersession reason. Recipient reconstruction and audit tools should
retain historical nodes because those nodes remain valid evidence even when
they are no longer current claims.
