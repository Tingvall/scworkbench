.wb_sscf_install <- function() {
  library <- tempfile("scwb-sscf-lib-"); dir.create(library)
  log <- tempfile("scwb-sscf-install-", fileext = ".log")
  source <- file.path(normalizePath(".", mustWork = TRUE), "tests",
    "fixtures", "operation-pack-v3-phase5")
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

.wb_sscf_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_sscf_bundle <- function() {
  root <- tempfile("scwb-sscf-bundle-")
  bundle <- wb_init_bundle(root)
  cells <- sprintf("cell_%03d", seq_len(120L))
  cells[1:2] <- c("cell|001", "cell:002")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(360L), nrow = 120L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  list(root = root, bundle = bundle, cells = cells)
}

.wb_sscf_run <- function(bundle, source = "pca", model = FALSE,
    keys = c("lineage_z", "lineage_a"), subsets = NULL, mode = "normal") {
  if (is.null(subsets)) stop("Explicit subsets required.")
  operation <- if (model) "scwbv3phase5::standalone_sparse_family_model"
    else "scwbv3phase5::standalone_sparse_family"
  input <- if (model) list(model = source) else list(source = source)
  wb_session_run_op(wb_session_new(), bundle, operation, inputs = c(input,
    list(keys = keys, per_key_cells = subsets, mode = mode,
      cell_set = "all", min_cells = 1L)))
}

.wb_sscf_records <- function(run) {
  transition <- run$run$operation_pack_transition
  root <- file.path(.wb_operation_pack_v2_store(run$session$staging_bundle),
    transition$transition_id)
  list(root = root,
    request = jsonlite::read_json(file.path(root, "request.json"),
      simplifyVector = FALSE),
    receipt = jsonlite::read_json(file.path(root, "receipt.json"),
      simplifyVector = FALSE))
}

.wb_sscf_expect <- function(expr, codes) {
  error <- tryCatch(force(expr), error = identity)
  if (!(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"))) stop(
        "Expected a pack-contract error, got ",
        paste(class(error), collapse = "/"), ": ",
        conditionMessage(error), call. = FALSE)
  if (!as.character(error$code) %in% codes) stop(
    "Expected ", paste(codes, collapse = "/"), "; got ",
    as.character(error$code), ": ", conditionMessage(error),
    call. = FALSE)
  invisible(error)
}

.wb_sscf_rehash <- function(value, field) {
  identity <- value[[field]]
  value[[field]] <- NULL
  value[[field]] <- if (is.null(identity$scope))
    .wb_operation_pack_v2_identity_plain(identity$scheme, value) else
    .wb_operation_pack_v2_identity_scoped(identity$scheme,
      identity$scope, value)
  value
}

.wb_sscf_forge_retained_source <- function(request, field) {
  forged <- .wb_operation_pack_v2_deep_copy(request)
  grant <- forged$standalone_sparse_cell_family_grants[[1L]]
  source <- grant$source_axis
  source[[field]]$sha256 <- paste(rep("f", 64L), collapse = "")
  source <- .wb_sscf_rehash(source, "source_axis_identity")
  grant$source_axis <- source
  grant$source_axis_identity <- .wb_operation_pack_v3_unscoped_identity(
    source$source_axis_identity)
  grant <- .wb_sscf_rehash(grant, "grant_identity")
  forged$standalone_sparse_cell_family_grants[[1L]] <- grant
  output_index <- match(grant$output_name, vapply(forged$outputs,
    `[[`, character(1), "name"))
  descriptor <- forged$outputs[[output_index]]$descriptor
  descriptor$standalone_sparse_cell_family_provisional_grant <- grant
  descriptor <- .wb_sscf_rehash(descriptor, "grant_identity")
  forged$outputs[[output_index]]$descriptor <- descriptor
  capability <- forged$execution_capability
  capability$standalone_sparse_cell_family_grant_identities <- list(
    .wb_operation_pack_v3_unscoped_identity(grant$grant_identity))
  forged$execution_capability <- .wb_sscf_rehash(capability,
    "capability_identity")
  .wb_sscf_rehash(forged, "request_identity")
}

test_operation_pack_v3_standalone_sparse_family_protocol_identity_contract <-
    function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)
  cases <- Filter(function(x) startsWith(x$name, "sparse_"),
    fixture$cases)
  negatives <- Filter(function(x) startsWith(x$name, "sparse_"),
    fixture$negative_cases)
  stopifnot(length(cases) == 17L, length(negatives) == 8L)
  identities <- stats::setNames(vapply(cases, function(item) {
    stopifnot(identical(.wb_operation_pack_sha256(item$preimage),
      item$identity$sha256))
    item$identity$sha256
  }, character(1)), vapply(cases, `[[`, character(1), "name"))
  stopifnot(!identical(identities[["sparse_structured_pair_order"]],
      identities[["sparse_swapped_key_pair_order"]]),
    !identical(identities[["sparse_separator_pair_left"]],
      identities[["sparse_separator_pair_right"]]))
  root <- stats::setNames(lapply(c(
    "operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json"), function(path)
      jsonlite::read_json(file.path("inst", "protocol", path),
        simplifyVector = FALSE)), c("operation-pack-v3.schema.json",
      "operation-pack-transition-request-v3.schema.json",
      "operation-pack-transition-receipt-v3.schema.json"))
  for (item in negatives) {
    schema <- root[[item$schema_file]]
    definition <- schema$`$defs`[[item$definition]]
    result <- .wb_json_schema_validate_2020(item$value, definition,
      schema)
    stopifnot(identical(isTRUE(result$ok),
      identical(item$expected, "semantic_reject")))
  }
  map <- stats::setNames(cases, vapply(cases, `[[`, character(1), "name"))
  request <- map[["sparse_success_request"]]$value
  receipt <- map[["sparse_success_receipt"]]$value
  stopifnot(isTRUE(.wb_operation_pack_v3_sscf_receipt_audit(receipt,
    request)))
  negative_map <- stats::setNames(negatives,
    vapply(negatives, `[[`, character(1), "name"))
  altered <- .wb_operation_pack_v2_deep_copy(receipt)
  altered$sparse_cell_family_observations[[1L]]$declaration <-
    negative_map[["sparse_declaration_keys_swapped_self_rehashed"]]$value
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_receipt_audit(altered,
    request), "PYBENCH_RECEIPT_MISMATCH")
  altered <- .wb_operation_pack_v2_deep_copy(receipt)
  altered$sparse_cell_family_observations[[1L]] <-
    negative_map[["sparse_receipt_keys_swapped_self_rehashed"]]$value
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_receipt_audit(altered,
    request), "PYBENCH_RECEIPT_MISMATCH")
  .wb_sscf_expect(.wb_operation_pack_v3_assert_self_identity(
    negative_map[["sparse_policy_self_hash_wrong"]]$value,
    "policy_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging"),
    "PYBENCH_CAPABILITY_MISMATCH")
  TRUE
}

