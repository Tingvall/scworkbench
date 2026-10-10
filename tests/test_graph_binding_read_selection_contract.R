test_graph_content_only_and_selected_view_contract <- function() {
  root <- tempfile("graph_views_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("cell_2", "cell_10"); wb_define_cells(b, cells)
  bindings <- artifacts <- list()
  for (view in c("available", "unavailable")) {
    primitive <- wb_prim_cell_vector(stats::setNames(c("A", "B"), cells))
    run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(),
      outputs = list(vector = primitive))
    promoted <- wb_promote_analysis(b, stats::setNames(list(run), run$run_id), run$run_id, outputs = "vector")
    id <- as.character(promoted$promoted$artifact_id[[1L]]); artifacts[[view]] <- id
    snapshot <- DBI::dbGetQuery(b$con, paste0("SELECT h.* FROM prov_heads h JOIN artifacts a ",
      "ON a.provenance_snapshot_id=h.snapshot_id WHERE a.artifact_id=?;"), params = list(id))
    snapshot_identity <- scworkbench:::.wb_operation_pack_v3_head_snapshot(snapshot)$source_snapshot_identity
    snapshot_identity$scope <- NULL
    source <- list(kind = "retained_cell_axis", source_id = id)
    axis <- scworkbench:::.wb_graph_source_axis_hash(b, source, "cell", scworkbench:::.wb_graph_budgets())
    bindings[[view]] <- list(binding_id = view, axis_kind = "cell", source_ref = source,
      source_snapshot_identity = snapshot_identity, axis_content_identity = axis$axis_content_identity,
      axis_order_identity = axis$axis_order_identity,
      mapping = lapply(cells, function(cell) list(node_id = cell, axis_id = cell)))
  }
  graph <- wb_prim_graph(lapply(cells, function(cell) list(node_id = cell)), list(), list(),
    associations = unname(bindings), direction_mode = "undirected")
  run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(), outputs = list(vector = graph))
  promoted <- wb_promote_analysis(b, stats::setNames(list(run), run$run_id), run$run_id, outputs = "vector")
  graph_id <- as.character(promoted$promoted$artifact_id[[1L]])
  original <- wb_art_graph_info(b, graph_id)
  DBI::dbExecute(b$con, "UPDATE artifact_labels SET label='changed' WHERE artifact_id=? AND payload_ordinal=0;",
    params = list(artifacts$unavailable))
  value <- wb_art_load(b, graph_id)
  declaration <- list(binding_policy = "optional")
  content_only <- scworkbench:::.wb_operation_pack_v4_graph_input(b, "source", value, declaration)
  selected <- scworkbench:::.wb_operation_pack_v4_graph_input(b, "source", value, declaration, list("available"))
  stopifnot(content_only$descriptor$component_counts$bindings == "2",
    identical(content_only$descriptor$binding_identity, original$binding_identity),
    identical(selected$descriptor$retained_descriptor_identity, original$descriptor_identity))
  for (record in list(content_only, selected)) {
    grant <- attr(record, "graph_read_grant")
    scworkbench:::.wb_operation_pack_v4_sources_assert_current(b, list(graph_read_grants = list(grant)))
    cursor <- scworkbench:::.wb_operation_pack_v4_graph_cursor(b, grant)
    repeat {part <- cursor$peek(); cursor$accept(part); if (is.null(part)) break}
    stopifnot(isTRUE(cursor$usage()$complete))
  }
  stopifnot(inherits(tryCatch(scworkbench:::.wb_operation_pack_v4_graph_input(b, "source", value,
    declaration, list("unavailable")), error = identity), "wb_graph_error"),
    inherits(tryCatch(scworkbench:::.wb_operation_pack_v4_graph_input(b, "source", value,
      declaration, list("missing")), error = identity), "wb_graph_error"))
  # An unavailable binding remains retained, but cannot be republished by
  # copying a content-only input or silently omitting its source validation.
  stopifnot(wb_art_graph_info(b, graph_id)$source_authority$status == "unverified")
  staged <- scworkbench:::.wb_graph_stage_small(graph)
  on.exit(scworkbench:::.wb_graph_stage_discard(staged), add = TRUE)
  stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_sources_assert(b, staged$con,
    "staged", staged$budgets), error = identity), "wb_graph_error"))
  TRUE
}
