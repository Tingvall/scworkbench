# scworkbench Getter Catalog

<!-- Generated from wb_getter_catalog_semantic(); do not edit getter entries by hand. -->

Generated at: 2026-08-03T13:53:15+0200

Getter count: 77

This document summarizes safe bundle getter and inspection functions for humans, agents, and semantic indexing.
The machine-readable companion is `docs/getter_catalog_semantic.json`.

## artifacts

### `wb_art_list`

Title: Artifacts

Description: List promoted artifacts, optionally filtered by type.

Returns: data.frame

Payload level: metadata

Arguments: bundle, type, include_history

Use when:
- find promoted outputs
- choose artifact for plotting or loading

### `wb_list_trajectory_models`

Title: Trajectory Model Inventory

Description: List promoted model_ref trajectory candidates with engine, provenance, and optional pseudotime coverage.

Returns: data.frame

Payload level: metadata

Arguments: bundle, inspect_payload

Use when:
- choose trajectory model
- review trajectory candidates for reports or agents

### `wb_trajectory_lineage_weights`

Title: Trajectory Lineage Weights

Description: Load Slingshot lineage membership weights as a cell_vector_family from a promoted lineage_weights artifact, promoted sibling trajectory artifact, or in-memory Slingshot model_ref fallback.

Returns: wb_primitive cell_vector_family

Payload level: payload

Arguments: bundle, model_ref, pseudotime_artifact, lineage_weights_artifact

Use when:
- restrict trajectory universes by lineage membership
- filter cells by Slingshot lineage weight
- derive claim-supporting trajectory cell sets

### `wb_trajectory_fit_info`

Title: Trajectory Fit Identity

Description: Inspect the trajectory_fit_id, engine, lineage keys, and available cell universe metadata for a trajectory primitive or promoted artifact.

Returns: data.frame

Payload level: metadata

Arguments: bundle, x, runs

Use when:
- audit trajectory fit-family identity
- check whether trajectory artifacts can be combined

### `wb_trajectory_assert_fit_compatible`

Title: Trajectory Fit Compatibility Assertion

Description: Fail loudly when trajectory artifacts come from different trajectory fit families; shared labels such as L1 are not sufficient compatibility evidence.

Returns: invisible data.frame or error

Payload level: metadata

Arguments: bundle, ..., runs, allow_legacy

Use when:
- validate pseudotime, weights, model, and path compatibility
- prevent cross-fit lineage-label mixing

### `wb_art_load`

Title: Load Artifact

Description: Load a promoted artifact as a primitive.

Returns: wb_primitive

Payload level: payload

Arguments: bundle, artifact_id, expected_kind

Use when:
- load promoted output for downstream analysis

### `wb_art_table_info`

Title: Table Artifact Info

Description: Read metadata for a promoted table artifact.

Returns: data.frame

Payload level: metadata

Arguments: bundle, artifact_id

Use when:
- inspect table type before slicing

### `wb_art_table_slice`

Title: Table Artifact Slice

Description: Read a bounded row slice from a promoted feature_table or obs_table.

Returns: data.frame

Payload level: payload

Arguments: bundle, artifact_id, filters, limit

Use when:
- preview artifact table without full load
- filter promoted dynamics tables

### `wb_art_table_distinct`

Title: Table Artifact Distinct Values

Description: List distinct values from one promoted table artifact column.

Returns: vector

Payload level: metadata

Arguments: bundle, artifact_id, column, filters, limit

Use when:
- enumerate lineage IDs
- find feature sets in an artifact

### `wb_art_identity_card`

Title: Artifact Identity Card

Description: Summarize artifact identity, provenance, labels, and display hints.

Returns: list

Payload level: metadata

Arguments: bundle, artifact_id

Use when:
- explain an artifact to an agent or user

### `wb_art_birth_certificate`

Title: Artifact Birth Certificate

Description: Read provenance/birth metadata for a promoted artifact.

Returns: list

Payload level: metadata

Arguments: bundle, artifact_id

Use when:
- trace artifact provenance

### `wb_art_dependencies`

Title: Artifact Dependencies

Description: Get dependency relationships for an artifact.

Returns: data.frame/list

Payload level: metadata

Arguments: bundle, artifact_id

Use when:
- inspect downstream/upstream artifact relationships

### `wb_art_trajectory_related`

