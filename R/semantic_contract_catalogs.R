# Semantic catalogs for non-op engine contracts.

.wb_semantic_catalog_clean <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) .wb_semantic_catalog_clean(as.list(x[i, , drop = FALSE]))))
  if (is.list(x)) return(lapply(x, .wb_semantic_catalog_clean))
  if (is.factor(x)) return(as.character(x))
  if (length(x) == 0L) return(list())
  if (length(x) == 1L && is.na(x)) return(NULL)
  x
}

.wb_semantic_reference_lines <- function(title, generator, count_label, count, records, id_field, section_field = NULL, body_fn) {
  lines <- c(
    paste0("# ", title),
    "",
    paste0("<!-- Generated from ", generator, "; do not edit entries by hand. -->"),
    "",
    paste0(count_label, ": ", as.integer(count)),
    ""
  )
  if (is.null(section_field)) {
    groups <- list(records)
    names(groups) <- ".__all__"
  } else {
    groups <- split(records, vapply(records, function(x) as.character(x[[section_field]] %||% "misc")[1], character(1)))
  }
  for (grp in sort(names(groups))) {
    if (nzchar(grp) && !identical(grp, ".__all__")) lines <- c(lines, paste0("## ", grp), "")
    for (rec in groups[[grp]]) {
      lines <- c(lines, paste0("### `", as.character(rec[[id_field]] %||% "")[1], "`"), "", body_fn(rec), "")
    }
  }
  lines
}

.wb_wrangler_catalog_notes <- function(mapper_id, plot_type) {
  notes <- list(
    space2d_overlay_v1 = list(
      title = "Space + Vector Embedding Overlay Wrangler",
      description = "Combines a 2D space with optional cell-vector overlays into an embedding_overlay dataset.",
      consumes = c("space_2d", "cell_vector", "cell_vector_family"),
      produces = "embedding_overlay dataset",
      use_when = c("color UMAP by expression or scores", "overlay sets or labels on a 2D space")
    ),
    feature_table_volcano_v1 = list(
      title = "Feature Table Volcano Wrangler",
      description = "Maps differential or trend-like feature tables to volcano plot columns.",
      consumes = c("feature_table"),
      produces = "ranked_features dataset",
      use_when = c("plot DE effect versus significance", "inspect feature-level statistics")
    ),
    feature_table_trend_scatter_v1 = list(
      title = "Feature Trend Scatter Wrangler",
      description = "Maps feature trend statistics to a feature_scatter plot dataset.",
      consumes = c("feature_table"),
      produces = "feature_scatter dataset",
      use_when = c("plot pseudotime trend statistics", "inspect feature association effects")
    ),
    cell_vector_violin_v1 = list(
      title = "Cell Vector Violin Wrangler",
      description = "Combines a numeric cell vector with a grouping vector to form distribution data.",
      consumes = c("cell_vector", "cell_vector_family"),
      produces = "distribution dataset",
      use_when = c("compare scores across groups", "display UCell/module score distributions")
    ),
    cell_vector_category_count_bar_v1 = list(
      title = "Categorical Cell Vector Count Wrangler",
      description = "Counts categorical cell-vector labels for category bar plots.",
      consumes = c("cell_vector"),
      produces = "category_summary dataset",
      use_when = c("summarize winner labels", "count categorical annotations")
    ),
    feature_table_dotplot_v1 = list(
      title = "Feature Group Dotplot Wrangler",
      description = "Maps marker-style feature group summaries to dotplot columns.",
      consumes = c("feature_table"),
      produces = "feature_group_summary dataset",
      use_when = c("plot markers by cluster", "show percent expression and average expression")
    ),
    feature_table_pathway_bar_v1 = list(
      title = "Pathway Summary Wrangler",
      description = "Maps pathway enrichment observation tables to ranked pathway bars.",
      consumes = c("obs_table"),
      produces = "pathway_summary dataset",
      use_when = c("plot pathway enrichment", "rank GSEA or feature-set terms")
    ),
    feature_table_ranked_lollipop_v1 = list(
      title = "Ranked Table Lollipop Wrangler",
      description = "Maps feature or observation tables with score-like columns to ranked entity data.",
      consumes = c("feature_table", "obs_table"),
      produces = "ranked_entities dataset",
      use_when = c("show top genes", "show top dynamic signals", "show top pathways")
    ),
    feature_table_heatmap_ranked_v1 = list(
      title = "Ranked Feature Heatmap Wrangler",
      description = "Maps feature-by-group values to a matrix-like ranked heatmap dataset.",
      consumes = c("feature_table"),
      produces = "matrix_like dataset",
      use_when = c("compare ranked features across groups")
    ),
    feature_table_feature_rank_bar_v1 = list(
      title = "Feature Rank Bar Wrangler",
      description = "Maps feature tables with score-like values to ranked bar data.",
      consumes = c("feature_table"),
      produces = "ranked_features dataset",
      use_when = c("show compact ranked feature summaries")
    ),
    trajectory_pseudotime_smooth_panel_v1 = list(
      title = "Pseudotime Smooth Wrangler",
      description = "Maps trajectory_smooth tables to per-gene pseudotime curve panels.",
      consumes = c("obs_table:trajectory_smooth"),
      produces = "trajectory_smooth dataset",
      use_when = c("plot gene dynamics along pseudotime")
    ),
    trajectory_pseudotime_signature_line_v1 = list(
      title = "Pseudotime Signature Wrangler",
      description = "Maps signature, gene-set, signal, or driver curves to pseudotime line datasets.",
      consumes = c("obs_table:trajectory_signature_smooth", "obs_table:trajectory_geneset_dynamics_curve", "obs_table:trajectory_signal_dynamics_curve"),
      produces = "trajectory_signature_smooth dataset",
      use_when = c("plot gene-set dynamics", "plot signal dynamics", "plot driver-gene curves")
    )
  )
  notes[[mapper_id]] %||% list(
    title = paste(plot_type, mapper_id),
    description = "Registered plot mapper wrangler.",
    consumes = character(0),
    produces = paste0(plot_type, " dataset"),
    use_when = character(0)
  )
}

