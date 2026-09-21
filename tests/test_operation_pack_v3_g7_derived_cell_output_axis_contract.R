.wb_g7_fixture_install <- function() {
  library <- tempfile("scwb-g7-lib-"); dir.create(library, recursive = TRUE)
  log <- tempfile("scwb-g7-install-", fileext = ".log")
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

.wb_g7_fixture_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_g7_bundle <- function() {
  root <- tempfile("scwb-g7-bundle-"); bundle <- wb_init_bundle(root)
  cells <- c("cell_2", "cell_10", "cell_1", "cell_3")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(12L), nrow = 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  list(root = root, bundle = bundle, cells = cells)
}

.wb_g7_expect <- function(expr, code = "PYBENCH_OUTPUT_INVALID") {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"),
    identical(as.character(error$code), code))
  invisible(error)
}

test_operation_pack_v3_g7_protocol_identity_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)
  cases <- Filter(function(x) startsWith(x$name, "g7_"), fixture$cases)
  stopifnot(length(cases) == 55L)
  for (item in cases) stopifnot(identical(
    .wb_operation_pack_sha256(item$preimage), item$identity$sha256))
  nonlex <- fixture$g7_positive_examples$union_nonlexicographic
  alternate <- fixture$g7_positive_examples$union_alternate_order
  stopifnot(identical(as.character(unlist(nonlex$member_axes[[1L]])),
      c("cell_2", "cell_10")),
    identical(as.character(unlist(nonlex$member_axes[[2L]])),
      c("cell_1", "cell_2")),
    identical(as.character(unlist(nonlex$declared_final_order)),
      c("cell_1", "cell_10", "cell_2")),
    !identical(nonlex$declaration$pack_declaration_identity,
      alternate$declaration$pack_declaration_identity),
    !identical(nonlex$sealed_axis$sealed_axis_identity,
      alternate$sealed_axis$sealed_axis_identity),
    !identical(nonlex$observation$observation_identity,
      alternate$observation$observation_identity),
    !identical(nonlex$receipt$receipt_identity,
      alternate$receipt$receipt_identity))
  case_map <- stats::setNames(cases, vapply(cases, `[[`, character(1),
    "name"))
  divergent_suffixes <- c("derivation", "sealed_axis",
    "vector_cardinality", "family_cardinality",
    "vector_observed_cardinality", "family_observed_cardinality",
    "vector_content", "family_content", "vector_payload",
    "vector_descriptor", "family_descriptor", "axis_observation",
    "receipt")
  for (suffix in divergent_suffixes) stopifnot(!identical(
    case_map[[paste0("g7_union_nonlexicographic_", suffix)]]$identity,
    case_map[[paste0("g7_union_alternate_order_", suffix)]]$identity))
  family_content <- case_map[[
    "g7_union_nonlexicographic_family_content"]]$preimage
  stopifnot(identical(as.character(unlist(family_content$key)),
      rep(c("score", "confidence"), each = 3L)),
    identical(as.character(unlist(family_content$cell_id)),
      rep(c("cell_1", "cell_10", "cell_2"), 2L)))

  schema_valid <- function(value, schema, definitions = list()) {
    root <- c(list(`$schema` = "https://json-schema.org/draft/2020-12/schema"),
      schema, if (length(definitions)) list(`$defs` = definitions) else list())
    isTRUE(.wb_json_schema_validate_2020(value, root)$ok)
  }
  request_schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-transition-request-v3.schema.json",
    simplifyVector = FALSE)
  receipt_schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-transition-receipt-v3.schema.json",
    simplifyVector = FALSE)
  manifest_schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-v3.schema.json", simplifyVector = FALSE)
  subset <- fixture$g7_positive_examples$subset
  union <- fixture$g7_positive_examples$union_nonlexicographic
  declaration_schema <- request_schema[["$defs"]]$
    derived_cell_output_axis_declaration
  stopifnot(schema_valid(subset$pack_declaration, declaration_schema,
      request_schema[["$defs"]]),
    schema_valid(union$declaration, declaration_schema,
      request_schema[["$defs"]]))
  invalid_subset <- subset$pack_declaration
  invalid_subset$member_selections <- list()
  invalid_mode <- subset$pack_declaration
  invalid_mode$derivation_mode <- "declared_ordered_unique_union_v1"
  invalid_empty <- subset$pack_declaration
  invalid_empty$final_cell_ids <- list()
  invalid_union <- union$declaration
  invalid_union$member_selections <- NULL
  stopifnot(!schema_valid(invalid_subset, declaration_schema,
      request_schema[["$defs"]]),
    !schema_valid(invalid_mode, declaration_schema,
      request_schema[["$defs"]]),
    !schema_valid(invalid_empty, declaration_schema,
      request_schema[["$defs"]]),
    !schema_valid(invalid_union, declaration_schema,
      request_schema[["$defs"]]))

  source_schema <- request_schema[["$defs"]]$
    derived_cell_source_axis_reference
  vector_source <- subset$grant$source_axes[[1L]]
  invalid_vector_source <- vector_source
  invalid_vector_source$source_axis_selector_identity <-
    vector_source$source_axis_reference_identity[c("scheme", "sha256")]
  invalid_family_source <- vector_source
  invalid_family_source$primitive_kind <- "cell_vector_family"
  invalid_family_source$projection <- "family_key_cell_axis_v1"
  stopifnot(schema_valid(vector_source, source_schema,
      request_schema[["$defs"]]),
    !schema_valid(invalid_vector_source, source_schema,
      request_schema[["$defs"]]),
    !schema_valid(invalid_family_source, source_schema,
      request_schema[["$defs"]]))

  axis_schema <- manifest_schema[["$defs"]]$operation$properties$
    derived_cell_output_axes$items
  invalid_axis <- subset$declaration
  invalid_axis$source$family_key_selector <- list(mode = "literal", key = "x")
  stopifnot(schema_valid(subset$declaration, axis_schema,
      manifest_schema[["$defs"]]),
    !schema_valid(invalid_axis, axis_schema, manifest_schema[["$defs"]]))

  grant <- union$grant
  request <- list(derived_cell_output_axis_grants = list(grant))
  attr(request, "operation_pack_v3_derived_axis_state") <- list(derived = list(
    cells = list(c("cell_2", "cell_10"), c("cell_1", "cell_2")),
    selectors = list(NULL, NULL), references = grant$source_axes))
  derivation <- .wb_operation_pack_v3_g7_seal(request,
    list(union$declaration))[[1L]]$derivation
  derivation_schema <- receipt_schema[["$defs"]]$
    derived_cell_axis_derivation
  wrong_derivation <- derivation
  wrong_derivation$derivation_mode <- "ordered_unique_subset_v1"
  stopifnot(schema_valid(derivation, derivation_schema,
      receipt_schema[["$defs"]]),
    !schema_valid(wrong_derivation, derivation_schema,
      receipt_schema[["$defs"]]))
  TRUE
}

