test_graph_content_frozen_identity_contract <- function() {
  file <- system.file("protocol/fixtures/graph-v1/content-identities.json",
    package = "scworkbench")
  vectors <- scworkbench:::.wb_operation_pack_parse_canonical_json(
    paste(readLines(file, encoding = "UTF-8", warn = FALSE), collapse = "\n"))
  fixtures <- stats::setNames(lapply(vectors$positive, `[[`, "content"),
    vapply(vectors$positive, `[[`, character(1), "id"))
  for (case in vectors$positive) {
    content_identity <- scworkbench:::.wb_graph_content_identity(case$content)
    stopifnot(identical(content_identity$sha256, case$expected_sha256))
    attrs <- case$content$attributes
    primitive <- wb_prim_graph(case$content$nodes, case$content$edges,
      case$content$incidences, attrs$graph, attrs$node, attrs$edge, attrs$incidence,
      direction_mode = case$content$direction_mode)
    stopifnot(isTRUE(wb_graph_validate(primitive)),
      identical(primitive$content, case$content))
  }
  mutate <- function(value, path, operation, replacement = NULL) {
    if (!length(path)) return(replacement)
    key <- if (is.null(names(value))) {
      if (path[[1]] == "-") length(value) + 1L else as.integer(path[[1]]) + 1L
    } else path[[1]]
    if (length(path) == 1L) {
      if (operation == "remove") value[key] <- NULL else value[key] <- list(replacement)
    } else value[key] <- list(mutate(value[[key]], path[-1], operation, replacement))
    value
  }
  lookup <- function(value, path) {
    for (key in path) value <- value[[if (is.null(names(value))) as.integer(key) + 1L else key]]
    value
  }
  rejected <- 0L
  for (negative in vectors$negative) {
    change <- negative$mutation
    if (!change$op %in% c("replace", "add", "remove", "copy")) next
    path <- strsplit(sub("^/", "", change$path), "/", fixed = TRUE)[[1]]
    base <- fixtures[[negative$base]]
    replacement <- if (change$op == "copy") lookup(base,
      strsplit(sub("^/", "", change$from), "/", fixed = TRUE)[[1]]) else change$value
    altered <- mutate(base, path, change$op, replacement)
    # A valid self-hash of the malicious claim must never waive structure.
    scworkbench:::.wb_operation_pack_canonical_json(altered)
    error <- tryCatch({scworkbench:::.wb_graph_content_identity(altered); NULL},
      error = identity)
    stopifnot(inherits(error, "wb_graph_error"))
    rejected <- rejected + 1L
  }
  stopifnot(rejected == 13L)
  TRUE
}

test_graph_typed_missing_values_contract <- function() {
  fields <- list(list(name = "integer", type = "int64_decimal_string",
      nullable = FALSE, values = list("-9223372036854775808")),
    list(name = "missing", type = "utf8", nullable = TRUE, values = list(NULL)),
    list(name = "negative_zero", type = "float64_le_hex", nullable = FALSE,
      values = wb_graph_encode_finite_f64(-0)))
  graph <- wb_prim_graph(list(), list(), list(), graph_attributes = fields)
  stopifnot(wb_graph_validate(graph),
    identical(fields[[3]]$values[[1]], "0000000000000080"))
  for (value in c("9223372036854775808", "-9223372036854775809", "-0", "01")) {
    graph$content$attributes$graph[[1]]$values <- list(value)
    stopifnot(inherits(tryCatch(wb_graph_validate(graph), error = identity), "wb_graph_error"))
  }
  stopifnot(inherits(tryCatch(wb_prim_graph(list(), list(), list(),
    associations = NULL), error = identity), "wb_graph_error"))
  TRUE
}

test_graph_sql_stream_identity_contract <- function() {
  vectors <- scworkbench:::.wb_operation_pack_parse_canonical_json(paste(readLines(
    system.file("protocol/fixtures/graph-v1/content-identities.json", package = "scworkbench"),
    warn = FALSE), collapse = "\n"))
  for (case in vectors$positive) {
    content <- case$content
    attrs <- content$attributes
    graph <- wb_prim_graph(content$nodes, content$edges, content$incidences,
      attrs$graph, attrs$node, attrs$edge, attrs$incidence,
      direction_mode = content$direction_mode)
    for (page in c(1L, 2L, 512L)) {
      stage <- scworkbench:::.wb_graph_stage_small(graph, list(partition_rows = page))
      tryCatch({
        stopifnot(identical(stage$content$identity$sha256, case$expected_sha256))
        if (length(content$incidences)) {
          replacement <- content$incidences[[1]]
          replacement$node_id <- "foreign"
          DBI::dbExecute(stage$con, paste0("UPDATE artifact_graph_rows SET record_json=? ",
            "WHERE component='incidences' AND row_ordinal=0;"), params = list(
              scworkbench:::.wb_operation_pack_canonical_json(replacement)))
          stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_sql_content_hash(
            stage$con, "staged", stage$budgets), error = identity), "wb_graph_error"))
        }
      }, finally = scworkbench:::.wb_graph_stage_discard(stage))
      stopifnot(!file.exists(stage$path))
    }
  }
  TRUE
}

