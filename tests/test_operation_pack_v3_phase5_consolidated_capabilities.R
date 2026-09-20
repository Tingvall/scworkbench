.wb_phase5_fixture_install <- function() {
  library <- tempfile("scwb-phase5-lib-")
  dir.create(library, recursive = TRUE)
  log <- tempfile("scwb-phase5-install-", fileext = ".log")
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

.wb_phase5_fixture_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_phase5_expect_code <- function(expr, code) {
  error <- tryCatch(force(expr), error = identity)
  if (!(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"))) stop(paste0(
        "Expected an operation-pack error; observed ",
        paste(class(error), collapse = "/"), ": ", conditionMessage(error)),
      call. = FALSE)
  stopifnot(identical(as.character(error$code), code))
  invisible(error)
}

.wb_phase5_bundle <- function(root = tempfile("scwb-phase5-bundle-")) {
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c4", "c3")
  wb_define_cells(bundle, cells)
  coordinates <- matrix(seq_len(12L), nrow = 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3")))
  wb_add_space(bundle, "pca", coordinates)
  wb_add_space(bundle, "display", coordinates[c("c1", "c2", "c3"),
    1:2, drop = FALSE])
  wb_cell_set_replace(bundle, "set:first", c("c4", "c1", "c3"),
    source = "phase5-contract")
  wb_cell_set_replace(bundle, "set:last", c("c2", "c4"),
    source = "phase5-contract")
  list(root = root, bundle = bundle, cells = cells,
    coordinates = coordinates)
}

test_operation_pack_v3_phase5_manifest_admission_no_residue_contract <-
    function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  stopifnot(identical(wb_operation_pack_manifest_validate(manifest)$
    identity$pack_abi_version, "3"))
  before <- list(packs = wb_operation_packs(), ops = wb_list_ops(),
    catalog = wb_operation_catalog_identity())
  reject <- function(value) {
    error <- tryCatch(wb_operation_pack_manifest_validate(value),
      error = identity)
    stopifnot(inherits(error, "wb_operation_pack_v3_error"),
      identical(as.character(error$code),
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID"),
      identical(before$packs, wb_operation_packs()),
      identical(before$ops, wb_list_ops()),
      identical(before$catalog, wb_operation_catalog_identity()))
  }
  wildcard <- unserialize(serialize(manifest, NULL))
  wildcard$operations[[2L]]$self_linked_contained_model_reads[[1L]]$
    allowed_models[[1L]]$engine <- "*"
  reject(wildcard)
  duplicate <- unserialize(serialize(manifest, NULL))
  duplicate$operations[[2L]]$self_linked_contained_model_reads[[1L]]$
    allowed_models[[2L]] <- duplicate$operations[[2L]]$
      self_linked_contained_model_reads[[1L]]$allowed_models[[1L]]
  # uniqueItems is an outer-schema failure, and must equally leave no residue.
  duplicate_error <- tryCatch(wb_operation_pack_manifest_validate(duplicate),
    error = identity)
  stopifnot(inherits(duplicate_error, "wb_operation_pack_v3_error"),
    identical(before$catalog, wb_operation_catalog_identity()))
  missing_sibling <- unserialize(serialize(manifest, NULL))
  missing_sibling$operations[[1L]]$outputs[[1L]]$
    contained_model_sibling_closure_policy$required_sibling_terminals <-
      list("absent")
  reject(missing_sibling)
  TRUE
}

test_operation_pack_v3_phase5_g1_g2_durable_lifecycle_contract <- function() {
  fixture <- .wb_phase5_fixture_install()
  state <- .wb_phase5_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_phase5_fixture_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
  transition <- fit$run$operation_pack_transition
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    fit$session$staging_bundle), transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  model_observed <- receipt$outputs[[match("model", vapply(
    receipt$outputs, `[[`, character(1), "name"))]]$descriptor
  stopifnot(!is.null(model_observed$contained_model_sibling_tree),
    identical(model_observed$contained_model_sibling_tree$loadability_status,
      "contained_tree_authenticated"),
    length(model_observed$contained_model_sibling_tree$
      ordered_sibling_observed_descriptor_identities) == 1L)
  transition_model <- wb_operation_pack_transition_load(
    fit$session$staging_bundle, transition$transition_id, "model")
  stopifnot(identical(transition_model$kind, "model_ref"),
    dir.exists(transition_model$model_tree_root),
    file.exists(file.path(transition_model$model_tree_root,
      transition_model$model_primary_path)),
    identical(transition_model$model_source_linkage$linkage_identity,
      fit$run$outputs$model$model_source_linkage$linkage_identity))

  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model"), created_by = "phase5-contract")
  stopifnot(nrow(promoted$promoted) == 2L,
    all(promoted$promoted$status == "ok"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  loaded_model <- wb_art_load(state$bundle, model_id,
    expected_kind = "model_ref")
  try(wb_session_discard(fit$session), silent = TRUE)
  stopifnot(identical(loaded_model$model_source_linkage$source_space_id,
    "pca"), dir.exists(loaded_model$model_tree_root))
  consumer_definition <- .wb_operation_pack_registry$operations[[
    "scwbv3phase5::consume_self_linked_model"]]$definition$v3_definition
  model_record <- .wb_operation_pack_v2_input_descriptor("model",
    loaded_model, consumer_definition$inputs[[1L]])$descriptor
  bad_engine <- .wb_operation_pack_v2_deep_copy(loaded_model)
  bad_engine$engine <- "substituted"
  negative_stage <- tempfile("scwb-phase5-g1-negative-")
  dir.create(negative_stage)
  .wb_phase5_expect_code(
    .wb_operation_pack_v3_prepare_self_linked_model_reads(state$bundle,
      consumer_definition, list(model = bad_engine),
      list(model = model_record), negative_stage),
    "PYBENCH_CAPABILITY_MISMATCH")
  bad_linkage <- .wb_operation_pack_v2_deep_copy(loaded_model)
  bad_linkage$model_source_linkage$source_space_content_identity$sha256 <-
    paste(rep("0", 64L), collapse = "")
  bad_linkage$model_source_linkage$linkage_identity <- NULL
  bad_linkage$model_source_linkage$linkage_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.model_source_linkage.v2",
      "linkage excluding linkage_identity", bad_linkage$model_source_linkage)
  .wb_phase5_expect_code(
    .wb_operation_pack_v3_prepare_self_linked_model_reads(state$bundle,
      consumer_definition, list(model = bad_linkage),
      list(model = model_record), negative_stage),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  good_stage <- tempfile("scwb-phase5-g1-tree-"); dir.create(good_stage)
  prepared_model <- .wb_operation_pack_v3_prepare_self_linked_model_reads(
    state$bundle, consumer_definition, list(model = loaded_model),
    list(model = model_record), good_stage)
  private_primary <- file.path(good_stage,
    prepared_model$grants[[1L]]$relative_root,
    prepared_model$grants[[1L]]$tree_manifest$primary_path)
  Sys.chmod(private_primary, mode = "0644")
  connection <- file(private_primary, open = "ab")
  writeBin(charToRaw("mutation"), connection); close(connection)
  .wb_phase5_expect_code(.wb_operation_pack_v3_validate_model_read(
    good_stage, prepared_model$grants[[1L]]),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  unlink(c(negative_stage, good_stage), recursive = TRUE, force = TRUE)

  consumed <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::consume_self_linked_model", inputs = list(
      model = wb_ref_artifact(model_id, "model"), cell_set = "all",
      min_cells = 1L))
  consumed_transition <- consumed$run$operation_pack_transition
  consumed_receipt <- jsonlite::read_json(file.path(
    .wb_operation_pack_v2_store(consumed$session$staging_bundle),
    consumed_transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  stopifnot(length(consumed_receipt$self_linked_model_payload_reads) == 1L,
    identical(consumed_receipt$self_linked_model_payload_reads[[1L]]$
      integrity_status, "unchanged"))
  summary_promotion <- wb_session_promote_current(state$bundle,
    consumed$session, outputs = "summary", created_by = "phase5-contract")
  try(wb_session_discard(consumed$session), silent = TRUE)
  stopifnot(nrow(summary_promotion$promoted) == 1L,
    summary_promotion$promoted$status[[1L]] == "ok")

  # A publication fault leaves neither a public transition nor analytical
  # artifacts and the same operation remains retryable.
  before_artifacts <- nrow(wb_art_list(state$bundle))
  before_store <- sort(list.files(.wb_operation_pack_v2_store(state$bundle),
    all.files = TRUE, no.. = TRUE))
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, "before_publication")) stop("phase5 fault"))
  .wb_phase5_expect_code(wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L)),
    "PYBENCH_PUBLICATION_FAILED")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(nrow(wb_art_list(state$bundle)) == before_artifacts,
    identical(sort(list.files(.wb_operation_pack_v2_store(state$bundle),
      all.files = TRUE, no.. = TRUE)), before_store))
  retry <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
  retry_transition <- retry$run$operation_pack_transition$transition_id
  retry_path <- file.path(.wb_operation_pack_v2_store(
    retry$session$staging_bundle), retry_transition)
  stopifnot(isTRUE(.wb_operation_pack_v2_record_validate(retry_path,
    load_payloads = TRUE)$ok))
  retry$session <- wb_session_discard(retry$session)

  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle); state$bundle <- NULL
  relocated <- tempfile("scwb-phase5-relocated-")
  fs::dir_copy(state$root, relocated)
  state$bundle <- wb_open_bundle(relocated, read_only = TRUE)
  report <- wb_bundle_validation_report(relocated, level = "recipient")
  reopened <- wb_art_load(state$bundle, model_id, expected_kind = "model_ref")
  stopifnot(isTRUE(report$ok), dir.exists(reopened$model_tree_root),
    identical(reopened$model_source_linkage,
      loaded_model$model_source_linkage))
  wb_close_bundle(state$bundle); state$bundle <- NULL

  source_corrupt <- tempfile("scwb-phase5-source-corrupt-")
  fs::dir_copy(relocated, source_corrupt)
  source_bundle <- wb_open_bundle(source_corrupt, read_only = TRUE)
  source_model <- wb_art_load(source_bundle, model_id,
    expected_kind = "model_ref")
  source_record <- .wb_operation_pack_v2_input_descriptor("model",
    source_model, consumer_definition$inputs[[1L]])$descriptor
  source_stage <- tempfile("scwb-phase5-source-stage-"); dir.create(source_stage)
  source_prepared <- .wb_operation_pack_v3_prepare_self_linked_model_reads(
    source_bundle, consumer_definition, list(model = source_model),
    list(model = source_record), source_stage)
  source_request <- list(
    self_linked_model_payload_grants = unname(source_prepared$grants),
    artifact_collection_grants = list(),
    named_cell_axis_collection_grants = list(),
    optional_display_axis_group_grants = list())
  attr(source_request, "operation_pack_stage_root") <- source_stage
  row <- DBI::dbGetQuery(source_bundle$con,
    "SELECT path FROM space_payloads WHERE space_id='pca';")
  source_path <- file.path(source_corrupt, row$path[[1L]])
  Sys.chmod(source_path, mode = "0644")
  rhdf5::h5write(999, source_path, "coordinates", index = list(1L, 1L))
  .wb_phase5_expect_code(
    .wb_operation_pack_v3_phase5_sources_assert_current(source_bundle,
      consumer_definition, source_request, list()),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  wb_close_bundle(source_bundle)
  unlink(c(source_corrupt, source_stage), recursive = TRUE, force = TRUE)

  corrupt <- tempfile("scwb-phase5-corrupt-")
  fs::dir_copy(relocated, corrupt)
  mutable <- wb_open_bundle(corrupt, validate = FALSE)
  corrupt_model <- wb_art_load(mutable, model_id, expected_kind = "model_ref")
  wb_close_bundle(mutable)
  primary <- file.path(corrupt_model$model_tree_root,
    corrupt_model$model_primary_path)
  Sys.chmod(primary, mode = "0644")
  connection <- file(primary, open = "ab")
  writeBin(charToRaw("mutation"), connection); close(connection)
  corrupted <- wb_bundle_validation_report(corrupt, level = "recipient")
  stopifnot(!isTRUE(corrupted$ok))
  unlink(c(relocated, corrupt), recursive = TRUE, force = TRUE)
  TRUE
}

