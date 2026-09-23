.wb_g1_dispatch_install <- function() {
  library <- tempfile("scwb-g1-dispatch-lib-")
  dir.create(library)
  log <- tempfile("scwb-g1-dispatch-install-", fileext = ".log")
  source <- file.path(normalizePath(".", mustWork = TRUE), "tests",
    "fixtures", "operation-pack-v3-phase5")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = "\n"), call. = FALSE)
  old <- .libPaths()
  .libPaths(c(library, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Phase5", lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  list(library = library, old = old)
}

.wb_g1_dispatch_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_g1_dispatch_bundle <- function(root) {
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c4", "c3")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(12L), nrow = 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  wb_cell_set_replace(bundle, "set:session", c("c2", "c4", "c3"),
    source = "g1-dispatch-contract")
  bundle
}

.wb_g1_dispatch_consume <- function(session, bundle, model) {
  wb_session_run_op(session, bundle,
    "scwbv3phase5::consume_self_linked_model", inputs = list(
      model = model, cell_set = "all", min_cells = 1L))
}

.wb_g1_dispatch_state <- function(bundle) {
  list(artifacts = wb_art_list(bundle), fingerprint =
    .wb_session_source_identity(bundle)$scientific_state_fingerprint,
    records = sort(list.files(.wb_operation_pack_v2_store(bundle),
      all.files = TRUE, no.. = TRUE)))
}

.wb_g1_dispatch_reader_axis <- function(bundle, model, expected) {
  definition <- .wb_operation_pack_registry$operations[[
    "scwbv3phase5::consume_self_linked_model"]]$definition$v3_definition
  descriptor <- .wb_operation_pack_v2_input_descriptor("model", model,
    definition$inputs[[1L]])$descriptor
  stage_root <- tempfile("scwb-g1-reader-axis-")
  dir.create(stage_root)
  on.exit(unlink(stage_root, recursive = TRUE, force = TRUE), add = TRUE)
  prepared <- .wb_operation_pack_v3_prepare_self_linked_model_reads(bundle,
    definition, list(model = model), list(model = descriptor), stage_root)
  request <- list(outputs = list(), model_payload_grants = list(),
    self_linked_model_payload_grants = unname(prepared$grants))
  attr(request, "operation_pack_v3_self_linked_model_read_values") <-
    prepared$values
  state <- new.env(parent = emptyenv())
  state$used <- FALSE
  state$model_payload_calls <- list()
  adapted <- .wb_operation_pack_v3_model_adapters(list(state = state,
    readers = list(), writers = list()), request, definition, stage_root)
  payload <- adapted$readers$fitted_model()
  stopifnot(identical(as.character(payload$primary_path),
    as.character(prepared$grants[[1L]]$tree_manifest$primary_path)),
    identical(state$model_payload_calls$fitted_model, 1L))
  if (identical(as.character(model$model_source_linkage$schema %||% "")[1],
      "scworkbench.operation_pack.model_source_linkage.v3")) {
    stopifnot(identical(rownames(payload$fitted_source_space), expected),
      identical(colnames(payload$fitted_source_space),
        c("PC1", if (length(expected) == 2L) "PC3" else "PC2")))
  } else {
    # A v2 read binds its full cell order through the linkage and has no
    # separately derived fitted-space projection at the reader boundary.
    stopifnot(is.null(payload$fitted_source_space),
      identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(expected))),
        model$model_source_linkage$fitted_cell_order_identity))
  }
  invisible(TRUE)
}