test_graph_sql_transaction_roundtrip_contract <- function() {
  root <- tempfile("graph_sql_lifecycle_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list(),
    node_attributes = list(list(name = "caption", type = "utf8", nullable = FALSE,
      values = list("東京\nquoted\""))))
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(),
    outputs = list(graph = graph))
  before <- wb_graph_identity(graph)
  con <- bundle$con
  options_before <- options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
    if (event == "graph_component_rows") stop("injected graph publication failure")
  })
  on.exit(options(options_before), add = TRUE)
  error <- tryCatch(DBI::dbWithTransaction(con,
    scworkbench:::.wb_promote_graph(bundle, run, "graph", graph)), error = identity)
  stopifnot(inherits(error, "error"),
    DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM artifacts;")$n[[1]] == 0,
    DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM artifact_graph_rows;")$n[[1]] == 0)
  options(options_before)
  artifact <- DBI::dbWithTransaction(con,
    scworkbench:::.wb_promote_graph(bundle, run, "graph", graph))
  stopifnot(inherits(tryCatch(wb_art_load(bundle, artifact), error = identity), "wb_graph_error"))
  scworkbench:::.wb_prov_write_snapshot(bundle,
    stats::setNames(list(run), run$run_id), topo = run$run_id, heads = run$run_id,
    promoted_df = data.frame(run_id = run$run_id, output = "graph", artifact_id = artifact,
      status = "ok", stringsAsFactors = FALSE))
  loaded <- wb_art_load(bundle, artifact, "graph")
  info <- wb_art_graph_info(bundle, artifact)
  stopifnot(identical(info$content_identity, before$content_identity),
    identical(info$binding_identity, before$binding_identity),
    identical(info$descriptor_identity, before$descriptor_identity),
    identical(loaded$artifact_id, artifact),
    identical(wb_art_graph_slice(bundle, artifact, "nodes")[[1]]$node_id, "isolated"))
  DBI::dbExecute(con, "UPDATE artifact_graph_rows SET record_json=? WHERE component='nodes';",
    params = list('{"node_id":"changed"}'))
  stopifnot(inherits(tryCatch(wb_art_load(bundle, artifact), error = identity), "wb_graph_error"))
  TRUE
}

test_graph_igraph_lossless_boundary_contract <- function() {
  stopifnot(requireNamespace("igraph", quietly = TRUE))
  for (mode in c("directed", "undirected", "mixed")) {
    empty <- wb_prim_graph(list(), list(), list(), direction_mode = mode)
    stopifnot(identical(wb_graph_identity(empty),
      wb_graph_identity(wb_graph_from_igraph(wb_graph_to_igraph(empty)))))
  }
  nodes <- lapply(c("z", "a", "isolate"), function(id) list(node_id = id))
  for (direction in c("directed", "undirected")) {
    edges <- lapply(c("parallel_2", "parallel_1", "loop"), function(id)
      list(edge_id = id, kind = "ordinary", direction = direction))
    incidences <- list()
    for (i in seq_along(edges)) for (j in 0:1) incidences[[length(incidences) + 1L]] <-
      list(incidence_id = paste0("i", i, "_", j), edge_id = edges[[i]]$edge_id,
        node_id = if (i == 3L || j == 0L) "z" else "a",
        role = if (direction == "undirected") "member" else if (j == 0L) "tail" else "head",
        ordinal = j)
    graph <- wb_prim_graph(nodes, edges, incidences,
      node_attributes = list(list(name = "bool", type = "bool", nullable = TRUE,
          values = list(TRUE, FALSE, NULL)),
        list(name = "text", type = "utf8", nullable = FALSE, values = list("é", "東京", "")),
        list(name = "int64", type = "int64_decimal_string", nullable = FALSE,
          values = list("9223372036854775807", "-9223372036854775808", "0"))),
      edge_attributes = list(list(name = "weight", type = "float64_le_hex", nullable = TRUE,
        values = wb_graph_encode_finite_f64(c(-0, 2.5, NA_real_)))), direction_mode = "mixed")
    native <- wb_graph_to_igraph(graph)
    restored <- wb_graph_from_igraph(native)
    stopifnot(identical(wb_graph_identity(graph), wb_graph_identity(restored)),
      igraph::vcount(native) == 3, igraph::ecount(native) == 3)
    changed <- igraph::set_edge_attr(native, "weight", value = c(0, 2.5, NA_real_))
    stopifnot(inherits(tryCatch(wb_graph_from_igraph(changed), error = identity), "wb_graph_error"))
    dropped <- igraph::delete_edges(native, 1)
    stopifnot(inherits(tryCatch(wb_graph_from_igraph(dropped), error = identity), "wb_graph_error"))
    stopifnot(inherits(tryCatch(wb_graph_to_igraph(graph, materialization_bytes = 1),
      error = identity), "wb_graph_error"))
  }
  graph$content$edges[[1]]$kind <- "hyper"
  stopifnot(inherits(tryCatch(wb_graph_to_igraph(graph), error = identity), "wb_graph_error"))
  TRUE
}