Title: Related Trajectory Artifacts

Description: Find trajectory-related sibling artifacts for a source artifact.

Returns: list

Payload level: metadata

Arguments: bundle, artifact_id

Use when:
- navigate between trajectory DE, smooth, and signature artifacts

## bundle

### `wb_status`

Title: Bundle Status

Description: Summarize bundle health and high-level registry counts.

Returns: list

Payload level: metadata

Arguments: bundle

Use when:
- check whether a bundle is readable
- get a quick bundle overview

### `wb_manifest`

Title: Bundle Manifest

Description: Read the bundle manifest metadata.

Returns: list

Payload level: metadata

Arguments: bundle

Use when:
- inspect bundle identity
- read manifest fields

### `wb_bundle_overview`

Title: Bundle Overview

Description: Summarize bundle identity, validation state, registries, artifact counts, and provenance heads for read-only clients.

Returns: list

Payload level: metadata

Arguments: bundle, validate

Use when:
- build collaborator dashboard
- inspect bundle readiness without direct SQL

### `wb_bundle_schema`

Title: Bundle Schema

Description: Inspect available SQLite schema objects in the bundle.

Returns: data.frame/list

Payload level: metadata

Arguments: bundle

Use when:
- debug bundle tables
- inspect schema capabilities

### `wb_list`

Title: Registry List

Description: List common registry tables such as matrices, features, spaces, or datasets.

Returns: data.frame

Payload level: metadata

Arguments: bundle, what

Use when:
- quickly inspect registry content

## cells

### `wb_cells`

Title: Cell IDs

Description: Return cell IDs in canonical bundle order, optionally restricted to a cell set or dataset.

Returns: character vector

Payload level: metadata

Arguments: bundle, cell_set, dataset_id

Use when:
- get cells for an analysis
- resolve a cell set to cell IDs

### `wb_cell_sets`

Title: Cell Sets

Description: List available cell sets in a bundle.

Returns: character vector

Payload level: metadata

Arguments: bundle, include_history

Use when:
- find available subsets
- choose cell_set input for an op

### `wb_resolve_cell_set`

Title: Resolve Cell Set

Description: Resolve a cell-set selector into concrete cell IDs.

Returns: character vector

Payload level: metadata

Arguments: bundle, cell_set

Use when:
- expand set:<name>
- verify effective cell IDs

### `wb_meta`

Title: Cell Metadata

Description: Read cell-level metadata for selected cells and columns.

Returns: data.frame

Payload level: metadata

Arguments: bundle, cells, cols, dataset_id

Use when:
- inspect annotations
- fetch labels or covariates

### `wb_cell_metadata_columns`

Title: Cell Metadata Columns

Description: List cell metadata columns with type, missingness, cardinality, and display hints for clients.

Returns: data.frame

Payload level: metadata

Arguments: bundle, summarize, max_distinct_for_grouping

Use when:
- choose metadata coloring columns
- avoid direct SQLite metadata introspection

### `wb_cell_coverage`

Title: Cell Coverage

Description: Summarize which cells are covered by matrices, spaces, and sets.

Returns: data.frame/list

Payload level: metadata

Arguments: bundle

Use when:
- check data coverage before running ops

## client

### `wb_client_discover`

Title: Client Discovery

Description: Client facade for discovering bundle state and available operations.

Returns: list

Payload level: metadata

Arguments: bundle

Use when:
- initialize UI or agent context

### `wb_client_inspect`

Title: Client Inspect

Description: Client facade for inspecting session and bundle runtime state.

Returns: list

Payload level: metadata

Arguments: bundle, session

Use when:
- summarize current analysis state

### `wb_client_load`

Title: Client Load

Description: Client facade for loading primitives by reference.

Returns: wb_primitive

Payload level: payload

Arguments: bundle, ref, session

Use when:
- load selected artifact or session output

### `wb_client_load_table`

Title: Client Load Table

Description: Client facade for loading and wrangling references into normalized tables.

Returns: data.frame

Payload level: payload

Arguments: bundle, ref, session, key

Use when:
- preview primitive data in a table

## feature_sets

### `wb_feature_sets`

Title: Feature Sets

Description: List feature sets and namespaces in the bundle.

Returns: data.frame

Payload level: metadata

Arguments: bundle, matrix_id, namespace, organism, origin, include_history

