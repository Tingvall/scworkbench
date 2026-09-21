.wb_g7_effective_fixture_install <- function() {
  library <- tempfile("scwb-g7-effective-lib-"); dir.create(library,
    recursive = TRUE)
  log <- tempfile("scwb-g7-effective-install-", fileext = ".log")
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v3-phase5")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)), stdout = log,
    stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = "\n"), call. = FALSE)
  old <- .libPaths(); .libPaths(c(library, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Phase5", lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  list(library = library, old = old)
}

.wb_g7_effective_fixture_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_g7_effective_bundle <- function() {
  root <- tempfile("scwb-g7-effective-bundle-"); bundle <- wb_init_bundle(root)
  cells <- c("cell_2", "cell_10", "cell_1", "cell_3")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(12L), nrow = 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  list(root = root, bundle = bundle, cells = cells)
}

.wb_g7_effective_expect <- function(expr,
    code = "PYBENCH_OUTPUT_INVALID") {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"),
    identical(as.character(error$code), code))
  invisible(error)
}

.wb_g7_effective_transition_records <- function(run) {
  transition <- run$run$operation_pack_transition
  root <- file.path(.wb_operation_pack_v2_store(run$session$staging_bundle),
    transition$transition_id)
  list(request = jsonlite::read_json(file.path(root, "request.json"),
      simplifyVector = FALSE),
    receipt = jsonlite::read_json(file.path(root, "receipt.json"),
      simplifyVector = FALSE))
}

test_operation_pack_v3_g7_effective_key_protocol_fixture_contract <-
    function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)
  cases <- Filter(function(x) startsWith(x$name, "g7_effective_key_"),
    fixture$cases)
  expected <- c(
    g7_effective_key_primary =
      "41fc556b8956f70752b78ecdd2ec0fc6e16f5653fc631b9fe21a29b771602f1a",
    g7_effective_key_null_fallback =
      "c7e26a6987eaeba2131a574c6e8f3732886d71bbdd16a0e28d310b7974bd071d",
    g7_effective_key_schema_default =
      "3879604c3d7939422b4bfd83cb1f20449949b5aa60ce7c244e795fd4d97aeeae",
    g7_effective_key_override =
      "33672c5b3f08411bea4605b38e445165e4eb4ff9cbe5824d2719a415b915b6a4",
    g7_effective_key_same_no_presence =
      "3207954905f3d149e9a05f2c35587324efe4590871e1b0c57d37d5ac88deed0f",
    g7_effective_key_same_with_presence =
      "f939e5ed81f919558b602fa151cc6c215811d40f77dad739d9a568ab9bcf67d4")
  observed <- stats::setNames(vapply(cases, function(item) {
    stopifnot(identical(.wb_operation_pack_sha256(item$preimage),
      item$identity$sha256))
    item$identity$sha256
  }, character(1)), vapply(cases, `[[`, character(1), "name"))
  stopifnot(identical(unname(observed[names(expected)]), unname(expected)),
    length(fixture$g7_effective_key_positive_examples) == 6L,
    length(fixture$g7_effective_key_negative_examples) == 6L,
    !identical(observed[["g7_effective_key_same_no_presence"]],
      observed[["g7_effective_key_same_with_presence"]]))
  TRUE
}

