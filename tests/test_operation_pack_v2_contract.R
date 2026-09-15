.wb_v2_fixture_install <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  lib <- tempfile("scwb_v2_fixture_lib_")
  dir.create(lib, recursive = TRUE)
  log <- tempfile("scwb_v2_fixture_install_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)),
    shQuote(file.path(root, "tests", "fixtures", "operation-pack-v2-reference"))),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"), call. = FALSE)
  old <- .libPaths(); .libPaths(c(lib, old))
  list(lib = lib, old = old,
    manifest = system.file("scworkbench", "operation-pack.json", package = "scwbV2Reference", lib.loc = lib))
}

.wb_v2_fixture_install_v1 <- function(lib) {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  log <- tempfile("scwb_v1_fixture_install_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)),
    shQuote(file.path(root, "tests", "fixtures", "operation-pack-second"))),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"), call. = FALSE)
  system.file("scworkbench", "operation-pack.json",
    package = "scworkbenchOperationPackFixture", lib.loc = lib)
}

.wb_v2_fixture_cleanup <- function(fixture, include_v1 = FALSE) {
  for (package in c("scwbV2Reference",
      if (isTRUE(include_v1)) "scworkbenchOperationPackFixture" else character())) {
    if (package %in% loadedNamespaces()) try(unloadNamespace(package), silent = TRUE)
  }
  .libPaths(fixture$old)
  unlink(fixture$lib, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_v2_fixture_inputs <- function(provider = "stats") {
  make <- function(kind, ...) structure(c(list(kind = kind), list(...)), class = "wb_primitive")
  list(
    matrix = make("matrix", values = matrix(1, 1, 1), dimensions = c(1L, 1L),
      cell_id = "cell_1", feature_id = "feature_1", storage_profile = "matrix_ordinary_v1",
      meta = list(genome_provider = provider)),
    space = make("space", values = matrix(1, 1, 1), dimensions = c(1L, 1L),
      cell_id = "cell_1", storage_profile = "space_dense_v1"),
    space_2d = make("space_2d", values = matrix(c(0, 1), 1, 2), dimensions = c(1L, 2L),
      cell_id = "cell_1", storage_profile = "space_2d_dense_v1"),
    model_ref = make("model_ref", engine = "synthetic", model_space_id = "space",
      in_space_id = "matrix", payload_tree = list(a = "b")),
    cell_vector = wb_prim_cell_vector(stats::setNames("a", "cell_1"), meta = list(input = TRUE)),
    cell_vector_family = wb_prim_cell_vector_family("k", "cell_1", 1, meta = list(input = TRUE)),
    relation_family = wb_prim_relation_family("k", "cell_1", value = 1, meta = list(input = TRUE)),
    feature_table = wb_prim_feature_table(data.frame(feature_id = "feature_1"), table_type = "input"),
    obs_table = wb_prim_obs_table(data.frame(value = 1), table_type = "input"),
    path_2d_family = wb_prim_path_2d_family("p", 1L, 0, 1, meta = list(input = TRUE)),
    space_path_family = wb_prim_space_path_family("space", "p", 1L, 1L, 0, meta = list(input = TRUE)))
}

.wb_v2_expect_error <- function(expr, code, phase = NULL) {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"), identical(as.character(error$code), code))
  if (!is.null(phase)) stopifnot(identical(as.character(error$phase), phase))
  invisible(error)
}

.wb_v2_copy <- function(x) unserialize(serialize(x, NULL, version = 3L))

.wb_v2_pointer_parts <- function(pointer) {
  if (identical(pointer, "")) return(character())
  parts <- strsplit(sub("^/", "", pointer), "/", fixed = TRUE)[[1]]
  gsub("~1", "/", gsub("~0", "~", parts, fixed = TRUE), fixed = TRUE)
}

.wb_v2_pointer_get <- function(x, pointer) {
  for (part in .wb_v2_pointer_parts(pointer)) {
    index <- suppressWarnings(as.integer(part))
    x <- if (!is.na(index) && is.null(names(x))) x[[index + 1L]] else x[[part]]
  }
  x
}

.wb_v2_pointer_set <- function(x, pointer, value, remove = FALSE) {
  parts <- .wb_v2_pointer_parts(pointer)
  recurse <- function(node, i) {
    key <- parts[[i]]; index <- suppressWarnings(as.integer(key))
    slot <- if (!is.na(index) && is.null(names(node))) index + 1L else key
    if (i == length(parts)) {
      if (isTRUE(remove)) node[[slot]] <- NULL else node[[slot]] <- value
    } else node[[slot]] <- recurse(node[[slot]], i + 1L)
    node
  }
  recurse(x, 1L)
}

test_operation_pack_v2_manifest_admission_contract <- function() {
  schema <- jsonlite::read_json("inst/protocol/operation-pack-v2.schema.json", simplifyVector = FALSE)
  before_packs <- wb_operation_packs(); before_ops <- wb_list_ops(); before_catalog <- wb_operation_catalog_identity()
  for (recipe in schema[["x-semantic-negative-fixtures"]]) {
    value <- .wb_v2_copy(schema$examples[[as.integer(recipe$base_example) + 1L]])
    pointer_value <- .wb_v2_pointer_get(value, recipe$pointer)
    if (identical(recipe$mutation, "replace")) value <- .wb_v2_pointer_set(value, recipe$pointer, recipe$value)
    if (identical(recipe$mutation, "append_modified_copy")) {
      copy <- .wb_v2_copy(pointer_value)
      for (name in names(recipe$changes)) copy[[name]] <- recipe$changes[[name]]
      parent <- sub("/[0-9]+$", "", recipe$pointer)
      array <- .wb_v2_pointer_get(value, parent); array[[length(array) + 1L]] <- copy
      value <- .wb_v2_pointer_set(value, parent, array)
    }
    error <- .wb_v2_expect_error(wb_operation_pack_manifest_validate(value),
      recipe$expected_code, recipe$expected_stage)
    stopifnot(identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
      identical(wb_operation_catalog_identity(), before_catalog))
  }
  text <- paste(readLines("tests/fixtures/operation-pack-v2-reference/inst/scworkbench/operation-pack.json", warn = FALSE), collapse = "\n")
  duplicate <- sub('"schema_version": "scworkbench.operation_pack.v2",',
    '"schema_version": "scworkbench.operation_pack.v2", "schema_version": "scworkbench.operation_pack.v2",', text, fixed = TRUE)
  path <- tempfile(fileext = ".json"); writeLines(duplicate, path, useBytes = TRUE)
  .wb_v2_expect_error(wb_operation_pack_manifest_validate(path),
    "OPERATION_PACK_MANIFEST_PARSE_INVALID", "parse")
  TRUE
}

test_operation_pack_v2_outer_schema_exhaustive_contract <- function() {
  schema <- jsonlite::read_json("inst/protocol/operation-pack-v2.schema.json", simplifyVector = FALSE)
  validate <- getFromNamespace(".wb_json_schema_validate_2020", "scworkbench")
  input_branches <- schema[["$defs"]]$input$oneOf
  output_branches <- schema[["$defs"]]$output$oneOf
  input_tuples <- lapply(input_branches, function(x) c(kind = x$properties$kind$const,
    alignment = x$properties$alignment$const))
  output_tuples <- lapply(output_branches, function(x) c(category = x$properties$category$const,
    kind = x$properties$kind$const, storage_profile = x$properties$storage_profile$const))
  input_kinds <- unique(vapply(input_tuples, `[[`, character(1), "kind"))
  alignments <- unique(vapply(input_tuples, `[[`, character(1), "alignment"))
  input_invalid <- 0L
  for (kind in input_kinds) for (alignment in alignments) {
    legal <- any(vapply(input_tuples, function(x) identical(unname(x), c(kind, alignment)), logical(1)))
    candidate <- list(name = "input", kind = kind, required = TRUE, alignment = alignment)
    ok <- validate(candidate, schema[["$defs"]]$input, schema)$ok
    stopifnot(identical(ok, legal)); if (!legal) input_invalid <- input_invalid + 1L
  }
  categories <- unique(vapply(output_tuples, `[[`, character(1), "category"))
  kinds <- unique(vapply(output_tuples, `[[`, character(1), "kind"))
  profiles <- unique(vapply(output_tuples, `[[`, character(1), "storage_profile"))
  output_invalid <- 0L
  for (category in categories) for (kind in kinds) for (profile in profiles) {
    legal <- any(vapply(output_tuples, function(x) identical(unname(x), c(category, kind, profile)), logical(1)))
    candidate <- list(name = "output", category = category, kind = kind,
      storage_profile = profile, allocated_id_key = "output_id", required = TRUE,
      promotion_group = "group")
    if (identical(category, "materialization")) candidate$materialized_by_terminals <- list("terminal")
    if (kind %in% c("cell_vector", "cell_vector_family")) candidate$value_kind <- "continuous"
    if (kind %in% c("feature_table", "obs_table")) candidate$table_type <- "fixture"
    ok <- validate(candidate, schema[["$defs"]]$output, schema)$ok
    stopifnot(identical(ok, legal)); if (!legal) output_invalid <- output_invalid + 1L
  }
  stopifnot(input_invalid == 66L, output_invalid == 345L)
  input_removals <- 0L
  for (branch in input_branches) for (field in as.character(unlist(branch$required))) {
    candidate <- list(name = "input", kind = branch$properties$kind$const, required = TRUE,
      alignment = branch$properties$alignment$const); candidate[[field]] <- NULL
    stopifnot(!validate(candidate, schema[["$defs"]]$input, schema)$ok); input_removals <- input_removals + 1L
  }
  output_removals <- 0L
  for (branch in output_branches) {
    candidate <- list(name = "output", category = branch$properties$category$const,
      kind = branch$properties$kind$const, storage_profile = branch$properties$storage_profile$const,
      allocated_id_key = "output_id", required = TRUE, promotion_group = "group")
    if (identical(candidate$category, "materialization")) candidate$materialized_by_terminals <- list("terminal")
    if (candidate$kind %in% c("cell_vector", "cell_vector_family")) candidate$value_kind <- "continuous"
    if (candidate$kind %in% c("feature_table", "obs_table")) candidate$table_type <- "fixture"
    for (field in as.character(unlist(branch$required))) {
      removed <- candidate; removed[[field]] <- NULL
      stopifnot(!validate(removed, schema[["$defs"]]$output, schema)$ok); output_removals <- output_removals + 1L
    }
  }
  stopifnot(input_removals == 44L, output_removals == 105L)
  TRUE
}

test_operation_pack_v2_atomic_activation_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  stopifnot(length(wb_list_ops()) == 53L)
  before_packs <- wb_operation_packs(); before_ops <- wb_list_ops()
  before_identity <- wb_operation_catalog_identity()
  boundaries <- c("catalog_before_pack", "catalog_pack_installed",
    "catalog_operation_installed", "catalog_before_commit")
  for (boundary in boundaries) {
    fired <- FALSE
    options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
      if (!fired && identical(event, boundary)) { fired <<- TRUE; stop(paste0("injected ", boundary)) }
    })
    on.exit(options(scworkbench.operation_pack_v2_test_hook = NULL), add = TRUE)
    .wb_v2_expect_error(wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib),
      "OPERATION_PACK_CATALOG_PUBLICATION_FAILED", "catalog_publication")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(fired, identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
      identical(wb_operation_catalog_identity(), before_identity))
  }
  activated <- wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  stopifnot(nrow(wb_operation_packs()) == 1L, length(wb_list_ops()) == 55L,
    identical(activated$identity$pack_abi_version, "2"))
  wb_operation_pack_unload("scwbv2reference")
  stopifnot(identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_operation_catalog_identity(), before_identity))
  TRUE
}

