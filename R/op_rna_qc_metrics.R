# Per-cell RNA quality-control facts. Cell inclusion remains a separate,
# explicit selection operation.

.wb_rna_qc_feature_group <- function(all_features,
                                     explicit = NULL,
                                     pattern = NULL,
                                     ignore_case = FALSE,
                                     missing_policy = c("error", "drop"),
                                     label) {
  missing_policy <- match.arg(missing_policy)
  all_features <- as.character(all_features)
  explicit <- unique(as.character(explicit %||% character(0)))
  explicit <- explicit[!is.na(explicit) & nzchar(explicit)]
  pattern <- as.character(pattern %||% "")[1]
  if (is.na(pattern)) pattern <- ""

  missing <- setdiff(explicit, all_features)
  if (length(missing) && identical(missing_policy, "error")) {
    stop(
      label, " feature ids are absent from the matrix: ",
      paste(utils::head(missing, 20L), collapse = ", "),
      if (length(missing) > 20L) " ..." else "",
      call. = FALSE
    )
  }
  explicit_matched <- intersect(explicit, all_features)

  pattern_matched <- character(0)
  if (nzchar(pattern)) {
    matched <- tryCatch(
      grepl(pattern, all_features, ignore.case = isTRUE(ignore_case), perl = TRUE),
      error = function(e) stop(label, " pattern is invalid: ", conditionMessage(e), call. = FALSE)
    )
    pattern_matched <- all_features[matched]
    .wb_assert(length(pattern_matched) > 0L,
               paste0(label, " pattern matched no matrix features: ", pattern))
  }

  selected <- all_features[all_features %in% union(explicit_matched, pattern_matched)]
  source <- vapply(selected, function(feature_id) {
    in_explicit <- feature_id %in% explicit_matched
    in_pattern <- feature_id %in% pattern_matched
    if (in_explicit && in_pattern) "explicit+pattern" else if (in_explicit) "explicit" else "pattern"
  }, character(1))

  list(
    features = selected,
    source = source,
    missing = missing,
    pattern = pattern,
    n_explicit_supplied = length(explicit),
    n_explicit_matched = length(explicit_matched),
    n_pattern_matched = length(pattern_matched)
  )
}

