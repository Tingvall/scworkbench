#' Feature-level continuous trend vs pseudotime (Spearman)
#'
#' Computes per-feature correlation against a continuous cell vector.
#'
#' @param bundle Bundle handle.
#' @param matrix_id Matrix identifier.
#' @param pseudotime Named numeric vector (names are cell IDs).
#' @param cells Optional cell IDs to restrict analysis.
#' @param features Optional feature IDs (default all in matrix).
#' @param min_pct_nonzero Optional minimum nonzero fraction filter.
#' @param p_adjust_method Method for p.adjust.
#' @param chunk_size Number of features per slice chunk.
#' @export
wb_op_feature_trend_spearman <- function(bundle,
                                         matrix_id,
                                         pseudotime,
                                         cells = NULL,
                                         features = NULL,
                                         min_pct_nonzero = 0,
                                         min_sd = 0,
                                         p_adjust_method = "BH",
                                         chunk_size = 128L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.atomic(pseudotime) && !is.null(names(pseudotime)),
             "pseudotime must be a named vector.")
  .wb_assert(is.numeric(min_sd) && length(min_sd) == 1 && is.finite(min_sd) && min_sd >= 0,
             "min_sd must be a non-negative scalar.")

  pt <- suppressWarnings(as.numeric(pseudotime))
  names(pt) <- as.character(names(pseudotime))
  .wb_assert(any(is.finite(pt)), "pseudotime has no finite values.")

  universe <- if (is.null(cells)) as.character(wb_cells(bundle, cell_set = "all")) else unique(as.character(cells))
  shared <- intersect(universe, names(pt))
  n_cells_input <- length(shared)
  .wb_assert(n_cells_input >= 10, "Need at least 10 cells with pseudotime.")

  pt <- pt[shared]
  keep <- is.finite(pt)
  pt <- pt[keep]
  shared <- names(pt)
  n_cells_used <- length(shared)
  .wb_assert(n_cells_used >= 10, "Too few finite pseudotime cells.")
  .wb_assert(stats::sd(pt) > 0, "pseudotime variance is zero.")

  feats <- if (is.null(features)) wb_feature_ids(bundle, matrix_id = matrix_id) else as.character(features)
  feats <- feats[nzchar(feats)]
  .wb_assert(length(feats) > 0, "No features selected.")
  n_features_input <- length(feats)

  out <- vector("list", length(feats))
  oi <- 0L
  n_filtered_min_cells <- 0L
  n_filtered_min_pct_nonzero <- 0L
  n_filtered_min_sd <- 0L

  for (i in seq(1L, length(feats), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(feats))
    f <- feats[i:j]
    x <- wb_slice(bundle, matrix_id = matrix_id, features = f, cells = shared)
    m <- as.matrix(x)
    for (k in seq_len(nrow(m))) {
      y0 <- as.numeric(m[k, ])
      ok <- is.finite(y0) & is.finite(pt)
      n_used <- sum(ok)
      n_dropped_na <- length(ok) - n_used
      if (n_used < 10L) {
        n_filtered_min_cells <- n_filtered_min_cells + 1L
        next
      }

      y <- y0[ok]
      pt_ok <- pt[ok]

      nz <- mean(y > 0)
      if (is.finite(min_pct_nonzero) && min_pct_nonzero > 0 && nz < as.numeric(min_pct_nonzero)) {
        n_filtered_min_pct_nonzero <- n_filtered_min_pct_nonzero + 1L
        next
      }

      sd_y <- stats::sd(y)
      if (!is.finite(sd_y) || sd_y < as.numeric(min_sd)) {
        n_filtered_min_sd <- n_filtered_min_sd + 1L
        next
      }

      rho <- suppressWarnings(stats::cor(y, pt_ok, method = "spearman"))
      if (!is.finite(rho)) next

      if (abs(rho) >= 1) {
        pval <- 0
      } else {
        tval <- rho * sqrt((n_used - 2) / pmax(1 - rho^2, .Machine$double.eps))
        pval <- 2 * stats::pt(abs(tval), df = n_used - 2, lower.tail = FALSE)
      }
      slope <- tryCatch(as.numeric(stats::coef(stats::lm(y ~ pt_ok))[2]), error = function(e) NA_real_)

      oi <- oi + 1L
      out[[oi]] <- data.frame(
        feature_id = rownames(m)[k],
        rho = rho,
        abs_rho = abs(rho),
        direction = ifelse(rho > 0, "up", ifelse(rho < 0, "down", "flat")),
        slope = slope,
        p_val = pval,
        pct_nonzero = nz,
        sd_expr = sd_y,
        mean_expr = mean(y),
        n_used = as.integer(n_used),
        n_dropped_na = as.integer(n_dropped_na),
        stringsAsFactors = FALSE
      )
    }
  }

  if (oi == 0L) {
    tbl <- data.frame(
      feature_id = character(0),
      rho = numeric(0),
      abs_rho = numeric(0),
      direction = character(0),
      slope = numeric(0),
      p_val = numeric(0),
      p_val_adj = numeric(0),
      pct_nonzero = numeric(0),
      sd_expr = numeric(0),
      mean_expr = numeric(0),
      n_used = integer(0),
      n_dropped_na = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    tbl <- do.call(rbind, out[seq_len(oi)])
    tbl$p_val_adj <- stats::p.adjust(tbl$p_val, method = as.character(p_adjust_method)[1])
    tbl <- tbl[order(tbl$p_val_adj, -tbl$abs_rho), , drop = FALSE]
    rownames(tbl) <- NULL
  }

  list(
    outputs = list(
      trend_table = wb_prim_feature_table(
        table = tbl,
        table_type = "feature_trend_spearman",
        meta = list(
          matrix_id = matrix_id,
          n_cells_input = as.integer(n_cells_input),
          n_cells_used = as.integer(n_cells_used),
          n_features_input = as.integer(n_features_input),
          n_features_tested = as.integer(nrow(tbl)),
          min_pct_nonzero = as.numeric(min_pct_nonzero),
          min_sd = as.numeric(min_sd),
          p_adjust_method = as.character(p_adjust_method)[1],
          n_filtered_min_cells = as.integer(n_filtered_min_cells),
          n_filtered_min_pct_nonzero = as.integer(n_filtered_min_pct_nonzero),
          n_filtered_min_sd = as.integer(n_filtered_min_sd)
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_cells_input = as.integer(n_cells_input),
      n_cells_used = as.integer(n_cells_used),
      n_features_input = as.integer(n_features_input),
      n_features_tested = as.integer(nrow(tbl)),
      min_pct_nonzero = as.numeric(min_pct_nonzero),
      min_sd = as.numeric(min_sd),
      p_adjust_method = as.character(p_adjust_method)[1],
      n_filtered_min_cells = as.integer(n_filtered_min_cells),
      n_filtered_min_pct_nonzero = as.integer(n_filtered_min_pct_nonzero),
      n_filtered_min_sd = as.integer(n_filtered_min_sd)
    )
  )
}