test_operation_pack_v2_reference_lifecycle_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  before_count <- length(wb_list_ops())
  activated <- wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  stopifnot(identical(activated$identity$pack_abi_version, "2"),
    length(wb_list_ops()) == before_count + 2L)
  dir <- tempfile("scwb_v2_bundle_")
  bundle <- wb_init_bundle(dir)
  result <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")(
    bundle, "scwbv2reference::all_contracts", .wb_v2_fixture_inputs(), list())
  stopifnot(identical(result$state, "reopened"), length(result$outputs) == 14L,
    length(result$registry_requests) == 1L,
    nrow(wb_operation_pack_transition_outputs(bundle, result$transition_id)) == 15L)
  wb_close_bundle(bundle)
  writable <- wb_open_bundle(dir)
  wb_finalize_recipient_bundle(writable)
  wb_close_bundle(writable)
  read_only <- wb_open_bundle(dir, read_only = TRUE)
  inventory <- wb_operation_pack_transition_outputs(read_only, result$transition_id)
  stopifnot(nrow(inventory) == 15L, setequal(unique(inventory$storage_profile), c(
    "matrix_ordinary_v1", "matrix_backed_chunked_v1", "space_dense_v1",
    "space_file_backed_hdf5_v1", "space_2d_dense_v1",
    "model_ref_contained_tree_v1", "terminal_primitive_v1",
    "path_2d_family_v1", "space_path_family_v1", "cell_set_admission_v1")))
  value <- wb_operation_pack_transition_load(read_only, result$transition_id, "cell_vector")
  stopifnot(inherits(value, "wb_primitive"), identical(value$kind, "cell_vector"),
    identical(value$meta$fixture, "v2"))
  wb_close_bundle(read_only)
  tree_identity <- function(root) {
    files <- sort(list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE,
      include.dirs = FALSE, no.. = TRUE), method = "radix")
    getFromNamespace(".wb_operation_pack_sha256", "scworkbench")(list(
      path = substring(files, nchar(root) + 2L),
      bytes = vapply(files, digest::digest, character(1), file = TRUE,
        algo = "sha256", serialize = FALSE)))
  }
  before <- tree_identity(dir)
  report <- wb_bundle_validation_report(dir, level = "recipient")
  stopifnot(isTRUE(report$ok), identical(before, tree_identity(dir)),
    identical(report$pre_validation_fingerprint, report$post_validation_fingerprint))
  payload <- file.path(dir, "operation_pack_v2", result$transition_id,
    "outputs", "cell_vector", "payload.rds")
  con <- file(payload, open = "ab"); writeBin(charToRaw("mutation"), con); close(con)
  corrupt <- wb_bundle_validation_report(dir, level = "recipient")
  stopifnot(!isTRUE(corrupt$ok), "OPERATION_PACK_V2_RECIPIENT_INVALID" %in% corrupt$diagnostics$code)
  TRUE
}

