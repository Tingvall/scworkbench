# scworkbench Unified Semantic Catalog

<!-- Generated from wb_semantic_catalog(); do not edit entries by hand. -->

Generated at: 2026-08-03T21:38:07+0200

Record count: 314

Graph edges: 900

## artifact_type

### `artifact_type:cell_vector`

Title: Per-Cell Vector Artifact

Description: Promoted per-cell scalar/categorical vector such as pseudotime, labels, entropy, or module score.

### `artifact_type:cell_vector_family`

Title: Per-Cell Vector Family Artifact

Description: Promoted keyed family of per-cell vectors, for example UCell signatures or chromVAR deviations.

### `artifact_type:relation_family`

Title: Relation Family Artifact

Description: Promoted sparse long-form cell-to-key relations such as branch membership.

### `artifact_type:path_2d_family`

Title: 2D Path Family Artifact

Description: Promoted 2D trajectory or lineage curves.

### `artifact_type:space_path_family`

Title: Space Path Family Artifact

Description: Promoted high-dimensional route/trajectory paths.

### `artifact_type:space_2d`

Title: 2D Space Artifact

Description: Promoted reference to a 2D bundle space.

### `artifact_type:model_ref`

Title: Model Reference Artifact

Description: Promoted model reference for projection or method-specific reuse.

### `artifact_type:feature_table:de_wilcox`

Title: Wilcoxon DE Table

Description: Feature-level differential expression/accessibility statistics.

### `artifact_type:feature_table:markers_topn`

Title: Top Marker Table

Description: Top-ranked marker features per group.

### `artifact_type:feature_table:feature_trend_spearman`

Title: Feature Trend Spearman Table

Description: Feature-level association with a continuous vector such as pseudotime.

### `artifact_type:feature_table:trajectory_de`

Title: Trajectory DE Table

Description: Feature-level differential or dynamic statistics along trajectory lineages.

### `artifact_type:feature_table:trajectory_branch_compare`

Title: Trajectory Branch Compare Table

Description: Feature-level branch comparison statistics.

### `artifact_type:obs_table:derived_cell_set_manifest`

Title: Derived Cell-Set Manifest

Description: Lifecycle manifest for a named derived cell set, including role, status, counts, recipe availability, source summary, and derivation metadata.

### `artifact_type:obs_table:derived_cell_set_rules`

Title: Derived Cell-Set Rule Table

Description: Ordered per-rule audit table for a derived cell set, including input/output counts and selector/source fields.

### `artifact_type:obs_table:feature_set_import_summary`

Title: Feature-Set Import Summary

Description: Summary counts for a feature-set library import into bundle namespaces.

### `artifact_type:obs_table:feature_set_import_manifest`

Title: Feature-Set Import Manifest

Description: One row per parsed feature set with namespace, collection, mapped-gene counts, status, and source metadata.

### `artifact_type:obs_table:feature_set_import_rejected`

Title: Rejected Feature-Set Import Table

Description: Feature sets rejected during import, typically because no source genes mapped to the target matrix.

### `artifact_type:obs_table:feature_set_overlap_qc`

Title: Feature-Set Matrix Overlap QC

Description: Per-set raw, mapped, detected, duplicate, and include/exclude screening metrics against a matrix.

### `artifact_type:obs_table:feature_set_overlap_qc_summary`

Title: Feature-Set Namespace Overlap Summary

Description: Namespace-level overlap QC summary for imported feature-set libraries.

### `artifact_type:obs_table:feature_set_transfer_summary`

Title: Feature-Set Transfer Summary

Description: Summary of matrix-scoped feature-set namespace transfer between comparable matrices.

### `artifact_type:obs_table:feature_set_transfer_manifest`

Title: Feature-Set Transfer Manifest

Description: One row per source feature set transferred or rejected between source and target matrices.

### `artifact_type:obs_table:feature_set_transfer_rejected`

Title: Rejected Feature-Set Transfer Table

Description: Feature sets rejected during matrix namespace transfer because retained target members failed thresholds.

### `artifact_type:obs_table:pathway_enrich`

Title: Pathway Enrichment Table

Description: Pathway or gene-set enrichment summary.

### `artifact_type:obs_table:trajectory_smooth`

Title: Trajectory Smooth Curve Table

Description: Binned/smoothed per-gene expression curves along trajectory pseudotime.

### `artifact_type:obs_table:trajectory_signature_smooth`

Title: Trajectory Signature Smooth Table

Description: Smoothed signature/module curves along trajectory pseudotime.

### `artifact_type:obs_table:trajectory_geneset_dynamics_curve`

Title: Trajectory Gene-Set Curve Table

Description: Gene-set scores over pseudotime bins.

### `artifact_type:obs_table:trajectory_geneset_dynamics`

Title: Trajectory Gene-Set Dynamics Table

Description: One row per gene set with dynamics metrics and curve class.

### `artifact_type:obs_table:trajectory_geneset_dynamics_drivers`

Title: Trajectory Gene-Set Driver Table

Description: Top member genes contributing to dynamic gene-set behavior.

### `artifact_type:obs_table:trajectory_geneset_dynamics_driver_curve`

Title: Trajectory Gene-Set Driver Curves

Description: Driver-gene curves for selected dynamic gene sets.

### `artifact_type:obs_table:trajectory_signal_dynamics_curve`

Title: Trajectory Signal Curve Table

Description: Precomputed signal/vector-family curves over pseudotime.

### `artifact_type:obs_table:trajectory_signal_dynamics`

Title: Trajectory Signal Dynamics Table

Description: Dynamics metrics and classes for precomputed signals.

### `artifact_type:obs_table:trajectory_segment_manifest`

Title: Trajectory Segment Manifest

Description: Audit manifest for one formal trajectory segment, including source kind, source engine, membership rule, normalization rule, parent artifacts, and caveats.

### `artifact_type:obs_table:trajectory_segment_local_membership`

Title: Trajectory Segment-Local Membership Table

Description: One row per cell per parent segment preserving local pseudotime, scaled local pseudotime, lineage weight, and waypoint role.

### `artifact_type:obs_table:trajectory_segment_join_manifest`

Title: Trajectory Segment Join Manifest

