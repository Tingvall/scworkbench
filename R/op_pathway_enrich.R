#' Pathway enrichment against all feature sets in a namespace
#'
#' Enriches a query feature list (typically derived from a DE feature table)
#' against all feature sets in the selected namespace for one matrix.
#'
#' @param bundle Bundle handle.
#' @param matrix_id Matrix identifier.
#' @param feature_table Feature table primitive payload (`data.frame`) containing feature IDs.
#' @param namespace Feature-set namespace to test (e.g. `msigdb_h`, `go_bp`, `user`).
#' @param feature_col Column in `feature_table` containing feature IDs.
#' @param p_adj_col Optional adjusted p-value column for query filtering.
#' @param p_adj_max Maximum adjusted p-value (applied when `p_adj_col` exists).
#' @param lfc_col Optional effect-size column (e.g. `avg_log1p_fc`) for directional filtering.
#' @param direction One of `any`, `up`, `down`.
#' @param lfc_min_abs Minimum absolute effect size when `direction='any'`.
#' @param lfc_min Directional minimum effect size when `direction='up'`/`'down'`.
#' @param min_set_size Minimum pathway size to test.
#' @param max_set_size Maximum pathway size to test.
#' @param p_adjust_method Method for `p.adjust`.
#' @export
wb_op_pathway_enrich <- function(bundle,
                                 matrix_id,
                                 feature_table,
                                 namespace,
                                 feature_col = "feature_id",
                                 p_adj_col = "p_val_adj",
                                 p_adj_max = 0.05,
                                 lfc_col = "avg_log1p_fc",
                                 direction = "any",
                                 lfc_min_abs = 0,
                                 lfc_min = 0.25,
                                 min_set_size = 5L,
                                 max_set_size = 5000L,
                                 p_adjust_method = "BH") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.data.frame(feature_table), "feature_table must be a data.frame")
  .wb_assert(is.character(namespace) && length(namespace) == 1 && nzchar(namespace), "namespace invalid")
  .wb_assert(is.character(feature_col) && length(feature_col) == 1 && nzchar(feature_col), "feature_col invalid")
  .wb_assert(feature_col %in% names(feature_table), paste0("feature_col not found: ", feature_col))

  direction <- tolower(as.character(direction %||% "any")[1])
  .wb_assert(direction %in% c("any", "up", "down"), "direction must be one of: any, up, down")

  q <- feature_table
  q[[feature_col]] <- as.character(q[[feature_col]])
  q <- q[nzchar(q[[feature_col]]), , drop = FALSE]

  # Optional adjusted-p filtering
  if (!is.null(p_adj_col) && is.character(p_adj_col) && length(p_adj_col) == 1 &&
      nzchar(p_adj_col) && p_adj_col %in% names(q)) {
    pv <- suppressWarnings(as.numeric(q[[p_adj_col]]))
    q <- q[!is.na(pv) & pv <= as.numeric(p_adj_max), , drop = FALSE]
  }

  # Optional directional/effect filtering
  if (!is.null(lfc_col) && is.character(lfc_col) && length(lfc_col) == 1 &&
      nzchar(lfc_col) && lfc_col %in% names(q)) {
    lf <- suppressWarnings(as.numeric(q[[lfc_col]]))
    if (identical(direction, "up")) {
      q <- q[!is.na(lf) & lf >= as.numeric(lfc_min), , drop = FALSE]
    } else if (identical(direction, "down")) {
      q <- q[!is.na(lf) & lf <= -as.numeric(lfc_min), , drop = FALSE]
    } else {
      q <- q[!is.na(lf) & abs(lf) >= as.numeric(lfc_min_abs), , drop = FALSE]
    }
  }

  query_ids <- unique(as.character(q[[feature_col]]))
  query_ids <- query_ids[nzchar(query_ids)]
  .wb_assert(length(query_ids) > 0, "No query features after filtering.")

  universe <- unique(as.character(wb_feature_ids(bundle, matrix_id = matrix_id)))
  universe <- universe[nzchar(universe)]
  .wb_assert(length(universe) > 0, "No feature universe for matrix_id.")

  query_ids <- intersect(query_ids, universe)
  .wb_assert(length(query_ids) > 0, "No query features overlap matrix universe.")

  fs <- wb_feature_sets(bundle, matrix_id = matrix_id, namespace = namespace)
  .wb_assert(is.data.frame(fs) && nrow(fs) > 0,
             paste0("No feature sets found for namespace='", namespace, "' and matrix_id='", matrix_id, "'."))

  sets <- unique(as.character(fs$feature_set))
  sets <- sets[nzchar(sets)]
  .wb_assert(length(sets) > 0, "No feature sets available after filtering.")

  rows <- vector("list", length(sets))
  out_i <- 0L
  n_universe <- length(universe)
  n_query <- length(query_ids)

  for (sn in sets) {
    members <- as.character(wb_feature_set_get(bundle, feature_set = sn, matrix_id = matrix_id))
    members <- unique(intersect(members, universe))
    set_size <- length(members)
    if (set_size < as.integer(min_set_size) || set_size > as.integer(max_set_size)) next

    overlap <- intersect(query_ids, members)
    k <- length(overlap)
    if (k == 0L) {
      pval <- 1
      enr <- 0
    } else {
      # Hypergeometric upper-tail: P[X >= k]
      pval <- stats::phyper(k - 1L, set_size, n_universe - set_size, n_query, lower.tail = FALSE)
      enr <- (k / n_query) / (set_size / n_universe)
    }

    out_i <- out_i + 1L
    rows[[out_i]] <- data.frame(
      feature_id = as.character(sn),
      pathway = sn,
      namespace = as.character(namespace),
      matrix_id = as.character(matrix_id),
      set_size = as.integer(set_size),
      query_size = as.integer(n_query),
      universe_size = as.integer(n_universe),
      overlap = as.integer(k),
      enrichment_ratio = as.numeric(enr),
      p_val = as.numeric(pval),
      overlap_genes = paste(head(overlap, 200), collapse = ","),
      stringsAsFactors = FALSE
    )
  }

  if (out_i == 0L) {
    out <- data.frame(
      feature_id = character(0),
      pathway = character(0),
      namespace = character(0),
      matrix_id = character(0),
      set_size = integer(0),
      query_size = integer(0),
      universe_size = integer(0),
      overlap = integer(0),
      enrichment_ratio = numeric(0),
      p_val = numeric(0),
      p_val_adj = numeric(0),
      overlap_genes = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, rows[seq_len(out_i)])
    out$p_val_adj <- stats::p.adjust(out$p_val, method = as.character(p_adjust_method)[1])
    out <- out[order(out$p_val_adj, -out$enrichment_ratio, -out$overlap), , drop = FALSE]
    rownames(out) <- NULL
  }

  list(
    outputs = list(
      pathways = wb_prim_obs_table(
        table = out,
        table_type = "pathway_enrich",
        entity_kind = "pathway",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          query_size = as.integer(n_query),
          universe_size = as.integer(n_universe)
        )
      )
    ),
    params = list(
      matrix_id = as.character(matrix_id),
      namespace = as.character(namespace),
      n_query = as.integer(n_query),
      n_universe = as.integer(n_universe),
      n_pathways = nrow(out),
      direction = as.character(direction),
      p_adj_max = as.numeric(p_adj_max),
      min_set_size = as.integer(min_set_size),
      max_set_size = as.integer(max_set_size),
      p_adjust_method = as.character(p_adjust_method)[1]
    )
  )
}
