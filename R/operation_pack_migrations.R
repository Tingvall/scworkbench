# Compatibility metadata for operations extracted from the historical core
# catalog. This file contains no scientific method implementation.

.wb_operation_pack_migrated_map <- function() {
  c(
    de_wilcox = "scwbstatistics::de_wilcox",
    markers_topn = "scwbstatistics::markers_topn",
    cell_vector_assoc = "scwbstatistics::cell_vector_assoc",
    cell_vector_association = "scwbstatistics::cell_vector_association",
    cell_vector_compare = "scwbstatistics::cell_vector_compare",
    feature_trend_spearman = "scwbstatistics::feature_trend_spearman"
  )
}

.wb_operation_name_resolve <- function(op_name) {
  op_name <- as.character(op_name)[1]
  catalog <- .wb_operation_catalog()
  if (op_name %in% names(catalog)) return(op_name)
  if (!grepl("::", op_name, fixed = TRUE)) {
    candidates <- names(catalog)[endsWith(names(catalog), paste0("::", op_name))]
    if (length(candidates) == 1L) return(candidates[[1]])
    if (length(candidates) > 1L) .wb_operation_pack_abort(
      "OPERATION_PACK_OPERATION_AMBIGUOUS",
      paste0("Unqualified operation '", op_name, "' matches multiple active packs: ",
        paste(sort(candidates, method = "radix"), collapse = ", "), ". Use a qualified name."),
      operation = op_name, candidates = sort(candidates, method = "radix"),
      class = "wb_operation_pack_ambiguous")
    target <- .wb_operation_pack_migrated_map()[[op_name]]
    if (!is.null(target)) .wb_operation_pack_abort(
      "OPERATION_PACK_REQUIRED",
      paste0("Operation '", op_name, "' moved to '", target,
        "'. Install and explicitly activate scwbStatistics."),
      operation = op_name, required_operation = target, namespace = "scwbstatistics",
      class = "wb_operation_pack_unavailable")
  }
  if (grepl("::", op_name, fixed = TRUE)) {
    namespace <- strsplit(op_name, "::", fixed = TRUE)[[1]][1]
    .wb_operation_pack_abort("OPERATION_PACK_REQUIRED",
      paste0("Operation '", op_name, "' requires its exact compatible operation pack."),
      operation = op_name, namespace = namespace,
      class = "wb_operation_pack_unavailable")
  }
  op_name
}

