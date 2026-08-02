# scworkbench Foundation Contracts

This document defines the current contract for the foundation layers:

1. Data layer (SQLite + BPCells bundle)
2. Getter layer (`wb_*` read APIs)
3. Selector layer (`wb_sel_*`)

## Scope

These contracts are intended to be stable for all clients:

- notebooks
- Shiny apps
- AI agents

Ops/wranglers may evolve more quickly, but should build on these guarantees.

This document now also names the extension surfaces that sit directly above the
foundation and are expected to remain engine-owned:

- op catalog
- plot contracts / mappers
- identity-card issuers
- navigation resolvers

## Op/Wrangler Registration Contract

There is one canonical registration point for operations and wranglers:

- `R/op_catalog.R` via `.wb_op_catalog()`

Each op entry in `.wb_op_catalog()` defines, together:

- execution contract: `requires`, `produces`, `promotable`
- wrangler/runner: `runner(bundle, resolved, effective_cells, inputs, ...)`
- interface metadata: `title`, `description`, `intent`, `inputs`, `params`, `interface_produces`

Derived views must not be edited independently:

- `.wb_ops()` derives execution contract from `.wb_op_catalog()`
- `.wb_op_interface_registry()` derives interface contract from `.wb_op_catalog()`
- `.wb_op_dispatch_registry()` derives runners from `.wb_op_catalog()`

Adding a new op means adding one entry to `.wb_op_catalog()` plus the underlying `wb_op_*`
implementation function. Do not add parallel op lists in other files.

## Data Layer Contracts

### Source Ownership

Core, fragment, artifact, and provenance schema ownership is defined in
`docs/source_ownership.md`. Fresh initialization and migration call the same
canonical constructors; callers must not duplicate table DDL or runtime helper
definitions.

### Canonical Cell Order

- Canonical order is defined by `cells` table row order (`rowid`).
- `wb_cells(bundle, cell_set = "all")` is the canonical order source.

### Required Tables

At minimum, bundles should provide:

- `cells`
- `datasets`
- `features`
- `matrices`

Additional tables are optional based on capabilities (spaces, artifacts, etc.).

### Matrix Alignment

- Matrix columns are expected to align with canonical cell order.
- Getter functions that read matrix slices/vectors must preserve requested cell order.
- Peak matrices are expected to carry explicit genome metadata in the matrix
  registry:
  - `organism`
  - `genome_build`
  - optional `genome_provider`
- Clients should not invent genome/build semantics for peak matrices ad hoc.

### Motif Registry

The engine now has a canonical motif-registry surface distinct from feature
sets.

- `motif_libraries` defines motif-library identity:
  - `motif_library`
  - `source_type`
  - `organism`
  - `genome_build`
  - `collection`
  - `source_id`
  - `source_version`
- `motifs` defines motif identity within a library:
  - `motif_key` as the canonical engine identifier
  - optional external `motif_id`
  - `motif_name`
  - `matrix_class`
  - `payload_json`
  - `metadata_json`

Contract intent:

- motif definitions are first-class engine objects
- feature sets may cache motif-to-peak matches, but are not the canonical motif
  definition surface
- downstream ops (for example chromVAR, motif enrichment, regulatory summaries)
  should consume motif-library or motif-definition contracts rather than raw
  package-name strings as their final public shape

### Motif Match Contract

Motif-to-peak matches are a separate engine contract from motif definitions.

- `motif_match_sets` defines identity and provenance for one materialized match
  set:
  - `motif_match_set`
  - `matrix_id`
  - `motif_library`
  - `organism`
  - `genome_build`
  - `genome_provider`
  - `match_engine`
  - `match_params_json`
- `motif_match_membership` stores the actual motif-to-feature edges:
  - `motif_match_set`
  - `motif_key`
  - `feature_id`

Contract intent:

- motif definitions remain first-class biological objects
- motif matches are matrix-specific materializations with explicit provenance
- downstream ops may consume a `motif_match_set` when they need cached motif
  annotations for a specific peak universe
- sequence-backed motif ops should make seqlevel policy explicit; for chromVAR
  the default policy is standard chromosomes unless the user opts into broader
  inclusion

## Getter Layer Contracts

### Deterministic Ordering