#' Export Wrangler Catalog As Semantic Metadata
#'
#' Returns JSON-friendly descriptions of table wranglers and registered plot
#' mapper wranglers. Wranglers reshape primitives or references for display and
#' export; they do not perform primary analysis.
#'
#' @return A named list with wrangler records.
#' @export
wb_wrangler_catalog_semantic <- function() {
  plot_mappers <- wb_plot_mapper_list()
  mapper_records <- lapply(seq_len(nrow(plot_mappers)), function(i) {
    mapper_id <- as.character(plot_mappers$mapper_id[i])
    plot_type <- as.character(plot_mappers$plot_type[i])
    note <- .wb_wrangler_catalog_notes(mapper_id, plot_type)
    list(
      wrangler_id = paste0("plot_mapper:", mapper_id),
      function_name = "wb_wrangle_plot_dataset",
      title = as.character(note$title %||% mapper_id)[1],
      category = "plot_mapper",
      description = as.character(note$description %||% "")[1],
      consumes = as.character(note$consumes %||% character(0)),
      produces = as.character(note$produces %||% "")[1],
      plot_type = plot_type,
      mapper_id = mapper_id,
      priority = as.integer(plot_mappers$priority[i]),
      use_when = as.character(note$use_when %||% character(0)),
      mutates = FALSE
    )
  })
  table_records <- list(
    list(
      wrangler_id = "table:primitive_to_table",
      function_name = "wb_primitive_to_table",
      title = "Primitive To Table Wrangler",
      category = "table",
      description = "Projects primitive-native payloads to normalized data.frames for display, export, or light client use.",
      consumes = c("feature_table", "obs_table", "cell_vector", "cell_vector_family", "relation_family", "space_path_family", "space_2d"),
      produces = "data.frame",
      plot_type = NULL,
      mapper_id = NULL,
      priority = NULL,
      use_when = c("inspect a primitive as rows", "export primitive payload", "normalize promoted artifacts for clients"),
      mutates = FALSE
    ),
    list(
      wrangler_id = "table:client_load_table",
      function_name = "wb_client_load_table",
      title = "Client Reference To Table Wrangler",
      category = "table",
      description = "Loads a session/artifact/reference through the client facade and converts the resolved primitive to a normalized table.",
      consumes = c("artifact ref", "session ref", "primitive ref"),
      produces = "data.frame",
      plot_type = NULL,
      mapper_id = NULL,
      priority = NULL,
      use_when = c("load and inspect artifact tables", "agent-friendly reference inspection"),
      mutates = FALSE
    )
  )
  wranglers <- c(table_records, mapper_records)
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.wrangler_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    wrangler_count = length(wranglers),
    wranglers = wranglers
  ))
}

