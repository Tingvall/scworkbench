.wb_chunk_partition <- function(x, chunk_size) {
  x <- as.character(x)
  .wb_assert(length(x) > 0L, "chunk partition requires at least one element")
  chunk_size <- suppressWarnings(as.integer(chunk_size)[1])
  .wb_assert(is.finite(chunk_size) && chunk_size > 0L, "chunk_size must be a positive integer")

  starts <- seq.int(1L, length(x), by = chunk_size)
  out <- lapply(starts, function(i) x[i:min(i + chunk_size - 1L, length(x))])
  names(out) <- paste0("chunk_", seq_along(out))
  out
}

.wb_chunk_reorder_by_levels <- function(df, columns, levels_map) {
  .wb_assert(is.data.frame(df), "df must be a data.frame")
  if (!nrow(df) || !length(columns) || is.null(levels_map) || !length(levels_map)) return(df)

  ord_cols <- vector("list", length(columns))
  names(ord_cols) <- columns

  for (nm in columns) {
    vals <- df[[nm]]
    lv <- levels_map[[nm]] %||% NULL
    if (is.null(lv)) {
      ord_cols[[nm]] <- vals
    } else {
      ord <- match(as.character(vals), as.character(lv))
      ord[is.na(ord)] <- length(lv) + seq_len(sum(is.na(ord)))
      ord_cols[[nm]] <- ord
    }
  }

  oo <- do.call(order, c(ord_cols, list(na.last = TRUE)))
  df[oo, , drop = FALSE]
}

.wb_merge_chunked_cell_vector <- function(chunks, cell_order = NULL) {
  .wb_assert(length(chunks) > 0L, "cell_vector merge requires at least one chunk")
  value_type <- unique(vapply(chunks, function(x) as.character(x$value_type %||% "")[1], character(1)))
  .wb_assert(length(value_type) == 1L, "cell_vector chunks must share one value_type")

  cell_id <- unlist(lapply(chunks, `[[`, "cell_id"), use.names = FALSE)
  value <- unlist(lapply(chunks, `[[`, "value"), use.names = FALSE)
  .wb_assert(!anyDuplicated(cell_id), "cell_vector chunk merge found duplicate cell_id values")

  x <- stats::setNames(value, cell_id)
  if (!is.null(cell_order)) {
    keep <- intersect(as.character(cell_order), names(x))
    x <- x[keep]
  }

  nm <- names(x)
  if (identical(value_type, "continuous")) x <- suppressWarnings(as.numeric(x))
  x <- stats::setNames(x, nm)
  wb_prim_cell_vector(x, value_type = value_type)
}

.wb_merge_chunked_cell_vector_family <- function(chunks, cell_order = NULL, key_order = NULL) {
  .wb_assert(length(chunks) > 0L, "cell_vector_family merge requires at least one chunk")
  value_type <- unique(vapply(chunks, function(x) as.character(x$value_type %||% "")[1], character(1)))
  .wb_assert(length(value_type) == 1L, "cell_vector_family chunks must share one value_type")

  df <- do.call(
    rbind,
    lapply(chunks, function(x) {
      data.frame(
        key = as.character(x$key),
        cell_id = as.character(x$cell_id),
        value = as.numeric(x$value),
        stringsAsFactors = FALSE
      )
    })
  )
  .wb_assert(!anyDuplicated(df[, c("key", "cell_id"), drop = FALSE]),
             "cell_vector_family chunk merge found duplicate (key, cell_id) pairs")

  df <- .wb_chunk_reorder_by_levels(
    df,
    columns = c("key", "cell_id"),
    levels_map = list(key = key_order, cell_id = cell_order)
  )

  wb_prim_cell_vector_family(
    key = df$key,
    cell_id = df$cell_id,
    value = df$value,
    value_type = value_type
  )
}

.wb_merge_chunked_feature_table <- function(chunks, feature_order = NULL) {
  .wb_assert(length(chunks) > 0L, "feature_table merge requires at least one chunk")
  table_type <- unique(vapply(chunks, function(x) as.character(x$table_type %||% "")[1], character(1)))
  .wb_assert(length(table_type) == 1L, "feature_table chunks must share one table_type")

  tbl <- do.call(rbind, lapply(chunks, function(x) x$table))
  rownames(tbl) <- NULL
  if ("feature_id" %in% colnames(tbl)) {
    .wb_assert(!anyDuplicated(as.character(tbl$feature_id)),
               "feature_table chunk merge found duplicate feature_id values")
    tbl <- .wb_chunk_reorder_by_levels(
      tbl,
      columns = "feature_id",
      levels_map = list(feature_id = feature_order)
    )
    rownames(tbl) <- NULL
  }

  wb_prim_feature_table(
    table = tbl,
    table_type = table_type,
    meta = chunks[[1]]$meta %||% list()
  )
}