test_operation_pack_v2_dynamic_dependency_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  bundle <- wb_init_bundle(tempfile("scwb_v2_dynamic_"))
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  execute <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")
  inputs <- .wb_v2_fixture_inputs()
  ok <- execute(bundle, "scwbv2reference::dynamic_provider", list(matrix = inputs$matrix), list())
  stopifnot(length(ok$receipt$runtime_attestation$dynamic_resolutions) == 1L,
    identical(ok$receipt$runtime_attestation$dynamic_resolutions[[1]]$provider_name, "stats"))
  bad <- inputs$matrix; bad$meta$genome_provider <- ""
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider",
    list(matrix = bad), list()), "OPERATION_PACK_DYNAMIC_PROVIDER_INVALID", "preflight")
  missing <- inputs$matrix; missing$meta$genome_provider <- "Package.That.Does.Not.Exist"
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider",
    list(matrix = missing), list()), "OPERATION_PACK_DEPENDENCY_MISSING", "preflight")
  TRUE
}

test_operation_pack_v2_transition_atomicity_and_binding_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  bundle <- wb_init_bundle(tempfile("scwb_v2_atomic_"))
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  execute <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")
  state <- function() getFromNamespace(".wb_manifest_registry_snapshot", "scworkbench")(bundle$con)$fingerprint
  before <- state(); input <- list(matrix = .wb_v2_fixture_inputs()$matrix)
  events <- list(
    resolved = c("OPERATION_PACK_PREFLIGHT_FAILED", "preflight"),
    preflighted = c("OPERATION_PACK_PREFLIGHT_FAILED", "preflight"),
    staged = c("PYBENCH_PROCESS_FAILED", "execution"),
    before_dispatch = c("PYBENCH_PROCESS_FAILED", "execution"),
    receipt_received = c("PYBENCH_RECEIPT_MISMATCH", "receipt"),
    audited = c("PYBENCH_OUTPUT_INVALID", "audit"),
    before_publication = c("PYBENCH_PUBLICATION_FAILED", "publication"),
    published = c("PYBENCH_PUBLICATION_FAILED", "publication"),
    before_reopened = c("PYBENCH_REOPEN_VALIDATION_FAILED", "reopen"),
    reopened = c("PYBENCH_REOPEN_VALIDATION_FAILED", "reopen"))
  for (event in names(events)) {
    options(scworkbench.operation_pack_v2_test_hook = local({ target <- event; function(event, ...) {
      if (identical(event, target)) stop(paste0("injected ", target))
    }}))
    .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider", input, list()),
      events[[event]][[1]], events[[event]][[2]])
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(identical(state(), before), !dir.exists(file.path(bundle$dir, "operation_pack_v2")))
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event, transition_id, ...) {
    if (identical(event, "published")) {
      path <- file.path(bundle$dir, "operation_pack_v2", transition_id, "outputs", "provider", "payload.rds")
      con <- file(path, open = "ab"); on.exit(close(con)); writeBin(charToRaw("corruption"), con)
    }
  })
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider", input, list()),
    "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(identical(state(), before), !dir.exists(file.path(bundle$dir, "operation_pack_v2")))

  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  pack <- registry$packs$scwbv2reference
  original <- pack$registration$runners[["scwbv2reference::dynamic_provider"]]
  set_runner <- function(runner) {
    current <- registry$packs$scwbv2reference
    current$registration$runners[["scwbv2reference::dynamic_provider"]] <- runner
    registry$packs$scwbv2reference <- current
  }
  partial <- function(readers, writers, params, context) invisible(list(status = "partial"))
  set_runner(partial)
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider", input, list()),
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  wrong <- function(readers, writers, params, context) {
    writers$write_space("provider", readers$matrix()); invisible(NULL)
  }
  set_runner(wrong)
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider", input, list()),
    "PYBENCH_CAPABILITY_MISMATCH", "execution")
  wrong_dimensions <- function(readers, writers, params, context) {
    writers$write_terminal_primitive("provider", wb_prim_cell_vector(
      stats::setNames(c("a", "b"), c("cell_1", "cell_2"))))
  }
  set_runner(wrong_dimensions)
  .wb_v2_expect_error(execute(bundle, "scwbv2reference::dynamic_provider", input, list()),
    "PYBENCH_OUTPUT_INVALID", "audit")
  set_runner(original)
  stopifnot(identical(state(), before), !dir.exists(file.path(bundle$dir, "operation_pack_v2")))

  result <- execute(bundle, "scwbv2reference::dynamic_provider", input, list())
  registration <- registry$packs$scwbv2reference$registration
  operation <- registration$manifest$operations[[2]]
  request_audit <- getFromNamespace(".wb_operation_pack_v2_request_audit", "scworkbench")
  bad_request <- .wb_v2_copy(result$request)
  bad_request$operation_authentication$name <- "other::operation"
  bad_request$request_identity <- NULL
  bad_request$request_identity <- getFromNamespace(".wb_operation_pack_v2_identity_scoped", "scworkbench")(
    "scworkbench.operation_pack.transition_request.v2", "request excluding request_identity", bad_request)
  .wb_v2_expect_error(request_audit(bad_request, registration, operation),
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  receipt_audit <- getFromNamespace(".wb_operation_pack_v2_receipt_audit", "scworkbench")
  preflight <- getFromNamespace(".wb_operation_pack_v2_preflight", "scworkbench")(operation, input, list())
  bad_receipt <- .wb_v2_copy(result$receipt)
  bad_receipt$request_identity$sha256 <- paste(rep("0", 64), collapse = "")
  bad_receipt$receipt_identity <- NULL
  bad_receipt$receipt_identity <- getFromNamespace(".wb_operation_pack_v2_identity_scoped", "scworkbench")(
    "scworkbench.operation_pack.transition_receipt.v2", "receipt excluding receipt_identity", bad_receipt)
  .wb_v2_expect_error(receipt_audit(bad_receipt, result$request, registration, operation, preflight),
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  TRUE
}

test_operation_pack_v2_interrupted_recovery_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  dir <- tempfile("scwb_v2_recovery_"); bundle <- wb_init_bundle(dir)
  execute <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")
  result <- execute(bundle, "scwbv2reference::dynamic_provider",
    list(matrix = .wb_v2_fixture_inputs()$matrix), list())
  receipt_identity <- result$receipt$receipt_identity
  state_path <- file.path(result$path, "state.json")
  jsonlite::write_json(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "published", transition_id = result$transition_id,
    receipt_identity = receipt_identity), state_path, auto_unbox = TRUE, pretty = TRUE)
  pending <- file.path(dir, "operation_pack_v2", ".pending", "interrupted")
  dir.create(pending, recursive = TRUE); writeLines("private", file.path(pending, "partial"))
  wb_close_bundle(bundle)
  recovered <- wb_open_bundle(dir)
  state <- jsonlite::read_json(state_path, simplifyVector = FALSE)
  stopifnot(identical(state$state, "reopened"), !dir.exists(pending),
    nrow(wb_operation_pack_transition_outputs(recovered, result$transition_id)) == 1L)
  getFromNamespace(".wb_operation_pack_v2_recover", "scworkbench")(recovered)
  stopifnot(length(setdiff(list.dirs(file.path(dir, "operation_pack_v2"), recursive = FALSE,
    full.names = FALSE), ".pending")) == 1L)
  wb_close_bundle(recovered)
  TRUE
}

