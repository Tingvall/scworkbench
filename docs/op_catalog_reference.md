# scworkbench Operation Catalog

<!-- Generated from wb_op_catalog_semantic(); do not edit op entries by hand. -->

Generated at: 2026-05-19T13:40:27+0200

Operation count: 38

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
- `clusters`: cell_vector - Cluster label per cell (categorical cell vector).

Promotable outputs: clusters

Key parameters:
- `dims` (int_range, default=1:30): Which dimensions of the space to use (1-indexed).
- `k` (int, default=30): Number of neighbors for kNN graph.
- `resolution` (dbl, default=1): Leiden resolution parameter.
- `seed` (int, default=1): Random seed.

## `umap_fit`

Title: UMAP fit (train model)

Intent: umap, fit

Description: Fit a UMAP model on a space and store it for future projection.

Consumes:
- `space`: space
- `cell_set`: select

Produces:
- `model`: model_ref - Reference to the fitted UMAP model.
- `space_2d`: space_2d - The fitted 2D embedding space id.

Promotable outputs: space_2d, model

Key parameters:
- `dims` (int_range, default=NULL): Dims to use (e.g. 2:30).
- `overwrite` (bool, default=TRUE): Overwrite existing model/coords.

## `umap_transform`

Title: UMAP transform (project cells)

Intent: projection, umap

Description: Project cells into an existing UMAP using a stored model.

Consumes:
- `model`: model_ref
- `in_space`: space
- `cell_set`: select

Produces:
- `space_2d`: space_2d - Projected x/y in the target UMAP space.

Promotable outputs: space_2d

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
- `module_scores`: cell_vector_family - Per-cell module scores for one or more signatures.

Promotable outputs: module_scores

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
- `signature_scores`: cell_vector_family - Per-cell UCell scores for one or more signatures.
- `signature_summary`: obs_table - Per-signature scoring summary and feature-match diagnostics.

Promotable outputs: signature_scores, signature_summary

Key parameters:
- `features` (string_vec_or_list, default=NULL): Signature feature IDs: character vector or list of vectors.
- `name` (string, default=Signature): Prefix for signature names when features are unnamed.
- `max_rank` (int, default=1500): Maximum rank considered by UCell.
- `ncores` (int, default=1): Number of worker processes requested by UCell.
- `parallel_backend` (choice, default=auto): Execution backend for UCell. Use 'serial' to avoid socket-based parallel backends on constrained systems.
- `chunk_size` (int, default=NULL): Reserved chunk size hint for future engine-owned cell-axis chunking; currently ignored.
- `missing_features_policy` (choice, default=drop): How to handle signature features missing from the matrix.

## `cell_vector_family_reduce`

Title: Reduce Cell Vector Family

Intent: label, reduce, signal

Description: Compress a cell_vector_family into one categorical cell_vector using explicit reduction and abstention rules.

Consumes:
- `signal`: cell_vector_family
- `cell_set`: select

Produces:
- `label`: cell_vector - Per-cell categorical labels after reducing the signal family.
- `top_score`: cell_vector - Winning score for each cell.
- `runner_up_score`: cell_vector - Second-best score for each cell.
- `score_margin`: cell_vector - Winning minus runner-up score for each cell.
- `abstain_reason`: cell_vector - Per-cell abstention reason (`none`, `tie`, `min_score`, `min_margin`).
- `decision_table`: obs_table - Per-cell reduction diagnostics including label, scores, margin, and abstention reason.
- `label_summary`: obs_table - Per-label counts and score summaries after reduction.

Promotable outputs: label, top_score, runner_up_score, score_margin, abstain_reason, decision_table, label_summary

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
- `calibrated_signal`: cell_vector_family - Calibrated per-cell values for each key in the signal family.
- `calibration_summary`: obs_table - Per-key calibration statistics for raw and calibrated values.

Promotable outputs: calibrated_signal, calibration_summary

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
- `key_summary`: obs_table - Per-key QC summaries including score distribution, finite coverage, and winner frequencies.
- `pairwise_summary`: obs_table - Pairwise key relationships including overlap counts and correlations.
- `group_summary`: obs_table - Per-group per-key QC summaries when an optional grouping vector is supplied.

Promotable outputs: key_summary, pairwise_summary, group_summary

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `correlation_methods` (string_vec, default=pearson|spearman): Pairwise correlation methods to compute between keys.
- `tie_tol` (dbl, default=1e-08): Tolerance used when counting tied top-key winners.

## `chromvar`

Title: chromVAR deviations

Intent: atac, motif, signature, score

Description: Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `deviation_z`: cell_vector_family - Per-cell chromVAR z-scores keyed by motif.
- `deviation_raw`: cell_vector_family - Per-cell raw chromVAR deviations keyed by motif.
- `motif_summary`: obs_table - Per-motif chromVAR summary statistics.

Promotable outputs: deviation_z, deviation_raw, motif_summary

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
- `de_table`: feature_table - Feature-level DE statistics table.

Promotable outputs: de_table

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
- `markers`: feature_table - Cluster-marker table with per-feature statistics.

