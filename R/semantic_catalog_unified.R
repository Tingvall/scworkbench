# Unified semantic search/planning catalog.

.wb_semantic_record_text <- function(parts) {
  parts <- unlist(parts, recursive = TRUE, use.names = FALSE)
  parts <- as.character(parts[!is.na(parts)])
  parts <- parts[nzchar(parts)]
  paste(unique(parts), collapse = "\n")
}

.wb_semantic_record <- function(record_id, record_type, name, title, description,
                                search_text, tags = character(0), payload = list()) {
  list(
    record_id = as.character(record_id)[1],
    record_type = as.character(record_type)[1],
    name = as.character(name)[1],
    title = as.character(title %||% "")[1],
    description = as.character(description %||% "")[1],
    search_text = .wb_semantic_record_text(search_text),
    tags = as.character(tags %||% character(0)),
    payload = payload %||% list()
  )
}

.wb_semantic_edge <- function(from, to, edge_type, label = NULL) {
  list(
    from = as.character(from)[1],
    to = as.character(to)[1],
    edge_type = as.character(edge_type)[1],
    label = as.character(label %||% edge_type)[1]
  )
}

.wb_semantic_kind <- function(x) {
  k <- as.character(x %||% "")[1]
  if (!nzchar(k)) return("")
  sub(":.*$", "", k)
}