test_operation_pack_v3_standalone_sparse_family_manifest_admission_contract <-
    function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  stopifnot(identical(wb_operation_pack_manifest_validate(manifest)$
    identity$pack_abi_version, "3"))
  before <- list(packs = wb_operation_packs(), ops = wb_list_ops(),
    catalog = wb_operation_catalog_identity())
  reject <- function(value) {
    .wb_sscf_expect(wb_operation_pack_manifest_validate(value),
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID")
    stopifnot(identical(wb_operation_packs(), before$packs),
      identical(wb_list_ops(), before$ops),
      identical(wb_operation_catalog_identity(), before$catalog))
  }
  sparse <- manifest$operations[[length(manifest$operations) - 1L]]
  python <- manifest
  python$operations <- list(sparse)
  python$backend <- "Python"
  python$compatibility$process_protocol <- list(minimum = "pybench-op-v4",
    maximum = "pybench-op-v4")
  reject(python)
  sibling <- manifest
  policy <- sparse$dimension_policies[[1L]]
  policy$output <- "weights"
  policy$policy_identity$sha256 <- NULL
  policy$policy_identity$sha256 <- .wb_operation_pack_sha256(
    policy[names(policy) != "policy_identity"])
  sibling$operations[[1L]]$dimension_policies <- list(policy)
  reject(sibling)
  foreign <- manifest
  index <- length(foreign$operations) - 1L
  foreign$operations[[index]]$dimension_policies[[1L]]$axis_source$
    input <- "absent"
  policy <- foreign$operations[[index]]$dimension_policies[[1L]]
  foreign$operations[[index]]$dimension_policies[[1L]]$policy_identity$
    sha256 <- .wb_operation_pack_sha256(
      policy[names(policy) != "policy_identity"])
  reject(foreign)
  TRUE
}

