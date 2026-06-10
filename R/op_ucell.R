#' Compute UCell Signature Scores
#'
#' Computes per-cell signature scores using the UCell rank-based method.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier used as expression source.
#' @param features Character vector (single signature) or list of character
#'   vectors (multiple signatures).
#' @param cells Explicit cell ids. Required in session context.
#' @param name Prefix for signature names when `features` is unnamed.
#' @param max_rank Maximum rank considered by UCell.
#' @param ncores Number of worker processes requested by UCell.
#' @param parallel_backend Execution backend for UCell. One of `"auto"` or
#'   `"serial"`.
#' @param chunk_size Cell chunk size. A positive integer enables cell-axis
#'   chunking when `length(cells) > chunk_size`; `NULL` disables chunking.
#' @param missing_features_policy How to handle signature features missing from
#'   the matrix. One of `"drop"` or `"error"`.
#'
#' @return A standard op result list with `outputs$signature_scores` and
#'   `outputs$signature_summary`, plus normalized `params`.
#'
#' @export
.wb_ucell_normalize_signatures <- function(features, name = "Signature") {
  signatures <- .wb_normalize_module_features(features)
  signature_names <- names(signatures)
  if (is.null(signature_names) || !all(nzchar(signature_names))) {
    signature_names <- paste0(as.character(name)[1], seq_along(signatures))
  }
  names(signatures) <- signature_names
  signatures
}

.wb_ucell_signature_meta <- function(bundle,
                                     matrix_id,
                                     signatures,
                                     missing_features_policy = c("drop", "error")) {
  missing_features_policy <- match.arg(as.character(missing_features_policy)[1], c("drop", "error"))
  all_features <- wb_feature_ids(bundle, matrix_id = matrix_id)
  signature_names <- names(signatures) %||% character(0)

  sig_meta <- lapply(signature_names, function(sig_name) {
    feats_in <- unique(as.character(signatures[[sig_name]]))
    feats_match <- intersect(feats_in, all_features)
    feats_missing <- setdiff(feats_in, all_features)

    if (identical(missing_features_policy, "error") && length(feats_missing) > 0L) {
      stop(
        paste0(
          "UCell signature '", sig_name, "' contains missing features: ",
          paste(utils::head(feats_missing, 10L), collapse = ", "),
          if (length(feats_missing) > 10L) " ..." else ""
        ),
        call. = FALSE
      )
    }

    .wb_assert(length(feats_match) > 0L,
               paste0("UCell signature '", sig_name, "' has no features present in matrix '", matrix_id, "'."))

    list(
      signature = sig_name,
      features_input = feats_in,
      features_matched = feats_match,
      features_missing = feats_missing
    )
  })
  names(sig_meta) <- signature_names
  sig_meta
}

.wb_ucell_summary_table <- function(sig_meta, score_prim) {
  .wb_assert(is.list(sig_meta) && length(sig_meta) > 0L, "sig_meta must be a non-empty list")
  .wb_assert_kind(score_prim, "cell_vector_family")

  score_df <- wb_primitive_to_table(score_prim, include_context = FALSE)
  signature_names <- names(sig_meta)
  summary_rows <- vector("list", length(signature_names))

  for (i in seq_along(signature_names)) {
    sig_name <- signature_names[i]
    vals <- suppressWarnings(as.numeric(score_df$value[score_df$key == sig_name]))
    .wb_assert(length(vals) > 0L, paste0("Missing merged UCell scores for signature '", sig_name, "'."))

    meta <- sig_meta[[sig_name]]
    q <- stats::quantile(vals, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE, type = 7)
    summary_rows[[i]] <- data.frame(
      entity_id = sig_name,
      signature = sig_name,
      n_features_input = length(meta$features_input),
      n_features_matched = length(meta$features_matched),
      n_features_missing = length(meta$features_missing),
      matched_features = paste(meta$features_matched, collapse = ";"),
      missing_features = paste(meta$features_missing, collapse = ";"),
      score_min = suppressWarnings(min(vals, na.rm = TRUE)),
      score_q25 = as.numeric(q[1]),
      score_median = as.numeric(q[2]),
      score_mean = suppressWarnings(mean(vals, na.rm = TRUE)),
      score_q75 = as.numeric(q[3]),
      score_max = suppressWarnings(max(vals, na.rm = TRUE)),
      n_cells = length(vals),
      stringsAsFactors = FALSE
    )
  }

  summary_tbl <- do.call(rbind, summary_rows)
  rownames(summary_tbl) <- NULL
  summary_tbl
}

.wb_ucell_summary_prim <- function(sig_meta, score_prim, matrix_id, missing_features_policy) {
  wb_prim_obs_table(
    table = .wb_ucell_summary_table(sig_meta, score_prim),
    table_type = "ucell_signature_summary",
    entity_kind = "signature",
    meta = list(
      matrix_id = matrix_id,
      missing_features_policy = as.character(missing_features_policy)[1]
    )
  )
}

