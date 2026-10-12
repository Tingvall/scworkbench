# Pack author code uses only public SDK callbacks and path-free source context.
.small_fixture <- function() jsonlite::read_json(system.file("small.json",
  package = "scwbGraphSmallFixture"), simplifyVector = FALSE)
.small_summary <- function(writers, nodes) writers$write_terminal_primitive("summary",
  scworkbench::wb_prim_obs_table(data.frame(nodes = as.character(nodes)), table_type = "graph_summary"))
.emit_small <- function(readers, writers, params, context) {
  invisible(readers$matrix())
  fixture <- .small_fixture(); content <- fixture$content
  writer <- writers$open_graph("result", content[c("schema", "direction_mode")])
  append <- function(component, rows) {
    if (length(rows)) for (start in seq.int(1L, length(rows), by = 2L))
      writer$write_part(component, rows[start:min(start + 1L, length(rows))])
  }
  for (component in c("nodes", "edges", "incidences")) append(component, content[[component]])
  fields <- values <- list()
  for (scope in names(content$attributes)) for (i in seq_along(content$attributes[[scope]])) {
    field <- content$attributes[[scope]][[i]]
    fields[[length(fields) + 1L]] <- c(list(scope = scope, field_ordinal = as.character(i - 1L)),
      field[c("name", "type", "nullable")])
    for (j in seq_along(field$values)) values[[length(values) + 1L]] <- list(scope = scope,
      field_ordinal = as.character(i - 1L), entity_ordinal = as.character(j - 1L), value = field$values[[j]])
  }
  append("attribute_fields", fields); append("attribute_values", values)
  bindings <- maps <- list()
  for (i in seq_along(fixture$source_plan$bindings)) {
    plan <- fixture$source_plan$bindings[[i]]
    axes <- Filter(function(axis) identical(axis$axis_kind, plan$axis_kind), context$graph_source_axes$result)
    stopifnot(length(axes) == 1L)
    binding <- scworkbench::wb_graph_binding_from_source(axes[[1L]], plan$binding_id, plan$mapping)
    binding$mapping <- NULL; binding$binding_ordinal <- as.character(i - 1L)
    bindings[[i]] <- binding
    for (j in seq_along(plan$mapping)) maps[[length(maps) + 1L]] <- c(list(binding_id = plan$binding_id,
      mapping_ordinal = as.character(j - 1L)), plan$mapping[[j]])
  }
  append("bindings", bindings); append("binding_mappings", maps)
  writer$finish(); .small_summary(writers, length(content$nodes))
  list(status = "ok")
}
.copy_small <- function(readers, writers, params, context) {
  reader <- readers$source()
  writer <- writers$open_graph("result", list(schema = "scworkbench.graph.content.v1",
    direction_mode = reader$header$direction_mode))
  rows <- bytes <- 0L
  repeat {
    part <- reader$next_part()
    if (is.null(part)) break
    stopifnot(as.numeric(part$row_count) <= 2L)
    encoded <- nchar(jsonlite::toJSON(part, auto_unbox = TRUE, null = "null", digits = NA), type = "bytes")
    stopifnot(encoded <= 4096L)
    rows <- max(rows, length(part$rows)); bytes <- max(bytes, encoded)
    if (part$component != "header") writer$write_part(part$component, part$rows)
  }
  writer$finish(); .small_summary(writers, reader$header$component_counts$nodes)
  message("SMALL_CURSOR max_rows=", rows, " max_partition_json_bytes=", bytes)
  list(status = "ok")
}
.collect_small <- function(readers, writers, params, context) {
  scworkbench::wb_graph_collect(readers$source(), materialization_bytes = 8192)
  stop("oversized collection unexpectedly accepted")
}
register_operation_pack <- function() scworkbench::wb_operation_pack_register(system.file("scworkbench",
  "operation-pack.json", package = "scwbGraphSmallFixture"), list(
    `graphsmallfixture::emit_small` = .emit_small,
    `graphsmallfixture::copy_small` = .copy_small,
    `graphsmallfixture::collect_small` = .collect_small))
