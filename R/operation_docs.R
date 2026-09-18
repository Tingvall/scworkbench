# Generated from the runtime operation interface catalog; do not edit by hand.
# Source: .wb_op_catalog() via wb_op_interface().
# Regenerate: Rscript inst/dev/generate_operation_docs.R

#' @name wb_op_chromvar
#' @aliases wb_op_chromvar
#' @description Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param motif_library Canonical motif-library key from the motif registry.
#' @param motifs Optional motif-key subset within motif_library.
#' @param motif_match_set Optional canonical motif-match-set key to reuse cached motif-to-peak matches.
#' @param min_motif_peaks Minimum number of matched peaks per retained motif.
#' @param max_motif_peaks Optional maximum number of matched peaks per retained motif.
#' @param motif_p_cutoff Motifmatchr p-value cutoff.
#' @param motif_w Motifmatchr background window width.
#' @param seqlevels_mode Seqlevel policy; standard chromosomes are the default.
#' @param seqlevels_include Optional explicit seqlevels to keep after applying seqlevels_mode.
#' @param seqlevels_exclude Optional explicit seqlevels to drop after applying seqlevels_mode.
#' @param background_iterations Number of chromVAR background iterations.
#' @param background_w Background peak matching window width.
#' @param background_bs Background peak matching bin count.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$deviation_z` (`cell_vector_family`): Per-cell chromVAR z-scores keyed by motif.; `outputs$deviation_raw` (`cell_vector_family`): Per-cell raw chromVAR deviations keyed by motif.; `outputs$motif_summary` (`obs_table`): Per-motif chromVAR summary statistics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_feature_set_import
#' @aliases wb_op_feature_set_import
#' @description Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param source_path Path to GMT, RDS list/data.frame, or CSV-like table source.
#' @param source_format Input parser. auto infers from file extension.
#' @param table Optional in-memory feature-set source table.
#' @param sets Optional named in-memory feature-set list.
#' @param namespace Target feature-set namespace base label.
#' @param collection Optional collection label recorded in import manifests.
#' @param subcollection Optional subcollection label; used for namespace splitting when requested.
#' @param species Species/organism label recorded in feature-set metadata.
#' @param organism Organism label recorded with the imported feature-set namespace.
#' @param gene_id_type Identifier type expected in source genes, for example gene_symbol.
#' @param set_id_col For table sources, column containing set identifiers.
#' @param set_name_col For table sources, optional human-readable set-name column.
#' @param gene_col For table sources, column containing gene/feature identifiers.
#' @param description_col For table sources, optional set description column.
#' @param split_by_collection If TRUE, append detected/declared subcollection to the namespace base.
#' @param overwrite If FALSE, existing feature sets are skipped instead of replaced.
#' @param strict If TRUE, error on genes absent from the matrix; otherwise drop absent genes.
#' @param created_by Optional actor label recorded in provenance.
#' @param source_id Optional source/library identifier stored in feature-set metadata.
#' @param source_version Optional source/library version stored in feature-set metadata.
#' @param origin Human-readable origin label recorded for imported source material.
#' @param is_readonly Whether imported feature sets are marked read-only after registration.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$import_summary` (`obs_table`): One-row summary of parsed/imported/skipped/rejected set counts.; `outputs$import_manifest` (`obs_table`): One row per parsed feature set with target namespace, overlap counts, and import status.; `outputs$rejected_sets` (`obs_table`): Feature sets rejected during import, typically because no genes mapped to the matrix.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_knn_neighbors
#' @aliases wb_op_knn_neighbors
#' @description Find nearest neighbors in a latent space without requiring matrix aggregation.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier consumed by this operation.
#' @param query_cells Query cells: explicit IDs or 'set:<name>'
#' @param candidate_cells Optional candidate neighbor pool; defaults to all cells.
#' @param k Nearest neighbors per query cell.
#' @param include_query Include query cells themselves when they are in candidate pool.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$neighbors` (`obs_table`): Per-query neighbor table (cell_id, rank, distance).; `outputs$neighbor_distance` (`cell_vector_family`): Neighbor distances per query cell.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_knn_pseudobulk
#' @aliases wb_op_knn_pseudobulk
#' @description Find k nearest neighbors in latent space around query cells and aggregate matrix values.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param space_id Registered coordinate-space identifier consumed by this operation.
#' @param query_cells Query cells: explicit IDs or 'set:<name>'
#' @param candidate_cells Optional candidate neighbor pool; defaults to all cells.
#' @param features Optional feature subset for pseudobulk output.
#' @param k Nearest neighbors per query cell.
#' @param include_query Include query cells themselves when they are in candidate pool.
#' @param aggregate Aggregation mode: sum or mean.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudobulk_table` (`feature_table`): Feature-level pseudobulk values keyed by query cell.; `outputs$neighbor_distance` (`cell_vector_family`): Neighbor distances per query cell.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_matrix_log_normalize
#' @aliases wb_op_matrix_log_normalize
#' @description Create a reusable log1p(counts / library_size * scale_factor) BPCells matrix in the bundle.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param output_matrix_id Matrix id to create, for example RNA_log1p_cp10k. Defaults to <source>_log1p_cp<scale_factor>.
#' @param scale_factor Per-cell target count scale before log1p; 10000 is the common CP10K convention.
#' @param overwrite If TRUE, replace an existing output matrix with the same id.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$matrix` (`matrix`): Reference to the newly registered log-normalized matrix.; `outputs$summary` (`obs_table`): Transform parameters, source/output matrix ids, dimensions, library-size diagnostics, and storage path.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_metadata_cell_vector
#' @aliases wb_op_metadata_cell_vector
#' @description Materialize an imported cell metadata column as a typed, provenance-backed cell vector.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param source_column Imported metadata name or explicit wb_ref_metadata_field() reference to materialize.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param value_type Explicit vector value type; auto records a conservative native-type decision.
#' @param missing_policy How missing values are handled before vector materialization.
#' @param missing_label Replacement label when missing_policy='as_category'.
#' @param vector_name Stable promoted vector name; collision protection is controlled by overwrite.
#' @param overwrite Allow a new immutable artifact to supersede an existing vector with the same name.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$vector` (`cell_vector`): Typed per-cell vector materialized from imported bundle metadata.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_model_bound_latent_union
#' @aliases wb_op_model_bound_latent_union
#' @description Combine disjoint fitted-reference and projected-query latent coordinates only when both are bound to the same retained PeakVI or scVI model identity.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param reference_space Required `reference_space` input represented as `space`; accepted symbolic references are resolved by the operation interface.
#' @param query_space Required `query_space` input represented as `space`; accepted symbolic references are resolved by the operation interface.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param projection_summary Required `projection_summary` input represented as `obs_table`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param space_id_out New durable space identity for the unchanged row-wise coordinate union.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$space` (`space`): Durable high-dimensional space containing fitted reference and projected query coordinates in canonical cell order.; `outputs$union_summary` (`obs_table`): Model, source-space, output-space, cell-count, dimension, disjointness, and no-transformation record.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_monocle3_fit
#' @aliases wb_op_monocle3_fit
#' @description Fit monocle3 graph/pseudotime using a scworkbench latent space injected into monocle3's UMAP slot.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used to fit the model.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param dims Optional fit-space dimensions to use (e.g. 1:20 as explicit integer vector).
#' @param root_cells Root cell IDs (exactly one of root_cells or root_pr_nodes).
#' @param root_pr_nodes Principal graph root node IDs (advanced; exactly one of root_cells or root_pr_nodes).
#' @param k kNN size for monocle3 clustering.
#' @param cluster_method Monocle3 clustering backend.
#' @param num_iter Monocle3 clustering iterations.
#' @param partition_qval Partition significance threshold.
#' @param weight Whether weighted nearest-neighbor relationships are used by the engine.
#' @param resolution Optional clustering resolution (NULL lets monocle3 choose).
#' @param random_seed Random seed for clustering.
#' @param use_partition Learn graph per partition. FALSE is recommended for current tree semantics.
#' @param close_loop Allow loop closure in graph learning. FALSE is required for tree-derived lineages.
#' @param verbose Whether the underlying engine emits progress output.
#' @param nn_control Optional nearest-neighbor control list passed to the underlying engine.
#' @param learn_graph_control Optional principal-graph learning control list passed to the underlying engine.
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector`): Rooted global pseudotime per cell from monocle3.; `outputs$branch_membership` (`relation_family`): Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in the current implementation).; `outputs$model` (`model_ref`): Session-chainable monocle3 CDS model (engine='monocle3').. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_monocle3_project
#' @aliases wb_op_monocle3_project
#' @description Project a fitted monocle3 trajectory graph into a 2D display space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param monocle3_model Monocle3 `model_ref` primitive returned by `wb_op_monocle3_fit()`.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param approx_points Target max curve points per lineage for display (0/NULL = no compaction).
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$curves` (`path_2d_family`): Projected monocle3 root-qualified lineage curves in the chosen 2D display space.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_palantir_fit
#' @aliases wb_op_palantir_fit
#' @description Run Palantir pseudotime/branch probabilities on a scworkbench latent space via the pybench Python runtime.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used to fit the model.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param root_cell Single Palantir early/root cell ID (Palantir-native single-root semantics).
#' @param terminal_cells Optional explicit terminal cell IDs passed to Palantir as terminal states (recommended for branch probabilities).
#' @param dims Optional fit-space dimensions to use (for example 1:20 as explicit integer vector).
#' @param knn kNN size for Palantir diffusion graph and pseudotime.
#' @param n_diffusion_components Number of diffusion components for Palantir.
#' @param n_waypoints Number of Palantir waypoints.
#' @param use_early_cell_as_start Pass through to Palantir; if TRUE, force the provided early/root cell to be used as trajectory start.
#' @param seed Integer random seed used to make stochastic computation reproducible.
#' @param cell_set Named bundle cell set used to resolve the analysis universe.
#' @param python_bin Python executable used for an optional pybench-backed runtime.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector`): Palantir pseudotime (single-root, global).; `outputs$branch_membership` (`relation_family`): Palantir branch probabilities as cell-to-branch relations (`branch:*` keys; weights are probabilities).; `outputs$branch_summary` (`obs_table`): Palantir branch probability summary table.; `outputs$entropy` (`cell_vector`): Palantir entropy per cell.; `outputs$model` (`model_ref`): Palantir Python model payload (engine='palantir').. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_palantir_project
#' @aliases wb_op_palantir_project
#' @description Project Palantir branch trajectories into a 2D display space using Palantir-style mellon interpolation from the fitted Palantir model.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param prob_min Minimum branch probability mask threshold for branch trajectory interpolation.
#' @param smoothness Palantir-style mellon trajectory smoothing multiplier (higher = smoother).
#' @param min_cells_per_branch Minimum eligible cells required to derive a branch trajectory.
#' @param approx_points Number of trajectory sample points per branch (curve resolution).
#' @param python_bin Python executable used for an optional pybench-backed runtime.
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$curves` (`path_2d_family`): Palantir-style smoothed branch trajectories projected into the chosen 2D display space.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_pca_fit
#' @aliases wb_op_pca_fit
#' @description Compute PCA from a matrix and selected features, then persist the cell coordinates as a bundle space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param feature_table Feature-table data frame or primitive supplying selected features and annotations.
#' @param feature_ids Optional explicit feature IDs when not passing features as a feature_table reference.
#' @param n_components Number of principal components to compute.
#' @param center Center features before PCA.
#' @param scale Scale features before PCA.
#' @param backend PCA backend. 'irlba' is recommended for large sparse/backed matrices.
#' @param seed Integer random seed used to make stochastic computation reproducible.
#' @param space_id_out Bundle space id to create.
#' @param overwrite Replace an existing space_id_out if present.
#' @param max_dense_gb Approximate dense selected-block size guard for dense backends.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$space` (`space`): Reference to the persisted PCA space.; `outputs$loadings` (`feature_table`): Feature loadings per principal component.; `outputs$variance` (`obs_table`): Per-PC standard deviation and variance explained.; `outputs$fit_summary` (`obs_table`): Input matrix, feature count, backend, component count, and output space id.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_peakvi_project
#' @aliases wb_op_peakvi_project
#' @description Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param peakvi_model PeakVI `model_ref` primitive returned by the Python-backed fitting workflow.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param batch_key Optional observation field used as the PeakVI batch covariate during projection.
#' @param use_gpu If TRUE, request GPU-backed model loading/projection in scvi-tools.
#' @param space_id_out Space id to write for the projected PeakVI latent embedding.
#' @param python_bin Python executable used for an optional pybench-backed runtime.
#' @param cell_set Named bundle cell set used to resolve the analysis universe.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$space` (`space`): Projected PeakVI latent space written into the bundle spaces registry.; `outputs$fit_summary` (`obs_table`): Projection receipt and output-space summary.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot
#' @aliases wb_op_slingshot
#' @description Infer lineage curves and pseudotime from clusters in a 2D space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier consumed by this operation.
#' @param clusters Required `clusters` input represented as `cell_vector`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param exclude_cells Optional cell ids excluded before fitting.
#' @param include_clusters Optional cluster labels retained before fitting.
#' @param exclude_clusters Cluster id(s) to exclude before fitting.
#' @param start.clus Starting cluster id.
#' @param end.clus Ending cluster id(s).
#' @param stretch Slingshot curve stretching.
#' @param reweight Whether to reweight assignments during fitting.
#' @param shrink Engine shrinkage control for fitted trajectory curves.
#' @param maxit Maximum engine fitting iterations.
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Lineage-specific pseudotime values per cell.; `outputs$curves` (`path_2d_family`): Lineage curve paths in 2D.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot_adopt
#' @aliases wb_op_slingshot_adopt
#' @description Adopt a checksummed source-derived Slingshot fit as a complete trajectory family without refitting it.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model_ref Typed `model_ref` primitive required by this engine-specific helper.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param source Registered external_source reference for the object from which the selected Slingshot fit was extracted.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Source-derived lineage-specific pseudotime values; no refit is performed.; `outputs$lineage_weights` (`cell_vector_family`): Source-derived Slingshot lineage membership weights; no refit is performed.; `outputs$curves` (`path_2d_family`): Source-derived two-dimensional Slingshot lineage curves.; `outputs$model` (`model_ref`): Contained source-derived Slingshot model bound to the adopted trajectory fit family.; `outputs$adoption_summary` (`obs_table`): Source checksum, subobject identity, coordinate-alignment result, fit identity, dimensions, and explicit external-execution boundary.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot_fit
#' @aliases wb_op_slingshot_fit
#' @description Fit Slingshot lineages/pseudotime in a chosen fit space (typically latent/PCA).
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param fit_space_id Registered coordinate space used to fit the model.
#' @param clusters Required `clusters` input represented as `cell_vector`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param exclude_cells Optional cell ids excluded before fitting.
#' @param include_clusters Optional cluster labels retained before fitting.
#' @param exclude_clusters Cluster id(s) to exclude before fitting.
#' @param start.clus Starting cluster id.
#' @param end.clus Ending cluster id(s).
#' @param stretch Slingshot curve stretching.
#' @param reweight Whether to reweight assignments during fitting.
#' @param shrink Engine shrinkage control for fitted trajectory curves.
#' @param maxit Maximum engine fitting iterations.
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Lineage-specific pseudotime values per cell (fit space inference).; `outputs$lineage_weights` (`cell_vector_family`): Slingshot lineage membership weights per cell and lineage. These are trajectory membership weights, not pseudotime.; `outputs$model` (`model_ref`): Session-chainable Slingshot fit model (engine='slingshot').. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot_lineage_weights
#' @aliases wb_op_slingshot_lineage_weights
#' @description Extract Slingshot lineage membership weights from an existing model_ref without refitting, preserving trajectory_fit_id and lineage mapping.
#' @param model_ref Typed `model_ref` primitive required by this engine-specific helper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$lineage_weights` (`cell_vector_family`): Slingshot lineage membership weights extracted from an existing model_ref; no trajectory refit is performed.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_slingshot_project
#' @aliases wb_op_slingshot_project
#' @description Project a fitted Slingshot model into a 2D display space (e.g. UMAP).
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param slingshot_model Slingshot `model_ref` primitive returned by `wb_op_slingshot_fit()`.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param stretch Optional override of stretch during embedding.
#' @param shrink Engine shrinkage control for fitted trajectory curves.
#' @param approx_points Target max curve points per lineage for display (0/NULL = no compaction).
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$curves` (`path_2d_family`): Projected Slingshot lineage curves in the chosen 2D display space.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_space_path_define
#' @aliases wb_op_space_path_define
#' @description Contract scaffold for checkpoint-anchored path construction in a named analytical space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier consumed by this operation.
#' @param checkpoint_sets Ordered checkpoint cell-set refs that anchor the path definition.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param fit_mode Path fitting mode. The current implementation supports linear and a conservative manifold smoothing mode.
#' @param checkpoint_summary Checkpoint summarization rule used to derive anchors from checkpoint cells.
#' @param n_path_points Optional explicit number of fitted path points.
#' @param smooth_k For fit_mode='manifold_smooth', number of nearest cells used per provisional path point.
#' @param smooth_n_iter For fit_mode='manifold_smooth', number of refinement passes.
#' @param smooth_weight For fit_mode='manifold_smooth', distance-weighting rule for local cell pull.
#' @param path_id_out Path id to record for the emitted analytical path.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$path` (`space_path_family`): Analytical path in the original latent space.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_space_path_project_2d
#' @aliases wb_op_space_path_project_2d
#' @description Contract scaffold for projecting an analytical path into a drawable 2D path family.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param path Path-family primitive or compatible path reference.
#' @param plot_space_id Registered two-dimensional display space used for projection.
#' @param project_mode Projection mode used to approximate the analytical path in a 2D plot space.
#' @param approx_points Optional target point count for display compaction.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$curves` (`path_2d_family`): Approximate 2D rendering of the analytical path.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_space_path_score
#' @aliases wb_op_space_path_score
#' @description Contract scaffold for path-relative scoring in a named analytical space.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param space_id Registered coordinate-space identifier consumed by this operation.
#' @param path Path-family primitive or compatible path reference.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param score_mode Scoring mode. The current implementation standardizes on orthogonal projection semantics.
#' @param distance_metric Distance metric used for path-relative scoring.
#' @param score_prefix Optional prefix for emitted score-family keys.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$path_scores` (`cell_vector_family`): Per-cell path-relative scores such as progress and distance.; `outputs$fit_summary` (`obs_table`): Compact path-level scoring diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_branch_compare
#' @aliases wb_op_trajectory_branch_compare
#' @description Compare two trajectory branches feature-by-feature using explicit pseudotime and branch membership primitives.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param pseudotime Required `pseudotime` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param branch_membership Required `branch_membership` input represented as `relation_family`; accepted symbolic references are resolved by the operation interface.
#' @param branch_a Branch/lineage key A.
#' @param branch_b Branch/lineage key B.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param feature_set Optional feature set name from wb_feature_sets() for matrix.
#' @param features Optional explicit feature subset (intersected with feature_set when both provided).
#' @param min_pct Minimum detection fraction in either branch.
#' @param p_adjust_method Method passed to p.adjust.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$branch_de_table` (`feature_table`): Per-feature branch comparison statistics and effect sizes.; `outputs$branch_summary` (`obs_table`): Branch-pair cell counts and pseudotime summary diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_de
#' @aliases wb_op_trajectory_de
#' @description Lineage-aware feature trend testing against trajectory pseudotime from model_ref.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param feature_set Optional feature set name from wb_feature_sets() for matrix.
#' @param features Optional explicit feature subset (intersected with feature_set when both provided).
#' @param test Statistical test. The current implementation supports spearman.
#' @param min_pct_nonzero Minimum non-zero fraction filter.
#' @param min_sd Minimum per-feature standard deviation filter.
#' @param p_adjust_method Method passed to p.adjust.
#' @param chunk_size Maximum chunk size used for bounded-memory processing.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$de_table` (`feature_table`): Per-lineage feature trend statistics (rho, p, adjusted p).; `outputs$fit_summary` (`obs_table`): Per-lineage input and filtering diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_geneset_dynamics
#' @aliases wb_op_trajectory_geneset_dynamics
#' @description Screen all feature sets in a namespace for dynamic behavior along trajectory pseudotime.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param model Optional `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param pseudotime Optional `pseudotime` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param pseudotime_key Required key for explicit cell_vector_family pseudotime when multiple keys are present.
#' @param membership Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
#' @param namespace Feature-set namespace from wb_feature_sets() to screen.
#' @param pseudotime_artifact_id Optional promoted pseudotime artifact id recorded in explicit-pseudotime provenance.
#' @param membership_artifact_id Optional promoted membership artifact id recorded in explicit-pseudotime provenance.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param feature_sets Optional feature-set subset within the namespace.
#' @param score_method How to score each feature set within each cell.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param min_set_size Minimum feature-set size after intersecting with the matrix.
#' @param max_set_size Maximum feature-set size after intersecting with the matrix.
#' @param top_n Number of top-ranked feature sets retained in top_sets.
#' @param on_off_min_delta Minimum absolute late-early delta for turns_on/turns_off classes.
#' @param monotonic_min_abs_rho Minimum absolute Spearman rho for turns_on/turns_off classes.
#' @param top_driver_genes Number of top member genes retained as curve drivers per feature set.
#' @param pseudotime_direction Use pseudotime as provided or invert it before binning and classification.
#' @param start_label Optional biological start label recorded in output metadata.
#' @param end_label Optional biological end label recorded in output metadata.
#' @param min_amplitude Minimum curve amplitude required for passes_filters.
#' @param min_bins_observed Minimum retained bins required for passes_filters.
#' @param min_features_detected Minimum detected set members required for passes_filters.
#' @param min_detected_fraction Minimum fraction of detected set members required for passes_filters.
#' @param min_mean_score Optional minimum mean smoothed score required for passes_filters; use to suppress very low-abundance dynamics.
#' @param min_max_score Optional minimum maximum smoothed score required for passes_filters; use to suppress near-zero curves.
#' @param min_signal_to_noise Optional minimum amplitude divided by mean bootstrap SE required for passes_filters.
#' @param low_abundance_max_score Curves with max_score below this value are flagged low_abundance_flag but not filtered unless min_max_score is set.
#' @param smooth_method Optional smoothing method applied to binned curves before metrics/classes.
#' @param loess_span Span used when smooth_method='loess'.
#' @param bootstrap_n Bootstrap replicates per bin for confidence bands; 0 disables CIs.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Confidence level for bootstrap bands.
#' @param class_min_amplitude Minimum amplitude required before assigning non-flat curve classes.
#' @param n_permutations Number of empirical permutations for dynamic-score p-values; 0 disables permutation testing.
#' @param permutation_seed Random seed for empirical dynamic-score permutations.
#' @param p_adjust_method Multiple-testing correction method for q_dynamic.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$signature_table` (`obs_table`): Binned feature-set score curves along trajectory pseudotime.; `outputs$dynamics_table` (`obs_table`): Per-feature-set dynamic metrics and rank.; `outputs$top_sets` (`obs_table`): Top-ranked dynamic feature sets for report-first discovery.; `outputs$driver_table` (`obs_table`): Top dynamic member genes within each screened feature set.; `outputs$driver_curve_table` (`obs_table`): Binned curves for top driver genes within each screened feature set.; `outputs$fit_summary` (`obs_table`): Per-lineage screening diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_route_smooth
#' @aliases wb_op_trajectory_route_smooth
#' @description Summarize per-feature expression along an explicit route using global pseudotime plus route membership weights.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param pseudotime Required `pseudotime` input represented as `cell_vector`; accepted symbolic references are resolved by the operation interface.
#' @param branch_membership Required `branch_membership` input represented as `relation_family`; accepted symbolic references are resolved by the operation interface.
#' @param route_key Required route/branch key within branch_membership.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param feature_set Optional feature set name from wb_feature_sets() for matrix.
#' @param features Optional explicit feature subset (intersected with feature_set when both provided).
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin. Weighted routes currently support mean only.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param weight_mode Use route probabilities directly or threshold to a binary route membership.
#' @param prob_min Minimum route probability required to include a cell.
#' @param chunk_size Maximum chunk size used for bounded-memory processing.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$trend_table` (`obs_table`): Per-feature binned summaries along a selected route.; `outputs$fit_summary` (`obs_table`): Route smoothing diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_segment_from_artifacts
#' @aliases wb_op_trajectory_segment_from_artifacts
#' @description Materialize the generic trajectory segment contract from fitted-model trajectory artifacts with fit-family validation.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param pseudotime Required `pseudotime` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param lineage Lineage/key to extract from fitted pseudotime and optional weights.
#' @param segment_id Stable segment identifier.
#' @param segment_order Order of this fitted segment in a future composite.
#' @param model Optional `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param lineage_weights Optional `lineage_weights` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param membership Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
#' @param confidence Optional `confidence` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param confidence_key Optional key for confidence cell_vector_family. Defaults to lineage.
#' @param path Path-family primitive or compatible path reference.
#' @param source_engine Fitted trajectory engine, usually slingshot, monocle3, or palantir.
#' @param start_label Biological start label.
#' @param end_label Biological end label.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param runs Optional session run registry used to resolve symbolic input references.
#' @param allow_legacy Allow missing trajectory_fit_id with warning. Default rejects legacy ambiguity.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Fitted-model segment pseudotime for the selected lineage/key.; `outputs$membership` (`cell_vector`): Cells included in the fitted-model segment.; `outputs$confidence` (`cell_vector_family`): Segment confidence, derived from supplied confidence/lineage weights or defaulting to 1.; `outputs$segment_manifest` (`obs_table`): Audit manifest for the fitted-model segment.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_segment_join
#' @aliases wb_op_trajectory_segment_join
#' @description Join ordered generic trajectory segments into an auditable composite pseudotime without merging parent trajectory models.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param segments Ordered segment specs with source_kind/source_engine, pseudotime ref, lineage key, optional membership/weights/confidence/path refs, labels, and order.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param composite_key Key used in the output composite pseudotime cell_vector_family objects.
#' @param join_policy Overlap policy. The current implementation supports exact_boundary_collapse.
#' @param min_weight Optional minimum lineage weight required for segment-local membership when weights are supplied.
#' @param allow_legacy Allow missing trajectory_fit_id within a segment with warning. Default rejects legacy ambiguity.
#' @param runs Optional session run registry used to resolve symbolic input references.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$composite_pseudotime_unit_segment` (`cell_vector_family`): Canonical one-row-per-cell composite pseudotime with exact integer segment boundaries.; `outputs$composite_pseudotime_cell_weighted_0_1` (`cell_vector_family`): One-row-per-cell composite pseudotime normalized to \\[0,1\\] with segment lengths weighted by segment-local cell counts.; `outputs$segment_local_table` (`obs_table`): One row per cell per parent segment preserving source kind, raw pseudotime, normalized pseudotime, confidence, weight, and segment role.; `outputs$composite_manifest` (`obs_table`): Audit manifest recording parent segment sources, artifacts, fit IDs where available, labels, join policy, overlap counts, and caveats.; `outputs$composite_membership` (`cell_vector`): One-cell assignment to a unique segment or waypoint overlap.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_segment_path_join
#' @aliases wb_op_trajectory_segment_path_join
#' @description Join ordered parent path_2d_family segments into a derived composite display curve without merging parent trajectory models.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param paths Ordered path segment specs with path ref, lineage key, segment ID, labels, and order.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param composite_key Key used in the output composite path_2d_family.
#' @param display_space_id 2D display space used for endpoint cell-set coordinate QC when path segment specs declare endpoint cell sets.
#' @param endpoint_summary_method How endpoint cell sets are summarized in display space for QC.
#' @param endpoint_max_distance Optional absolute maximum endpoint distance before QC fails.
#' @param endpoint_qc_action Action when display-path endpoint QC detects a large mismatch.
#' @param allow_legacy Allow missing trajectory_fit_id on parent paths with warning.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$curves` (`path_2d_family`): Derived display-only composite path suitable for UMAP overlay; not a merged fitted trajectory model.; `outputs$path_manifest` (`obs_table`): Audit manifest recording parent path artifacts, segment order, point boundaries, and caveats.; `outputs$endpoint_qc` (`obs_table`): Endpoint-distance QC for joined display paths with declared endpoint descriptors.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_signal_dynamics
#' @aliases wb_op_trajectory_signal_dynamics
#' @description Rank precomputed cell-level signal families by dynamic behavior along trajectory pseudotime.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param signal Required `signal` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param model Optional `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param pseudotime Optional `pseudotime` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param pseudotime_key Required key for explicit cell_vector_family pseudotime when multiple keys are present.
#' @param membership Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells.
#' @param pseudotime_artifact_id Optional promoted pseudotime artifact id recorded in explicit-pseudotime provenance.
#' @param membership_artifact_id Optional promoted membership artifact id recorded in explicit-pseudotime provenance.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param signal_keys Optional signal-key subset within the cell_vector_family.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param top_n Number of top-ranked signals retained in top_signals.
#' @param on_off_min_delta Minimum absolute late-early delta for turns_on/turns_off classes.
#' @param monotonic_min_abs_rho Minimum absolute Spearman rho for turns_on/turns_off classes.
#' @param pseudotime_direction Use pseudotime as provided or invert it before binning and classification.
#' @param start_label Optional biological start label recorded in output metadata.
#' @param end_label Optional biological end label recorded in output metadata.
#' @param min_amplitude Minimum curve amplitude required for passes_filters.
#' @param min_bins_observed Minimum retained bins required for passes_filters.
#' @param smooth_method Optional smoothing method applied to binned curves before metrics/classes.
#' @param loess_span Span used when smooth_method='loess'.
#' @param bootstrap_n Bootstrap replicates per bin for confidence bands; 0 disables CIs.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Confidence level for bootstrap bands.
#' @param class_min_amplitude Minimum amplitude required before assigning non-flat curve classes.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$signal_table` (`obs_table`): Binned signal-score curves along trajectory pseudotime.; `outputs$dynamics_table` (`obs_table`): Per-signal dynamic metrics and rank.; `outputs$top_signals` (`obs_table`): Top-ranked dynamic signals for report-first discovery.; `outputs$fit_summary` (`obs_table`): Per-lineage signal dynamics diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_signature_smooth
#' @aliases wb_op_trajectory_signature_smooth
#' @description Summarize feature-set signature scores along trajectory pseudotime into reusable trend tables.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param feature_set Required feature set name from wb_feature_sets() for matrix.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param score_method How to score the feature set within each cell.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$signature_table` (`obs_table`): Per-signature binned summaries along trajectory pseudotime.; `outputs$fit_summary` (`obs_table`): Per-lineage signature smoothing diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_smooth
#' @aliases wb_op_trajectory_smooth
#' @description Summarize per-feature expression along trajectory pseudotime into reusable trend tables.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param matrix_id Registered logical matrix identifier consumed by this operation.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param feature_set Optional feature set name from wb_feature_sets() for matrix.
#' @param features Optional explicit feature subset (intersected with feature_set when both provided).
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param chunk_size Maximum chunk size used for bounded-memory processing.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$trend_table` (`obs_table`): Per-feature binned expression summaries along trajectory pseudotime.; `outputs$fit_summary` (`obs_table`): Per-lineage smoothing diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_space_path_segment
#' @aliases wb_op_trajectory_space_path_segment
#' @description Convert space_path_score output into a generic trajectory segment using path-progress pseudotime and transparent distance-based membership.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param path_scores Required `path_scores` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param segment_id Stable segment identifier.
#' @param segment_order Order of this bridge segment in a future composite.
#' @param score_prefix Optional prefix used by space_path_score keys.
#' @param candidate_cells Optional candidate universe before distance thresholding.
#' @param distance_threshold Include cells with distance_to_path <= threshold.
#' @param distance_quantile Alternative threshold: include cells up to this distance quantile.
#' @param start_label Biological start label.
#' @param end_label Biological end label.
#' @param path Path-family primitive or compatible path reference.
#' @param display_path Optional `display_path` input represented as `path_2d_family`; accepted symbolic references are resolved by the operation interface.
#' @param display_lineage Optional key/lineage to validate in display_path. Defaults to the only key if display_path has one.
#' @param display_space_id 2D display space used for endpoint cell-set coordinate QC.
#' @param start_endpoint Optional start endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC.
#' @param end_endpoint Optional end endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC.
#' @param start_cell_set Convenience start endpoint cell set for display-path QC.
#' @param end_cell_set Convenience end endpoint cell set for display-path QC.
#' @param endpoint_summary_method How endpoint cell sets are summarized in display space for QC.
#' @param endpoint_max_distance Optional absolute maximum endpoint distance before QC fails.
#' @param endpoint_qc_action Action when display-path endpoint QC detects a large mismatch.
#' @param composite_id Stable identifier for a derived composite trajectory.
#' @param pseudotime_key Key for emitted bridge pseudotime. Defaults to segment_id.
#' @param confidence_key Key for emitted bridge confidence. Defaults to segment_id.
#' @param runs Optional session run registry used to resolve symbolic input references.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$pseudotime` (`cell_vector_family`): Bridge pseudotime from path arclength progress in \\[0,1\\].; `outputs$membership` (`cell_vector`): Cells passing the transparent distance-to-path bridge membership rule.; `outputs$confidence` (`cell_vector_family`): Distance-derived confidence for included bridge cells.; `outputs$segment_manifest` (`obs_table`): Audit manifest for the space-path bridge segment.; `outputs$display_endpoint_qc` (`obs_table`): Endpoint-distance QC for an optional display_path against declared start/end endpoint descriptors.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_trajectory_vector_smooth
#' @aliases wb_op_trajectory_vector_smooth
#' @description Summarize cell-level signal families along trajectory pseudotime into reusable trend tables.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param signal Required `signal` input represented as `cell_vector_family`; accepted symbolic references are resolved by the operation interface.
#' @param model Required `model` input represented as `model_ref`; accepted symbolic references are resolved by the operation interface.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param lineage Optional lineage key subset.
#' @param signal_keys Optional signal-key subset within the cell_vector_family.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun Summary statistic across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$signal_table` (`obs_table`): Per-signal binned summaries along trajectory pseudotime.; `outputs$fit_summary` (`obs_table`): Per-lineage signal smoothing diagnostics.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_umap_fit
#' @aliases wb_op_umap_fit
#' @description Fit a UMAP model on a space and store it for future projection.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param source_space_id Registered source coordinate space used for fitting.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param cell_set Named bundle cell set used to resolve the analysis universe.
#' @param dims Dims to use (e.g. 2:30).
#' @param space_id_out Output 2D space id. Defaults to umap.<source_space>.
#' @param n_neighbors UMAP neighborhood size.
#' @param min_dist UMAP minimum distance.
#' @param metric Distance metric passed to uwot.
#' @param nn_method Nearest-neighbor backend. 'nndescent' requires rnndescent; 'fnn' requires FNN; 'annoy' uses uwot's Annoy backend.
#' @param spread UMAP spread parameter.
#' @param seed Integer random seed used to make stochastic computation reproducible.
#' @param verbose Whether the underlying engine emits progress output.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$model` (`model_ref`): Reference to the fitted UMAP model.; `outputs$space_2d` (`space_2d`): The fitted 2D embedding space id.. Promotion eligibility is declared by the operation catalog.
NULL

#' @name wb_op_umap_transform
#' @aliases wb_op_umap_transform
#' @description Project cells into an existing UMAP using a stored model.
#' @param bundle Open `scworkbench_bundle` that owns input storage, output registration, and provenance.
#' @param model_space_id Registered model-space identifier used to locate a stored projection model.
#' @param in_space_id Registered input-space identifier expected by the stored projection model.
#' @param cells Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.
#' @param cell_set Named bundle cell set used to resolve the analysis universe.
#' @param dims Dims to use from the input space (e.g. 2:30).
#' @param space_id_out New output space ID. Required when the fitted space already participates in promoted provenance.
#' @param overwrite Overwrite existing projected coordinates only in unbound staging/development space.
#' @param ... Additional engine-specific arguments accepted by this wrapper.
#' @details For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. The runtime catalog declares: `outputs$space_2d` (`space_2d`): Projected x/y in the target UMAP space.. Promotion eligibility is declared by the operation catalog.
NULL