test_operation_pack_v3_g7_seal_adversarial_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)$g7_positive_examples
  grant <- fixture$union_nonlexicographic$grant
  request <- list(derived_cell_output_axis_grants = list(grant))
  attr(request, "operation_pack_v3_derived_axis_state") <- list(derived = list(
    cells = list(c("cell_2", "cell_10"), c("cell_1", "cell_2")),
    selectors = list(NULL, NULL), references = grant$source_axes))
  good <- fixture$union_nonlexicographic$declaration
  sealed <- .wb_operation_pack_v3_g7_seal(request, list(good))[[1L]]
  alternate <- fixture$union_alternate_order$declaration
  alternate_sealed <- .wb_operation_pack_v3_g7_seal(request,
    list(alternate))[[1L]]
  empty_member <- wb_derived_cell_output_axis_declaration(grant,
    c("cell_2", "cell_1"), list(character(), c("cell_1", "cell_2")))
  empty_sealed <- .wb_operation_pack_v3_g7_seal(request,
    list(empty_member))[[1L]]
  stopifnot(identical(sealed$cells, c("cell_1", "cell_10", "cell_2")),
    identical(sealed$seal$status, "sealed"),
    !identical(sealed$seal$sealed_axis_identity,
      alternate_sealed$seal$sealed_axis_identity),
    identical(empty_sealed$cells, c("cell_2", "cell_1")))
  mutate <- function(value, fun) {
    value <- unserialize(serialize(value, NULL)); value <- fun(value)
    value$pack_declaration_identity <- NULL
    value$pack_declaration_identity <- .wb_operation_pack_v2_identity_scoped(
      value$schema,
      "derived cell output axis declaration excluding pack_declaration_identity",
      value)
    value
  }
  bad <- list(
    mutate(good, function(x) { x$member_selections[[1L]]$
      selected_cell_ids <- list("cell_10", "cell_2"); x }),
    mutate(good, function(x) { x$member_selections[[1L]]$
      selected_cell_ids <- list("foreign"); x }),
    mutate(good, function(x) { x$member_selections[[2L]]$
      selected_cell_ids <- list("cell_2", "cell_2"); x }),
    mutate(good, function(x) { x$member_selections <- x$member_selections[-2L]; x }),
    mutate(good, function(x) { x$member_selections[[2L]]$resolved_ordinal <- 1L; x }),
    mutate(good, function(x) { x$member_selections <- rev(x$member_selections); x }),
    mutate(good, function(x) { x$final_cell_ids <- list("cell_1", "cell_2"); x }),
    mutate(good, function(x) { x$final_cell_ids <- list("cell_1", "cell_2",
      "cell_2"); x }),
    mutate(good, function(x) { x$member_selections[[1L]]$selected_cell_ids <-
      list(); x$member_selections[[2L]]$selected_cell_ids <- list();
      x$final_cell_ids <- list("cell_1"); x }),
    mutate(good, function(x) { x$final_cell_ids <- list("cell_1", "cell_10",
      "cell_2", "foreign"); x }),
    mutate(good, function(x) { x$grant_identity <- list(scheme =
      "scworkbench.operation_pack.output_cardinality_grant.v1",
      sha256 = paste(rep("0", 64L), collapse = "")); x }))
  for (value in bad) .wb_g7_expect(
    .wb_operation_pack_v3_g7_seal(request, list(value)))
  .wb_g7_expect(.wb_operation_pack_v3_g7_seal(request, list()))
  .wb_g7_expect(.wb_operation_pack_v3_g7_seal(request, list(good, good)))
  .wb_g7_expect(.wb_operation_pack_v3_g7_seal(list(), list(good)))
  small <- request; small$derived_cell_output_axis_grants[[1L]]$limits$
    maximum_cells <- 2L
  .wb_g7_expect(.wb_operation_pack_v3_g7_seal(small, list(good)))
  TRUE
}