test_operation_pack_v3_g1_model_reference_dispatch_lifecycle_contract <-
    function() {
  fixture <- .wb_g1_dispatch_install()
  root <- tempfile("scwb-g1-dispatch-")
  bundle <- .wb_g1_dispatch_bundle(root)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    .wb_g1_dispatch_cleanup(fixture)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cases <- list(
    v2 = list(operation = "fit_sibling_model", inputs = list(
      source = "pca", dims = c(1L, 2L), cell_set = "all",
      min_cells = 1L), expected = c("c2", "c1", "c4", "c3"),
      outputs = c("embedding", "model")),
    v3 = list(operation = "fit_derived_axis_model", inputs = list(
      source = "pca", dims = c(1L, 3L), fitted_cells = c("c2", "c3"),
      cell_set = "set:session", min_cells = 1L),
      expected = c("c2", "c3"),
      outputs = c("embedding", "model", "weights")))
  model_ids <- character()
  sibling_grant <- NULL
  derived_linkage <- NULL
  for (version in names(cases)) {
    case <- cases[[version]]
    fit <- wb_session_run_op(wb_session_new(), bundle,
      paste0("scwbv3phase5::", case$operation), inputs = case$inputs)
    model <- fit$run$outputs$model
    stopifnot(identical(as.character(model$model_source_linkage$
      fitted_cell_order_identity$sha256), .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(case$expected)))$sha256))
    .wb_g1_dispatch_reader_axis(fit$session$staging_bundle, model,
      case$expected)
    staged <- .wb_g1_dispatch_consume(fit$session, bundle,
      wb_ref_run(fit$run$run_id, "model"))
    request_path <- file.path(.wb_operation_pack_v2_store(
      staged$session$staging_bundle), staged$run$operation_pack_transition$
      transition_id, "request.json")
    request <- jsonlite::read_json(request_path, simplifyVector = FALSE)
    if (identical(version, "v2")) {
      fit_request <- jsonlite::read_json(file.path(
        .wb_operation_pack_v2_store(fit$session$staging_bundle),
        fit$run$operation_pack_transition$transition_id, "request.json"),
        simplifyVector = FALSE)
      sibling_grant <- fit_request$outputs[[match("model", vapply(
        fit_request$outputs, `[[`, character(1), "name"))]]$descriptor$
        contained_model_sibling_write_grant
    } else derived_linkage <- model$model_source_linkage
    stopifnot(identical(request$self_linked_model_payload_grants[[1L]]$
      model_source_linkage$fitted_cell_order_identity,
      model$model_source_linkage$fitted_cell_order_identity),
      isTRUE(.wb_operation_pack_v3_schema_assert(request, "request",
        "PYBENCH_CAPABILITY_MISMATCH")))
    promoted <- wb_session_promote_current(bundle, fit$session,
      outputs = case$outputs, created_by = "g1-dispatch-contract")
    stopifnot(all(promoted$promoted$status == "ok"))
    model_id <- as.character(promoted$promoted$artifact_id[
      promoted$promoted$output == "model"][[1L]])
    model_ids[[version]] <- model_id
    .wb_g1_dispatch_reader_axis(bundle,
      wb_art_load(bundle, model_id, expected_kind = "model_ref"),
      case$expected)
    durable <- .wb_g1_dispatch_consume(wb_session_new(), bundle,
      wb_ref_artifact(model_id, "model"))
    stopifnot(identical(durable$run$outputs$summary$kind, "obs_table"))
  }
  request_schema <- jsonlite::read_json(file.path("inst", "protocol",
    "operation-pack-transition-request-v3.schema.json"),
    simplifyVector = FALSE)
  stopifnot(isTRUE(.wb_json_schema_validate_2020(sibling_grant,
    request_schema$`$defs`$contained_model_sibling_write_grant,
    request_schema)$ok))
  sibling_grant$model_source_linkage <- derived_linkage
  sibling_grant$write_grant_identity <- NULL
  sibling_grant$write_grant_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.contained_model_sibling_write_grant.v1",
      "grant excluding write_grant_identity", sibling_grant)
  stopifnot(isTRUE(.wb_json_schema_validate_2020(sibling_grant,
    request_schema$`$defs`$contained_model_sibling_write_grant,
    request_schema)$ok))
  substituted <- sibling_grant
  substituted$model_source_linkage$selected_axis_evidence <- NULL
  stopifnot(!isTRUE(.wb_json_schema_validate_2020(substituted,
    request_schema$`$defs`$contained_model_sibling_write_grant,
    request_schema)$ok))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- tempfile("scwb-g1-dispatch-relocated-")
  fs::dir_copy(root, relocated)
  on.exit(unlink(relocated, recursive = TRUE, force = TRUE), add = TRUE)
  bundle <- wb_open_bundle(relocated, read_only = TRUE)
  for (version in names(cases)) {
    model <- wb_art_load(bundle, model_ids[[version]],
      expected_kind = "model_ref")
    stopifnot(dir.exists(model$model_tree_root),
      identical(model$model_tree_manifest$primary_path,
        model$model_primary_path))
    .wb_g1_dispatch_reader_axis(bundle, model,
      cases[[version]]$expected)
    if (identical(version, "v3")) stopifnot(identical(
      rownames(.wb_operation_pack_v3_dfa_reopen(bundle, model,
        model$model_source_linkage, model$model_tree_root)),
      cases[[version]]$expected))
  }
  stopifnot(isTRUE(wb_bundle_validation_report(relocated,
    level = "recipient")$ok))
  wb_close_bundle(bundle); bundle <- NULL
  for (attack in c("linkage", "tree", "sidecar")) {
    target <- tempfile(paste0("scwb-g1-", attack, "-"))
    fs::dir_copy(relocated, target)
    on.exit(unlink(target, recursive = TRUE, force = TRUE), add = TRUE)
    bundle <- wb_open_bundle(target, validate = FALSE)
    row <- DBI::dbGetQuery(bundle$con, paste0(
      "SELECT model_path, linkage_json FROM artifact_model_ref ",
      "WHERE artifact_id=?;"), params = list(model_ids[["v3"]]))
    model_root <- file.path(target, row$model_path[[1L]])
    if (identical(attack, "linkage")) {
      linkage <- jsonlite::fromJSON(row$linkage_json[[1L]],
        simplifyVector = FALSE)
      linkage$selected_axis_evidence$sha256 <-
        paste(rep("0", 64L), collapse = "")
      linkage$linkage_identity <- NULL
      linkage$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.model_source_linkage.v3",
        "linkage excluding linkage_identity", linkage)
      DBI::dbExecute(bundle$con, paste0(
        "UPDATE artifact_model_ref SET linkage_json=? ",
        "WHERE artifact_id=?;"), params = list(as.character(
          jsonlite::toJSON(linkage, auto_unbox = TRUE, null = "null",
            digits = NA)), model_ids[["v3"]]))
    } else if (identical(attack, "tree")) {
      primary <- file.path(model_root, "model.bin")
      Sys.chmod(primary, "0644")
      writeBin(charToRaw("changed-tree"), primary)
    } else {
      sidecar <- file.path(model_root, ".scworkbench",
        "selected-axis-v1.json")
      Sys.chmod(sidecar, "0644")
      writeBin(charToRaw("changed-sidecar"), sidecar)
    }
    before <- .wb_g1_dispatch_state(bundle)
    failure <- tryCatch(.wb_g1_dispatch_consume(wb_session_new(),
      bundle, wb_ref_artifact(model_ids[["v3"]], "model")),
      error = identity)
    stopifnot(inherits(failure, "error"),
      identical(before, .wb_g1_dispatch_state(bundle)))
    wb_close_bundle(bundle); bundle <- NULL
  }
  TRUE
}