Description: Manifest for a segmented composite trajectory, recording parent trajectory_fit_ids, artifact IDs, biological labels, join policy, and overlap counts.

### `artifact_type:obs_table:trajectory_segment_path_join_manifest`

Title: Trajectory Segment Path Join Manifest

Description: Manifest for a derived segmented composite display path, recording parent path artifacts, segment order, point ranges, trajectory_fit_ids, and display-geometry caveats.

### `artifact_type:obs_table:trajectory_segment_display_path_endpoint_qc`

Title: Trajectory Display Path Endpoint QC

Description: Endpoint-distance diagnostics comparing display path start/end points with declared endpoint cell-set or coordinate descriptors.

### `artifact_type:obs_table:ucell_signature_summary`

Title: UCell Signature Summary

Description: Summary statistics for UCell signature scores.

### `artifact_type:obs_table:cell_vector_winners`

Title: Cell Vector Winner Table

Description: Per-cell winner, runner-up, confidence, and pruning metrics from a cell_vector_family.

### `artifact_type:obs_table:cell_vector_family_graph_smooth_summary`

Title: Cell Vector Family Graph Smoothing Summary

Description: Per-key diagnostics for nearest-neighbor smoothing of a cell_vector_family over a bundle space.

### `artifact_type:obs_table:cell_vector_association_summary`

Title: Cell Vector Association Summary

Description: Typed association result with dispatched method, effect size, and validity diagnostics.

### `artifact_type:obs_table:cell_vector_association_contingency`

Title: Cell Vector Association Contingency

Description: Observed and expected counts for categorical-by-categorical cell-vector association.

### `artifact_type:obs_table:cell_vector_association_cells`

Title: Cell Vector Association Cells

Description: Per-cell values used in a continuous-by-continuous association.

### `artifact_type:obs_table:winner_cell_set_manifest`

Title: Winner Cell-Set Manifest

Description: One row per registered winner-derived bundle cell set.

### `artifact_type:obs_table:chromvar_summary`

Title: chromVAR Motif Summary

Description: Summary statistics for chromVAR motif deviations.

### `artifact_type:obs_table:knn_neighbors`

Title: KNN Neighbor Table

Description: Cell-neighbor relationships from a KNN graph/query.

### `artifact_type:feature_table:knn_pseudobulk`

Title: KNN Pseudobulk Feature Table

Description: Feature summaries over KNN neighborhoods.

### `artifact_type:obs_table:matrix_log_normalize_summary`

Title: Matrix Log-Normalization Summary

Description: Summary of a persisted log-normalized matrix transform, including source matrix, output matrix, scale factor, dimensions, and library-size diagnostics.

### `artifact_type:obs_table:attach_report`

Title: Table Type: attach_report

Description: Promoted obs_table artifact with table_type='attach_report'.

### `artifact_type:obs_table:cell_suffix_label`

Title: Table Type: cell_suffix_label

Description: Promoted obs_table artifact with table_type='cell_suffix_label'.

### `artifact_type:feature_table:cell_vector_assoc`

Title: Table Type: cell_vector_assoc

Description: Promoted feature_table artifact with table_type='cell_vector_assoc'.

### `artifact_type:obs_table:cell_vector_assoc_group_stats`

Title: Table Type: cell_vector_assoc_group_stats

Description: Promoted obs_table artifact with table_type='cell_vector_assoc_group_stats'.

### `artifact_type:obs_table:cell_vector_compare`

Title: Table Type: cell_vector_compare

Description: Promoted obs_table artifact with table_type='cell_vector_compare'.

### `artifact_type:obs_table:cell_vector_compare_summary`

Title: Table Type: cell_vector_compare_summary

Description: Promoted obs_table artifact with table_type='cell_vector_compare_summary'.

### `artifact_type:obs_table:cell_vector_family_calibration_summary`

Title: Table Type: cell_vector_family_calibration_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_calibration_summary'.

### `artifact_type:obs_table:cell_vector_family_qc_group_summary`

Title: Table Type: cell_vector_family_qc_group_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_group_summary'.

### `artifact_type:obs_table:cell_vector_family_qc_key_summary`

Title: Table Type: cell_vector_family_qc_key_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_key_summary'.

### `artifact_type:obs_table:cell_vector_family_qc_pairwise_summary`

Title: Table Type: cell_vector_family_qc_pairwise_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_pairwise_summary'.

### `artifact_type:obs_table:cell_vector_family_reduce_decision_table`

Title: Table Type: cell_vector_family_reduce_decision_table

Description: Promoted obs_table artifact with table_type='cell_vector_family_reduce_decision_table'.

### `artifact_type:obs_table:cell_vector_family_reduce_summary`

Title: Table Type: cell_vector_family_reduce_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_reduce_summary'.

### `artifact_type:obs_table:generic`

Title: Table Type: generic

Description: Promoted obs_table artifact with table_type='generic'.

### `artifact_type:obs_table:ingest_report`

Title: Table Type: ingest_report

Description: Promoted obs_table artifact with table_type='ingest_report'.

### `artifact_type:obs_table:space_path_score_summary`

Title: Table Type: space_path_score_summary

Description: Promoted obs_table artifact with table_type='space_path_score_summary'.

### `artifact_type:obs_table:trajectory_branch_compare_summary`

Title: Table Type: trajectory_branch_compare_summary

Description: Promoted obs_table artifact with table_type='trajectory_branch_compare_summary'.

### `artifact_type:obs_table:trajectory_de_summary`

Title: Table Type: trajectory_de_summary

Description: Promoted obs_table artifact with table_type='trajectory_de_summary'.

### `artifact_type:obs_table:trajectory_geneset_dynamics_summary`

Title: Table Type: trajectory_geneset_dynamics_summary

Description: Promoted obs_table artifact with table_type='trajectory_geneset_dynamics_summary'.

### `artifact_type:obs_table:trajectory_geneset_dynamics_top`

Title: Table Type: trajectory_geneset_dynamics_top

Description: Promoted obs_table artifact with table_type='trajectory_geneset_dynamics_top'.

### `artifact_type:obs_table:trajectory_route_smooth`

Title: Table Type: trajectory_route_smooth

Description: Promoted obs_table artifact with table_type='trajectory_route_smooth'.

