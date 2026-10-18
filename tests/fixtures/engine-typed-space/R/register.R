.space_row_sum <- function(readers, writers, params, context) {
  capability <- context$typed_space_reads$coordinates
  cells <- capability$cells
  chunks <- scworkbench::wb_partition_axis(cells, params$chunk_size)
  values <- unlist(lapply(chunks, function(ids) {
    block <- readers$coordinates(ids)
    stopifnot(identical(block$cell_id, ids))
    rowSums(block$values)
  }), use.names = FALSE)
  writers$write_terminal_primitive("sums", scworkbench::wb_prim_cell_vector(
    stats::setNames(values, cells), value_type = "continuous"))
  invisible(list(status = "ok"))
}

register_operation_pack <- function() scworkbench::wb_operation_pack_register(
  system.file("scworkbench", "operation-pack.json", package = "scwbEngineSpaceFixture"),
  list(`enginespacefixture::row_sum` = .space_row_sum))
