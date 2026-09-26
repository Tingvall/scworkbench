.wb_phase6_matrix_fixture <- function() {
  library <- getOption("scworkbench.phase6.matrix_fixture_library", NULL)
  if (is.null(library) || !dir.exists(library)) {
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
    options(scworkbench.phase6.matrix_fixture_library = library)
  }
  old <- .libPaths(); .libPaths(c(library, old))
  if (is.null(.wb_operation_pack_registry$packs[["scwbv3matrixmodel"]])) {
    manifest <- system.file("scworkbench", "operation-pack.json",
      package = "scwbV3MatrixModel", lib.loc = library)
    wb_operation_pack_activate(manifest, lib.loc = library)
  }
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
  # Executed packs are intentionally not unloadable within one process.
  # Keep this disposable package available for subsequent focused tests.
  .libPaths(state$old)
  unlink(state$root, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_phase6_source_only_state <- function(bundle) {
  tables <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT name FROM sqlite_master WHERE type='table' ",
    "AND name NOT LIKE 'sqlite_%' ORDER BY name;"))$name
  counts <- stats::setNames(vapply(tables, function(table)
    as.integer(DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) AS n FROM ",
      DBI::dbQuoteIdentifier(bundle$con, table)))$n[[1L]]), integer(1)),
    tables)
  roots <- file.path(bundle$dir, c("space_payloads", "artifacts",
    "operation_pack_v2"))
  entries <- unlist(lapply(roots, function(root) if (dir.exists(root))
    list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
      no.. = TRUE, include.dirs = TRUE) else character()), use.names = FALSE)
  entries <- sort(entries[file.exists(entries)], method = "radix")
  files <- entries[!dir.exists(entries)]
  list(fingerprint = .wb_manifest_registry_snapshot(bundle$con)$fingerprint,
    counts = counts, entries = substring(entries, nchar(bundle$dir) + 2L),
    file_hashes = stats::setNames(vapply(files,
      .wb_prov_sha256_file, character(1)), substring(files,
        nchar(bundle$dir) + 2L)))
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
  baseline <- .wb_phase6_source_only_state(state$bundle)
  run <- function(attack = "none") wb_session_run_op(wb_session_new(),
    state$bundle, "scwbv3matrixmodel::fit_matrix_model",
    inputs = list(matrix = "ATAC", n_latent = 2L, chunk_size = 2L,
      attack = attack, cell_set = "all", min_cells = 1L))
  assert_source_only <- function() stopifnot(identical(
    .wb_phase6_source_only_state(state$bundle), baseline))
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
  for (attack in c("matrix_bytes", "feature_axis", "fitted_space",
      "model_tree")) {
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
    } else if (identical(attack, "feature_axis")) {
      DBI::dbExecute(damaged$con, paste0("UPDATE features SET feature_id=",
        "'mutated_f1' WHERE matrix_id='ATAC' AND feature_id='f1';"))
    } else if (identical(attack, "fitted_space")) {
      registry <- .wb_space_payload_registry_row(damaged,
        model$model_space_id)
      target <- .wb_space_payload_path(damaged, registry)
      values <- rhdf5::h5read(target, "coordinates")
      values[1L, 1L] <- values[1L, 1L] + 1
      rhdf5::h5write(values, target, "coordinates")
      # Even a self-rehashed registry row cannot rewrite the earlier receipt.
      DBI::dbExecute(damaged$con, paste0(
        "UPDATE space_payloads SET content_sha256=? WHERE space_id=?;"),
        params = list(.wb_prov_sha256_file(target), model$model_space_id))
    } else {
      target <- file.path(model$model_tree_root,
        model$model_primary_path)
      Sys.chmod(target, mode = "0644")
      connection <- file(target, open = "ab")
      writeBin(as.raw(1L), connection); close(connection)
    }
    stage <- tempfile("scwb-phase6-source-read-"); dir.create(stage)
    error <- tryCatch(.wb_operation_pack_v3_prepare_self_linked_model_reads(
      damaged, definition, list(model = model), list(model = descriptor),
      stage), error = identity)
    stopifnot(inherits(error, "error"))
    unlink(stage, recursive = TRUE, force = TRUE)
    wb_close_bundle(damaged)
  }
  model <- wb_art_load(state$bundle, model_id, expected_kind = "model_ref")
  original <- .wb_as_coord_matrix(wb_space(state$bundle,
    model$model_space_id))
  changed <- original; changed[1L, 1L] <- changed[1L, 1L] + 1
  stopifnot(inherits(tryCatch(
    .wb_operation_pack_v3_matrix_model_fitted_space_recheck(state$bundle,
      model_id, model$model_linkage, changed), error = identity), "error"))
  forged <- model$model_linkage
  forged$paired_fitted_space_id <- "forged-space"
  forged_preimage <- forged
  forged_preimage$linkage_identity <- NULL
  forged$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    forged$schema, "linkage excluding linkage_identity",
    forged_preimage)
  stopifnot(inherits(tryCatch(
    .wb_operation_pack_v3_matrix_model_fitted_space_recheck(state$bundle,
      model_id, forged, original), error = identity), "error"))
  TRUE
}
