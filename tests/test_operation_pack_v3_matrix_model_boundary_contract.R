.wb_phase6_matrix_fixture <- function() {
  library <- tempfile("scwb-phase6-lib-")
  dir.create(library)
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v3-matrix-model")
  log <- tempfile("scwb-phase6-install-", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = "\n"), call. = FALSE)
  old <- .libPaths(); .libPaths(c(library, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3MatrixModel", lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  root <- tempfile("scwb-phase6-bundle-")
  bundle <- wb_init_bundle(root)
  cells <- c("c3", "c1", "c4", "c2")
  features <- c("f3", "f1", "f2")
  wb_define_cells(bundle, cells)
  values <- matrix(seq_len(length(cells) * length(features)),
    nrow = length(features), dimnames = list(features, cells))
  wb_attach_matrix(bundle, "ATAC", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "peak")
  list(library = library, old = old, root = root, bundle = bundle,
    cells = cells, features = features, values = values)
}

test_operation_pack_v3_matrix_model_protocol_fixture_contract <- function() {
  fixture <- jsonlite::read_json(file.path("inst", "protocol", "fixtures",
    "operation-pack-v3", "phase6-matrix-model-identities.json"),
    simplifyVector = FALSE)
  fields <- list(
    model_source_linkage = "linkage_identity",
    contained_matrix_model_sibling_write_grant = "write_grant_identity",
    matrix_model_sibling_closure_observation = "observation_identity")
  for (name in names(fields)) {
    value <- fixture[[name]]
    field <- fields[[name]]
    .wb_operation_pack_v3_assert_self_identity(value, field,
      "PYBENCH_INPUT_IDENTITY_MISMATCH", "fixture")
  }
  TRUE
}

.wb_phase6_matrix_cleanup <- function(state) {
  try(wb_close_bundle(state$bundle), silent = TRUE)
  try(wb_operation_pack_unload("scwbv3matrixmodel"), silent = TRUE)
  if ("scwbV3MatrixModel" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3MatrixModel"), silent = TRUE)
  .libPaths(state$old)
  unlink(state$library, recursive = TRUE, force = TRUE)
  unlink(state$root, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

test_operation_pack_v3_matrix_model_boundary_lifecycle_contract <- function() {
  state <- .wb_phase6_matrix_fixture()
  on.exit(.wb_phase6_matrix_cleanup(state), add = TRUE)
  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3matrixmodel::fit_matrix_model", inputs = list(matrix = "ATAC",
      n_latent = 2L, chunk_size = 2L, cell_set = "all", min_cells = 1L))
  stopifnot(identical(sort(names(fit$run$outputs)),
    c("model", "space", "summary")))
  transition <- fit$run$operation_pack_transition
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    fit$session$staging_bundle), transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  model_receipt <- receipt$outputs[[match("model", vapply(receipt$outputs,
    `[[`, character(1), "name"))]]$descriptor
  stopifnot(!is.null(model_receipt$contained_matrix_model_sibling_tree),
    length(model_receipt$contained_matrix_model_sibling_tree$
      ordered_sibling_observed_descriptor_identities) == 2L)
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("model", "summary"), created_by = "phase6-contract")
  stopifnot(all(promoted$promoted$status == "ok"),
    fit$run$outputs$space$space_id %in% wb_spaces(state$bundle)$space_id)
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  loaded <- wb_art_load(state$bundle, model_id, expected_kind = "model_ref")
  stopifnot(identical(loaded$model_linkage$source_matrix_id, "ATAC"),
    identical(ncol(.wb_as_coord_matrix(wb_space(state$bundle,
      loaded$model_space_id))), 2L))
  fit$session <- wb_session_discard(fit$session)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  relocated <- tempfile("scwb-phase6-relocated-")
  on.exit(unlink(relocated, recursive = TRUE, force = TRUE), add = TRUE)
  wb_close_bundle(state$bundle); state$bundle <- NULL
  fs::dir_copy(state$root, relocated)
  state$bundle <- wb_open_bundle(relocated, read_only = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(relocated,
    level = "recipient")$ok))
  reopened <- wb_art_load(state$bundle, model_id,
    expected_kind = "model_ref")
  stopifnot(identical(reopened$model_linkage,
    loaded$model_linkage))
  wb_close_bundle(state$bundle)
  state$bundle <- wb_open_bundle(relocated)
  read <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3matrixmodel::read_matrix_model", inputs = list(
      model = wb_ref_artifact(model_id, "model"), cell_set = "all",
      min_cells = 1L))
  stopifnot(identical(read$run$outputs$summary$kind, "obs_table"))
  read$session <- wb_session_discard(read$session)
  TRUE
}

