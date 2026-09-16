.wb_registry_read_fixture <- function(with_sets = TRUE) {
  root <- tempfile("scwb_registry_read_bundle_")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- c("cell_2", "cell_1")
  features <- c("gene_c", "gene_a", "gene_b", "gene_d")
  wb_define_cells(bundle, cells)
  values <- Matrix::Matrix(matrix(seq_len(8), nrow = 4L,
    dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "RNA_counts", values, feature_type = "gene")
  if (isTRUE(with_sets)) {
    wb_feature_set_replace(bundle, "SET_B", "RNA_counts",
      c("gene_b", "gene_a"), namespace = "ns_beta", organism = "mouse",
      source_id = "source_beta", source_version = "2", origin = "fixture",
      recipe = list(n_genes_raw = 3L, method = "fixture"), is_readonly = TRUE,
      description = "Beta set", created_by = "contract", strict = TRUE)
    wb_feature_set_replace(bundle, "SET_A", "RNA_counts",
      c("gene_c", "gene_a", "gene_d"), namespace = "ns_alpha",
      organism = "mouse", source_id = "source_alpha", source_version = "1",
      origin = "fixture", recipe = list(n_genes_raw = 4L, method = "fixture"),
      is_readonly = TRUE, description = "Alpha set", created_by = "contract",
      strict = TRUE)
  }
  list(bundle = bundle, root = root, cells = cells, features = features)
}

.wb_registry_read_install <- function() {
  lib <- tempfile("scwb_registry_read_lib_")
  dir.create(lib, recursive = TRUE)
  log <- tempfile("scwb_registry_read_install_", fileext = ".log")
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v2-reference")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(source)), stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  old <- .libPaths(); .libPaths(c(lib, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV2Reference", lib.loc = lib)
  wb_operation_pack_activate(manifest, lib.loc = lib)
  list(lib = lib, old = old)
}

