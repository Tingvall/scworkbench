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

test_operation_pack_v3_model_linked_space_output_policy_contract <- function() {
  make_identity <- function(scheme, value = scheme)
    .wb_operation_pack_v2_identity_plain(scheme, value)
  policy <- list(output = "space",
    policy = "authenticated_model_linked_space_v1",
    model_read = "fitted_model", query_typed_slice_read = "query_chunks",
    row_order = "query_typed_slice_cell_axis_v1",
    dimension_source =
      "authenticated_model_linkage_latent_dimension_count_v1")
  make_request <- function(width) {
    linkage <- list(schema =
        "scworkbench.operation_pack.matrix_model_source_linkage.v1",
      engine = "generic", model_type = "retained_projection",
      source_matrix_id = "reference", source_matrix_content_identity =
        make_identity("test.matrix.content", "reference"),
      source_matrix_descriptor_identity = make_identity(
        "scworkbench.operation_pack.input_descriptor.v2", "source"),
      feature_order_identity = make_identity("scworkbench.feature_order.v1",
        c("f1", "f2")),
      fitted_cell_order_identity = make_identity("scworkbench.cell_order.v1",
        c("r1", "r2")), paired_fitted_space_id = "reference_space",
      latent_dimension_count = as.integer(width),
      source_matrix_snapshot_id = strrep("1", 64L),
      transition_source_state_identity = make_identity(
        "scworkbench.scientific_state.v1", "state"))
    linkage$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
      linkage$schema, "linkage excluding linkage_identity", linkage)
    model_descriptor <- make_identity(
      "scworkbench.operation_pack.input_descriptor.v2", "model")
    query_descriptor <- make_identity(
      "scworkbench.operation_pack.input_descriptor.v2", "query")
    model <- list(name = "fitted_model", input_name = "model",
      input_descriptor_identity = model_descriptor,
      model_content_identity = make_identity("scworkbench.model_ref.content.v1",
        "model"), model_source_linkage = linkage,
      model_source_linkage_identity =
        .wb_operation_pack_v3_unscoped_identity(linkage$linkage_identity),
      grant_identity = make_identity(
        "scworkbench.operation_pack.self_linked_contained_model_read_grant.v1",
        paste0("model-", width)))
    query <- list(name = "query_chunks", input_name = "query_matrix",
      input_descriptor_identity = query_descriptor,
      input_content_identity = make_identity("scworkbench.matrix.content.v1",
        "query"), cells_axis = list(count = 3L,
          order_identity = make_identity("scworkbench.cell_order.v1",
            c("q2", "q1", "q3"))),
      grant_identity = make_identity(
        "scworkbench.operation_pack.typed_slice_grant.v1", "query-grant"))
    publication <- list(publication_grant_identity = make_identity(
      "scworkbench.operation_pack.materialization_publication_grant.v1",
      "publication"))
    binding <- .wb_operation_pack_v3_model_linked_space_binding(policy,
      list(query), list(model), publication)
    descriptor <- c(list(publication_grant = publication), binding)
    list(operation = list(dimension_policies = list(policy)),
      request = list(outputs = list(list(name = "space",
        descriptor = descriptor)), typed_slice_grants = list(query),
        self_linked_model_payload_grants = list(model)),
      binding = binding)
  }
  for (width in c(2L, 10L, 20L)) {
    case <- make_request(width)
    stopifnot(identical(case$binding$expected_dimensions,
        list(3L, width)), identical(case$binding$expected_cell_order_identity,
        case$request$typed_slice_grants[[1L]]$cells_axis$order_identity))
    .wb_operation_pack_v3_model_linked_space_request_audit(case$request,
      case$operation)
  }
  attacks <- list(
    wrong_width = function(x) {
      x$request$outputs[[1L]]$descriptor$expected_dimensions[[2L]] <- 7L; x
    },
    wrong_cell_order = function(x) {
      x$request$outputs[[1L]]$descriptor$expected_cell_order_identity$sha256 <-
        strrep("0", 64L); x
    },
    wrong_model_linkage = function(x) {
      x$request$outputs[[1L]]$descriptor$expected_model_linkage$
        reference_identity$sha256 <- strrep("0", 64L); x
    },
    tampered_query_grant = function(x) {
      x$request$typed_slice_grants[[1L]]$grant_identity$sha256 <-
        strrep("0", 64L); x
    },
    tampered_publication = function(x) {
      x$request$outputs[[1L]]$descriptor$publication_grant$
        publication_grant_identity$sha256 <- strrep("0", 64L); x
    })
  for (attack_name in names(attacks)) {
    attack <- attacks[[attack_name]]
    case <- attack(make_request(10L))
    expected <- .wb_operation_pack_v3_model_linked_space_binding(
      case$operation$dimension_policies[[1L]],
      case$request$typed_slice_grants,
      case$request$self_linked_model_payload_grants,
      case$request$outputs[[1L]]$descriptor$publication_grant)
    if (identical(attack_name, "wrong_width")) stopifnot(!identical(
      case$request$outputs[[1L]]$descriptor$expected_dimensions,
      expected$expected_dimensions))
    rejected <- tryCatch(
      .wb_operation_pack_v3_model_linked_space_request_audit(case$request,
        case$operation), error = identity)
    if (!inherits(rejected, "error")) stop(
      "Model-linked policy accepted attack: ", attack_name)
  }
  case <- make_request(10L)
  wrong_order_space <- structure(list(kind = "space", space_id = "query",
    values = matrix(0, nrow = 3L, ncol = 10L),
    cell_id = c("q1", "q2", "q3"), dimensions = c(3L, 10L)),
    class = "wb_primitive")
  rejected <- tryCatch(.wb_operation_pack_v2_observed_descriptor(
    list(name = "space", descriptor = c(list(kind = "space"),
      case$binding)), list(value = wrong_order_space)), error = identity)
  if (!inherits(rejected, "error"))
    stop("Model-linked space accepted an output with reordered query cells.")
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
    "artifact_models", "operation_pack_v2"))
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
