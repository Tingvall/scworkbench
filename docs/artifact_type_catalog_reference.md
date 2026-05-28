# scworkbench Artifact Type Catalog

<!-- Generated from wb_artifact_type_catalog_semantic(); do not edit entries by hand. -->

Artifact type count: 53

## cell_vector

### `cell_vector`

Title: Per-Cell Vector Artifact

Description: Promoted per-cell scalar/categorical vector such as pseudotime, labels, entropy, or module score.

Table type: (none)

Entity kind: cell

Use when:
- load per-cell values
- plot overlays or distributions

## cell_vector_family

### `cell_vector_family`

Title: Per-Cell Vector Family Artifact

Description: Promoted keyed family of per-cell vectors, for example UCell signatures or chromVAR deviations.

Table type: (none)

Entity kind: cell_by_key

Use when:
- select one score family key
- compare many signatures or motifs

## feature_table

### `feature_table:de_wilcox`

Title: Wilcoxon DE Table

Description: Feature-level differential expression/accessibility statistics.

Table type: de_wilcox

Entity kind: feature

Use when:
- find marker genes
- plot volcanoes

### `feature_table:markers_topn`

Title: Top Marker Table

Description: Top-ranked marker features per group.

Table type: markers_topn

Entity kind: feature

Use when:
- summarize cluster markers
- build dotplots

### `feature_table:feature_trend_spearman`

Title: Feature Trend Spearman Table

Description: Feature-level association with a continuous vector such as pseudotime.

Table type: feature_trend_spearman

Entity kind: feature

Use when:
- find genes changing with pseudotime
- plot trend statistics

### `feature_table:trajectory_de`

Title: Trajectory DE Table

Description: Feature-level differential or dynamic statistics along trajectory lineages.

Table type: trajectory_de

Entity kind: feature

Use when:
- rank trajectory genes
- feed trajectory dynamics reports

### `feature_table:trajectory_branch_compare`

Title: Trajectory Branch Compare Table

Description: Feature-level branch comparison statistics.

Table type: trajectory_branch_compare

Entity kind: feature

Use when:
- compare branch programs

### `feature_table:knn_pseudobulk`

Title: KNN Pseudobulk Feature Table

Description: Feature summaries over KNN neighborhoods.

Table type: knn_pseudobulk

Entity kind: feature

Use when:
- inspect local pseudobulk expression

### `feature_table:cell_vector_assoc`

Title: Table Type: cell_vector_assoc

Description: Promoted feature_table artifact with table_type='cell_vector_assoc'.

Table type: cell_vector_assoc

Entity kind: feature

Use when:
- inspect promoted table payload
- route artifact through semantic planning

## model_ref

### `model_ref`

Title: Model Reference Artifact

Description: Promoted model reference for projection or method-specific reuse.

Table type: (none)

Entity kind: model

Use when:
- reuse fitted UMAP or trajectory models

## obs_table

### `obs_table:pathway_enrich`

Title: Pathway Enrichment Table

Description: Pathway or gene-set enrichment summary.

Table type: pathway_enrich

Entity kind: pathway

Use when:
- rank enriched pathways
- plot pathway bars

### `obs_table:trajectory_smooth`

Title: Trajectory Smooth Curve Table

Description: Binned/smoothed per-gene expression curves along trajectory pseudotime.

Table type: trajectory_smooth

Entity kind: trajectory_bin

Use when:
- plot gene dynamics
- inspect trajectory expression curves

### `obs_table:trajectory_signature_smooth`

Title: Trajectory Signature Smooth Table

Description: Smoothed signature/module curves along trajectory pseudotime.

Table type: trajectory_signature_smooth

Entity kind: trajectory_bin

Use when:
- plot signature dynamics

### `obs_table:trajectory_geneset_dynamics_curve`

Title: Trajectory Gene-Set Curve Table

Description: Gene-set scores over pseudotime bins.

Table type: trajectory_geneset_dynamics_curve

Entity kind: trajectory_bin

Use when:
- plot GSEA-like dynamics
- find gene sets that turn on or off

### `obs_table:trajectory_geneset_dynamics`

Title: Trajectory Gene-Set Dynamics Table

Description: One row per gene set with dynamics metrics and curve class.

