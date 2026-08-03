# First-pass RNA map construction ops: HVG selection and PCA.

.wb_matrix_block <- function(bundle, matrix_id, feature_ids, cell_ids) {
  frags <- tryCatch(wb_matrix_fragments(bundle, matrix_id), error = function(e) data.frame())
  if (nrow(frags) > 1L) {
    return(wb_matrix_read_features(bundle, matrix_id, feature_ids = feature_ids, cell_ids = cell_ids))
  }
  wb_slice(bundle, matrix_id = matrix_id, features = feature_ids, cells = cell_ids)
}

.wb_matrix_feature_stats <- function(bundle, matrix_id, features, cells, chunk_size = 256L) {
  .wb_require_pkg("Matrix", "feature statistics")
  features <- as.character(features)
  cells <- as.character(cells)
  chunk_size <- max(1L, as.integer(chunk_size)[1])
  chunks <- split(features, ceiling(seq_along(features) / chunk_size))

  out <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    feats <- chunks[[i]]
    x <- .wb_matrix_block(bundle, matrix_id, feature_ids = feats, cell_ids = cells)
    if (!inherits(x, "Matrix") && !is.matrix(x)) x <- as.matrix(x)
    n <- ncol(x)
    mu <- as.numeric(Matrix::rowMeans(x))
    ss <- as.numeric(Matrix::rowSums(x * x))
    var <- if (n > 1L) pmax((ss - n * mu * mu) / (n - 1L), 0) else rep(NA_real_, length(mu))
    detected <- as.numeric(Matrix::rowSums(x > 0))
    out[[i]] <- data.frame(
      feature_id = feats,
      mean = mu,
      variance = var,
      detected_cells = detected,
      detected_fraction = detected / max(n, 1L),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out)
}

.wb_hvg_score <- function(mean, variance, method = "vst") {
  method <- match.arg(method, c("vst", "dispersion", "variance"))
  if (identical(method, "variance")) return(variance)
  disp <- variance / pmax(mean, .Machine$double.eps)
  if (identical(method, "dispersion")) return(disp)
  log1p(pmax(disp, 0))
}

#' Select Highly Variable Features
#'
#' Computes feature-wise mean, variance, detection fraction, and a method score
#' from a matrix without materializing the whole matrix at once. The current
#' `"vst"` method is a lightweight stabilized dispersion score,
#' `log1p(variance / mean)`. Batch-aware HVG selection is not implemented.
#'
#' @export
wb_op_hvg_select <- function(bundle,
                             matrix_id,
                             cells = NULL,
                             n_features = 2000L,
                             method = c("vst", "dispersion", "variance"),
                             min_mean = NULL,
                             max_mean = NULL,
                             min_dispersion = NULL,
                             batch_key = NULL,
                             exclude_features = NULL,
                             feature_type = NULL,
                             seed = 1L,
                             chunk_size = 256L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id invalid")
  method <- match.arg(method)
  .wb_assert(is.null(batch_key) || identical(batch_key, "") || is.na(batch_key),
             "hvg_select: batch_key is reserved but not implemented; run without batch_key.")
  n_features <- suppressWarnings(as.integer(n_features)[1])
  .wb_assert(is.finite(n_features) && n_features > 0L, "n_features must be positive")
  seed <- suppressWarnings(as.integer(seed)[1])
  if (is.finite(seed)) set.seed(seed)

  matrix_row <- wb_matrix_info(bundle, matrix_id = matrix_id)
  .wb_assert(nrow(matrix_row) == 1L, paste0("matrix not found: ", matrix_id))
  cells <- as.character(cells %||% wb_cells(bundle, cell_set = "all"))
  .wb_assert(length(cells) > 0L, "hvg_select: no cells selected")

  features <- wb_feature_ids(bundle, matrix_id = matrix_id, feature_type = feature_type)
  if (!is.null(exclude_features)) {
    features <- setdiff(features, as.character(exclude_features))
  }
  .wb_assert(length(features) > 0L, "hvg_select: no features available after filters")

  stats <- .wb_matrix_feature_stats(bundle, matrix_id, features, cells, chunk_size = chunk_size)
  stats$dispersion <- stats$variance / pmax(stats$mean, .Machine$double.eps)
  stats$score <- .wb_hvg_score(stats$mean, stats$variance, method = method)
  stats$method <- method
  stats$matrix_id <- matrix_id

  passes <- is.finite(stats$score)
  if (!is.null(min_mean)) passes <- passes & stats$mean >= as.numeric(min_mean)[1]
  if (!is.null(max_mean)) passes <- passes & stats$mean <= as.numeric(max_mean)[1]
  if (!is.null(min_dispersion)) passes <- passes & stats$score >= as.numeric(min_dispersion)[1]

  ord <- order(!passes, -stats$score, -stats$variance, stats$feature_id, na.last = TRUE)
  rank_all <- integer(nrow(stats))
  rank_all[ord] <- seq_along(ord)
  selected_ord <- ord[passes[ord]]
  selected_ord <- selected_ord[seq_len(min(length(selected_ord), n_features))]
  stats$selected <- FALSE
  stats$selected[selected_ord] <- TRUE
  stats$rank <- rank_all

  stats <- stats[order(stats$rank), c(
    "feature_id", "rank", "mean", "variance", "dispersion", "score",
    "detected_cells", "detected_fraction", "selected", "method", "matrix_id"
  ), drop = FALSE]
  rownames(stats) <- NULL

  summary <- data.frame(
    matrix_id = matrix_id,
    method = method,
    n_cells = as.integer(length(cells)),
    n_input_features = as.integer(length(features)),
    n_passing_filters = as.integer(sum(passes, na.rm = TRUE)),
    n_selected_features = as.integer(sum(stats$selected, na.rm = TRUE)),
    min_mean = as.numeric(min_mean %||% NA_real_),
    max_mean = as.numeric(max_mean %||% NA_real_),
    min_dispersion = as.numeric(min_dispersion %||% NA_real_),
    batch_key = as.character(batch_key %||% NA_character_)[1],
    feature_type = as.character(feature_type %||% NA_character_)[1],
    chunk_size = as.integer(chunk_size),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      selected_features = wb_prim_feature_table(
        stats,
        table_type = "feature_selection_table",
        meta = list(
          selection_kind = "highly_variable_features",
          matrix_id = matrix_id,
          method = method,
          n_selected_features = as.integer(sum(stats$selected, na.rm = TRUE))
        )
      ),
      fit_summary = wb_prim_obs_table(
        summary,
        table_type = "hvg_select_summary",
        entity_kind = "matrix",
        meta = list(matrix_id = matrix_id, method = method)
      )
    ),
    params = as.list(summary[1, , drop = FALSE])
  )
}