test_operation_pack_v3_g7_source_and_linked_output_adversarial_contract <-
    function() {
  examples <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)$g7_positive_examples
  grant <- examples$subset$grant
  request <- list(derived_cell_output_axis_grants = list(grant))
  attr(request, "operation_pack_v3_derived_axis_state") <- list(derived = list(
    cells = list(c("cell_2", "cell_10", "cell_1")), selectors = list(NULL),
    references = grant$source_axes))
  declare <- function(cells) wb_derived_cell_output_axis_declaration(grant,
    cells)
  for (cells in list(c("foreign"), c("cell_2", "cell_2"),
      c("cell_1", "cell_2"), character(),
      c("cell_2", "cell_10", "cell_1", "foreign")))
    .wb_g7_expect(.wb_operation_pack_v3_g7_seal(request,
      list(declare(cells))))
  complete <- .wb_operation_pack_v3_g7_seal(request,
    list(declare(c("cell_2", "cell_10", "cell_1"))))[[1L]]
  one <- .wb_operation_pack_v3_g7_seal(request,
    list(declare("cell_10")))[[1L]]
  stopifnot(complete$seal$final_cell_count == 3L,
    one$seal$final_cell_count == 1L)

  ordinary <- list(name = "vector", descriptor = list(kind = "cell_vector",
    grant_identity = list(scheme =
      "scworkbench.operation_pack.output_grant.v3",
      scope = "descriptor excluding grant_identity",
      sha256 = paste(rep("2", 64L), collapse = "")),
    derived_cell_output_axis_policy = list(schema =
        "scworkbench.operation_pack.derived_cell_linked_output_policy.v1",
      manifest_declaration_identity = grant$manifest_declaration_identity,
      derived_axis_name = "derived", shape = "one_per_cell",
      row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden",
      resolved_key_axis_policy_identity_or_null = NULL,
      resolved_key_axis = NULL, resolved_keys = NULL)))
  sealed_grant <- .wb_operation_pack_v3_g7_sealed_cardinality(ordinary,
    complete)
  good <- wb_prim_cell_vector(stats::setNames(1:3, complete$cells),
    value_type = "continuous")
  stopifnot(.wb_operation_pack_v3_g7_observe_cardinality(good,
    sealed_grant)$semantic_validation == "passed")
  omitted <- good; omitted$cell_id <- omitted$cell_id[-3L]
  foreign <- good; foreign$cell_id[[3L]] <- "foreign"
  reversed <- good; reversed$cell_id <- rev(reversed$cell_id)
  invalid <- list(omitted, foreign, reversed)
  for (value in invalid) .wb_g7_expect(
    .wb_operation_pack_v3_g7_observe_cardinality(value, sealed_grant))

  family_output <- ordinary
  family_output$name <- "family"; family_output$descriptor$kind <-
    "cell_vector_family"
  policy <- family_output$descriptor$derived_cell_output_axis_policy
  policy$shape <- "cell_key_cartesian"
  policy$row_order <- "key_major_then_sealed_cell_v1"
  policy$resolved_keys <- list("k1", "k2")
  policy$resolved_key_axis <- list(declaration = list(source =
      "declared_keys_with_optional_prefix_v1", keys = list("k1", "k2"),
    prefix_parameter = "prefix"), keys = list("k1", "k2"),
    resolution = list(source = "declared_keys_with_optional_prefix_v1",
      base_keys = list("k1", "k2"), prefix_parameter = "prefix",
      prefix_value = "", keys = list("k1", "k2")))
  policy$resolved_key_axis_policy_identity_or_null <-
    .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.resolved_key_axis_policy.v1",
      policy$resolved_key_axis)
  family_output$descriptor$derived_cell_output_axis_policy <- policy
  family_grant <- .wb_operation_pack_v3_g7_sealed_cardinality(family_output,
    complete)
  family <- wb_prim_cell_vector_family(rep(c("k1", "k2"), each = 3L),
    rep(complete$cells, 2L), 1:6)
  stopifnot(.wb_operation_pack_v3_g7_observe_cardinality(family,
    family_grant)$semantic_validation == "passed")
  missing <- family; missing$key <- missing$key[-3L]
  missing$cell_id <- missing$cell_id[-3L]; missing$value <- missing$value[-3L]
  extra <- family; extra$key[[6L]] <- "k3"
  reordered <- family; reordered$cell_id[c(1L, 2L)] <-
    reordered$cell_id[c(2L, 1L)]
  for (value in list(missing, extra, reordered)) .wb_g7_expect(
    .wb_operation_pack_v3_g7_observe_cardinality(value, family_grant))

  # Family-key projections fail closed for absent and duplicate logical axes.
  selector <- list(resolved_key = "lineage")
  family_source <- wb_prim_cell_vector_family(c("lineage", "lineage"),
    c("cell_2", "cell_2"), c(1, 2))
  .wb_g7_expect(.wb_operation_pack_v3_g7_project_cells(family_source,
    "family_key_cell_axis_v1", selector),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  selector$resolved_key <- "absent"
  .wb_g7_expect(.wb_operation_pack_v3_g7_project_cells(family_source,
    "family_key_cell_axis_v1", selector),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  operation <- list(inputs = list(list(name = "source", kind = "cell_vector",
    required = TRUE, alignment = "cell_ordered")),
    derived_cell_output_axes = list(list(name = "derived",
    source = list(mode = "static_input_axis", input = "source",
      projection = "cell_vector_axis_v1", family_key_selector = NULL))))
  current <- wb_prim_cell_vector(c(cell_2 = 1, cell_10 = 2, cell_1 = 3),
    value_type = "continuous")
  request$derived_cell_output_axis_grants[[1L]]$source_axes[[1L]]$
    input_descriptor_identity <- .wb_operation_pack_v3_unscoped_identity(
      .wb_operation_pack_v2_input_descriptor("source", current,
        operation$inputs[[1L]])$descriptor$descriptor_identity)
  stopifnot(isTRUE(.wb_operation_pack_v3_g7_sources_assert_current(operation,
    list(source = current), list(), request)))
  current$cell_id <- rev(current$cell_id)
  .wb_g7_expect(.wb_operation_pack_v3_g7_sources_assert_current(operation,
    list(source = current), list(), request),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  current <- wb_prim_cell_vector(c(cell_2 = 9, cell_10 = 2, cell_1 = 3),
    value_type = "continuous")
  .wb_g7_expect(.wb_operation_pack_v3_g7_sources_assert_current(operation,
    list(source = current), list(), request),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}

test_operation_pack_v3_g7_manifest_semantic_rejection_contract <- function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  index <- match("scwbv3phase5::derived_subset", vapply(manifest$operations,
    `[[`, character(1), "qualified_name"))
  reject <- function(change) {
    candidate <- unserialize(serialize(manifest, NULL))
    candidate$operations[[index]] <- change(candidate$operations[[index]])
    error <- tryCatch(wb_operation_pack_manifest_validate(candidate),
      error = identity)
    stopifnot(inherits(error, "wb_operation_pack_v3_error"))
  }
  reject(function(op) { op$outputs[[1L]]$required <- FALSE; op })
  reject(function(op) { op$derived_cell_output_axes[[1L]]$linked_outputs[[1L]]$
    name <- "absent"; op })
  reject(function(op) { op$derived_cell_output_axes[[2L]] <-
    op$derived_cell_output_axes[[1L]]; op$derived_cell_output_axes[[2L]]$name <-
      "second"; op$derived_cell_output_axes[[2L]]$declaration_identity <-
        .wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.derived_cell_output_axis.v1",
          "derived cell output axis declaration excluding declaration_identity",
          within(op$derived_cell_output_axes[[2L]],
            rm(declaration_identity))); op })
  reject(function(op) { op$outputs[[1L]]$kind <- "obs_table"; op })
  reject(function(op) { op$derived_cell_output_axes[[1L]]$limits$
    maximum_source_axes <- 65L; op })
  TRUE
}

test_operation_pack_v3_g7_subset_lifecycle_and_atomicity_contract <- function() {
  fixture <- .wb_g7_fixture_install(); state <- .wb_g7_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_g7_fixture_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  fit <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
      dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model"), created_by = "g7-contract")
  source_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "embedding"][[1L]]
  fit$session <- wb_session_discard(fit$session)
  run <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::derived_subset", inputs = list(
      source = wb_ref_artifact(source_id, "embedding"),
      selected_cells = c("cell_2", "cell_1"), key_prefix = "g7_",
      cell_set = "all", min_cells = 1L))
  transition <- run$run$operation_pack_transition
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    run$session$staging_bundle), transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  request <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    run$session$staging_bundle), transition$transition_id, "request.json"),
    simplifyVector = FALSE)
  vector_value <- wb_operation_pack_transition_load(
    run$session$staging_bundle, transition$transition_id, "vector")
  family_value <- wb_operation_pack_transition_load(
    run$session$staging_bundle, transition$transition_id, "family")
  observation <- receipt$derived_cell_output_axis_observations[[1L]]
  stopifnot(identical(observation$seal_status, "sealed"),
    identical(observation$final_cell_count, 2L),
    length(observation$linked_outputs) == 2L,
    identical(vector_value$cell_id, c("cell_2", "cell_1")),
    identical(family_value$cell_id,
      rep(c("cell_2", "cell_1"), 2L)),
    identical(family_value$key,
      rep(c("g7_score", "g7_confidence"), each = 2L)))
  stopifnot(isTRUE(.wb_operation_pack_v3_g7_receipt_audit(receipt, request)))
  repair_observation <- function(value) {
    value$observation_identity <- NULL
    value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      value$schema, "observation excluding observation_identity", value)
    value
  }
  mutate_receipt <- function(fun, repair = TRUE) {
    candidate <- unserialize(serialize(receipt, NULL))
    candidate$derived_cell_output_axis_observations[[1L]] <- fun(
      candidate$derived_cell_output_axis_observations[[1L]])
    if (repair) candidate$derived_cell_output_axis_observations[[1L]] <-
      repair_observation(candidate$derived_cell_output_axis_observations[[1L]])
    candidate
  }
  receipt_cases <- list(
    mutate_receipt(function(x) { x$linked_outputs <- x$linked_outputs[-2L]; x }),
    mutate_receipt(function(x) { x$linked_outputs[[2L]] <- x$linked_outputs[[1L]]; x }),
    mutate_receipt(function(x) { x$linked_outputs <- rev(x$linked_outputs); x }),
    mutate_receipt(function(x) { x$grant_identity$sha256 <-
      paste(rep("0", 64L), collapse = ""); x }),
    mutate_receipt(function(x) { x$final_cell_count <- 999L; x },
      repair = FALSE))
  for (candidate in receipt_cases) .wb_g7_expect(
    .wb_operation_pack_v3_g7_receipt_audit(candidate, request),
    "PYBENCH_RECEIPT_MISMATCH")
  forged_output <- unserialize(serialize(receipt, NULL))
  forged_output$outputs[[1L]]$descriptor$sealed_axis_identity$sha256 <-
    paste(rep("f", 64L), collapse = "")
  .wb_g7_expect(.wb_operation_pack_v3_g7_receipt_audit(forged_output,
    request), "PYBENCH_RECEIPT_MISMATCH")
  promoted_subset <- wb_session_promote_current(state$bundle, run$session,
    outputs = c("vector", "family"), created_by = "g7-contract")
  stopifnot(nrow(promoted_subset$promoted) == 2L,
    all(promoted_subset$promoted$status == "ok"))
  run$session <- wb_session_discard(run$session)

  before_artifacts <- nrow(wb_art_list(state$bundle))
  before_fingerprint <- .wb_manifest_registry_snapshot(state$bundle$con)$
    fingerprint
  before_store <- sort(list.files(.wb_operation_pack_v2_store(state$bundle),
    all.files = TRUE, no.. = TRUE))
  faults <- c(before_dispatch = "PYBENCH_PROCESS_FAILED",
    receipt_received = "PYBENCH_RECEIPT_MISMATCH",
    audited = "PYBENCH_OUTPUT_INVALID",
    before_publication = "PYBENCH_PUBLICATION_FAILED",
    published = "PYBENCH_PUBLICATION_FAILED")
  for (fault in names(faults)) {
    options(scworkbench.operation_pack_v2_test_hook = local({ target <- fault
      function(event, ...) if (identical(event, target)) stop("g7 fault") }))
    .wb_g7_expect(wb_session_run_op(wb_session_new(), state$bundle,
      "scwbv3phase5::derived_subset", inputs = list(
        source = wb_ref_artifact(source_id, "embedding"),
        selected_cells = c("cell_2", "cell_1"), key_prefix = "g7_",
        cell_set = "all", min_cells = 1L)), faults[[fault]])
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(nrow(wb_art_list(state$bundle)) == before_artifacts,
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$fingerprint,
        before_fingerprint),
      identical(sort(list.files(.wb_operation_pack_v2_store(state$bundle),
        all.files = TRUE, no.. = TRUE)), before_store))
  }
  declaration_failures <- list(
    list(field = "fault_after_first_output", code = "PYBENCH_PROCESS_FAILED"),
    list(field = "omit_declaration", code = "PYBENCH_OUTPUT_INVALID"),
    list(field = "repeat_declaration", code = "PYBENCH_OUTPUT_INVALID"))
  for (case in declaration_failures) {
    inputs <- list(source = wb_ref_artifact(source_id, "embedding"),
      selected_cells = c("cell_2", "cell_1"), key_prefix = "g7_",
      cell_set = "all", min_cells = 1L)
    inputs[[case$field]] <- TRUE
    .wb_g7_expect(wb_session_run_op(wb_session_new(), state$bundle,
      "scwbv3phase5::derived_subset", inputs = inputs), case$code)
    stopifnot(nrow(wb_art_list(state$bundle)) == before_artifacts,
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$fingerprint,
        before_fingerprint),
      identical(sort(list.files(.wb_operation_pack_v2_store(state$bundle),
        all.files = TRUE, no.. = TRUE)), before_store))
  }
  TRUE
}

