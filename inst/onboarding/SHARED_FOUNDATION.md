# Agent Shared Foundation

For externally supplied per-cell tables, use the checksummed public boundary in
`METADATA_IMPORT.md`; do not mutate SQLite directly.

## Durable custom analysis

Ad hoc analysis is permitted; unrecorded durable evidence is not. Registered
ops remain the normal path. A provenance-bound analysis capsule is the narrow
exception for externally executed, dataset-specific terminal figures, reports,
or summaries. A capsule should contain only the irreducibly dataset- or
question-specific terminal portion; see `ANALYSIS_CAPSULES.md`.

Shared concepts for all agent roles in `scworkbench`.

## System Identity

`scworkbench` is the engine.
Clients (Shiny, scripts, notebooks, agents) are thin interfaces.

## Core Model

1. Bundle
- Portable analysis unit and source of truth.
- Persists data, sets, artifacts, runs, and provenance.

2. Data Layer
- Physical storage may be fragmented/optimized.
- Logical access must be unified and contract-stable.

3. Getter Boundary
- Getters are the only storage-facing API.
- Downstream compute should not depend on storage internals.

4. Selectors
- Composable query language over the getter universe.
- Intended for reproducible selection intent (recipes), not one-off filtering.

5. Primitives
- Typed internal currency:
  `matrix`, `space`, `space_2d`, `cell_vector`, `cell_vector_family`,
  `feature_table`, `obs_table`, `model_ref`, `path_2d_family`.
- Ops consume/emit primitives.
- Wranglers map primitives to display/report contracts.

6. Plot Contracts
- Plot compatibility is engine-owned.
- Primitive kind alone does not determine the right plot.
- Clients should ask the engine which plot contracts are compatible and let
  wranglers normalize display datasets.

7. Identity Cards
- Birth certificates are canonical provenance payloads.
- SQLite is the registry/control plane for dense spaces; numerical coordinates
  are held once in contained, versioned HDF5 payloads. `wb_space()` is the
  stable boundary and performs bounded row/dimension reads for subsets.
- Identity cards are human-facing issuers layered on top of birth certificates.
- Human summaries belong in issuers, not in ad hoc client logic.

8. Navigation
- Cross-artifact handoff is an engine concern.
- Clients should not invent friendships between plots or artifacts.
- Navigation targets and handoff payloads should come from engine contracts.

9. Promotion + Provenance
- Session work can be exploratory.
- Only selected outputs are promoted.
- DAG/provenance is mandatory for reproducibility and replay.
- Provenance-bound scientific identities are immutable. Revisions use a new
  identifier plus `wb_entity_supersede()`; retraction keeps evidence. Inspect
  states with `wb_entity_lifecycle()` and see `docs/entity_lifecycle.md`.
  Promotion atomically converts selected ephemeral work to a current,
  content-identified durable claim; terminal history is never revived.
  Content SHA-256, structural fingerprints, run/contract integrity, promotion
  materialization compatibility, and graph identifiers are distinct versioned
  identity schemes. Mixed historical/current provenance remains valid after
  migration without rewriting legacy hashes. See
  `docs/provenance_identity_schemes.md`.

10. Contract-Owned Friendships
- If two objects have a stable analytical relationship, encode it as an engine
  contract rather than client convention.
- Current important example:
  - peak matrix -> genome build
  - motif library -> motif definitions
  - motif match set -> matrix-specific motif-to-peak materialization
  - chromVAR -> motif activity over those contracts
- See `docs/motif_contracts_and_chromvar.md`.

## Non-Negotiable Invariants

- Engine semantics must be client-independent.
- Primitive contracts are stable interfaces.
- Plot contracts, identity cards, and navigation are also engine contracts.
- Claims in reports map to run/artifact IDs.
- Prefer symbolic references (`set:<name>`, refs) over huge literal payloads.

## Cell metadata identities

Imported cell metadata is governed by a durable field registry rather than raw
SQLite column names. Inspect it with `wb_metadata_fields()` and resolve one field
with `wb_metadata_field_resolve()`. Exact source names are preserved when
unambiguous; collisions and reserved names retain their source spelling but use
stable `meta:NNNNNN` identities and private physical storage. Ambiguous names
must be addressed with `wb_ref_metadata_field()`, not a bare stable-ID-shaped
string. Input column names remain source names even when they look like
`meta:*`, `core:*`, or `__wb_meta_*`; explicit compatible updates use the
position-aligned `field_refs` channel of `wb_attach_metadata()`. Default
`wb_meta()` always exposes literal core aliases `cell_id` and `dataset_id`.
See `docs/metadata_field_identity.md` for namespace, type, update, rollback,
bounded content identity, current producer, historical update, and set-based
ingestion rules.

# Provenance-only mutation boundary

An ordinary `wb_open_bundle()` handle represents committed scientific state.
Compute through `wb_session_run_op()` and save through
`wb_session_promote_current()`; thin clients use the equivalent
`wb_client_run()` and `wb_client_promote()` facade. Direct mutating operation
implementations and low-level registry, matrix, space, model, and primitive
payload writers are rejected before a committed write.

Direct writes remain supported only inside a declared ingestion transaction
(`wb_bundle_from_*()`, `wb_ingest_apply()`, or `wb_attach_apply()`) or on the
active assembly handle returned by `wb_init_bundle()`. Ingestion records durable
outputs and declared source inputs. Reopening the bundle ends assembly authority.
Inspect the machine-readable ownership inventory with
`wb_mutation_catalog_semantic()`.

# Bundle integrity proof

`manifest.json` is an atomically published authoritative snapshot of committed
registry state, not a cache hidden by getters. `wb_manifest(bundle)` reads that
durable snapshot; use `wb_manifest(bundle, view = "reconstructed")` only to
diagnose a recoverable publication disagreement. Every committed writer route
publishes while retaining the exclusive bundle-writer lock.

Manifest schema 2.3 never presents matrix-scoped feature registry rows as a
biological `n_features`. Read `counts$feature_registry_records` for physical
registry rows and `counts$feature_counts_by_matrix` for each matrix's feature
universe. `counts$bundle_unique_feature_count` is `not_applicable` because the
engine does not declare cross-matrix identifier or modality namespaces
equivalent.

Use `wb_bundle_validation_report()` when a structured integrity result is
needed. `structural`, `content`, and `recipient` are cumulative proof levels;
only content/recipient verify tagged payload identities and the complete
persisted run contract. `content_coverage` exposes every bundle-owned durable
entity's verification status. Recipient bundles must be finalized with no
active WAL, writer, or pending workspace. See
`docs/bundle_integrity_validation.md`.
