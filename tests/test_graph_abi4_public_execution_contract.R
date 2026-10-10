test_graph_abi4_public_r_execution_contract <- function() {
  lib <- tempfile("graph_public_lib_"); dir.create(lib)
  source <- file.path(normalizePath("."), "tests", "fixtures", "operation-pack-v4-graph")
  log <- tempfile("graph_fixture_install_")
  old <- .libPaths(); root <- tempfile("graph_public_bundle_")
  bundle <- NULL
  on.exit({
    try(wb_operation_pack_unload("scwbgraphfixture"), silent = TRUE)
    registry <- scworkbench:::.wb_operation_pack_registry
    pack <- registry$packs$scwbgraphfixture
    for (name in pack$operation_names %||% character()) registry$operations[[name]] <- NULL
    registry$packs$scwbgraphfixture <- NULL
    if ("scwbGraphFixture" %in% loadedNamespaces()) try(unloadNamespace("scwbGraphFixture"), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    for (result in list(run, next_run, bound)) try(wb_session_discard(result$session), silent = TRUE)
    .libPaths(old); unlink(c(lib, root), recursive = TRUE)
  }, add = TRUE)
  run <- next_run <- bound <- NULL
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(source)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, old))
  activated <- wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
    package = "scwbGraphFixture", lib.loc = lib), lib.loc = lib)
  stopifnot(activated$identity$pack_abi_version == "4")
  bundle <- wb_init_bundle(root)
  wb_define_cells(bundle, c("c2", "c1"))
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(c(1, 2, 3, 4), 2L,
    dimnames = list(c("g2", "g1"), c("c2", "c1"))), sparse = TRUE))
  run <- wb_session_run_op(wb_session_new(), bundle, "scwbgraphfixture::matrix_to_graph",
    inputs = list(matrix = "RNA", cell_set = "all", min_cells = 1L))
  stopifnot(run$run$outputs$result$kind == "graph")
  promoted <- wb_session_promote_current(bundle, run$session, outputs = "result")
  id <- as.character(promoted$promoted$artifact_id[[1L]])
  graph <- wb_art_load(bundle, id)
  nodes <- wb_art_graph_slice(bundle, id, "nodes")
  stopifnot(identical(vapply(nodes, `[[`, character(1), "node_id"), c("c2", "c1")))
  next_run <- wb_session_run_op(wb_session_new(), bundle, "scwbgraphfixture::graph_to_table",
    inputs = list(source = wb_ref_artifact(id, "result")))
  stopifnot(next_run$run$outputs$summary$table$value == 2L)
  promotion <- wb_session_promote_current(bundle, next_run$session, outputs = "summary")
  stopifnot(nrow(promotion$promoted) == 1L)
  vector <- wb_prim_cell_vector(stats::setNames(c("B", "A"), c("c2", "c1")))
  metadata_run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(),
    outputs = list(vector = vector))
  metadata_promotion <- wb_promote_analysis(bundle, stats::setNames(list(metadata_run), metadata_run$run_id),
    metadata_run$run_id, outputs = "vector")
  metadata_id <- as.character(metadata_promotion$promoted$artifact_id[[1L]])
  bound <- wb_session_run_op(wb_session_new(), bundle, "scwbgraphfixture::graph_and_cell_metadata",
    inputs = list(source = wb_ref_artifact(id, "result"), metadata = wb_ref_artifact(metadata_id, "vector"),
      min_cells = 1L))
  counts <- function() vapply(c("artifacts", "artifact_graph_meta", "artifact_graph_rows",
    "prov_commits", "prov_runs", "prov_run_outputs", "prov_run_entity_bindings"), function(table)
      as.numeric(DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) n FROM ", table))$n[[1L]]), numeric(1))
  before <- counts()
  before_payloads <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  for (boundary in c("graph_component_rows", "after_first_private_terminal_write",
      "after_payload_move_before_database_commit")) {
    old_hook <- options(scworkbench.promotion_transaction_test_hook = local({
      selected <- boundary
      function(event, ...) if (event == selected) stop(paste0("graph-public-promotion-fault-", selected))
    }))
    on.exit(options(old_hook), add = TRUE)
    failed <- tryCatch(wb_session_promote_current(bundle, bound$session, outputs = "result"), error = identity)
    options(old_hook)
    stopifnot(inherits(failed, "error"),
      grepl(paste0("graph-public-promotion-fault-", boundary), conditionMessage(failed), fixed = TRUE),
      identical(counts(), before),
      identical(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE), before_payloads))
  }
  promoted_bound <- wb_session_promote_current(bundle, bound$session, outputs = "result")
  stopifnot(nrow(promoted_bound$promoted) == 2L)
  bound_id <- as.character(promoted_bound$promoted$artifact_id[promoted_bound$promoted$output == "result"][[1L]])
  info <- wb_art_graph_info(bundle, bound_id)
  stopifnot(info$source_authority$status == "verified", info$component_counts$bindings == "1")
  # Failure before and after private-directory rename must not publish any
  # analytical claims or payloads into the source destination. Retry is above.
  baseline <- counts()
  payloads <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  for (boundary in c("before_dispatch", "receipt_received", "audited", "before_publication", "published", "reopened")) {
    scratch_before <- list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)
    hook <- options(scworkbench.operation_pack_v2_test_hook = local({
      selected <- boundary
      function(event, ...) if (event == selected) stop(paste0("graph-execution-fault-", selected))
    }))
    on.exit(options(hook), add = TRUE)
    failed <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
      "scwbgraphfixture::graph_and_cell_metadata", inputs = list(source = wb_ref_artifact(id, "result"),
        metadata = wb_ref_artifact(metadata_id, "vector"), min_cells = 1L)), error = identity)
    options(hook)
    stopifnot(inherits(failed, "error"),
      grepl(paste0("graph-execution-fault-", boundary), conditionMessage(failed), fixed = TRUE),
      identical(counts(), baseline),
      identical(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE), payloads),
      identical(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE), scratch_before))
  }
  stage_paths <- character()
  staging_root <- bound$session$staging_bundle$dir
  transitions_before <- list.files(file.path(staging_root, "operation_pack_v2"))
  hook <- options(
    scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "connected") stage_paths <<- c(stage_paths, state$path)
    }, scworkbench.operation_pack_v2_test_hook = function(event, transition_id = NULL, ...) {
      if (event == "reopened") writeBin(charToRaw("not-an-RDS"), file.path(
        staging_root, "operation_pack_v2", transition_id, "outputs", "summary", "payload.rds"))
    })
  on.exit(options(hook), add = TRUE)
  failed <- tryCatch(wb_session_run_op(bound$session, bundle,
    "scwbgraphfixture::graph_and_cell_metadata", inputs = list(source = wb_ref_artifact(id, "result"),
      metadata = wb_ref_artifact(metadata_id, "vector"), min_cells = 1L)), error = identity)
  options(hook)
  stopifnot(inherits(failed, "error"), length(stage_paths) > 0L, !any(file.exists(stage_paths)),
    identical(list.files(file.path(staging_root, "operation_pack_v2")), transitions_before),
    identical(counts(), baseline))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  descriptor <- info$descriptor_identity$sha256
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- tempfile("graph_public_relocated_")
  on.exit(unlink(relocated, recursive = TRUE), add = TRUE)
  fs::dir_copy(root, relocated)
  recipient_log <- tempfile("graph_recipient_process_")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(
    shQuote(file.path(normalizePath("."), "tests", "fixtures", "graph_recipient_process.R")),
    shQuote(normalizePath(".")), shQuote(relocated), shQuote(bound_id), shQuote(descriptor)),
    stdout = recipient_log, stderr = recipient_log)
  cat(paste(readLines(recipient_log, warn = FALSE), collapse = "\n"), "\n")
  stopifnot(status == 0L)
  TRUE
}