### `artifact_type:obs_table:trajectory_route_smooth_summary`

Title: Table Type: trajectory_route_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_route_smooth_summary'.

### `artifact_type:obs_table:trajectory_signal_dynamics_summary`

Title: Table Type: trajectory_signal_dynamics_summary

Description: Promoted obs_table artifact with table_type='trajectory_signal_dynamics_summary'.

### `artifact_type:obs_table:trajectory_signal_dynamics_top`

Title: Table Type: trajectory_signal_dynamics_top

Description: Promoted obs_table artifact with table_type='trajectory_signal_dynamics_top'.

### `artifact_type:obs_table:trajectory_signature_smooth_summary`

Title: Table Type: trajectory_signature_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_signature_smooth_summary'.

### `artifact_type:obs_table:trajectory_smooth_summary`

Title: Table Type: trajectory_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_smooth_summary'.

### `artifact_type:obs_table:trajectory_vector_smooth`

Title: Table Type: trajectory_vector_smooth

Description: Promoted obs_table artifact with table_type='trajectory_vector_smooth'.

### `artifact_type:obs_table:trajectory_vector_smooth_summary`

Title: Table Type: trajectory_vector_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_vector_smooth_summary'.

## getter

### `getter:wb_status`

Title: Bundle Status

Description: Summarize bundle health and high-level registry counts.

### `getter:wb_manifest`

Title: Bundle Manifest

Description: Read the bundle manifest metadata.

### `getter:wb_bundle_overview`

Title: Bundle Overview

Description: Summarize bundle identity, validation state, registries, artifact counts, and provenance heads for read-only clients.

### `getter:wb_bundle_schema`

Title: Bundle Schema

Description: Inspect available SQLite schema objects in the bundle.

### `getter:wb_list`

Title: Registry List

Description: List common registry tables such as matrices, features, spaces, or datasets.

### `getter:wb_cells`

Title: Cell IDs

Description: Return cell IDs in canonical bundle order, optionally restricted to a cell set or dataset.

### `getter:wb_cell_sets`

Title: Cell Sets

Description: List available cell sets in a bundle.

### `getter:wb_resolve_cell_set`

Title: Resolve Cell Set

Description: Resolve a cell-set selector into concrete cell IDs.

### `getter:wb_meta`

Title: Cell Metadata

Description: Read cell-level metadata for selected cells and columns.

### `getter:wb_cell_metadata_columns`

Title: Cell Metadata Columns

Description: List cell metadata columns with type, missingness, cardinality, and display hints for clients.

### `getter:wb_cell_coverage`

Title: Cell Coverage

Description: Summarize which cells are covered by matrices, spaces, and sets.

### `getter:wb_cells_with_matrix`

Title: Cells With Matrix

Description: List cells available for a given matrix.

### `getter:wb_cells_with_space`

Title: Cells With Space

Description: List cells available for a given space.

### `getter:wb_matrices`

Title: Matrices

Description: List matrices available in the bundle.

### `getter:wb_matrix_info`

Title: Matrix Info

Description: Read matrix registry metadata, optionally for one matrix.

### `getter:wb_matrix_fragments`

Title: Matrix Fragments

Description: List physical storage fragments backing a logical matrix.

### `getter:wb_matrix_resolve`

Title: Resolve Matrix

Description: Resolve matrix fragments to absolute storage paths.

### `getter:wb_matrix`

Title: Matrix Handle

Description: Open a matrix handle for a matrix ID.

### `getter:wb_slice`

Title: Matrix Slice

Description: Read a feature-by-cell matrix slice.

### `getter:wb_matrix_read_feature`

Title: Read One Feature

Description: Read one feature vector across requested cells.

### `getter:wb_matrix_read_features`

Title: Read Features

Description: Read multiple features across cells from a logical matrix.

### `getter:wb_vector`

Title: Feature Vector

Description: Get a single feature vector across cells.

### `getter:wb_features`

Title: Features

Description: Read feature registry rows, optionally filtered by matrix or feature type.

### `getter:wb_feature_ids`

Title: Feature IDs

Description: Get feature IDs in canonical order for a matrix.

### `getter:wb_search_features`

Title: Search Features

Description: Search feature IDs or feature metadata.

### `getter:wb_feature_sets`

Title: Feature Sets

Description: List feature sets and namespaces in the bundle.

### `getter:wb_feature_set_info`

Title: Feature Set Info

Description: Read metadata for one feature set.

### `getter:wb_feature_set_get`

Title: Feature Set Members

Description: Get feature IDs from one feature set.

### `getter:wb_spaces`

Title: Spaces

Description: List spaces in the bundle.

### `getter:wb_space_info`

Title: Space Info

Description: Read space registry metadata, optionally for one space.

### `getter:wb_space`

Title: Space Coordinates

Description: Read coordinates for a space, optionally restricted to cells and dimensions.

### `getter:wb_spaces_with_model`

Title: Spaces With Model

Description: List space IDs that have a stored projection model.

### `getter:wb_space_model`

Title: Space Model Metadata

Description: Get model metadata for a space.

### `getter:wb_space_model_path`

Title: Space Model Path

Description: Get absolute path to a stored model file for a space.

### `getter:wb_art_list`

Title: Artifacts

Description: List current promoted artifacts by default, optionally filtered by type or expanded to retained history.

### `getter:wb_entity_lifecycle`

Title: Durable Entity Lifecycle

Description: List current, superseded, rejected, retracted, and ephemeral durable entity identities without reading physical storage tables.

### `getter:wb_entity_supersessions`

Title: Entity Supersessions

Description: List explicit SUPERSEDES relationships between immutable durable identities.

### `getter:wb_list_trajectory_models`

Title: Trajectory Model Inventory

Description: List promoted model_ref trajectory candidates with engine, provenance, and optional pseudotime coverage.

### `getter:wb_trajectory_lineage_weights`

Title: Trajectory Lineage Weights

Description: Load Slingshot lineage membership weights as a cell_vector_family from a promoted lineage_weights artifact, promoted sibling trajectory artifact, or in-memory Slingshot model_ref fallback.

### `getter:wb_trajectory_fit_info`

Title: Trajectory Fit Identity

Description: Inspect the trajectory_fit_id, engine, lineage keys, and available cell universe metadata for a trajectory primitive or promoted artifact.