test_graph_hidden_row_closure_contract <- function() {
  graph <- wb_prim_graph(list(list(node_id = "visible")), list(), list())
  attacks <- list(list(component = "nodes", ordinal = -1),
    list(component = "unknown", ordinal = 0), list(component = "nodes", ordinal = 0.5))
  for (attack in attacks) {
    stage <- scworkbench:::.wb_graph_stage_small(graph)
    tryCatch({
      DBI::dbExecute(stage$con, "PRAGMA ignore_check_constraints=ON;")
      DBI::dbExecute(stage$con, paste0("INSERT INTO artifact_graph_rows ",
        "(artifact_id,component,row_ordinal,record_json) VALUES('staged',?,?,?);"),
        params = list(attack$component, attack$ordinal, '{"node_id":"hidden"}'))
      error <- tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con, "staged"),
        error = identity)
      stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_ROWS_INVALID")
    }, finally = scworkbench:::.wb_graph_stage_discard(stage))
  }
  TRUE
}

test_graph_decoded_partition_budget_contract <- function() {
  nodes <- lapply(1:3, function(i) list(node_id = paste0("n", i)))
  graph <- wb_prim_graph(nodes, list(), list(), node_attributes = list(list(
    name = "large", type = "utf8", nullable = FALSE,
    values = rep(list(paste(rep("é", 20000), collapse = "")), 3))))
  stage <- scworkbench:::.wb_graph_stage_small(graph,
    list(partition_bytes = 50000, partition_rows = 512L))
  on.exit(scworkbench:::.wb_graph_stage_discard(stage), add = TRUE)
  batches <- integer()
  scworkbench:::.wb_graph_scan(stage$con, "staged", "attribute_values", function(rows) {
    stopifnot(sum(nchar(rows$record_json, type = "bytes")) <= 50000)
    batches <<- c(batches, nrow(rows))
  }, page = 512L, bytes = 50000)
  stopifnot(identical(batches, c(1L, 1L, 1L)),
    identical(stage$content$identity, wb_graph_identity(graph)$content_identity))
  error <- tryCatch(scworkbench:::.wb_graph_scan(stage$con, "staged", "attribute_values",
    function(rows) stop("must not decode"), bytes = 100), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_RESOURCE_EXCEEDED")
  error <- tryCatch(scworkbench:::.wb_graph_stage_small(graph, list(collect_bytes = 100)),
    error = identity)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_RESOURCE_EXCEEDED")
  TRUE
}

test_graph_padded_edge_byte_admission_contract <- function() {
  nodes <- list(list(node_id = "node"))
  edges <- lapply(seq_len(9L), function(i) list(edge_id = paste0("edge_", i),
    kind = "ordinary", direction = "undirected"))
  incidences <- unlist(lapply(seq_along(edges), function(i) lapply(0:1, function(j)
    list(incidence_id = paste0("inc_", i, "_", j), edge_id = edges[[i]]$edge_id,
      node_id = "node", role = "member", ordinal = j))), recursive = FALSE)
  graph <- wb_prim_graph(nodes, edges, incidences, direction_mode = "undirected")
  stage <- scworkbench:::.wb_graph_stage_small(graph,
    list(partition_bytes = 4096, partition_rows = 512L))
  on.exit(scworkbench:::.wb_graph_stage_discard(stage), add = TRUE)
  for (i in seq_along(edges)) {
    text <- scworkbench:::.wb_operation_pack_canonical_json(edges[[i]])
    text <- paste0(text, strrep(" ", 4096 - nchar(text, type = "bytes")))
    DBI::dbExecute(stage$con,
      "UPDATE artifact_graph_rows SET record_json=? WHERE component='edges' AND row_ordinal=?;",
      params = list(text, i - 1L))
  }
  batches <- list()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "edge_aggregate_batch") batches[[length(batches) + 1L]] <<- state
  })
  on.exit(options(old), add = TRUE)
  result <- scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets)
  stopifnot(length(batches) >= 9L,
    all(vapply(batches, function(x) x$rows == 1L && x$encoded_bytes <= 4096, logical(1))),
    identical(result$content_identity, wb_graph_identity(graph)$content_identity))
  DBI::dbExecute(stage$con, "PRAGMA ignore_check_constraints=ON;")
  for (field in c("profile", "direction_mode", "canonical_bytes")) {
    before <- DBI::dbGetQuery(stage$con, paste0("SELECT ", field, " FROM artifact_graph_meta;"))[[1L]][[1L]]
    DBI::dbExecute(stage$con, paste0("UPDATE artifact_graph_meta SET ", field, "=?;"),
      params = list(strrep("x", 4097)))
    err <- tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets), error = identity)
    stopifnot(inherits(err, "wb_graph_error"), err$code == "GRAPH_RESOURCE_EXCEEDED")
    DBI::dbExecute(stage$con, paste0("UPDATE artifact_graph_meta SET ", field, "=?;"), params = list(before))
  }
  DBI::dbExecute(stage$con, "PRAGMA ignore_check_constraints=OFF;")
  TRUE
}