test_operation_pack_v3_standalone_sparse_family_typed_lifecycle_contract <-
    function() {
  fixture <- .wb_sscf_install()
  state <- .wb_sscf_bundle()
  on.exit({
    if (!is.null(state$bundle)) try(wb_close_bundle(state$bundle),
      silent = TRUE)
    .wb_sscf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  keys <- c("lineage|z", "lineage:a")
  subsets <- list(state$cells[1:80], state$cells[41:120])
  run <- .wb_sscf_run(state$bundle, keys = keys, subsets = subsets)
  record <- .wb_sscf_records(run)
  grant <- record$request$standalone_sparse_cell_family_grants[[1L]]
  observation <- record$receipt$sparse_cell_family_observations[[1L]]
  stopifnot(isTRUE(.wb_operation_pack_v3_sscf_retained_binding_audit(
    record$request)))
  forged <- .wb_sscf_forge_retained_source(record$request,
    "input_content_identity")
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_retained_binding_audit(
    forged), "PYBENCH_REOPEN_VALIDATION_FAILED")
  forged_receipt <- .wb_operation_pack_v2_deep_copy(record$receipt)
  forged_receipt$request_identity <- forged$request_identity
  forged_receipt$capability_identity <- forged$execution_capability$
    capability_identity
  forged_receipt <- .wb_sscf_rehash(forged_receipt,
    "receipt_identity")
  stopifnot(!isTRUE(.wb_operation_pack_v3_record_validate(forged,
    forged_receipt, record$root, load_payloads = TRUE)$ok))
  stopifnot(identical(grant$source_axis$source_kind,
      "typed_space_input_v1"),
    identical(observation$observed_row_count, 160L),
    identical(unlist(observation$observed_keys, use.names = FALSE), keys),
    identical(unlist(observation$per_key_cell_counts, use.names = FALSE),
      c(80L, 80L)),
    isTRUE(.wb_operation_pack_v2_record_validate(record$root,
      load_payloads = TRUE)$ok))
  value <- wb_operation_pack_transition_load(run$session$staging_bundle,
    run$run$operation_pack_transition$transition_id, "family")
  stopifnot(identical(as.character(value$key), rep(keys, each = 80L)),
    identical(as.character(value$cell_id), unlist(subsets,
      use.names = FALSE)), length(value$value) == 160L)
  promoted <- wb_session_promote_current(state$bundle, run$session,
    outputs = "family", created_by = "sparse-family-contract")
  stopifnot(nrow(promoted$promoted) == 1L,
    identical(promoted$promoted$status[[1L]], "ok"))
  artifact_id <- promoted$promoted$artifact_id[[1L]]
  try(wb_session_discard(run$session), silent = TRUE)
  loaded <- wb_art_load(state$bundle, artifact_id,
    expected_kind = "cell_vector_family")
  stopifnot(identical(loaded$key, value$key),
    identical(loaded$cell_id, value$cell_id),
    identical(loaded$value, value$value))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle); state$bundle <- NULL
  state$bundle <- wb_open_bundle(state$root, read_only = TRUE)
  report <- wb_bundle_validation_report(state$root, level = "recipient")
  reopened <- wb_art_load(state$bundle, artifact_id,
    expected_kind = "cell_vector_family")
  stopifnot(isTRUE(report$ok), identical(reopened$key, value$key),
    identical(reopened$cell_id, value$cell_id))
  relocated_root <- tempfile("scwb-sscf-relocated-")
  fs::dir_copy(state$root, relocated_root)
  on.exit(unlink(relocated_root, recursive = TRUE, force = TRUE),
    add = TRUE)
  relocated <- wb_open_bundle(relocated_root, read_only = TRUE)
  on.exit(wb_close_bundle(relocated), add = TRUE)
  relocated_report <- wb_bundle_validation_report(relocated_root,
    level = "recipient")
  relocated_value <- wb_art_load(relocated, artifact_id,
    expected_kind = "cell_vector_family")
  stopifnot(isTRUE(relocated_report$ok),
    identical(relocated_value$key, value$key),
    identical(relocated_value$cell_id, value$cell_id),
    identical(relocated_value$value, value$value))
  TRUE
}