### `getter:wb_trajectory_assert_fit_compatible`

Title: Trajectory Fit Compatibility Assertion

Description: Fail loudly when trajectory artifacts come from different trajectory fit families; shared labels such as L1 are not sufficient compatibility evidence.

### `getter:wb_art_load`

Title: Load Artifact

Description: Load a promoted artifact as a primitive.

### `getter:wb_art_table_info`

Title: Table Artifact Info

Description: Read metadata for a promoted table artifact.

### `getter:wb_art_table_slice`

Title: Table Artifact Slice

Description: Read a bounded row slice from a promoted feature_table or obs_table.

### `getter:wb_art_table_distinct`

Title: Table Artifact Distinct Values

Description: List distinct values from one promoted table artifact column.

### `getter:wb_art_identity_card`

Title: Artifact Identity Card

Description: Summarize artifact identity, provenance, labels, and display hints.

### `getter:wb_art_birth_certificate`

Title: Artifact Birth Certificate

Description: Read provenance/birth metadata for a promoted artifact.

### `getter:wb_art_dependencies`

Title: Artifact Dependencies

Description: Get dependency relationships for an artifact.

### `getter:wb_art_trajectory_related`

Title: Related Trajectory Artifacts

Description: Find trajectory-related sibling artifacts for a source artifact.

### `getter:wb_list_cell_vectors`

Title: Cell Vectors

Description: List available cell vectors from artifacts and optionally session outputs.

### `getter:wb_list_vector_sources`

Title: Vector Sources

Description: List vector-like sources available for UI/agent selection.

### `getter:wb_read_cell_vector`

Title: Read Cell Vector

Description: Read a scalar cell vector for a requested set of cells.

### `getter:wb_read_cell_vector_family`

Title: Read Cell Vector Family Member

Description: Read one key/member from a cell_vector_family for requested cells.

### `getter:wb_cell_vector_load`

Title: Load Cell Vector Primitive

Description: Load a cell vector primitive by artifact or session reference.

### `getter:wb_motif_libraries`

Title: Motif Libraries

Description: List registered motif libraries.

### `getter:wb_motifs`

Title: Motifs

Description: List motifs, optionally filtered by library.

### `getter:wb_motif_match_sets`

Title: Motif Match Sets

Description: List motif match sets available for peak features.

### `getter:wb_motif_match_get`

Title: Motif Match Membership

Description: Load motif match membership rows for a match set.

### `getter:wb_prov_list_heads`

Title: Provenance Heads

Description: List persisted provenance snapshot heads.

### `getter:wb_prov_dag`

Title: Provenance DAG

Description: Read one snapshot-local persisted provenance DAG.

### `getter:wb_prov_bundle_dag`

Title: Bundle-Level Composed Provenance DAG

Description: Compose persisted runs, artifacts, snapshots, artifact inputs, outputs, and registry mutations across all bundle provenance snapshots.

### `getter:wb_target_reproduction_plan`

Title: Target Reproduction Plan

Description: Resolve an artifact, matrix, space, model, or run DAG node into its minimal cross-snapshot replay closure.

### `getter:wb_target_emit_r_script`

Title: Target Reproduction Script

Description: Emit a replay-and-promotion script for a target reproduction plan and writable execution clone.

### `getter:wb_prov_replay_equivalence_results`

Title: Replay Equivalence Results

Description: List target-reproduction equivalence results with separate original and replayed payload SHA-256 identities.

### `getter:wb_prov_artifact_lineage`

Title: Composed Artifact Lineage

Description: Return an upstream, downstream, or bidirectional composed provenance subgraph centered on one promoted artifact.

### `getter:wb_prov_run_details`

Title: Provenance Run Details

Description: Inspect one persisted run from provenance.

### `getter:wb_run_history`

Title: Run History

Description: Flatten persisted provenance snapshots into a chronological run-history table.

### `getter:wb_session_dag`

Title: Session DAG

Description: Inspect an in-memory session DAG.

### `getter:wb_session_dag_run_details`

Title: Session DAG Run Details

Description: Inspect one run node from an in-memory session DAG.

### `getter:wb_session_view`

Title: Session Staging View

Description: Open the session-local bundle overlay containing staged outputs before promotion.

### `getter:wb_nav_entities`

Title: Navigation Entities

Description: List entities that can be navigated from an artifact-backed source.

### `getter:wb_nav_targets`

Title: Navigation Targets

Description: List compatible navigation targets for a selected source/entity.

### `getter:wb_nav_handoff`

Title: Navigation Handoff

Description: Resolve a navigation target into a client-agnostic handoff payload.

### `getter:wb_client_discover`

Title: Client Discovery

Description: Client facade for discovering bundle state and available operations.

### `getter:wb_client_inspect`

Title: Client Inspect

Description: Client facade for inspecting session and bundle runtime state.

### `getter:wb_client_load`

Title: Client Load

Description: Client facade for loading primitives by reference.

### `getter:wb_client_load_table`

Title: Client Load Table

Description: Client facade for loading and wrangling references into normalized tables.

## op

### `op:leiden`

Title: Leiden clustering

Description: Graph clustering on a kNN graph derived from an embedding space.

### `op:matrix_log_normalize`

Title: Log-normalize count matrix

Description: Create a reusable log1p(counts / library_size * scale_factor) BPCells matrix in the bundle.

### `op:hvg_select`

Title: Highly Variable Feature Selection

Description: Select highly variable features from a matrix using chunked feature-wise summaries.

### `op:pca_fit`

Title: PCA Fit

Description: Compute PCA from a matrix and selected features, then persist the cell coordinates as a bundle space.

### `op:umap_fit`

Title: UMAP fit (train model)

Description: Fit a UMAP model on a space and store it for future projection.

### `op:umap_transform`

Title: UMAP transform (project cells)

Description: Project cells into an existing UMAP using a stored model.

### `op:addmodulescore`

Title: Add module score

Description: Seurat-style module scoring using matched control features by expression bin.

### `op:ucell`

Title: UCell Signature Scoring

Description: Rank-based per-cell signature scoring using the UCell method.

### `op:cell_vector_family_reduce`

Title: Reduce Cell Vector Family