Use when:
- find gene-set libraries
- choose namespace for enrichment or dynamics

### `wb_feature_set_info`

Title: Feature Set Info

Description: Read metadata for one feature set.

Returns: data.frame

Payload level: metadata

Arguments: bundle, feature_set, matrix_id

Use when:
- inspect gene-set provenance and metadata

### `wb_feature_set_get`

Title: Feature Set Members

Description: Get feature IDs from one feature set.

Returns: character vector

Payload level: metadata

Arguments: bundle, feature_set, matrix_id

Use when:
- inspect gene-set members
- debug missing genes

## features

### `wb_features`

Title: Features

Description: Read feature registry rows, optionally filtered by matrix or feature type.

Returns: data.frame

Payload level: metadata

Arguments: bundle, matrix_id, feature_type

Use when:
- inspect feature metadata
- find available genes or peaks

### `wb_feature_ids`

Title: Feature IDs

Description: Get feature IDs in canonical order for a matrix.

Returns: character vector

Payload level: metadata

Arguments: bundle, matrix_id, feature_type

Use when:
- verify feature availability
- choose genes for scoring

### `wb_search_features`

Title: Search Features

Description: Search feature IDs or feature metadata.

Returns: data.frame

Payload level: metadata

Arguments: bundle, query, matrix_id

Use when:
- find matching genes/features by text

## matrices

### `wb_cells_with_matrix`

Title: Cells With Matrix

Description: List cells available for a given matrix.

Returns: character vector

Payload level: metadata

Arguments: bundle, matrix_id

Use when:
- intersect cells with matrix coverage

### `wb_matrices`

Title: Matrices

Description: List matrices available in the bundle.

Returns: data.frame

Payload level: metadata

Arguments: bundle, include_history

Use when:
- choose matrix input for an op

### `wb_matrix_info`

Title: Matrix Info

Description: Read matrix registry metadata, optionally for one matrix.

Returns: data.frame

Payload level: metadata

Arguments: bundle, matrix_id

Use when:
- inspect matrix type, dimensions, and metadata

### `wb_matrix_fragments`

Title: Matrix Fragments

Description: List physical storage fragments backing a logical matrix.

Returns: data.frame

Payload level: metadata

Arguments: bundle, matrix_id

Use when:
- debug fragmented matrix storage

### `wb_matrix_resolve`

Title: Resolve Matrix

Description: Resolve matrix fragments to absolute storage paths.

Returns: data.frame/list

Payload level: metadata

Arguments: bundle, matrix_id

Use when:
- inspect physical matrix payload locations

### `wb_matrix`

Title: Matrix Handle

Description: Open a matrix handle for a matrix ID.

Returns: matrix-like object

Payload level: payload

Arguments: bundle, matrix_id

Use when:
- advanced direct matrix access

### `wb_slice`

Title: Matrix Slice

Description: Read a feature-by-cell matrix slice.

Returns: matrix

Payload level: payload

Arguments: bundle, matrix_id, features, cells

Use when:
- read expression/accessibility block
- feed custom analysis

### `wb_matrix_read_feature`

Title: Read One Feature

Description: Read one feature vector across requested cells.

Returns: numeric vector

Payload level: payload

Arguments: bundle, matrix_id, feature_id, cell_ids

Use when:
- inspect one gene or peak across cells

### `wb_matrix_read_features`

Title: Read Features

Description: Read multiple features across cells from a logical matrix.

Returns: matrix

Payload level: payload

Arguments: bundle, matrix_id, features, cells

Use when:
- inspect marker panel
- read feature block

### `wb_vector`

Title: Feature Vector

Description: Get a single feature vector across cells.

Returns: numeric vector

Payload level: payload

Arguments: bundle, matrix_id, feature_id, cells

Use when:
- plot one gene
- threshold one feature

## motifs

### `wb_motif_libraries`

Title: Motif Libraries

Description: List registered motif libraries.

Returns: data.frame

Payload level: metadata

Arguments: bundle

Use when:
- inspect available motif catalogs

### `wb_motifs`

Title: Motifs

Description: List motifs, optionally filtered by library.

Returns: data.frame

Payload level: metadata

Arguments: bundle, library_id

Use when:
- find motif IDs for regulatory analysis

### `wb_motif_match_sets`

Title: Motif Match Sets