test_graph_factory_failure_cleanup_contract <- function() {
  captured <- NULL
  prior <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "connected") {captured <<- state; stop("injected setup failure")}
  })
  on.exit(options(prior), add = TRUE)
  error <- tryCatch(scworkbench:::.wb_graph_stage_new("mixed"), error = identity)
  stopifnot(inherits(error, "error"), identical(conditionMessage(error), "injected setup failure"),
    !is.null(captured), isTRUE(captured$closed), !DBI::dbIsValid(captured$con),
    !file.exists(captured$path), !file.exists(paste0(captured$path, "-journal")))
  TRUE
}

test_graph_sql_binding_descriptor_frozen_identity_contract <- function() {
  cases <- scworkbench:::.wb_graph_parse(paste(readLines(system.file(
    "protocol/fixtures/graph-v1/binding-descriptor-identities.json", package = "scworkbench"),
    warn = FALSE), collapse = "\n"))$positive
  stopifnot(length(cases) == 13L)
  for (case in cases) {
    content <- case$content; attrs <- content$attributes
    graph <- wb_prim_graph(content$nodes, content$edges, content$incidences,
      attrs$graph, attrs$node, attrs$edge, attrs$incidence,
      associations = case$claimed_projections$binding_preimage$bindings,
      direction_mode = content$direction_mode)
    for (page in c(1L, 2L, 512L)) {
      stage <- scworkbench:::.wb_graph_stage_small(graph, list(partition_rows = page))
      tryCatch({
        actual <- scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets)
        for (field in c("content_identity", "binding_identity", "descriptor_identity"))
          stopifnot(identical(actual[[field]], case$claimed_projections[[field]]))
        if (scworkbench:::.wb_graph_count(stage$con, "staged", "binding_mappings") != "0") {
          row <- scworkbench:::.wb_graph_parse(DBI::dbGetQuery(stage$con,
            "SELECT record_json FROM artifact_graph_rows WHERE component='binding_mappings' ORDER BY row_ordinal LIMIT 1;")$record_json[[1]])
          row$mapping_ordinal <- "1"
          DBI::dbExecute(stage$con, "UPDATE artifact_graph_rows SET record_json=? WHERE component='binding_mappings' AND row_ordinal=0;",
            params = list(scworkbench:::.wb_operation_pack_canonical_json(row)))
          stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con,
            "staged", stage$budgets), error = identity), "wb_graph_error"))
        }
      }, finally = scworkbench:::.wb_graph_stage_discard(stage))
    }
  }
  TRUE
}