Description: Compress a cell_vector_family into one categorical cell_vector using explicit reduction and abstention rules.

### `op:cell_vector_family_calibrate`

Title: Calibrate Cell Vector Family

Description: Normalize one keyed per-cell signal family within keys so cross-key comparisons become more meaningful.

### `op:cell_vector_family_qc`

Title: QC Cell Vector Family

Description: Compute per-key and pairwise diagnostics for one keyed per-cell signal family.

### `op:cell_vector_family_graph_smooth`

Title: Graph Smooth Cell Vector Family

Description: Smooth each key of a cell_vector_family over local nearest-neighbor geometry in a selected bundle space.

### `op:cell_vector_winners`

Title: Cell Vector Winner Assignment

Description: Assign one winning key per cell from a cell_vector_family and report confidence and pruning metrics.

### `op:winner_cell_sets`

Title: Winner Cell-Set Registration

Description: Register bundle cell sets from a cell_vector_winners obs_table and return a manifest table.

### `op:chromvar`

Title: chromVAR deviations

Description: Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.

### `op:de_wilcox`

Title: Differential Expression (Wilcoxon)

Description: Wilcoxon rank-sum DE between two cell groups (A vs B).

### `op:markers_topn`

Title: Top Markers Per Cluster

Description: One-vs-rest Wilcoxon marker ranking for each cluster.

### `op:pathway_enrich`

Title: Pathway Enrichment (Namespace)

Description: Hypergeometric enrichment against all feature sets in a namespace.

### `op:feature_set_import`

Title: Feature-Set Library Import

Description: Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.

### `op:feature_set_overlap_qc`

Title: Feature-Set Matrix Overlap QC

Description: Screen imported feature-set namespaces against a matrix before pathway or trajectory discovery.

### `op:feature_set_namespace_transfer`

Title: Feature-Set Namespace Transfer

Description: Transfer matrix-scoped feature-set namespaces between comparable matrices using mirror or intersect semantics.

### `op:cell_suffix_label`

Title: Cell Labels From ID Suffix

Description: Build a categorical cell vector by parsing cell_id suffix tokens.

### `op:cell_set_derive`

Title: Derived Cell Set

Description: Materialize a selector-derived or explicitly declared cell universe as a named cell set with lifecycle role/status and manifest tables.

### `op:cell_vector_assoc`

Title: Cell Vector Association

Description: Test whether a continuous cell-level signal differs across groups defined by a categorical cell-level vector.

### `op:metadata_cell_vector`

Title: Metadata Cell Vector

Description: Materialize an imported cell metadata column as a typed, provenance-backed cell vector.

### `op:cell_vector_association`

Title: Cell Vector Association

Description: Associate two typed cell vectors with categorical and continuous dispatch.

### `op:cell_vector_compare`

Title: Cell Vector Comparison

Description: Compare two cell-level signals on their shared cell universe in raw or rank space.

### `op:feature_trend_spearman`

Title: Feature Trends vs Continuous Vector

Description: Feature-level Spearman trend testing against continuous pseudotime-like vectors.

### `op:trajectory_de`

Title: Trajectory DE

Description: Lineage-aware feature trend testing against trajectory pseudotime from model_ref.

### `op:trajectory_smooth`

Title: Trajectory Feature Smoothing

Description: Summarize per-feature expression along trajectory pseudotime into reusable trend tables.

### `op:trajectory_branch_compare`

Title: Trajectory Branch Compare

Description: Compare two trajectory branches feature-by-feature using explicit pseudotime and branch membership primitives.

### `op:trajectory_signature_smooth`

Title: Trajectory Signature Smoothing

Description: Summarize feature-set signature scores along trajectory pseudotime into reusable trend tables.

### `op:trajectory_geneset_dynamics`

Title: Trajectory Gene-Set Dynamics

Description: Screen all feature sets in a namespace for dynamic behavior along trajectory pseudotime.

### `op:trajectory_route_smooth`

Title: Trajectory Route Smoothing

Description: Summarize per-feature expression along an explicit route using global pseudotime plus route membership weights.

### `op:trajectory_vector_smooth`

Title: Trajectory Signal Smoothing

Description: Summarize cell-level signal families along trajectory pseudotime into reusable trend tables.

### `op:trajectory_signal_dynamics`

Title: Trajectory Signal Dynamics

Description: Rank precomputed cell-level signal families by dynamic behavior along trajectory pseudotime.

### `op:knn_pseudobulk`

Title: kNN Pseudobulk Around Query Cell(s)

Description: Find k nearest neighbors in latent space around query cells and aggregate matrix values.

### `op:knn_neighbors`

Title: kNN neighbors around query cell(s)

Description: Find nearest neighbors in a latent space without requiring matrix aggregation.

### `op:slingshot`

Title: Slingshot trajectory

Description: Infer lineage curves and pseudotime from clusters in a 2D space.

### `op:slingshot_fit`

Title: Slingshot fit

Description: Fit Slingshot lineages/pseudotime in a chosen fit space (typically latent/PCA).

### `op:slingshot_lineage_weights`

Title: Slingshot lineage weights

Description: Extract Slingshot lineage membership weights from an existing model_ref without refitting, preserving trajectory_fit_id and lineage mapping.

### `op:trajectory_segment_join`

Title: Trajectory segment join

Description: Join ordered generic trajectory segments into an auditable composite pseudotime without merging parent trajectory models.

### `op:trajectory_segment_from_artifacts`

Title: Trajectory fitted-artifact segment

Description: Materialize the generic trajectory segment contract from fitted-model trajectory artifacts with fit-family validation.

### `op:trajectory_space_path_segment`

Title: Trajectory space-path segment

Description: Convert space_path_score output into a generic trajectory segment using path-progress pseudotime and transparent distance-based membership.

### `op:trajectory_segment_path_join`

Title: Trajectory segment path join

Description: Join ordered parent path_2d_family segments into a derived composite display curve without merging parent trajectory models.

### `op:slingshot_project`

Title: Slingshot project curves

Description: Project a fitted Slingshot model into a 2D display space (e.g. UMAP).

### `op:monocle3_fit`

Title: Monocle3 fit (hybrid space)

Description: Fit monocle3 graph/pseudotime using a scworkbench latent space injected into monocle3's UMAP slot.