.wb_merge_chunked_obs_table <- function(chunks) {
  .wb_assert(length(chunks) > 0L, "obs_table merge requires at least one chunk")
  table_type <- unique(vapply(chunks, function(x) as.character(x$table_type %||% "")[1], character(1)))
  entity_kind <- unique(vapply(chunks, function(x) as.character(x$entity_kind %||% "")[1], character(1)))
  .wb_assert(length(table_type) == 1L, "obs_table chunks must share one table_type")
  .wb_assert(length(entity_kind) == 1L, "obs_table chunks must share one entity_kind")

  tbl <- do.call(rbind, lapply(chunks, function(x) x$table))
  rownames(tbl) <- NULL

  wb_prim_obs_table(
    table = tbl,
    table_type = table_type,
    entity_kind = entity_kind,
    meta = chunks[[1]]$meta %||% list()
  )
}

.wb_merge_chunked_output <- function(chunks, strategy, context = list()) {
  .wb_assert(length(chunks) > 0L, "chunk merge requires at least one primitive chunk")
  .wb_assert(is.character(strategy) && length(strategy) == 1L && nzchar(strategy),
             "chunk merge strategy must be a non-empty string")

  switch(
    strategy,
    row_bind_cell_vector = .wb_merge_chunked_cell_vector(
      chunks,
      cell_order = context$cell_order %||% NULL
    ),
    row_bind_cell_vector_family = .wb_merge_chunked_cell_vector_family(
      chunks,
      cell_order = context$cell_order %||% NULL,
      key_order = context$key_order %||% NULL
    ),
    row_bind_feature_table = .wb_merge_chunked_feature_table(
      chunks,
      feature_order = context$feature_order %||% NULL
    ),
    row_bind_obs_table = .wb_merge_chunked_obs_table(chunks),
    stop("Unsupported chunk merge strategy: ", strategy, call. = FALSE)
  )
}

.wb_merge_chunked_outputs <- function(chunk_results, merge_spec, context = list()) {
  .wb_assert(is.list(chunk_results) && length(chunk_results) > 0L,
             "chunk_results must be a non-empty list")
  .wb_assert(is.list(merge_spec) && length(merge_spec) > 0L,
             "merge_spec must be a non-empty named list")
  .wb_assert(!is.null(names(merge_spec)) && all(nzchar(names(merge_spec))),
             "merge_spec must be a named list")

  out_names <- names(merge_spec)
  chunk_outputs <- lapply(chunk_results, function(x) {
    .wb_assert(is.list(x) && is.list(x$outputs), "each chunk result must have an outputs list")
    x$outputs
  })

  merged <- setNames(vector("list", length(out_names)), out_names)
  for (nm in out_names) {
    chunks <- lapply(chunk_outputs, function(x) x[[nm]])
    .wb_assert(all(vapply(chunks, .wb_is_primitive, logical(1))),
               paste0("chunk output '", nm, "' must be present and primitive in every chunk"))
    merged[[nm]] <- .wb_merge_chunked_output(
      chunks = chunks,
      strategy = as.character(merge_spec[[nm]])[1],
      context = context[[nm]] %||% context
    )
  }

  merged
}

.wb_run_op_in_chunks <- function(bundle,
                                 resolved,
                                 effective_cells,
                                 inputs = list(),
                                 runner,
                                 chunk_axis,
                                 chunk_size,
                                 merge_spec,
                                 context = list()) {
  .wb_assert(is.function(runner), "runner must be a function")
  axis <- as.character(chunk_axis)[1]
  .wb_assert(axis %in% c("cells", "features"), "chunk_axis must be 'cells' or 'features'")

  chunks <- switch(
    axis,
    cells = .wb_chunk_partition(as.character(effective_cells), chunk_size = chunk_size),
    features = .wb_chunk_partition(as.character(inputs$features %||% character(0)), chunk_size = chunk_size)
  )
  .wb_assert(length(chunks) > 0L, "chunk plan must contain at least one chunk")

  chunk_results <- lapply(chunks, function(chunk_vals) {
    chunk_inputs <- inputs
    chunk_cells <- effective_cells
    if (identical(axis, "cells")) {
      chunk_cells <- as.character(chunk_vals)
    } else {
      chunk_inputs$features <- as.character(chunk_vals)
    }

    runner(
      bundle = bundle,
      resolved = resolved,
      effective_cells = chunk_cells,
      inputs = chunk_inputs
    )
  })

  merged_outputs <- .wb_merge_chunked_outputs(
    chunk_results = chunk_results,
    merge_spec = merge_spec,
    context = context
  )

  list(
    outputs = merged_outputs,
    params = list(
      chunking = list(
        enabled = TRUE,
        axis = axis,
        chunk_size = as.integer(chunk_size),
        n_chunks = length(chunks)
      ),
      chunk_sizes = as.integer(vapply(chunks, length, integer(1)))
    ),
    chunks = chunks,
    chunk_results = chunk_results
  )
}