.wb_parameter_semantics_entries <- function() {
  list(
    list(parameter_name = "cell_set", title = "Cell Set / Analysis Universe", category = "selection", description = "Restricts the cells considered by an op. This is a biological and computational universe choice, not a cosmetic filter.", applies_to = "op inputs", affects = c("cell inclusion", "statistics", "plots", "runtime"), guidance = c("Use a biologically justified set for focused analysis.", "Use all/core intentionally; changing the set can change effect sizes, trajectory curves, and enrichment."), aliases = c("cells", "cell_ids")),
    list(parameter_name = "target_cell_set", title = "Target Derived Cell Set", category = "selection", description = "Stable bundle name assigned to a newly materialized derived cell universe.", applies_to = "cell-set derivation params", affects = c("bundle registry", "downstream op inputs", "claim auditability"), guidance = c("Use meaningful names for claim-supporting universes.", "Downstream promoted runs should consume this named set rather than a raw cell_id vector."), aliases = c("output_cell_set", "derived_cell_set")),
    list(parameter_name = "role", title = "Cell-Set Lifecycle Role", category = "selection_lifecycle", description = "Declared purpose of a cell set, such as analysis_universe, exclusion_set, endpoint_set, annotation, diagnostic, or temporary.", applies_to = "cell-set derivation params", affects = c("visibility", "interpretation", "agent planning"), guidance = c("Use analysis_universe for claim-supporting restriction sets.", "Use temporary for exploratory sets that should not be interpreted as accepted state."), aliases = c("cell_set_role")),
    list(parameter_name = "status", title = "Cell-Set Lifecycle Status", category = "selection_lifecycle", description = "Declared maturity of a cell set, such as candidate, accepted, superseded, rejected, active, or temporary.", applies_to = "cell-set derivation params", affects = c("visibility", "interpretation", "audit state"), guidance = c("Use candidate while evaluating a restriction.", "Use accepted only after biological and diagnostic review."), aliases = c("cell_set_status", "lifecycle_status")),
    list(parameter_name = "matrix", title = "Matrix Input", category = "data_source", description = "Symbolic matrix primitive consumed by an op. The matrix defines the feature universe and measurement scale.", applies_to = "op inputs", affects = c("feature universe", "measurement scale", "detected features"), guidance = c("Choose RNA/ATAC/counts/normalized matrix intentionally.", "Matrix semantics are more important than the string id; future matrix metadata should formalize this."), aliases = c("matrix_id")),
    list(parameter_name = "output_matrix_id", title = "Output Matrix Identifier", category = "data_source", description = "Matrix id assigned to a newly created bundle matrix.", applies_to = "matrix-producing op params", affects = c("downstream matrix selection", "replay", "artifact interpretation"), guidance = c("Use a name that records the transform and scale, for example RNA_log1p_cp10k.", "Do not reuse an existing matrix id unless overwrite behavior is intentional."), aliases = c("new_matrix_id", "target_matrix_id")),
    list(parameter_name = "scale_factor", title = "Library-Size Normalization Scale", category = "normalization", description = "Target per-cell total used when converting raw counts to scaled expression before log transformation.", applies_to = "matrix normalization params", affects = c("expression scale", "dynamic curves", "feature-set scores"), guidance = c("10000 is the common log1p(CP10K) convention for scRNA-seq.", "Changing this value changes numeric scale but usually preserves rank-like patterns after log1p."), aliases = c("target_sum", "counts_per_cell", "cp_scale")),
    list(parameter_name = "overwrite", title = "Overwrite Existing Output", category = "mutation", description = "Controls whether an op may replace an existing persisted bundle object with the same identifier.", applies_to = "mutating op params", affects = c("bundle state", "reproducibility", "rerun safety"), guidance = c("Keep FALSE for safety when creating named outputs.", "Set TRUE only for deliberate deterministic reruns or temporary development outputs."), aliases = c("replace", "force")),
    list(parameter_name = "space", title = "Embedding / Latent Space Input", category = "data_source", description = "Symbolic space primitive used for geometry, clustering, nearest-neighbor, projection, or trajectory operations.", applies_to = "op inputs", affects = c("geometry", "neighborhoods", "trajectory shape"), guidance = c("Use a space whose dimensions represent the biology under study.", "Changing space can change distances, branches, and inferred progress."), aliases = c("space_id", "fit_space", "plot_space")),
    list(parameter_name = "model", title = "Model Reference Input", category = "data_source", description = "Reference to a fitted model or trajectory object used by downstream projection/smoothing/dynamics ops.", applies_to = "op inputs", affects = c("pseudotime", "lineage keys", "projection semantics"), guidance = c("Model provenance defines the biological orientation and branch structure.", "Do not treat models from different methods as interchangeable without checking semantics."), aliases = c("model_ref")),
    list(parameter_name = "pseudotime", title = "Pseudotime Vector Input", category = "trajectory", description = "Continuous per-cell progress coordinate, usually inferred by a trajectory method or path-scoring op.", applies_to = "op inputs", affects = c("ordering", "trend tests", "dynamic classes"), guidance = c("Pseudotime is relative to its root/orientation.", "Compare methods only after aligning orientation and intersecting cells when needed."), aliases = c("trajectory_time", "progress")),
    list(parameter_name = "trajectory_fit_id", title = "Trajectory Fit Identity", category = "trajectory", description = "Stable identity binding trajectory-derived artifacts emitted from one fit, including model_ref, pseudotime, lineage weights, and projected paths.", applies_to = "trajectory artifacts and params", affects = c("lineage label meaning", "artifact compatibility", "provenance validation"), guidance = c("Lineage labels such as L1 are only meaningful within one trajectory_fit_id.", "Do not combine pseudotime, weights, model, or paths across fit families without an explicit mapping operation."), aliases = c("trajectory_family_id", "fit_family_id")),
    list(parameter_name = "trajectory_composite_id", title = "Trajectory Composite Identity", category = "trajectory", description = "Stable identity for a derived trajectory assembled from separately fitted parent trajectory segments.", applies_to = "segmented trajectory join outputs", affects = c("composite pseudotime interpretation", "parent segment provenance", "downstream trajectory dynamics"), guidance = c("A trajectory_composite_id is not a trajectory_fit_id and does not imply one merged model.", "Use parent segment metadata to inspect which fit families contributed to the composite."), aliases = c("composite_trajectory_id", "segmented_trajectory_id")),
    list(parameter_name = "source_kind", title = "Trajectory Segment Source Kind", category = "trajectory", description = "Declares how a trajectory segment was generated. Implemented source kinds are fitted_model and space_path_bridge; graph_path_bridge, imported_pseudotime, manual_pseudotime, and composite are reserved until adapters exist.", applies_to = "trajectory segment params and manifests", affects = c("claim boundaries", "compatibility validation", "auditability"), guidance = c("Do not infer source kind from labels.", "Curated/manual/imported segments are reserved and must not be claimed as implemented until a segment adapter exists.", "Bridge segments must be declared rather than hidden as fitted models."), aliases = c("segment_source_kind")),
    list(parameter_name = "source_engine", title = "Trajectory Segment Source Engine", category = "trajectory", description = "Declares the engine or source family that produced a segment, such as slingshot, monocle3, palantir, space_path, manual, imported, graph, or unknown.", applies_to = "trajectory segment params and manifests", affects = c("methods text", "source-specific interpretation", "agent planning"), guidance = c("Use source_engine with source_kind to distinguish fitted models from bridge or imported segments.", "Unknown is allowed but less useful for audit."), aliases = c("segment_source_engine")),
    list(parameter_name = "join_policy", title = "Trajectory Segment Join Policy", category = "trajectory", description = "Rule used to convert segment-local pseudotimes into one composite pseudotime.", applies_to = "trajectory_segment_join params", affects = c("waypoint handling", "composite scale", "overlap interpretation"), guidance = c("exact_boundary_collapse maps adjacent overlap cells to the shared boundary without averaging.", "Unsupported policies fail explicitly.", "Report the join policy when using composite pseudotime for dynamics."), aliases = c("trajectory_join_policy", "overlap_policy", "boundary_policy")),
    list(parameter_name = "pseudotime_direction", title = "Pseudotime Direction", category = "trajectory", description = "Controls whether pseudotime is used as provided or inverted before binning, curve metrics, and class assignment.", applies_to = "op params", affects = c("early/late interpretation", "turns_on/turns_off labels", "report captions"), guidance = c("Set this so early and late correspond to the biological start and endpoint.", "Inversion changes interpretation, not the underlying cell scores."), aliases = c("orientation", "direction")),
    list(parameter_name = "pseudotime_key", title = "Pseudotime Key", category = "trajectory", description = "Selects the key/lineage from an explicit cell_vector_family pseudotime input.", applies_to = "op params", affects = c("cell ordering", "lineage identity", "curve labels"), guidance = c("Required when explicit pseudotime contains multiple keys.", "Do not assume equal key names across unrelated trajectory fits or composites."), aliases = c("lineage_key", "trajectory_key")),
    list(parameter_name = "membership", title = "Pseudotime Membership Filter", category = "selection", description = "Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells before dynamics are computed.", applies_to = "op params", affects = c("analysis universe", "cell counts", "curve stability"), guidance = c("Use membership to restrict composite trajectories to their intended cell universe.", "Report n_membership_cells and n_cells_used from fit_summary."), aliases = c("trajectory_membership", "cell_filter")),
    list(parameter_name = "start_label", title = "Biological Start Label", category = "trajectory", description = "Human-readable label for the intended biological start of a trajectory or dynamics analysis.", applies_to = "op params", affects = c("metadata", "reports", "interpretation"), guidance = c("Use this to make orientation explicit in reports.", "This records intent; it does not root the trajectory by itself."), aliases = c("root_label", "early_label")),
    list(parameter_name = "end_label", title = "Biological End Label", category = "trajectory", description = "Human-readable label for the intended biological endpoint of a trajectory or dynamics analysis.", applies_to = "op params", affects = c("metadata", "reports", "interpretation"), guidance = c("Use this to make endpoint interpretation explicit.", "This records intent; it does not alter model geometry by itself."), aliases = c("terminal_label", "late_label")),
    list(parameter_name = "lineage", title = "Lineage Subset", category = "trajectory", description = "Restricts analysis to one or more lineage/path keys from a trajectory, relation, or path family.", applies_to = "op params", affects = c("branch selection", "curve counts", "reported dynamics"), guidance = c("Use lineage keys that are present in the upstream model/artifact.", "Different methods may use different lineage/branch key semantics."), aliases = c("branch", "path_id", "lineage_id")),
    list(parameter_name = "score_method", title = "Feature-Set Scoring Method", category = "signature", description = "Defines how member features are collapsed into a per-cell or per-bin feature-set score.", applies_to = "op params", affects = c("score scale", "curve shape", "dynamic ranking"), guidance = c("Mean/sum depend on expression scale and set size.", "Rank-based methods reduce scale sensitivity but change interpretation."), aliases = c("scoring", "signature_score_method")),
    list(parameter_name = "namespace", title = "Feature-Set Namespace", category = "signature", description = "Selects the registered collection of feature sets to screen or score.", applies_to = "op params", affects = c("tested hypotheses", "multiple testing universe", "discovery scope"), guidance = c("Treat namespace as the biological hypothesis library.", "Report the namespace because it defines what could have been discovered."), aliases = c("gene_set_namespace", "collection")),
    list(parameter_name = "feature_sets", title = "Feature-Set Subset", category = "signature", description = "Optional restriction to named feature sets within a namespace.", applies_to = "op params", affects = c("screening universe", "reported terms"), guidance = c("Use NULL for broad discovery.", "Use explicit subsets for targeted validation."), aliases = c("gene_sets", "signatures")),
    list(parameter_name = "source_path", title = "Feature-Set Source Path", category = "import", description = "File-backed source for feature-set imports, such as GMT, RDS list/data.frame, or CSV-style table.", applies_to = "feature-set import params", affects = c("imported library", "provenance", "replay"), guidance = c("Use file-backed imports for agent/session execution so provenance can point to the source.", "Record source_id and source_version when the path alone is not a durable library identity."), aliases = c("gene_set_file", "gmt_path")),
    list(parameter_name = "source_format", title = "Feature-Set Source Format", category = "import", description = "Parser choice for a feature-set import source.", applies_to = "feature-set import params", affects = c("column interpretation", "wide versus long parsing", "library import validity"), guidance = c("Use auto for ordinary .gmt and .rds files.", "Set explicitly when a file extension is ambiguous."), aliases = c("format", "input_format")),
    list(parameter_name = "split_by_collection", title = "Split Feature-Set Namespace By Collection", category = "import", description = "Controls whether broad gene-set libraries are split into collection/subcollection namespaces during import.", applies_to = "feature-set import params", affects = c("namespace granularity", "screening universe", "multiple testing universe"), guidance = c("Use TRUE for broad mixed libraries such as MSigDB when collection/subcollection labels are meaningful.", "Keep WikiPathways or focused custom libraries in their own namespace unless splitting adds biological clarity."), aliases = c("split_namespace", "collection_split")),
    list(parameter_name = "gene_id_type", title = "Gene Identifier Type", category = "import", description = "Records the identifier convention used by imported feature-set genes.", applies_to = "feature-set import params", affects = c("mapping interpretation", "cross-species reliability", "QC interpretation"), guidance = c("Use explicit labels such as gene_symbol or ensembl_id when known.", "The current import path matches against bundle feature IDs; it does not perform synonym or ortholog mapping."), aliases = c("feature_id_type", "id_type")),
    list(parameter_name = "source_matrix_id", title = "Source Matrix Identifier", category = "matrix_transfer", description = "Matrix id that owns the source matrix-scoped feature-set namespace or other transferable registry state.", applies_to = "matrix transfer params", affects = c("source feature universe", "registry provenance", "transfer validity"), guidance = c("Use a matrix whose feature IDs define the existing feature-set memberships.", "Do not use this for cross-feature-type conversion; that requires an explicit mapping artifact."), aliases = c("from_matrix", "source_matrix")),
    list(parameter_name = "target_matrix_id", title = "Target Matrix Identifier", category = "matrix_transfer", description = "Matrix id that will receive transferred feature-set memberships after mirror or intersect validation.", applies_to = "matrix transfer params", affects = c("target feature universe", "retained features", "downstream namespace availability"), guidance = c("Use mirror only when source and target feature universes are identical.", "Use intersect when feature universes overlap and loss should be recorded."), aliases = c("to_matrix", "target_matrix")),
    list(parameter_name = "target_namespace", title = "Target Feature-Set Namespace", category = "matrix_transfer", description = "Optional namespace assigned to transferred feature sets on the target matrix.", applies_to = "feature-set transfer params", affects = c("downstream namespace selection", "provenance readability"), guidance = c("Leave NULL to preserve source namespace.", "Set explicitly when keeping raw-count and normalized-matrix namespaces separate is useful."), aliases = c("destination_namespace")),
    list(parameter_name = "min_retained_features", title = "Minimum Retained Features", category = "matrix_transfer", description = "Minimum number of source feature-set members that must remain valid on a target matrix during transfer.", applies_to = "feature-set transfer params", affects = c("intersect transfer rejection", "screening universe quality"), guidance = c("Use with mode='intersect' to avoid transferring nearly empty sets.", "For mode='mirror' this should normally be trivially satisfied."), aliases = c("min_transfer_features")),
    list(parameter_name = "min_retained_fraction", title = "Minimum Retained Fraction", category = "matrix_transfer", description = "Minimum fraction of source feature-set members that must remain valid on a target matrix during transfer.", applies_to = "feature-set transfer params", affects = c("lossy transfer rejection", "QC stringency"), guidance = c("Use to prevent broad lossy transfers from silently changing gene-set meaning.", "This is not a biological mapping confidence score; it only measures retained feature IDs."), aliases = c("transfer_fraction")),
    list(parameter_name = "signal_keys", title = "Signal Key Subset", category = "signal", description = "Optional restriction to selected keys in a cell_vector_family, such as UCell signatures or chromVAR motifs.", applies_to = "op params", affects = c("screening universe", "reported signals"), guidance = c("Use NULL for broad signal-family screening.", "Use explicit keys for targeted follow-up."), aliases = c("keys", "signature_keys", "motif_keys")),
    list(parameter_name = "n_bins", title = "Pseudotime Bin Count", category = "trajectory", description = "Number of bins used to aggregate cells along pseudotime before curve summaries and dynamics metrics.", applies_to = "op params", affects = c("curve resolution", "noise", "runtime"), guidance = c("More bins preserve detail but increase sparsity/noise.", "Fewer bins smooth curves but may hide sharp transitions."), aliases = c("bins")),
    list(parameter_name = "min_cells_per_bin", title = "Minimum Cells Per Bin", category = "filtering", description = "Minimum number of cells required for a pseudotime bin to be retained.", applies_to = "op params", affects = c("curve support", "missing bins", "confidence"), guidance = c("Higher values make curves more stable but can remove sparse terminal regions.", "Report this when interpreting missing or truncated curves."), aliases = c("min_bin_cells")),
    list(parameter_name = "summary_fun", title = "Bin Summary Function", category = "summary", description = "Statistic used to summarize cell-level values within each bin.", applies_to = "op params", affects = c("curve values", "outlier sensitivity"), guidance = c("Mean is sensitive to outliers and abundance shifts.", "Median is more robust but may compress sparse expression."), aliases = c("summary_function")),
    list(parameter_name = "min_amplitude", title = "Minimum Curve Amplitude Filter", category = "filtering", description = "Minimum observed/smoothed curve range required for a signal or feature set to pass report filters.", applies_to = "op params", affects = c("reported dynamics", "noise filtering"), guidance = c("This is a reporting/filter threshold, not a p-value.", "Set it relative to score scale; amplitude units differ between mean expression, UCell, chromVAR, and ranks."), aliases = c("amplitude_threshold")),
    list(parameter_name = "class_min_amplitude", title = "Minimum Amplitude For Non-Flat Class", category = "classification", description = "Minimum curve range required before assigning a non-flat dynamic class.", applies_to = "op params", affects = c("flat versus dynamic classes", "turns_on/turns_off/transient calls"), guidance = c("Use this to avoid classifying tiny numerical wiggles as biology.", "Keep distinct from min_amplitude if you want permissive reporting but conservative classes."), aliases = c("dynamic_class_amplitude")),
    list(parameter_name = "min_bins_observed", title = "Minimum Observed Bins Filter", category = "filtering", description = "Minimum number of retained pseudotime bins required for a curve to pass filters.", applies_to = "op params", affects = c("curve completeness", "terminal-region confidence"), guidance = c("Higher values reduce fragmentary curves.", "Sparse branches may fail this filter even if biologically interesting."), aliases = c("min_bins")),
    list(parameter_name = "min_features_detected", title = "Minimum Detected Set Members", category = "filtering", description = "Minimum number of feature-set members detected in the matrix before a set passes filters.", applies_to = "op params", affects = c("feature-set validity", "dropout robustness"), guidance = c("Use this to avoid interpreting gene sets represented by too few measured genes.", "Important for targeted panels and cross-species or sparse feature spaces."), aliases = c("min_detected_genes")),
    list(parameter_name = "min_detected_fraction", title = "Minimum Detected Set Fraction", category = "filtering", description = "Minimum fraction of feature-set members detected in the matrix before a set passes filters.", applies_to = "op params", affects = c("feature-set validity", "dropout robustness"), guidance = c("Complements min_features_detected by scaling with set size.", "Useful when screening gene sets of very different sizes."), aliases = c("detected_fraction")),
    list(parameter_name = "min_mean_score", title = "Minimum Mean Score Filter", category = "filtering", description = "Minimum mean smoothed curve score required before a gene set or signal passes report filters.", applies_to = "op params", affects = c("low-abundance filtering", "reported dynamics"), guidance = c("Use this to avoid over-interpreting tiny but smooth low-expression changes.", "Thresholds are score-scale dependent; keep disabled for broad discovery if unsure."), aliases = c("mean_score_threshold")),
    list(parameter_name = "min_max_score", title = "Minimum Maximum Score Filter", category = "filtering", description = "Minimum maximum smoothed curve score required before a gene set or signal passes report filters.", applies_to = "op params", affects = c("low-abundance filtering", "reported dynamics"), guidance = c("For log1p CP10K mean scores, a small threshold such as 0.1 can separate robust programs from near-zero wiggles.", "Do not reuse the same number for UCell, chromVAR, or other score scales without checking distributions."), aliases = c("max_score_threshold")),
    list(parameter_name = "min_signal_to_noise", title = "Minimum Signal-To-Noise Filter", category = "filtering", description = "Minimum amplitude divided by mean bootstrap standard error required before a curve passes filters.", applies_to = "op params", affects = c("uncertainty-aware filtering", "reported dynamics"), guidance = c("Requires bootstrap-derived standard errors to be meaningful.", "Use as a support filter, not as a formal p-value."), aliases = c("snr_threshold", "min_snr")),
    list(parameter_name = "low_abundance_max_score", title = "Low-Abundance Flag Threshold", category = "filtering", description = "Maximum score threshold below which dynamic-looking curves are flagged as low abundance.", applies_to = "op params", affects = c("interpretation", "report triage"), guidance = c("This flag warns about low-expression dynamics without removing them by default.", "Set relative to the selected matrix or score method."), aliases = c("low_expression_threshold", "low_signal_threshold")),
    list(parameter_name = "on_off_min_delta", title = "On/Off Delta Threshold", category = "classification", description = "Minimum late-minus-early absolute difference required for turns_on or turns_off classes.", applies_to = "op params", affects = c("turns_on calls", "turns_off calls"), guidance = c("Interpret relative to score scale.", "A stricter threshold reduces weak monotonic calls."), aliases = c("delta_threshold")),
    list(parameter_name = "monotonic_min_abs_rho", title = "Monotonicity Threshold", category = "classification", description = "Minimum absolute Spearman correlation with pseudotime required for monotonic on/off classes.", applies_to = "op params", affects = c("turns_on calls", "turns_off calls", "transient calls"), guidance = c("Higher values require cleaner monotonic behavior.", "Transient or multi-phase curves should not be forced into monotonic classes."), aliases = c("rho_threshold")),
    list(parameter_name = "smooth_method", title = "Curve Smoothing Method", category = "smoothing", description = "Optional smoother applied to binned curves before metrics and class assignment.", applies_to = "op params", affects = c("curve shape", "classification", "confidence bands"), guidance = c("Smoothing can reveal broad dynamics but can also erase sharp transitions.", "Report the method because it affects classes."), aliases = c("smoother")),
    list(parameter_name = "loess_span", title = "LOESS Span", category = "smoothing", description = "Controls the locality of LOESS smoothing when smooth_method is loess.", applies_to = "op params", affects = c("smoothness", "local transitions"), guidance = c("Smaller span follows local variation more closely.", "Larger span produces broader, smoother trends."), aliases = c("span")),
    list(parameter_name = "bootstrap_n", title = "Bootstrap Replicate Count", category = "uncertainty", description = "Number of bootstrap resamples per bin for confidence intervals; zero disables bootstrap intervals.", applies_to = "op params", affects = c("confidence bands", "runtime"), guidance = c("Use for report-quality uncertainty bands.", "Large values increase runtime."), aliases = c("n_bootstrap")),
    list(parameter_name = "ci_level", title = "Confidence Interval Level", category = "uncertainty", description = "Nominal confidence level for bootstrap confidence bands.", applies_to = "op params", affects = c("confidence band width"), guidance = c("Higher levels produce wider intervals.", "Only meaningful when bootstrap_n is greater than zero."), aliases = c("confidence_level")),
    list(parameter_name = "n_permutations", title = "Empirical Permutation Count", category = "statistics", description = "Number of score-pseudotime permutations used to estimate empirical dynamic-score p-values.", applies_to = "trajectory dynamics op params", affects = c("p_dynamic", "q_dynamic", "runtime"), guidance = c("Use 0 for fast exploratory discovery.", "Use hundreds to thousands for final reports when runtime is acceptable.", "Permutation p-values support dynamic-score ranking but do not replace effect-size and abundance filters."), aliases = c("n_perm", "permutations")),
    list(parameter_name = "permutation_seed", title = "Permutation Random Seed", category = "reproducibility", description = "Seed used for empirical score-pseudotime permutation tests.", applies_to = "trajectory dynamics op params", affects = c("p_dynamic reproducibility", "q_dynamic reproducibility"), guidance = c("Set explicitly for replayable reports.", "Changing the seed can slightly change empirical p-values when n_permutations is modest."), aliases = c("perm_seed")),
    list(parameter_name = "p_adjust_method", title = "P-Value Adjustment Method", category = "statistics", description = "Multiple-testing correction method used to convert empirical p_dynamic values into q_dynamic values.", applies_to = "statistical op params", affects = c("FDR calls", "reported statistical support"), guidance = c("BH is the usual default for discovery-style FDR control.", "Correction is across the screened feature-set universe, so namespace/subset choice matters."), aliases = c("fdr_method", "multiple_testing_method")),
    list(parameter_name = "mad_multiplier", title = "MAD Distance Inclusion Multiplier", category = "trajectory_inclusion", description = "Threshold multiplier for median absolute deviation distance filters around a trajectory/path.", applies_to = "workflow or op params", affects = c("included cells", "trajectory tightness", "terminal contamination"), guidance = c("Lower values create a tighter trajectory tube and exclude more distant cells.", "Interpret relative to the embedding/space; unlike fixed distance thresholds, MAD adapts to scale.", "Not yet universal in op interfaces; include when route inclusion becomes a first-class op parameter."), aliases = c("mad_threshold", "distance_mad_multiplier")),
    list(parameter_name = "top_n", title = "Top-N Retention", category = "reporting", description = "Number of top-ranked records retained for compact outputs or reports.", applies_to = "op params", affects = c("report size", "visible discoveries"), guidance = c("Does not usually change the full underlying calculation unless explicitly documented.", "Use larger values for exploratory reports."), aliases = c("n_top")),
    list(parameter_name = "seed", title = "Random Seed", category = "reproducibility", description = "Seed used for stochastic algorithms or resampling.", applies_to = "op params", affects = c("reproducibility", "stochastic outputs"), guidance = c("Set explicitly for replayable reports.", "Changing seed can affect stochastic fits, bootstraps, or approximations."), aliases = c("random_seed", "bootstrap_seed"))
  )
}