### `op:monocle3_project`

Title: Monocle3 project curves

Description: Project a fitted monocle3 trajectory graph into a 2D display space.

### `op:peakvi_fit`

Title: PeakVI fit (pybench)

Description: Train a PeakVI model on a matrix via the pybench Python runtime and emit a latent space plus model reference.

### `op:scvi_train`

Title: scVI train (pybench)

Description: Train an RNA scVI model on a raw/count-like matrix via the pybench Python runtime and emit a latent space, model reference, and fit summary.

### `op:peakvi_project`

Title: PeakVI project (pybench)

Description: Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.

### `op:space_path_define`

Title: Define analytical space path

Description: Contract scaffold for checkpoint-anchored path construction in a named analytical space.

### `op:space_path_score`

Title: Score cells against analytical path

Description: Contract scaffold for path-relative scoring in a named analytical space.

### `op:space_path_project_2d`

Title: Project analytical path into 2D

Description: Contract scaffold for projecting an analytical path into a drawable 2D path family.

### `op:palantir_fit`

Title: Palantir fit (pybench)

Description: Run Palantir pseudotime/branch probabilities on a scworkbench latent space via the pybench Python runtime.

### `op:palantir_project`

Title: Palantir project trajectories

Description: Project Palantir branch trajectories into a 2D display space using Palantir-style mellon interpolation from the fitted Palantir model.

## parameter

### `parameter:cell_set`

Title: Cell Set / Analysis Universe

Description: Restricts the cells considered by an op. This is a biological and computational universe choice, not a cosmetic filter.

### `parameter:target_cell_set`

Title: Target Derived Cell Set

Description: Stable bundle name assigned to a newly materialized derived cell universe.

### `parameter:role`

Title: Cell-Set Lifecycle Role

Description: Declared purpose of a cell set, such as analysis_universe, exclusion_set, endpoint_set, annotation, diagnostic, or temporary.

### `parameter:status`

Title: Cell-Set Lifecycle Status

Description: Declared maturity of a cell set, such as candidate, accepted, superseded, rejected, active, or temporary.

### `parameter:matrix`

Title: Matrix Input

Description: Symbolic matrix primitive consumed by an op. The matrix defines the feature universe and measurement scale.

### `parameter:output_matrix_id`

Title: Output Matrix Identifier

Description: Matrix id assigned to a newly created bundle matrix.

### `parameter:scale_factor`

Title: Library-Size Normalization Scale

Description: Target per-cell total used when converting raw counts to scaled expression before log transformation.

### `parameter:overwrite`

Title: Overwrite Existing Output

Description: Controls whether an op may replace an existing persisted bundle object with the same identifier.

### `parameter:space`

Title: Embedding / Latent Space Input

Description: Symbolic space primitive used for geometry, clustering, nearest-neighbor, projection, or trajectory operations.

### `parameter:model`

Title: Model Reference Input

Description: Reference to a fitted model or trajectory object used by downstream projection/smoothing/dynamics ops.

### `parameter:pseudotime`

Title: Pseudotime Vector Input

Description: Continuous per-cell progress coordinate, usually inferred by a trajectory method or path-scoring op.

### `parameter:trajectory_fit_id`

Title: Trajectory Fit Identity

Description: Stable identity binding trajectory-derived artifacts emitted from one fit, including model_ref, pseudotime, lineage weights, and projected paths.

### `parameter:trajectory_composite_id`

Title: Trajectory Composite Identity

Description: Stable identity for a derived trajectory assembled from separately fitted parent trajectory segments.

### `parameter:source_kind`

Title: Trajectory Segment Source Kind

Description: Declares how a trajectory segment was generated. Implemented source kinds are fitted_model and space_path_bridge; graph_path_bridge, imported_pseudotime, manual_pseudotime, and composite are reserved until adapters exist.

### `parameter:source_engine`

Title: Trajectory Segment Source Engine

Description: Declares the engine or source family that produced a segment, such as slingshot, monocle3, palantir, space_path, manual, imported, graph, or unknown.

### `parameter:join_policy`

Title: Trajectory Segment Join Policy

Description: Rule used to convert segment-local pseudotimes into one composite pseudotime.

### `parameter:pseudotime_direction`

Title: Pseudotime Direction

Description: Controls whether pseudotime is used as provided or inverted before binning, curve metrics, and class assignment.

### `parameter:pseudotime_key`

Title: Pseudotime Key

Description: Selects the key/lineage from an explicit cell_vector_family pseudotime input.

### `parameter:membership`

Title: Pseudotime Membership Filter

Description: Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells before dynamics are computed.

### `parameter:start_label`

Title: Biological Start Label

Description: Human-readable label for the intended biological start of a trajectory or dynamics analysis.

### `parameter:end_label`

Title: Biological End Label

Description: Human-readable label for the intended biological endpoint of a trajectory or dynamics analysis.

### `parameter:lineage`

Title: Lineage Subset

Description: Restricts analysis to one or more lineage/path keys from a trajectory, relation, or path family.

### `parameter:score_method`

Title: Feature-Set Scoring Method

Description: Defines how member features are collapsed into a per-cell or per-bin feature-set score.

### `parameter:namespace`

Title: Feature-Set Namespace

Description: Selects the registered collection of feature sets to screen or score.

### `parameter:feature_sets`

Title: Feature-Set Subset

Description: Optional restriction to named feature sets within a namespace.

### `parameter:source_path`

Title: Feature-Set Source Path

Description: File-backed source for feature-set imports, such as GMT, RDS list/data.frame, or CSV-style table.

### `parameter:source_format`

Title: Feature-Set Source Format

Description: Parser choice for a feature-set import source.

### `parameter:split_by_collection`

Title: Split Feature-Set Namespace By Collection

Description: Controls whether broad gene-set libraries are split into collection/subcollection namespaces during import.

### `parameter:gene_id_type`

Title: Gene Identifier Type

Description: Records the identifier convention used by imported feature-set genes.

### `parameter:source_matrix_id`

Title: Source Matrix Identifier

Description: Matrix id that owns the source matrix-scoped feature-set namespace or other transferable registry state.

### `parameter:target_matrix_id`

Title: Target Matrix Identifier