.wb_rna_qc_metric_summary <- function(matrix_id, metrics, cells, zero_count_cells = 0L) {
  keys <- unique(as.character(metrics$key))
  rows <- lapply(keys, function(key) {
    value <- as.numeric(metrics$value[metrics$key == key])
    finite <- value[is.finite(value)]
    data.frame(
      matrix_id = matrix_id,
      metric = key,
      n_cells = as.integer(length(cells)),
      n_missing = as.integer(sum(!is.finite(value))),
      n_zero_denominator = if (grepl("_percent$", key)) as.integer(zero_count_cells) else 0L,
      minimum = if (length(finite)) min(finite) else NA_real_,
      median = if (length(finite)) stats::median(finite) else NA_real_,
      mean = if (length(finite)) mean(finite) else NA_real_,
      maximum = if (length(finite)) max(finite) else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Calculate Per-Cell RNA QC Metrics
#'
#' Calculates count depth, detected-feature count, and optional mitochondrial
#' and ribosomal count/percentage metrics from a declared count matrix. Feature
#' groups are supplied explicitly and/or selected by recorded regular
#' expressions. This operation calculates facts only; it does not choose QC
#' thresholds or filter cells.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Registered raw-count matrix identifier.
#' @param cells Canonical cell ids for which metrics are calculated.
#' @param mitochondrial_features Optional explicit mitochondrial feature ids.
#' @param mitochondrial_pattern Optional regular expression matched against
#'   matrix feature ids.
#' @param ribosomal_features Optional explicit ribosomal feature ids.
#' @param ribosomal_pattern Optional regular expression matched against matrix
#'   feature ids.
#' @param pattern_ignore_case Whether regular-expression matching ignores case.
#' @param missing_feature_policy Whether absent explicit feature ids cause an
#'   error or are recorded and dropped.
#' @param require_integer_counts Require matrix values to be integer-like.
#' @param integer_tolerance Absolute tolerance for integer-like validation.
#' @param chunk_size Number of cells read per backed-matrix chunk.
#'
#' @return Standard operation result with per-cell `metrics`, exact
#'   `qc_features`, and an audit `summary`.
#'
#' @export
wb_op_rna_qc_metrics <- function(bundle,
                                 matrix_id,
                                 cells,
                                 mitochondrial_features = NULL,
                                 mitochondrial_pattern = NULL,
                                 ribosomal_features = NULL,
                                 ribosomal_pattern = NULL,
                                 pattern_ignore_case = FALSE,
                                 missing_feature_policy = c("error", "drop"),
                                 require_integer_counts = TRUE,
                                 integer_tolerance = 1e-8,
                                 chunk_size = 2000L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(!missing(cells) && is.character(cells) && length(cells) > 0L,
             "rna_qc_metrics: cells must be a non-empty character vector")
  .wb_assert(!anyNA(cells) && !anyDuplicated(cells),
             "rna_qc_metrics: cells must be unique and non-missing")
  missing_feature_policy <- match.arg(missing_feature_policy)
  chunk_size <- suppressWarnings(as.integer(chunk_size)[1])
  .wb_assert(is.finite(chunk_size) && chunk_size > 0L, "chunk_size must be positive")
  integer_tolerance <- suppressWarnings(as.numeric(integer_tolerance)[1])
  .wb_assert(is.finite(integer_tolerance) && integer_tolerance >= 0,
             "integer_tolerance must be finite and non-negative")

  matrix_row <- wb_matrix_info(bundle, matrix_id = matrix_id)
  .wb_assert(nrow(matrix_row) == 1L, paste0("matrix not found: ", matrix_id))
  all_cells <- wb_cells(bundle, cell_set = "all")
  .wb_assert(!anyNA(match(cells, all_cells)), "rna_qc_metrics: cells are absent from the bundle")
  # The public operator can also be called directly. Resolve its requested
  # subset back onto the bundle's canonical cell order so direct calls and
  # catalog-mediated session calls have one order contract.
  requested_cells <- cells
  cells <- all_cells[all_cells %in% requested_cells]
  .wb_assert(length(cells) == length(requested_cells),
             "rna_qc_metrics: canonical cell-order resolution was incomplete")
  all_features <- wb_feature_ids(bundle, matrix_id = matrix_id)
  .wb_assert(length(all_features) > 0L, "rna_qc_metrics: matrix has no registered features")

  mito <- .wb_rna_qc_feature_group(
    all_features, mitochondrial_features, mitochondrial_pattern,
    pattern_ignore_case, missing_feature_policy, "mitochondrial"
  )
  ribo <- .wb_rna_qc_feature_group(
    all_features, ribosomal_features, ribosomal_pattern,
    pattern_ignore_case, missing_feature_policy, "ribosomal"
  )

  chunks <- split(cells, ceiling(seq_along(cells) / chunk_size))
  values <- vector("list", length(chunks))
  for (i in seq_along(chunks)) {
    chunk_cells <- chunks[[i]]
    x <- .wb_matrix_block(bundle, matrix_id, all_features, chunk_cells)
    if (!inherits(x, "Matrix") && !is.matrix(x)) x <- as.matrix(x)
    stored <- if (inherits(x, "sparseMatrix")) x@x else as.numeric(x)
    .wb_assert(all(is.finite(stored)), "rna_qc_metrics: matrix contains non-finite values")
    .wb_assert(all(stored >= 0), "rna_qc_metrics: matrix contains negative values")
    if (isTRUE(require_integer_counts)) {
      .wb_assert(
        all(abs(stored - round(stored)) <= integer_tolerance),
        "rna_qc_metrics: matrix contains non-integer values; use a raw count matrix or explicitly set require_integer_counts=FALSE"
      )
    }

    total <- as.numeric(Matrix::colSums(x))
    detected <- as.numeric(Matrix::colSums(x > 0))
    chunk_out <- list(total_counts = total, detected_features = detected)
    if (length(mito$features)) {
      mito_counts <- as.numeric(Matrix::colSums(x[mito$features, , drop = FALSE]))
      chunk_out$mitochondrial_counts <- mito_counts
      chunk_out$mitochondrial_percent <- ifelse(total > 0, 100 * mito_counts / total, 0)
    }
    if (length(ribo$features)) {
      ribo_counts <- as.numeric(Matrix::colSums(x[ribo$features, , drop = FALSE]))
      chunk_out$ribosomal_counts <- ribo_counts
      chunk_out$ribosomal_percent <- ifelse(total > 0, 100 * ribo_counts / total, 0)
    }
    values[[i]] <- chunk_out
  }

  metric_keys <- names(values[[1]])
  metric_values <- lapply(metric_keys, function(key) unlist(lapply(values, `[[`, key), use.names = FALSE))
  names(metric_values) <- metric_keys
  metrics <- wb_prim_cell_vector_family(
    key = rep(metric_keys, each = length(cells)),
    cell_id = rep(cells, times = length(metric_keys)),
    value = unlist(metric_values, use.names = FALSE),
    value_type = "continuous",
    meta = list(
      matrix_id = matrix_id,
      metric_keys = metric_keys,
      percentage_unit = "percent",
      zero_count_percentage_convention = "zero",
      threshold_selection = "not_performed"
    )
  )

  feature_rows <- list()
  if (length(mito$features)) {
    feature_rows[[length(feature_rows) + 1L]] <- data.frame(
      feature_id = mito$features, metric_group = "mitochondrial",
      selection_source = unname(mito$source), matrix_id = matrix_id,
      stringsAsFactors = FALSE
    )
  }
  if (length(ribo$features)) {
    feature_rows[[length(feature_rows) + 1L]] <- data.frame(
      feature_id = ribo$features, metric_group = "ribosomal",
      selection_source = unname(ribo$source), matrix_id = matrix_id,
      stringsAsFactors = FALSE
    )
  }
  qc_features <- if (length(feature_rows)) do.call(rbind, feature_rows) else data.frame(
    feature_id = character(), metric_group = character(),
    selection_source = character(), matrix_id = character(),
    stringsAsFactors = FALSE
  )

  feature_meta <- list(
    matrix_id = matrix_id,
    mitochondrial_pattern = mito$pattern,
    mitochondrial_missing_features = mito$missing,
    ribosomal_pattern = ribo$pattern,
    ribosomal_missing_features = ribo$missing,
    missing_feature_policy = missing_feature_policy
  )
  n_zero_count_cells <- sum(metric_values$total_counts == 0)
  summary <- .wb_rna_qc_metric_summary(
    matrix_id, metrics, cells, zero_count_cells = n_zero_count_cells
  )

  list(
    outputs = list(
      metrics = metrics,
      qc_features = wb_prim_feature_table(
        qc_features,
        table_type = "rna_qc_feature_membership",
        meta = feature_meta
      ),
      summary = wb_prim_obs_table(
        summary,
        table_type = "rna_qc_metrics_summary",
        entity_kind = "qc_metric",
        meta = c(feature_meta, list(
          n_cells = length(cells),
          n_zero_count_cells = n_zero_count_cells,
          zero_count_percentage_convention = "zero",
          threshold_selection = "not_performed"
        ))
      )
    ),
    params = list(
      matrix_id = matrix_id,
      mitochondrial_features = unique(as.character(mitochondrial_features %||% character(0))),
      mitochondrial_pattern = mito$pattern,
      ribosomal_features = unique(as.character(ribosomal_features %||% character(0))),
      ribosomal_pattern = ribo$pattern,
      pattern_ignore_case = isTRUE(pattern_ignore_case),
      missing_feature_policy = missing_feature_policy,
      require_integer_counts = isTRUE(require_integer_counts),
      integer_tolerance = integer_tolerance,
      chunk_size = chunk_size,
      n_chunks = length(chunks),
      n_cells = length(cells),
      n_mitochondrial_features = length(mito$features),
      n_ribosomal_features = length(ribo$features),
      threshold_selection = "not_performed"
    )
  )
}