test_operation_pack_v3_g7_union_lifecycle_contract <- function() {
  fixture <- .wb_g7_fixture_install(); state <- .wb_g7_bundle()
  on.exit({
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_g7_fixture_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  make_source <- function() {
    fit <- wb_session_run_op(wb_session_new(), state$bundle,
      "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
        dims = c(1L, 2L), cell_set = "all", min_cells = 1L))
    promoted <- wb_session_promote_current(state$bundle, fit$session,
      outputs = c("embedding", "model"), created_by = "g7-contract")
    fit$session <- wb_session_discard(fit$session)
    promoted$promoted$artifact_id[
      promoted$promoted$output == "embedding"][[1L]]
  }
  sources <- c(make_source(), make_source())
  items <- list(list(name = "left", order = 1,
      axis_ref = wb_ref_artifact(sources[[1L]], "embedding")),
    list(name = "right", order = 2,
      axis_ref = wb_ref_artifact(sources[[2L]], "embedding")))
  run <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3phase5::derived_union", inputs = list(items = items,
      member_selections = list(c("cell_2", "cell_10"),
        c("cell_2", "cell_1")),
      final_cells = c("cell_1", "cell_10", "cell_2"),
      cell_set = "all", min_cells = 1L))
  vector_value <- wb_operation_pack_transition_load(
    run$session$staging_bundle,
    run$run$operation_pack_transition$transition_id, "vector")
  stopifnot(identical(vector_value$cell_id,
    c("cell_1", "cell_10", "cell_2")))
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    run$session$staging_bundle),
    run$run$operation_pack_transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  stopifnot(identical(receipt$derived_cell_output_axis_observations[[1L]]$
    overlap_collapse_count, 1L))
  run$session <- wb_session_discard(run$session)
  TRUE
}
