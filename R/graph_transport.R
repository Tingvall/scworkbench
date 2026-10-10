# Bounded component transport inside the existing private transition workspace.
# These hashes authenticate transport observations, never replace graph roots.
.wb_graph_partition <- function(component, first_ordinal, rows) {
  value <- list(schema = "scworkbench.graph.component_partition.v1",
    component = component, first_ordinal = first_ordinal,
    row_count = as.character(length(rows)), rows = rows)
  value$partition_identity <- .wb_graph_identity("scworkbench.graph.partition.v1", value)
  value
}

.wb_graph_chain_seed <- function(component) .wb_graph_identity(
  "scworkbench.graph.partition_chain.v1", list(
    schema = "scworkbench.graph.partition_chain.v1", component = component,
    partition_count = "0", previous = NULL))

.wb_graph_observations_new <- function() stats::setNames(lapply(
  c("header", .wb_graph_components()), function(component) list(rows = "0",
    partitions = "0", chain_identity = .wb_graph_chain_seed(component))),
  c("header", .wb_graph_components()))

.wb_graph_observe_part <- function(observations, part) {
  previous <- observations[[part$component]]
  .wb_graph_require(!is.null(previous) && identical(previous$rows, part$first_ordinal),
    "GRAPH_PART_ORDER_INVALID", "Repeated, missing or foreign partition.")
  count <- .wb_graph_add_count(previous$partitions, 1L)
  observations[[part$component]] <- list(
    rows = .wb_graph_add_count(previous$rows, .wb_graph_i64(part$row_count)),
    partitions = count, chain_identity = .wb_graph_identity(
      "scworkbench.graph.partition_chain.v1", list(
        schema = "scworkbench.graph.partition_chain.v1", component = part$component,
        partition_count = count, previous = previous$chain_identity,
        partition_identity = part$partition_identity)))
  observations
}

.wb_graph_partition_validate <- function(part, budgets) {
  .wb_graph_closed(part, c("schema", "component", "first_ordinal", "row_count",
    "rows", "partition_identity"), "graph partition")
  .wb_graph_require(identical(part$schema, "scworkbench.graph.component_partition.v1") &&
    .wb_graph_string(part$component) && part$component %in%
      c("header", .wb_graph_components()), "GRAPH_PART_ORDER_INVALID", "Unknown partition.")
  .wb_graph_i64(part$first_ordinal); .wb_graph_i64(part$row_count)
  .wb_graph_require(is.list(part$rows) && is.null(names(part$rows)) &&
    length(part$rows) > 0 && length(part$rows) <= budgets$partition_rows &&
    identical(part$row_count, as.character(length(part$rows))),
    "GRAPH_PART_ORDER_INVALID", "Incomplete partition rows.")
  .wb_graph_materialization_admit(part, budgets$partition_bytes)
  .wb_graph_identity_assert(part$partition_identity, "scworkbench.graph.partition.v1")
  preimage <- part; preimage$partition_identity <- NULL
  .wb_graph_require(identical(part$partition_identity,
    .wb_graph_identity("scworkbench.graph.partition.v1", preimage)),
    "GRAPH_CONTENT_IDENTITY_MISMATCH", "Partition bytes differ from its identity.")
  invisible(TRUE)
}

.wb_graph_ndjson_reader <- function(path, line_bytes) {
  .wb_graph_require(is.numeric(line_bytes) && length(line_bytes) == 1L &&
    is.finite(line_bytes) && line_bytes > 0 && line_bytes <= 2147483647,
    "GRAPH_RESOURCE_POLICY_INVALID", "Invalid transport record budget.")
  con <- file(path, "rb")
  closed <- FALSE; buffer <- raw()
  retire <- function() {if (!closed) close(con); closed <<- TRUE; invisible(TRUE)}
  next_line <- function() {
    .wb_graph_require(!closed, "GRAPH_READER_RETIRED", "Transport reader retired.")
    repeat {
      positions <- which(buffer == as.raw(10))
      if (length(positions)) {
        end <- positions[[1]]
        .wb_graph_require(end > 1L && end - 1L <= line_bytes,
          "GRAPH_RESOURCE_EXCEEDED", "Empty/oversized graph transport line.")
        line <- rawToChar(buffer[seq_len(end - 1L)])
        buffer <<- if (end < length(buffer)) buffer[seq.int(end + 1L, length(buffer))] else raw()
        return(line)
      }
      .wb_graph_require(length(buffer) <= line_bytes,
        "GRAPH_RESOURCE_EXCEEDED", "Graph transport record exceeds byte budget before decoding.")
      chunk <- readBin(con, "raw", n = min(65536L, line_bytes + 1L - length(buffer)))
      if (!length(chunk)) {
        .wb_graph_require(!length(buffer), "GRAPH_READER_INCOMPLETE",
          "Interrupted graph transport: final newline missing.")
        retire(); return(NULL)
      }
      buffer <<- c(buffer, chunk)
    }
  }
  list(next_line = next_line, close = retire)
}

