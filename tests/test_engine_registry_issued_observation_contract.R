.engine_registry_issued_fixture <- function() {
  root <- tempfile("registry_issued_"); bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1"); features <- c("g2", "g1", "g3")
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(1:6, 3L,
    dimnames = list(features, cells)), sparse = TRUE), feature_type = "gene")
  input <- wb_prim_matrix("RNA"); input$cell_id <- cells
  input$feature_id <- features; input$dimensions <- c(3L, 2L)
  inputs <- list(matrix = input)
  descriptor <- scworkbench:::.wb_operation_pack_v2_input_descriptor("matrix", input,
    list(name = "matrix", kind = "matrix", required = TRUE,
      alignment = "cell_and_feature_ordered"))$descriptor
  operation <- list(outputs = list(), registry_reads = list(list(name = "annotations",
    category = "authenticated_core_registry_snapshot", kind = "matrix_feature_annotations",
    reader = "read_matrix_feature_annotations", matrix_input = "matrix",
    fields = list("feature_type"), row_order = "matrix_feature_order_v1",
    missing_annotation_policy = "preserve_null", call_discipline = "single_use")))
  stage <- file.path(root, "private_stage"); dir.create(stage)
  made <- scworkbench:::.wb_operation_pack_v3_registry_read_records(bundle, operation,
    inputs, list(matrix = descriptor), list(), stage, cells, "session", "run",
    "ephemeral", NULL)
  request <- list(registry_reads = made$records, outputs = list(),
    inputs = list(list(name = "matrix", descriptor = descriptor)),
    execution_capability = list(source_state_identity = NULL))
  attr(request, "operation_pack_v3_registry_observations") <- made$observations
  list(root = root, bundle = bundle, cells = cells, operation = operation,
    inputs = inputs, request = request, made = made, stage = stage)
}
.engine_registry_issued_close <- function(f) {
  try(wb_close_bundle(f$bundle), silent = TRUE)
  unlink(f$root, recursive = TRUE, force = TRUE)
}
.engine_registry_issued_check <- function(f, request = f$request, operation = f$operation) {
  scworkbench:::.wb_operation_pack_v3_registry_reads_assert_current(f$bundle,
    operation, f$inputs, list(), request, f$cells, "session", "run", "ephemeral")
}
.engine_registry_issued_spy <- function() {
  ns <- asNamespace("scworkbench"); counts <- new.env(parent = emptyenv())
  names <- c(".wb_operation_pack_v3_feature_annotation_snapshot",
    ".wb_operation_pack_v3_registry_snapshot_identities")
  originals <- setNames(lapply(names, get, envir = ns), names)
  for (name in names) local({
    key <- name; original <- originals[[key]]; counts[[key]] <- 0L
    wrapper <- function(...) { counts[[key]] <- counts[[key]] + 1L; original(...) }
    unlockBinding(key, ns); assign(key, wrapper, ns); lockBinding(key, ns)
  })
  restore <- function() for (name in names) {
    unlockBinding(name, ns); assign(name, originals[[name]], ns); lockBinding(name, ns)
  }
  list(counts = counts, restore = restore)
}

test_engine_registry_issued_fresh_reads_and_recovery_contract <- function() {
  f <- .engine_registry_issued_fixture(); on.exit(.engine_registry_issued_close(f), add = TRUE)
  spy <- .engine_registry_issued_spy(); on.exit(spy$restore(), add = TRUE, after = FALSE)
  for (i in 1:2) stopifnot(isTRUE(.engine_registry_issued_check(f)))
  stopifnot(spy$counts[[".wb_operation_pack_v3_feature_annotation_snapshot"]] == 2L,
    spy$counts[[".wb_operation_pack_v3_registry_snapshot_identities"]] == 0L)
  recovered <- f$request; attr(recovered, "operation_pack_v3_registry_observations") <- NULL
  stopifnot(identical(scworkbench:::.wb_operation_pack_canonical_json(f$request),
    scworkbench:::.wb_operation_pack_canonical_json(recovered)))
  for (i in 1:2) stopifnot(isTRUE(.engine_registry_issued_check(f, recovered)))
  stopifnot(spy$counts[[".wb_operation_pack_v3_feature_annotation_snapshot"]] == 4L,
    spy$counts[[".wb_operation_pack_v3_registry_snapshot_identities"]] == 2L)
  # Uncertain private evidence must not suppress independent recomputation.
  uncertain <- f$request
  attr(uncertain, "operation_pack_v3_registry_observations")$annotations$snapshot$rows <- list()
  stopifnot(isTRUE(.engine_registry_issued_check(f, uncertain)),
    spy$counts[[".wb_operation_pack_v3_registry_snapshot_identities"]] == 3L)
  TRUE
}