Table type: trajectory_geneset_dynamics

Entity kind: feature_set

Use when:
- rank dynamic gene sets
- filter turns_on/turns_off/transient terms

### `obs_table:trajectory_geneset_dynamics_drivers`

Title: Trajectory Gene-Set Driver Table

Description: Top member genes contributing to dynamic gene-set behavior.

Table type: trajectory_geneset_dynamics_drivers

Entity kind: feature

Use when:
- explain dynamic terms
- plot driver genes

### `obs_table:trajectory_geneset_dynamics_driver_curve`

Title: Trajectory Gene-Set Driver Curves

Description: Driver-gene curves for selected dynamic gene sets.

Table type: trajectory_geneset_dynamics_driver_curve

Entity kind: trajectory_bin

Use when:
- show which genes drive a dynamic term

### `obs_table:trajectory_signal_dynamics_curve`

Title: Trajectory Signal Curve Table

Description: Precomputed signal/vector-family curves over pseudotime.

Table type: trajectory_signal_dynamics_curve

Entity kind: trajectory_bin

Use when:
- plot UCell/chromVAR/signal dynamics

### `obs_table:trajectory_signal_dynamics`

Title: Trajectory Signal Dynamics Table

Description: Dynamics metrics and classes for precomputed signals.

Table type: trajectory_signal_dynamics

Entity kind: signal

Use when:
- rank dynamic UCell or chromVAR signals

### `obs_table:ucell_signature_summary`

Title: UCell Signature Summary

Description: Summary statistics for UCell signature scores.

Table type: ucell_signature_summary

Entity kind: signature

Use when:
- inspect signature score distributions

### `obs_table:chromvar_summary`

Title: chromVAR Motif Summary

Description: Summary statistics for chromVAR motif deviations.

Table type: chromvar_summary

Entity kind: motif

Use when:
- inspect motif activity summaries

### `obs_table:knn_neighbors`

Title: KNN Neighbor Table

Description: Cell-neighbor relationships from a KNN graph/query.

Table type: knn_neighbors

Entity kind: neighbor

Use when:
- inspect local neighborhoods

### `obs_table:matrix_log_normalize_summary`

Title: Matrix Log-Normalization Summary

Description: Summary of a persisted log-normalized matrix transform, including source matrix, output matrix, scale factor, dimensions, and library-size diagnostics.

Table type: matrix_log_normalize_summary

Entity kind: matrix

Use when:
- inspect normalized matrix provenance
- choose a reusable expression matrix for downstream ops

### `obs_table:attach_report`

Title: Table Type: attach_report

Description: Promoted obs_table artifact with table_type='attach_report'.

Table type: attach_report

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_suffix_label`

Title: Table Type: cell_suffix_label

Description: Promoted obs_table artifact with table_type='cell_suffix_label'.

Table type: cell_suffix_label

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_assoc_group_stats`

Title: Table Type: cell_vector_assoc_group_stats

Description: Promoted obs_table artifact with table_type='cell_vector_assoc_group_stats'.

Table type: cell_vector_assoc_group_stats

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_compare`

Title: Table Type: cell_vector_compare

Description: Promoted obs_table artifact with table_type='cell_vector_compare'.

Table type: cell_vector_compare

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_compare_summary`

Title: Table Type: cell_vector_compare_summary

Description: Promoted obs_table artifact with table_type='cell_vector_compare_summary'.

Table type: cell_vector_compare_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_calibration_summary`

Title: Table Type: cell_vector_family_calibration_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_calibration_summary'.

Table type: cell_vector_family_calibration_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_qc_group_summary`

Title: Table Type: cell_vector_family_qc_group_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_group_summary'.

Table type: cell_vector_family_qc_group_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_qc_key_summary`

Title: Table Type: cell_vector_family_qc_key_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_key_summary'.

Table type: cell_vector_family_qc_key_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_qc_pairwise_summary`

Title: Table Type: cell_vector_family_qc_pairwise_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_qc_pairwise_summary'.

Table type: cell_vector_family_qc_pairwise_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_reduce_decision_table`

Title: Table Type: cell_vector_family_reduce_decision_table

Description: Promoted obs_table artifact with table_type='cell_vector_family_reduce_decision_table'.

Table type: cell_vector_family_reduce_decision_table

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:cell_vector_family_reduce_summary`