#' Export Parameter Semantics Catalog
#'
#' Returns reusable semantic descriptions for recurring op inputs and
#' parameters. This complements op-specific help text with shared biological
#' and computational meaning.
#'
#' @return A named list with parameter semantic records.
#' @export
wb_parameter_semantics_catalog <- function() {
  params <- .wb_parameter_semantics_entries()
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.parameter_semantics_catalog.v1",
    generated_at = .wb_catalog_generated_at(),
    parameter_count = length(params),
    parameters = params
  ))
}

.wb_parameter_semantics_reference_lines <- function(catalog) {
  .wb_semantic_reference_lines(
    title = "scworkbench Parameter Semantics Catalog",
    generator = "wb_parameter_semantics_catalog()",
    count_label = "Parameter count",
    count = catalog$parameter_count,
    records = catalog$parameters,
    id_field = "parameter_name",
    section_field = "category",
    body_fn = function(x) {
      c(
        paste0("Title: ", as.character(x$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(x$description %||% "")[1]),
        "",
        paste0("Applies to: ", as.character(x$applies_to %||% "")[1]),
        "",
        paste0("Affects: ", paste(as.character(x$affects %||% character(0)), collapse = ", ")),
        "",
        "Guidance:",
        if (length(x$guidance %||% character(0))) paste0("- ", as.character(x$guidance)) else "- (unspecified)",
        "",
        paste0("Aliases: ", paste(as.character(x$aliases %||% character(0)), collapse = ", "))
      )
    }
  )
}

#' Write Parameter Semantics Catalog Reference Files
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the parameter semantics catalog.
#' @export
wb_write_parameter_semantics_reference <- function(path_md = "docs/parameter_semantics_reference.md",
                                                   path_json = "docs/parameter_semantics_catalog.json") {
  catalog <- wb_parameter_semantics_catalog()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    .wb_write_markdown_reference(.wb_parameter_semantics_reference_lines(catalog), path_md)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "parameter semantics catalog export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}

.wb_recipe_semantics_entries <- function() {
  list(
    list(
      recipe_id = "trajectory_geneset_dynamics_discovery",
      title = "Run gene-set dynamics along a trajectory",
      category = "trajectory_discovery",
      question = "Which biological processes turn on, turn off, or behave transiently along a trajectory?",
      description = "Screen a feature-set namespace across trajectory pseudotime and report dynamic terms plus driver genes.",
      steps = c("Inspect available feature-set namespaces with wb_feature_sets().", "Choose matrix plus either a trajectory model artifact/model_ref or an explicit pseudotime cell_vector_family.", "Run trajectory_geneset_dynamics with namespace, lineage or pseudotime_key, orientation, and filtering thresholds.", "Promote signature_table, dynamics_table, top_sets, driver_table, driver_curve_table, and fit_summary.", "Plot top dynamic terms and driver-gene curves with pseudotime_signature_line."),
      uses = c("getter:wb_feature_sets", "getter:wb_art_list", "op:trajectory_geneset_dynamics", "plot:pseudotime_signature_line", "wrangler:plot_mapper:trajectory_pseudotime_signature_line_v1", "parameter:namespace", "parameter:score_method", "parameter:pseudotime_key", "parameter:pseudotime_direction", "parameter:min_amplitude"),
      produces = c("artifact_type:obs_table:trajectory_geneset_dynamics_curve", "artifact_type:obs_table:trajectory_geneset_dynamics", "artifact_type:obs_table:trajectory_geneset_dynamics_drivers", "artifact_type:obs_table:trajectory_geneset_dynamics_driver_curve"),
      use_when = c("collaborator asks for GSEA-like discovery along pseudotime", "find metabolism/signaling/processes not preselected by marker intuition"),
      cautions = c("Gene-set universe and score_method define the biological meaning.", "Explicit pseudotime mode records its cell_vector_family source and does not invent a model_ref.", "Pseudotime orientation controls turns_on versus turns_off labels.", "Amplitude thresholds are scale-dependent filters, not p-values.")
    ),
    list(
      recipe_id = "feature_set_import_qc_then_dynamics",
      title = "Import and QC a feature-set library before trajectory screening",
      category = "trajectory_discovery",
      question = "Can this external gene-set library be used for dynamic program discovery along a trajectory?",
      description = "Import a GMT/RDS/table feature-set library into a namespace, record import provenance, QC matrix overlap, then use the namespace in trajectory_geneset_dynamics.",
      steps = c("Choose the target matrix that defines the feature universe.", "Run feature_set_import with source_path, namespace, species/gene_id_type, and source_version.", "Promote import_summary, import_manifest, and rejected_sets for auditability.", "Run feature_set_overlap_qc on the imported namespace and inspect include/exclude reasons.", "Use the accepted namespace with trajectory_geneset_dynamics and report QC artifacts alongside dynamics."),
      uses = c("op:feature_set_import", "op:feature_set_overlap_qc", "op:trajectory_geneset_dynamics", "getter:wb_feature_sets", "artifact_type:obs_table:feature_set_import_manifest", "artifact_type:obs_table:feature_set_overlap_qc", "parameter:source_path", "parameter:namespace", "parameter:split_by_collection", "parameter:min_detected_fraction"),
      produces = c("artifact_type:obs_table:feature_set_import_summary", "artifact_type:obs_table:feature_set_import_manifest", "artifact_type:obs_table:feature_set_overlap_qc", "artifact_type:obs_table:trajectory_geneset_dynamics"),
      use_when = c("collaborator sends new GSEA/MSigDB/custom gene-set library", "need to prove library coverage before screening pseudotime dynamics"),
      cautions = c("Import matching is against bundle feature IDs; synonym/ortholog mapping is not performed here.", "QC include/exclude thresholds define the screened universe and should be reported.", "Broad libraries should be split only when collection/subcollection semantics are meaningful.")
    ),
    list(
      recipe_id = "feature_set_namespace_transfer_for_normalized_matrix",
      title = "Transfer feature-set namespaces to a derived normalized matrix",
      category = "matrix_transfer",
      question = "How can feature-set libraries registered on raw counts be reused on a comparable derived matrix?",
      description = "Transfer matrix-scoped feature-set namespaces from a source matrix to a target matrix using mirror or intersect semantics before running dynamics on the target matrix.",
      steps = c("Confirm the target matrix is comparable to the source matrix and uses the same feature ID type.", "Run feature_set_namespace_transfer with source_matrix_id, target_matrix_id, namespace, and mode='mirror' for lossless derived matrices.", "Promote transfer_summary, transfer_manifest, and transfer_rejected for provenance.", "Run feature_set_overlap_qc on the target matrix/namespace before broad screening.", "Run trajectory_geneset_dynamics on the target matrix with the transferred namespace."),
      uses = c("op:feature_set_namespace_transfer", "op:feature_set_overlap_qc", "op:trajectory_geneset_dynamics", "getter:wb_feature_sets", "artifact_type:obs_table:feature_set_transfer_manifest", "parameter:source_matrix_id", "parameter:target_matrix_id", "parameter:namespace", "parameter:target_namespace"),
      produces = c("artifact_type:obs_table:feature_set_transfer_summary", "artifact_type:obs_table:feature_set_transfer_manifest", "artifact_type:obs_table:feature_set_overlap_qc", "artifact_type:obs_table:trajectory_geneset_dynamics"),
      use_when = c("raw-count feature sets need to be reused on log-normalized RNA", "derived matrices preserve feature IDs but feature-set registry is matrix-scoped"),
      cautions = c("This is not ortholog/synonym/gene-to-peak/motif-to-TF mapping.", "mode='mirror' requires identical feature universes.", "mode='intersect' changes gene-set membership and must be reported with loss metrics.")
    ),
    list(
      recipe_id = "trajectory_signal_dynamics_discovery",
      title = "Run signal dynamics along a trajectory",
      category = "trajectory_discovery",
      question = "Which precomputed cell-level signals are dynamic along pseudotime?",
      description = "Rank UCell, chromVAR, module-score, or other cell_vector_family signals by dynamic behavior along a trajectory.",
      steps = c("Load or identify a cell_vector_family artifact containing signals.", "Choose either a trajectory model artifact/model_ref or an explicit pseudotime cell_vector_family plus lineage/pseudotime_key and orientation.", "Run trajectory_signal_dynamics with signal_keys or all keys.", "Promote signal_table, dynamics_table, top_signals, and fit_summary.", "Plot top signal curves with pseudotime_signature_line."),
      uses = c("getter:wb_art_list", "getter:wb_read_cell_vector_family", "op:trajectory_signal_dynamics", "plot:pseudotime_signature_line", "parameter:signal_keys", "parameter:pseudotime_key", "parameter:pseudotime_direction", "parameter:min_amplitude"),
      produces = c("artifact_type:obs_table:trajectory_signal_dynamics_curve", "artifact_type:obs_table:trajectory_signal_dynamics"),
      use_when = c("UCell or chromVAR scores already exist", "screen signal families without recomputing gene-set scores"),
      cautions = c("Signal scale depends on upstream scoring method.", "Explicit pseudotime mode records its cell_vector_family source and does not invent a model_ref.", "Only compare signals with compatible score semantics.")
    ),
    list(
      recipe_id = "inspect_promoted_artifact",
      title = "Inspect a promoted artifact",
      category = "artifact_inspection",
      question = "What is this artifact and how can I use or plot it?",
      description = "Use artifact getters to inspect identity, provenance, table shape, dependencies, and compatible downstream actions.",
      steps = c("List artifacts with wb_art_list().", "Read identity/provenance using wb_art_identity_card() and wb_art_birth_certificate().", "If table-like, inspect columns with wb_art_table_info() and preview rows with wb_art_table_slice().", "Load as primitive with wb_art_load() only when payload access is needed.", "Use semantic_compatibility_graph to find compatible wranglers/plots."),
      uses = c("getter:wb_art_list", "getter:wb_art_identity_card", "getter:wb_art_birth_certificate", "getter:wb_art_table_info", "getter:wb_art_table_slice", "getter:wb_art_load", "wrangler:table:client_load_table"),
      produces = c("primitive:feature_table", "primitive:obs_table", "primitive:cell_vector", "primitive:cell_vector_family"),
      use_when = c("agent needs to decide next step from artifact id", "human wants provenance before interpretation"),
      cautions = c("Do not infer biology from artifact type alone; check source op and parameters.", "Prefer bounded table slices before loading large payloads.")
    ),
    list(
      recipe_id = "plot_ucell_on_umap",
      title = "Plot UCell signatures on UMAP",
      category = "visualization",
      question = "Where are signature-high cells located in a 2D embedding?",
      description = "Overlay one or more UCell signature scores from a cell_vector_family onto a 2D space.",
      steps = c("Run or locate ucell output signature_scores.", "Choose a 2D space with wb_spaces() or a space_2d artifact.", "Load/select the desired signature key from the cell_vector_family.", "Use wb_wrangle_plot_dataset for embedding_overlay or plot via compatible client.", "Inspect distribution with violin if group comparison is needed."),
      uses = c("op:ucell", "getter:wb_spaces", "getter:wb_read_cell_vector_family", "plot:embedding_overlay", "plot:violin", "wrangler:plot_mapper:space2d_overlay_v1", "wrangler:plot_mapper:cell_vector_violin_v1", "parameter:space"),
      produces = c("artifact_type:cell_vector_family"),
      use_when = c("visualize signature activity spatially", "check whether a gene-set score follows known cell states"),
      cautions = c("UCell scores are rank-based within cells; interpret as relative signature activity.", "Embedding overlay is a visualization, not a statistical test.")
    ),
    list(
      recipe_id = "plot_trajectory_on_umap",
      title = "Plot selected trajectory curves on UMAP",
      category = "visualization",
      question = "How does a selected trajectory or lineage sit in the 2D embedding?",
      description = "Combine a 2D space with path_2d_family curves and pseudotime/cell overlays for trajectory diagnostics.",
      steps = c("Locate trajectory curve artifact or project model/path into 2D.", "For segmented composites, use trajectory_segment_path_join to derive display geometry from parent segment paths.", "Choose only the selected lineage/path used for dynamics if multiple are present.", "Plot full candidate cells in muted color and selected curve in foreground.", "Overlay pseudotime or endpoint labels as needed.", "Use diagnostics to avoid showing unused branches in dynamics figures."),
      uses = c("artifact_type:path_2d_family", "op:slingshot_project", "op:monocle3_project", "op:palantir_project", "op:space_path_project_2d", "op:trajectory_segment_path_join", "plot:embedding_overlay", "primitive:path_2d_family", "parameter:lineage"),
      produces = c("artifact_type:path_2d_family"),
      use_when = c("validate trajectory geometry", "prepare collaborator-facing trajectory diagnostics"),
      cautions = c("2D curves are display projections and may not equal high-dimensional geometry.", "Composite display paths are derived geometry, not merged fitted models.", "If dynamics use one lineage, do not display unrelated lineages as if they were used.")
    ),
    list(
      recipe_id = "mixed_source_composite_trajectory",
      title = "Build a mixed-source composite trajectory",
      category = "trajectory_composition",
      question = "How can fitted trajectory segments and bridge/path segments be joined into one auditable pseudotime axis?",
      description = "Create source-declared trajectory segments, join them with exact boundary collapse, then use the composite pseudotime in explicit-pseudotime dynamics.",
      steps = c("Create fitted trajectory segments with trajectory_segment_from_artifacts or bridge segments with trajectory_space_path_segment.", "Ensure every segment declares source_kind, source_engine, lineage key, order, labels, and parent artifacts.", "Run trajectory_segment_join with join_policy='exact_boundary_collapse'.", "Optionally run trajectory_segment_path_join for UMAP display geometry.", "Use composite_pseudotime_unit_segment or composite_pseudotime_cell_weighted_0_1 plus composite_membership in trajectory_geneset_dynamics or trajectory_signal_dynamics explicit-pseudotime mode."),
      uses = c("op:trajectory_segment_from_artifacts", "op:trajectory_space_path_segment", "op:trajectory_segment_join", "op:trajectory_segment_path_join", "op:trajectory_geneset_dynamics", "op:trajectory_signal_dynamics", "parameter:source_kind", "parameter:source_engine", "parameter:join_policy", "parameter:pseudotime_key"),
      produces = c("artifact_type:cell_vector_family", "artifact_type:cell_vector", "artifact_type:obs_table:trajectory_segment_join_manifest", "artifact_type:obs_table:trajectory_segment_local_membership", "artifact_type:path_2d_family"),
      use_when = c("a biological route must pass through waypoints", "one fitted trajectory cannot represent all route intervals", "a curated space-path bridge is needed between fitted segments"),
      cautions = c("A composite trajectory is not one fitted model.", "Only fitted_model and space_path_bridge adapters are implemented currently; manual/imported/graph/composite source kinds are reserved.", "Display paths are not analytical pseudotime.")
    ),
    list(
      recipe_id = "de_to_pathway_report",
      title = "Differential expression to pathway report",
      category = "differential_analysis",
      question = "Which pathways explain differential genes between two cell sets?",
      description = "Run DE between two sets, convert ranked/significant features to enrichment queries, and plot top pathway terms.",
      steps = c("Define or choose group_a and group_b cell sets.", "Run de_wilcox on the selected matrix.", "Promote de_table and inspect top features.", "Run pathway_enrich on selected up/down genes or ranked query policy.", "Plot pathway_bar and volcano summaries."),
      uses = c("op:de_wilcox", "op:pathway_enrich", "plot:volcano", "plot:pathway_bar", "artifact_type:feature_table:de_wilcox", "artifact_type:obs_table:pathway_enrich", "parameter:cell_set", "parameter:matrix", "parameter:namespace"),
      produces = c("artifact_type:feature_table:de_wilcox", "artifact_type:obs_table:pathway_enrich"),
      use_when = c("compare two biological groups", "derive pathway interpretation from DE"),
      cautions = c("Cell-set definitions control the comparison.", "Pathway output depends on the selected feature universe and query policy.")
    ),
    list(
      recipe_id = "cluster_markers_pathways",
      title = "Cluster to markers to pathways",
      category = "discovery",
      question = "What are the marker genes and pathway programs for clusters?",
      description = "Cluster cells in a chosen space, find top markers per cluster, and optionally enrich each cluster marker list.",
      steps = c("Run leiden on a biologically appropriate space and cell_set.", "Run markers_topn using the cluster labels.", "Promote marker table.", "Optionally run pathway_enrich per cluster marker subset.", "Plot dotplot, ranked lollipop, or pathway bars."),
      uses = c("op:leiden", "op:markers_topn", "op:pathway_enrich", "plot:dotplot", "plot:ranked_lollipop", "plot:pathway_bar", "parameter:space", "parameter:cell_set", "parameter:matrix"),
      produces = c("artifact_type:cell_vector", "artifact_type:feature_table:markers_topn", "artifact_type:obs_table:pathway_enrich"),
      use_when = c("explore unknown populations", "summarize cluster identities"),
      cautions = c("Cluster resolution changes biological granularity.", "Markers reflect selected matrix and cell universe.")
    ),
    list(
      recipe_id = "semantic_next_steps_from_artifact",
      title = "Find next steps from an artifact",
      category = "agent_planning",
      question = "Given an artifact, what can the agent do next?",
      description = "Use the semantic catalog and compatibility graph to find downstream getters, wranglers, plots, and ops compatible with the artifact primitive type.",
      steps = c("Inspect artifact_type and primitive_kind.", "Find graph edges from artifact_type to primitive via loads_as.", "Follow primitive to wranglers via wrangled_by and plots via feeds_plot.", "Follow primitive to ops via consumed_by for downstream analysis.", "Return candidates with provenance caveats."),
      uses = c("getter:wb_art_identity_card", "getter:wb_art_load", "artifact_type:cell_vector", "primitive:cell_vector", "wrangler:table:client_load_table", "plot:embedding_overlay"),
      produces = c("plot:embedding_overlay", "plot:violin", "plot:ranked_lollipop"),
      use_when = c("agent receives artifact id and needs actionable options", "semantic search needs planning, not just text matches"),
      cautions = c("Compatibility means technically possible, not biologically appropriate.", "Use provenance and parameter semantics before making claims.")
    )
  )
}

#' Export Recipe Semantics Catalog
#'
#' Returns agent-facing workflow examples as searchable semantic records.
#' Recipes describe how ops, getters, artifacts, parameters, wranglers, and
#' plots are composed for common scientific tasks.
#'
#' @return A named list with recipe semantic records.
#' @export
wb_recipe_semantics_catalog <- function() {
  recipes <- .wb_recipe_semantics_entries()
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.recipe_semantics_catalog.v1",
    generated_at = .wb_catalog_generated_at(),
    recipe_count = length(recipes),
    recipes = recipes
  ))
}

