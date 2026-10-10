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
  run <- wb_new_run("graph_contract_fixture", inputs = list(), params = list(),
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