test_operation_pack_v2_protocol_identity_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v2/identities.json", simplifyVector = FALSE)
  hash_file <- getFromNamespace(".wb_operation_pack_v2_file_sha256", "scworkbench")
  id <- getFromNamespace(".wb_operation_pack_v2_id", "scworkbench")
  validate <- getFromNamespace(".wb_json_schema_validate_2020", "scworkbench")
  files <- c(
    "operation-pack-v2.schema.json",
    "operation-pack-transition-request-v2.schema.json",
    "operation-pack-transition-receipt-v2.schema.json")
  for (file in files) {
    path <- file.path("inst/protocol", file)
    stopifnot(identical(hash_file(path), fixture$files[[file]]))
    schema <- jsonlite::read_json(path, simplifyVector = FALSE)
    stopifnot(identical(schema[["$schema"]], "https://json-schema.org/draft/2020-12/schema"))
    for (example in schema$examples) stopifnot(isTRUE(validate(example, schema, schema)$ok))
  }
  manifest <- jsonlite::read_json(file.path("inst/protocol", files[[1]]), simplifyVector = FALSE)
  for (expected in fixture$manifest_examples) {
    value <- getFromNamespace(".wb_operation_pack_v2_normalize", "scworkbench")(
      manifest$examples[[as.integer(expected$index)]])
    stopifnot(identical(id("scworkbench.operation_pack.manifest.v2", value)$sha256,
      expected$manifest_sha256))
    for (name in names(expected$definitions)) stopifnot(identical(
      id("scworkbench.operation_pack.definition.v2",
        value$operations[[match(name, vapply(value$operations, `[[`, character(1), "qualified_name"))]])$sha256,
      expected$definitions[[name]]))
  }
  for (entry in list(
    list(file = files[[2]], key = "request_identity", expected = fixture$request_examples),
    list(file = files[[3]], key = "receipt_identity", expected = fixture$receipt_examples))) {
    schema <- jsonlite::read_json(file.path("inst/protocol", entry$file), simplifyVector = FALSE)
    observed <- vapply(schema$examples, function(value) {
      identity <- value[[entry$key]]; value[[entry$key]] <- NULL
      getFromNamespace(".wb_operation_pack_v2_identity_scoped", "scworkbench")(
        identity$scheme, identity$scope, value)$sha256
    }, character(1))
    stopifnot(identical(unname(observed), unlist(entry$expected, use.names = FALSE)))
  }
  TRUE
}

