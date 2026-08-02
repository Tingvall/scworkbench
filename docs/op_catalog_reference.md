# scworkbench Operation Catalog

<!-- Generated from wb_op_catalog_semantic(); do not edit op entries by hand. -->

Generated at: 2026-08-02T17:32:45+0200

Operation count: 56

This document summarizes registered scworkbench ops for humans, agents, and semantic indexing.
The machine-readable companion is `docs/op_catalog_semantic.json`.

## `leiden`

Title: Leiden clustering

Intent: cluster

Description: Graph clustering on a kNN graph derived from an embedding space.

Consumes:
- `space`: space
- `cell_set`: select

Produces:
- `clusters`: cell_vector [terminal artifact] - Cluster label per cell (categorical cell vector).

Promotable outputs: clusters

Replay equivalence:
- `clusters`: `exact_canonical_value`

Key parameters:
- `dims` (int_range, default=1:30): Which dimensions of the space to use (1-indexed).
- `k` (int, default=30): Number of neighbors for kNN graph.
- `resolution` (dbl, default=1): Leiden resolution parameter.
- `seed` (int, default=1): Random seed.

## `matrix_log_normalize`

Title: Log-normalize count matrix

Intent: matrix, normalize, rna, transform

Description: Create a reusable log1p(counts / library_size * scale_factor) BPCells matrix in the bundle.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `matrix`: matrix [materialization; committed by: summary] - Reference to the newly registered log-normalized matrix.
- `summary`: obs_table [terminal artifact] - Transform parameters, source/output matrix ids, dimensions, library-size diagnostics, and storage path.

Promotable outputs: summary

Replay equivalence:
- `matrix`: `exact_canonical_value`
- `summary`: `exact_canonical_value`

Key parameters:
- `output_matrix_id` (string, default=NULL): Matrix id to create, for example RNA_log1p_cp10k. Defaults to <source>_log1p_cp<scale_factor>.
- `scale_factor` (dbl, default=10000): Per-cell target count scale before log1p; 10000 is the common CP10K convention.
- `overwrite` (bool, default=FALSE): If TRUE, replace an existing output matrix with the same id.
- `cell_set` (cell_set, default=all): Must be 'all' because the output matrix is registered as a full bundle matrix.

## `hvg_select`

Title: Highly Variable Feature Selection

Intent: matrix, feature_selection, rna, hvg

Description: Select highly variable features from a matrix using chunked feature-wise summaries.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `selected_features`: feature_table [terminal artifact] - Feature-wise mean, variance, dispersion, score, rank, and selected flag.
- `fit_summary`: obs_table [terminal artifact] - Input matrix, method, filters, dimensions, and selection counts.

Promotable outputs: selected_features, fit_summary

Replay equivalence:
- `selected_features`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `n_features` (int, default=2000): Number of highly variable features to mark selected.
- `method` (choice, default=vst): Feature scoring method. 'vst' is a lightweight stabilized dispersion score log1p(variance / mean).
- `min_mean` (dbl, default=NULL): Optional minimum feature mean filter.
- `max_mean` (dbl, default=NULL): Optional maximum feature mean filter.
- `min_dispersion` (dbl, default=NULL): Optional minimum HVG score filter.
- `batch_key` (string, default=NULL): Reserved for future batch-aware HVG; currently unsupported if non-null.
- `exclude_features` (string_vec, default=NULL): Optional feature IDs to exclude before ranking.
- `feature_type` (string, default=NULL): Optional feature_type filter from the bundle feature registry.
- `seed` (int, default=1): Random seed reserved for deterministic future methods.
- `chunk_size` (int, default=256): Feature chunk size for backed matrix reads.

## `pca_fit`

Title: PCA Fit

Intent: matrix, pca, space, rna, dimension_reduction

Description: Compute PCA from a matrix and selected features, then persist the cell coordinates as a bundle space.

Consumes:
- `matrix`: matrix
- `features`: feature_table
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: loadings, variance, fit_summary] - Reference to the persisted PCA space.
- `loadings`: feature_table [terminal artifact] - Feature loadings per principal component.
- `variance`: obs_table [terminal artifact] - Per-PC standard deviation and variance explained.
- `fit_summary`: obs_table [terminal artifact] - Input matrix, feature count, backend, component count, and output space id.

Promotable outputs: loadings, variance, fit_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `loadings`: `exact_canonical_value`
- `variance`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `feature_ids` (string_vec, default=NULL): Optional explicit feature IDs when not passing features as a feature_table reference.
- `n_components` (int, default=50): Number of principal components to compute.
- `center` (bool, default=TRUE): Center features before PCA.
- `scale` (bool, default=TRUE): Scale features before PCA.
- `backend` (choice, default=irlba): PCA backend. 'irlba' is recommended for large sparse/backed matrices.
- `seed` (int, default=1): Random seed.
- `space_id_out` (string, default=rna.pca): Bundle space id to create.
- `overwrite` (bool, default=FALSE): Replace an existing space_id_out if present.
- `max_dense_gb` (dbl, default=8): Approximate dense selected-block size guard for dense backends.

## `umap_fit`

Title: UMAP fit (train model)

Intent: umap, fit

Description: Fit a UMAP model on a space and store it for future projection.

Consumes:
- `space`: space
- `cell_set`: select

Produces:
- `model`: model_ref [terminal artifact] - Reference to the fitted UMAP model.
- `space_2d`: space_2d [terminal artifact] - The fitted 2D embedding space id.

Promotable outputs: space_2d, model

Replay equivalence:
- `model`: `loadable_reference`
- `space_2d`: `exact_canonical_value`

Key parameters:
- `dims` (int_range, default=NULL): Dims to use (e.g. 2:30).
- `space_id_out` (string, default=NULL): Output 2D space id. Defaults to umap.<source_space>.
- `n_neighbors` (int, default=30): UMAP neighborhood size.
- `min_dist` (dbl, default=0.3): UMAP minimum distance.
- `metric` (string, default=euclidean): Distance metric passed to uwot.
- `nn_method` (choice, default=nndescent): Nearest-neighbor backend. 'nndescent' requires rnndescent; 'fnn' requires FNN; 'annoy' uses uwot's Annoy backend.
- `spread` (dbl, default=1): UMAP spread parameter.
- `seed` (int, default=1): Random seed.

## `umap_transform`

Title: UMAP transform (project cells)

Intent: projection, umap

Description: Project cells into an existing UMAP using a stored model.

Consumes:
- `model`: model_ref
- `in_space`: space
- `cell_set`: select

Produces:
- `space_2d`: space_2d [terminal artifact] - Projected x/y in the target UMAP space.

Promotable outputs: space_2d

Replay equivalence:
- `space_2d`: `exact_canonical_value`

Key parameters:
- `dims` (int_range, default=NULL): Dims to use from the input space (e.g. 2:30).
- `overwrite` (bool, default=TRUE): Overwrite existing projected coordinates for those cells.

## `addmodulescore`

Title: Add module score

Intent: expression, signature, score

Description: Seurat-style module scoring using matched control features by expression bin.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `module_scores`: cell_vector_family [terminal artifact] - Per-cell module scores for one or more signatures.

Promotable outputs: module_scores

Replay equivalence:
- `module_scores`: `exact_canonical_value`

Key parameters:
- `features` (string_vec_or_list, default=NULL): Module feature IDs: character vector or list of vectors.
- `pool` (string_vec, default=NULL): Optional control feature pool; defaults to all matrix features.
- `nbin` (int, default=24): Number of expression bins for control matching.
- `ctrl` (int, default=100): Control features sampled per module feature.
- `name` (string, default=Module): Prefix for module names when features are unnamed.
- `seed` (int, default=1): Random seed for control sampling.

## `ucell`

Title: UCell Signature Scoring

Intent: expression, signature, score

Description: Rank-based per-cell signature scoring using the UCell method.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `signature_scores`: cell_vector_family [terminal artifact] - Per-cell UCell scores for one or more signatures.
- `signature_summary`: obs_table [terminal artifact] - Per-signature scoring summary and feature-match diagnostics.

Promotable outputs: signature_scores, signature_summary

Replay equivalence:
- `signature_scores`: `exact_canonical_value`
- `signature_summary`: `exact_canonical_value`

Key parameters:
- `features` (string_vec_or_list, default=NULL): Signature feature IDs: character vector or list of vectors.
- `name` (string, default=Signature): Prefix for signature names when features are unnamed.
- `max_rank` (int, default=1500): Maximum rank considered by UCell.
- `ncores` (int, default=1): Number of worker processes requested by UCell.
- `parallel_backend` (choice, default=auto): Execution backend for UCell. Use 'serial' to avoid socket-based parallel backends on constrained systems.
- `chunk_size` (int, default=2000): Cell-axis chunk size for engine-owned UCell execution. Use NULL to disable chunking.
- `missing_features_policy` (choice, default=drop): How to handle signature features missing from the matrix.

## `cell_vector_family_reduce`

Title: Reduce Cell Vector Family

Intent: label, reduce, signal