test_operation_pack_v3_g7_effective_key_resolution_contract <- function() {
  spec <- list(source = "resolved_effective_parameter_key_v1",
    parameter_candidates = list("primary", "fallback"),
    null_policy = "first_non_null_v1", invalid_value_policy = "error",
    input_presence_override = list(present = "weights", absent = "confidence",
      use_parameter = "fallback"))
  resolve <- function(inputs = list(), primary = NULL, fallback = "L1")
    .wb_operation_pack_v3_g7_key_axis(spec, inputs,
      list(primary = primary, fallback = fallback), list())
  primary <- resolve(primary = "custom")
  fallback <- resolve()
  override <- resolve(list(weights = TRUE), "custom", "L1")
  both <- resolve(list(weights = TRUE, confidence = TRUE), "custom", "L1")
  whitespace <- resolve(primary = "  ")
  stopifnot(identical(primary$keys, "custom"),
    identical(fallback$keys, "L1"), identical(override$keys, "L1"),
    isTRUE(override$resolution$resolution$override_applied),
    identical(override$resolution$resolution$selected_parameter, "fallback"),
    identical(both$keys, "custom"),
    !isTRUE(both$resolution$resolution$override_applied),
    identical(whitespace$keys, "  "),
    !identical(fallback$identity, override$identity))
  for (bad in list("", NA_character_, character(), c("a", "b"), 1L,
      list("a"))) .wb_g7_effective_expect(.wb_operation_pack_v3_g7_key_axis(spec,
        list(), list(primary = bad, fallback = "L1"), list()),
      "PYBENCH_INPUT_IDENTITY_MISMATCH")
  .wb_g7_effective_expect(.wb_operation_pack_v3_g7_key_axis(spec, list(weights = TRUE),
    list(primary = "custom", fallback = NULL), list()),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  .wb_g7_effective_expect(.wb_operation_pack_v3_g7_key_axis(spec, list(),
    list(primary = NULL, fallback = NULL), list()),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}

test_operation_pack_v3_g7_effective_key_manifest_adversarial_contract <-
    function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  index <- match("scwbv3phase5::derived_effective_key", vapply(
    manifest$operations, `[[`, character(1), "qualified_name"))
  reject <- function(change) {
    candidate <- unserialize(serialize(manifest, NULL))
    candidate$operations[[index]] <- change(candidate$operations[[index]])
    error <- tryCatch(wb_operation_pack_manifest_validate(candidate),
      error = identity)
    stopifnot(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"))
  }
  key <- function(op) op$derived_cell_output_axes[[1L]]$linked_outputs[[1L]]$
    key_axis
  set_key <- function(op, value) {
    op$derived_cell_output_axes[[1L]]$linked_outputs[[1L]]$key_axis <- value
    op
  }
  reject(function(op) { value <- key(op); value$parameter_candidates <-
    list("unknown"); set_key(op, value) })
  reject(function(op) { value <- key(op); value$parameter_candidates <-
    list("primary_key", "primary_key"); set_key(op, value) })
  reject(function(op) { value <- key(op); value$input_presence_override$absent <-
    "override_present"; set_key(op, value) })
  reject(function(op) { value <- key(op); value$input_presence_override$
    use_parameter <- "unknown"; set_key(op, value) })
  reject(function(op) { op$params_schema$properties$primary_key$default <- "";
    op })
  reject(function(op) { op$params_schema$properties$primary_key$type <-
    list("number", "null"); op })
  reject(function(op) { op$derived_cell_output_axes[[1L]]$linked_outputs[[1L]]$
    shape <- "bounded_grouped_cell_key_cartesian"; op })
  TRUE
}

test_operation_pack_v3_g7_effective_key_lifecycle_rollback_and_receipt_contract <-
    function() {
  fixture <- .wb_g7_effective_fixture_install(); state <-
    .wb_g7_effective_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_g7_effective_fixture_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model"), created_by = "g7-effective")
  source_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "embedding"][[1L]]
  fit$session <- wb_session_discard(fit$session)
  source <- wb_ref_artifact(source_id, "embedding")
  execute <- function(primary = NULL, fallback = "fallback", extra = list()) {
    inputs <- c(list(source = source, selected_cells = c("cell_2", "cell_1"),
      fallback_key = fallback, cell_set = "all", min_cells = 1L), extra)
    if (!is.null(primary)) inputs$primary_key <- primary
    wb_session_run_op(wb_session_new(), state$bundle,
      "scwbv3phase5::derived_effective_key", inputs = inputs)
  }
  primary <- execute("custom")
  primary_value <- wb_operation_pack_transition_load(
    primary$session$staging_bundle,
    primary$run$operation_pack_transition$transition_id, "family")
  primary_records <- .wb_g7_effective_transition_records(primary)
  stopifnot(identical(primary_value$key, rep("custom", 2L)),
    isTRUE(.wb_operation_pack_v3_g7_receipt_audit(primary_records$receipt,
      primary_records$request)))
  policy <- primary_records$request$outputs[[1L]]$descriptor$
    derived_cell_output_axis_policy$resolved_key_axis
  stopifnot(identical(policy$resolution$selected_parameter, "primary_key"),
    identical(policy$resolution$selected_key, "custom"))

  override <- execute("custom", "L1", list(override_present = source))
  override_value <- wb_operation_pack_transition_load(
    override$session$staging_bundle,
    override$run$operation_pack_transition$transition_id, "family")
  override_records <- .wb_g7_effective_transition_records(override)
  override_policy <- override_records$request$outputs[[1L]]$descriptor$
    derived_cell_output_axis_policy$resolved_key_axis
  stopifnot(identical(override_value$key, rep("L1", 2L)),
    isTRUE(override_policy$resolution$override_applied),
    identical(override_policy$resolution$selected_parameter, "fallback_key"),
    isTRUE(.wb_operation_pack_v3_g7_receipt_audit(override_records$receipt,
      override_records$request)))

  forged_request <- unserialize(serialize(primary_records$request, NULL))
  forged_policy <- forged_request$outputs[[1L]]$descriptor$
    derived_cell_output_axis_policy$resolved_key_axis
  forged_policy$keys <- list("forged")
  forged_policy$resolution$selected_key <- "forged"
  linked <- forged_request$outputs[[1L]]$descriptor$
    derived_cell_output_axis_policy
  linked$resolved_key_axis <- forged_policy
  linked$resolved_keys <- list("forged")
  linked$resolved_key_axis_policy_identity_or_null <-
    .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.resolved_key_axis_policy.v1", forged_policy)
  forged_request$outputs[[1L]]$descriptor$
    derived_cell_output_axis_policy <- linked
  .wb_g7_effective_expect(.wb_operation_pack_v3_g7_receipt_audit(
    primary_records$receipt, forged_request), "PYBENCH_CAPABILITY_MISMATCH")

  before <- list(artifacts = nrow(wb_art_list(state$bundle)),
    fingerprint = .wb_manifest_registry_snapshot(state$bundle$con)$fingerprint,
    store = sort(list.files(.wb_operation_pack_v2_store(state$bundle),
      all.files = TRUE, no.. = TRUE)))
  for (extra in list(list(forge_key = "wrong"),
      list(fault_after_output = TRUE))) {
    .wb_g7_effective_expect(execute("custom", "L1", extra),
      if (!is.null(extra$forge_key)) "PYBENCH_OUTPUT_INVALID" else
        "PYBENCH_PROCESS_FAILED")
    stopifnot(nrow(wb_art_list(state$bundle)) == before$artifacts,
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$fingerprint,
        before$fingerprint), identical(sort(list.files(
          .wb_operation_pack_v2_store(state$bundle), all.files = TRUE,
          no.. = TRUE)), before$store))
  }
  primary$session <- wb_session_discard(primary$session)
  override$session <- wb_session_discard(override$session)
  TRUE
}
