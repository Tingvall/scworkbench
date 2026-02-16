#' Differential expression by Wilcoxon rank-sum (A vs B)
#'
#' Returns one row per feature with effect and significance metrics.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param cells_a Character vector of group-A cell IDs
#' @param cells_b Character vector of group-B cell IDs
#' @param features Optional feature IDs (default: all features in matrix)
#' @param min_pct Optional minimum detection fraction in either group
#' @param p_adjust_method P-value adjustment method
#' @export
wb_op_de_wilcox <- function(bundle,
                            matrix_id,
                            cells_a,
                            cells_b,
                            features = NULL,
                            min_pct = 0,
                            p_adjust_method = "BH") {
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(is.character(cells_a) && length(cells_a) >= 2, "cells_a must contain at least 2 cells.")
  .wb_assert(is.character(cells_b) && length(cells_b) >= 2, "cells_b must contain at least 2 cells.")

  cells_a <- unique(as.character(cells_a))
  cells_b <- unique(as.character(cells_b))
  .wb_assert(length(intersect(cells_a, cells_b)) == 0, "cells_a and cells_b must be disjoint.")

  feature_ids <- if (is.null(features)) wb_feature_ids(bundle, matrix_id) else as.character(features)
  .wb_assert(length(feature_ids) > 0, "No features available for DE.")

  de <- .wb_de_wilcox_core(
    bundle = bundle,
    matrix_id = matrix_id,
    features = feature_ids,
    cells_a = cells_a,
    cells_b = cells_b
  )

  if (!is.null(min_pct) && is.finite(min_pct) && min_pct > 0) {
    de <- de[pmax(de$pct_a, de$pct_b) >= as.numeric(min_pct), , drop = FALSE]
  }

  if (nrow(de) > 0) {
    de$p_val_adj <- stats::p.adjust(de$p_val, method = as.character(p_adjust_method)[1])
  } else {
    de$p_val_adj <- numeric(0)
  }

  de <- de[order(de$p_val_adj, -de$avg_log1p_fc), , drop = FALSE]
  rownames(de) <- NULL

  list(
    outputs = list(
      de_table = wb_prim_feature_table(
        table = de,
        table_type = "de_wilcox",
        meta = list(
          matrix_id = matrix_id,
          n_cells_a = length(cells_a),
          n_cells_b = length(cells_b)
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_features = nrow(de),
      n_cells_a = length(cells_a),
      n_cells_b = length(cells_b),
      min_pct = as.numeric(min_pct),
      p_adjust_method = as.character(p_adjust_method)[1]
    )
  )
}

#' Marker genes per cluster via one-vs-rest Wilcoxon DE
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param clusters Named vector: names=cell_id, values=cluster label
#' @param cells Cell universe to evaluate
#' @param features Optional feature IDs
#' @param top_n Top markers per cluster
#' @param min_pct Minimum detection fraction in either side
#' @param p_adjust_method P-value adjustment method
#' @export
wb_op_markers_topn <- function(bundle,
                               matrix_id,
                               clusters,
                               cells,
                               features = NULL,
                               top_n = 20,
                               min_pct = 0.1,
                               p_adjust_method = "BH") {
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(is.atomic(clusters) && !is.null(names(clusters)),
             "clusters must be a named vector (names=cell_id, values=cluster).")
  .wb_assert(is.character(cells) && length(cells) >= 10, "cells must contain at least 10 cells.")
  .wb_assert(is.numeric(top_n) && length(top_n) == 1 && top_n >= 1, "top_n must be >= 1.")

  cells <- unique(as.character(cells))
  cl <- as.character(clusters)
  names(cl) <- as.character(names(clusters))
  cl <- cl[cells]
  keep <- !is.na(cl)
  cells <- cells[keep]
  cl <- cl[keep]
  .wb_assert(length(cells) >= 10, "Too few cells with cluster labels.")

  labs <- sort(unique(cl))
  .wb_assert(length(labs) >= 2, "Need at least 2 clusters for marker testing.")

  feature_ids <- if (is.null(features)) wb_feature_ids(bundle, matrix_id) else as.character(features)
  .wb_assert(length(feature_ids) > 0, "No features available for marker testing.")

  rows <- vector("list", length(labs))
  for (i in seq_along(labs)) {
    lab <- labs[i]
    cells_a <- cells[cl == lab]
    cells_b <- cells[cl != lab]
    if (length(cells_a) < 2 || length(cells_b) < 2) {
      rows[[i]] <- data.frame()
      next
    }

    de <- .wb_de_wilcox_core(
      bundle = bundle,
      matrix_id = matrix_id,
      features = feature_ids,
      cells_a = cells_a,
      cells_b = cells_b
    )
    if (!is.null(min_pct) && is.finite(min_pct) && min_pct > 0) {
      de <- de[pmax(de$pct_a, de$pct_b) >= as.numeric(min_pct), , drop = FALSE]
    }
    if (nrow(de) == 0) {
      rows[[i]] <- data.frame()
      next
    }

    de$p_val_adj <- stats::p.adjust(de$p_val, method = as.character(p_adjust_method)[1])
    de$cluster <- lab
    de <- de[de$avg_log1p_fc > 0, , drop = FALSE]
    de <- de[order(de$p_val_adj, -de$avg_log1p_fc), , drop = FALSE]
    de <- utils::head(de, as.integer(top_n))
    rows[[i]] <- de
  }

  markers <- do.call(rbind, rows)
  if (is.null(markers) || nrow(markers) == 0) {
    markers <- data.frame(
      feature_id = character(0),
      pct_a = numeric(0),
      pct_b = numeric(0),
      avg_expr_a = numeric(0),
      avg_expr_b = numeric(0),
      avg_log1p_fc = numeric(0),
      p_val = numeric(0),
      p_val_adj = numeric(0),
      cluster = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    rownames(markers) <- NULL
  }

  list(
    outputs = list(
      markers = wb_prim_feature_table(
        table = markers,
        table_type = "markers_topn",
        meta = list(
          matrix_id = matrix_id,
          n_clusters = length(labs),
          top_n = as.integer(top_n)
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_clusters = length(labs),
      n_markers = nrow(markers),
      top_n = as.integer(top_n),
      min_pct = as.numeric(min_pct),
      p_adjust_method = as.character(p_adjust_method)[1]
    )
  )
}

.wb_de_wilcox_core <- function(bundle, matrix_id, features, cells_a, cells_b, chunk_size = 128L) {
  .wb_require_pkg("Matrix", "DE testing")

  features <- as.character(features)
  out <- vector("list", length(features))
  out_i <- 0L

  for (i in seq(1L, length(features), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(features))
    feats <- features[i:j]
    xa <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells_a)
    xb <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells_b)

    ma <- as.matrix(xa)
    mb <- as.matrix(xb)

    for (k in seq_along(feats)) {
      va <- as.numeric(ma[k, , drop = TRUE])
      vb <- as.numeric(mb[k, , drop = TRUE])

      p <- tryCatch(
        suppressWarnings(stats::wilcox.test(va, vb, alternative = "two.sided", exact = FALSE)$p.value),
        error = function(e) 1
      )

      out_i <- out_i + 1L
      out[[out_i]] <- data.frame(
        feature_id = feats[k],
        pct_a = mean(va > 0),
        pct_b = mean(vb > 0),
        avg_expr_a = mean(va),
        avg_expr_b = mean(vb),
        avg_log1p_fc = log1p(mean(va)) - log1p(mean(vb)),
        p_val = as.numeric(p),
        stringsAsFactors = FALSE
      )
    }
  }

  do.call(rbind, out[seq_len(out_i)])
}

.wb_resolve_group_cells <- function(bundle, x, effective_cells) {
  .wb_assert(!is.null(x), "Group input is missing.")
  eff <- unique(as.character(effective_cells))

  if (is.character(x) && length(x) == 1 && startsWith(x, "set:")) {
    set_name <- sub("^set:", "", x)
    cand <- wb_cells(bundle, cell_set = set_name)
  } else if (is.character(x)) {
    cand <- x
  } else {
    stop("Unsupported group input. Use cell IDs or 'set:<name>'.", call. = FALSE)
  }

  unique(intersect(as.character(cand), eff))
}