Promotable outputs: markers

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
- `pathways`: obs_table - Pathway enrichment statistics for one namespace.

Promotable outputs: pathways

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

## `cell_suffix_label`

Title: Cell Labels From ID Suffix

Intent: annotation, metadata

Description: Build a categorical cell vector by parsing cell_id suffix tokens.

Consumes:
- `cell_set`: select

Produces:
- `labels`: cell_vector - Categorical label per cell from suffix parsing.
- `label_table`: obs_table - Per-cell suffix/label table.

Promotable outputs: labels, label_table

Key parameters:
- `sep` (string, default=-): Separator used in cell IDs before suffix token.
- `mapping` (string_vec, default=NULL): Optional named mapping suffix->label.
- `default_label` (string, default=UNKNOWN): Fallback label for unmapped suffixes.

## `cell_vector_assoc`

Title: Cell Vector Association

Intent: statistics, association, confounding

Description: Test whether a continuous cell-level signal differs across groups defined by a categorical cell-level vector.

Consumes:
- `vector_cont`: cell_vector - Examples: pseudotime, module score, gene-program score.
- `vector_group`: cell_vector - Examples: cluster labels, cell type labels, condition labels.
- `cell_set`: select

Produces:
- `assoc_summary`: feature_table - Omnibus association test summary (Kruskal/ANOVA).
- `group_stats`: obs_table - Per-group descriptive statistics.

Promotable outputs: assoc_summary, group_stats

Key parameters:
- `min_n_per_group` (int, default=3): Minimum cells per group.

## `cell_vector_compare`

Title: Cell Vector Comparison

Intent: statistics, comparison, signal

Description: Compare two cell-level signals on their shared cell universe in raw or rank space.

Consumes:
- `a`: cell_vector - Continuous or rankable numeric signal per cell.
- `b`: cell_vector - Continuous or rankable numeric signal per cell.
- `cell_set`: select

Produces:
- `summary`: obs_table - One-row comparison summary with concordance and delta metrics.
- `comparison`: obs_table - Per-cell comparison table with original values, compared values, and deltas.

Promotable outputs: summary, comparison

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
- `trend_table`: feature_table - Per-feature trend statistics (rho, p, adjusted p).

Promotable outputs: trend_table

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
- `de_table`: feature_table - Per-lineage feature trend statistics (rho, p, adjusted p).
- `fit_summary`: obs_table - Per-lineage input and filtering diagnostics.

Promotable outputs: de_table, fit_summary

Key parameters:
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
- `feature_set` (string, default=NULL): Optional feature set name from wb_feature_sets() for matrix.
- `features` (string_vec, default=NULL): Optional explicit feature subset (intersected with feature_set when both provided).
- `test` (choice, default=spearman): Statistical test. v1 supports spearman.
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
- `trend_table`: obs_table - Per-feature binned expression summaries along trajectory pseudotime.
- `fit_summary`: obs_table - Per-lineage smoothing diagnostics.

Promotable outputs: trend_table, fit_summary

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
- `branch_de_table`: feature_table - Per-feature branch comparison statistics and effect sizes.
- `branch_summary`: obs_table - Branch-pair cell counts and pseudotime summary diagnostics.

Promotable outputs: branch_de_table, branch_summary

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
- `signature_table`: obs_table - Per-signature binned summaries along trajectory pseudotime.
- `fit_summary`: obs_table - Per-lineage signature smoothing diagnostics.

Promotable outputs: signature_table, fit_summary

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
- `cell_set`: select

Produces:
- `signature_table`: obs_table - Binned feature-set score curves along trajectory pseudotime.
- `dynamics_table`: obs_table - Per-feature-set dynamic metrics and rank.
- `top_sets`: obs_table - Top-ranked dynamic feature sets for report-first discovery.
- `driver_table`: obs_table - Top dynamic member genes within each screened feature set.
- `driver_curve_table`: obs_table - Binned curves for top driver genes within each screened feature set.
- `fit_summary`: obs_table - Per-lineage screening diagnostics.

Promotable outputs: signature_table, dynamics_table, top_sets, driver_table, driver_curve_table, fit_summary

Key parameters:
- `namespace` (string, default=NULL): Feature-set namespace from wb_feature_sets() to screen.
- `feature_sets` (string_vec, default=NULL): Optional feature-set subset within the namespace.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
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
- `smooth_method` (choice, default=none): Optional smoothing method applied to binned curves before metrics/classes.
- `loess_span` (dbl, default=0.5): Span used when smooth_method='loess'.
- `bootstrap_n` (int, default=0): Bootstrap replicates per bin for confidence bands; 0 disables CIs.
- `bootstrap_seed` (int, default=1): Random seed for bootstrap confidence bands.
- `ci_level` (dbl, default=0.95): Confidence level for bootstrap bands.
- `class_min_amplitude` (dbl, default=0): Minimum amplitude required before assigning non-flat curve classes.

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
- `trend_table`: obs_table - Per-feature binned summaries along a selected route.
- `fit_summary`: obs_table - Route smoothing diagnostics.