.wb_registry_read_cleanup <- function(fixture = NULL, installed = NULL) {
  try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE)
  if (!is.null(installed)) {
    if ("scwbV2Reference" %in% loadedNamespaces()) try(unloadNamespace("scwbV2Reference"), silent = TRUE)
    .libPaths(installed$old)
    unlink(installed$lib, recursive = TRUE, force = TRUE)
  }
  if (!is.null(fixture)) {
    try(wb_close_bundle(fixture$bundle), silent = TRUE)
    unlink(fixture$root, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

.wb_registry_read_declaration <- function(empty = "allow") list(
  name = "feature_sets",
  category = "authenticated_core_registry_snapshot",
  kind = "feature_set_registry",
  reader = "read_feature_set_registry",
  matrix_input = "matrix",
  namespace_parameter = "namespace",
  namespaces_parameter = "namespaces",
  feature_sets_parameter = "feature_sets",
  no_selector_policy = "all_namespaces",
  empty_match_policy = empty)

.wb_registry_read_inputs <- function() list(matrix = wb_prim_matrix("RNA_counts"))

.wb_registry_read_expect <- function(expr, code) {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(as.character(error$code), code))
  error
}

test_operation_pack_v2_feature_set_registry_snapshot_contract <- function() {
  fixture <- .wb_registry_read_fixture()
  on.exit(.wb_registry_read_cleanup(fixture), add = TRUE)
  resolve <- getFromNamespace(
    ".wb_operation_pack_v2_feature_set_registry_snapshot", "scworkbench")
  declaration <- .wb_registry_read_declaration()
  many <- resolve(fixture$bundle, declaration, .wb_registry_read_inputs(),
    list(namespace = NULL, namespaces = NULL, feature_sets = NULL))
  stopifnot(
    identical(many$matrix_id, "RNA_counts"),
    identical(unlist(many$feature_universe, use.names = FALSE), fixture$features),
    identical(vapply(many$sets, `[[`, character(1), "feature_set"),
      c("SET_A", "SET_B")),
    identical(vapply(many$sets[[1]]$memberships, `[[`, character(1), "feature_id"),
      c("gene_c", "gene_a", "gene_d")),
    identical(vapply(many$sets[[1]]$memberships, function(x) as.integer(x$rank), integer(1)),
      1:3),
    identical(many$sets[[1]]$source_id, "source_alpha"),
    grepl("n_genes_raw", many$sets[[1]]$recipe_json, fixed = TRUE)
  )
  one <- resolve(fixture$bundle, declaration, .wb_registry_read_inputs(),
    list(namespace = "ns_beta", namespaces = NULL, feature_sets = NULL))
  zero <- resolve(fixture$bundle, declaration, .wb_registry_read_inputs(),
    list(namespace = "missing", namespaces = NULL, feature_sets = NULL))
  stopifnot(length(one$sets) == 1L, identical(one$sets[[1]]$feature_set, "SET_B"),
    length(zero$sets) == 0L)
  again <- resolve(fixture$bundle, declaration, .wb_registry_read_inputs(),
    list(namespace = NULL, namespaces = c("ns_beta", "ns_alpha"), feature_sets = NULL))
  reordered <- resolve(fixture$bundle, declaration, .wb_registry_read_inputs(),
    list(namespace = NULL, namespaces = c("ns_alpha", "ns_beta"), feature_sets = NULL))
  identity <- getFromNamespace(".wb_operation_pack_sha256", "scworkbench")
  stopifnot(identical(identity(again), identity(reordered)))

  error_decl <- .wb_registry_read_declaration("error")
  .wb_registry_read_expect(resolve(fixture$bundle, error_decl,
    .wb_registry_read_inputs(), list(namespace = "missing", namespaces = NULL,
      feature_sets = NULL)), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  wrong <- list(matrix = wb_prim_matrix("not_a_matrix"))
  .wb_registry_read_expect(resolve(fixture$bundle, declaration, wrong,
    list(namespace = NULL, namespaces = NULL, feature_sets = NULL)),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  TRUE
}

test_operation_pack_v2_feature_set_registry_snapshot_negative_contract <- function() {
  fixture <- .wb_registry_read_fixture()
  on.exit(.wb_registry_read_cleanup(fixture), add = TRUE)
  resolve <- getFromNamespace(
    ".wb_operation_pack_v2_feature_set_registry_snapshot", "scworkbench")
  validate <- getFromNamespace(
    ".wb_operation_pack_v2_feature_set_registry_snapshot_validate", "scworkbench")
  snapshot <- resolve(fixture$bundle, .wb_registry_read_declaration(),
    .wb_registry_read_inputs(), list(namespace = NULL, namespaces = NULL,
      feature_sets = NULL))
  mutate_expect <- function(mutator) {
    value <- unserialize(serialize(snapshot, NULL, version = 3L))
    value <- mutator(value)
    .wb_registry_read_expect(validate(value), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  }
  mutate_expect(function(x) { x$sets[[2]]$feature_set <- x$sets[[1]]$feature_set; x })
  mutate_expect(function(x) { x$sets[[1]]$memberships[[2]]$feature_id <- x$sets[[1]]$memberships[[1]]$feature_id; x })
  mutate_expect(function(x) { x$sets[[1]]$memberships[[1]]$feature_id <- "foreign_gene"; x })
  mutate_expect(function(x) { x$sets[[1]]$memberships[[1]]$rank <- 2L; x })
  mutate_expect(function(x) { x$sets[[1]]$matrix_id <- "wrong_matrix"; x })
  mutate_expect(function(x) { x$sets <- rev(x$sets); x })
  TRUE
}

test_operation_pack_v2_feature_set_registry_identity_fixture_contract <- function() {
  corpus <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v2/identities.json",
    simplifyVector = FALSE)$feature_set_registry_examples
  validate <- getFromNamespace(
    ".wb_operation_pack_v2_feature_set_registry_snapshot_validate",
    "scworkbench")
  scoped <- getFromNamespace(".wb_operation_pack_v2_identity_scoped",
    "scworkbench")
  plain <- getFromNamespace(".wb_operation_pack_v2_identity_plain",
    "scworkbench")
  stopifnot(identical(vapply(corpus, `[[`, character(1), "name"),
    c("zero_selected_sets", "one_selected_set", "many_selected_sets")))
  for (entry in corpus) {
    snapshot <- validate(entry$snapshot)
    selection <- scoped("scworkbench.feature_set_registry.selection.v1",
      "normalized selector binding", snapshot$selection)
    stopifnot(
      identical(selection, entry$selection_identity),
      identical(scoped("scworkbench.feature_set_registry.snapshot.v1",
        "canonical matrix-bound registry snapshot", snapshot),
        entry$content_identity),
      identical(scoped("scworkbench.feature_set_registry.source.v1",
        "ordered registry source state", list(matrix_id = snapshot$matrix_id,
          feature_universe = snapshot$feature_universe, sets = snapshot$sets)),
        entry$source_identity),
      identical(plain("scworkbench.feature_order.v1",
        snapshot$feature_universe), entry$feature_order_identity),
      identical(scoped("scworkbench.provenance.ancestry.v1",
        "registry snapshot ancestry", list(matrix_input = "matrix",
          matrix_content_identity = entry$matrix_content_identity,
          selection_identity = selection)), entry$ancestry_identity)
    )
  }
  TRUE
}

test_operation_pack_v2_feature_set_registry_lifecycle_contract <- function() {
  fixture <- .wb_registry_read_fixture()
  installed <- .wb_registry_read_install()
  on.exit(.wb_registry_read_cleanup(fixture, installed), add = TRUE)
  run <- wb_session_run_op(wb_session_new(), fixture$bundle,
    "scwbv2reference::feature_set_registry_contract", inputs = list(
      matrix = wb_prim_matrix("RNA_counts"), namespace = "ns_alpha",
      cell_set = "all", min_cells = 1L))
  output <- run$run$outputs$summary
  stopifnot(nrow(output$table) == 1L,
    identical(output$table$feature_set[[1]], "SET_A"),
    identical(output$table$members[[1]], "gene_c,gene_a,gene_d"))
  transition_id <- as.character(run$run$operation_pack_transition$transition_id)[1]
  stopifnot(nzchar(transition_id))
  promoted <- wb_session_promote_current(fixture$bundle, run$session,
    name_prefix = "Registry read contract", outputs = "summary", fail_fast = TRUE)
  stopifnot(nrow(promoted$promoted) == 1L)
  record <- getFromNamespace(".wb_operation_pack_v2_record_validate", "scworkbench")(
    file.path(fixture$root, "operation_pack_v2", transition_id), load_payloads = TRUE)
  stopifnot(isTRUE(record$ok), length(record$request$registry_reads) == 1L,
    length(record$receipt$registry_reads) == 1L,
    identical(as.integer(record$receipt$registry_reads[[1]]$descriptor$use_count), 1L))
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  saved_pack <- registry$packs$scwbv2reference
  saved_operations <- registry$operations[saved_pack$operation_names]
  detach_pack <- function() {
    for (name in saved_pack$operation_names) registry$operations[[name]] <- NULL
    registry$packs$scwbv2reference <- NULL
  }
  restore_pack <- function() {
    registry$packs$scwbv2reference <- saved_pack
    for (name in names(saved_operations)) {
      registry$operations[[name]] <- saved_operations[[name]]
    }
  }
  on.exit(restore_pack(), add = TRUE)
  detach_pack()
  wb_finalize_recipient_bundle(fixture$bundle)
  wb_close_bundle(fixture$bundle)
  fixture$bundle <- wb_open_bundle(fixture$root, read_only = TRUE)
  validation <- wb_bundle_validation_report(fixture$root, level = "recipient")
  stopifnot(isTRUE(validation$ok))
  registry_reads <- wb_operation_pack_transition_registry_reads(
    fixture$bundle, transition_id)
  stopifnot(identical(names(registry_reads), "feature_sets"),
    inherits(registry_reads$feature_sets$snapshot,
      "wb_operation_pack_feature_set_registry"),
    identical(registry_reads$feature_sets$snapshot$sets[[1]]$feature_set,
      "SET_A"),
    identical(as.integer(
      registry_reads$feature_sets$observation$use_count), 1L))
  loaded <- wb_art_load(fixture$bundle, promoted$promoted$artifact_id[[1]],
    expected_kind = "obs_table")
  stopifnot(identical(loaded$table$feature_set[[1]], "SET_A"))
  restore_pack()
  TRUE
}

test_operation_pack_v2_feature_set_registry_fail_closed_contract <- function() {
  fixture <- .wb_registry_read_fixture()
  installed <- .wb_registry_read_install()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    .wb_registry_read_cleanup(fixture, installed)
  }, add = TRUE)
  execute <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")
  bind <- getFromNamespace(".wb_operation_pack_v2_bind_inputs", "scworkbench")
  inputs <- bind(fixture$bundle, .wb_registry_read_inputs(), fixture$cells)
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  op_name <- "scwbv2reference::feature_set_registry_contract"
  original <- registry$packs$scwbv2reference$registration$runners[[op_name]]
  set_runner <- function(runner) {
    pack <- registry$packs$scwbv2reference
    pack$registration$runners[[op_name]] <- runner
    registry$packs$scwbv2reference <- pack
  }
  transition_root <- file.path(fixture$root, "operation_pack_v2")
  assert_no_residue <- function() {
    entries <- if (dir.exists(transition_root)) list.dirs(transition_root,
      recursive = FALSE, full.names = TRUE) else character()
    stopifnot(!length(entries))
  }
  set_runner(function(readers, writers, params, context) {
    writers$write_terminal_primitive("summary", wb_prim_obs_table(
      data.frame(ok = TRUE), "synthetic_feature_set_registry_summary"))
  })
  .wb_registry_read_expect(execute(fixture$bundle, op_name, inputs,
    list(namespace = NULL, namespaces = NULL, feature_sets = NULL)),
    "PYBENCH_CAPABILITY_MISMATCH")
  assert_no_residue()
  set_runner(function(readers, writers, params, context) {
    readers$feature_sets(); readers$feature_sets()
    writers$write_terminal_primitive("summary", wb_prim_obs_table(
      data.frame(ok = TRUE), "synthetic_feature_set_registry_summary"))
  })
  .wb_registry_read_expect(execute(fixture$bundle, op_name, inputs,
    list(namespace = NULL, namespaces = NULL, feature_sets = NULL)),
    "PYBENCH_CAPABILITY_MISMATCH")
  assert_no_residue()
  set_runner(original)

  source_mutations <- list(
    metadata = list(
      sql = paste("UPDATE feature_sets SET description = ?",
        "WHERE matrix_id = ? AND feature_set = ?;"),
      change = list("changed after preflight", "RNA_counts", "SET_A"),
      restore = list("Alpha set", "RNA_counts", "SET_A")),
    membership = list(
      sql = paste("UPDATE feature_set_membership SET feature_id = ?",
        "WHERE matrix_id = ? AND feature_set = ? AND feature_id = ?;"),
      change = list("gene_b", "RNA_counts", "SET_A", "gene_d"),
      restore = list("gene_d", "RNA_counts", "SET_A", "gene_b")),
    rank = list(
      sql = paste("UPDATE feature_set_membership SET rank = ?",
        "WHERE matrix_id = ? AND feature_set = ? AND feature_id = ?;"),
      change = list(7L, "RNA_counts", "SET_A", "gene_d"),
      restore = list(3L, "RNA_counts", "SET_A", "gene_d"))
  )
  for (mutation in source_mutations) {
    mutated <- FALSE
    options(scworkbench.operation_pack_v2_test_hook = local({
      current <- mutation
      function(event, ...) {
        if (identical(event, "staged") && !mutated) {
          DBI::dbExecute(fixture$bundle$con, current$sql,
            params = current$change)
          mutated <<- TRUE
        }
      }
    }))
    .wb_registry_read_expect(execute(fixture$bundle, op_name, inputs,
      list(namespace = NULL, namespaces = NULL, feature_sets = NULL)),
      "PYBENCH_INPUT_IDENTITY_MISMATCH")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    assert_no_residue()
    DBI::dbExecute(fixture$bundle$con, mutation$sql,
      params = mutation$restore)
  }
  retry <- execute(fixture$bundle, op_name, inputs,
    list(namespace = NULL, namespaces = NULL, feature_sets = NULL))
  stopifnot(identical(retry$state, "reopened"),
    length(retry$receipt$registry_reads) == 1L)
  copy <- function(x) unserialize(serialize(x, NULL, version = 3L))
  scoped <- getFromNamespace(".wb_operation_pack_v2_identity_scoped",
    "scworkbench")
  request_audit <- getFromNamespace(".wb_operation_pack_v2_request_audit",
    "scworkbench")
  receipt_audit <- getFromNamespace(".wb_operation_pack_v2_receipt_audit",
    "scworkbench")
  registration <- registry$packs$scwbv2reference$registration
  operation <- registry$operations[[op_name]]$definition$v2_definition
  preflight <- getFromNamespace(".wb_operation_pack_v2_preflight",
    "scworkbench")(operation, inputs,
      list(namespace = NULL, namespaces = NULL, feature_sets = NULL),
      registration = registration)
  before_forgery_audits <- .wb_manifest_registry_snapshot(fixture$bundle$con)

  malformed <- copy(retry$request)
  malformed$registry_reads[[1]]$descriptor$source_identity <- NULL
  .wb_registry_read_expect(getFromNamespace(
    ".wb_operation_pack_v2_schema_assert", "scworkbench")(
      malformed, "request", "PYBENCH_CAPABILITY_MISMATCH"),
    "PYBENCH_CAPABILITY_MISMATCH")

  forged_request <- copy(retry$request)
  forged_request$registry_reads[[1]]$descriptor$content_identity$sha256 <-
    strrep("0", 64L)
  forged_request$registry_reads[[1]]$descriptor$descriptor_identity <- NULL
  forged_request$registry_reads[[1]]$descriptor$descriptor_identity <- scoped(
    "scworkbench.operation_pack.registry_read_descriptor.v2",
    "descriptor excluding descriptor_identity",
    forged_request$registry_reads[[1]]$descriptor)
  forged_request$execution_capability$reader_grants[[2]]$descriptor_identity <-
    forged_request$registry_reads[[1]]$descriptor$descriptor_identity
  forged_request$execution_capability$capability_identity <- NULL
  forged_request$execution_capability$capability_identity <- scoped(
    "scworkbench.operation_pack.capability.v2",
    "capability excluding capability_identity",
    forged_request$execution_capability)
  forged_request$request_identity <- NULL
  forged_request$request_identity <- scoped(
    "scworkbench.operation_pack.transition_request.v2",
    "request excluding request_identity", forged_request)
  stopifnot(isTRUE(request_audit(forged_request, registration, operation)))
  .wb_registry_read_expect(getFromNamespace(
    ".wb_operation_pack_v2_registry_reads_assert_current", "scworkbench")(
      fixture$bundle, operation, inputs,
      list(namespace = NULL, namespaces = NULL, feature_sets = NULL),
      forged_request$registry_reads), "PYBENCH_INPUT_IDENTITY_MISMATCH")

  forged_receipt <- copy(retry$receipt)
  forged_receipt$registry_reads[[1]]$descriptor$content_identity$sha256 <-
    strrep("f", 64L)
  observed <- forged_receipt$registry_reads[[1]]$descriptor
  observed$observed_descriptor_identity <- NULL
  observed$observed_descriptor_identity <- scoped(
    "scworkbench.operation_pack.observed_registry_read.v2",
    "descriptor excluding observed_descriptor_identity", observed)
  forged_receipt$registry_reads[[1]]$descriptor <- observed
  forged_receipt$receipt_identity <- NULL
  forged_receipt$receipt_identity <- scoped(
    "scworkbench.operation_pack.transition_receipt.v2",
    "receipt excluding receipt_identity", forged_receipt)
  .wb_registry_read_expect(receipt_audit(forged_receipt, retry$request,
    registration, operation, preflight), "PYBENCH_RECEIPT_MISMATCH")
  stopifnot(identical(before_forgery_audits,
    .wb_manifest_registry_snapshot(fixture$bundle$con)))
  TRUE
}