wb_op_ucell <- function(bundle,
                        matrix_id,
                        features,
                        cells,
                        name = "Signature",
                        max_rank = 1500L,
                        ncores = 1L,
                        parallel_backend = c("auto", "serial"),
                        chunk_size = 2000L,
                        missing_features_policy = c("drop", "error")) {
  .wb_require_pkg("UCell", "UCell signature scoring")
  .wb_require_pkg("Matrix", "UCell signature scoring")
  .wb_require_pkg("BiocParallel", "UCell parallel backend selection")

  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_ucell() must be called with 'cells' (use wb_session_run_op).")
  .wb_assert(is.numeric(max_rank) && length(max_rank) == 1 && is.finite(max_rank) && max_rank >= 1,
             "max_rank must be >= 1.")
  .wb_assert(is.numeric(ncores) && length(ncores) == 1 && is.finite(ncores) && ncores >= 1,
             "ncores must be >= 1.")

  parallel_backend <- match.arg(as.character(parallel_backend)[1], c("auto", "serial"))
  missing_features_policy <- match.arg(as.character(missing_features_policy)[1], c("drop", "error"))
  cells <- as.character(cells)
  all_features <- wb_feature_ids(bundle, matrix_id = matrix_id)
  signatures <- .wb_ucell_normalize_signatures(features, name = name)
  signature_names <- names(signatures)
  sig_meta <- .wb_ucell_signature_meta(
    bundle = bundle,
    matrix_id = matrix_id,
    signatures = signatures,
    missing_features_policy = missing_features_policy
  )

  chunk_size_i <- suppressWarnings(as.integer(chunk_size %||% NA_integer_)[1])
  if (is.finite(chunk_size_i) && chunk_size_i > 0L && length(cells) > chunk_size_i) {
    run_one <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
      wb_op_ucell(
        bundle = bundle,
        matrix_id = matrix_id,
        features = signatures,
        cells = as.character(effective_cells),
        name = name,
        max_rank = max_rank,
        ncores = ncores,
        parallel_backend = parallel_backend,
        chunk_size = NULL,
        missing_features_policy = missing_features_policy
      )
    }

    raw_chunked <- .wb_run_op_in_chunks(
      bundle = bundle,
      resolved = list(matrix = wb_prim_matrix(matrix_id)),
      effective_cells = cells,
      inputs = list(features = signatures),
      runner = run_one,
      chunk_axis = "cells",
      chunk_size = chunk_size_i,
      merge_spec = list(
        signature_scores = "row_bind_cell_vector_family"
      ),
      context = list(
        signature_scores = list(
          cell_order = cells,
          key_order = signature_names
        )
      )
    )

    score_prim <- raw_chunked$outputs$signature_scores
    return(list(
      outputs = list(
        signature_scores = score_prim,
        signature_summary = .wb_ucell_summary_prim(
          sig_meta = sig_meta,
          score_prim = score_prim,
          matrix_id = matrix_id,
          missing_features_policy = missing_features_policy
        )
      ),
      params = list(
        matrix_id = matrix_id,
        n_signatures = length(signature_names),
        signature_names = signature_names,
        n_cells = length(cells),
        max_rank = as.integer(max_rank),
        ncores = as.integer(ncores),
        parallel_backend = parallel_backend,
        missing_features_policy = missing_features_policy,
        chunking = raw_chunked$params$chunking,
        chunk_sizes = raw_chunked$params$chunk_sizes
      )
    ))
  }

  x <- wb_slice(
    bundle = bundle,
    matrix_id = matrix_id,
    features = all_features,
    cells = cells
  )
  x <- methods::as(x, "dgCMatrix")

  feats_use <- lapply(sig_meta, `[[`, "features_matched")
  bp_param <- if (identical(parallel_backend, "serial")) BiocParallel::SerialParam() else NULL
  score_df <- UCell::ScoreSignatures_UCell(
    x,
    features = feats_use,
    maxRank = as.integer(max_rank),
    ncores = as.integer(ncores),
    BPPARAM = bp_param,
    name = ""
  )

  if (is.matrix(score_df)) score_df <- as.data.frame(score_df, stringsAsFactors = FALSE)
  .wb_assert(is.data.frame(score_df), "UCell scoring must return a data.frame-like object.")

  score_cols <- intersect(signature_names, colnames(score_df))
  .wb_assert(length(score_cols) == length(signature_names),
             "UCell scoring did not return one column per requested signature.")

  score_df <- score_df[, signature_names, drop = FALSE]
  if (is.null(rownames(score_df)) || !length(rownames(score_df))) {
    rownames(score_df) <- cells
  }

  score_key <- character(0)
  score_cell <- character(0)
  score_value <- numeric(0)

  for (i in seq_along(signature_names)) {
    sig_name <- signature_names[i]
    vals <- suppressWarnings(as.numeric(score_df[[sig_name]]))
    .wb_assert(length(vals) == length(cells),
               paste0("UCell score length mismatch for signature '", sig_name, "'."))

    score_key <- c(score_key, rep(sig_name, length(cells)))
    score_cell <- c(score_cell, cells)
    score_value <- c(score_value, vals)
  }

  score_prim <- wb_prim_cell_vector_family(
    key = score_key,
    cell_id = score_cell,
    value = score_value,
    value_type = "continuous"
  )

  list(
    outputs = list(
      signature_scores = score_prim,
      signature_summary = .wb_ucell_summary_prim(
        sig_meta = sig_meta,
        score_prim = score_prim,
        matrix_id = matrix_id,
        missing_features_policy = missing_features_policy
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_signatures = length(signature_names),
      signature_names = signature_names,
      n_cells = length(cells),
      max_rank = as.integer(max_rank),
      ncores = as.integer(ncores),
      parallel_backend = parallel_backend,
      missing_features_policy = missing_features_policy
    )
  )
}
