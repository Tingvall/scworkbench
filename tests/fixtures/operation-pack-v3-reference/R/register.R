.fixture_groups <- function(params) {
  groups <- params$features
  if (is.character(groups)) groups <- list(module1 = groups)
  if (is.null(names(groups)) || any(!nzchar(names(groups))))
    names(groups) <- paste0(params$name, seq_along(groups))
  groups
}

.fixture_scores <- function(groups, cells, all_cells = cells) {
  keys <- names(groups)
  values <- unlist(lapply(seq_along(keys), function(i)
    (i - 1L) * length(all_cells) + match(cells, all_cells)),
    use.names = FALSE)
  scworkbench::wb_prim_cell_vector_family(
    rep(keys, each = length(cells)), rep(cells, length(keys)),
    as.numeric(values),
    meta = list(fixture = "abi_v3"))
}

.bounded_family <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  writers$write_terminal_primitive("scores", .fixture_scores(
    .fixture_groups(params), matrix$cell_id))
  invisible(list(status = "ok"))
}

.chunked_family <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  cells <- as.character(matrix$cell_id)
  chunk_size <- as.integer(params$chunk_size)
  groups <- .fixture_groups(params)
  starts <- seq.int(1L, length(cells), by = chunk_size)
  for (i in seq_along(starts)) {
    selected <- cells[starts[[i]]:min(length(cells),
      starts[[i]] + chunk_size - 1L)]
    readers$matrix(cells = selected)
    writers$write_chunk("scores", i, .fixture_scores(groups, selected,
      all_cells = cells))
  }
  invisible(list(status = "ok"))
}

.reduce_family <- function(readers, writers, params, context) {
  signal <- readers$signal()
  cells <- unique(as.character(signal$cell_id))
  values <- vapply(cells, function(cell) mean(as.numeric(signal$value[
    as.character(signal$cell_id) == cell]), na.rm = TRUE), numeric(1))
  writers$write_terminal_primitive("reduced",
    scworkbench::wb_prim_cell_vector(stats::setNames(values, cells),
      value_type = "continuous", meta = list(fixture = "abi_v3")))
  invisible(list(status = "ok"))
}

.summarize_scores <- function(merged_family, metadata) {
  keys <- unique(as.character(merged_family$key))
  rows <- data.frame(key = keys,
    mean = vapply(keys, function(key) mean(merged_family$value[
      merged_family$key == key]), numeric(1)), stringsAsFactors = FALSE)
  scworkbench::wb_prim_obs_table(rows, table_type = "abi_v3_chunk_summary",
    meta = list(fixture = "abi_v3"))
}

.ancestry_family <- function(readers, writers, params, context) {
  signal <- readers$signal()
  ancestry <- readers$source_ancestry()
  stopifnot(identical(ancestry$artifact_id, params$artifact_id))
  keys <- unique(as.character(signal$key))
  cells <- unique(as.character(signal$cell_id))
  pairs <- unlist(lapply(keys, function(key) lapply(cells, function(cell)
    which(as.character(signal$key) == key &
      as.character(signal$cell_id) == cell)[[1]])), use.names = FALSE)
  writers$write_terminal_primitive("smoothed",
    scworkbench::wb_prim_cell_vector_family(signal$key[pairs],
      signal$cell_id[pairs], as.numeric(signal$value[pairs]), meta = list(
        source_snapshot_id = ancestry$source_snapshot_id)))
  invisible(list(status = "ok"))
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json",
      package = "scwbV3Reference"),
    list(
      `scwbv3reference::bounded_family` = .bounded_family,
      `scwbv3reference::chunked_family` = .chunked_family,
      `scwbv3reference::reduce_family` = .reduce_family,
      `scwbv3reference::ancestry_family` = .ancestry_family
    ),
    finalizers = list(summarize_scores = .summarize_scores)
  )
}