test_operation_pack_v3_phase5_g4_ordered_artifact_collection_contract <-
    function() {
  fixture <- .wb_phase5_fixture_install()
  state <- .wb_phase5_bundle()
  stage <- tempfile("scwb-phase5-g4-stage-"); dir.create(stage)
  on.exit({
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_phase5_fixture_cleanup(fixture)
    unlink(c(state$root, stage), recursive = TRUE, force = TRUE)
  }, add = TRUE)
  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model"))$promoted
  ids <- stats::setNames(promoted$artifact_id, promoted$output)
  declaration <- list(name = "retained", parameter = "items",
    reader = "read_retained_artifact_collection_item",
    item_key_field = "key", order_field = "order", minimum_items = 2L,
    maximum_items = 2L, reference_slots = list(
      list(slot = "model", field = "model", required = FALSE,
        allowed_kinds = list("model_ref"), activation = "when_present",
        lifecycle_policy = "require_current",
        ancestry_policy = "require_content_verified_producer"),
      list(slot = "signal", field = "signal", required = FALSE,
        allowed_kinds = list("cell_vector"), activation = "when_present",
        lifecycle_policy = "require_current",
        ancestry_policy = "require_content_verified_producer")),
    maximum_references = 2L, maximum_single_payload_bytes = 268435456L,
    maximum_total_payload_bytes = 1073741824,
    call_discipline = "resolved_ordinal_slot_exactly_once")
  params <- list(items = list(
    list(key = "late", order = 20, signal = wb_ref_artifact(
      ids[["embedding"]], "embedding")),
    list(key = "early", order = 10, model = wb_ref_artifact(
      ids[["model"]], "model"))))
  prepared <- .wb_operation_pack_v3_prepare_artifact_collections(
    state$bundle, list(artifact_collection_reads = list(declaration)), params,
    stage)
  grant <- prepared$grants$retained
  stopifnot(identical(vapply(grant$items, `[[`, character(1), "item_key"),
    c("early", "late")), identical(vapply(grant$items, `[[`, integer(1),
      "parameter_ordinal"), c(2L, 1L)))
  request <- list(artifact_collection_grants = list(grant),
    named_cell_axis_collection_grants = list(),
    optional_display_axis_group_grants = list(), request_identity = list(
      scheme = "fixture", scope = "request", sha256 = paste(rep("1", 64),
        collapse = "")), execution_capability = list(capability_identity =
      list(scheme = "fixture", scope = "capability", sha256 = paste(rep("2",
        64), collapse = ""))), operation_authentication = list(
      operation_definition_identity = list(scheme = "fixture", scope = "op",
        sha256 = paste(rep("3", 64), collapse = ""))))
  attr(request, "operation_pack_v3_artifact_collection_values") <-
    prepared$values
  attr(request, "operation_pack_stage_root") <- stage
  stopifnot(isTRUE(.wb_operation_pack_v3_phase5_staged_payloads_assert(
    request)))
  adapter <- list(state = new.env(parent = emptyenv()), readers = list())
  adapter$state$used <- FALSE
  adapter <- .wb_operation_pack_v3_add_phase5_readers(adapter, request)
  .wb_phase5_expect_code(adapter$readers$
    read_retained_artifact_collection_item("retained", 2L, "signal"),
    "PYBENCH_CAPABILITY_MISMATCH")
  model <- adapter$readers$read_retained_artifact_collection_item(
    "retained", 1L, "model")
  signal <- adapter$readers$read_retained_artifact_collection_item(
    "retained", 2L, "signal")
  stopifnot(identical(model$kind, "model_ref"),
    identical(signal$kind, "cell_vector"), is.null(model$model_path),
    is.null(model$model_tree_root), is.null(model$model_tree_manifest))
  .wb_phase5_expect_code(adapter$readers$
    read_retained_artifact_collection_item("retained", 2L, "signal"),
    "PYBENCH_CAPABILITY_MISMATCH")
  usage <- .wb_operation_pack_v3_phase5_usage(adapter, request)
  stopifnot(length(usage$artifact_collection_usage) == 1L,
    usage$artifact_collection_usage[[1L]]$coverage_status == "exact")
  incomplete <- list(state = new.env(parent = emptyenv()), readers = list())
  incomplete$state$used <- FALSE
  incomplete <- .wb_operation_pack_v3_add_phase5_readers(incomplete, request)
  incomplete$readers$read_retained_artifact_collection_item(
    "retained", 1L, "model")
  .wb_phase5_expect_code(.wb_operation_pack_v3_phase5_usage(incomplete,
    request), "PYBENCH_RECEIPT_MISMATCH")
  payload <- file.path(stage, "artifact_collection_reads", "retained", "1",
    "model", "payload.rds")
  connection <- file(payload, open = "ab")
  writeBin(charToRaw("mutation"), connection); close(connection)
  .wb_phase5_expect_code(
    .wb_operation_pack_v3_phase5_staged_payloads_assert(request, "audit"),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}

test_operation_pack_v3_phase5_g5_g6_named_axis_contract <- function() {
  state <- .wb_phase5_bundle()
  stage <- tempfile("scwb-phase5-axis-stage-"); dir.create(stage)
  on.exit({
    try(wb_close_bundle(state$bundle), silent = TRUE)
    unlink(c(state$root, stage), recursive = TRUE, force = TRUE)
  }, add = TRUE)
  display_values <- wb_space(state$bundle, "display")
  display <- structure(list(kind = "space", space_id = "display",
    values = display_values, dimensions = as.integer(dim(display_values)),
    cell_id = rownames(display_values), storage_profile = "space_dense_v1",
    meta = list()), class = "wb_primitive")
  record <- .wb_operation_pack_v2_input_descriptor("display", display,
    list(name = "display", kind = "space", required = TRUE,
      alignment = "cell_ordered"))$descriptor
  axis_declaration <- list(name = "checkpoints", parameter = "sets",
    space_input = "display", reader = "read_named_cell_axis",
    minimum_axes = 2L, maximum_axes = 2L, minimum_cells_per_axis = 1L,
    maximum_cells_per_axis = 100L, maximum_total_memberships = 200L,
    projection_policy = "bundle_membership_intersect_space_axis_v1",
    call_discipline = "axis_ordinal_exactly_once")
  axes <- .wb_operation_pack_v3_prepare_named_axis_collections(state$bundle,
    list(named_cell_axis_collections = list(axis_declaration)),
    list(display = display), list(display = record),
    list(sets = c("set:first", "set:last")), stage)
  axis_grant <- axes$grants$checkpoints
  stopifnot(identical(vapply(axis_grant$axes, `[[`, character(1), "name"),
    c("set:first", "set:last")),
    identical(vapply(axis_grant$axes, `[[`, integer(1),
      "excluded_by_projection_count"), c(1L, 1L)),
    length(axis_grant$quality_observations$pairwise_overlap_counts) == 1L)

  display_declaration <- list(name = "endpoints", scope = "operation",
    collection_read = NULL, activation = list(
      start = list(endpoint_parameter = "start",
        top_level_cell_set_parameter = NULL),
      end = list(endpoint_parameter = "end",
        top_level_cell_set_parameter = NULL)),
    display_space_selector = list(operation_parameter = "display_space",
      item_field = NULL), endpoint_roles = list("start", "end"),
    dimension_count = 2L, maximum_groups = 1L,
    maximum_display_cells = 100L,
    maximum_cells_per_endpoint_axis = 100L,
    maximum_total_endpoint_memberships = 200L,
    call_discipline =
      "display_partition_then_endpoint_ordinal_exactly_once")
  optional <- .wb_operation_pack_v3_prepare_optional_display_groups(
    state$bundle, list(optional_display_axis_groups = list(
      display_declaration), artifact_collection_reads = list()),
    list(start = "set:first", end = list(cells = c("c4", "c2")),
      display_space = "display"), stage,
    list(grants = list(), values = list()))
  stopifnot(length(optional$grants) == 1L,
    length(optional$grants[[1L]]$endpoint_axes) == 2L,
    optional$grants[[1L]]$display_space$dimension_count == 2L)

  request <- list(artifact_collection_grants = list(),
    named_cell_axis_collection_grants = list(axis_grant),
    optional_display_axis_group_grants = unname(optional$grants),
    request_identity = list(scheme = "fixture", scope = "request",
      sha256 = paste(rep("1", 64), collapse = "")),
    execution_capability = list(capability_identity = list(
      scheme = "fixture", scope = "capability",
      sha256 = paste(rep("2", 64), collapse = ""))),
    operation_authentication = list(operation_definition_identity = list(
      scheme = "fixture", scope = "op",
      sha256 = paste(rep("3", 64), collapse = ""))))
  attr(request, "operation_pack_v3_named_axis_values") <- axes$values
  attr(request, "operation_pack_v3_optional_display_values") <-
    optional$values
  attr(request, "operation_pack_stage_root") <- stage
  stopifnot(isTRUE(.wb_operation_pack_v3_phase5_staged_payloads_assert(
    request)))
  adapter <- list(state = new.env(parent = emptyenv()), readers = list())
  adapter$state$used <- FALSE
  adapter <- .wb_operation_pack_v3_add_phase5_readers(adapter, request)
  .wb_phase5_expect_code(adapter$readers$read_named_cell_axis(
    "checkpoints", 2L), "PYBENCH_CAPABILITY_MISMATCH")
  first <- adapter$readers$read_named_cell_axis("checkpoints", 1L)
  last <- adapter$readers$read_named_cell_axis("checkpoints", 2L)
  stopifnot(identical(as.character(first$cell_id), c("c1", "c3")),
    identical(as.character(last$cell_id), "c2"))
  display_first <- adapter$readers$read_optional_display_space(
    "endpoints", "operation", c("c2", "c1"))
  display_last <- adapter$readers$read_optional_display_space(
    "endpoints", "operation", "c3")
  start <- adapter$readers$read_optional_endpoint_axis(
    "endpoints", "operation", 1L)
  end <- adapter$readers$read_optional_endpoint_axis(
    "endpoints", "operation", 2L)
  stopifnot(nrow(display_first$values) == 2L,
    nrow(display_last$values) == 1L,
    identical(as.character(start$cell_id), c("c1", "c3")),
    identical(as.character(end$cell_id), "c2"))
  usage <- .wb_operation_pack_v3_phase5_usage(adapter, request)
  stopifnot(length(usage$named_cell_axis_collection_usage) == 1L,
    length(usage$optional_display_axis_group_usage) == 1L)

  # Revalidation rejects a changed durable membership after dispatch.
  attr(request, "operation_pack_v3_named_axis_sources") <- axes$sources
  attr(request, "operation_pack_v3_optional_display_sources") <-
    optional$sources
  attr(request, "operation_pack_v3_optional_display_values") <-
    optional$values
  request$self_linked_model_payload_grants <- list()
  request$artifact_collection_grants <- list()
  wb_cell_set_replace(state$bundle, "set:first", c("c1", "c2"),
    source = "phase5-mutation")
  .wb_phase5_expect_code(.wb_operation_pack_v3_phase5_sources_assert_current(
    state$bundle, list(), request, list()),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}