Promotable outputs: trend_table, fit_summary

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
- `signal_table`: obs_table - Per-signal binned summaries along trajectory pseudotime.
- `fit_summary`: obs_table - Per-lineage signal smoothing diagnostics.

Promotable outputs: signal_table, fit_summary

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
- `cell_set`: select

Produces:
- `signal_table`: obs_table - Binned signal-score curves along trajectory pseudotime.
- `dynamics_table`: obs_table - Per-signal dynamic metrics and rank.
- `top_signals`: obs_table - Top-ranked dynamic signals for report-first discovery.
- `fit_summary`: obs_table - Per-lineage signal dynamics diagnostics.

Promotable outputs: signal_table, dynamics_table, top_signals, fit_summary

Key parameters:
- `signal_keys` (string_vec, default=NULL): Optional signal-key subset within the cell_vector_family.
- `lineage` (string_vec, default=NULL): Optional lineage key subset.
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
- `pseudobulk_table`: feature_table - Feature-level pseudobulk values keyed by query cell.
- `neighbor_distance`: cell_vector_family - Neighbor distances per query cell.

Promotable outputs: pseudobulk_table, neighbor_distance

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
- `neighbors`: obs_table - Per-query neighbor table (cell_id, rank, distance).
- `neighbor_distance`: cell_vector_family - Neighbor distances per query cell.

Promotable outputs: neighbors, neighbor_distance

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
- `pseudotime`: cell_vector_family - Lineage-specific pseudotime values per cell.
- `curves`: path_2d_family - Lineage curve paths in 2D.

Promotable outputs: pseudotime, curves

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
- `pseudotime`: cell_vector_family - Lineage-specific pseudotime values per cell (fit space inference).
- `model`: model_ref - Session-chainable Slingshot fit model (engine='slingshot').

Promotable outputs: pseudotime, model

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

## `slingshot_project`

Title: Slingshot project curves

Intent: trajectory

Description: Project a fitted Slingshot model into a 2D display space (e.g. UMAP).

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family - Projected Slingshot lineage curves in the chosen 2D display space.

Promotable outputs: curves

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
- `pseudotime`: cell_vector - Rooted global pseudotime per cell from monocle3.
- `branch_membership`: relation_family - Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in v1).
- `model`: model_ref - Session-chainable monocle3 CDS model (engine='monocle3').

Promotable outputs: pseudotime, branch_membership, model

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
- `use_partition` (bool, default=FALSE): Learn graph per partition. FALSE is recommended for v1 tree semantics.
- `close_loop` (bool, default=FALSE): Allow loop closure in graph learning. FALSE required for v1 tree-derived lineages.
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
- `curves`: path_2d_family - Projected monocle3 root-qualified lineage curves in the chosen 2D display space.

Promotable outputs: curves

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
- `space`: space - PeakVI latent space written into the bundle spaces registry.
- `model`: model_ref - Serialized PeakVI Python model payload (engine='peakvi').

Promotable outputs: model

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

## `peakvi_project`

Title: PeakVI project (pybench)

Intent: projection, latent, python

Description: Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `space`: space - Projected PeakVI latent space written into the bundle spaces registry.

Promotable outputs: (none)

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
- `path`: space_path_family - Analytical path in the original latent space.

Promotable outputs: path

Key parameters:
- `checkpoint_sets` (string_vec, default=NULL): Ordered checkpoint cell-set refs that anchor the path definition.
- `fit_mode` (choice, default=linear): Path fitting mode. V1 supports linear and a first conservative manifold smoothing mode.
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
- `path_scores`: cell_vector_family - Per-cell path-relative scores such as progress and distance.
- `fit_summary`: obs_table - Compact path-level scoring diagnostics.

Promotable outputs: path_scores, fit_summary

Key parameters:
- `score_mode` (choice, default=orthogonal_projection): Scoring mode. V1 scaffolding standardizes on orthogonal projection semantics.
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
- `curves`: path_2d_family - Approximate 2D rendering of the analytical path.

Promotable outputs: curves

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
- `pseudotime`: cell_vector - Palantir pseudotime (single-root, global).
- `branch_membership`: relation_family - Palantir branch probabilities as cell-to-branch relations (`branch:*` keys; weights are probabilities).
- `branch_summary`: obs_table - Palantir branch probability summary table.
- `entropy`: cell_vector - Palantir entropy per cell.
- `model`: model_ref - Palantir Python model payload (engine='palantir').

Promotable outputs: pseudotime, branch_membership, branch_summary, entropy, model

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
- `curves`: path_2d_family - Palantir-style smoothed branch trajectories projected into the chosen 2D display space.

Promotable outputs: curves

Key parameters:
- `prob_min` (dbl, default=0.05): Minimum branch probability mask threshold for branch trajectory interpolation.
- `smoothness` (dbl, default=1): Palantir-style mellon trajectory smoothing multiplier (higher = smoother).
- `min_cells_per_branch` (int, default=50): Minimum eligible cells required to derive a branch trajectory.
- `approx_points` (int, default=200): Number of trajectory sample points per branch (curve resolution).