test_operation_pack_v3_standalone_sparse_family_seal_and_receipt_contract <-
    function() {
  fixture <- .wb_sscf_install()
  state <- .wb_sscf_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_sscf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  subsets <- list(state$cells[1:80], state$cells[41:120])
  before <- sort(list.files(.wb_operation_pack_v2_store(state$bundle),
    all.files = TRUE, no.. = TRUE))
  before_fingerprint <- .wb_manifest_registry_snapshot(state$bundle$con)$
    fingerprint
  for (mode in c("omit", "repeat", "write_before_declare", "late",
      "swap_rows", "invalid_then_valid", "non_numeric",
      "non_finite", "wrong_value_type")) {
    .wb_sscf_expect(.wb_sscf_run(state$bundle, subsets = subsets,
      mode = mode), c("PYBENCH_CAPABILITY_MISMATCH",
        "PYBENCH_OUTPUT_INVALID", "PYBENCH_RECEIPT_MISMATCH",
        "PYBENCH_PROCESS_FAILED"))
    stopifnot(identical(sort(list.files(.wb_operation_pack_v2_store(
      state$bundle), all.files = TRUE, no.. = TRUE)), before),
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$
        fingerprint, before_fingerprint),
      nrow(wb_art_list(state$bundle)) == 0L)
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, "sparse_cell_family_sealed"))
      stop("caught sparse seal fault"))
  .wb_sscf_expect(.wb_sscf_run(state$bundle, subsets = subsets,
    mode = "caught_seal_fault"),
    c("PYBENCH_CAPABILITY_MISMATCH", "PYBENCH_PROCESS_FAILED"))
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(identical(sort(list.files(.wb_operation_pack_v2_store(
    state$bundle), all.files = TRUE, no.. = TRUE)), before),
    identical(.wb_manifest_registry_snapshot(state$bundle$con)$
      fingerprint, before_fingerprint),
    nrow(wb_art_list(state$bundle)) == 0L)
  bad_subsets <- list(state$cells[2:81], rev(state$cells[41:120]))
  .wb_sscf_expect(.wb_sscf_run(state$bundle, subsets = bad_subsets),
    c("PYBENCH_OUTPUT_INVALID", "PYBENCH_PROCESS_FAILED"))
  .wb_sscf_expect(.wb_sscf_run(state$bundle,
    subsets = list(state$cells[1:80], c(state$cells[41:119],
      "foreign_cell"))), c("PYBENCH_OUTPUT_INVALID",
        "PYBENCH_PROCESS_FAILED"))
  stopifnot(identical(sort(list.files(.wb_operation_pack_v2_store(
    state$bundle), all.files = TRUE, no.. = TRUE)), before),
    identical(.wb_manifest_registry_snapshot(state$bundle$con)$
      fingerprint, before_fingerprint))
  for (fault_event in c("before_publication", "published",
      "before_reopened")) {
    options(scworkbench.operation_pack_v2_test_hook = local({
      wanted <- fault_event
      function(event, ...) if (identical(event, wanted))
        stop("sparse fault")
    }))
    .wb_sscf_expect(.wb_sscf_run(state$bundle, subsets = subsets),
      if (identical(fault_event, "before_reopened"))
        "PYBENCH_REOPEN_VALIDATION_FAILED" else
        "PYBENCH_PUBLICATION_FAILED")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(identical(sort(list.files(.wb_operation_pack_v2_store(
      state$bundle), all.files = TRUE, no.. = TRUE)), before),
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$
        fingerprint, before_fingerprint),
      nrow(wb_art_list(state$bundle)) == 0L)
  }
  run <- .wb_sscf_run(state$bundle, subsets = subsets)
  record <- .wb_sscf_records(run)
  grant <- record$request$standalone_sparse_cell_family_grants[[1L]]
  axis <- .wb_operation_pack_v3_sscf_cells(grant$source_axis)
  first <- .wb_operation_pack_v3_sscf_layout(grant, "family",
    c("a|b", "a"), list(axis[1:2], axis[3:4]))
  swapped <- .wb_operation_pack_v3_sscf_layout(grant, "family",
    c("a", "a|b"), list(axis[1:2], axis[3:4]))
  stopifnot(!identical(first$seal$key_major_pair_order_identity,
    swapped$seal$key_major_pair_order_identity),
    !identical(first$seal$seal_identity, swapped$seal$seal_identity))
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(grant, "family",
    paste0("key", seq_len(65L)), rep(list(axis[[1L]]), 65L)),
    "PYBENCH_CAPABILITY_MISMATCH")
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(grant, "family",
    "key", list(rev(axis[1:2]))), "PYBENCH_OUTPUT_INVALID")
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(grant, "family",
    "key", list(rep(axis[[1L]], 2L))), "PYBENCH_OUTPUT_INVALID")
  tight <- grant; tight$limits$maximum_control_bytes <- 1L
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(tight, "family",
    "key", list(axis[[1L]])), "PYBENCH_CAPABILITY_MISMATCH")
  tight <- grant; tight$limits$maximum_rows <- 1L
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(tight, "family",
    "key", list(axis[1:2])), "PYBENCH_CAPABILITY_MISMATCH")
  tight <- grant; tight$limits$maximum_id_bytes <- 1L
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_layout(tight, "family",
    "key", list(axis[[1L]])), "PYBENCH_CAPABILITY_MISMATCH")
  changed <- .wb_operation_pack_v2_deep_copy(record$receipt)
  changed$sparse_cell_family_observations[[1L]]$observed_row_count <- 159L
  changed$sparse_cell_family_observations[[1L]]$observation_identity <- NULL
  changed$sparse_cell_family_observations[[1L]]$observation_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_sparse_cell_family.v1",
      "observation excluding observation_identity",
      changed$sparse_cell_family_observations[[1L]])
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_receipt_audit(changed,
    record$request, stage_root = record$root), "PYBENCH_RECEIPT_MISMATCH")
  altered_root <- tempfile("scwb-sscf-payload-tamper-")
  fs::dir_copy(record$root, altered_root)
  on.exit(unlink(altered_root, recursive = TRUE, force = TRUE),
    add = TRUE)
  payload <- file.path(altered_root, "outputs", "family", "payload.rds")
  altered_value <- readRDS(payload)
  altered_value$value[[1L]] <- altered_value$value[[1L]] + 1
  saveRDS(altered_value, payload)
  stopifnot(!isTRUE(.wb_operation_pack_v3_record_validate(
    record$request, record$receipt, altered_root,
    load_payloads = TRUE)$ok))
  changed <- .wb_operation_pack_v2_deep_copy(record$receipt)
  changed$sparse_cell_family_observations[[1L]]$output_content_identity$
    sha256 <- paste(rep("0", 64L), collapse = "")
  changed$sparse_cell_family_observations[[1L]]$observation_identity <- NULL
  changed$sparse_cell_family_observations[[1L]]$observation_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_sparse_cell_family.v1",
      "observation excluding observation_identity",
      changed$sparse_cell_family_observations[[1L]])
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_receipt_audit(changed,
    record$request, stage_root = record$root), "PYBENCH_RECEIPT_MISMATCH")
  try(wb_session_discard(run$session), silent = TRUE)
  TRUE
}