.wb_wrangler_catalog_reference_lines <- function(catalog) {
  .wb_semantic_reference_lines(
    title = "scworkbench Wrangler Catalog",
    generator = "wb_wrangler_catalog_semantic()",
    count_label = "Wrangler count",
    count = catalog$wrangler_count,
    records = catalog$wranglers,
    id_field = "wrangler_id",
    section_field = "category",
    body_fn = function(x) {
      c(
        paste0("Function: `", as.character(x$function_name %||% "")[1], "`"),
        "",
        paste0("Title: ", as.character(x$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(x$description %||% "")[1]),
        "",
        paste0("Consumes: ", paste(as.character(x$consumes %||% character(0)), collapse = ", ")),
        "",
        paste0("Produces: ", as.character(x$produces %||% "")[1]),
        "",
        "Use when:",
        if (length(x$use_when %||% character(0))) paste0("- ", as.character(x$use_when)) else "- (unspecified)"
      )
    }
  )
}

#' Write Wrangler Catalog Reference Files
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the semantic wrangler catalog.
#' @export
wb_write_wrangler_catalog_reference <- function(path_md = "docs/wrangler_catalog_reference.md",
                                                path_json = "docs/wrangler_catalog_semantic.json") {
  catalog <- wb_wrangler_catalog_semantic()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    writeLines(.wb_wrangler_catalog_reference_lines(catalog), con = path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "wrangler catalog semantic export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}

.wb_primitive_catalog_entries <- function() {
  list(
    list(primitive_kind = "matrix", constructor = "wb_prim_matrix", title = "Matrix Reference", description = "Symbolic reference to a feature-by-cell matrix stored in the bundle.", shape = "matrix_id", payload_level = "reference", use_when = c("select expression/accessibility matrix", "pass matrix identity to ops"), promotable = FALSE),
    list(primitive_kind = "space", constructor = "wb_prim_space", title = "Space Reference", description = "Symbolic reference to a cell embedding or latent space stored in the bundle.", shape = "space_id", payload_level = "reference", use_when = c("select latent/embedding space for ops"), promotable = FALSE),
    list(primitive_kind = "space_2d", constructor = "wb_prim_space_2d", title = "2D Space Reference", description = "Reference to a two-dimensional cell space, typically UMAP-like coordinates.", shape = "space_id or table with cell_id/x/y", payload_level = "reference/table", use_when = c("plot cells in 2D", "overlay scores or sets"), promotable = TRUE),
    list(primitive_kind = "cell_vector", constructor = "wb_prim_cell_vector", title = "Cell Vector", description = "One value per cell, continuous or categorical.", shape = "cell_id, value, value_type", payload_level = "payload", use_when = c("store pseudotime", "store labels", "store per-cell scores"), promotable = TRUE),
    list(primitive_kind = "cell_vector_family", constructor = "wb_prim_cell_vector_family", title = "Cell Vector Family", description = "Long-form collection of keyed per-cell vectors.", shape = "key, cell_id, value, value_type", payload_level = "payload", use_when = c("store UCell signatures", "store chromVAR motif scores", "store per-lineage or per-feature vectors"), promotable = TRUE),
    list(primitive_kind = "relation_family", constructor = "wb_prim_relation_family", title = "Relation Family", description = "Sparse long-form cell-to-key relations with optional weights, values, or distances.", shape = "key, cell_id, optional weight/value/distance", payload_level = "payload", use_when = c("store branch membership", "store fuzzy assignments", "store edge-like relations"), promotable = TRUE),
    list(primitive_kind = "feature_table", constructor = "wb_prim_feature_table", title = "Feature Table", description = "Data frame where rows are feature-centric results such as genes, peaks, or markers.", shape = "table with feature_id plus table_type", payload_level = "payload", use_when = c("store DE tables", "store marker tables", "store feature trend results"), promotable = TRUE),
    list(primitive_kind = "obs_table", constructor = "wb_prim_obs_table", title = "Observation Table", description = "Generic observation-style data frame specialized by table_type and entity_kind.", shape = "table plus table_type/entity_kind", payload_level = "payload", use_when = c("store summaries", "store trajectory curves", "store pathway results", "store dynamics tables"), promotable = TRUE),
    list(primitive_kind = "model_ref", constructor = "wb_prim_model_ref", title = "Model Reference", description = "Reference to a stored model artifact and the spaces it maps between.", shape = "engine, model_space_id, in_space_id, artifact_id", payload_level = "reference", use_when = c("store projection models", "project new data into fitted space"), promotable = TRUE),
    list(primitive_kind = "path_2d_family", constructor = "wb_prim_path_2d_family", title = "2D Path Family", description = "Lineage or curve coordinates in a 2D plotting space.", shape = "key, point, x, y", payload_level = "payload", use_when = c("draw trajectory curves on UMAP", "inspect fitted lineages"), promotable = TRUE),
    list(primitive_kind = "space_path_family", constructor = "wb_prim_space_path_family", title = "High-Dimensional Space Path Family", description = "Curves in an arbitrary-dimensional bundle space, represented point-by-dimension.", shape = "space_id, path_id, point, dim, value", payload_level = "payload", use_when = c("represent checkpoint paths", "score cells against high-dimensional trajectories"), promotable = TRUE)
  )
}

#' Export Primitive Catalog As Semantic Metadata
#'
#' @return A named list with primitive-kind records.
#' @export
wb_primitive_catalog_semantic <- function() {
  primitives <- .wb_primitive_catalog_entries()
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.primitive_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    primitive_count = length(primitives),
    primitives = primitives
  ))
}

.wb_primitive_catalog_reference_lines <- function(catalog) {
  .wb_semantic_reference_lines(
    title = "scworkbench Primitive Catalog",
    generator = "wb_primitive_catalog_semantic()",
    count_label = "Primitive count",
    count = catalog$primitive_count,
    records = catalog$primitives,
    id_field = "primitive_kind",
    body_fn = function(x) {
      c(
        paste0("Constructor: `", as.character(x$constructor %||% "")[1], "`"),
        "",
        paste0("Title: ", as.character(x$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(x$description %||% "")[1]),
        "",
        paste0("Shape: ", as.character(x$shape %||% "")[1]),
        "",
        paste0("Payload level: ", as.character(x$payload_level %||% "")[1]),
        "",
        paste0("Promotable: ", as.character(x$promotable %||% FALSE)[1]),
        "",
        "Use when:",
        if (length(x$use_when %||% character(0))) paste0("- ", as.character(x$use_when)) else "- (unspecified)"
      )
    }
  )
}

#' Write Primitive Catalog Reference Files
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the semantic primitive catalog.
#' @export
wb_write_primitive_catalog_reference <- function(path_md = "docs/primitive_catalog_reference.md",
                                                 path_json = "docs/primitive_catalog_semantic.json") {
  catalog <- wb_primitive_catalog_semantic()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    writeLines(.wb_primitive_catalog_reference_lines(catalog), con = path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "primitive catalog semantic export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}

.wb_artifact_type_catalog_entries <- function() {
  list(
    list(artifact_type = "cell_vector", primitive_kind = "cell_vector", title = "Per-Cell Vector Artifact", description = "Promoted per-cell scalar/categorical vector such as pseudotime, labels, entropy, or module score.", table_type = NULL, entity_kind = "cell", use_when = c("load per-cell values", "plot overlays or distributions")),
    list(artifact_type = "cell_vector_family", primitive_kind = "cell_vector_family", title = "Per-Cell Vector Family Artifact", description = "Promoted keyed family of per-cell vectors, for example UCell signatures or chromVAR deviations.", table_type = NULL, entity_kind = "cell_by_key", use_when = c("select one score family key", "compare many signatures or motifs")),
    list(artifact_type = "relation_family", primitive_kind = "relation_family", title = "Relation Family Artifact", description = "Promoted sparse long-form cell-to-key relations such as branch membership.", table_type = NULL, entity_kind = "cell_relation", use_when = c("inspect branch assignment", "load fuzzy membership")),
    list(artifact_type = "path_2d_family", primitive_kind = "path_2d_family", title = "2D Path Family Artifact", description = "Promoted 2D trajectory or lineage curves.", table_type = NULL, entity_kind = "path_point", use_when = c("draw trajectory curves", "inspect selected lineages")),
    list(artifact_type = "space_path_family", primitive_kind = "space_path_family", title = "Space Path Family Artifact", description = "Promoted high-dimensional route/trajectory paths.", table_type = NULL, entity_kind = "space_path_point", use_when = c("score cells against checkpoint paths", "reuse space trajectories")),
    list(artifact_type = "space_2d", primitive_kind = "space_2d", title = "2D Space Artifact", description = "Promoted reference to a 2D bundle space.", table_type = NULL, entity_kind = "cell", use_when = c("plot embeddings", "provide spatial context to wranglers")),
    list(artifact_type = "model_ref", primitive_kind = "model_ref", title = "Model Reference Artifact", description = "Promoted model reference for projection or method-specific reuse.", table_type = NULL, entity_kind = "model", use_when = c("reuse fitted UMAP or trajectory models")),
    list(artifact_type = "feature_table:de_wilcox", primitive_kind = "feature_table", title = "Wilcoxon DE Table", description = "Feature-level differential expression/accessibility statistics.", table_type = "de_wilcox", entity_kind = "feature", use_when = c("find marker genes", "plot volcanoes")),
    list(artifact_type = "feature_table:markers_topn", primitive_kind = "feature_table", title = "Top Marker Table", description = "Top-ranked marker features per group.", table_type = "markers_topn", entity_kind = "feature", use_when = c("summarize cluster markers", "build dotplots")),
    list(artifact_type = "feature_table:feature_trend_spearman", primitive_kind = "feature_table", title = "Feature Trend Spearman Table", description = "Feature-level association with a continuous vector such as pseudotime.", table_type = "feature_trend_spearman", entity_kind = "feature", use_when = c("find genes changing with pseudotime", "plot trend statistics")),
    list(artifact_type = "feature_table:trajectory_de", primitive_kind = "feature_table", title = "Trajectory DE Table", description = "Feature-level differential or dynamic statistics along trajectory lineages.", table_type = "trajectory_de", entity_kind = "feature", use_when = c("rank trajectory genes", "feed trajectory dynamics reports")),
    list(artifact_type = "feature_table:trajectory_branch_compare", primitive_kind = "feature_table", title = "Trajectory Branch Compare Table", description = "Feature-level branch comparison statistics.", table_type = "trajectory_branch_compare", entity_kind = "feature", use_when = c("compare branch programs")),
    list(artifact_type = "obs_table:pathway_enrich", primitive_kind = "obs_table", title = "Pathway Enrichment Table", description = "Pathway or gene-set enrichment summary.", table_type = "pathway_enrich", entity_kind = "pathway", use_when = c("rank enriched pathways", "plot pathway bars")),
    list(artifact_type = "obs_table:trajectory_smooth", primitive_kind = "obs_table", title = "Trajectory Smooth Curve Table", description = "Binned/smoothed per-gene expression curves along trajectory pseudotime.", table_type = "trajectory_smooth", entity_kind = "trajectory_bin", use_when = c("plot gene dynamics", "inspect trajectory expression curves")),
    list(artifact_type = "obs_table:trajectory_signature_smooth", primitive_kind = "obs_table", title = "Trajectory Signature Smooth Table", description = "Smoothed signature/module curves along trajectory pseudotime.", table_type = "trajectory_signature_smooth", entity_kind = "trajectory_bin", use_when = c("plot signature dynamics")),
    list(artifact_type = "obs_table:trajectory_geneset_dynamics_curve", primitive_kind = "obs_table", title = "Trajectory Gene-Set Curve Table", description = "Gene-set scores over pseudotime bins.", table_type = "trajectory_geneset_dynamics_curve", entity_kind = "trajectory_bin", use_when = c("plot GSEA-like dynamics", "find gene sets that turn on or off")),
    list(artifact_type = "obs_table:trajectory_geneset_dynamics", primitive_kind = "obs_table", title = "Trajectory Gene-Set Dynamics Table", description = "One row per gene set with dynamics metrics and curve class.", table_type = "trajectory_geneset_dynamics", entity_kind = "feature_set", use_when = c("rank dynamic gene sets", "filter turns_on/turns_off/transient terms")),
    list(artifact_type = "obs_table:trajectory_geneset_dynamics_drivers", primitive_kind = "obs_table", title = "Trajectory Gene-Set Driver Table", description = "Top member genes contributing to dynamic gene-set behavior.", table_type = "trajectory_geneset_dynamics_drivers", entity_kind = "feature", use_when = c("explain dynamic terms", "plot driver genes")),
    list(artifact_type = "obs_table:trajectory_geneset_dynamics_driver_curve", primitive_kind = "obs_table", title = "Trajectory Gene-Set Driver Curves", description = "Driver-gene curves for selected dynamic gene sets.", table_type = "trajectory_geneset_dynamics_driver_curve", entity_kind = "trajectory_bin", use_when = c("show which genes drive a dynamic term")),
    list(artifact_type = "obs_table:trajectory_signal_dynamics_curve", primitive_kind = "obs_table", title = "Trajectory Signal Curve Table", description = "Precomputed signal/vector-family curves over pseudotime.", table_type = "trajectory_signal_dynamics_curve", entity_kind = "trajectory_bin", use_when = c("plot UCell/chromVAR/signal dynamics")),
    list(artifact_type = "obs_table:trajectory_signal_dynamics", primitive_kind = "obs_table", title = "Trajectory Signal Dynamics Table", description = "Dynamics metrics and classes for precomputed signals.", table_type = "trajectory_signal_dynamics", entity_kind = "signal", use_when = c("rank dynamic UCell or chromVAR signals")),
    list(artifact_type = "obs_table:ucell_signature_summary", primitive_kind = "obs_table", title = "UCell Signature Summary", description = "Summary statistics for UCell signature scores.", table_type = "ucell_signature_summary", entity_kind = "signature", use_when = c("inspect signature score distributions")),
    list(artifact_type = "obs_table:cell_vector_winners", primitive_kind = "obs_table", title = "Cell Vector Winner Table", description = "Per-cell winner, runner-up, confidence, and pruning metrics from a cell_vector_family.", table_type = "cell_vector_winners", entity_kind = "cell", use_when = c("inspect score-family winner labels", "register winner cell sets")),
    list(artifact_type = "obs_table:winner_cell_set_manifest", primitive_kind = "obs_table", title = "Winner Cell-Set Manifest", description = "One row per registered winner-derived bundle cell set.", table_type = "winner_cell_set_manifest", entity_kind = "cell_set", use_when = c("audit winner cell sets", "report derived label sets")),
    list(artifact_type = "obs_table:chromvar_summary", primitive_kind = "obs_table", title = "chromVAR Motif Summary", description = "Summary statistics for chromVAR motif deviations.", table_type = "chromvar_summary", entity_kind = "motif", use_when = c("inspect motif activity summaries")),
    list(artifact_type = "obs_table:knn_neighbors", primitive_kind = "obs_table", title = "KNN Neighbor Table", description = "Cell-neighbor relationships from a KNN graph/query.", table_type = "knn_neighbors", entity_kind = "neighbor", use_when = c("inspect local neighborhoods")),
    list(artifact_type = "feature_table:knn_pseudobulk", primitive_kind = "feature_table", title = "KNN Pseudobulk Feature Table", description = "Feature summaries over KNN neighborhoods.", table_type = "knn_pseudobulk", entity_kind = "feature", use_when = c("inspect local pseudobulk expression")),
    list(artifact_type = "obs_table:matrix_log_normalize_summary", primitive_kind = "obs_table", title = "Matrix Log-Normalization Summary", description = "Summary of a persisted log-normalized matrix transform, including source matrix, output matrix, scale factor, dimensions, and library-size diagnostics.", table_type = "matrix_log_normalize_summary", entity_kind = "matrix", use_when = c("inspect normalized matrix provenance", "choose a reusable expression matrix for downstream ops"))
  )
}

.wb_known_source_table_types <- function() {
  entries <- list(
    c("attach_report", "obs_table"),
    c("cell_suffix_label", "obs_table"),
    c("cell_vector_assoc", "feature_table"),
    c("cell_vector_assoc_group_stats", "obs_table"),
    c("cell_vector_compare", "obs_table"),
    c("cell_vector_compare_summary", "obs_table"),
    c("cell_vector_family_calibration_summary", "obs_table"),
    c("cell_vector_family_qc_group_summary", "obs_table"),
    c("cell_vector_family_qc_key_summary", "obs_table"),
    c("cell_vector_family_qc_pairwise_summary", "obs_table"),
    c("cell_vector_family_reduce_decision_table", "obs_table"),
    c("cell_vector_family_reduce_summary", "obs_table"),
    c("cell_vector_winners", "obs_table"),
    c("chromvar_summary", "obs_table"),
    c("de_wilcox", "feature_table"),
    c("feature_trend_spearman", "feature_table"),
    c("generic", "obs_table"),
    c("ingest_report", "obs_table"),
    c("knn_neighbors", "obs_table"),
    c("knn_pseudobulk", "feature_table"),
    c("matrix_log_normalize_summary", "obs_table"),
    c("markers_topn", "feature_table"),
    c("pathway_enrich", "obs_table"),
    c("space_path_score_summary", "obs_table"),
    c("trajectory_branch_compare", "feature_table"),
    c("trajectory_branch_compare_summary", "obs_table"),
    c("trajectory_de", "feature_table"),
    c("trajectory_de_summary", "obs_table"),
    c("trajectory_geneset_dynamics", "obs_table"),
    c("trajectory_geneset_dynamics_curve", "obs_table"),
    c("trajectory_geneset_dynamics_driver_curve", "obs_table"),
    c("trajectory_geneset_dynamics_drivers", "obs_table"),
    c("trajectory_geneset_dynamics_summary", "obs_table"),
    c("trajectory_geneset_dynamics_top", "obs_table"),
    c("trajectory_route_smooth", "obs_table"),
    c("trajectory_route_smooth_summary", "obs_table"),
    c("trajectory_signal_dynamics", "obs_table"),
    c("trajectory_signal_dynamics_curve", "obs_table"),
    c("trajectory_signal_dynamics_summary", "obs_table"),
    c("trajectory_signal_dynamics_top", "obs_table"),
    c("trajectory_signature_smooth", "obs_table"),
    c("trajectory_signature_smooth_summary", "obs_table"),
    c("trajectory_smooth", "obs_table"),
    c("trajectory_smooth_summary", "obs_table"),
    c("trajectory_vector_smooth", "obs_table"),
    c("trajectory_vector_smooth_summary", "obs_table"),
    c("ucell_signature_summary", "obs_table"),
    c("winner_cell_set_manifest", "obs_table")
  )
  out <- as.data.frame(do.call(rbind, entries), stringsAsFactors = FALSE)
  names(out) <- c("table_type", "primitive_kind")
  out
}

.wb_artifact_type_catalog_fill_known_tables <- function(entries) {
  known <- .wb_known_source_table_types()
  existing <- vapply(entries, function(x) as.character(x$table_type %||% ""), character(1))
  for (i in seq_len(nrow(known))) {
    tt <- as.character(known$table_type[i])
    pk <- as.character(known$primitive_kind[i])
    if (tt %in% existing) next
    entries[[length(entries) + 1L]] <- list(
      artifact_type = paste0(pk, ":", tt),
      primitive_kind = pk,
      title = paste0("Table Type: ", tt),
      description = paste0("Promoted ", pk, " artifact with table_type='", tt, "'."),
      table_type = tt,
      entity_kind = if (identical(pk, "feature_table")) "feature" else "generic",
      use_when = c("inspect promoted table payload", "route artifact through semantic planning")
    )
    existing <- c(existing, tt)
  }
  entries
}

#' Export Artifact Type Catalog As Semantic Metadata
#'
#' @return A named list with promoted artifact type and table-type records.
#' @export
wb_artifact_type_catalog_semantic <- function() {
  artifact_types <- .wb_artifact_type_catalog_fill_known_tables(.wb_artifact_type_catalog_entries())
  .wb_semantic_catalog_clean(list(
    schema_version = "scworkbench.artifact_type_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    artifact_type_count = length(artifact_types),
    artifact_types = artifact_types
  ))
}

.wb_artifact_type_catalog_reference_lines <- function(catalog) {
  .wb_semantic_reference_lines(
    title = "scworkbench Artifact Type Catalog",
    generator = "wb_artifact_type_catalog_semantic()",
    count_label = "Artifact type count",
    count = catalog$artifact_type_count,
    records = catalog$artifact_types,
    id_field = "artifact_type",
    section_field = "primitive_kind",
    body_fn = function(x) {
      c(
        paste0("Title: ", as.character(x$title %||% "")[1]),
        "",
        paste0("Description: ", as.character(x$description %||% "")[1]),
        "",
        paste0("Table type: ", as.character(x$table_type %||% "(none)")[1]),
        "",
        paste0("Entity kind: ", as.character(x$entity_kind %||% "")[1]),
        "",
        "Use when:",
        if (length(x$use_when %||% character(0))) paste0("- ", as.character(x$use_when)) else "- (unspecified)"
      )
    }
  )
}

#' Write Artifact Type Catalog Reference Files
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the semantic artifact type catalog.
#' @export
wb_write_artifact_type_catalog_reference <- function(path_md = "docs/artifact_type_catalog_reference.md",
                                                     path_json = "docs/artifact_type_catalog_semantic.json") {
  catalog <- wb_artifact_type_catalog_semantic()
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    writeLines(.wb_artifact_type_catalog_reference_lines(catalog), con = path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "artifact type catalog semantic export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}
