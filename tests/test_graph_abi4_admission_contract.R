test_graph_abi4_closed_admission_contract <- function() {
  fixture <- jsonlite::read_json("tests/fixtures/graph-abi4-draft-interop.json", simplifyVector = FALSE)
  ns <- asNamespace("scworkbench")
  manifest <- get(".wb_operation_pack_v4_normalize", ns)(fixture$manifest)
  stopifnot(identical(manifest$pack_abi_version, "4"), length(manifest$operations) == 4L)
  for (kind in c("request", "receipt"))
    get(".wb_operation_pack_v4_schema_assert", ns)(fixture[[kind]], kind)
  definition <- get(".wb_operation_pack_v4_catalog_definition", ns)(manifest$operations[[2L]])
  stopifnot(identical(definition$pack_abi_version, "4"),
    identical(definition$coverage[["source"]], "reference_only"),
    identical(definition$coverage[["metadata"]], "reference_only"))
  wrong <- manifest; wrong$pack_abi_version <- "3"
  stopifnot(inherits(tryCatch(get(".wb_operation_pack_v4_normalize", ns)(wrong),
    error = identity), "wb_operation_pack_error"))
  bad <- manifest; bad$operations[[1L]]$outputs[[1L]]$resource_budgets$undeclared <- "1"
  stopifnot(inherits(tryCatch(get(".wb_operation_pack_v4_normalize", ns)(bad),
    error = identity), "wb_operation_pack_error"))
  TRUE
}

test_graph_abi4_axis_source_declaration_contract <- function() {
  fixture <- jsonlite::read_json("tests/fixtures/graph-abi4-draft-interop.json", simplifyVector = FALSE)
  normalize <- scworkbench:::.wb_operation_pack_v4_normalize
  before <- wb_list_ops()
  good <- normalize(fixture$manifest)
  bound <- which(vapply(good$operations, function(op) op$name == "graph_and_cell_vector", logical(1)))
  stopifnot(length(bound) == 1L,
    good$operations[[bound]]$outputs[[1L]]$axis_sources[[1L]]$selection_mode == "retained_input_axis")
  for (attack in c("missing_source", "foreign_input", "wrong_kind", "duplicate_source",
      "unexpected_selector", "foreign_axis", "omitted_sources")) {
    bad <- good
    output <- bad$operations[[bound]]$outputs[[1L]]
    source <- output$axis_sources[[1L]]
    if (attack == "missing_source") output$axis_sources <- list()
    if (attack == "foreign_input") source$input_name <- "absent"
    if (attack == "wrong_kind") source$input_name <- "source"
    if (attack == "unexpected_selector") source$source_binding_selector <- list(kind = "fixed_binding_id_v1", binding_id = "other")
    if (attack == "foreign_axis") source$axis_kind <- "feature"
    if (!attack %in% c("missing_source", "omitted_sources")) output$axis_sources <- list(source)
    if (attack == "duplicate_source") output$axis_sources <- list(source, source)
    if (attack == "omitted_sources") output$axis_sources <- NULL
    bad$operations[[bound]]$outputs[[1L]] <- output
    rejected <- tryCatch(normalize(bad), error = identity)
    if (!inherits(rejected, "error")) stop(paste("Axis declaration attack accepted:", attack))
    stopifnot(identical(before, wb_list_ops()))
  }
  TRUE
}