test_operation_pack_v3_standalone_sparse_family_verified_g1_contract <-
    function() {
  fixture <- .wb_sscf_install()
  state <- .wb_sscf_bundle()
  on.exit({
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_sscf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  for (variant in c("v2", "v3")) {
    if (identical(variant, "v2")) {
      fit <- wb_session_run_op(wb_session_new(), state$bundle,
        "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
          dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
      promoted <- wb_session_promote_current(state$bundle, fit$session,
        outputs = c("model", "embedding"),
        created_by = "sparse-g1-contract")
      axis <- state$cells
    } else {
      fit <- wb_session_run_op(wb_session_new(), state$bundle,
        "scwbv3phase5::fit_derived_axis_model", inputs = list(
          source = "pca", dims = c(1L, 3L),
          fitted_cells = state$cells[11:110], cell_set = "all",
          min_cells = 1L))
      promoted <- wb_session_promote_current(state$bundle, fit$session,
        outputs = c("model", "embedding", "weights"),
        created_by = "sparse-g1-contract")
      axis <- state$cells[11:110]
    }
    model_id <- promoted$promoted$artifact_id[
      promoted$promoted$output == "model"][[1L]]
    try(wb_session_discard(fit$session), silent = TRUE)
    subsets <- list(axis[1:80], axis[(length(axis) - 79L):length(axis)])
    run <- .wb_sscf_run(state$bundle,
      source = wb_ref_artifact(model_id, "model"), model = TRUE,
      subsets = subsets)
    record <- .wb_sscf_records(run)
    source <- record$request$standalone_sparse_cell_family_grants[[1L]]$
      source_axis
    stopifnot(isTRUE(.wb_operation_pack_v3_sscf_retained_binding_audit(
      record$request)))
    forged <- .wb_sscf_forge_retained_source(record$request,
      "model_content_identity")
    .wb_sscf_expect(.wb_operation_pack_v3_sscf_retained_binding_audit(
      forged), "PYBENCH_REOPEN_VALIDATION_FAILED")
    stopifnot(identical(source$source_kind,
        "verified_g1_model_fitted_axis_v1"),
      identical(source$axis_evidence$schema, paste0(
        "scworkbench.operation_pack.sparse_family_g1_axis_evidence.",
        variant)),
      identical(unlist(source$ordered_fitted_cells,
        use.names = FALSE), axis),
      isTRUE(.wb_operation_pack_v2_record_validate(record$root,
        load_payloads = TRUE)$ok))
    family <- wb_operation_pack_transition_load(run$session$staging_bundle,
      run$run$operation_pack_transition$transition_id, "family")
    stopifnot(identical(family$cell_id, unlist(subsets,
      use.names = FALSE)))
    if (identical(variant, "v3")) {
      altered_root <- tempfile("scwb-sscf-model-corrupt-")
      fs::dir_copy(state$root, altered_root)
      altered <- wb_open_bundle(altered_root, validate = FALSE)
      altered_model <- wb_art_load(altered, model_id,
        expected_kind = "model_ref")
      primary <- file.path(altered_model$model_tree_root,
        altered_model$model_primary_path)
      Sys.chmod(primary, mode = "0644")
      connection <- file(primary, open = "ab")
      writeBin(charToRaw("changed-model"), connection)
      close(connection)
      .wb_sscf_expect(.wb_operation_pack_v3_sscf_source_assert_current(
        altered, record$request, list(model = altered_model),
        phase = "audit"), "PYBENCH_INPUT_IDENTITY_MISMATCH")
      wb_close_bundle(altered)
      unlink(altered_root, recursive = TRUE, force = TRUE)
    }
    result <- wb_session_promote_current(state$bundle, run$session,
      outputs = "family", created_by = "sparse-g1-contract")
    stopifnot(nrow(result$promoted) == 1L,
      result$promoted$status[[1L]] == "ok")
    try(wb_session_discard(run$session), silent = TRUE)
  }
  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle); state$bundle <- NULL
  report <- wb_bundle_validation_report(state$root, level = "recipient")
  if (!isTRUE(report$ok)) stop(paste(capture.output(str(report)),
    collapse = "\n"), call. = FALSE)
  TRUE
}

test_operation_pack_v3_standalone_sparse_family_source_recheck_contract <-
    function() {
  fixture <- .wb_sscf_install()
  state <- .wb_sscf_bundle()
  on.exit({
    if (!is.null(state$bundle)) try(wb_close_bundle(state$bundle),
      silent = TRUE)
    .wb_sscf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  run <- .wb_sscf_run(state$bundle, subsets = list(state$cells[1:80],
    state$cells[41:120]))
  request <- .wb_sscf_records(run)$request
  try(wb_session_discard(run$session), silent = TRUE)
  before <- sort(list.files(.wb_operation_pack_v2_store(state$bundle),
    all.files = TRUE, no.. = TRUE))
  row <- DBI::dbGetQuery(state$bundle$con,
    "SELECT path FROM space_payloads WHERE space_id='pca';")
  source_path <- file.path(state$root, row$path[[1L]])
  Sys.chmod(source_path, mode = "0644")
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, "audited")) rhdf5::h5write(999,
      source_path, "coordinates", index = list(1L, 1L)))
  on.exit(options(scworkbench.operation_pack_v2_test_hook = NULL),
    add = TRUE)
  .wb_sscf_expect(.wb_sscf_run(state$bundle,
    subsets = list(state$cells[1:80], state$cells[41:120])),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(identical(sort(list.files(.wb_operation_pack_v2_store(
    state$bundle), all.files = TRUE, no.. = TRUE)), before),
    nrow(wb_art_list(state$bundle)) == 0L)
  wb_close_bundle(state$bundle); state$bundle <- NULL
  altered_root <- tempfile("scwb-sscf-source-corrupt-")
  fs::dir_copy(state$root, altered_root)
  on.exit(unlink(altered_root, recursive = TRUE, force = TRUE), add = TRUE)
  altered <- wb_open_bundle(altered_root, validate = FALSE)
  on.exit(try(wb_close_bundle(altered), silent = TRUE), add = TRUE)
  row <- DBI::dbGetQuery(altered$con,
    "SELECT path FROM space_payloads WHERE space_id='pca';")
  path <- file.path(altered_root, row$path[[1L]])
  Sys.chmod(path, mode = "0644")
  rhdf5::h5write(999, path, "coordinates", index = list(1L, 1L))
  .wb_sscf_expect(.wb_operation_pack_v3_sscf_source_assert_current(
    altered, request, list(source = wb_prim_space("pca")),
    phase = "publication"), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}
