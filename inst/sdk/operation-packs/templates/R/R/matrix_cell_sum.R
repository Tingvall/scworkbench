.matrix_cell_sum <- function(readers, writers, params, context) {
  grant <- context$typed_slice_reads$matrix_chunks
  pieces <- scworkbench::wb_operation_pack_map_partitions(
    readers$matrix_chunks, grant, function(block, index) {
      if (any(!is.finite(block$values)))
        stop("matrix_cell_sum requires finite values; NA/NaN/Inf are rejected.")
      sums <- colSums(block$values)
      if (any(!is.finite(sums)) || !is.finite(sum(sums)))
        stop("matrix_cell_sum numeric overflow is not permitted.")
      list(cells = block$cell_id, sums = sums,
        summary = data.frame(chunk_index = as.integer(index),
          cell_count = as.integer(length(block$cell_id)),
          feature_count = as.integer(length(block$feature_id)),
          first_cell = block$cell_id[[1L]],
          last_cell = tail(block$cell_id, 1L), sum_total = sum(sums),
          stringsAsFactors = FALSE))
    })
  cells <- unlist(lapply(pieces, `[[`, "cells"), use.names = FALSE)
  sums <- unlist(lapply(pieces, `[[`, "sums"), use.names = FALSE)
  writers$write_terminal_primitive("sums",
    scworkbench::wb_prim_cell_vector(stats::setNames(sums, cells),
      value_type = "continuous", meta = list(finite_policy = "error")))
  writers$write_terminal_primitive("summary",
    scworkbench::wb_prim_obs_table(do.call(rbind,
      lapply(pieces, `[[`, "summary")),
      table_type = "sdk_matrix_cell_sum_summary"))
  invisible(list(status = "ok"))
}