test_operation_pack_v2_v1_coexistence_and_order_contract <- function() {
  v2 <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(v2, include_v1 = TRUE), add = TRUE)
  v1_manifest <- .wb_v2_fixture_install_v1(v2$lib)
  activate <- function(order) {
    for (abi in order) {
      if (abi == "1") wb_operation_pack_activate(v1_manifest, lib.loc = v2$lib)
      else wb_operation_pack_activate(v2$manifest, lib.loc = v2$lib)
    }
    stopifnot(length(wb_list_ops()) == 56L, nrow(wb_operation_packs()) == 2L)
    identity <- wb_operation_catalog_identity()
    for (pack in rev(order)) {
      wb_operation_pack_unload(if (pack == "1") "scwbfixture" else "scwbv2reference")
    }
    stopifnot(length(wb_list_ops()) == 53L)
    identity
  }
  first <- activate(c("1", "2"))
  second <- activate(c("2", "1"))
  stopifnot(identical(first, second))
  TRUE
}

test_operation_pack_v2_optional_dependency_and_capability_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  operation <- .wb_v2_copy(registry$packs$scwbv2reference$registration$manifest$operations[[2]])
  operation$dependencies[[1]] <- list(requirement_id = "optional_missing", kind = "r_package",
    name = "Package.That.Does.Not.Exist", version = list(specifier = ">=1"), disposition = "optional",
    selected_when = list(parameter = "use_optional", equals = TRUE))
  preflight <- getFromNamespace(".wb_operation_pack_v2_preflight", "scworkbench")
  input <- list(matrix = .wb_v2_fixture_inputs()$matrix)
  unselected <- preflight(operation, input, list(use_optional = FALSE))
  stopifnot(identical(unselected$dispositions$optional_missing$status, "not_selected"))
  .wb_v2_expect_error(preflight(operation, input, list(use_optional = TRUE)),
    "OPERATION_PACK_DEPENDENCY_MISSING", "preflight")
  dynamic_operation <- registry$packs$scwbv2reference$registration$manifest$operations[[2]]
  resolved <- preflight(dynamic_operation, input, list())
  changed <- input
  changed$matrix$meta$genome_provider <- "utils"
  .wb_v2_expect_error(getFromNamespace(".wb_operation_pack_v2_dynamic_reread", "scworkbench")(
    dynamic_operation, changed, resolved), "OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED", "dispatch")

  retained_writer <- NULL
  original <- registry$packs$scwbv2reference$registration$runners[["scwbv2reference::dynamic_provider"]]
  replacement <- function(readers, writers, params, context) {
    retained_writer <<- writers$write_terminal_primitive
    original(readers, writers, params, context)
  }
  current <- registry$packs$scwbv2reference
  current$registration$runners[["scwbv2reference::dynamic_provider"]] <- replacement
  registry$packs$scwbv2reference <- current
  bundle <- wb_init_bundle(tempfile("scwb_v2_lease_"))
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")(
    bundle, "scwbv2reference::dynamic_provider", input, list())
  .wb_v2_expect_error(retained_writer("provider", wb_prim_cell_vector(
    stats::setNames("late", "cell_1"))), "PYBENCH_CAPABILITY_MISMATCH", "execution")
  TRUE
}