.wb_operation_pack_migration_catalog_overlay <- function(definition) {
  qualified <- as.character(definition$op_name %||% definition$name)[1]
  short <- sub("^scwbstatistics::", "", qualified)
  if (!short %in% names(.wb_operation_pack_migrated_map())) return(definition)
  specs <- list(
    de_wilcox = list(
      title = "Differential Expression (Wilcoxon)",
      description = "Wilcoxon rank-sum DE between two cell groups (A vs B).",
      intent = c("de", "markers", "comparison"),
      inputs = list(matrix = list(required = TRUE, kind = "matrix")),
      params = list(
        list(name = "group_a", type = "cell_ids_or_set", default = NULL,
          help = "Group A cells: vector of cell IDs or 'set:<name>'."),
        list(name = "group_b", type = "cell_ids_or_set", default = NULL,
          help = "Group B cells: vector of cell IDs or 'set:<name>'."),
        list(name = "features", type = "string_vec", default = NULL,
          help = "Optional feature subset."),
        list(name = "min_pct", type = "dbl", default = 0, min = 0, max = 1,
          help = "Minimum detection fraction in either group."),
        list(name = "p_adjust_method", type = "string", default = "BH",
          help = "Method passed to p.adjust.")),
      output = list(de_table = list(kind="feature_table", description="Feature-level DE statistics table."))),
    markers_topn = list(
      title = "Top Markers Per Cluster",
      description = "One-vs-rest Wilcoxon marker ranking for each cluster.",
      intent = c("markers", "cluster"),
      inputs = list(matrix = list(required = TRUE, kind = "matrix"),
        clusters = list(required = TRUE, kind = "cell_vector")),
      params = list(
        list(name = "features", type = "string_vec", default = NULL,
          help = "Optional feature subset."),
        list(name = "top_n", type = "int", default = 20, min = 1, max = 1000,
          help = "Top markers retained per cluster."),
        list(name = "min_pct", type = "dbl", default = 0.1, min = 0, max = 1,
          help = "Minimum detection fraction in either group."),
        list(name = "p_adjust_method", type = "string", default = "BH",
          help = "Method passed to p.adjust.")),
      output = list(markers=list(kind="feature_table",description="Cluster-marker table with per-feature statistics."))),
    cell_vector_assoc = list(
      title = "Cell Vector Association",
      description = paste("Test whether a continuous cell-level signal differs across groups",
        "defined by a categorical cell-level vector."),
      intent=c("statistics","association","confounding"),
      inputs = list(
        vector_cont = list(required = TRUE, kind = "cell_vector",
          label = "Continuous vector (numeric per cell)",
          help = "Examples: pseudotime, module score, gene-program score."),
        vector_group = list(required = TRUE, kind = "cell_vector",
          label = "Grouping vector (categorical per cell)",
          help = "Examples: cluster labels, cell type labels, condition labels.")),
      params=list(list(name = "min_n_per_group", type = "int", default = 3,
        min = 1, max = 1e5, help = "Minimum cells per group.")),
      output=list(assoc_summary=list(kind="feature_table",description="Omnibus association test summary (Kruskal/ANOVA)."),group_stats=list(kind="obs_table",description="Per-group descriptive statistics."))),
    cell_vector_association = list(
      title = "Cell Vector Association",
      description = "Associate two typed cell vectors with categorical and continuous dispatch.",
      intent=c("statistics","association","confounding"),
      inputs = list(
        a = list(required = TRUE, kind = "cell_vector", label = "First vector",
          help = "Categorical or continuous cell vector."),
        b = list(required = TRUE, kind = "cell_vector", label = "Second vector",
          help = "Categorical or continuous cell vector.")),
      params=list(
        list(name = "cell_set", type = "cell_set", default = "all",
          help = "Named bundle cell set defining the association universe."),
        list(name = "min_n_per_group", type = "int", default = 3, min = 1,
          max = 1e5, help = "Minimum cells per retained categorical group."),
        list(name = "method", type = "choice", default = "auto",
          choices = c("auto","chisq","fisher","kruskal_anova","correlation"),
          help = "Association method or typed automatic dispatch.")),
      output=list(summary=list(kind="obs_table",description="Typed association summary including method, effect size, and diagnostics."),detail=list(kind="obs_table",description="Contingency, group-statistic, or per-cell association detail appropriate to the dispatched test."))),
    cell_vector_compare = list(
      title = "Cell Vector Comparison",
      description = "Compare two cell-level signals on their shared cell universe in raw or rank space.",
      intent=c("statistics","comparison","signal"),
      inputs = list(
        a = list(required = TRUE, kind = "cell_vector", label = "Signal A",
          help = "Continuous or rankable numeric signal per cell."),
        b = list(required = TRUE, kind = "cell_vector", label = "Signal B",
          help = "Continuous or rankable numeric signal per cell.")),
      params=list(
        list(name = "compare_space", type = "choice", default = "rank",
          choices = c("raw","rank"),
          help = "Whether to compare original numeric values or cell ranks."),
        list(name = "ties_method", type = "choice", default = "average",
          choices = c("average","first","last","random","max","min"),
          help = "Tie handling rule used when compare_space='rank'."),
        list(name = "signal_a", type = "string", default = "a",
          help = "Optional label recorded in the summary table for signal A."),
        list(name = "signal_b", type = "string", default = "b",
          help = "Optional label recorded in the summary table for signal B.")),
      output=list(summary=list(kind="obs_table",description="One-row comparison summary with concordance and delta metrics."),comparison=list(kind="obs_table",description="Per-cell comparison table with original values, compared values, and deltas."))),
    feature_trend_spearman = list(
      title = "Feature Trends vs Continuous Vector",
      description = "Feature-level Spearman trend testing against continuous pseudotime-like vectors.",
      intent=c("trend","statistics","trajectory"),
      inputs = list(matrix = list(required = TRUE, kind = "matrix"),
        pseudotime = list(required = TRUE, kind = "cell_vector")),
      params=list(
        list(name = "features", type = "string_vec", default = NULL,
          help = "Optional feature subset."),
        list(name = "min_pct_nonzero", type = "dbl", default = 0, min = 0,
          max = 1, help = "Minimum non-zero fraction filter."),
        list(name = "min_sd", type = "dbl", default = 0, min = 0, max = 1e6,
          help = "Minimum per-feature standard deviation filter."),
        list(name = "p_adjust_method", type = "string", default = "BH",
          help = "Method passed to p.adjust."),
        list(name = "chunk_size", type = "int", default = 128, min = 1,
          max = 4096, help = "Chunk size for matrix slicing.")),
      output=list(trend_table=list(kind="feature_table",description="Per-feature trend statistics (rho, p, adjusted p).")),
      chunking=list(chunkable=TRUE,axis="features",chunk_size_param="chunk_size",
        chunk_size_default=128L,merge=list(trend_table="row_bind_feature_table"),status="implemented_generic"))
  )[[short]]
  definition$title <- specs$title
  definition$description <- specs$description
  definition$intent <- specs$intent
  definition$inputs <- specs$inputs
  definition$params <- specs$params
  definition$interface_produces <- specs$output
  if (!is.null(specs$chunking)) definition$chunking <- specs$chunking
  definition
}