.wb_recipe_semantics_reference_lines <- function(catalog) {
  .wb_semantic_reference_lines(
    title = "scworkbench Recipe Semantics Catalog",
    generator = "wb_recipe_semantics_catalog()",
    count_label = "Recipe count",
    count = catalog$recipe_count,
    records = catalog$recipes,
    id_field = "recipe_id",
    section_field = "category",
    body_fn = function(x) {
      c(
        paste0("Title: ", as.character(x$title %||% "")[1]),
        "",
        paste0("Question: ", as.character(x$question %||% "")[1]),
        "",
        paste0("Description: ", as.character(x$description %||% "")[1]),
        "",
        "Steps:",
        if (length(x$steps %||% character(0))) paste0("- ", as.character(x$steps)) else "- (unspecified)",
        "",
        "Uses:",
        if (length(x$uses %||% character(0))) paste0("- `", as.character(x$uses), "`") else "- (unspecified)",
        "",
        "Cautions:",
        if (length(x$cautions %||% character(0))) paste0("- ", as.character(x$cautions)) else "- (none)"
      )
    }
  )
}

#' Write Recipe Semantics Catalog Reference Files
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the recipe semantics catalog.
#' @export
wb_write_recipe_semantics_reference <- function(path_md = "docs/recipe_semantics_reference.md",
                                                path_json = "docs/recipe_semantics_catalog.json") {
  catalog <- wb_recipe_semantics_catalog()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    .wb_write_markdown_reference(.wb_recipe_semantics_reference_lines(catalog), path_md)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "recipe semantics catalog export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}

.wb_semantic_catalog_records <- function(bundle = NULL) {
  ops <- wb_op_catalog_semantic(bundle = bundle)$ops %||% list()
  getters <- wb_getter_catalog_semantic()$getters %||% list()
  plots <- wb_plot_catalog_semantic()$plots %||% list()
  wranglers <- wb_wrangler_catalog_semantic()$wranglers %||% list()
  primitives <- wb_primitive_catalog_semantic()$primitives %||% list()
  artifact_types <- wb_artifact_type_catalog_semantic()$artifact_types %||% list()
  parameters <- wb_parameter_semantics_catalog()$parameters %||% list()
  recipes <- wb_recipe_semantics_catalog()$recipes %||% list()

  records <- list()
  add <- function(x) records[[length(records) + 1L]] <<- x

  for (op in ops) {
    nm <- as.character(op$op_name %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("op:", nm),
      record_type = "op",
      name = nm,
      title = op$title,
      description = op$description,
      search_text = list(op$title, op$description, op$intent, op$consumes, op$produces, op$params),
      tags = c("op", as.character(op$intent %||% character(0))),
      payload = op
    ))
  }
  for (g in getters) {
    nm <- as.character(g$function_name %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("getter:", nm),
      record_type = "getter",
      name = nm,
      title = g$title,
      description = g$description,
      search_text = list(g$title, g$description, g$category, g$returns, g$arguments, g$use_when),
      tags = c("getter", as.character(g$category %||% "")),
      payload = g
    ))
  }
  for (p in plots) {
    nm <- as.character(p$plot_type %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("plot:", nm),
      record_type = "plot",
      name = nm,
      title = p$title,
      description = p$description,
      search_text = list(p$title, p$description, p$use_when, p$compatible_refs, p$required_fields, p$optional_fields),
      tags = c("plot", as.character(p$dataset_type %||% "")),
      payload = p
    ))
  }
  for (w in wranglers) {
    nm <- as.character(w$wrangler_id %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("wrangler:", nm),
      record_type = "wrangler",
      name = nm,
      title = w$title,
      description = w$description,
      search_text = list(w$title, w$description, w$consumes, w$produces, w$plot_type, w$use_when),
      tags = c("wrangler", as.character(w$category %||% ""), as.character(w$plot_type %||% "")),
      payload = w
    ))
  }
  for (p in primitives) {
    nm <- as.character(p$primitive_kind %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("primitive:", nm),
      record_type = "primitive",
      name = nm,
      title = p$title,
      description = p$description,
      search_text = list(p$title, p$description, p$shape, p$payload_level, p$use_when),
      tags = c("primitive", as.character(p$payload_level %||% "")),
      payload = p
    ))
  }
  for (a in artifact_types) {
    nm <- as.character(a$artifact_type %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("artifact_type:", nm),
      record_type = "artifact_type",
      name = nm,
      title = a$title,
      description = a$description,
      search_text = list(a$title, a$description, a$primitive_kind, a$table_type, a$entity_kind, a$use_when),
      tags = c("artifact_type", as.character(a$primitive_kind %||% ""), as.character(a$table_type %||% "")),
      payload = a
    ))
  }
  for (p in parameters) {
    nm <- as.character(p$parameter_name %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("parameter:", nm),
      record_type = "parameter",
      name = nm,
      title = p$title,
      description = p$description,
      search_text = list(p$title, p$description, p$category, p$applies_to, p$affects, p$guidance, p$aliases),
      tags = c("parameter", as.character(p$category %||% ""), as.character(p$aliases %||% character(0))),
      payload = p
    ))
  }
  for (r in recipes) {
    nm <- as.character(r$recipe_id %||% "")[1]
    add(.wb_semantic_record(
      record_id = paste0("recipe:", nm),
      record_type = "recipe",
      name = nm,
      title = r$title,
      description = r$description,
      search_text = list(r$title, r$question, r$description, r$category, r$steps, r$uses, r$produces, r$use_when, r$cautions),
      tags = c("recipe", as.character(r$category %||% ""), as.character(r$use_when %||% character(0))),
      payload = r
    ))
  }

  records
}