test_graph_sdk_collect_contract <- function() {
  graph <- wb_prim_graph(list(list(node_id = "z"), list(node_id = "a")), list(), list(),
    node_attributes = list(list(name = "label", type = "utf8", nullable = TRUE,
      values = list("second", NULL))))
  stage <- scworkbench:::.wb_graph_stage_small(graph)
  on.exit(scworkbench:::.wb_graph_stage_discard(stage), add = TRUE)
  parts <- list()
  add <- function(component, ordinal, rows) {
    value <- list(schema = "scworkbench.graph.component_partition.v1",
      component = component, first_ordinal = ordinal, row_count = as.character(length(rows)), rows = rows)
    value$partition_identity <- scworkbench:::.wb_graph_identity("scworkbench.graph.partition.v1", value)
    parts[[length(parts) + 1L]] <<- value
  }
  add("header", "0", list(list(schema = "scworkbench.graph.content.v1", direction_mode = "mixed")))
  for (component in scworkbench:::.wb_graph_components())
    scworkbench:::.wb_graph_scan(stage$con, "staged", component, function(rows)
      add(component, as.character(rows$row_ordinal[[1]]),
        lapply(rows$record_json, scworkbench:::.wb_graph_parse)), page = 1L)
  expected_identity <- wb_graph_identity(graph)
  counts <- c(list(header = "1"), as.list(stage$counts))
  reader <- function(chunks) {
    cursor <- 0L
    list(header = c(list(direction_mode = "mixed", component_counts = counts), expected_identity),
      next_part = function() {cursor <<- cursor + 1L; if (cursor <= length(chunks)) chunks[[cursor]] else NULL})
  }
  loaded <- wb_graph_collect(reader(parts))
  stopifnot(identical(wb_graph_identity(loaded), expected_identity))
  for (chunks in list(parts[-1], c(parts[1], parts), parts[-length(parts)]))
    stopifnot(inherits(tryCatch(wb_graph_collect(reader(chunks)), error = identity), "wb_graph_error"))
  altered <- parts
  altered[[2]]$rows[[1]]$node_id <- "foreign"
  stopifnot(inherits(tryCatch(wb_graph_collect(reader(altered)), error = identity), "wb_graph_error"),
    inherits(tryCatch(wb_graph_collect(reader(parts), materialization_bytes = 1),
      error = identity), "wb_graph_error"))
  TRUE
}

test_graph_bounded_transport_seal_contract <- function() {
  graph <- wb_prim_graph(lapply(c("z", "b", "a"), function(id) list(node_id = id)),
    list(), list(), node_attributes = list(list(name = "title", type = "utf8",
      nullable = TRUE, values = list("hi", NULL, "東京"))))
  stage <- scworkbench:::.wb_graph_stage_small(graph, list(partition_rows = 1L))
  path <- tempfile("graph_parts_"); changed <- tempfile("graph_parts_bad_")
  on.exit({scworkbench:::.wb_graph_stage_discard(stage); unlink(c(path, changed))}, add = TRUE)
  observed <- scworkbench:::.wb_graph_export_parts(stage$con, "staged", path,
    list(partition_rows = 1L))
  expected <- c(list(component_observations = observed,
    component_counts = c(list(header = "1"), as.list(stage$counts))), wb_graph_identity(graph))
  loaded <- scworkbench:::.wb_graph_import_parts(path, expected = expected)
  stopifnot(identical(loaded$seal$content_identity, expected$content_identity))
  scworkbench:::.wb_graph_stage_discard(loaded)
  lines <- readLines(path, warn = FALSE)
  cases <- list(lines[-1], c(lines[1], lines), lines[-length(lines)], lines[c(1, 3, 2, 4:length(lines))])
  node <- scworkbench:::.wb_graph_parse(lines[[2]])
  node$rows[[1]]$node_id <- "self_rehashed_foreign"
  node$partition_identity <- NULL
  node$partition_identity <- scworkbench:::.wb_graph_identity("scworkbench.graph.partition.v1", node)
  altered <- lines; altered[[2]] <- scworkbench:::.wb_operation_pack_canonical_json(node)
  cases[[length(cases) + 1L]] <- altered
  before <- sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))
  for (case in cases) {
    writeLines(case, changed, useBytes = TRUE)
    error <- tryCatch(scworkbench:::.wb_graph_import_parts(changed, expected = expected), error = identity)
    stopifnot(inherits(error, "wb_graph_error"),
      identical(before, sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))))
  }
  # Reject an oversized line before decoding it, including a valid self-hash.
  error <- tryCatch(scworkbench:::.wb_graph_import_parts(path,
    budgets = list(partition_bytes = 100)), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_RESOURCE_EXCEEDED")
  writeChar(lines[[1]], changed, eos = NULL, useBytes = TRUE)
  error <- tryCatch(scworkbench:::.wb_graph_import_parts(changed), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_READER_INCOMPLETE")
  TRUE
}
