#' Materialize imported cell metadata as a typed cell vector
#'
#' @param bundle Bundle containing the imported cell metadata.
#' @param source_column Name of one cell metadata column.
#' @param cells Optional cell IDs defining the output universe.
#' @param value_type One of `"categorical"`, `"continuous"`, or `"auto"`.
#' @param missing_policy One of `"error"`, `"drop"`, or `"as_category"`.
#' @param missing_label Label used by `missing_policy = "as_category"`.
#' @param vector_name Stable human-readable identifier recorded in provenance.
#' @param overwrite Whether an existing promoted vector with the same name may
#'   be superseded by a new immutable artifact.
#' @export
wb_op_metadata_cell_vector <- function(bundle,
                                       source_column,
                                       cells = NULL,
                                       value_type = "auto",
                                       missing_policy = "error",
                                       missing_label = "__MISSING__",
                                       vector_name = source_column,
                                       overwrite = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  source_column <- as.character(source_column)[1]
  vector_name <- as.character(vector_name)[1]
  value_type_requested <- as.character(value_type)[1]
  missing_policy <- as.character(missing_policy)[1]
  .wb_assert(nzchar(source_column), "source_column must be a non-empty metadata column name.")
  .wb_assert(nzchar(vector_name), "vector_name must be a non-empty string.")
  .wb_assert(value_type_requested %in% c("categorical", "continuous", "auto"),
             "value_type must be categorical, continuous, or auto.")
  .wb_assert(missing_policy %in% c("error", "drop", "as_category"),
             "missing_policy must be error, drop, or as_category.")
  .wb_assert(is.character(missing_label) && length(missing_label) == 1L && nzchar(missing_label),
             "missing_label must be a non-empty string.")

  all_cells <- as.character(wb_cells(bundle, cell_set = "all"))
  target <- if (is.null(cells)) all_cells else as.character(cells)
  .wb_assert(length(target) > 0L && !anyDuplicated(target), "cells must be a non-empty unique cell vector.")
  .wb_assert(all(target %in% all_cells), "Some requested cells are absent from the bundle.")
  md <- wb_meta(bundle, cells = target, cols = c("cell_id", source_column))
  raw <- md[[source_column]]
  detected_type <- if (is.numeric(raw) || is.integer(raw)) "continuous" else "categorical"
  resolved_type <- if (identical(value_type_requested, "auto")) detected_type else value_type_requested

  if (identical(resolved_type, "continuous")) {
    value <- suppressWarnings(as.numeric(raw))
    missing <- !is.finite(value)
  } else {
    value <- as.character(raw)
    missing <- is.na(value) | !nzchar(value)
  }
  n_missing <- sum(missing)
  if (n_missing) {
    if (identical(missing_policy, "error")) {
      stop("Metadata column '", source_column, "' contains ", n_missing,
           " missing/non-finite values; choose missing_policy='drop' or an applicable replacement policy.", call. = FALSE)
    }
    if (identical(missing_policy, "as_category")) {
      .wb_assert(identical(resolved_type, "categorical"),
                 "missing_policy='as_category' requires categorical value_type.")
      value[missing] <- missing_label
    }
    if (identical(missing_policy, "drop")) {
      target <- target[!missing]
      value <- value[!missing]
    }
  }
  .wb_assert(length(target) > 0L, "No cells remain after missing-value handling.")

  names(value) <- target
  list(
    outputs = list(vector = wb_prim_cell_vector(value, value_type = resolved_type)),
    params = list(
      source_column = source_column,
      source_metadata_scope = "cells",
      source_dataset_id = NULL,
      vector_name = vector_name,
      overwrite = isTRUE(overwrite),
      value_type_requested = value_type_requested,
      value_type = resolved_type,
      auto_detected = identical(value_type_requested, "auto"),
      auto_detection_rule = if (identical(value_type_requested, "auto")) "native_numeric_is_continuous_else_categorical" else NULL,
      missing_policy = missing_policy,
      missing_label = if (identical(missing_policy, "as_category")) missing_label else NULL,
      n_cells_requested = nrow(md),
      n_cells_output = length(target),
      n_missing = as.integer(n_missing)
    )
  )
}
