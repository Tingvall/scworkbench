# scworkbench Getter Catalog

<!-- Generated from wb_getter_catalog_semantic(); do not edit getter entries by hand. -->

Generated at: 2026-05-19T13:24:32+0200

Getter count: 62

This document summarizes safe bundle getter and inspection functions for humans, agents, and semantic indexing.
The machine-readable companion is `docs/getter_catalog_semantic.json`.

## artifacts

### `wb_art_list`

Title: Artifacts

Description: List promoted artifacts, optionally filtered by type.

Returns: data.frame

Payload level: metadata

Arguments: bundle, type

Use when:
- find promoted outputs
- choose artifact for plotting or loading

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

Arguments: bundle

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

Arguments: bundle, matrix_id, namespace

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

Arguments: bundle

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

Description: Read a persisted provenance DAG.

Returns: list/data.frame

Payload level: metadata

Arguments: bundle, head_id

Use when:
- inspect run lineage
- reconstruct analysis steps

### `wb_prov_run_details`

Title: Provenance Run Details

Description: Inspect one persisted run from provenance.

Returns: list

Payload level: metadata

Arguments: bundle, run_id

Use when:
- explain exact inputs and params for one run

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

Arguments: bundle

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

