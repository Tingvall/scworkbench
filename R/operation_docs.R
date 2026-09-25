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

