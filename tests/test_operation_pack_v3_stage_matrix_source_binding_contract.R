.wb_g2_stage_matrix_fixture <- function() {
  root <- tempfile("g2-stage-source-")
  bundle <- wb_init_bundle(root)
  cells <- c("cell_2", "cell_10", "cell_1")
  features <- c("gene_2", "gene_1")
  wb_define_cells(bundle, cells)
  values <- matrix(c(1, 2, 3, 4, 5, 6), nrow = 2L,
    dimnames = list(features, cells))
  wb_attach_matrix(bundle, "RNA_counts", Matrix::Matrix(values,
    sparse = TRUE), layer = "counts", feature_type = "gene")
  list(root = root, bundle = bundle, cells = cells,
    features = features, values = values)
}

.wb_g2_stage_matrix_close <- function(fixture, staged = NULL) {
  if (!is.null(staged))
    try(wb_session_discard(staged$session), silent = TRUE)
  try(wb_close_bundle(fixture$bundle), silent = TRUE)
  unlink(fixture$root, recursive = TRUE, force = TRUE)
}

.wb_g2_reference_pack_install <- function() {
  library <- tempfile("g2-reference-pack-")
  dir.create(library)
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v3-reference")
  log <- tempfile("g2-reference-install-", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)),
    stdout = log, stderr = log)
  if (!identical(as.integer(status), 0L)) stop(paste(readLines(log,
    warn = FALSE), collapse = "\n"), call. = FALSE)
  old <- .libPaths()
  .libPaths(c(library, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Reference", lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  list(library = library, old = old)
}

.wb_g2_reference_pack_close <- function(installed) {
  try(wb_operation_pack_unload("scwbv3reference"), silent = TRUE)
  if ("scwbV3Reference" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Reference"), silent = TRUE)
  .libPaths(installed$old)
  unlink(installed$library, recursive = TRUE, force = TRUE)
}

.wb_g2_source_only_state <- function(bundle) {
  count <- function(table) as.integer(DBI::dbGetQuery(bundle$con,
    paste0("SELECT COUNT(*) AS n FROM ", table))$n[[1L]])
  store <- file.path(bundle$dir, "operation_pack_v2")
  list(artifacts = count("artifacts"), runs = count("prov_runs"),
    run_outputs = count("prov_run_outputs"),
    materializations = count("prov_materializations"),
    spaces = count("spaces"),
    transitions = if (dir.exists(store)) sort(list.files(store,
      recursive = TRUE, all.files = TRUE, no.. = TRUE)) else character())
}

.wb_g2_replace_stage_matrix <- function(stage, matrix_id,
    forge_checksum = FALSE) {
  row <- wb_matrices(stage)
  relative <- as.character(row$path[as.character(row$matrix_id) == matrix_id])
  stopifnot(length(relative) == 1L)
  target <- file.path(stage$dir, relative)
  values <- as.matrix(wb_matrix(stage, matrix_id))
  values[1L, 1L] <- values[1L, 1L] + 1
  unlink(target, recursive = TRUE)
  BPCells::write_matrix_dir(Matrix::Matrix(values, sparse = TRUE), target)
  if (isTRUE(forge_checksum))
    writeLines(.wb_prov_sha256_file(file.path(target, "val")),
      file.path(target, "local_checksum.sha256"))
  stopifnot(identical(as.matrix(wb_slice(stage, matrix_id)), values))
  invisible(TRUE)
}

.wb_g2_stage_matrix_grant <- function(stage, matrix_id) {
  observed <- .wb_operation_pack_v3_matrix_consumed_identity(stage,
    matrix_id)
  identity <- list(scheme = observed$content_identity_scheme,
    sha256 = observed$content_sha256)
  state <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.scientific_state.v1",
    .wb_manifest_registry_snapshot(stage$con))
  list(name = "chunks", input_content_identity = identity,
    source_reference = list(source_kind = "bundle_matrix",
      matrix_id = matrix_id, input_content_identity = identity,
      transition_source_state_identity = state))
}

test_operation_pack_v3_stage_matrix_committed_and_predecessor_contract <-
    function() {
  fixture <- .wb_g2_stage_matrix_fixture()
  staged <- NULL
  on.exit(.wb_g2_stage_matrix_close(fixture, staged), add = TRUE)
  staged <- .wb_session_stage_bundle(fixture$bundle, wb_session_new())
  original <- .wb_prov_payload_identity(fixture$bundle,
    wb_prim_matrix("RNA_counts"))
  observed <- .wb_operation_pack_v3_matrix_consumed_identity(staged$bundle,
    "RNA_counts")
  stopifnot(identical(observed$content_identity_scheme,
      original$content_identity_scheme),
    identical(observed$content_sha256, original$content_sha256),
    identical(as.matrix(wb_slice(staged$bundle, "RNA_counts")),
      fixture$values))
  predecessor <- fixture$values + 7
  wb_attach_matrix(staged$bundle, "stage_only_counts",
    Matrix::Matrix(predecessor, sparse = TRUE), layer = "counts",
    feature_type = "gene")
  stopifnot(!"stage_only_counts" %in%
      as.character(wb_matrices(fixture$bundle)$matrix_id),
    "stage_only_counts" %in%
      as.character(wb_matrices(staged$bundle)$matrix_id))
  stage_identity <- .wb_operation_pack_v3_matrix_consumed_identity(
    staged$bundle, "stage_only_counts")
  durable_identity <- .wb_prov_payload_identity(staged$bundle,
    wb_prim_matrix("stage_only_counts"))
  stopifnot(identical(stage_identity$content_sha256,
      durable_identity$content_sha256),
    identical(as.matrix(wb_slice(staged$bundle, "stage_only_counts")),
      predecessor))
  TRUE
}

test_operation_pack_v3_stage_only_predecessor_typed_read_contract <-
    function() {
  installed <- .wb_g2_reference_pack_install()
  on.exit(.wb_g2_reference_pack_close(installed), add = TRUE)
  fixture <- .wb_g2_stage_matrix_fixture()
  staged <- NULL
  on.exit(.wb_g2_stage_matrix_close(fixture, staged), add = TRUE)
  staged <- .wb_session_stage_bundle(fixture$bundle, wb_session_new())
  wb_attach_matrix(staged$bundle, "stage_only_counts",
    Matrix::Matrix(fixture$values + 7, sparse = TRUE), layer = "counts",
    feature_type = "gene")
  result <- wb_session_run_op(staged$session, fixture$bundle,
    "scwbv3reference::chunked_family", inputs = list(
      matrix = "stage_only_counts", cell_set = "all", min_cells = 1L,
      features = list(signal = as.list(fixture$features)),
      name = "stage", chunk_size = 2L))
  stopifnot(identical(sort(names(result$run$outputs)),
      c("scores", "summary")),
    identical(as.character(result$run$inputs$user_inputs$matrix),
      "stage_only_counts"),
    !"stage_only_counts" %in%
      as.character(wb_matrices(fixture$bundle)$matrix_id))
  result$session <- wb_session_discard(result$session)
  staged <- NULL
  TRUE
}

test_operation_pack_v3_stage_matrix_payload_and_checksum_rejection_contract <-
    function() {
  fixture <- .wb_g2_stage_matrix_fixture()
  staged <- NULL
  on.exit(.wb_g2_stage_matrix_close(fixture, staged), add = TRUE)
  staged <- .wb_session_stage_bundle(fixture$bundle, wb_session_new())
  stage <- staged$bundle
  grant <- .wb_g2_stage_matrix_grant(stage, "RNA_counts")
  .wb_operation_pack_v3_typed_slice_grant_assert_current(stage, grant)
  relative <- as.character(wb_matrices(stage)$path[[1L]])
  target <- file.path(stage$dir, relative)
  source_file <- file.path(fixture$root, relative, "val")
  source_sha <- .wb_prov_sha256_file(source_file)
  stopifnot(nzchar(Sys.readlink(file.path(target, "val"))))
  changed <- as.matrix(wb_matrix(stage, "RNA_counts"))
  changed[1L, 1L] <- changed[1L, 1L] + 1
  unlink(target, recursive = TRUE)
  BPCells::write_matrix_dir(Matrix::Matrix(changed, sparse = TRUE), target)
  # A forged local checksum sidecar must not replace the grant's observed
  # fragment-tree identity, even when it matches the modified payload file.
  writeLines(.wb_prov_sha256_file(file.path(target, "val")),
    file.path(target, "local_checksum.sha256"))
  stopifnot(identical(.wb_prov_sha256_file(source_file), source_sha),
    identical(as.matrix(wb_slice(stage, "RNA_counts")), changed))
  rejection <- tryCatch(
    .wb_operation_pack_v3_typed_slice_grant_assert_current(stage, grant),
    error = base::identity)
  stopifnot(inherits(rejection, "error"),
    identical(as.character(rejection$code),
      "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  TRUE
}

test_operation_pack_v3_stage_matrix_registry_and_broker_contract <-
    function() {
  fixture <- .wb_g2_stage_matrix_fixture()
  staged <- NULL
  broker <- NULL
  source <- NULL
  on.exit({
    if (!is.null(broker)) try(wb_close_bundle(broker), silent = TRUE)
    if (!is.null(source)) try(wb_close_bundle(source), silent = TRUE)
    .wb_g2_stage_matrix_close(fixture, staged)
  }, add = TRUE)
  staged <- .wb_session_stage_bundle(fixture$bundle, wb_session_new())
  stage <- staged$bundle
  broker <- .wb_operation_pack_v3_broker_open_bundle(stage$dir)
  source <- .wb_operation_pack_v3_broker_open_bundle(fixture$root)
  broker$staging_source_bundle <- source
  committed <- .wb_g2_stage_matrix_grant(stage, "RNA_counts")
  stopifnot(identical(.wb_operation_pack_v3_broker_source(broker, "",
      committed, fixture$features, fixture$cells), fixture$values))
  predecessor <- fixture$values + 7
  wb_attach_matrix(stage, "stage_only_counts",
    Matrix::Matrix(predecessor, sparse = TRUE), layer = "counts",
    feature_type = "gene")
  stage_only <- .wb_g2_stage_matrix_grant(stage, "stage_only_counts")
  stopifnot(identical(.wb_operation_pack_v3_broker_source(broker, "",
      stage_only, fixture$features, fixture$cells), predecessor))
  .wb_g2_replace_stage_matrix(stage, "RNA_counts")
  rejection <- tryCatch(.wb_operation_pack_v3_broker_source(broker, "",
    committed, fixture$features, fixture$cells), error = base::identity)
  stopifnot(inherits(rejection, "error"),
    identical(as.character(rejection$code),
      "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  # Change only a registry field; intact BPCells bytes no longer authorize
  # either grant because the exact scientific-state snapshot has changed.
  DBI::dbExecute(stage$con, paste0("UPDATE matrices SET description = ",
    "'registry-only change' WHERE matrix_id = 'stage_only_counts'"))
  rejection <- tryCatch(.wb_operation_pack_v3_broker_source(broker, "",
    stage_only, fixture$features, fixture$cells), error = base::identity)
  stopifnot(inherits(rejection, "error"),
    identical(as.character(rejection$code),
      "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  TRUE
}

test_operation_pack_v3_stage_matrix_between_reads_and_publication_contract <-
    function() {
  installed <- .wb_g2_reference_pack_install()
  on.exit(.wb_g2_reference_pack_close(installed), add = TRUE)
  fixture <- .wb_g2_stage_matrix_fixture()
  active <- NULL
  on.exit({options(scworkbench.operation_pack_v2_test_hook = NULL,
      scworkbench.operation_pack_v3_typed_slice_test_hook = NULL);
    if (!is.null(active)) try(wb_session_discard(active), silent = TRUE);
    .wb_g2_stage_matrix_close(fixture)}, add = TRUE)
  baseline <- .wb_g2_source_only_state(fixture$bundle)
  run <- function(session) wb_session_run_op(session, fixture$bundle,
    "scwbv3reference::chunked_family", inputs = list(
      matrix = "RNA_counts", cell_set = "all", min_cells = 1L,
      features = list(signal = as.list(fixture$features)),
      name = "source", chunk_size = 2L))
  for (mode in c("between_reads", "before_publication")) {
    staged <- .wb_session_stage_bundle(fixture$bundle, wb_session_new())
    active <- staged$session
    injected <- FALSE
    mutate <- function() {
      .wb_g2_replace_stage_matrix(staged$bundle, "RNA_counts",
        forge_checksum = TRUE)
      injected <<- TRUE
    }
    if (identical(mode, "between_reads"))
      options(scworkbench.operation_pack_v3_typed_slice_test_hook =
        function(name, read_index) {
          if (identical(name, "matrix_chunks") &&
              identical(as.integer(read_index), 1L)) mutate()
        })
    else options(scworkbench.operation_pack_v2_test_hook =
      function(event, ...) {
        if (identical(event, "audited")) mutate()
      })
    failure <- tryCatch(run(active), error = base::identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL,
      scworkbench.operation_pack_v3_typed_slice_test_hook = NULL)
    stopifnot(isTRUE(injected), inherits(failure, "error"),
      identical(as.character(failure$code), if (identical(mode,
        "between_reads")) "PYBENCH_PROCESS_FAILED" else
        "PYBENCH_INPUT_IDENTITY_MISMATCH"),
      grepl("Typed-slice source changed after authentication",
        conditionMessage(failure), fixed = TRUE),
      identical(.wb_g2_source_only_state(fixture$bundle), baseline))
    stage_dir <- active$staging_dir
    active <- wb_session_discard(active)
    stopifnot(!dir.exists(stage_dir),
      identical(.wb_g2_source_only_state(fixture$bundle), baseline))
  }
  retry <- run(wb_session_new())
  stopifnot(identical(sort(names(retry$run$outputs)),
      c("scores", "summary")),
    identical(.wb_g2_source_only_state(fixture$bundle), baseline))
  retry$session <- wb_session_discard(retry$session)
  TRUE
}
