# Agent Shared Foundation

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