Description: Matrix id that will receive transferred feature-set memberships after mirror or intersect validation.

### `parameter:target_namespace`

Title: Target Feature-Set Namespace

Description: Optional namespace assigned to transferred feature sets on the target matrix.

### `parameter:min_retained_features`

Title: Minimum Retained Features

Description: Minimum number of source feature-set members that must remain valid on a target matrix during transfer.

### `parameter:min_retained_fraction`

Title: Minimum Retained Fraction

Description: Minimum fraction of source feature-set members that must remain valid on a target matrix during transfer.

### `parameter:signal_keys`

Title: Signal Key Subset

Description: Optional restriction to selected keys in a cell_vector_family, such as UCell signatures or chromVAR motifs.

### `parameter:n_bins`

Title: Pseudotime Bin Count

Description: Number of bins used to aggregate cells along pseudotime before curve summaries and dynamics metrics.

### `parameter:min_cells_per_bin`

Title: Minimum Cells Per Bin

Description: Minimum number of cells required for a pseudotime bin to be retained.

### `parameter:summary_fun`

Title: Bin Summary Function

Description: Statistic used to summarize cell-level values within each bin.

### `parameter:min_amplitude`

Title: Minimum Curve Amplitude Filter

Description: Minimum observed/smoothed curve range required for a signal or feature set to pass report filters.

### `parameter:class_min_amplitude`

Title: Minimum Amplitude For Non-Flat Class

Description: Minimum curve range required before assigning a non-flat dynamic class.

### `parameter:min_bins_observed`

Title: Minimum Observed Bins Filter

Description: Minimum number of retained pseudotime bins required for a curve to pass filters.

### `parameter:min_features_detected`

Title: Minimum Detected Set Members

Description: Minimum number of feature-set members detected in the matrix before a set passes filters.

### `parameter:min_detected_fraction`

Title: Minimum Detected Set Fraction

Description: Minimum fraction of feature-set members detected in the matrix before a set passes filters.

### `parameter:min_mean_score`

Title: Minimum Mean Score Filter

Description: Minimum mean smoothed curve score required before a gene set or signal passes report filters.

### `parameter:min_max_score`

Title: Minimum Maximum Score Filter

Description: Minimum maximum smoothed curve score required before a gene set or signal passes report filters.

### `parameter:min_signal_to_noise`

Title: Minimum Signal-To-Noise Filter

Description: Minimum amplitude divided by mean bootstrap standard error required before a curve passes filters.

### `parameter:low_abundance_max_score`

Title: Low-Abundance Flag Threshold

Description: Maximum score threshold below which dynamic-looking curves are flagged as low abundance.

### `parameter:on_off_min_delta`

Title: On/Off Delta Threshold

Description: Minimum late-minus-early absolute difference required for turns_on or turns_off classes.

### `parameter:monotonic_min_abs_rho`

Title: Monotonicity Threshold

Description: Minimum absolute Spearman correlation with pseudotime required for monotonic on/off classes.

### `parameter:smooth_method`

Title: Curve Smoothing Method

Description: Optional smoother applied to binned curves before metrics and class assignment.

### `parameter:loess_span`

Title: LOESS Span

Description: Controls the locality of LOESS smoothing when smooth_method is loess.

### `parameter:bootstrap_n`

Title: Bootstrap Replicate Count

Description: Number of bootstrap resamples per bin for confidence intervals; zero disables bootstrap intervals.

### `parameter:ci_level`

Title: Confidence Interval Level

Description: Nominal confidence level for bootstrap confidence bands.

### `parameter:n_permutations`

Title: Empirical Permutation Count

Description: Number of score-pseudotime permutations used to estimate empirical dynamic-score p-values.

### `parameter:permutation_seed`

Title: Permutation Random Seed

Description: Seed used for empirical score-pseudotime permutation tests.

### `parameter:p_adjust_method`

Title: P-Value Adjustment Method

Description: Multiple-testing correction method used to convert empirical p_dynamic values into q_dynamic values.

### `parameter:mad_multiplier`

Title: MAD Distance Inclusion Multiplier

Description: Threshold multiplier for median absolute deviation distance filters around a trajectory/path.

### `parameter:top_n`

Title: Top-N Retention

Description: Number of top-ranked records retained for compact outputs or reports.

### `parameter:seed`

Title: Random Seed

Description: Seed used for stochastic algorithms or resampling.

## plot

### `plot:embedding_overlay`

Title: Embedding Overlay

Description: Display cells in a 2D embedding with optional color, shape, size, alpha, or set overlays.

### `plot:volcano`

Title: Volcano Plot

Description: Plot feature-level effect size against adjusted p-value for differential or trend-like feature tables.

### `plot:trend_scatter`

Title: Trend Scatter

Description: Plot feature-level trend or association statistics as a scatter plot.

### `plot:violin`

Title: Violin Plot

Description: Show distributions of per-cell vector values across groups.

### `plot:category_count_bar`

Title: Category Count Bar

Description: Show counts and percentages for categorical cell-vector labels.

### `plot:dotplot`

Title: Dotplot

Description: Show feature expression summaries across groups with percent-expressed and average-expression encodings.

### `plot:pathway_bar`

Title: Pathway Bar

Description: Show ranked pathway or feature-set enrichment terms.

### `plot:ranked_lollipop`

Title: Ranked Lollipop

Description: Show ranked entities from feature tables or obs_table summaries.

### `plot:heatmap_ranked`

Title: Ranked Heatmap

Description: Show matrix-like feature-by-group values from ranked feature tables.

### `plot:feature_rank_bar`

Title: Feature Rank Bar

Description: Show ranked feature values as bars.

### `plot:pseudotime_smooth_panel`

Title: Pseudotime Smooth Panel

Description: Show per-feature smoothed expression curves along trajectory pseudotime.

### `plot:pseudotime_signature_line`

Title: Pseudotime Signature Line

Description: Show feature-set or signal curves along trajectory pseudotime.

## primitive

### `primitive:matrix`

Title: Matrix Reference

Description: Symbolic reference to a feature-by-cell matrix stored in the bundle.

### `primitive:space`

Title: Space Reference

Description: Symbolic reference to a cell embedding or latent space stored in the bundle.

### `primitive:space_2d`

Title: 2D Space Reference

