# The ABI4 graph callbacks extend the existing invocation adapter. Their
# closures own staging state; none of it is returned to an operation pack.
.wb_operation_pack_v4_graph_budgets <- function(resource) {
  .wb_graph_budgets(list(storage_bytes = resource$max_spill_bytes,
    token_bytes = resource$max_spill_bytes,
    published_bytes = resource$max_published_bytes, wal_bytes = resource$max_wal_bytes,
    memory_bytes = resource$max_memory_bytes,
    sqlite_cache_kib = max(1L, as.integer(min(8192, as.numeric(resource$max_memory_bytes) / 4096))),
    partition_bytes = as.numeric(resource$partition_limits$max_decoded_bytes),
    partition_rows = as.numeric(resource$partition_limits$max_rows),
    collect_bytes = as.numeric(resource$max_collect_bytes)))
}

.wb_operation_pack_v4_graph_cursor <- function(bundle, grant) {
  components <- c("header", .wb_graph_components())
  state <- new.env(parent = emptyenv())
  state$component <- 1L; state$offset <- "0"; state$complete <- FALSE
  state$observations <- .wb_graph_observations_new()
  state$counts <- grant$component_counts
  state$limits <- .wb_graph_budgets(list(
    partition_rows = as.numeric(grant$partition_limits$max_rows),
    partition_bytes = as.numeric(grant$partition_limits$max_decoded_bytes)))
  state$expected <- function() {
    while (state$component <= length(components) &&
      state$offset == state$counts[[components[[state$component]]]]) {
      state$component <- state$component + 1L; state$offset <- "0"
    }
    if (state$component > length(components)) "end" else components[[state$component]]
  }
  state$peek <- function() {
    .wb_graph_require(!state$complete, "GRAPH_READER_RETIRED", "Graph reader has been retired.")
    component <- state$expected()
    if (component == "end") return(NULL)
    if (component == "header") {
      mode <- DBI::dbGetQuery(bundle$con, paste0("SELECT direction_mode FROM artifact_graph_meta ",
        "WHERE artifact_id=? AND octet_length(direction_mode)<=10;"), params = list(grant$source_artifact_id))
      .wb_graph_require(nrow(mode) == 1L, "GRAPH_SOURCE_AUTHORITY_INVALID", "Graph source header changed.")
      return(.wb_graph_partition("header", "0", list(list(
        schema = "scworkbench.graph.content.v1", direction_mode = mode$direction_mode[[1L]]))))
    }
    rows <- .wb_graph_page(bundle$con, grant$source_artifact_id, component, state$offset,
      state$limits$partition_rows, state$limits$partition_bytes - 1024)
    .wb_graph_require(nrow(rows) > 0L, "GRAPH_READER_INCOMPLETE", "Missing admitted graph partition.")
    part <- .wb_graph_partition(component, state$offset, lapply(rows$record_json, .wb_graph_parse))
    .wb_graph_partition_validate(part, state$limits)
    part
  }
  state$accept <- function(part) {
    if (is.null(part)) {
      .wb_graph_require(state$expected() == "end" && !state$complete,
        "GRAPH_READER_INCOMPLETE", "Graph stream ended before its complete declared closure.")
      .wb_operation_pack_v4_sources_assert_current(bundle, list(graph_read_grants = list(grant)))
      state$complete <- TRUE
    } else {
      .wb_graph_require(!state$complete && identical(part$component, state$expected()) &&
        identical(part$first_ordinal, state$offset), "GRAPH_PART_ORDER_INVALID", "Graph read schedule differs.")
      state$observations <- .wb_graph_observe_part(state$observations, part)
      state$offset <- .wb_graph_add_count(state$offset, .wb_graph_i64(part$row_count))
      .wb_graph_require(.wb_graph_i64(state$offset) <= .wb_graph_i64(state$counts[[part$component]]),
        "GRAPH_READER_INCOMPLETE", "Graph stream exceeds admitted source counts.")
    }
    invisible(TRUE)
  }
  state$usage <- function() {
    .wb_graph_require(state$complete, "GRAPH_READER_INCOMPLETE", "Graph reader was not fully consumed.")
    list(input_name = grant$input_name, grant_identity = grant$grant_identity,
      content_identity = grant$content_identity, binding_identity = grant$binding_identity,
      descriptor_identity = grant$descriptor_identity, selected_binding_ids = grant$selected_binding_ids,
      component_observations = state$observations, complete = TRUE)
  }
  state
}