Description: Compress a cell_vector_family into one categorical cell_vector using explicit reduction and abstention rules.

Consumes:
- `signal`: cell_vector_family
- `cell_set`: select

Produces:
- `label`: cell_vector [terminal artifact] - Per-cell categorical labels after reducing the signal family.
- `top_score`: cell_vector [terminal artifact] - Winning score for each cell.
- `runner_up_score`: cell_vector [terminal artifact] - Second-best score for each cell.
- `score_margin`: cell_vector [terminal artifact] - Winning minus runner-up score for each cell.
- `abstain_reason`: cell_vector [terminal artifact] - Per-cell abstention reason (`none`, `tie`, `min_score`, `min_margin`).
- `decision_table`: obs_table [terminal artifact] - Per-cell reduction diagnostics including label, scores, margin, and abstention reason.
- `label_summary`: obs_table [terminal artifact] - Per-label counts and score summaries after reduction.

Promotable outputs: label, top_score, runner_up_score, score_margin, abstain_reason, decision_table, label_summary

Replay equivalence:
- `label`: `exact_canonical_value`
- `top_score`: `exact_canonical_value`
- `runner_up_score`: `exact_canonical_value`
- `score_margin`: `exact_canonical_value`
- `abstain_reason`: `exact_canonical_value`
- `decision_table`: `exact_canonical_value`
- `label_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `rule` (choice, default=argmax): Reduction rule used to choose one label per cell.
- `min_score` (dbl, default=NULL): Optional minimum winning score required to emit a non-unknown label.
- `min_margin` (dbl, default=NULL): Optional minimum top-vs-second margin required to emit a non-unknown label.
- `unknown_label` (string, default=unknown): Fallback label emitted when thresholds or ties abstain.
- `ties` (choice, default=unknown): How to handle tied top scores.
- `tie_tol` (dbl, default=1e-08): Tolerance used when detecting ties.

## `cell_vector_family_calibrate`

Title: Calibrate Cell Vector Family

Intent: signal, calibrate, normalize

Description: Normalize one keyed per-cell signal family within keys so cross-key comparisons become more meaningful.

Consumes:
- `signal`: cell_vector_family
- `cell_set`: select

Produces:
- `calibrated_signal`: cell_vector_family [terminal artifact] - Calibrated per-cell values for each key in the signal family.
- `calibration_summary`: obs_table [terminal artifact] - Per-key calibration statistics for raw and calibrated values.

Promotable outputs: calibrated_signal, calibration_summary

Replay equivalence:
- `calibrated_signal`: `exact_canonical_value`
- `calibration_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `method` (choice, default=percentile): Calibration method applied independently within each key.
- `center` (bool, default=TRUE): For z-score calibration, subtract the fitted center.
- `scale` (bool, default=TRUE): For z-score calibration, divide by the fitted scale.
- `ties_method` (choice, default=average): Rank tie handling for percentile calibration.
- `na_rm` (bool, default=TRUE): Ignore non-finite values when fitting calibration.

## `cell_vector_family_qc`

Title: QC Cell Vector Family

Intent: signal, qc, diagnostics

Description: Compute per-key and pairwise diagnostics for one keyed per-cell signal family.

Consumes:
- `signal`: cell_vector_family
- `grouping`: cell_vector
- `cell_set`: select

Produces:
- `key_summary`: obs_table [terminal artifact] - Per-key QC summaries including score distribution, finite coverage, and winner frequencies.
- `pairwise_summary`: obs_table [terminal artifact] - Pairwise key relationships including overlap counts and correlations.
- `group_summary`: obs_table [terminal artifact] - Per-group per-key QC summaries when an optional grouping vector is supplied.

Promotable outputs: key_summary, pairwise_summary, group_summary

Replay equivalence:
- `key_summary`: `exact_canonical_value`
- `pairwise_summary`: `exact_canonical_value`
- `group_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `correlation_methods` (string_vec, default=pearson|spearman): Pairwise correlation methods to compute between keys.
- `tie_tol` (dbl, default=1e-08): Tolerance used when counting tied top-key winners.

## `cell_vector_family_graph_smooth`

Title: Graph Smooth Cell Vector Family

Intent: signal, smoothing, geometry

Description: Smooth each key of a cell_vector_family over local nearest-neighbor geometry in a selected bundle space.

Consumes:
- `signal`: cell_vector_family
- `space`: space
- `cell_set`: select

Produces:
- `smoothed_signal`: cell_vector_family [terminal artifact] - Geometry-smoothed per-cell values for each selected key.
- `smoothing_summary`: obs_table [terminal artifact] - Per-key smoothing diagnostics and parameter echo.

Promotable outputs: smoothed_signal, smoothing_summary

Replay equivalence:
- `smoothed_signal`: `exact_canonical_value`
- `smoothing_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional key subset within the cell_vector_family.
- `dims` (int_vec, default=NULL): Optional dimensions of the selected space. NULL uses all dimensions.
- `k` (int, default=30): Nearest-neighbor count per cell.
- `alpha` (dbl, default=0.5): Blend weight for raw score in alpha * raw + (1 - alpha) * neighbor_mean.
- `distance_metric` (choice, default=euclidean): Distance metric used for nearest-neighbor search.
- `query_chunk_size` (int, default=512): Number of query cells processed per nearest-neighbor chunk.
- `include_self` (bool, default=FALSE): Include each cell itself in its neighbor mean.
- `na_policy` (choice, default=ignore): How missing signal values are handled during neighbor averaging.
- `source_signal_artifact_id` (string, default=NULL): Optional source cell_vector_family artifact ID copied into metadata.
- `source_run_id` (string, default=NULL): Optional source run ID copied into metadata.
- `source_snapshot_id` (string, default=NULL): Optional source provenance snapshot ID copied into metadata.

## `cell_vector_winners`

Title: Cell Vector Winner Assignment

Intent: signal, labeling, winner

Description: Assign one winning key per cell from a cell_vector_family and report confidence and pruning metrics.

Consumes:
- `signal`: cell_vector_family
- `cell_set`: select

Produces:
- `winners`: obs_table [terminal artifact] - Per-cell winner, runner-up, confidence, and pruning table.

Promotable outputs: winners

Replay equivalence:
- `winners`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional key subset within the cell_vector_family.
- `min_winners` (int, default=10): Minimum raw winner count required for a winner label to pass pruning.
- `tie_method` (choice, default=first): Deterministic tie handling for top-score winners.
- `source_score_artifact_id` (string, default=NULL): Optional source cell_vector_family artifact ID copied into winner table metadata.
- `source_run_id` (string, default=NULL): Optional source run ID copied into winner table metadata.
- `source_snapshot_id` (string, default=NULL): Optional source provenance snapshot ID copied into winner table metadata.

## `winner_cell_sets`

Title: Winner Cell-Set Registration

Intent: signal, labeling, cell_sets

Description: Register bundle cell sets from a cell_vector_winners obs_table and return a manifest table.

Consumes:
- `winners`: obs_table
- `cell_set`: select

Produces:
- `manifest`: obs_table [terminal artifact] - One row per registered winner cell set.

Promotable outputs: manifest

Replay equivalence:
- `manifest`: `exact_canonical_value`

Key parameters:
- `source_winner_artifact_id` (string, default=NULL): Optional source winner obs_table artifact ID copied into manifest metadata.
- `cell_set_prefix` (string, default=winner_): Prefix used after set: when creating winner cell-set names.
- `winner_col` (string, default=winner): Winner-label column in the winner table.
- `passes_col` (string, default=passes_pruning): Logical pruning-pass column in the winner table.
- `source` (string, default=cell_vector_winners): Source label stored on cell-set membership rows.
- `created_by` (string, default=NULL): Optional actor stored on cell-set membership rows.
- `replace` (logical, default=TRUE): If TRUE, replace existing winner cell-set memberships.

## `chromvar`

Title: chromVAR deviations

Intent: atac, motif, signature, score

Description: Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `deviation_z`: cell_vector_family [terminal artifact] - Per-cell chromVAR z-scores keyed by motif.
- `deviation_raw`: cell_vector_family [terminal artifact] - Per-cell raw chromVAR deviations keyed by motif.
- `motif_summary`: obs_table [terminal artifact] - Per-motif chromVAR summary statistics.

Promotable outputs: deviation_z, deviation_raw, motif_summary

Replay equivalence:
- `deviation_z`: `exact_canonical_value`
- `deviation_raw`: `exact_canonical_value`
- `motif_summary`: `exact_canonical_value`

