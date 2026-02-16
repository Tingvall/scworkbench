#' Seurat-style module scoring (AddModuleScore)
#'
#' Computes per-cell module scores as:
#' mean(expression of module genes) - mean(expression of matched control genes)
#'
#' Control genes are sampled from expression bins (equal-frequency bins across a pool),
#' matching Seurat's AddModuleScore strategy.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier used as expression source
#' @param features Character vector (single module) or list of character vectors (multiple modules)
#' @param pool Optional character vector of feature_ids used as control-gene pool
#' @param cells Explicit cell_ids (required in session context)
#' @param nbin Number of expression bins for matching controls
#' @param ctrl Number of control genes sampled per feature
#' @param name Prefix for module names when `features` is unnamed
#' @param seed RNG seed for control sampling
#' @export
wb_op_addmodulescore <- function(bundle,
                                 matrix_id,
                                 features,
                                 pool = NULL,
                                 cells,
                                 nbin = 24,
                                 ctrl = 100,
                                 name = "Module",
                                 seed = 1) {
  .wb_require_pkg("Matrix", "module scoring")

  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_addmodulescore() must be called with 'cells' (use wb_session_run_op).")
  .wb_assert(is.numeric(nbin) && length(nbin) == 1 && nbin >= 2,
             "nbin must be >= 2.")
  .wb_assert(is.numeric(ctrl) && length(ctrl) == 1 && ctrl >= 1,
             "ctrl must be >= 1.")

  cells <- as.character(cells)
  all_features <- wb_feature_ids(bundle, matrix_id = matrix_id)

  modules <- .wb_normalize_module_features(features)
  module_names <- names(modules)
  if (is.null(module_names) || !all(nzchar(module_names))) {
    module_names <- paste0(as.character(name)[1], seq_along(modules))
  }
  names(modules) <- module_names

  modules <- lapply(modules, function(g) unique(intersect(as.character(g), all_features)))
  keep_mod <- vapply(modules, length, integer(1)) > 0
  .wb_assert(any(keep_mod), "None of the provided module features exist in the selected matrix.")
  modules <- modules[keep_mod]
  module_names <- names(modules)

  pool_use <- if (is.null(pool)) all_features else intersect(unique(as.character(pool)), all_features)
  .wb_assert(length(pool_use) >= 2, "Control pool is too small after filtering to matrix features.")

  if (!is.null(seed)) set.seed(as.integer(seed))

  # Compute per-feature average expression on selected cells for control matching bins.
  # This is chunked to avoid materializing huge feature x cell matrices.
  pool_avg <- .wb_feature_means_chunked(
    bundle = bundle,
    matrix_id = matrix_id,
    features = pool_use,
    cells = cells,
    chunk_size = 128L
  )

  bins <- .wb_equal_count_bins(pool_avg, nbin = as.integer(nbin))
  bin_map <- split(names(bins), bins)

  score_key <- character(0)
  score_cell <- character(0)
  score_value <- numeric(0)

  for (nm in module_names) {
    genes <- modules[[nm]]
    module_union <- genes

    ctrl_genes <- unique(unlist(lapply(genes, function(g) {
      gbin <- bins[[g]]
      cand <- setdiff(bin_map[[as.character(gbin)]], module_union)
      if (!length(cand)) return(character(0))
      n_pick <- min(as.integer(ctrl), length(cand))
      sample(cand, size = n_pick, replace = FALSE)
    }), use.names = FALSE))

    .wb_assert(length(ctrl_genes) > 0,
               paste0("No control genes available for module '", nm, "'. Try lower ctrl/nbin or provide a larger pool."))

    mod_mat <- wb_slice(bundle, matrix_id = matrix_id, features = genes, cells = cells)
    ctl_mat <- wb_slice(bundle, matrix_id = matrix_id, features = ctrl_genes, cells = cells)

    mod_score <- Matrix::colMeans(mod_mat)
    ctl_score <- Matrix::colMeans(ctl_mat)
    score <- as.numeric(mod_score - ctl_score)

    score_key <- c(score_key, rep(nm, length(cells)))
    score_cell <- c(score_cell, cells)
    score_value <- c(score_value, score)
  }

  list(
    outputs = list(
      module_scores = wb_prim_cell_vector_family(
        key = score_key,
        cell_id = score_cell,
        value = score_value,
        value_type = "continuous"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_modules = length(module_names),
      module_names = module_names,
      n_cells = length(cells),
      nbin = as.integer(nbin),
      ctrl = as.integer(ctrl),
      seed = if (is.null(seed)) NULL else as.integer(seed)
    )
  )
}

.wb_normalize_module_features <- function(features) {
  if (is.character(features)) {
    out <- list(features)
    names(out) <- "module1"
    return(out)
  }

  .wb_assert(is.list(features) && length(features) > 0,
             "features must be a character vector or a non-empty list of character vectors.")
  out <- lapply(features, function(x) {
    .wb_assert(is.character(x) && length(x) > 0,
               "each module in features must be a non-empty character vector.")
    as.character(x)
  })
  if (is.null(names(out))) names(out) <- paste0("module", seq_along(out))
  out
}

.wb_equal_count_bins <- function(x, nbin = 24L) {
  x_names <- names(x)
  x <- as.numeric(x)
  .wb_assert(length(x) > 0, "cannot bin empty vector")
  n <- length(x)
  nbin <- max(2L, min(as.integer(nbin), n))

  # Stable tie-breaking jitter to avoid degenerate buckets for many identical means.
  jitter <- seq_along(x) * .Machine$double.eps
  ord <- order(x + jitter, decreasing = FALSE, na.last = TRUE)

  bins_ord <- ceiling(seq_len(n) * nbin / n)
  bins <- integer(n)
  bins[ord] <- bins_ord
  names(bins) <- x_names
  bins
}

.wb_feature_means_chunked <- function(bundle, matrix_id, features, cells, chunk_size = 128L) {
  features <- as.character(features)
  .wb_assert(length(features) > 0, "features must be non-empty")
  .wb_assert(is.numeric(chunk_size) && chunk_size >= 1, "chunk_size must be >= 1")

  out <- numeric(length(features))
  names(out) <- features

  idx <- seq_len(length(features))
  for (i in seq(1L, length(features), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(features))
    feats <- features[idx[i:j]]
    x <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells)
    mu <- as.numeric(Matrix::rowMeans(x))
    names(mu) <- feats
    out[feats] <- mu
  }

  out
}