.wb_operation_pack_v4_graph_adapter <- function(base, request, bundle, stage_root) {
  state <- base$state; state$graph_cursors <- list(); state$graph_opened <- list()
  grants <- stats::setNames(request$graph_read_grants %||% list(),
    vapply(request$graph_read_grants %||% list(), `[[`, character(1), "input_name"))
  for (name in names(grants)) local({
    input_name <- name; grant <- grants[[name]]
    base$readers[[input_name]] <<- function(...) {
      .wb_graph_require(!state$used && !length(list(...)) && is.null(state$graph_cursors[[input_name]]),
        "GRAPH_READER_RETIRED", "Graph input reader is invocation-scoped and exactly once.")
      cursor <- .wb_operation_pack_v4_graph_cursor(bundle, grant)
      state$graph_cursors[[input_name]] <- cursor
      mode <- cursor$peek()$rows[[1L]]$direction_mode
      list(header = c(list(direction_mode = mode, component_counts = grant$component_counts),
        grant[c("content_identity", "binding_identity", "descriptor_identity")]),
        next_part = function() {
          .wb_graph_require(!state$used, "GRAPH_READER_RETIRED", "Invocation has ended.")
          part <- cursor$peek(); cursor$accept(part); part
        })
    }
  })
  write_grants <- stats::setNames(request$graph_write_grants %||% list(),
    vapply(request$graph_write_grants %||% list(), `[[`, character(1), "output_name"))
  open <- function(name, header) {
    .wb_graph_require(.wb_graph_string(name) && !state$used && !is.null(write_grants[[name]]) &&
      is.null(state$graph_opened[[name]]), "GRAPH_WRITER_RETIRED", "Graph output is not granted or was opened before.")
    .wb_graph_closed(header, c("schema", "direction_mode"), "writer header")
    .wb_graph_require(header$schema == "scworkbench.graph.content.v1", "GRAPH_VERSION_UNSUPPORTED", "Writer schema.")
    grant <- write_grants[[name]]
    staged <- .wb_graph_stage_new(header$direction_mode, .wb_operation_pack_v4_graph_budgets(grant$resource_budgets))
    state$graph_opened[[name]] <- staged
    finished <- FALSE
    list(write_part = function(component, rows) {
      .wb_graph_require(!finished && !state$used, "GRAPH_WRITER_RETIRED", "Graph writer finished.")
      .wb_graph_require(component %in% .wb_graph_components(), "GRAPH_PART_ORDER_INVALID", "Unknown graph component.")
      for (row in rows) .wb_graph_row_validate(component, row)
      .wb_graph_append(staged, component, rows)
      invisible(NULL)
    }, finish = function() {
      .wb_graph_require(!finished && !state$used, "GRAPH_WRITER_RETIRED", "Graph writer finished.")
      identity <- .wb_graph_sql_identities(staged$con, "staged", staged$budgets)
      .wb_graph_sources_assert(bundle, staged$con, "staged", staged$budgets)
      count <- c(list(header = "1"), stats::setNames(lapply(.wb_graph_components(),
        function(component) .wb_graph_count(staged$con, "staged", component)), .wb_graph_components()))
      .wb_graph_require(grant$binding_policy != "required" || count$bindings != "0",
        "GRAPH_BINDINGS_REQUIRED", "Graph output requires bindings.")
      .wb_graph_require(grant$binding_policy != "forbidden" || count$bindings == "0",
        "GRAPH_BINDINGS_FORBIDDEN", "Graph output forbids bindings.")
      .wb_operation_pack_v4_graph_authorities_assert(bundle, grant)
      .wb_operation_pack_v4_graph_output_bindings_assert(staged, grant)
      for (component in c("nodes", "edges", "incidences", "attribute_fields"))
        .wb_graph_require(.wb_graph_i64(count[[component]]) <=
          .wb_graph_i64(grant$resource_budgets[[paste0("max_", component)]]),
          "GRAPH_RESOURCE_EXCEEDED", "Graph output count budget exceeded.")
      root <- file.path(stage_root, "outputs", name)
      dir.create(root, recursive = TRUE, showWarnings = FALSE)
      parts <- file.path(root, "graph.parts.ndjson")
      observations <- .wb_graph_export_parts(staged$con, "staged", parts, staged$budgets)
      .wb_graph_require(file.info(parts)$size <= as.numeric(grant$resource_budgets$max_staged_bytes),
        "GRAPH_RESOURCE_EXCEEDED", "Graph transport exceeds staged budget.")
      sealed <- list(output_name = name, grant_identity = grant$grant_identity,
        content_identity = identity$content_identity, binding_identity = identity$binding_identity,
        descriptor_identity = identity$descriptor_identity, component_counts = count,
        component_observations = observations, complete = TRUE)
      sealed$sealed_output_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.graph.sealed_output.v1", "seal excluding sealed_output_identity", sealed)
      .wb_operation_pack_v2_atomic_json(list(schema = "scworkbench.graph.staged_payload.v1",
        output_name = name, parts_file = "graph.parts.ndjson", observation = sealed),
        file.path(root, "payload.json"))
      .wb_graph_require(sum(file.info(c(parts, file.path(root, "payload.json")))$size) <=
        as.numeric(grant$resource_budgets$max_staged_bytes), "GRAPH_RESOURCE_EXCEEDED",
        "Complete graph stage including its descriptor exceeds admitted staged bytes.")
      state$writes[[name]] <- list(graph_observation = sealed, payload = parts)
      finished <<- TRUE
      .wb_graph_stage_discard(staged)
      invisible(NULL)
    })
  }
  base$writers$open_graph <- open
  base$writers$write_graph <- function(name, value) {
    grant <- write_grants[[name]]
    .wb_graph_require(!is.null(grant), "GRAPH_WRITER_REQUIRED", "No graph output grant.")
    budgets <- .wb_operation_pack_v4_graph_budgets(grant$resource_budgets)
    staged <- .wb_graph_stage_small(value, budgets)
    on.exit(.wb_graph_stage_discard(staged), add = TRUE)
    writer <- open(name, list(schema = "scworkbench.graph.content.v1", direction_mode = value$content$direction_mode))
    for (component in .wb_graph_components()) .wb_graph_scan(staged$con, "staged", component,
      function(rows) writer$write_part(component, lapply(rows$record_json, .wb_graph_parse)),
      page = budgets$partition_rows, bytes = budgets$partition_bytes)
    writer$finish()
  }
  original_consume <- base$consume
  base$consume <- function() {
    for (staged in state$graph_opened) .wb_graph_stage_discard(staged)
    original_consume()
  }
  base
}