Description: List motif match sets available for peak features.

Returns: data.frame

Payload level: metadata

Arguments: bundle

Use when:
- choose motif-to-peak mapping for chromVAR

### `wb_motif_match_get`

Title: Motif Match Membership

Description: Load motif match membership rows for a match set.

Returns: data.frame

Payload level: payload

Arguments: bundle, match_set_id

Use when:
- inspect motif-feature memberships

## navigation

### `wb_nav_entities`

Title: Navigation Entities

Description: List entities that can be navigated from an artifact-backed source.

Returns: data.frame

Payload level: metadata

Arguments: source, bundle, entity_kind, lineage_id

Use when:
- find clickable genes, lineages, or feature sets

### `wb_nav_targets`

Title: Navigation Targets

Description: List compatible navigation targets for a selected source/entity.

Returns: data.frame

Payload level: metadata

Arguments: source, bundle, entity, lineage_id

Use when:
- find next plot/table from an artifact

### `wb_nav_handoff`

Title: Navigation Handoff

Description: Resolve a navigation target into a client-agnostic handoff payload.

Returns: list

Payload level: metadata

Arguments: source, target, bundle, entity, lineage_id

Use when:
- open linked plot from selected artifact entity

## provenance

### `wb_entity_lifecycle`

Title: Durable Entity Lifecycle

Description: List current, superseded, rejected, retracted, and ephemeral durable entity identities without reading physical storage tables.

Returns: data.frame

Payload level: metadata

Arguments: bundle, entity_kind, entity_id, lifecycle_state, include_history

Use when:
- distinguish current claims from historical evidence
- audit immutable identity state

### `wb_entity_supersessions`

Title: Entity Supersessions

Description: List explicit SUPERSEDES relationships between immutable durable identities.

Returns: data.frame

Payload level: metadata

Arguments: bundle

Use when:
- trace claim replacement
- render historical lifecycle relationships

### `wb_prov_list_heads`

Title: Provenance Heads

Description: List persisted provenance snapshot heads.

Returns: data.frame

Payload level: metadata

Arguments: bundle

Use when:
- find saved analysis DAGs

### `wb_prov_dag`

Title: Provenance DAG

Description: Read one snapshot-local persisted provenance DAG.

Returns: list/data.frame

Payload level: metadata

Arguments: bundle, snapshot_id

Use when:
- inspect one saved analysis snapshot
- reconstruct analysis steps within one snapshot

### `wb_prov_bundle_dag`

Title: Bundle-Level Composed Provenance DAG

Description: Compose persisted runs, artifacts, snapshots, artifact inputs, outputs, and registry mutations across all bundle provenance snapshots.

Returns: list/data.frame

Payload level: metadata

Arguments: bundle, snapshot_id, run_id, artifact_id, direction, max_depth, include_snapshots, include_registry_mutations

Use when:
- render a connected artifact/run lineage across promotions
- show bundle-level provenance in Shiny or agents
- trace analysis chains that continue from promoted artifacts

### `wb_target_reproduction_plan`

Title: Target Reproduction Plan

Description: Resolve an artifact, matrix, space, model, or run DAG node into its minimal cross-snapshot replay closure.

Returns: wb_target_reproduction_plan

Payload level: metadata

Arguments: bundle, target

Use when:
- export the minimum reproducible path to a durable result
- distinguish imported source state from engine-reproducible output

### `wb_target_emit_r_script`

Title: Target Reproduction Script

Description: Emit a replay-and-promotion script for a target reproduction plan and writable execution clone.

Returns: character

Payload level: metadata

Arguments: plan, execution_bundle_dir

Use when:
- hand off a target-specific reproducible analysis path

### `wb_prov_replay_equivalence_results`

Title: Replay Equivalence Results

Description: List target-reproduction equivalence results with separate original and replayed payload SHA-256 identities.

Returns: data.frame

Payload level: metadata

Arguments: bundle, replay_snapshot_id

Use when:
- audit scientific replay equality separately from stored-payload integrity

### `wb_prov_artifact_lineage`

Title: Composed Artifact Lineage

Description: Return an upstream, downstream, or bidirectional composed provenance subgraph centered on one promoted artifact.

Returns: list/data.frame

Payload level: metadata

Arguments: bundle, artifact_id, direction, max_depth

Use when:
- explain one artifact in context
- find upstream source artifacts and downstream dependents