.wb_pca_feature_ids_from_table <- function(feature_table) {
  .wb_assert(is.data.frame(feature_table), "pca_fit: feature_table must contain a data.frame")
  .wb_assert("feature_id" %in% names(feature_table), "pca_fit: feature_table requires feature_id")
  tab <- feature_table
  if ("selected" %in% names(tab)) {
    sel <- suppressWarnings(as.logical(tab$selected))
    if (any(sel, na.rm = TRUE)) tab <- tab[!is.na(sel) & sel, , drop = FALSE]
  }
  feats <- unique(as.character(tab$feature_id))
  feats[nzchar(feats)]
}

#' Fit PCA From A Matrix
#'
#' Computes PCA coordinates from selected features and persists them as a normal
#' scworkbench space. The default `backend = "irlba"` uses
#' `irlba::prcomp_irlba()`.
#'
#' @export
wb_op_pca_fit <- function(bundle,
                          matrix_id,
                          cells = NULL,
                          feature_table = NULL,
                          feature_ids = NULL,
                          n_components = 50L,
                          center = TRUE,
                          scale = TRUE,
                          backend = c("irlba", "prcomp"),
                          seed = 1L,
                          space_id_out = "rna.pca",
                          overwrite = FALSE,
                          max_dense_gb = 8) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "pca_fit")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id invalid")
  backend <- match.arg(backend)
  seed <- suppressWarnings(as.integer(seed)[1])
  if (is.finite(seed)) set.seed(seed)
  n_components <- suppressWarnings(as.integer(n_components)[1])
  .wb_assert(is.finite(n_components) && n_components >= 2L, "n_components must be at least 2 because scworkbench spaces require at least two dimensions")
  space_id_out <- as.character(space_id_out %||% "")[1]
  .wb_assert(nzchar(space_id_out), "space_id_out must be non-empty")

  matrix_row <- wb_matrix_info(bundle, matrix_id = matrix_id)
  .wb_assert(nrow(matrix_row) == 1L, paste0("matrix not found: ", matrix_id))
  cells <- as.character(cells %||% wb_cells(bundle, cell_set = "all"))
  .wb_assert(length(cells) > 2L, "pca_fit: at least three cells are required")

  if (!is.null(feature_table)) {
    feature_ids <- .wb_pca_feature_ids_from_table(feature_table$table)
  } else {
    feature_ids <- as.character(feature_ids %||% wb_feature_ids(bundle, matrix_id = matrix_id))
    feature_ids <- feature_ids[nzchar(feature_ids)]
  }
  available <- wb_feature_ids(bundle, matrix_id = matrix_id)
  feature_ids <- intersect(feature_ids, available)
  .wb_assert(length(feature_ids) >= 2L, "pca_fit: at least two valid features are required")

  max_rank <- min(length(cells) - 1L, length(feature_ids) - 1L)
  .wb_assert(n_components <= max_rank,
             paste0("pca_fit: n_components=", n_components, " exceeds max rank ", max_rank, "."))

  approx_gb <- length(cells) * length(feature_ids) * 8 / 1024^3
  max_dense_gb <- suppressWarnings(as.numeric(max_dense_gb)[1])
  .wb_assert(is.finite(max_dense_gb) && max_dense_gb > 0, "max_dense_gb must be positive")
  .wb_assert(approx_gb <= max_dense_gb || identical(backend, "irlba"),
             paste0("pca_fit: selected block is approximately ", round(approx_gb, 2),
                    " GB dense; increase max_dense_gb or use backend='irlba'."))

  block <- .wb_matrix_block(bundle, matrix_id, feature_ids = feature_ids, cell_ids = cells)
  if (!inherits(block, "Matrix") && !is.matrix(block)) block <- as.matrix(block)
  x <- Matrix::t(block)
  rownames(x) <- cells
  colnames(x) <- feature_ids

  n_feat_input <- length(feature_ids)
  feat_mean <- as.numeric(Matrix::colMeans(x))
  feat_ss <- as.numeric(Matrix::colSums(x * x))
  feat_var <- if (nrow(x) > 1L) pmax((feat_ss - nrow(x) * feat_mean * feat_mean) / (nrow(x) - 1L), 0) else rep(NA_real_, ncol(x))
  keep_feature <- is.finite(feat_var) & feat_var > 0
  .wb_assert(sum(keep_feature) >= 2L, "pca_fit: fewer than two non-constant features remain after variance filtering.")
  if (!all(keep_feature)) {
    x <- x[, keep_feature, drop = FALSE]
    feature_ids <- colnames(x)
  }

  max_rank <- min(nrow(x) - 1L, ncol(x) - 1L)
  .wb_assert(n_components <= max_rank,
             paste0("pca_fit: n_components=", n_components,
                    " exceeds max rank ", max_rank, " after non-constant feature filtering."))

  if (identical(backend, "irlba")) {
    .wb_require_pkg("irlba", "pca_fit backend='irlba'")
    fit <- irlba::prcomp_irlba(
      x,
      n = n_components,
      center = isTRUE(center),
      scale. = isTRUE(scale)
    )
  } else {
    .wb_assert(approx_gb <= max_dense_gb,
               paste0("pca_fit: backend='prcomp' would materialize about ", round(approx_gb, 2), " GB."))
    fit <- stats::prcomp(
      as.matrix(x),
      rank. = n_components,
      center = isTRUE(center),
      scale. = isTRUE(scale)
    )
  }

  coords <- fit$x[, seq_len(n_components), drop = FALSE]
  colnames(coords) <- paste0("PC", seq_len(n_components))
  rownames(coords) <- cells
  wb_add_space(
    bundle,
    space_id = space_id_out,
    coords = coords,
    description = paste0("PCA from matrix ", matrix_id, " using ", length(feature_ids), " features."),
    source = "pca_fit",
    overwrite = isTRUE(overwrite)
  )

  rot <- fit$rotation[, seq_len(n_components), drop = FALSE]
  if (is.null(rownames(rot)) || length(rownames(rot)) != nrow(rot) || any(!nzchar(rownames(rot)))) {
    rownames(rot) <- feature_ids
  }
  loadings <- data.frame(
    feature_id = rep(rownames(rot), times = ncol(rot)),
    PC = rep(paste0("PC", seq_len(ncol(rot))), each = nrow(rot)),
    component = rep(seq_len(ncol(rot)), each = nrow(rot)),
    loading = as.numeric(rot),
    matrix_id = matrix_id,
    space_id = space_id_out,
    stringsAsFactors = FALSE
  )

  stdev <- as.numeric(fit$sdev[seq_len(n_components)])
  variance <- stdev^2
  total_variance <- sum(as.numeric(fit$sdev)^2)
  variance_explained <- variance / total_variance
  variance_tbl <- data.frame(
    PC = paste0("PC", seq_len(n_components)),
    component = seq_len(n_components),
    stdev = stdev,
    variance = variance,
    variance_explained = variance_explained,
    cumulative_variance_explained = cumsum(variance_explained),
    matrix_id = matrix_id,
    space_id = space_id_out,
    stringsAsFactors = FALSE
  )

  summary <- data.frame(
    matrix_id = matrix_id,
    space_id = space_id_out,
    n_cells = as.integer(length(cells)),
    n_features_input = as.integer(n_feat_input),
    n_features = as.integer(length(feature_ids)),
    n_features_filtered_constant = as.integer(n_feat_input - length(feature_ids)),
    n_components = as.integer(n_components),
    center = isTRUE(center),
    scale = isTRUE(scale),
    backend = backend,
    seed = as.integer(seed),
    approx_dense_gb = as.numeric(approx_gb),
    max_dense_gb = as.numeric(max_dense_gb),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      space = wb_prim_space(space_id_out),
      loadings = wb_prim_feature_table(
        loadings,
        table_type = "pca_loadings",
        meta = list(matrix_id = matrix_id, space_id = space_id_out)
      ),
      variance = wb_prim_obs_table(
        variance_tbl,
        table_type = "pca_variance_explained",
        entity_kind = "principal_component",
        meta = list(matrix_id = matrix_id, space_id = space_id_out)
      ),
      fit_summary = wb_prim_obs_table(
        summary,
        table_type = "pca_fit_summary",
        entity_kind = "space",
        meta = list(matrix_id = matrix_id, space_id = space_id_out)
      )
    ),
    params = as.list(summary[1, , drop = FALSE])
  )
}