Title: Table Type: cell_vector_family_reduce_summary

Description: Promoted obs_table artifact with table_type='cell_vector_family_reduce_summary'.

Table type: cell_vector_family_reduce_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:generic`

Title: Table Type: generic

Description: Promoted obs_table artifact with table_type='generic'.

Table type: generic

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:ingest_report`

Title: Table Type: ingest_report

Description: Promoted obs_table artifact with table_type='ingest_report'.

Table type: ingest_report

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:space_path_score_summary`

Title: Table Type: space_path_score_summary

Description: Promoted obs_table artifact with table_type='space_path_score_summary'.

Table type: space_path_score_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_branch_compare_summary`

Title: Table Type: trajectory_branch_compare_summary

Description: Promoted obs_table artifact with table_type='trajectory_branch_compare_summary'.

Table type: trajectory_branch_compare_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_de_summary`

Title: Table Type: trajectory_de_summary

Description: Promoted obs_table artifact with table_type='trajectory_de_summary'.

Table type: trajectory_de_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_geneset_dynamics_summary`

Title: Table Type: trajectory_geneset_dynamics_summary

Description: Promoted obs_table artifact with table_type='trajectory_geneset_dynamics_summary'.

Table type: trajectory_geneset_dynamics_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_geneset_dynamics_top`

Title: Table Type: trajectory_geneset_dynamics_top

Description: Promoted obs_table artifact with table_type='trajectory_geneset_dynamics_top'.

Table type: trajectory_geneset_dynamics_top

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_route_smooth`

Title: Table Type: trajectory_route_smooth

Description: Promoted obs_table artifact with table_type='trajectory_route_smooth'.

Table type: trajectory_route_smooth

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_route_smooth_summary`

Title: Table Type: trajectory_route_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_route_smooth_summary'.

Table type: trajectory_route_smooth_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_signal_dynamics_summary`

Title: Table Type: trajectory_signal_dynamics_summary

Description: Promoted obs_table artifact with table_type='trajectory_signal_dynamics_summary'.

Table type: trajectory_signal_dynamics_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_signal_dynamics_top`

Title: Table Type: trajectory_signal_dynamics_top

Description: Promoted obs_table artifact with table_type='trajectory_signal_dynamics_top'.

Table type: trajectory_signal_dynamics_top

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_signature_smooth_summary`

Title: Table Type: trajectory_signature_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_signature_smooth_summary'.

Table type: trajectory_signature_smooth_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_smooth_summary`

Title: Table Type: trajectory_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_smooth_summary'.

Table type: trajectory_smooth_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_vector_smooth`

Title: Table Type: trajectory_vector_smooth

Description: Promoted obs_table artifact with table_type='trajectory_vector_smooth'.

Table type: trajectory_vector_smooth

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

### `obs_table:trajectory_vector_smooth_summary`

Title: Table Type: trajectory_vector_smooth_summary

Description: Promoted obs_table artifact with table_type='trajectory_vector_smooth_summary'.

Table type: trajectory_vector_smooth_summary

Entity kind: generic

Use when:
- inspect promoted table payload
- route artifact through semantic planning

## path_2d_family

### `path_2d_family`

Title: 2D Path Family Artifact

Description: Promoted 2D trajectory or lineage curves.

Table type: (none)

Entity kind: path_point

Use when:
- draw trajectory curves
- inspect selected lineages

## relation_family

### `relation_family`

Title: Relation Family Artifact

Description: Promoted sparse long-form cell-to-key relations such as branch membership.

Table type: (none)

Entity kind: cell_relation

Use when:
- inspect branch assignment
- load fuzzy membership

## space_2d

### `space_2d`

Title: 2D Space Artifact

Description: Promoted reference to a 2D bundle space.

Table type: (none)

Entity kind: cell

Use when:
- plot embeddings
- provide spatial context to wranglers

## space_path_family

### `space_path_family`

Title: Space Path Family Artifact

Description: Promoted high-dimensional route/trajectory paths.

Table type: (none)

Entity kind: space_path_point

Use when:
- score cells against checkpoint paths
- reuse space trajectories