.wb_graph_import_parts <- function(path, budgets = list(), expected = NULL) {
  budgets <- .wb_graph_budgets(budgets)
  reader <- .wb_graph_ndjson_reader(path, budgets$partition_bytes)
  state <- NULL; succeeded <- FALSE
  on.exit({reader$close(); if (!succeeded && !is.null(state)) .wb_graph_stage_discard(state)}, add = TRUE)
  observations <- .wb_graph_observations_new()
  first <- TRUE
  repeat {
    line <- reader$next_line()
    if (is.null(line)) break
    .wb_operation_pack_v2_assert_strict_json(line)
    part <- .wb_graph_parse(line)
    .wb_graph_partition_validate(part, budgets)
    if (first) {
      .wb_graph_require(part$component == "header" && part$first_ordinal == "0" &&
        part$row_count == "1", "GRAPH_PART_ORDER_INVALID", "Header must occur once first.")
      header <- part$rows[[1]]
      .wb_graph_closed(header, c("schema", "direction_mode"), "graph header")
      .wb_graph_require(identical(header$schema, "scworkbench.graph.content.v1"),
        "GRAPH_VERSION_UNSUPPORTED", "Unsupported graph content header.")
      state <- .wb_graph_stage_new(header$direction_mode, budgets)
      first <- FALSE
    } else {
      .wb_graph_require(part$component != "header", "GRAPH_PART_ORDER_INVALID", "Repeated header.")
      for (row in part$rows) .wb_graph_row_validate(part$component, row)
      .wb_graph_append(state, part$component, part$rows, part$first_ordinal)
    }
    observations <- .wb_graph_observe_part(observations, part)
  }
  .wb_graph_require(!first, "GRAPH_READER_INCOMPLETE", "Missing graph header.")
  state$seal <- .wb_graph_sql_identities(state$con, "staged", state$budgets)
  state$observations <- observations
  if (!is.null(expected)) {
    counts <- c(list(header = "1"), stats::setNames(lapply(.wb_graph_components(),
      function(component) .wb_graph_count(state$con, "staged", component)), .wb_graph_components()))
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(counts),
      .wb_operation_pack_canonical_json(expected$component_counts)),
      "GRAPH_SEAL_MISMATCH", "Imported SQL counts disagree with the complete declared output seal.")
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(observations),
      .wb_operation_pack_canonical_json(expected$component_observations)),
      "GRAPH_SEAL_MISMATCH", "Imported partitions disagree with independently issued observation.")
    for (field in c("content_identity", "binding_identity", "descriptor_identity"))
      .wb_graph_require(identical(state$seal[[field]], expected[[field]]),
        "GRAPH_SEAL_MISMATCH", "Imported payload disagrees with the complete declared output seal.")
  }
  state$finished <- TRUE; succeeded <- TRUE
  state
}

.wb_graph_export_parts <- function(con, artifact_id, path, budgets = list()) {
  budgets <- .wb_graph_budgets(budgets)
  link <- Sys.readlink(path)
  .wb_graph_require(!file.exists(path) && (is.na(link) || !nzchar(link)),
    "GRAPH_WRITER_RETIRED", "Graph transport destination already exists.")
  .wb_graph_require(budgets$partition_bytes > 1024,
    "GRAPH_RESOURCE_EXCEEDED", "Partition budget cannot admit the transport envelope.")
  output <- file(path, "wb"); succeeded <- FALSE
  on.exit({close(output); if (!succeeded && file.exists(path)) unlink(path)}, add = TRUE)
  observations <- .wb_graph_observations_new()
  emit <- function(part) {
    .wb_graph_partition_validate(part, budgets)
    writeBin(charToRaw(paste0(.wb_operation_pack_canonical_json(part), "\n")), output)
    observations <<- .wb_graph_observe_part(observations, part)
  }
  mode <- DBI::dbGetQuery(con, "SELECT direction_mode FROM artifact_graph_meta WHERE artifact_id=?;",
    params = list(artifact_id))$direction_mode[[1]]
  emit(.wb_graph_partition("header", "0", list(list(
    schema = "scworkbench.graph.content.v1", direction_mode = mode))))
  for (component in .wb_graph_components()) .wb_graph_scan(con, artifact_id, component,
    function(rows) emit(.wb_graph_partition(component, as.character(rows$row_ordinal[[1]]),
      lapply(rows$record_json, .wb_graph_parse))), page = budgets$partition_rows,
    bytes = budgets$partition_bytes - 1024)
  succeeded <- TRUE
  observations
}