#' Build Semantic Compatibility Graph
#'
#' Builds deterministic graph edges between semantic records. This is the
#' planning layer under semantic search: ops consume and produce primitives,
#' artifact types load as primitives, wranglers consume primitives/artifacts,
#' and plot wranglers feed plot contracts.
#'
#' @param bundle Optional open bundle, passed through to op catalog export.
#' @return A named list containing `nodes` and `edges` records.
#' @export
wb_semantic_compatibility_graph <- function(bundle = NULL) {
  records <- .wb_semantic_catalog_records(bundle = bundle)
  node_ids <- vapply(records, function(x) as.character(x$record_id), character(1))
  record_by_id <- stats::setNames(records, node_ids)

  ops <- wb_op_catalog_semantic(bundle = bundle)$ops %||% list()
  wranglers <- wb_wrangler_catalog_semantic()$wranglers %||% list()
  artifact_types <- wb_artifact_type_catalog_semantic()$artifact_types %||% list()
  plots <- wb_plot_catalog_semantic()$plots %||% list()
  parameters <- wb_parameter_semantics_catalog()$parameters %||% list()
  recipes <- wb_recipe_semantics_catalog()$recipes %||% list()

  primitive_ids <- node_ids[grepl("^primitive:", node_ids)]
  primitive_kinds <- sub("^primitive:", "", primitive_ids)
  artifact_ids <- node_ids[grepl("^artifact_type:", node_ids)]
  plot_ids <- node_ids[grepl("^plot:", node_ids)]
  parameter_ids <- node_ids[grepl("^parameter:", node_ids)]
  parameter_names <- sub("^parameter:", "", parameter_ids)
  recipe_ids <- node_ids[grepl("^recipe:", node_ids)]
  parameter_aliases <- list()
  for (p in parameters) {
    pn <- as.character(p$parameter_name %||% "")[1]
    for (alias in unique(c(pn, as.character(p$aliases %||% character(0))))) {
      parameter_aliases[[alias]] <- pn
    }
  }

  edges <- list()
  add_edge <- function(from, to, edge_type, label = NULL) {
    if (from %in% node_ids && to %in% node_ids) {
      edges[[length(edges) + 1L]] <<- .wb_semantic_edge(from, to, edge_type, label)
    }
  }

  for (op in ops) {
    op_id <- paste0("op:", as.character(op$op_name %||% "")[1])
    for (x in op$consumes %||% list()) {
      k <- .wb_semantic_kind(x$kind)
      if (k %in% primitive_kinds) add_edge(paste0("primitive:", k), op_id, "consumed_by", paste0("input:", x$name %||% ""))
      pn <- parameter_aliases[[as.character(x$name %||% "")[1]]] %||% NULL
      if (!is.null(pn) && pn %in% parameter_names) add_edge(op_id, paste0("parameter:", pn), "has_parameter_semantics", paste0("input:", x$name %||% ""))
    }
    for (p in op$params %||% list()) {
      pn <- parameter_aliases[[as.character(p$name %||% "")[1]]] %||% NULL
      if (!is.null(pn) && pn %in% parameter_names) add_edge(op_id, paste0("parameter:", pn), "has_parameter_semantics", paste0("param:", p$name %||% ""))
    }
    for (x in op$produces %||% list()) {
      k <- .wb_semantic_kind(x$kind)
      if (k %in% primitive_kinds) add_edge(op_id, paste0("primitive:", k), "produces", paste0("output:", x$name %||% ""))
    }
    for (out_name in as.character(op$promotable %||% character(0))) {
      produced <- op$produces %||% list()
      hit <- NULL
      for (x in produced) if (identical(as.character(x$name %||% "")[1], out_name)) hit <- x
      k <- .wb_semantic_kind(hit$kind %||% "")
      if (nzchar(k)) add_edge(op_id, paste0("artifact_type:", k), "promotes_as", paste0("promotable:", out_name))
    }
  }

  for (a in artifact_types) {
    aid <- paste0("artifact_type:", as.character(a$artifact_type %||% "")[1])
    k <- as.character(a$primitive_kind %||% "")[1]
    if (k %in% primitive_kinds) add_edge(aid, paste0("primitive:", k), "loads_as", "wb_art_load")
  }

  for (w in wranglers) {
    wid <- paste0("wrangler:", as.character(w$wrangler_id %||% "")[1])
    for (cns in as.character(w$consumes %||% character(0))) {
      k <- .wb_semantic_kind(cns)
      if (k %in% primitive_kinds) add_edge(paste0("primitive:", k), wid, "wrangled_by", cns)
      exact_art <- paste0("artifact_type:", cns)
      if (exact_art %in% artifact_ids) add_edge(exact_art, wid, "wrangled_by", cns)
      if (grepl(":", cns, fixed = TRUE)) {
        parts <- strsplit(cns, ":", fixed = TRUE)[[1]]
        if (length(parts) >= 2L) {
          table_art <- paste0("artifact_type:", parts[1], ":", parts[2])
          if (table_art %in% artifact_ids) add_edge(table_art, wid, "wrangled_by", cns)
        }
      }
    }
    pt <- as.character(w$plot_type %||% "")[1]
    if (paste0("plot:", pt) %in% plot_ids) add_edge(wid, paste0("plot:", pt), "feeds_plot", pt)
  }

  for (p in plots) {
    pid <- paste0("plot:", as.character(p$plot_type %||% "")[1])
    for (m in p$mappers %||% list()) {
      mid <- paste0("wrangler:plot_mapper:", as.character(m$mapper_id %||% "")[1])
      add_edge(mid, pid, "feeds_plot", as.character(p$plot_type %||% "")[1])
    }
  }

  for (r in recipes) {
    rid <- paste0("recipe:", as.character(r$recipe_id %||% "")[1])
    for (u in as.character(r$uses %||% character(0))) {
      if (u %in% node_ids) add_edge(rid, u, "uses", u)
      if (u %in% node_ids) add_edge(u, rid, "used_by_recipe", rid)
    }
    for (p in as.character(r$produces %||% character(0))) {
      if (p %in% node_ids) add_edge(rid, p, "recipe_produces", p)
      if (p %in% node_ids) add_edge(p, rid, "produced_by_recipe", rid)
    }
  }

  edge_keys <- vapply(edges, function(e) paste(e$from, e$to, e$edge_type, e$label, sep = "\r"), character(1))
  edges <- edges[!duplicated(edge_keys)]
  names(edges) <- NULL

  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.semantic_compatibility_graph.v1",
    generated_at = .wb_catalog_generated_at(),
    node_count = length(records),
    edge_count = length(edges),
    nodes = lapply(records, function(x) {
      list(
        record_id = x$record_id,
        record_type = x$record_type,
        name = x$name,
        title = x$title
      )
    }),
    edges = edges
  ))
}