Key parameters:
- `motif_library` (string, default=NULL): Canonical motif-library key from the motif registry.
- `motifs` (string_vec, default=NULL): Optional motif-key subset within motif_library.
- `motif_match_set` (string, default=NULL): Optional canonical motif-match-set key to reuse cached motif-to-peak matches.
- `min_motif_peaks` (int, default=10): Minimum number of matched peaks per retained motif.
- `max_motif_peaks` (int, default=NULL): Optional maximum number of matched peaks per retained motif.
- `motif_p_cutoff` (dbl, default=5e-05): Motifmatchr p-value cutoff.
- `motif_w` (int, default=7): Motifmatchr background window width.
- `seqlevels_mode` (choice, default=standard): Seqlevel policy; standard chromosomes are the default.
- `seqlevels_include` (string_vec, default=NULL): Optional explicit seqlevels to keep after applying seqlevels_mode.
- `seqlevels_exclude` (string_vec, default=NULL): Optional explicit seqlevels to drop after applying seqlevels_mode.
- `background_iterations` (int, default=50): Number of chromVAR background iterations.
- `background_w` (dbl, default=0.1): Background peak matching window width.
- `background_bs` (int, default=50): Background peak matching bin count.

## `de_wilcox`

Title: Differential Expression (Wilcoxon)

Intent: de, markers, comparison

Description: Wilcoxon rank-sum DE between two cell groups (A vs B).

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `de_table`: feature_table [terminal artifact] - Feature-level DE statistics table.

Promotable outputs: de_table

Replay equivalence:
- `de_table`: `exact_canonical_value`

Key parameters:
- `group_a` (cell_ids_or_set, default=NULL): Group A cells: vector of cell IDs or 'set:<name>'.
- `group_b` (cell_ids_or_set, default=NULL): Group B cells: vector of cell IDs or 'set:<name>'.
- `features` (string_vec, default=NULL): Optional feature subset.
- `min_pct` (dbl, default=0): Minimum detection fraction in either group.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.

## `markers_topn`

Title: Top Markers Per Cluster

Intent: markers, cluster

Description: One-vs-rest Wilcoxon marker ranking for each cluster.

Consumes:
- `matrix`: matrix
- `clusters`: cell_vector
- `cell_set`: select

Produces:
- `markers`: feature_table [terminal artifact] - Cluster-marker table with per-feature statistics.

Promotable outputs: markers

Replay equivalence:
- `markers`: `exact_canonical_value`

Key parameters:
- `features` (string_vec, default=NULL): Optional feature subset.
- `top_n` (int, default=20): Top markers retained per cluster.
- `min_pct` (dbl, default=0.1): Minimum detection fraction in either group.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.

## `pathway_enrich`

Title: Pathway Enrichment (Namespace)

Intent: pathway, enrichment

Description: Hypergeometric enrichment against all feature sets in a namespace.

Consumes:
- `matrix`: matrix
- `feature_table`: feature_table
- `cell_set`: select

Produces:
- `pathways`: obs_table [terminal artifact] - Pathway enrichment statistics for one namespace.

Promotable outputs: pathways

Replay equivalence:
- `pathways`: `exact_canonical_value`

Key parameters:
- `namespace` (string, default=NULL): Feature-set namespace from wb_feature_sets() (e.g. bcell_gsea).
- `feature_col` (string, default=feature_id): Column in input feature table containing feature IDs (usually feature_id).
- `p_adj_col` (string, default=p_val_adj): Adjusted p-value column used for query filtering.
- `p_adj_max` (dbl, default=0.05): Maximum adjusted p-value for query features.
- `lfc_col` (string, default=avg_log1p_fc): Effect-size column used for directional filtering.
- `direction` (string, default=any): Directional filter: any|up|down.
- `lfc_min_abs` (dbl, default=0): Minimum |effect| when direction='any'.
- `lfc_min` (dbl, default=0.25): Minimum effect for direction='up'/'down'.
- `min_set_size` (int, default=5): Minimum pathway size to test.
- `max_set_size` (int, default=5000): Maximum pathway size to test.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.

## `feature_set_import`

Title: Feature-Set Library Import

Intent: feature_set, import, gene_set, provenance, library

Description: Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `import_summary`: obs_table [terminal artifact] - One-row summary of parsed/imported/skipped/rejected set counts.
- `import_manifest`: obs_table [terminal artifact] - One row per parsed feature set with target namespace, overlap counts, and import status.
- `rejected_sets`: obs_table [terminal artifact] - Feature sets rejected during import, typically because no genes mapped to the matrix.

Promotable outputs: import_summary, import_manifest, rejected_sets

Replay equivalence:
- `import_summary`: `exact_canonical_value`
- `import_manifest`: `exact_canonical_value`
- `rejected_sets`: `exact_canonical_value`

Key parameters:
- `source_path` (path, default=NULL): Path to GMT, RDS list/data.frame, or CSV-like table source.
- `source_format` (choice, default=auto): Input parser. auto infers from file extension.
- `namespace` (string, default=NULL): Target feature-set namespace base label.
- `collection` (string, default=NULL): Optional collection label recorded in import manifests.
- `subcollection` (string, default=NULL): Optional subcollection label; used for namespace splitting when requested.
- `species` (string, default=NULL): Species/organism label recorded in feature-set metadata.
- `gene_id_type` (string, default=NULL): Identifier type expected in source genes, for example gene_symbol.
- `set_id_col` (string, default=feature_set): For table sources, column containing set identifiers.
- `set_name_col` (string, default=NULL): For table sources, optional human-readable set-name column.
- `gene_col` (string, default=feature_id): For table sources, column containing gene/feature identifiers.
- `description_col` (string, default=description): For table sources, optional set description column.
- `split_by_collection` (bool, default=FALSE): If TRUE, append detected/declared subcollection to the namespace base.
- `overwrite` (bool, default=TRUE): If FALSE, existing feature sets are skipped instead of replaced.
- `strict` (bool, default=FALSE): If TRUE, error on genes absent from the matrix; otherwise drop absent genes.
- `source_id` (string, default=NULL): Optional source/library identifier stored in feature-set metadata.
- `source_version` (string, default=NULL): Optional source/library version stored in feature-set metadata.

## `feature_set_overlap_qc`

Title: Feature-Set Matrix Overlap QC

Intent: feature_set, qc, gene_set, screening, trajectory

Description: Screen imported feature-set namespaces against a matrix before pathway or trajectory discovery.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `overlap_qc`: obs_table [terminal artifact] - One row per feature set with raw, mapped, detected counts and include/exclude status.
- `namespace_summary`: obs_table [terminal artifact] - Namespace-level count and overlap summaries.

Promotable outputs: overlap_qc, namespace_summary

Replay equivalence:
- `overlap_qc`: `exact_canonical_value`
- `namespace_summary`: `exact_canonical_value`

Key parameters:
- `namespace` (string, default=NULL): Single feature-set namespace to QC.
- `namespaces` (string_vec, default=NULL): Optional multiple feature-set namespaces to QC.
- `feature_sets` (string_vec, default=NULL): Optional feature-set subset within selected namespaces.
- `min_set_size` (int, default=1): Minimum mapped/detected genes required to include a set.
- `max_set_size` (dbl, default=Inf): Maximum mapped/detected genes allowed to include a set.
- `min_detected_fraction` (dbl, default=0): Minimum fraction of source genes detected in the matrix.
- `deduplicate_sets` (bool, default=TRUE): If TRUE, duplicate mapped-gene signatures after the first are excluded.

## `feature_set_namespace_transfer`

Title: Feature-Set Namespace Transfer

Intent: feature_set, transfer, namespace, matrix, provenance

Description: Transfer matrix-scoped feature-set namespaces between comparable matrices using mirror or intersect semantics.

Consumes:
- `cell_set`: select

Produces:
- `transfer_summary`: obs_table [terminal artifact] - Namespace-level summary of transfer mode, matrix compatibility, and transferred/skipped/rejected set counts.
- `transfer_manifest`: obs_table [terminal artifact] - One row per source feature set with source/target matrices, namespaces, retained members, status, and set IDs.
- `transfer_rejected`: obs_table [terminal artifact] - Feature sets rejected during intersect transfer because retained members failed thresholds.

Promotable outputs: transfer_summary, transfer_manifest, transfer_rejected

Replay equivalence:
- `transfer_summary`: `exact_canonical_value`
- `transfer_manifest`: `exact_canonical_value`
- `transfer_rejected`: `exact_canonical_value`

Key parameters:
- `namespace` (string, default=NULL): Single source namespace to transfer.
- `namespaces` (string_vec, default=NULL): Optional multiple source namespaces to transfer.
- `feature_sets` (string_vec, default=NULL): Optional feature-set subset within selected source namespaces.
- `mode` (choice, default=mirror): mirror requires identical feature universes; intersect retains only target-valid members and records loss.
- `target_namespace` (string, default=NULL): Optional target namespace override. Defaults to the source namespace.
- `overwrite` (bool, default=FALSE): If FALSE, existing target feature sets are skipped instead of replaced.
- `strict` (bool, default=TRUE): If TRUE, fail when intersect mode rejects any selected set by retention thresholds.
- `min_retained_features` (int, default=1): Minimum target-retained members required to transfer a set.
- `min_retained_fraction` (dbl, default=0): Minimum fraction of source members retained on the target matrix.
- `created_by` (string, default=NULL): Optional created_by metadata for transferred registry rows.
- `notes` (string, default=NULL): Optional provenance note. This op is not for gene-to-peak, peak-to-gene, motif-to-TF, ortholog, or synonym mapping.