- `wb_cells()` returns ordered `cell_id` vectors.
- `wb_meta(bundle, cells=...)` aligns rows to requested `cells` order.
- `wb_space(bundle, cells=...)` aligns outputs to requested `cells` order.
- `wb_space(bundle)` uses canonical all-bundle cell order restricted to cells
  present in that space. A 2D result remains a `cell_id,x,y` table and also has
  `rownames == cell_id`; numerical consumers use the canonical coordinate
  converter rather than `as.matrix()` on that table.

### Coverage Helpers

- `wb_cells_with_space()` returns cells with available coordinates for a space.
- `wb_cells_with_matrix()` returns available cells for a matrix.
- `wb_cell_coverage()` reports requested/effective coverage for input requirements.
- Effective-cell resolution (`.wb_effective_cells`) treats `inputs$cell_ids` as explicit
  requested universe override and then applies required-input intersections.
- Ops should rely on session-level effective-cell resolution instead of ad-hoc filtering.

### Type/Shape Guarantees

- Getter return classes and key columns are stable and documented in roxygen.
- Errors are raised for unknown IDs or invalid argument shapes.

## Selector Layer Contracts

### Input Model

Selectors accept:

- a bundle (`scworkbench_bundle`) as pipeline root
- selector output vectors with attached bundle metadata

### Output Model

Every selector returns:

- character vector of `cell_id`
- canonical bundle ordering
- attached bundle (`attr(x, "wb_bundle")`)
- attached recipe (`attr(x, "wb_recipe")`)

### Algebra Semantics

- `wb_sel_and`: intersection
- `wb_sel_or`: union
- `wb_sel_not`: universe minus input

All outputs are canonical-order deterministic.

## Reference Model Contracts

The engine supports a single canonical reference model across runtimes:

- `wb_ref_run(run_id, output_name)` for ephemeral session outputs
- `wb_ref_artifact(artifact_id, output_name)` for persisted outputs
- `wb_resolve_primitive()` as canonical resolver for primitive/spec/artifact/session refs
- `wb_vector_ref_to_spec()` and `wb_list_vector_sources()` for stable vector references

This reference model is intended to be shared by all clients (Shiny, Python, Node, agents).

## Tabular Primitive Contracts

The engine now supports canonical tabular primitives for analysis results:

- `feature_table` (rows are feature-level results; requires `feature_id` column)
- `obs_table` (generic entity-level tables: pathways, samples, clusters, etc.)

Primitive shape:

- `feature_table`:
  - `kind = "feature_table"`
  - `table_type` (string)
  - `table` (`data.frame`)
  - `meta` (list)
- `obs_table`:
  - `kind = "obs_table"`
  - `table_type` (string)
  - `entity_kind` (string, e.g. `sample`, `cluster`, `pathway`, `generic`)
  - `table` (`data.frame`)
  - `meta` (list)

Promotion contract:

- both kinds are promotable through `wb_promote_analysis()`
- artifact types:
  - `feature_table`
  - `obs_table`
- storage tables:
  - `artifact_tables` (metadata: `table_type`, `entity_kind`, `meta_json`)
  - `artifact_table_rows` (row-wise JSON payload, ordered by `row_idx`)

Loading contract:

- `wb_art_load()` reconstructs promoted table artifacts back to:
  - `wb_prim_feature_table(...)`
  - `wb_prim_obs_table(...)`

Wrangler contract:

- outward clients should use `wb_primitive_to_table()` / `wb_client_load_table()`
  for normalized display tables instead of reading primitive internals directly.

## Plot Contract Layer

Plot compatibility is not a client guess.

The engine owns:

- plot contracts
- plot mapper registry
- plot compatibility discovery
- normalized plot dataset wrangling

Clients should ask the engine which plot types are compatible and then render the
resulting normalized dataset/spec.

Plot semantics should not be reimplemented in Shiny or scripts.

## Identity Card Layer

The engine distinguishes:

- birth certificate: canonical provenance payload
- identity card: human-facing issuer summary

Identity-card issuers are an engine extensibility surface.

Clients should render identity cards, not invent their own artifact summaries.

## Navigation Layer

Cross-artifact and cross-plot handoff is also an engine contract.

The engine should declare:

- what entities a source contains
- what targets are valid
- what handoff payload should be sent

Clients should apply those payloads rather than inventing friendships from column
names or local heuristics.

## Validation Strategy

Foundation behavior is verified by:

- `tests/test_foundation_data_getters_selectors.R`
- exhaustive discovery and isolated execution through
  `inst/tests/run_contract_tests.R`

When contracts change, update:

1. this document
2. roxygen docs for affected functions
3. foundation tests
