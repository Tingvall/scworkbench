# Opt-in installed-candidate composite. A missing interpreter/pack is a named
# skip, never a pass. Run in a fresh R process, not the native-fixture registry.
test_graph_abi4_python_live_broker_contract <- function() {
  python <- Sys.getenv("SCWORKBENCH_GRAPH_PYTHON", unset = "")
  manifest <- Sys.getenv("SCWORKBENCH_GRAPH_PYTHON_MANIFEST", unset = "")
  if (!file.exists(python) || !file.exists(manifest))
    return(contract_test_skip("Graph ABI4 live broker requires exact installed SCWORKBENCH_GRAPH_PYTHON and SCWORKBENCH_GRAPH_PYTHON_MANIFEST"))
  activated <- wb_operation_pack_activate(manifest, python = python)
  stopifnot(activated$identity$pack_abi_version == "4", activated$identity$backend == "Python")
  root <- tempfile("graph_python_live_")
  bundle <- wb_init_bundle(root)
  runs <- list()
  on.exit({
    for (result in runs) try(wb_session_discard(result$session), silent = TRUE)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE)
  }, add = TRUE)
  wb_define_cells(bundle, c("c2", "c1"))
  wb_attach_matrix(bundle, "counts", Matrix::Matrix(matrix(1:4, 2L,
    dimnames = list(c("g2", "g1"), c("c2", "c1"))), sparse = TRUE))
  graph <- wb_session_run_op(wb_session_new(), bundle,
    "scwbgraphfixture::matrix_to_graph", inputs = list(matrix = "counts", min_cells = 1L))
  runs[[length(runs) + 1L]] <- graph
  promotion <- wb_session_promote_current(bundle, graph$session, outputs = "result")
  id <- as.character(promotion$promoted$artifact_id[[1L]])
  stopifnot(identical(vapply(wb_art_graph_slice(bundle, id, "nodes"), `[[`,
    character(1), "node_id"), c("c2", "c1")))
  inspected <- wb_session_run_op(wb_session_new(), bundle,
    "scwbgraphfixture::graph_to_table", inputs = list(source = wb_ref_artifact(id, "result")))
  runs[[length(runs) + 1L]] <- inspected
  stopifnot(inspected$run$outputs$summary$table$nodes == 2L)
  wb_session_promote_current(bundle, inspected$session, outputs = "summary")
  vector <- wb_prim_cell_vector(stats::setNames(c("B", "A"), c("c2", "c1")))
  source <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(),
    outputs = list(vector = vector))
  promoted <- wb_promote_analysis(bundle, stats::setNames(list(source), source$run_id),
    source$run_id, outputs = "vector")
  source_id <- as.character(promoted$promoted$artifact_id[[1L]])
  bound <- wb_session_run_op(wb_session_new(), bundle,
    "scwbgraphfixture::graph_and_cell_vector", inputs = list(source = wb_ref_artifact(id, "result"),
      labels = wb_ref_artifact(source_id, "vector"), min_cells = 1L))
  runs[[length(runs) + 1L]] <- bound
  transition <- bound$run$operation_pack_transition$transition_id
  path <- file.path(wb_session_view(bound$session)$dir, "operation_pack_v2", transition)
  request <- jsonlite::read_json(file.path(path, "request.json"), simplifyVector = FALSE)
  receipt <- jsonlite::read_json(file.path(path, "receipt.json"), simplifyVector = FALSE)
  stopifnot(request$pack_abi_version == "4", request$process_protocol_version == "pybench-op-v5",
    isTRUE(receipt$graph_read_usage[[1L]]$complete),
    identical(receipt$graph_read_usage[[1L]]$content_identity, request$graph_read_grants[[1L]]$content_identity),
    length(receipt$outputs) == 2L,
    !dir.exists(file.path(path, "broker")),
    !file.exists(file.path(path, "graph-broker-observations.json")))
  before <- bound$run$outputs$result$descriptor_identity
  promoted <- wb_session_promote_current(bundle, bound$session, outputs = "result")
  stopifnot(nrow(promoted$promoted) == 2L)
  bound_id <- as.character(promoted$promoted$artifact_id[promoted$promoted$output == "result"][[1L]])
  info <- wb_art_graph_info(bundle, bound_id)
  stopifnot(info$source_authority$status == "verified", info$component_counts$bindings == "1",
    identical(info$descriptor_identity, before))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle); bundle <- NULL
  report <- wb_bundle_validation_report(root, level = "recipient")
  if (!isTRUE(report$ok)) print(report$diagnostics)
  stopifnot(isTRUE(report$ok), identical(report$pre_validation_fingerprint, report$post_validation_fingerprint))
  cat("GRAPH_ABI4_LIVE_PYTHON matrix_to_graph=PASS graph_broker_to_table=PASS",
    "retained_cv_bound_graph_table=PASS full_closure=PASS source_authority=verified",
    "recipient=PASS fingerprint_unchanged=TRUE\n")
  TRUE
}