test_operation_pack_v3_matrix_model_boundary_rollback_contract <- function() {
  state <- .wb_phase6_matrix_fixture()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    .wb_phase6_matrix_cleanup(state)
  }, add = TRUE)
  baseline <- list(artifacts = nrow(wb_art_list(state$bundle)),
    spaces = wb_spaces(state$bundle)$space_id,
    transitions = sort(list.files(.wb_operation_pack_v2_store(state$bundle),
      all.files = TRUE, no.. = TRUE)))
  run <- function(attack = "none") wb_session_run_op(wb_session_new(),
    state$bundle, "scwbv3matrixmodel::fit_matrix_model",
    inputs = list(matrix = "ATAC", n_latent = 2L, chunk_size = 2L,
      attack = attack, cell_set = "all", min_cells = 1L))
  assert_source_only <- function() stopifnot(
    identical(nrow(wb_art_list(state$bundle)), baseline$artifacts),
    identical(wb_spaces(state$bundle)$space_id, baseline$spaces),
    identical(sort(list.files(.wb_operation_pack_v2_store(state$bundle),
      all.files = TRUE, no.. = TRUE)), baseline$transitions))
  for (attack in c("wrong_axis", "omit_space", "incomplete_tree")) {
    error <- tryCatch(run(attack), error = identity)
    stopifnot(inherits(error, "error"))
    assert_source_only()
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, "before_publication")) stop("phase6 publication fault"))
  error <- tryCatch(run(), error = identity)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(inherits(error, "error"))
  assert_source_only()
  retry <- run()
  stopifnot(identical(sort(names(retry$run$outputs)),
    c("model", "space", "summary")))
  retry$session <- wb_session_discard(retry$session)
  TRUE
}

test_operation_pack_v3_matrix_model_source_reopen_authentication_contract <-
    function() {
  state <- .wb_phase6_matrix_fixture()
  on.exit(.wb_phase6_matrix_cleanup(state), add = TRUE)
  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3matrixmodel::fit_matrix_model", inputs = list(matrix = "ATAC",
      n_latent = 2L, chunk_size = 2L, cell_set = "all", min_cells = 1L))
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("model", "summary"), created_by = "phase6-contract")
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  fit$session <- wb_session_discard(fit$session)
  definition <- .wb_operation_pack_registry$operations[[
    "scwbv3matrixmodel::read_matrix_model"]]$definition$v3_definition
  for (attack in c("matrix_bytes", "feature_axis")) {
    copy <- tempfile(paste0("scwb-phase6-", attack, "-"))
    fs::dir_copy(state$root, copy)
    on.exit(unlink(copy, recursive = TRUE, force = TRUE), add = TRUE)
    damaged <- wb_open_bundle(copy)
    model <- wb_art_load(damaged, model_id, expected_kind = "model_ref")
    descriptor <- .wb_operation_pack_v2_input_descriptor("model", model,
      definition$inputs[[1L]])$descriptor
    if (identical(attack, "matrix_bytes")) {
      target <- list.files(file.path(copy, "mat"), pattern = "^val$",
        recursive = TRUE, full.names = TRUE)[[1L]]
      connection <- file(target, open = "ab")
      writeBin(as.raw(1L), connection); close(connection)
    } else {
      DBI::dbExecute(damaged$con, paste0("UPDATE features SET feature_id=",
        "'mutated_f1' WHERE matrix_id='ATAC' AND feature_id='f1';"))
    }
    stage <- tempfile("scwb-phase6-source-read-"); dir.create(stage)
    error <- tryCatch(.wb_operation_pack_v3_prepare_self_linked_model_reads(
      damaged, definition, list(model = model), list(model = descriptor),
      stage), error = identity)
    stopifnot(inherits(error, "error"))
    unlink(stage, recursive = TRUE, force = TRUE)
    wb_close_bundle(damaged)
  }
  TRUE
}