## `cell_suffix_label`

Title: Cell Labels From ID Suffix

Intent: annotation, metadata

Description: Build a categorical cell vector by parsing cell_id suffix tokens.

Consumes:
- `cell_set`: select

Produces:
- `labels`: cell_vector [terminal artifact] - Categorical label per cell from suffix parsing.
- `label_table`: obs_table [terminal artifact] - Per-cell suffix/label table.

Promotable outputs: labels, label_table

Replay equivalence:
- `labels`: `exact_canonical_value`
- `label_table`: `exact_canonical_value`

Key parameters:
- `sep` (string, default=-): Separator used in cell IDs before suffix token.
- `mapping` (string_vec, default=NULL): Optional named mapping suffix->label.
- `default_label` (string, default=UNKNOWN): Fallback label for unmapped suffixes.

## `cell_set_derive`

Title: Derived Cell Set

Intent: selection, provenance, registry

Description: Materialize a selector-derived or explicitly declared cell universe as a named cell set with lifecycle role/status and manifest tables.

Consumes:
- `cell_set`: select

Produces:
- `manifest`: obs_table [terminal artifact] - One-row lifecycle manifest for the named derived cell set, including counts, role, status, recipe availability, and source summary.
- `rule_table`: obs_table [terminal artifact] - Ordered per-rule derivation audit table with input/output/removal counts and source fields.

Promotable outputs: manifest, rule_table

Replay equivalence:
- `manifest`: `exact_canonical_value`
- `rule_table`: `exact_canonical_value`

Key parameters:
- `target_cell_set` (string, default=NULL): Name of the derived cell set to create, for example set:universe_b_l1_weight090.
- `role` (choice, default=analysis_universe): Lifecycle role of the derived set.
- `status` (choice, default=candidate): Lifecycle status controlling interpretation and default visibility.
- `source` (string, default=selector_recipe): Source/provenance label stored on membership rows.
- `created_by` (string, default=NULL): Optional creator label.
- `description` (string, default=NULL): Human-readable derivation rationale.
- `overwrite` (bool, default=TRUE): If TRUE, replace existing membership for the target set; if FALSE, add cells to it.

## `cell_vector_assoc`

Title: Cell Vector Association

Intent: statistics, association, confounding

Description: Test whether a continuous cell-level signal differs across groups defined by a categorical cell-level vector.

Consumes:
- `vector_cont`: cell_vector - Examples: pseudotime, module score, gene-program score.
- `vector_group`: cell_vector - Examples: cluster labels, cell type labels, condition labels.
- `cell_set`: select

Produces:
- `assoc_summary`: feature_table [terminal artifact] - Omnibus association test summary (Kruskal/ANOVA).
- `group_stats`: obs_table [terminal artifact] - Per-group descriptive statistics.

Promotable outputs: assoc_summary, group_stats

Replay equivalence:
- `assoc_summary`: `exact_canonical_value`
- `group_stats`: `exact_canonical_value`

Key parameters:
- `min_n_per_group` (int, default=3): Minimum cells per group.

## `metadata_cell_vector`

Title: Metadata Cell Vector

Intent: metadata, cell_vector, provenance, technical_diagnostics

Description: Materialize an imported cell metadata column as a typed, provenance-backed cell vector.

Consumes:
- `cell_set`: select

Produces:
- `vector`: cell_vector [terminal artifact] - Typed per-cell vector materialized from imported bundle metadata.

Promotable outputs: vector

Replay equivalence:
- `vector`: `exact_canonical_value`

Key parameters:
- `source_column` (string, default=NULL): Imported cell metadata column to materialize.
- `cell_set` (cell_set, default=all): Named bundle cell set defining the vector universe.
- `value_type` (choice, default=auto): Explicit vector value type; auto records a conservative native-type decision.
- `missing_policy` (choice, default=error): How missing values are handled before vector materialization.
- `missing_label` (string, default=__MISSING__): Replacement label when missing_policy='as_category'.
- `vector_name` (string, default=NULL): Stable promoted vector name; collision protection is controlled by overwrite.
- `overwrite` (bool, default=FALSE): Allow a new immutable artifact to supersede an existing vector with the same name.

## `cell_vector_association`

Title: Cell Vector Association

Intent: statistics, association, confounding

Description: Associate two typed cell vectors with categorical and continuous dispatch.

Consumes:
- `a`: cell_vector - Categorical or continuous cell vector.
- `b`: cell_vector - Categorical or continuous cell vector.
- `cell_set`: select

Produces:
- `summary`: obs_table [terminal artifact] - Typed association summary including method, effect size, and diagnostics.
- `detail`: obs_table [terminal artifact] - Contingency, group-statistic, or per-cell association detail appropriate to the dispatched test.

Promotable outputs: summary, detail

Replay equivalence:
- `summary`: `exact_canonical_value`
- `detail`: `exact_canonical_value`

Key parameters:
- `cell_set` (cell_set, default=all): Named bundle cell set defining the association universe.
- `min_n_per_group` (int, default=3): Minimum cells per retained categorical group.
- `method` (choice, default=auto): Association method or typed automatic dispatch.

## `cell_vector_compare`

Title: Cell Vector Comparison

Intent: statistics, comparison, signal

Description: Compare two cell-level signals on their shared cell universe in raw or rank space.

Consumes:
- `a`: cell_vector - Continuous or rankable numeric signal per cell.
- `b`: cell_vector - Continuous or rankable numeric signal per cell.
- `cell_set`: select

Produces:
- `summary`: obs_table [terminal artifact] - One-row comparison summary with concordance and delta metrics.
- `comparison`: obs_table [terminal artifact] - Per-cell comparison table with original values, compared values, and deltas.

Promotable outputs: summary, comparison

Replay equivalence:
- `summary`: `exact_canonical_value`
- `comparison`: `exact_canonical_value`

Key parameters:
- `compare_space` (choice, default=rank): Whether to compare original numeric values or cell ranks.
- `ties_method` (choice, default=average): Tie handling rule used when compare_space='rank'.
- `signal_a` (string, default=a): Optional label recorded in the summary table for signal A.
- `signal_b` (string, default=b): Optional label recorded in the summary table for signal B.

## `feature_trend_spearman`

Title: Feature Trends vs Continuous Vector

Intent: trend, statistics, trajectory

Description: Feature-level Spearman trend testing against continuous pseudotime-like vectors.

Consumes:
- `matrix`: matrix
- `pseudotime`: cell_vector
- `cell_set`: select

Produces:
- `trend_table`: feature_table [terminal artifact] - Per-feature trend statistics (rho, p, adjusted p).

Promotable outputs: trend_table

Replay equivalence:
- `trend_table`: `exact_canonical_value`

Key parameters:
- `features` (string_vec, default=NULL): Optional feature subset.
- `min_pct_nonzero` (dbl, default=0): Minimum non-zero fraction filter.
- `min_sd` (dbl, default=0): Minimum per-feature standard deviation filter.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.
- `chunk_size` (int, default=128): Chunk size for matrix slicing.

## `trajectory_de`

Title: Trajectory DE

Intent: trajectory, trend, statistics

Description: Lineage-aware feature trend testing against trajectory pseudotime from model_ref.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `de_table`: feature_table [terminal artifact] - Per-lineage feature trend statistics (rho, p, adjusted p).
- `fit_summary`: obs_table [terminal artifact] - Per-lineage input and filtering diagnostics.

Promotable outputs: de_table, fit_summary

Replay equivalence:
- `de_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `feature_set` (string, default=NULL): Optional feature set name from wb_feature_sets() for matrix.
- `features` (string_vec, default=NULL): Optional explicit feature subset (intersected with feature_set when both provided).
- `test` (choice, default=spearman): Statistical test. The current implementation supports spearman.
- `min_pct_nonzero` (dbl, default=0): Minimum non-zero fraction filter.
- `min_sd` (dbl, default=0): Minimum per-feature standard deviation filter.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.
- `chunk_size` (int, default=128): Chunk size for matrix slicing.

## `trajectory_smooth`

Title: Trajectory Feature Smoothing

Intent: trajectory, summary, expression

Description: Summarize per-feature expression along trajectory pseudotime into reusable trend tables.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `trend_table`: obs_table [terminal artifact] - Per-feature binned expression summaries along trajectory pseudotime.
- `fit_summary`: obs_table [terminal artifact] - Per-lineage smoothing diagnostics.

Promotable outputs: trend_table, fit_summary

Replay equivalence:
- `trend_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `feature_set` (string, default=NULL): Optional feature set name from wb_feature_sets() for matrix.
- `features` (string_vec, default=NULL): Optional explicit feature subset (intersected with feature_set when both provided).
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.
- `chunk_size` (int, default=128): Chunk size for matrix slicing.

## `trajectory_branch_compare`

Title: Trajectory Branch Compare

Intent: trajectory, comparison, statistics

Description: Compare two trajectory branches feature-by-feature using explicit pseudotime and branch membership primitives.

Consumes:
- `matrix`: matrix
- `pseudotime`: cell_vector_family
- `branch_membership`: relation_family
- `cell_set`: select