#' Export Unified Semantic Catalog
#'
#' Combines op, getter, plot, wrangler, primitive, and artifact-type catalogs
#' into a normalized search corpus and includes the compatibility graph.
#'
#' @param bundle Optional open bundle, passed through to op catalog export.
#' @return A JSON-friendly semantic catalog list.
#' @export
wb_semantic_catalog <- function(bundle = NULL) {
  records <- .wb_semantic_catalog_records(bundle = bundle)
  graph <- wb_semantic_compatibility_graph(bundle = bundle)
  type_counts <- table(vapply(records, function(x) as.character(x$record_type), character(1)))
  type_count_list <- as.list(as.integer(type_counts))
  names(type_count_list) <- names(type_counts)
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.semantic_catalog.v1",
    generated_at = .wb_catalog_generated_at(),
    record_count = length(records),
    record_type_counts = type_count_list,
    records = records,
    graph = graph
  ))
}

#' Audit Semantic Catalog Coverage
#'
#' Checks whether registered engine surfaces are represented in semantic
#' catalogs and whether graph endpoints are valid.
#'
#' @param bundle Optional open bundle, passed through to op catalog export.
#' @return A named list with audit tables and a boolean `ok`.
#' @export
wb_semantic_catalog_audit <- function(bundle = NULL) {
  catalog <- wb_semantic_catalog(bundle = bundle)
  records <- catalog$records %||% list()
  record_ids <- vapply(records, function(x) as.character(x$record_id), character(1))

  op_catalog_names <- sub("^op:", "", record_ids[grepl("^op:", record_ids)])
  mapper_catalog_ids <- sub("^wrangler:plot_mapper:", "", record_ids[grepl("^wrangler:plot_mapper:", record_ids)])
  primitive_catalog_kinds <- sub("^primitive:", "", record_ids[grepl("^primitive:", record_ids)])
  artifact_catalog <- wb_artifact_type_catalog_semantic()$artifact_types %||% list()
  artifact_catalog_table_types <- unique(vapply(artifact_catalog, function(x) as.character(x$table_type %||% ""), character(1)))
  artifact_catalog_table_types <- artifact_catalog_table_types[nzchar(artifact_catalog_table_types)]
  known_table_types <- as.character(.wb_known_source_table_types()$table_type)

  exports <- tryCatch(getNamespaceExports("scworkbench"), error = function(e) character(0))
  if (!length(exports) && file.exists("NAMESPACE")) {
    ns <- readLines("NAMESPACE", warn = FALSE)
    exports <- sub("^export\\((.*)\\)$", "\\1", ns[grepl("^export\\(", ns)])
  }

  missing_ops <- setdiff(wb_list_ops(), op_catalog_names)
  missing_plot_mappers <- setdiff(as.character(wb_plot_mapper_list()$mapper_id), mapper_catalog_ids)
  promoter_kinds <- names(.wb_promoters_by_kind())
  missing_promoter_primitives <- setdiff(promoter_kinds, primitive_catalog_kinds)
  primitive_catalog <- wb_primitive_catalog_semantic()$primitives %||% list()
  primitive_constructors <- vapply(primitive_catalog, function(x) as.character(x$constructor %||% ""), character(1))
  primitive_constructors <- primitive_constructors[nzchar(primitive_constructors)]
  missing_primitive_constructor_exports <- setdiff(primitive_constructors, exports)
  exported_primitive_constructors <- exports[grepl("^wb_prim_", exports)]
  exported_primitive_kinds <- sub("^wb_prim_", "", exported_primitive_constructors)
  missing_constructor_primitives <- setdiff(exported_primitive_kinds, primitive_catalog_kinds)

  getter_catalog_names <- vapply(wb_getter_catalog_semantic()$getters, function(x) as.character(x$function_name %||% ""), character(1))
  missing_cataloged_getter_exports <- setdiff(getter_catalog_names, exports)
  semantic_export_names <- c(
    "wb_op_catalog_semantic",
    "wb_getter_catalog_semantic",
    "wb_plot_catalog_semantic",
    "wb_wrangler_catalog_semantic",
    "wb_primitive_catalog_semantic",
    "wb_artifact_type_catalog_semantic",
    "wb_parameter_semantics_catalog",
    "wb_recipe_semantics_catalog",
    "wb_semantic_catalog",
    "wb_semantic_compatibility_graph",
    "wb_semantic_catalog_audit",
    "wb_semantic_plan_artifact_next_steps",
    "wb_semantic_graph_tables",
    "wb_semantic_graph_dot",
    "wb_write_semantic_graph_views",
    "wb_refresh_semantic_catalogs"
  )
  missing_semantic_function_exports <- setdiff(semantic_export_names, exports)
  missing_known_table_types <- setdiff(known_table_types, artifact_catalog_table_types)

  parameter_catalog_names <- sub("^parameter:", "", record_ids[grepl("^parameter:", record_ids)])
  required_parameters <- c("cell_set", "matrix", "pseudotime", "pseudotime_direction", "score_method", "min_amplitude", "mad_multiplier")
  missing_required_parameters <- setdiff(required_parameters, parameter_catalog_names)
  recipe_catalog_names <- sub("^recipe:", "", record_ids[grepl("^recipe:", record_ids)])
  required_recipes <- c("trajectory_geneset_dynamics_discovery", "inspect_promoted_artifact", "plot_ucell_on_umap")
  missing_required_recipes <- setdiff(required_recipes, recipe_catalog_names)

  graph <- catalog$graph
  edges <- graph$edges %||% list()
  bad_edges <- Filter(function(e) !(e$from %in% record_ids && e$to %in% record_ids), edges)

  ops <- wb_op_catalog_semantic(bundle = bundle)$ops %||% list()
  unknown_op_kinds <- character(0)
  for (op in ops) {
    for (x in c(op$consumes %||% list(), op$produces %||% list())) {
      k <- .wb_semantic_kind(x$kind)
      if (nzchar(k) && !(k %in% primitive_catalog_kinds) && !(k %in% c("select", "feature_set", "string", "numeric", "integer", "bool", "choice"))) {
        unknown_op_kinds <- unique(c(unknown_op_kinds, paste0(op$op_name, ":", x$name, ":", k)))
      }
    }
  }

  ok <- length(missing_ops) == 0L &&
    length(missing_plot_mappers) == 0L &&
    length(missing_promoter_primitives) == 0L &&
    length(missing_primitive_constructor_exports) == 0L &&
    length(missing_constructor_primitives) == 0L &&
    length(missing_cataloged_getter_exports) == 0L &&
    length(missing_semantic_function_exports) == 0L &&
    length(missing_known_table_types) == 0L &&
    length(missing_required_parameters) == 0L &&
    length(missing_required_recipes) == 0L &&
    length(bad_edges) == 0L &&
    length(unknown_op_kinds) == 0L

  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.semantic_catalog_audit.v1",
    generated_at = .wb_catalog_generated_at(),
    ok = ok,
    missing_ops = missing_ops,
    missing_plot_mappers = missing_plot_mappers,
    missing_promoter_primitives = missing_promoter_primitives,
    missing_primitive_constructor_exports = missing_primitive_constructor_exports,
    missing_constructor_primitives = missing_constructor_primitives,
    missing_cataloged_getter_exports = missing_cataloged_getter_exports,
    missing_semantic_function_exports = missing_semantic_function_exports,
    missing_known_table_types = missing_known_table_types,
    missing_required_parameters = missing_required_parameters,
    missing_required_recipes = missing_required_recipes,
    unknown_op_kinds = unknown_op_kinds,
    bad_edge_count = length(bad_edges),
    known_table_type_count = length(known_table_types),
    record_count = catalog$record_count,
    edge_count = graph$edge_count
  ))
}