test_engine_registry_issued_changes_reject_and_retry_contract <- function() {
  f <- .engine_registry_issued_fixture(); on.exit(.engine_registry_issued_close(f), add = TRUE)
  counts <- function() c(runs = DBI::dbGetQuery(f$bundle$con,
    "SELECT COUNT(*) n FROM prov_runs;")$n, artifacts = DBI::dbGetQuery(f$bundle$con,
    "SELECT COUNT(*) n FROM artifacts;")$n)
  inherited <- counts()
  reject <- function(request = f$request, operation = f$operation) {
    error <- tryCatch(.engine_registry_issued_check(f, request, operation), error = identity)
    stopifnot(inherits(error, "wb_operation_pack_error"),
      identical(error$code, "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  }
  for (field in c("source_identity", "content_identity")) {
    changed <- f$request
    changed$registry_reads[[1L]]$descriptor[[field]]$sha256 <- strrep("0", 64L)
    reject(changed)
  }
  changed <- f$request
  changed$inputs[[1L]]$descriptor$content_identity$sha256 <- strrep("1", 64L)
  reject(changed)
  operation <- f$operation; operation$registry_reads[[1L]]$fields <- list("foreign")
  reject(operation = operation)
  # A real SQL mutation cannot hide behind an unchanged private observation.
  DBI::dbBegin(f$bundle$con)
  DBI::dbExecute(f$bundle$con, "UPDATE features SET feature_type='peak' WHERE feature_id='g2';")
  reject()
  DBI::dbRollback(f$bundle$con)
  stopifnot(isTRUE(.engine_registry_issued_check(f)))
  # Even a self-rehashed expectation for the wrong rows is checked against the
  # actual fresh snapshot; private bindings cannot authorize it.
  wrong <- f$made$values$annotations; wrong$rows <- rev(wrong$rows)
  wrong$feature_order_identity <- scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.feature_order.v1", lapply(wrong$rows, `[[`, "feature_id"))
  ids <- scworkbench:::.wb_operation_pack_v3_registry_snapshot_identities(wrong,
    "matrix_feature_annotations")
  changed <- f$request
  changed$registry_reads[[1L]]$descriptor$content_identity <- ids$content
  changed$registry_reads[[1L]]$descriptor$source_identity <- ids$source
  reject(changed)
  stopifnot(isTRUE(.engine_registry_issued_check(f)),
    identical(counts(), inherited))
  TRUE
}

test_engine_registry_issued_callback_isolation_contract <- function() {
  f <- .engine_registry_issued_fixture(); on.exit(.engine_registry_issued_close(f), add = TRUE)
  adapter <- scworkbench:::.wb_operation_pack_v2_capability_adapter(f$request,
    f$operation, list(), f$stage, bundle = f$bundle, registry_read_values = f$made$values)
  delivered <- adapter$readers$annotations()
  delivered$rows[[1L]]$values$feature_type <- "mutated_by_pack"
  stopifnot(identical(f$made$values$annotations$rows[[1L]]$values$feature_type, "gene"),
    identical(attr(f$request, "operation_pack_v3_registry_observations")$
      annotations$snapshot$rows[[1L]]$values$feature_type, "gene"),
    isTRUE(.engine_registry_issued_check(f)))
  duplicate <- try(adapter$readers$annotations(), silent = TRUE)
  stopifnot(inherits(duplicate, "try-error"))
  TRUE
}