Produces:
- `branch_de_table`: feature_table [terminal artifact] - Per-feature branch comparison statistics and effect sizes.
- `branch_summary`: obs_table [terminal artifact] - Branch-pair cell counts and pseudotime summary diagnostics.

Promotable outputs: branch_de_table, branch_summary

Replay equivalence:
- `branch_de_table`: `exact_canonical_value`
- `branch_summary`: `exact_canonical_value`

Key parameters:
- `branch_a` (string, default=NULL): Branch/lineage key A.
- `branch_b` (string, default=NULL): Branch/lineage key B.
- `feature_set` (string, default=NULL): Optional feature set name from wb_feature_sets() for matrix.
- `features` (string_vec, default=NULL): Optional explicit feature subset (intersected with feature_set when both provided).
- `min_pct` (dbl, default=0): Minimum detection fraction in either branch.
- `p_adjust_method` (string, default=BH): Method passed to p.adjust.

## `trajectory_signature_smooth`

Title: Trajectory Signature Smoothing

Intent: trajectory, summary, signature

Description: Summarize feature-set signature scores along trajectory pseudotime into reusable trend tables.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `signature_table`: obs_table [terminal artifact] - Per-signature binned summaries along trajectory pseudotime.
- `fit_summary`: obs_table [terminal artifact] - Per-lineage signature smoothing diagnostics.

Promotable outputs: signature_table, fit_summary

Replay equivalence:
- `signature_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `feature_set` (string, default=NULL): Required feature set name from wb_feature_sets() for matrix.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `score_method` (choice, default=mean): How to score the feature set within each cell.
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.

## `trajectory_geneset_dynamics`

Title: Trajectory Gene-Set Dynamics

Intent: trajectory, pathway, discovery, signature

Description: Screen all feature sets in a namespace for dynamic behavior along trajectory pseudotime.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `pseudotime`: cell_vector_family
- `cell_set`: select

Produces:
- `signature_table`: obs_table [terminal artifact] - Binned feature-set score curves along trajectory pseudotime.
- `dynamics_table`: obs_table [terminal artifact] - Per-feature-set dynamic metrics and rank.
- `top_sets`: obs_table [terminal artifact] - Top-ranked dynamic feature sets for report-first discovery.
- `driver_table`: obs_table [terminal artifact] - Top dynamic member genes within each screened feature set.
- `driver_curve_table`: obs_table [terminal artifact] - Binned curves for top driver genes within each screened feature set.
- `fit_summary`: obs_table [terminal artifact] - Per-lineage screening diagnostics.

Promotable outputs: signature_table, dynamics_table, top_sets, driver_table, driver_curve_table, fit_summary

Replay equivalence:
- `signature_table`: `exact_canonical_value`
- `dynamics_table`: `exact_canonical_value`
- `top_sets`: `exact_canonical_value`
- `driver_table`: `exact_canonical_value`
- `driver_curve_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `namespace` (string, default=NULL): Feature-set namespace from wb_feature_sets() to screen.
- `feature_sets` (string_vec, default=NULL): Optional feature-set subset within the namespace.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `pseudotime_key` (string, default=NULL): Required key for explicit cell_vector_family pseudotime when multiple keys are present.
- `membership` (cell_ids_or_set, default=NULL): Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
- `score_method` (choice, default=mean): How to score each feature set within each cell.
- `pseudotime_direction` (choice, default=as_is): Use pseudotime as provided or invert it before binning and classification.
- `start_label` (string, default=NULL): Optional biological start label recorded in output metadata.
- `end_label` (string, default=NULL): Optional biological end label recorded in output metadata.
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.
- `min_set_size` (int, default=5): Minimum feature-set size after intersecting with the matrix.
- `max_set_size` (int, default=5000): Maximum feature-set size after intersecting with the matrix.
- `top_n` (int, default=50): Number of top-ranked feature sets retained in top_sets.
- `on_off_min_delta` (dbl, default=0): Minimum absolute late-early delta for turns_on/turns_off classes.
- `monotonic_min_abs_rho` (dbl, default=0.5): Minimum absolute Spearman rho for turns_on/turns_off classes.
- `top_driver_genes` (int, default=5): Number of top member genes retained as curve drivers per feature set.
- `min_amplitude` (dbl, default=0): Minimum curve amplitude required for passes_filters.
- `min_bins_observed` (int, default=5): Minimum retained bins required for passes_filters.
- `min_features_detected` (int, default=1): Minimum detected set members required for passes_filters.
- `min_detected_fraction` (dbl, default=0): Minimum fraction of detected set members required for passes_filters.
- `min_mean_score` (dbl, default=0): Optional minimum mean smoothed score required for passes_filters; use to suppress very low-abundance dynamics.
- `min_max_score` (dbl, default=0): Optional minimum maximum smoothed score required for passes_filters; use to suppress near-zero curves.
- `min_signal_to_noise` (dbl, default=0): Optional minimum amplitude divided by mean bootstrap SE required for passes_filters.
- `low_abundance_max_score` (dbl, default=0.1): Curves with max_score below this value are flagged low_abundance_flag but not filtered unless min_max_score is set.
- `smooth_method` (choice, default=none): Optional smoothing method applied to binned curves before metrics/classes.
- `loess_span` (dbl, default=0.5): Span used when smooth_method='loess'.
- `bootstrap_n` (int, default=0): Bootstrap replicates per bin for confidence bands; 0 disables CIs.
- `bootstrap_seed` (int, default=1): Random seed for bootstrap confidence bands.
- `ci_level` (dbl, default=0.95): Confidence level for bootstrap bands.
- `class_min_amplitude` (dbl, default=0): Minimum amplitude required before assigning non-flat curve classes.
- `n_permutations` (int, default=0): Number of empirical permutations for dynamic-score p-values; 0 disables permutation testing.
- `permutation_seed` (int, default=1): Random seed for empirical dynamic-score permutations.
- `p_adjust_method` (choice, default=BH): Multiple-testing correction method for q_dynamic.

## `trajectory_route_smooth`

Title: Trajectory Route Smoothing

Intent: trajectory, summary, route

Description: Summarize per-feature expression along an explicit route using global pseudotime plus route membership weights.

Consumes:
- `matrix`: matrix
- `pseudotime`: cell_vector
- `branch_membership`: relation_family
- `cell_set`: select

Produces:
- `trend_table`: obs_table [terminal artifact] - Per-feature binned summaries along a selected route.
- `fit_summary`: obs_table [terminal artifact] - Route smoothing diagnostics.

Promotable outputs: trend_table, fit_summary