### `wb_prov_run_details`

Title: Provenance Run Details

Description: Inspect one persisted run from provenance.

Returns: list

Payload level: metadata

Arguments: bundle, run_id

Use when:
- explain exact inputs and params for one run

### `wb_run_history`

Title: Run History

Description: Flatten persisted provenance snapshots into a chronological run-history table.

Returns: data.frame

Payload level: metadata

Arguments: bundle, snapshot_id

Use when:
- build run history timeline
- inspect promoted analysis steps

## session

### `wb_session_dag`

Title: Session DAG

Description: Inspect an in-memory session DAG.

Returns: data.frame/list

Payload level: metadata

Arguments: session, bundle, include_artifacts, include_active

Use when:
- inspect current session runs

### `wb_session_dag_run_details`

Title: Session DAG Run Details

Description: Inspect one run node from an in-memory session DAG.

Returns: list

Payload level: metadata

Arguments: session, run_id, bundle

Use when:
- explain one current session run

### `wb_session_view`

Title: Session Staging View

Description: Open the session-local bundle overlay containing staged outputs before promotion.

Returns: scworkbench_bundle

Payload level: data

Arguments: session

Use when:
- inspect staged matrix or space output before promotion
- continue session-local analysis without mutating the portable bundle

## spaces

### `wb_cells_with_space`

Title: Cells With Space

Description: List cells available for a given space.

Returns: character vector

Payload level: metadata

Arguments: bundle, space_id, dims

Use when:
- intersect cells with embedding coverage

### `wb_spaces`

Title: Spaces

Description: List spaces in the bundle.

Returns: data.frame

Payload level: metadata

Arguments: bundle, include_history

Use when:
- choose embedding or latent space for an op

### `wb_space_info`

Title: Space Info

Description: Read space registry metadata, optionally for one space.

Returns: data.frame

Payload level: metadata

Arguments: bundle, space_id

Use when:
- inspect space dimensions and source

### `wb_space`

Title: Space Coordinates

Description: Read coordinates for a space, optionally restricted to cells and dimensions.

Returns: matrix/data.frame

Payload level: payload

Arguments: bundle, space_id, cells, dims

Use when:
- load UMAP/latent coordinates
- plot or fit geometry

### `wb_spaces_with_model`

Title: Spaces With Model

Description: List space IDs that have a stored projection model.

Returns: character vector

Payload level: metadata

Arguments: bundle, model_type

Use when:
- choose UMAP model for projection

### `wb_space_model`

Title: Space Model Metadata

Description: Get model metadata for a space.

Returns: data.frame/list

Payload level: metadata

Arguments: bundle, space_id

Use when:
- inspect fitted UMAP or projection model metadata

### `wb_space_model_path`

Title: Space Model Path

Description: Get absolute path to a stored model file for a space.

Returns: character

Payload level: metadata

Arguments: bundle, space_id

Use when:
- locate model payload file

## vectors

### `wb_list_cell_vectors`

Title: Cell Vectors

Description: List available cell vectors from artifacts and optionally session outputs.

Returns: data.frame

Payload level: metadata

Arguments: bundle, session, include_session

Use when:
- choose vector input
- find UCell/module score artifacts

### `wb_list_vector_sources`

Title: Vector Sources

Description: List vector-like sources available for UI/agent selection.

Returns: data.frame

Payload level: metadata

Arguments: bundle, runs

Use when:
- discover cell_vector and cell_vector_family inputs

### `wb_read_cell_vector`

Title: Read Cell Vector

Description: Read a scalar cell vector for a requested set of cells.

Returns: named vector

Payload level: payload

Arguments: bundle, vector_id, cell_ids

Use when:
- read promoted per-cell values

### `wb_read_cell_vector_family`

Title: Read Cell Vector Family Member

Description: Read one key/member from a cell_vector_family for requested cells.

Returns: named vector

Payload level: payload

Arguments: bundle, vector_id, key, cell_ids

Use when:
- read one UCell/module/chromVAR signal

### `wb_cell_vector_load`

Title: Load Cell Vector Primitive

Description: Load a cell vector primitive by artifact or session reference.

Returns: wb_primitive

Payload level: payload

Arguments: bundle, session, vector_id, expected_kind

Use when:
- resolve vector reference for plotting or ops

