test_graph_abi4_actual_payload_count_contract <- function() {
  ns <- asNamespace("scworkbench")
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list())
  staged <- get(".wb_graph_stage_small", ns)(graph)
  root <- tempfile("graph_count_admission_")
  dir.create(file.path(root, "outputs", "result"), recursive = TRUE)
  on.exit({get(".wb_graph_stage_discard", ns)(staged); unlink(root, recursive = TRUE)}, add = TRUE)
  parts <- file.path(root, "outputs", "result", "graph.parts.ndjson")
  observations <- get(".wb_graph_export_parts", ns)(staged$con, "staged", parts)
  seal <- c(list(output_name = "result", grant_identity = list(),
    component_counts = c(list(header = "1"), as.list(staged$counts)),
    component_observations = observations, complete = TRUE), wb_graph_identity(graph))
  write_seal <- function(seal) get(".wb_operation_pack_v2_atomic_json", ns)(
    list(schema = "scworkbench.graph.staged_payload.v1", output_name = "result",
      parts_file = "graph.parts.ndjson", observation = seal),
    file.path(root, "outputs", "result", "payload.json"))
  fixture <- jsonlite::read_json("tests/fixtures/graph-abi4-draft-interop.json", simplifyVector = FALSE)
  grant <- list(resource_budgets = fixture$request$graph_write_grants[[1L]]$resource_budgets)
  payload <- get(".wb_operation_pack_v4_graph_payload", ns)
  write_seal(seal)
  admitted <- payload(root, "result", seal, grant)
  get(".wb_graph_stage_discard", ns)(admitted)
  owned_paths <- character()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "connected") owned_paths <<- c(owned_paths, state$path)
  })
  on.exit(options(old), add = TRUE)
  grant$resource_budgets$max_nodes <- "0"
  rejected <- tryCatch(payload(root, "result", seal, grant), error = identity)
  stopifnot(inherits(rejected, "wb_graph_error"),
    identical(rejected$code, "GRAPH_RESOURCE_EXCEEDED"), !any(file.exists(owned_paths)))
  grant$resource_budgets$max_nodes <- "100"
  original_staged_budget <- grant$resource_budgets$max_staged_bytes
  grant$resource_budgets$max_staged_bytes <- as.character(file.info(parts)$size)
  rejected <- tryCatch(payload(root, "result", seal, grant), error = identity)
  stopifnot(inherits(rejected, "wb_graph_error"), rejected$code == "GRAPH_RESOURCE_EXCEEDED",
    !any(file.exists(owned_paths)))
  grant$resource_budgets$max_staged_bytes <- original_staged_budget
  altered <- seal; altered$component_counts$nodes <- "2"
  altered$sealed_output_identity <- get(".wb_operation_pack_v2_identity_scoped", ns)(
    "scworkbench.graph.sealed_output.v1", "seal excluding sealed_output_identity", altered)
  write_seal(altered)
  rejected <- tryCatch(payload(root, "result", altered, grant), error = identity)
  stopifnot(inherits(rejected, "wb_graph_error"), identical(rejected$code, "GRAPH_SEAL_MISMATCH"),
    !any(file.exists(owned_paths)))
  write_seal(seal)
  admitted <- payload(root, "result", seal, grant)
  get(".wb_graph_stage_discard", ns)(admitted)
  stopifnot(!any(file.exists(owned_paths)))
  TRUE
}

test_graph_session_discard_owned_stage_contract <- function() {
  staged <- scworkbench:::.wb_graph_stage_small(wb_prim_graph(list(), list(), list()))
  on.exit(scworkbench:::.wb_graph_stage_discard(staged), add = TRUE)
  value <- structure(list(kind = "graph"), class = "wb_primitive")
  attr(value, "graph_stage") <- staged
  session <- wb_session_new()
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(),
    outputs = list(result = value))
  session <- wb_session_add_run(session, run)
  path <- staged$path
  discarded <- wb_session_discard(session)
  stopifnot(!file.exists(path), !DBI::dbIsValid(staged$con),
    is.null(discarded$staging_bundle))
  TRUE
}