Description: Reference to a two-dimensional cell space, typically UMAP-like coordinates.

### `primitive:cell_vector`

Title: Cell Vector

Description: One value per cell, continuous or categorical.

### `primitive:cell_vector_family`

Title: Cell Vector Family

Description: Long-form collection of keyed per-cell vectors.

### `primitive:relation_family`

Title: Relation Family

Description: Sparse long-form cell-to-key relations with optional weights, values, or distances.

### `primitive:feature_table`

Title: Feature Table

Description: Data frame where rows are feature-centric results such as genes, peaks, or markers.

### `primitive:obs_table`

Title: Observation Table

Description: Generic observation-style data frame specialized by table_type and entity_kind.

### `primitive:model_ref`

Title: Model Reference

Description: Reference to a stored model artifact and the spaces it maps between.

### `primitive:path_2d_family`

Title: 2D Path Family

Description: Lineage or curve coordinates in a 2D plotting space.

### `primitive:space_path_family`

Title: High-Dimensional Space Path Family

Description: Curves in an arbitrary-dimensional bundle space, represented point-by-dimension.

## recipe

### `recipe:trajectory_geneset_dynamics_discovery`

Title: Run gene-set dynamics along a trajectory

Description: Screen a feature-set namespace across trajectory pseudotime and report dynamic terms plus driver genes.

### `recipe:feature_set_import_qc_then_dynamics`

Title: Import and QC a feature-set library before trajectory screening

Description: Import a GMT/RDS/table feature-set library into a namespace, record import provenance, QC matrix overlap, then use the namespace in trajectory_geneset_dynamics.

### `recipe:feature_set_namespace_transfer_for_normalized_matrix`

Title: Transfer feature-set namespaces to a derived normalized matrix

Description: Transfer matrix-scoped feature-set namespaces from a source matrix to a target matrix using mirror or intersect semantics before running dynamics on the target matrix.

### `recipe:trajectory_signal_dynamics_discovery`

Title: Run signal dynamics along a trajectory

Description: Rank UCell, chromVAR, module-score, or other cell_vector_family signals by dynamic behavior along a trajectory.

### `recipe:inspect_promoted_artifact`

Title: Inspect a promoted artifact

Description: Use artifact getters to inspect identity, provenance, table shape, dependencies, and compatible downstream actions.

### `recipe:plot_ucell_on_umap`

Title: Plot UCell signatures on UMAP

Description: Overlay one or more UCell signature scores from a cell_vector_family onto a 2D space.

### `recipe:plot_trajectory_on_umap`

Title: Plot selected trajectory curves on UMAP

Description: Combine a 2D space with path_2d_family curves and pseudotime/cell overlays for trajectory diagnostics.

### `recipe:mixed_source_composite_trajectory`

Title: Build a mixed-source composite trajectory

Description: Create source-declared trajectory segments, join them with exact boundary collapse, then use the composite pseudotime in explicit-pseudotime dynamics.

### `recipe:de_to_pathway_report`

Title: Differential expression to pathway report

Description: Run DE between two sets, convert ranked/significant features to enrichment queries, and plot top pathway terms.

### `recipe:cluster_markers_pathways`

Title: Cluster to markers to pathways

Description: Cluster cells in a chosen space, find top markers per cluster, and optionally enrich each cluster marker list.

### `recipe:semantic_next_steps_from_artifact`

Title: Find next steps from an artifact

Description: Use the semantic catalog and compatibility graph to find downstream getters, wranglers, plots, and ops compatible with the artifact primitive type.

## wrangler

### `wrangler:table:primitive_to_table`

Title: Primitive To Table Wrangler

Description: Projects primitive-native payloads to normalized data.frames for display, export, or light client use.

### `wrangler:table:client_load_table`

Title: Client Reference To Table Wrangler

Description: Loads a session/artifact/reference through the client facade and converts the resolved primitive to a normalized table.

### `wrangler:plot_mapper:space2d_overlay_v1`

Title: Space + Vector Embedding Overlay Wrangler

Description: Combines a 2D space with optional cell-vector overlays into an embedding_overlay dataset.

### `wrangler:plot_mapper:feature_table_volcano_v1`

Title: Feature Table Volcano Wrangler

Description: Maps differential or trend-like feature tables to volcano plot columns.

### `wrangler:plot_mapper:feature_table_trend_scatter_v1`

Title: Feature Trend Scatter Wrangler

Description: Maps feature trend statistics to a feature_scatter plot dataset.

### `wrangler:plot_mapper:cell_vector_violin_v1`

Title: Cell Vector Violin Wrangler

Description: Combines a numeric cell vector with a grouping vector to form distribution data.

### `wrangler:plot_mapper:cell_vector_category_count_bar_v1`

Title: Categorical Cell Vector Count Wrangler

Description: Counts categorical cell-vector labels for category bar plots.

### `wrangler:plot_mapper:feature_table_dotplot_v1`

Title: Feature Group Dotplot Wrangler

Description: Maps marker-style feature group summaries to dotplot columns.

### `wrangler:plot_mapper:feature_table_pathway_bar_v1`

Title: Pathway Summary Wrangler

Description: Maps pathway enrichment observation tables to ranked pathway bars.

### `wrangler:plot_mapper:feature_table_ranked_lollipop_v1`

Title: Ranked Table Lollipop Wrangler

Description: Maps feature or observation tables with score-like columns to ranked entity data.

### `wrangler:plot_mapper:feature_table_heatmap_ranked_v1`

Title: Ranked Feature Heatmap Wrangler

Description: Maps feature-by-group values to a matrix-like ranked heatmap dataset.

### `wrangler:plot_mapper:feature_table_feature_rank_bar_v1`

Title: Feature Rank Bar Wrangler

Description: Maps feature tables with score-like values to ranked bar data.

### `wrangler:plot_mapper:trajectory_pseudotime_smooth_panel_v1`

Title: Pseudotime Smooth Wrangler

Description: Maps trajectory_smooth tables to per-gene pseudotime curve panels.

### `wrangler:plot_mapper:trajectory_pseudotime_signature_line_v1`

Title: Pseudotime Signature Wrangler

Description: Maps signature, gene-set, signal, or driver curves to pseudotime line datasets.