.wb_operation_pack_params_transport <- function(value) {
  if (is.factor(value)) value <- as.character(value)
  if (is.atomic(value) && length(value) > 1L) return(unname(as.list(value)))
  if (is.list(value)) {
    out <- lapply(value, .wb_operation_pack_params_transport)
    if (!is.null(names(value))) names(out) <- names(value)
    return(out)
  }
  value
}

.wb_operation_pack_resolve_migrated_params <- function(bundle, op_name, params,
                                                        effective_cells) {
  short <- sub("^scwbstatistics::", "", op_name)
  if (identical(short, "de_wilcox")) {
    params$group_a <- .wb_resolve_group_cells(bundle, params$group_a, effective_cells)
    params$group_b <- .wb_resolve_group_cells(bundle, params$group_b, effective_cells)
  }
  .wb_operation_pack_params_transport(params)
}

.wb_operation_pack_migrated_result_params <- function(op_name, inputs, resolved,
                                                       outputs) {
  short <- sub("^scwbstatistics::", "", op_name)
  if (identical(short, "de_wilcox")) {
    meta <- outputs$de_table$meta
    return(list(matrix_id = meta$matrix_id, n_features = nrow(outputs$de_table$table),
      n_cells_a = meta$n_cells_a, n_cells_b = meta$n_cells_b,
      min_pct = as.numeric(inputs$min_pct),
      p_adjust_method = as.character(inputs$p_adjust_method)[1]))
  }
  if (identical(short, "markers_topn")) {
    meta <- outputs$markers$meta
    supplied <- !is.null(inputs$features)
    requested <- if (supplied) length(inputs$features) else
      length(resolved$matrix$feature_id %||% character())
    return(list(matrix_id = meta$matrix_id, n_clusters = meta$n_clusters,
      n_features_requested = requested, feature_subset_supplied = supplied,
      n_markers = nrow(outputs$markers$table), top_n = as.integer(inputs$top_n),
      min_pct = as.numeric(inputs$min_pct),
      p_adjust_method = as.character(inputs$p_adjust_method)[1]))
  }
  if (identical(short, "cell_vector_assoc")) {
    row <- outputs$assoc_summary$table
    return(list(n_cells = row$n_cells[[1]], n_groups = row$n_groups[[1]],
      min_n_per_group = as.integer(inputs$min_n_per_group)))
  }
  if (identical(short, "cell_vector_association")) {
    row <- outputs$summary$table
    association_type <- as.character(row$association_type[[1]])
    if (identical(association_type, "continuous_x_categorical")) {
      return(list(n_cells = row$n_cells[[1]], n_groups = row$n_groups[[1]],
        min_n_per_group = as.integer(inputs$min_n_per_group),
        association_type = association_type, method = row$method[[1]]))
    }
    if (identical(association_type, "continuous_x_continuous")) {
      return(list(association_type = association_type, method = row$method[[1]],
        n_cells = row$n_cells[[1]]))
    }
    return(list(association_type = association_type, method = row$method[[1]],
      min_n_per_group = as.integer(inputs$min_n_per_group),
      n_cells = row$n_cells[[1]]))
  }
  if (identical(short, "cell_vector_compare")) {
    return(list(compare_space = as.character(inputs$compare_space)[1],
      ties_method = as.character(inputs$ties_method)[1],
      signal_a = as.character(inputs$signal_a)[1],
      signal_b = as.character(inputs$signal_b)[1],
      n_shared_cells = nrow(outputs$comparison$table)))
  }
  if (identical(short, "feature_trend_spearman")) {
    return(outputs$trend_table$meta)
  }
  list()
}