test_graph_abi4_core_issued_request_contract <- function() {
  fixture <- jsonlite::read_json("tests/fixtures/graph-abi4-draft-interop.json", simplifyVector = FALSE)
  ns <- asNamespace("scworkbench")
  fixture$manifest$backend <- "R"
  fixture$manifest$package$name <- "scwbGraphFixture"
  fixture$manifest$entry_point <- "scwbGraphFixture::register_operation_pack"
  fixture$manifest$compatibility$process_protocol <- NULL
  fixture$manifest$operations[[2L]]$outputs[[1L]]$axis_sources <- list()
  manifest <- get(".wb_operation_pack_v4_normalize", ns)(fixture$manifest)
  root <- tempfile("graph_abi4_request_"); bundle <- wb_init_bundle(root)
  stage <- tempfile("graph_abi4_request_stage_"); dir.create(stage)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE); unlink(root, recursive = TRUE);
    unlink(stage, recursive = TRUE)}, add = TRUE)
  graph <- wb_prim_graph(list(), list(), list(), direction_mode = "undirected")
  run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"),
    params = list(), outputs = list(vector = graph))
  promoted <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  value <- wb_art_load(bundle, promoted$promoted$artifact_id[[1L]])
  op <- manifest$operations[[3L]]
  pack_identity <- get(".wb_operation_pack_v4_identity", ns)(manifest,
    paste(rep("a", 64L), collapse = ""), list(scheme = "scworkbench.operation_pack.content.v1",
      sha256 = paste(rep("b", 64L), collapse = "")))
  registration <- structure(list(manifest = manifest, identity = pack_identity),
    class = c("wb_operation_pack_registration_v4", "wb_operation_pack_registration_v3",
      "wb_operation_pack_registration_v2"))
  inputs <- list(source = value)
  preflight <- get(".wb_operation_pack_v2_preflight", ns)(op, inputs, list(), registration)
  request <- get(".wb_operation_pack_v4_request", ns)(bundle, registration, op, inputs,
    list(), "transition_fixture", "session_fixture", "run_fixture", "ephemeral", preflight, stage)
  get(".wb_operation_pack_v4_schema_assert", ns)(request, "request")
  get(".wb_operation_pack_v4_request_audit", ns)(request, registration, op, bundle, inputs, list())
  get(".wb_operation_pack_v4_sources_assert_current", ns)(bundle, request)
  stopifnot(request$pack_abi_version == "4", request$process_protocol_version == "pybench-op-v5",
    length(request$graph_read_grants) == 1L, request$graph_read_grants[[1L]]$component_counts$nodes == "0",
    identical(request$execution_capability$reader_grants[[1L]]$grant_identity,
      request$graph_read_grants[[1L]]$grant_identity))
  adapter <- get(".wb_operation_pack_v3_capability_adapter", ns)(request, op, list(), stage, bundle)
  adapter <- get(".wb_operation_pack_v4_graph_adapter", ns)(adapter, request, bundle, stage)
  reader <- adapter$readers$source()
  roundtrip <- wb_graph_collect(reader)
  stopifnot(identical(wb_graph_identity(roundtrip), wb_graph_identity(graph)),
    length(adapter$state$graph_cursors) == 1L,
    isTRUE(adapter$state$graph_cursors$source$usage()$complete))
  stopifnot(inherits(tryCatch(adapter$readers$source(), error = identity), "wb_graph_error"),
    inherits(tryCatch(reader$next_part(), error = identity), "wb_graph_error"))
  adapter$consume()
  # Reuse the same mixed request pipeline for a graph and ordinary table.
  op <- manifest$operations[[2L]]
  metadata <- wb_prim_obs_table(data.frame(value = "label"), table_type = "graph_summary")
  inputs <- list(source = value, metadata = metadata)
  preflight <- get(".wb_operation_pack_v2_preflight", ns)(op, inputs, list(), registration)
  request <- get(".wb_operation_pack_v4_request", ns)(bundle, registration, op, inputs,
    list(), "transition_mixed", "session_mixed", "run_mixed", "ephemeral", preflight, stage)
  get(".wb_operation_pack_v4_request_audit", ns)(request, registration, op, bundle, inputs, list())
  adapter <- get(".wb_operation_pack_v3_capability_adapter", ns)(request, op,
    list(metadata = metadata), stage, bundle)
  adapter <- get(".wb_operation_pack_v4_graph_adapter", ns)(adapter, request, bundle, stage)
  on.exit(adapter$consume(), add = TRUE)
  copied <- wb_graph_collect(adapter$readers$source())
  adapter$writers$write_graph("result", copied)
  adapter$writers$write_terminal_primitive("summary", metadata)
  stopifnot(setequal(names(adapter$state$writes), c("result", "summary")),
    isTRUE(adapter$state$writes$result$graph_observation$complete))
  imported <- get(".wb_graph_import_parts", ns)(adapter$state$writes$result$payload,
    expected = adapter$state$writes$result$graph_observation)
  on.exit(get(".wb_graph_stage_discard", ns)(imported), add = TRUE)
  stopifnot(identical(imported$seal$content_identity, wb_graph_identity(graph)$content_identity))
  usage <- lapply(adapter$state$graph_cursors, function(cursor) cursor$usage())
  receipt <- get(".wb_operation_pack_v4_receipt", ns)(request, registration, op,
    adapter$state$writes, preflight, inputs, graph_read_usage = usage)
  get(".wb_operation_pack_v4_receipt_audit", ns)(receipt, request, registration, op, preflight,
    graph_read_usage = unname(usage))
  get(".wb_operation_pack_v2_atomic_json", ns)(request, file.path(stage, "request.json"))
  get(".wb_operation_pack_v2_atomic_json", ns)(receipt, file.path(stage, "receipt.json"))
  get(".wb_operation_pack_v2_atomic_json", ns)(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "reopened", transition_id = request$transition$transition_id, receipt_identity = receipt$receipt_identity),
    file.path(stage, "state.json"))
  reopened <- get(".wb_operation_pack_v2_record_validate", ns)(stage, load_payloads = TRUE)
  if (!isTRUE(reopened$ok)) stop(paste("ABI4 retained record:", reopened$code, reopened$output), call. = FALSE)
  stopifnot(isTRUE(reopened$ok))
  rehash <- function(value) {
    value$receipt_identity <- NULL
    value$receipt_identity <- get(".wb_operation_pack_v2_identity_scoped", ns)(
      "scworkbench.operation_pack.transition_receipt.v4", "receipt excluding receipt_identity", value)
    value
  }
  for (attack in c("dropped_output", "dropped_usage", "changed_usage", "changed_allocation")) {
    forged <- receipt
    if (attack == "dropped_output") forged$outputs <- forged$outputs[-1L]
    if (attack == "dropped_usage") forged$graph_read_usage <- list()
    if (attack == "changed_usage") forged$graph_read_usage[[1L]]$complete <- FALSE
    if (attack == "changed_allocation") forged$outputs[[1L]]$allocated_id <- "foreign_allocation"
    forged <- rehash(forged)
    stopifnot(inherits(tryCatch(get(".wb_operation_pack_v4_receipt_audit", ns)(forged,
      request, registration, op, preflight, graph_read_usage = unname(usage)), error = identity), "error"))
  }
  stopifnot(inherits(tryCatch(adapter$writers$write_graph("result", copied), error = identity), "wb_graph_error"))
  TRUE
}
