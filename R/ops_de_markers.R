# Private statistical helpers still used by unmigrated core operations. The
# public de_wilcox and markers_topn methods live only in scwbStatistics.

.wb_de_wilcox_core <- function(bundle, matrix_id, features, cells_a, cells_b,
                                chunk_size = 128L) {
  .wb_require_pkg("Matrix", "DE testing")
  features <- as.character(features)
  out <- vector("list", length(features)); out_i <- 0L
  for (i in seq(1L, length(features), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(features))
    feats <- features[i:j]
    ma <- as.matrix(wb_slice(bundle, matrix_id = matrix_id, features = feats,
      cells = cells_a))
    mb <- as.matrix(wb_slice(bundle, matrix_id = matrix_id, features = feats,
      cells = cells_b))
    for (k in seq_along(feats)) {
      va <- as.numeric(ma[k, , drop = TRUE]); vb <- as.numeric(mb[k, , drop = TRUE])
      p <- tryCatch(suppressWarnings(stats::wilcox.test(va, vb,
        alternative = "two.sided", exact = FALSE)$p.value), error = function(e) 1)
      out_i <- out_i + 1L
      out[[out_i]] <- data.frame(feature_id = feats[k], pct_a = mean(va > 0),
        pct_b = mean(vb > 0), avg_expr_a = mean(va), avg_expr_b = mean(vb),
        avg_log1p_fc = log1p(mean(va)) - log1p(mean(vb)), p_val = as.numeric(p),
        stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out[seq_len(out_i)])
}

.wb_resolve_group_cells <- function(bundle, x, effective_cells) {
  .wb_assert(!is.null(x), "Group input is missing.")
  effective <- unique(as.character(effective_cells))
  if (is.character(x) && length(x) == 1L) {
    token <- as.character(x)[1]
    known <- try(as.character(wb_cell_sets(bundle)), silent = TRUE)
    if (inherits(known, "try-error")) known <- character()
    is_set <- startsWith(token, "set:") || token %in% c("core", "all") || token %in% known
    candidates <- if (is_set) wb_cells(bundle, cell_set = token) else token
    if (is_set && !length(candidates) && !startsWith(token, "set:") &&
        !token %in% c("core", "all")) {
      candidates <- wb_cells(bundle, cell_set = paste0("set:", token))
    }
  } else if (is.character(x)) {
    candidates <- x
  } else {
    stop("Unsupported group input. Use cell IDs, 'core'/'all', or set selectors.", call. = FALSE)
  }
  unique(intersect(as.character(candidates), effective))
}