.wb_semantic_catalog_reference_lines <- function(catalog) {
  records <- catalog$records %||% list()
  by_type <- split(records, vapply(records, function(x) as.character(x$record_type), character(1)))
  lines <- c(
    "# scworkbench Unified Semantic Catalog",
    "",
    "<!-- Generated from wb_semantic_catalog(); do not edit entries by hand. -->",
    "",
    paste0("Generated at: ", as.character(catalog$generated_at %||% "")),
    "",
    paste0("Record count: ", as.integer(catalog$record_count %||% length(records))),
    "",
    paste0("Graph edges: ", as.integer(catalog$graph$edge_count %||% 0L)),
    ""
  )
  for (tp in sort(names(by_type))) {
    lines <- c(lines, paste0("## ", tp), "")
    for (rec in by_type[[tp]]) {
      lines <- c(
        lines,
        paste0("### `", as.character(rec$record_id %||% "")[1], "`"),
        "",
        paste0("Title: ", as.character(rec$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(rec$description %||% "")[1]),
        ""
      )
    }
  }
  lines
}

#' Write Unified Semantic Catalog Reference Files
#'
#' Writes the unified semantic catalog, graph, and audit files. This does not
#' generate embeddings; it creates the deterministic corpus that an embedding
#' index can consume.
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json Unified catalog JSON output path, or `NULL` to skip.
#' @param path_graph Compatibility graph JSON output path, or `NULL` to skip.
#' @param path_audit Audit JSON output path, or `NULL` to skip.
#' @param bundle Optional open bundle, passed through to op catalog export.
#' @return Invisibly returns the unified semantic catalog.
#' @export
wb_write_semantic_catalog_reference <- function(path_md = "docs/semantic_catalog_reference.md",
                                                path_json = "docs/semantic_catalog.json",
                                                path_graph = "docs/semantic_compatibility_graph.json",
                                                path_audit = "docs/semantic_catalog_audit.json",
                                                bundle = NULL) {
  catalog <- wb_semantic_catalog(bundle = bundle)
  graph <- catalog$graph
  audit <- wb_semantic_catalog_audit(bundle = bundle)
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    .wb_write_markdown_reference(.wb_semantic_catalog_reference_lines(catalog), path_md)
  }
  .wb_require_pkg("jsonlite", "semantic catalog export")
  for (spec in list(
    list(path = path_json, value = catalog),
    list(path = path_graph, value = graph),
    list(path = path_audit, value = audit)
  )) {
    if (!is.null(spec$path)) {
      dir.create(dirname(spec$path), recursive = TRUE, showWarnings = FALSE)
      jsonlite::write_json(spec$value, path = spec$path, auto_unbox = TRUE, pretty = TRUE, null = "null")
    }
  }
  invisible(catalog)
}