test_operation_pack_v3_g1_verified_primary_deserialization_contract <-
    function() {
  root <- tempfile("scwb-g1-primary-")
  bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  stage <- NULL
  on.exit({
    if (!is.null(stage)) try(wb_session_discard(stage$session), silent = TRUE)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c2", "c1", "c3")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(6L), nrow = 3L,
    dimnames = list(cells, c("PC1", "PC2"))))
  stage <- .wb_session_stage_bundle(bundle, wb_session_new())
  identities <- list()
  for (engine in c("slingshot", "monocle3")) {
    tree_root <- file.path(stage$bundle$dir, "operation_pack_v2",
      paste0("primary_", engine))
    dir.create(tree_root, recursive = TRUE, showWarnings = FALSE)
    object <- list(engine = engine, fitted_cells = cells,
      fitted_dimensions = c("PC1", "PC2"))
    saveRDS(object, file.path(tree_root, "model.rds"), version = 3L)
    writeBin(charToRaw("secondary"), file.path(tree_root, "support.bin"))
    tree <- .wb_operation_pack_v3_model_tree_manifest(tree_root,
      engine, engine, "model.rds")
    model <- wb_prim_model_ref(paste0(engine, ".model"), "pca",
      engine = engine)
    model$model_type <- engine
    model$model_path <- tree_root
    model$model_tree_root <- tree_root
    model$model_primary_path <- tree$primary_path
    model$model_tree_manifest <- tree
    model$model_payload_manifest_identity <-
      .wb_operation_pack_v3_model_payload_identity(tree)
    model$model_linkage <- .wb_operation_pack_v3_model_linkage(engine,
      engine, "pca", .wb_operation_pack_v3_selected_dimensions(
        structure(list(kind = "space", space_id = "pca", values =
          wb_space(bundle, "pca")), class = "wb_primitive"),
        list(dims = 1:2), "dims"))
    run <- wb_new_run("monocle3_fit", inputs = list(cell_set = "all",
      parents = character(), user_inputs = list()),
      outputs = list(model = model))
    promoted <- wb_promote_analysis(bundle, setNames(list(run),
      run$run_id), run$run_id, outputs = "model",
      staging_bundle = stage$bundle)
    id <- as.character(promoted$promoted$artifact_id[[1L]])
    loaded <- wb_art_load(bundle, id, expected_kind = "model_ref")
    stopifnot(identical(loaded$model_obj, object),
      dir.exists(loaded$model_path),
      identical(loaded$model_tree_manifest, tree),
      identical(loaded$model_primary_path, "model.rds"))
    identities[[engine]] <- id
  }
  stage$session <- wb_session_discard(stage$session)
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- file.path(root, "relocated.bundle")
  fs::dir_copy(file.path(root, "source.bundle"), relocated)
  bundle <- wb_open_bundle(relocated, read_only = TRUE)
  for (engine in names(identities)) {
    loaded <- wb_art_load(bundle, identities[[engine]],
      expected_kind = "model_ref")
    stopifnot(identical(loaded$model_obj$engine, engine),
      identical(loaded$model_obj$fitted_cells, cells),
      startsWith(loaded$model_tree_root, relocated))
  }
  wb_close_bundle(bundle); bundle <- NULL
  source_path <- relocated
  for (attack in c("changed", "missing", "symlink", "escaping_primary")) {
    target <- file.path(root, paste0("attack_", attack, ".bundle"))
    fs::dir_copy(source_path, target)
    candidate <- wb_open_bundle(target, validate = FALSE)
    row <- DBI::dbGetQuery(candidate$con, paste0(
      "SELECT model_path, model_primary_path FROM artifact_model_ref ",
      "WHERE artifact_id=?;"), params = list(identities$slingshot))
    primary <- file.path(target, row$model_path[[1L]],
      row$model_primary_path[[1L]])
    if (identical(attack, "changed")) {
      Sys.chmod(primary, "0644")
      writeBin(charToRaw("changed"), primary)
    } else if (identical(attack, "missing")) {
      unlink(primary)
    } else if (identical(attack, "symlink")) {
      unlink(primary)
      stopifnot(file.symlink(file.path(target, "manifest.json"), primary))
    } else {
      DBI::dbExecute(candidate$con, paste0(
        "UPDATE artifact_model_ref SET model_primary_path=? ",
        "WHERE artifact_id=?;"), params = list("../escape.rds",
          identities$slingshot))
    }
    before <- .wb_g1_dispatch_state(candidate)
    failure <- tryCatch(wb_art_load(candidate, identities$slingshot,
      expected_kind = "model_ref"), error = identity)
    stopifnot(inherits(failure, "error"),
      identical(before, .wb_g1_dispatch_state(candidate)))
    wb_close_bundle(candidate)
  }
  TRUE
}
test_operation_pack_v3_g1_deserialized_model_view_is_not_input_authority_contract <- function() {
  model <- wb_prim_model_ref("fit", "fit", engine = "slingshot")
  model$model_type <- "slingshot"
  model$model_tree_manifest <- list(primary_path = "model.rds")
  declaration <- list(kind = "model_ref", alignment = "model_linked")
  expected <- .wb_operation_pack_v2_input_descriptor("model", model,
    declaration)
  model$model_obj <- new.env(parent = emptyenv())
  observed <- .wb_operation_pack_v2_input_descriptor("model", model,
    declaration)
  stopifnot(identical(expected, observed))
  TRUE
}