Replay equivalence:
- `trend_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `route_key` (string, default=NULL): Required route/branch key within branch_membership.
- `feature_set` (string, default=NULL): Optional feature set name from wb_feature_sets() for matrix.
- `features` (string_vec, default=NULL): Optional explicit feature subset (intersected with feature_set when both provided).
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin. Weighted routes currently support mean only.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.
- `weight_mode` (choice, default=probability): Use route probabilities directly or threshold to a binary route membership.
- `prob_min` (dbl, default=0): Minimum route probability required to include a cell.
- `chunk_size` (int, default=128): Feature chunk size for matrix slicing.

## `trajectory_vector_smooth`

Title: Trajectory Signal Smoothing

Intent: trajectory, summary, signal

Description: Summarize cell-level signal families along trajectory pseudotime into reusable trend tables.

Consumes:
- `signal`: cell_vector_family
- `model`: model_ref
- `cell_set`: select

Produces:
- `signal_table`: obs_table [terminal artifact] - Per-signal binned summaries along trajectory pseudotime.
- `fit_summary`: obs_table [terminal artifact] - Per-lineage signal smoothing diagnostics.

Promotable outputs: signal_table, fit_summary

Replay equivalence:
- `signal_table`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.

## `trajectory_signal_dynamics`

Title: Trajectory Signal Dynamics

Intent: trajectory, signal, discovery, dynamics

Description: Rank precomputed cell-level signal families by dynamic behavior along trajectory pseudotime.

Consumes:
- `signal`: cell_vector_family
- `model`: model_ref
- `pseudotime`: cell_vector_family
- `cell_set`: select

Produces:
- `signal_table`: obs_table [terminal artifact] - Binned signal-score curves along trajectory pseudotime.
- `dynamics_table`: obs_table [terminal artifact] - Per-signal dynamic metrics and rank.
- `top_signals`: obs_table [terminal artifact] - Top-ranked dynamic signals for report-first discovery.
- `fit_summary`: obs_table [terminal artifact] - Per-lineage signal dynamics diagnostics.

Promotable outputs: signal_table, dynamics_table, top_signals, fit_summary

Replay equivalence:
- `signal_table`: `exact_canonical_value`
- `dynamics_table`: `exact_canonical_value`
- `top_signals`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `pseudotime_key` (string, default=NULL): Required key for explicit cell_vector_family pseudotime when multiple keys are present.
- `membership` (cell_ids_or_set, default=NULL): Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
- `pseudotime_direction` (choice, default=as_is): Use pseudotime as provided or invert it before binning and classification.
- `start_label` (string, default=NULL): Optional biological start label recorded in output metadata.
- `end_label` (string, default=NULL): Optional biological end label recorded in output metadata.
- `n_bins` (int, default=50): Number of pseudotime bins.
- `summary_fun` (choice, default=mean): Summary statistic across cells within each bin.
- `min_cells_per_bin` (int, default=5): Minimum cells required for an output bin.
- `top_n` (int, default=50): Number of top-ranked signals retained in top_signals.
- `on_off_min_delta` (dbl, default=0): Minimum absolute late-early delta for turns_on/turns_off classes.
- `monotonic_min_abs_rho` (dbl, default=0.5): Minimum absolute Spearman rho for turns_on/turns_off classes.
- `min_amplitude` (dbl, default=0): Minimum curve amplitude required for passes_filters.
- `min_bins_observed` (int, default=5): Minimum retained bins required for passes_filters.
- `smooth_method` (choice, default=none): Optional smoothing method applied to binned curves before metrics/classes.
- `loess_span` (dbl, default=0.5): Span used when smooth_method='loess'.
- `bootstrap_n` (int, default=0): Bootstrap replicates per bin for confidence bands; 0 disables CIs.
- `bootstrap_seed` (int, default=1): Random seed for bootstrap confidence bands.
- `ci_level` (dbl, default=0.95): Confidence level for bootstrap bands.
- `class_min_amplitude` (dbl, default=0): Minimum amplitude required before assigning non-flat curve classes.

## `knn_pseudobulk`

Title: kNN Pseudobulk Around Query Cell(s)

Intent: pseudobulk, neighbors, projection

Description: Find k nearest neighbors in latent space around query cells and aggregate matrix values.

Consumes:
- `matrix`: matrix
- `space`: space
- `cell_set`: select

Produces:
- `pseudobulk_table`: feature_table [terminal artifact] - Feature-level pseudobulk values keyed by query cell.
- `neighbor_distance`: cell_vector_family [terminal artifact] - Neighbor distances per query cell.

Promotable outputs: pseudobulk_table, neighbor_distance

Replay equivalence:
- `pseudobulk_table`: `exact_canonical_value`
- `neighbor_distance`: `exact_canonical_value`

Key parameters:
- `query_cells` (cell_ids_or_set, default=NULL): Query cells: explicit IDs or 'set:<name>'
- `candidate_cells` (cell_ids_or_set, default=NULL): Optional candidate neighbor pool; defaults to all cells.
- `features` (string_vec, default=NULL): Optional feature subset for pseudobulk output.
- `k` (int, default=100): Nearest neighbors per query cell.
- `include_query` (bool, default=FALSE): Include query cells themselves when they are in candidate pool.
- `aggregate` (string, default=sum): Aggregation mode: sum or mean.

## `knn_neighbors`

Title: kNN neighbors around query cell(s)

Intent: neighbors, geometry, projection

Description: Find nearest neighbors in a latent space without requiring matrix aggregation.

Consumes:
- `space`: space
- `cell_set`: select

Produces:
- `neighbors`: obs_table [terminal artifact] - Per-query neighbor table (cell_id, rank, distance).
- `neighbor_distance`: cell_vector_family [terminal artifact] - Neighbor distances per query cell.

Promotable outputs: neighbors, neighbor_distance

Replay equivalence:
- `neighbors`: `exact_canonical_value`
- `neighbor_distance`: `exact_canonical_value`

Key parameters:
- `query_cells` (cell_ids_or_set, default=NULL): Query cells: explicit IDs or 'set:<name>'
- `candidate_cells` (cell_ids_or_set, default=NULL): Optional candidate neighbor pool; defaults to all cells.
- `k` (int, default=100): Nearest neighbors per query cell.
- `include_query` (bool, default=FALSE): Include query cells themselves when they are in candidate pool.

## `slingshot`

Title: Slingshot trajectory

Intent: trajectory

Description: Infer lineage curves and pseudotime from clusters in a 2D space.

Consumes:
- `space`: space
- `plot_space`: space
- `clusters`: cell_vector
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector_family [terminal artifact] - Lineage-specific pseudotime values per cell.
- `curves`: path_2d_family [terminal artifact] - Lineage curve paths in 2D.

Promotable outputs: pseudotime, curves

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `curves`: `exact_canonical_value`

Key parameters:
- `start.clus` (string, default=NULL): Starting cluster id.
- `end.clus` (string_vec, default=NULL): Ending cluster id(s).
- `exclude_clusters` (string_vec, default=): Cluster id(s) to exclude before fitting.
- `stretch` (dbl, default=2): Slingshot curve stretching.
- `reweight` (bool, default=TRUE): Whether to reweight assignments during fitting.

## `slingshot_fit`

Title: Slingshot fit

Intent: trajectory

Description: Fit Slingshot lineages/pseudotime in a chosen fit space (typically latent/PCA).

Consumes:
- `fit_space`: space
- `clusters`: cell_vector
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector_family [terminal artifact] - Lineage-specific pseudotime values per cell (fit space inference).
- `lineage_weights`: cell_vector_family [terminal artifact] - Slingshot lineage membership weights per cell and lineage. These are trajectory membership weights, not pseudotime.
- `model`: model_ref [terminal artifact] - Session-chainable Slingshot fit model (engine='slingshot').

Promotable outputs: pseudotime, lineage_weights, model

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `lineage_weights`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `start.clus` (string, default=NULL): Starting cluster id.
- `end.clus` (string_vec, default=NULL): Ending cluster id(s).
- `include_clusters` (string_vec, default=NULL): Restrict fitting to these cluster id(s).
- `exclude_clusters` (string_vec, default=): Cluster id(s) to exclude before fitting.
- `exclude_cells` (cell_ids, default=NULL): Optional cell IDs to exclude before fitting.
- `stretch` (dbl, default=2): Slingshot curve stretching.
- `reweight` (bool, default=TRUE): Whether to reweight assignments during fitting.
- `shrink` (dbl, default=1): Curve shrinkage toward shared segments.
- `maxit` (int, default=10): Maximum fitting iterations.

## `slingshot_lineage_weights`

Title: Slingshot lineage weights

Intent: trajectory, provenance, backfill

Description: Extract Slingshot lineage membership weights from an existing model_ref without refitting, preserving trajectory_fit_id and lineage mapping.

Consumes:
- `model`: model_ref
- `cell_set`: select

Produces:
- `lineage_weights`: cell_vector_family [terminal artifact] - Slingshot lineage membership weights extracted from an existing model_ref; no trajectory refit is performed.

Promotable outputs: lineage_weights

Replay equivalence:
- `lineage_weights`: `exact_canonical_value`

Key parameters:
- (none)

## `trajectory_segment_join`

Title: Trajectory segment join

Intent: trajectory, provenance, composition

Description: Join ordered generic trajectory segments into an auditable composite pseudotime without merging parent trajectory models.

Consumes:
- `cell_set`: select

Produces:
- `composite_pseudotime_unit_segment`: cell_vector_family [terminal artifact] - Canonical one-row-per-cell composite pseudotime with exact integer segment boundaries.
- `composite_pseudotime_cell_weighted_0_1`: cell_vector_family [terminal artifact] - One-row-per-cell composite pseudotime normalized to [0,1] with segment lengths weighted by segment-local cell counts.
- `segment_local_table`: obs_table [terminal artifact] - One row per cell per parent segment preserving source kind, raw pseudotime, normalized pseudotime, confidence, weight, and segment role.
- `composite_manifest`: obs_table [terminal artifact] - Audit manifest recording parent segment sources, artifacts, fit IDs where available, labels, join policy, overlap counts, and caveats.
- `composite_membership`: cell_vector [terminal artifact] - One-cell assignment to a unique segment or waypoint overlap.

Promotable outputs: composite_pseudotime_unit_segment, composite_pseudotime_cell_weighted_0_1, segment_local_table, composite_manifest, composite_membership

Replay equivalence:
- `composite_pseudotime_unit_segment`: `exact_canonical_value`
- `composite_pseudotime_cell_weighted_0_1`: `exact_canonical_value`
- `segment_local_table`: `exact_canonical_value`
- `composite_manifest`: `exact_canonical_value`
- `composite_membership`: `exact_canonical_value`

Key parameters:
- `segments` (list, default=NULL): Ordered segment specs with source_kind/source_engine, pseudotime ref, lineage key, optional membership/weights/confidence/path refs, labels, and order.
- `composite_id` (string, default=NULL): Optional stable trajectory_composite_id. Generated when omitted.
- `composite_key` (string, default=composite_L1): Key used in the output composite pseudotime cell_vector_family objects.
- `join_policy` (string, default=exact_boundary_collapse): Overlap policy. The current implementation supports exact_boundary_collapse.
- `min_weight` (dbl, default=NULL): Optional minimum lineage weight required for segment-local membership when weights are supplied.
- `allow_legacy` (bool, default=FALSE): Allow missing trajectory_fit_id within a segment with warning. Default rejects legacy ambiguity.

## `trajectory_segment_from_artifacts`

Title: Trajectory fitted-artifact segment

Intent: trajectory, adapter, composition, provenance

Description: Materialize the generic trajectory segment contract from fitted-model trajectory artifacts with fit-family validation.

Consumes:
- `pseudotime`: cell_vector_family
- `model`: model_ref
- `lineage_weights`: cell_vector_family
- `confidence`: cell_vector_family
- `path`: path_2d_family
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector_family [terminal artifact] - Fitted-model segment pseudotime for the selected lineage/key.
- `membership`: cell_vector [terminal artifact] - Cells included in the fitted-model segment.
- `confidence`: cell_vector_family [terminal artifact] - Segment confidence, derived from supplied confidence/lineage weights or defaulting to 1.
- `segment_manifest`: obs_table [terminal artifact] - Audit manifest for the fitted-model segment.

Promotable outputs: pseudotime, membership, confidence, segment_manifest

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `membership`: `exact_canonical_value`
- `confidence`: `exact_canonical_value`
- `segment_manifest`: `exact_canonical_value`

Key parameters:
- `segment_id` (string, default=NULL): Stable segment identifier.
- `segment_order` (dbl, default=1): Order of this fitted segment in a future composite.
- `lineage` (string, default=NULL): Lineage/key to extract from fitted pseudotime and optional weights.
- `membership` (cell_ids_or_set, default=NULL): Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
- `confidence_key` (string, default=NULL): Optional key for confidence cell_vector_family. Defaults to lineage.
- `source_engine` (string, default=NULL): Fitted trajectory engine, usually slingshot, monocle3, or palantir.
- `start_label` (string, default=NULL): Biological start label.
- `end_label` (string, default=NULL): Biological end label.
- `allow_legacy` (bool, default=FALSE): Allow missing trajectory_fit_id with warning. Default rejects legacy ambiguity.

## `trajectory_space_path_segment`

Title: Trajectory space-path segment

Intent: trajectory, bridge, composition, geometry

Description: Convert space_path_score output into a generic trajectory segment using path-progress pseudotime and transparent distance-based membership.

Consumes:
- `path_scores`: cell_vector_family
- `display_path`: path_2d_family
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector_family [terminal artifact] - Bridge pseudotime from path arclength progress in [0,1].
- `membership`: cell_vector [terminal artifact] - Cells passing the transparent distance-to-path bridge membership rule.
- `confidence`: cell_vector_family [terminal artifact] - Distance-derived confidence for included bridge cells.
- `segment_manifest`: obs_table [terminal artifact] - Audit manifest for the space-path bridge segment.
- `display_endpoint_qc`: obs_table [terminal artifact] - Endpoint-distance QC for an optional display_path against declared start/end endpoint descriptors.

Promotable outputs: pseudotime, membership, confidence, segment_manifest, display_endpoint_qc

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `membership`: `exact_canonical_value`
- `confidence`: `exact_canonical_value`
- `segment_manifest`: `exact_canonical_value`
- `display_endpoint_qc`: `exact_canonical_value`

Key parameters:
- `segment_id` (string, default=NULL): Stable segment identifier.
- `segment_order` (dbl, default=1): Order of this bridge segment in a future composite.
- `score_prefix` (string, default=NULL): Optional prefix used by space_path_score keys.
- `candidate_cells` (cell_ids_or_set, default=NULL): Optional candidate universe before distance thresholding.
- `distance_threshold` (dbl, default=NULL): Include cells with distance_to_path <= threshold.
- `distance_quantile` (dbl, default=NULL): Alternative threshold: include cells up to this distance quantile.
- `start_label` (string, default=NULL): Biological start label.
- `end_label` (string, default=NULL): Biological end label.
- `display_lineage` (string, default=NULL): Optional key/lineage to validate in display_path. Defaults to the only key if display_path has one.
- `display_space_id` (string, default=NULL): 2D display space used for endpoint cell-set coordinate QC.
- `start_endpoint` (list_or_cell_set, default=NULL): Optional start endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC.
- `end_endpoint` (list_or_cell_set, default=NULL): Optional end endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC.
- `start_cell_set` (cell_set, default=NULL): Convenience start endpoint cell set for display-path QC.
- `end_cell_set` (cell_set, default=NULL): Convenience end endpoint cell set for display-path QC.
- `endpoint_summary_method` (choice, default=centroid): How endpoint cell sets are summarized in display space for QC.
- `endpoint_max_distance` (dbl, default=NULL): Optional absolute maximum endpoint distance before QC fails.
- `endpoint_qc_action` (choice, default=fail): Action when display-path endpoint QC detects a large mismatch.
- `pseudotime_key` (string, default=NULL): Key for emitted bridge pseudotime. Defaults to segment_id.
- `confidence_key` (string, default=NULL): Key for emitted bridge confidence. Defaults to segment_id.

## `trajectory_segment_path_join`

Title: Trajectory segment path join

Intent: trajectory, visualization, provenance, composition

Description: Join ordered parent path_2d_family segments into a derived composite display curve without merging parent trajectory models.

Consumes:
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Derived display-only composite path suitable for UMAP overlay; not a merged fitted trajectory model.
- `path_manifest`: obs_table [terminal artifact] - Audit manifest recording parent path artifacts, segment order, point boundaries, and caveats.
- `endpoint_qc`: obs_table [terminal artifact] - Endpoint-distance QC for joined display paths with declared endpoint descriptors.

Promotable outputs: curves, path_manifest, endpoint_qc

Replay equivalence:
- `curves`: `exact_canonical_value`
- `path_manifest`: `exact_canonical_value`
- `endpoint_qc`: `exact_canonical_value`

Key parameters:
- `paths` (list, default=NULL): Ordered path segment specs with path ref, lineage key, segment ID, labels, and order.
- `composite_id` (string, default=NULL): Optional trajectory_composite_id shared with a segmented pseudotime join.
- `composite_key` (string, default=composite_path): Key used in the output composite path_2d_family.
- `display_space_id` (string, default=NULL): 2D display space used for endpoint cell-set coordinate QC when path segment specs declare endpoint cell sets.
- `endpoint_summary_method` (choice, default=centroid): How endpoint cell sets are summarized in display space for QC.
- `endpoint_max_distance` (dbl, default=NULL): Optional absolute maximum endpoint distance before QC fails.
- `endpoint_qc_action` (choice, default=fail): Action when display-path endpoint QC detects a large mismatch.
- `allow_legacy` (bool, default=FALSE): Allow missing trajectory_fit_id on parent paths with warning.

## `slingshot_project`

Title: Slingshot project curves

Intent: trajectory

Description: Project a fitted Slingshot model into a 2D display space (e.g. UMAP).

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Projected Slingshot lineage curves in the chosen 2D display space.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `stretch` (dbl, default=NULL): Optional override of stretch during embedding.
- `shrink` (dbl, default=NULL): Optional override of shrink during embedding.
- `approx_points` (int, default=200): Target max curve points per lineage for display (0/NULL = no compaction).

## `monocle3_fit`

Title: Monocle3 fit (hybrid space)

Intent: trajectory

Description: Fit monocle3 graph/pseudotime using a scworkbench latent space injected into monocle3's UMAP slot.

Consumes:
- `fit_space`: space
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector [terminal artifact] - Rooted global pseudotime per cell from monocle3.
- `branch_membership`: relation_family [terminal artifact] - Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in the current implementation).
- `model`: model_ref [terminal artifact] - Session-chainable monocle3 CDS model (engine='monocle3').

Promotable outputs: pseudotime, branch_membership, model

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `branch_membership`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `dims` (string_vec, default=NULL): Optional fit-space dimensions to use (e.g. 1:20 as explicit integer vector).
- `root_cells` (cell_ids, default=NULL): Root cell IDs (exactly one of root_cells or root_pr_nodes).
- `root_pr_nodes` (string_vec, default=NULL): Principal graph root node IDs (advanced; exactly one of root_cells or root_pr_nodes).
- `k` (int, default=20): kNN size for monocle3 clustering.
- `cluster_method` (choice, default=leiden): Monocle3 clustering backend.
- `num_iter` (int, default=2): Monocle3 clustering iterations.
- `partition_qval` (dbl, default=0.05): Partition significance threshold.
- `weight` (bool, default=FALSE): Use weighted nearest-neighbor graph for monocle3 clustering.
- `resolution` (dbl, default=NULL): Optional clustering resolution (NULL lets monocle3 choose).
- `random_seed` (int, default=42): Random seed for clustering.
- `use_partition` (bool, default=FALSE): Learn graph per partition. FALSE is recommended for current tree semantics.
- `close_loop` (bool, default=FALSE): Allow loop closure in graph learning. FALSE is required for tree-derived lineages.
- `verbose` (bool, default=FALSE): Verbose monocle3 output.

## `monocle3_project`

Title: Monocle3 project curves

Intent: trajectory

Description: Project a fitted monocle3 trajectory graph into a 2D display space.

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Projected monocle3 root-qualified lineage curves in the chosen 2D display space.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `approx_points` (int, default=200): Target max curve points per lineage for display (0/NULL = no compaction).

## `peakvi_fit`

Title: PeakVI fit (pybench)

Intent: latent, model, python

Description: Train a PeakVI model on a matrix via the pybench Python runtime and emit a latent space plus model reference.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: model] - PeakVI latent space written into the bundle spaces registry.
- `model`: model_ref [terminal artifact] - Serialized PeakVI Python model payload (engine='peakvi').

Promotable outputs: model

Replay equivalence:
- `space`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `n_latent` (int, default=20): Target latent dimensionality for the emitted PeakVI space.
- `n_layers` (int, default=2): Number of hidden layers passed to the PeakVI model constructor.
- `n_hidden` (int, default=256): Hidden width passed to the PeakVI model constructor.
- `dropout` (number, default=0.2): Dropout rate passed to the PeakVI model constructor.
- `batch_key` (string, default=NULL): Optional observation field used as the PeakVI batch covariate.
- `max_epochs` (int, default=500): Maximum training epochs passed through to scvi-tools.
- `lr` (number, default=0.001): Optional learning rate passed through in train plan_kwargs.
- `early_stopping` (bool, default=TRUE): If TRUE, enable scvi-tools early stopping during PeakVI training.
- `seed` (int, default=1): Random seed for PeakVI training.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed training in scvi-tools.
- `space_id_out` (string, default=peakvi_space): Space id to write for the learned PeakVI latent embedding.

## `scvi_train`

Title: scVI train (pybench)

Intent: latent, model, python, rna, counts

Description: Train an RNA scVI model on a raw/count-like matrix via the pybench Python runtime and emit a latent space, model reference, and fit summary.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: model, fit_summary] - scVI latent space written into the bundle spaces registry.
- `model`: model_ref [terminal artifact] - Serialized scVI Python model payload (engine='scvi').
- `fit_summary`: obs_table [terminal artifact] - Training summary, parameter, runtime, and metric table emitted by pybench.

Promotable outputs: model, fit_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `model`: `loadable_reference`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `n_latent` (int, default=30): Target latent dimensionality for the emitted scVI space.
- `n_hidden` (int, default=128): Hidden width passed to the scVI model constructor.
- `n_layers` (int, default=2): Number of hidden layers passed to the scVI model constructor.
- `dropout` (number, default=0.1): Dropout rate passed to the scVI model constructor.
- `batch_key` (string, default=NULL): Optional cell metadata field used as the scVI batch covariate.
- `categorical_covariates` (string_array, default=NULL): Optional categorical cell metadata covariates passed to scVI setup_anndata.
- `continuous_covariates` (string_array, default=NULL): Optional continuous cell metadata covariates passed to scVI setup_anndata.
- `max_epochs` (int, default=NULL): Optional maximum training epochs passed through to scvi-tools.
- `early_stopping` (bool, default=TRUE): If TRUE, enable scvi-tools early stopping during scVI training.
- `seed` (int, default=1): Random seed for scVI training.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed training in scvi-tools.
- `output_space_id` (string, default=rna.scvi): Space id to write for the learned scVI latent embedding.
- `model_artifact_id` (string, default=NULL): Optional preregistered model artifact id. NULL lets scworkbench assign one.
- `overwrite` (bool, default=FALSE): If TRUE, allow replacing an existing output_space_id.
- `allow_non_counts` (bool, default=FALSE): If TRUE, bypass raw/count-like matrix checks. Use only for intentional expert overrides.

## `peakvi_project`

Title: PeakVI project (pybench)

Intent: projection, latent, python

Description: Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: fit_summary] - Projected PeakVI latent space written into the bundle spaces registry.
- `fit_summary`: obs_table [terminal artifact] - Projection receipt and output-space summary.

Promotable outputs: fit_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `batch_key` (string, default=NULL): Optional observation field used as the PeakVI batch covariate during projection.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed model loading/projection in scvi-tools.
- `space_id_out` (string, default=peakvi_project_space): Space id to write for the projected PeakVI latent embedding.

## `space_path_define`

Title: Define analytical space path

Intent: trajectory, geometry, path

Description: Contract scaffold for checkpoint-anchored path construction in a named analytical space.

Consumes:
- `space`: space
- `cell_set`: select

Produces:
- `path`: space_path_family [terminal artifact] - Analytical path in the original latent space.

Promotable outputs: path

Replay equivalence:
- `path`: `exact_canonical_value`

Key parameters:
- `checkpoint_sets` (string_vec, default=NULL): Ordered checkpoint cell-set refs that anchor the path definition.
- `fit_mode` (choice, default=linear): Path fitting mode. The current implementation supports linear and a conservative manifold smoothing mode.
- `checkpoint_summary` (choice, default=centroid): Checkpoint summarization rule used to derive anchors from checkpoint cells.
- `n_path_points` (int, default=NULL): Optional explicit number of fitted path points.
- `smooth_k` (int, default=30): For fit_mode='manifold_smooth', number of nearest cells used per provisional path point.
- `smooth_n_iter` (int, default=2): For fit_mode='manifold_smooth', number of refinement passes.
- `smooth_weight` (choice, default=inverse_distance): For fit_mode='manifold_smooth', distance-weighting rule for local cell pull.
- `path_id_out` (string, default=space_path): Path id to record for the emitted analytical path.

## `space_path_score`

Title: Score cells against analytical path

Intent: trajectory, geometry, path

Description: Contract scaffold for path-relative scoring in a named analytical space.

Consumes:
- `space`: space
- `path`: space_path_family
- `cell_set`: select

Produces:
- `path_scores`: cell_vector_family [terminal artifact] - Per-cell path-relative scores such as progress and distance.
- `fit_summary`: obs_table [terminal artifact] - Compact path-level scoring diagnostics.

Promotable outputs: path_scores, fit_summary

Replay equivalence:
- `path_scores`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `score_mode` (choice, default=orthogonal_projection): Scoring mode. The current implementation standardizes on orthogonal projection semantics.
- `distance_metric` (choice, default=euclidean): Distance metric used for path-relative scoring.
- `score_prefix` (string, default=NULL): Optional prefix for emitted score-family keys.

## `space_path_project_2d`

Title: Project analytical path into 2D

Intent: trajectory, geometry, path, display

Description: Contract scaffold for projecting an analytical path into a drawable 2D path family.

Consumes:
- `path`: space_path_family
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Approximate 2D rendering of the analytical path.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `project_mode` (choice, default=local_interpolation): Projection mode used to approximate the analytical path in a 2D plot space.
- `approx_points` (int, default=NULL): Optional target point count for display compaction.

## `palantir_fit`

Title: Palantir fit (pybench)

Intent: trajectory

Description: Run Palantir pseudotime/branch probabilities on a scworkbench latent space via the pybench Python runtime.

Consumes:
- `fit_space`: space
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector [terminal artifact] - Palantir pseudotime (single-root, global).
- `branch_membership`: relation_family [terminal artifact] - Palantir branch probabilities as cell-to-branch relations (`branch:*` keys; weights are probabilities).
- `branch_summary`: obs_table [terminal artifact] - Palantir branch probability summary table.
- `entropy`: cell_vector [terminal artifact] - Palantir entropy per cell.
- `model`: model_ref [terminal artifact] - Palantir Python model payload (engine='palantir').

Promotable outputs: pseudotime, branch_membership, branch_summary, entropy, model

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `branch_membership`: `exact_canonical_value`
- `branch_summary`: `exact_canonical_value`
- `entropy`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `root_cell` (string, default=NULL): Single Palantir early/root cell ID (Palantir-native single-root semantics).
- `terminal_cells` (cell_ids, default=NULL): Optional explicit terminal cell IDs passed to Palantir as terminal states (recommended for branch probabilities).
- `dims` (string_vec, default=NULL): Optional fit-space dimensions to use (for example 1:20 as explicit integer vector).
- `knn` (int, default=30): kNN size for Palantir diffusion graph and pseudotime.
- `n_diffusion_components` (int, default=10): Number of diffusion components for Palantir.
- `n_waypoints` (int, default=300): Number of Palantir waypoints.
- `use_early_cell_as_start` (bool, default=TRUE): Pass through to Palantir; if TRUE, force the provided early/root cell to be used as trajectory start.
- `seed` (int, default=20): Random seed for Palantir stochastic steps.

## `palantir_project`

Title: Palantir project trajectories

Intent: trajectory

Description: Project Palantir branch trajectories into a 2D display space using Palantir-style mellon interpolation from the fitted Palantir model.

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Palantir-style smoothed branch trajectories projected into the chosen 2D display space.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `prob_min` (dbl, default=0.05): Minimum branch probability mask threshold for branch trajectory interpolation.
- `smoothness` (dbl, default=1): Palantir-style mellon trajectory smoothing multiplier (higher = smoother).
- `min_cells_per_branch` (int, default=50): Minimum eligible cells required to derive a branch trajectory.
- `approx_points` (int, default=200): Number of trajectory sample points per branch (curve resolution).