#' (Advanced) Refresh All Semantic Catalog Reference Files
#'
#' Regenerates operation, getter, plot, wrangler, primitive, artifact-type, and
#' unified semantic catalog docs/JSON, then validates every generated JSON file
#' and requires the semantic audit to pass by default.
#' This is a repository-maintenance API; consumers should read the committed
#' catalog exports rather than regenerate them during ordinary analysis.
#'
#' @param bundle Optional open bundle, passed through to op catalog export.
#' @param docs_dir Output directory.
#' @param validate If `TRUE`, validate every generated JSON file with
#'   `jsonlite::validate()`.
#' @param fail_on_audit If `TRUE`, error when `wb_semantic_catalog_audit()` is
#'   not `ok`.
#' @param write_graph_views If `TRUE`, write CSV node/edge tables and Graphviz
#'   DOT views under `semantic_graphs/`.
#' @return Invisibly returns the semantic catalog audit.
#' @export
wb_refresh_semantic_catalogs <- function(bundle = NULL,
                                         docs_dir = "docs",
                                         validate = TRUE,
                                         fail_on_audit = TRUE,
                                         write_graph_views = TRUE) {
  old_stamp <- getOption("scworkbench.catalog_generated_at", NULL)
  on.exit(options(scworkbench.catalog_generated_at = old_stamp), add = TRUE)
  stamp_path <- file.path(docs_dir, "op_catalog_semantic.json")
  stamp <- if (file.exists(stamp_path)) {
    prior <- try(jsonlite::read_json(stamp_path, simplifyVector = TRUE), silent = TRUE)
    if (!inherits(prior, "try-error")) as.character(prior$generated_at %||% "")[1] else ""
  } else ""
  if (!nzchar(stamp)) stamp <- "source-controlled"
  options(scworkbench.catalog_generated_at = stamp)
  json_paths <- file.path(
    docs_dir,
    c(
      "op_catalog_semantic.json",
      "getter_catalog_semantic.json",
      "plot_catalog_semantic.json",
      "wrangler_catalog_semantic.json",
      "primitive_catalog_semantic.json",
      "artifact_type_catalog_semantic.json",
      "mutation_catalog_semantic.json",
      "parameter_semantics_catalog.json",
      "recipe_semantics_catalog.json",
      "semantic_catalog.json",
      "semantic_compatibility_graph.json",
      "semantic_catalog_audit.json"
    )
  )

  wb_write_op_catalog_reference(
    path_md = file.path(docs_dir, "op_catalog_reference.md"),
    path_json = file.path(docs_dir, "op_catalog_semantic.json"),
    bundle = bundle
  )
  wb_write_getter_catalog_reference(
    path_md = file.path(docs_dir, "getter_catalog_reference.md"),
    path_json = file.path(docs_dir, "getter_catalog_semantic.json")
  )
  wb_write_plot_catalog_reference(
    path_md = file.path(docs_dir, "plot_catalog_reference.md"),
    path_json = file.path(docs_dir, "plot_catalog_semantic.json")
  )
  wb_write_wrangler_catalog_reference(
    path_md = file.path(docs_dir, "wrangler_catalog_reference.md"),
    path_json = file.path(docs_dir, "wrangler_catalog_semantic.json")
  )
  wb_write_primitive_catalog_reference(
    path_md = file.path(docs_dir, "primitive_catalog_reference.md"),
    path_json = file.path(docs_dir, "primitive_catalog_semantic.json")
  )
  wb_write_artifact_type_catalog_reference(
    path_md = file.path(docs_dir, "artifact_type_catalog_reference.md"),
    path_json = file.path(docs_dir, "artifact_type_catalog_semantic.json")
  )
  wb_write_mutation_catalog_reference(
    path_md = file.path(docs_dir, "mutation_catalog_reference.md"),
    path_json = file.path(docs_dir, "mutation_catalog_semantic.json")
  )
  wb_write_parameter_semantics_reference(
    path_md = file.path(docs_dir, "parameter_semantics_reference.md"),
    path_json = file.path(docs_dir, "parameter_semantics_catalog.json")
  )
  wb_write_recipe_semantics_reference(
    path_md = file.path(docs_dir, "recipe_semantics_reference.md"),
    path_json = file.path(docs_dir, "recipe_semantics_catalog.json")
  )
  wb_write_semantic_catalog_reference(
    path_md = file.path(docs_dir, "semantic_catalog_reference.md"),
    path_json = file.path(docs_dir, "semantic_catalog.json"),
    path_graph = file.path(docs_dir, "semantic_compatibility_graph.json"),
    path_audit = file.path(docs_dir, "semantic_catalog_audit.json"),
    bundle = bundle
  )
  audit <- wb_semantic_catalog_audit(bundle = bundle)
  if (isTRUE(write_graph_views)) {
    audit$graph_views <- wb_write_semantic_graph_views(
      out_dir = file.path(docs_dir, "semantic_graphs"),
      bundle = bundle
    )
  }
  if (isTRUE(fail_on_audit)) {
    .wb_assert(isTRUE(audit$ok), "Semantic catalog audit failed; inspect docs/semantic_catalog_audit.json.")
  }

  if (isTRUE(validate)) {
    .wb_require_pkg("jsonlite", "semantic catalog validation")
    missing <- json_paths[!file.exists(json_paths)]
    .wb_assert(!length(missing), paste0("Missing semantic JSON files: ", paste(missing, collapse = ", ")))

    invalid <- character(0)
    for (path in json_paths) {
      txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
      if (!isTRUE(jsonlite::validate(txt))) invalid <- c(invalid, path)
    }
    .wb_assert(!length(invalid), paste0("Invalid semantic JSON files: ", paste(invalid, collapse = ", ")))
    audit$json_validated <- json_paths
  }

  invisible(audit)
}
