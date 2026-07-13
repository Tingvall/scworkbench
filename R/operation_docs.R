# Generated source-level Roxygen adjunct for the retained public operation surface.
# Detailed typed input/output metadata remains in wb_op_interface() and the op catalog.

#' @name wb_op_addmodulescore
#' @aliases wb_op_addmodulescore
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param pool Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param nbin Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ctrl Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param name Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_catalog_semantic
#' @aliases wb_op_catalog_semantic
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_suffix_label
#' @aliases wb_op_cell_suffix_label
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param sep Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param mapping Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param default_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_assoc
#' @aliases wb_op_cell_vector_assoc
#' @param vector_cont Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param vector_group Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_n_per_group Minimum threshold controlling filtering or eligibility for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_compare
#' @aliases wb_op_cell_vector_compare
#' @param a Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param b Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param compare_space Comparison scale, for example raw values or ranks.
#' @param ties_method Named computational method; supported values are validated by the operation.
#' @param signal_a Optional provenance label for the first compared signal.
#' @param signal_b Optional provenance label for the second compared signal.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_family_calibrate
#' @aliases wb_op_cell_vector_family_calibrate
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param method Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param center Logical control flag for this operation.
#' @param scale Logical control flag for this operation.
#' @param ties_method Named computational method; supported values are validated by the operation.
#' @param na_rm Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_family_graph_smooth
#' @aliases wb_op_cell_vector_family_graph_smooth
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param space_id Registered coordinate-space identifier.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param k Number of nearest neighbors.
#' @param alpha Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param distance_metric Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param query_chunk_size Maximum query-cell chunk used during nearest-neighbor processing.
#' @param include_self Logical control flag for this operation.
#' @param na_policy Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param source_signal_artifact_id Identifier or key interpreted by this operation according to its interface contract.
#' @param source_run_id Identifier or key interpreted by this operation according to its interface contract.
#' @param source_snapshot_id Identifier or key interpreted by this operation according to its interface contract.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_family_qc
#' @aliases wb_op_cell_vector_family_qc
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param grouping Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param correlation_methods Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param tie_tol Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_family_reduce
#' @aliases wb_op_cell_vector_family_reduce
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param rule Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_score Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_margin Minimum threshold controlling filtering or eligibility for this operation.
#' @param unknown_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ties Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param tie_tol Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cell_vector_winners
#' @aliases wb_op_cell_vector_winners
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param min_winners Minimum threshold controlling filtering or eligibility for this operation.
#' @param tie_method Named computational method; supported values are validated by the operation.
#' @param source_score_artifact_id Identifier or key interpreted by this operation according to its interface contract.
#' @param source_run_id Identifier or key interpreted by this operation according to its interface contract.
#' @param source_snapshot_id Identifier or key interpreted by this operation according to its interface contract.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_all
#' @aliases wb_op_cells_all
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_counts_by
#' @aliases wb_op_cells_counts_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_filter
#' @aliases wb_op_cells_filter
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param predicate Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param na_value Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_in_dataset
#' @aliases wb_op_cells_in_dataset
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param dataset_id Identifier or key interpreted by this operation according to its interface contract.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_intersect
#' @aliases wb_op_cells_intersect
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_order_like
#' @aliases wb_op_cells_order_like
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_sample
#' @aliases wb_op_cells_sample
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param n Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param replace Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_setdiff
#' @aliases wb_op_cells_setdiff
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param a Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param b Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_split_by
#' @aliases wb_op_cells_split_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_top_n_by
#' @aliases wb_op_cells_top_n_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_cells_union
#' @aliases wb_op_cells_union
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_chromvar
#' @aliases wb_op_chromvar
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param motif_library Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param motifs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param motif_match_set Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_motif_peaks Minimum threshold controlling filtering or eligibility for this operation.
#' @param max_motif_peaks Maximum threshold controlling filtering or eligibility for this operation.
#' @param motif_p_cutoff Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param motif_w Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seqlevels_mode Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seqlevels_include Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seqlevels_exclude Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param background_iterations Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param background_w Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param background_bs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_de_wilcox
#' @aliases wb_op_de_wilcox
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param cells_a Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells_b Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param min_pct Minimum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_avg_by
#' @aliases wb_op_expr_avg_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_frac_nonzero_by
#' @aliases wb_op_expr_frac_nonzero_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_pseudobulk_by
#' @aliases wb_op_expr_pseudobulk_by
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param by Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param drop_na Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_slice
#' @aliases wb_op_expr_slice
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_vector
#' @aliases wb_op_expr_vector
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param feature_id Single feature identifier in the selected matrix.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_expr_zscore_by_feature
#' @aliases wb_op_expr_zscore_by_feature
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param center Logical control flag for this operation.
#' @param scale Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_feature_set_import
#' @aliases wb_op_feature_set_import
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param source_path Input file path for a feature-set import.
#' @param source_format Declared source format for a feature-set import.
#' @param table Optional in-memory source table for a feature-set import.
#' @param sets Optional in-memory named gene-set list for import.
#' @param namespace Feature-set namespace registered for the selected matrix and organism.
#' @param collection Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param subcollection Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param species Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param organism Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param gene_id_type Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param set_id_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param set_name_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param gene_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param description_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param split_by_collection Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param overwrite Whether an existing output with the same identifier may be replaced.
#' @param strict Whether invalid or unmatched input should fail rather than be reported.
#' @param created_by Optional actor label recorded in import provenance.
#' @param source_id Identifier or key interpreted by this operation according to its interface contract.
#' @param source_version Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param origin Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param is_readonly Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_feature_set_overlap_qc
#' @aliases wb_op_feature_set_overlap_qc
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param namespaces Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param namespace Feature-set namespace registered for the selected matrix and organism.
#' @param feature_sets Optional feature-set names within the selected namespace.
#' @param min_set_size Minimum threshold controlling filtering or eligibility for this operation.
#' @param max_set_size Maximum threshold controlling filtering or eligibility for this operation.
#' @param min_detected_fraction Minimum threshold controlling filtering or eligibility for this operation.
#' @param deduplicate_sets Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_feature_trend_spearman
#' @aliases wb_op_feature_trend_spearman
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param min_pct_nonzero Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_sd Minimum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @param chunk_size Maximum chunk size for bounded-memory processing along the documented chunking axis.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_hvg_select
#' @aliases wb_op_hvg_select
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param n_features Positive integer count controlling this operation.
#' @param method Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_mean Minimum threshold controlling filtering or eligibility for this operation.
#' @param max_mean Maximum threshold controlling filtering or eligibility for this operation.
#' @param min_dispersion Minimum threshold controlling filtering or eligibility for this operation.
#' @param batch_key Optional metadata column describing batches; support is operation-specific.
#' @param exclude_features Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param feature_type Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param chunk_size Maximum chunk size for bounded-memory processing along the documented chunking axis.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_interface
#' @aliases wb_op_interface
#' @param op_name Registered operation name.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_knn_graph
#' @aliases wb_op_knn_graph
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param k Number of nearest neighbors.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param metric Distance metric for neighborhood or embedding computation.
#' @param weight Whether to compute or use weighted neighborhood relationships.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_knn_neighbors
#' @aliases wb_op_knn_neighbors
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param query_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param candidate_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param k Number of nearest neighbors.
#' @param include_query Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_knn_pseudobulk
#' @aliases wb_op_knn_pseudobulk
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param space_id Registered coordinate-space identifier.
#' @param query_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param candidate_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param k Number of nearest neighbors.
#' @param include_query Logical control flag for this operation.
#' @param aggregate Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_leiden
#' @aliases wb_op_leiden
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param k Number of nearest neighbors.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param resolution Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_iterations Positive integer count controlling this operation.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param weight Whether to compute or use weighted neighborhood relationships.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_markers_topn
#' @aliases wb_op_markers_topn
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param clusters Named cell-level cluster-label vector or compatible cell-vector primitive.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param top_n Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_pct Minimum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_matrix_log_normalize
#' @aliases wb_op_matrix_log_normalize
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param output_matrix_id Identifier for a newly registered derived matrix.
#' @param scale_factor Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param overwrite Whether an existing output with the same identifier may be replaced.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_meanexpr
#' @aliases wb_op_meanexpr
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param na_rm Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_monocle3_fit
#' @aliases wb_op_monocle3_fit
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used for model fitting.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param root_cells Root cell identifiers used to orient a trajectory.
#' @param root_pr_nodes Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param k Number of nearest neighbors.
#' @param cluster_method Named computational method; supported values are validated by the operation.
#' @param num_iter Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param partition_qval Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param weight Whether to compute or use weighted neighborhood relationships.
#' @param resolution Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param random_seed Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param use_partition Logical control flag for this operation.
#' @param close_loop Logical control flag for this operation.
#' @param verbose Logical control flag for this operation.
#' @param nn_control Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param learn_graph_control Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_monocle3_project
#' @aliases wb_op_monocle3_project
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param monocle3_model Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param approx_points Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_palantir_fit
#' @aliases wb_op_palantir_fit
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used for model fitting.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param root_cell Root cell identifier used to orient a trajectory.
#' @param terminal_cells Terminal cell identifiers used to define trajectory endpoints.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param knn Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_diffusion_components Positive integer count controlling this operation.
#' @param n_waypoints Positive integer count controlling this operation.
#' @param use_early_cell_as_start Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param python_bin Python executable used for the optional pybench runtime.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_palantir_project
#' @aliases wb_op_palantir_project
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param prob_min Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param smoothness Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_cells_per_branch Minimum threshold controlling filtering or eligibility for this operation.
#' @param approx_points Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param python_bin Python executable used for the optional pybench runtime.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_pathway_enrich
#' @aliases wb_op_pathway_enrich
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param feature_table Feature-table data frame or primitive supplying selected features and annotations.
#' @param namespace Feature-set namespace registered for the selected matrix and organism.
#' @param feature_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param p_adj_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param p_adj_max Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param lfc_col Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param direction Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param lfc_min_abs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param lfc_min Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_set_size Minimum threshold controlling filtering or eligibility for this operation.
#' @param max_set_size Maximum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_pca_fit
#' @aliases wb_op_pca_fit
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param feature_table Feature-table data frame or primitive supplying selected features and annotations.
#' @param feature_ids Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_components Positive integer count controlling this operation.
#' @param center Logical control flag for this operation.
#' @param scale Logical control flag for this operation.
#' @param backend Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param space_id_out Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param overwrite Whether an existing output with the same identifier may be replaced.
#' @param max_dense_gb Maximum threshold controlling filtering or eligibility for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_peakvi_project
#' @aliases wb_op_peakvi_project
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param peakvi_model Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param batch_key Optional metadata column describing batches; support is operation-specific.
#' @param use_gpu Whether an optional Python-backed method may request GPU execution.
#' @param space_id_out Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param python_bin Python executable used for the optional pybench runtime.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_slingshot
#' @aliases wb_op_slingshot
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param clusters Named cell-level cluster-label vector or compatible cell-vector primitive.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param exclude_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param include_clusters Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param exclude_clusters Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start.clus Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end.clus Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param stretch Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param reweight Logical control flag for this operation.
#' @param shrink Logical control flag for this operation.
#' @param maxit Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_slingshot_fit
#' @aliases wb_op_slingshot_fit
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used for model fitting.
#' @param clusters Named cell-level cluster-label vector or compatible cell-vector primitive.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param exclude_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param include_clusters Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param exclude_clusters Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start.clus Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end.clus Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param stretch Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param reweight Logical control flag for this operation.
#' @param shrink Logical control flag for this operation.
#' @param maxit Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_slingshot_lineage_weights
#' @aliases wb_op_slingshot_lineage_weights
#' @param model_ref Slingshot `model_ref` primitive with an in-memory or loadable model payload.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_slingshot_project
#' @aliases wb_op_slingshot_project
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param slingshot_model Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param stretch Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param shrink Logical control flag for this operation.
#' @param approx_points Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_space_path_define
#' @aliases wb_op_space_path_define
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param checkpoint_sets Ordered checkpoint cell sets defining a space path.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param fit_mode Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param checkpoint_summary Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_path_points Positive integer count controlling this operation.
#' @param smooth_k Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param smooth_n_iter Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param smooth_weight Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param path_id_out Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_space_path_project_2d
#' @aliases wb_op_space_path_project_2d
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param path Path-family primitive or compatible path reference.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param project_mode Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param approx_points Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_space_path_score
#' @aliases wb_op_space_path_score
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier.
#' @param path Path-family primitive or compatible path reference.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param score_mode Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param distance_metric Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param score_prefix Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_branch_compare
#' @aliases wb_op_trajectory_branch_compare
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param branch_membership Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param branch_a Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param branch_b Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param feature_set Feature-set name or feature-set reference used by the operation.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param min_pct Minimum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_de
#' @aliases wb_op_trajectory_de
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param feature_set Feature-set name or feature-set reference used by the operation.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param test Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_pct_nonzero Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_sd Minimum threshold controlling filtering or eligibility for this operation.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @param chunk_size Maximum chunk size for bounded-memory processing along the documented chunking axis.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_geneset_dynamics
#' @aliases wb_op_trajectory_geneset_dynamics
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param pseudotime_key Key selecting one pseudotime coordinate from a vector family.
#' @param membership Optional cell-vector, cell-set, or compatible membership restriction.
#' @param namespace Feature-set namespace registered for the selected matrix and organism.
#' @param pseudotime_artifact_id Optional promoted pseudotime artifact id recorded for explicit-pseudotime provenance.
#' @param membership_artifact_id Optional promoted membership artifact id recorded for provenance.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param feature_sets Optional feature-set names within the selected namespace.
#' @param score_method Named computational method; supported values are validated by the operation.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @param min_set_size Minimum threshold controlling filtering or eligibility for this operation.
#' @param max_set_size Maximum threshold controlling filtering or eligibility for this operation.
#' @param top_n Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param on_off_min_delta Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param monotonic_min_abs_rho Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param top_driver_genes Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param pseudotime_direction Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_amplitude Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_bins_observed Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_features_detected Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_detected_fraction Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_mean_score Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_max_score Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_signal_to_noise Minimum threshold controlling filtering or eligibility for this operation.
#' @param low_abundance_max_score Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param smooth_method Curve smoothing method; supported values are operation-specific.
#' @param loess_span Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param bootstrap_n Number of per-bin bootstrap replicates; zero disables confidence bands.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param class_min_amplitude Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_permutations Number of empirical pseudotime-association permutations; zero disables testing.
#' @param permutation_seed Random seed for empirical permutation testing.
#' @param p_adjust_method Multiple-testing adjustment method passed to `p.adjust()`.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_route_smooth
#' @aliases wb_op_trajectory_route_smooth
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param branch_membership Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param route_key Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param feature_set Feature-set name or feature-set reference used by the operation.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @param weight_mode Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param prob_min Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param chunk_size Maximum chunk size for bounded-memory processing along the documented chunking axis.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_segment_from_artifacts
#' @aliases wb_op_trajectory_segment_from_artifacts
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param segment_id Identifier or key interpreted by this operation according to its interface contract.
#' @param segment_order Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param lineage_weights Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param membership Optional cell-vector, cell-set, or compatible membership restriction.
#' @param confidence Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param confidence_key Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param path Path-family primitive or compatible path reference.
#' @param source_engine Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param runs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param allow_legacy Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_segment_join
#' @aliases wb_op_trajectory_segment_join
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param segments Ordered validated trajectory segment specifications to join.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param composite_key Key assigned to the composite pseudotime coordinate.
#' @param join_policy Named composite overlap policy; supported values are operation-specific.
#' @param min_weight Minimum threshold controlling filtering or eligibility for this operation.
#' @param allow_legacy Logical control flag for this operation.
#' @param runs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_segment_path_join
#' @aliases wb_op_trajectory_segment_path_join
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param paths Ordered display-path segment specifications to join.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param composite_key Key assigned to the composite pseudotime coordinate.
#' @param display_space_id Identifier or key interpreted by this operation according to its interface contract.
#' @param endpoint_summary_method Named computational method; supported values are validated by the operation.
#' @param endpoint_max_distance Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param endpoint_qc_action Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param allow_legacy Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_signal_dynamics
#' @aliases wb_op_trajectory_signal_dynamics
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param pseudotime Explicit `cell_vector_family` pseudotime primitive or compatible reference.
#' @param pseudotime_key Key selecting one pseudotime coordinate from a vector family.
#' @param membership Optional cell-vector, cell-set, or compatible membership restriction.
#' @param pseudotime_artifact_id Optional promoted pseudotime artifact id recorded for explicit-pseudotime provenance.
#' @param membership_artifact_id Optional promoted membership artifact id recorded for provenance.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @param top_n Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param on_off_min_delta Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param monotonic_min_abs_rho Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param pseudotime_direction Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param min_amplitude Minimum threshold controlling filtering or eligibility for this operation.
#' @param min_bins_observed Minimum threshold controlling filtering or eligibility for this operation.
#' @param smooth_method Curve smoothing method; supported values are operation-specific.
#' @param loess_span Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param bootstrap_n Number of per-bin bootstrap replicates; zero disables confidence bands.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param class_min_amplitude Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_signature_smooth
#' @aliases wb_op_trajectory_signature_smooth
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param feature_set Feature-set name or feature-set reference used by the operation.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param score_method Named computational method; supported values are validated by the operation.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_smooth
#' @aliases wb_op_trajectory_smooth
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier; getters resolve its physical storage.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param feature_set Feature-set name or feature-set reference used by the operation.
#' @param features Optional feature ids to analyse; defaults are operation-specific.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @param chunk_size Maximum chunk size for bounded-memory processing along the documented chunking axis.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_space_path_segment
#' @aliases wb_op_trajectory_space_path_segment
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param path_scores Scored space-path output used to build a trajectory bridge segment.
#' @param segment_id Identifier or key interpreted by this operation according to its interface contract.
#' @param segment_order Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param score_prefix Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param candidate_cells Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param distance_threshold Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param distance_quantile Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_label Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param path Path-family primitive or compatible path reference.
#' @param display_path Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param display_lineage Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param display_space_id Identifier or key interpreted by this operation according to its interface contract.
#' @param start_endpoint Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_endpoint Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param start_cell_set Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param end_cell_set Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param endpoint_summary_method Named computational method; supported values are validated by the operation.
#' @param endpoint_max_distance Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param endpoint_qc_action Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param pseudotime_key Key selecting one pseudotime coordinate from a vector family.
#' @param confidence_key Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param runs Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_trajectory_vector_smooth
#' @aliases wb_op_trajectory_vector_smooth
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param signal Cell-vector or cell-vector-family primitive containing per-cell scores.
#' @param model Typed `model_ref` trajectory/model primitive or compatible reference.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param lineage Optional trajectory lineage key to analyse.
#' @param signal_keys Optional keys to retain from a cell-vector-family signal.
#' @param n_bins Number of ordered pseudotime bins used for curve summaries.
#' @param summary_fun Within-bin summary statistic, usually `mean` or `median`.
#' @param min_cells_per_bin Minimum cells required for a pseudotime bin to contribute a summary.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_umap_fit
#' @aliases wb_op_umap_fit
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param source_space_id Registered source coordinate space used for fitting.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param space_id_out Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param n_neighbors Positive integer count controlling this operation.
#' @param min_dist Minimum threshold controlling filtering or eligibility for this operation.
#' @param metric Distance metric for neighborhood or embedding computation.
#' @param nn_method Named computational method; supported values are validated by the operation.
#' @param spread Operation-specific parameter. See `wb_op_interface()` for its validated runtime contract and defaults.
#' @param seed Optional integer random seed for reproducible stochastic computation.
#' @param verbose Logical control flag for this operation.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

#' @name wb_op_umap_transform
#' @aliases wb_op_umap_transform
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model_space_id Identifier or key interpreted by this operation according to its interface contract.
#' @param in_space_id Identifier or key interpreted by this operation according to its interface contract.
#' @param cells Optional canonical cell ids defining the analysis universe; operations may require an explicit effective universe.
#' @param cell_set Named bundle cell set used when an operation resolves its own cell universe.
#' @param dims Optional coordinate dimensions to use from the selected space.
#' @param overwrite Whether an existing output with the same identifier may be replaced.
#' @param ... Additional engine-specific arguments passed only where the documented wrapper supports them.
#' @return A typed operation result or interface object. Inspect `wb_op_interface()` for declared primitive outputs and promotion behavior.
NULL