test_operation_pack_v2_transition_schema_exhaustive_contract <- function() {
  fixture <- .wb_v2_fixture_install()
  on.exit(.wb_v2_fixture_cleanup(fixture), add = TRUE)
  wb_operation_pack_activate(fixture$manifest, lib.loc = fixture$lib)
  on.exit(try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE), add = TRUE)
  bundle <- wb_init_bundle(tempfile("scwb_v2_schema_"))
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  result <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")(
    bundle, "scwbv2reference::all_contracts", .wb_v2_fixture_inputs(), list())
  request_schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-transition-request-v2.schema.json", simplifyVector = FALSE)
  receipt_schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-transition-receipt-v2.schema.json", simplifyVector = FALSE)
  validate <- getFromNamespace(".wb_json_schema_validate_2020", "scworkbench")
  stopifnot(length(result$request$inputs) == 11L, length(result$request$outputs) == 15L,
    length(result$receipt$outputs) == 14L, length(result$receipt$registry_requests) == 1L)

  for (entry in result$request$inputs) {
    descriptor <- entry$descriptor
    stopifnot(isTRUE(validate(descriptor, request_schema[["$defs"]]$input_descriptor,
      request_schema)$ok))
    branch <- Filter(function(x) identical(x$properties$kind$const, descriptor$kind),
      request_schema[["$defs"]]$input_descriptor$oneOf)[[1]]
    for (field in as.character(unlist(branch$required, use.names = FALSE))) {
      bad <- descriptor; bad[[field]] <- NULL
      stopifnot(!validate(bad, request_schema[["$defs"]]$input_descriptor,
        request_schema)$ok)
    }
  }

  grants <- lapply(result$request$outputs, `[[`, "descriptor")
  legal <- unique(vapply(grants, function(x) paste(x$category, x$kind,
    x$storage_profile, x$writer, sep = "|"), character(1)))
  fields <- lapply(c("category", "kind", "storage_profile", "writer"), function(field)
    unique(vapply(grants, `[[`, character(1), field)))
  names(fields) <- c("category", "kind", "storage_profile", "writer")
  for (category in fields$category) for (kind in fields$kind)
    for (profile in fields$storage_profile) for (writer in fields$writer) {
      candidate <- .wb_v2_copy(grants[[1]])
      candidate$category <- category; candidate$kind <- kind
      candidate$storage_profile <- profile; candidate$writer <- writer
      candidate$grant_identity <- getFromNamespace(".wb_operation_pack_v2_identity_scoped", "scworkbench")(
        "scworkbench.operation_pack.output_grant.v2", "descriptor excluding grant_identity",
        within(.wb_v2_copy(candidate), rm(grant_identity)))
      expected <- paste(category, kind, profile, writer, sep = "|") %in% legal
      # Tuple validity is tested after restoring a real branch-shaped record;
      # arbitrary cross-branch fields must never make an invalid tuple valid.
      observed <- validate(candidate, request_schema[["$defs"]]$output_descriptor,
        request_schema)$ok
      if (!expected) stopifnot(!observed)
    }
  for (descriptor in grants) stopifnot(isTRUE(validate(descriptor,
    request_schema[["$defs"]]$output_descriptor, request_schema)$ok))
  receipt_descriptors <- lapply(result$receipt$outputs, `[[`, "descriptor")
  for (descriptor in receipt_descriptors) stopifnot(isTRUE(validate(descriptor,
    receipt_schema[["$defs"]]$observed_output_descriptor, receipt_schema)$ok))
  registry_descriptor <- result$receipt$registry_requests[[1]]$descriptor
  stopifnot(isTRUE(validate(registry_descriptor,
    receipt_schema[["$defs"]]$registry_request_descriptor, receipt_schema)$ok))
  TRUE
}
