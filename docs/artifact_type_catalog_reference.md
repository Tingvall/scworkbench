# scworkbench Artifact Type Catalog

<!-- Generated from wb_artifact_type_catalog_semantic(); do not edit entries by hand. -->

Artifact type count: 25

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

