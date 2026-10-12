test_graph_matrix_promotion_first_precheck_contract <- function() {
  root <- tempfile("graph_matrix_promotion_first_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  wb_define_cells(bundle, c("c2", "c1"))
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(1:4, 2L,
    dimnames = list(c("g2", "g1"), c("c2", "c1"))), sparse = TRUE))
  manifest <- jsonlite::fromJSON("tests/fixtures/operation-pack-v4-graph/inst/scworkbench/operation-pack.json",
    simplifyVector = FALSE)
  resource <- manifest$operations[[1L]]$outputs[[1L]]$resource_budgets
  resource$max_memory_bytes <- "8388608"; resource$max_collect_bytes <- "4194304"
  resource$partition_limits <- list(max_rows = "256", max_decoded_bytes = "262144")
  operation <- list(outputs = list(list(kind = "graph", resource_budgets = resource,
    axis_sources = list(list(input_name = "matrix", axis_kind = "cell",
      selection_mode = "retained_matrix_axis", source_binding_selector = NULL)))))
  registry <- scworkbench:::.wb_operation_pack_registry
  name <- "matrix_precheck_private_fixture::graph"
  previous <- registry$operations[[name]]
  on.exit({registry$operations[[name]] <- previous}, add = TRUE)
  registry$operations[[name]] <- list(definition = list(v4_definition = operation))
  session <- wb_session_new()
  selected <- scworkbench:::.wb_operation_pack_v4_matrix_sources_precheck(session, bundle, name,
    list(matrix = "RNA"))
  stopifnot(identical(selected$matrix$matrix_id, "RNA"), !is.null(selected$matrix$selection))
  pending <- wb_new_run("scwbrna::matrix_log_normalize", list(), list(),
    list(matrix = wb_prim_matrix("RNA")))
  session$runs[[pending$run_id]] <- pending
  session$active$matrix <- wb_ref_run(pending$run_id, "matrix")
  before <- scworkbench:::.wb_manifest_registry_snapshot(bundle$con)
  for (inputs in list(list(matrix = session$active$matrix), list(matrix = "RNA"),
    list(matrix = wb_prim_matrix("RNA")), list())) {
    error <- tryCatch(scworkbench:::.wb_operation_pack_v4_matrix_sources_precheck(session, bundle, name, inputs),
      error = identity)
    stopifnot(inherits(error, "wb_graph_error"),
      identical(error$code, "GRAPH_SOURCE_AUTHORITY_REQUIRED"))
  }
  stopifnot(is.null(session$staging_bundle), identical(before,
    scworkbench:::.wb_manifest_registry_snapshot(bundle$con)))
  TRUE
}

test_graph_matrix_native_existing_source_authority_contract <- function() {
  root <- tempfile("graph_matrix_native_authority_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c1"); features <- c("g2", "g1")
  wb_define_cells(bundle, cells)
  counts <- Matrix::Matrix(matrix(1:4, 2L, dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "RNA", counts)
  wb_attach_matrix(bundle, "other", counts)
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  before <- list(cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = bundle$con@ref$wb_graph_policy, cap = bundle$con@ref$wb_graph_cache_kib)
  scoped <- 0L
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "producer_hash_budget") {
      scoped <<- scoped + 1L
      stopifnot(state$budgets$memory_bytes == "8388608",
        -DBI::dbGetQuery(state$con, "PRAGMA cache_size;")[[1L]][[1L]] + 128L <= 2048L,
        state$con@ref$wb_graph_policy$memory_bytes == "8388608")
    }
  })
  on.exit(options(hook), add = TRUE)
  selected <- scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA", policy)
  snapshot <- scworkbench:::.wb_graph_matrix_retained_snapshot(bundle, selected, policy)
  for (axis in c("cell", "feature")) {
    ref <- list(kind = "matrix", source_id = "RNA")
    axes <- scworkbench:::.wb_graph_source_axis_hash(bundle, ref, axis, policy)
    binding <- c(list(binding_id = "native_source", axis_kind = axis, source_ref = ref,
      source_snapshot_identity = snapshot$source_snapshot_identity),
      axes[c("axis_content_identity", "axis_order_identity")])
    actual <- scworkbench:::.wb_graph_native_matrix_source_authorize(bundle, binding, policy)
    stopifnot(identical(actual$source_payload_closure_identity, snapshot$source_payload_closure_identity),
      actual$axis_count == "2", actual$source_snapshot_id == selected$snapshot_id)
    for (field in c("axis_content_identity", "axis_order_identity", "source_id")) {
      changed <- binding
      if (field == "source_id") changed$source_ref$source_id <- "other" else
        changed[[field]]$sha256 <- strrep("0", 64L)
      error <- tryCatch(scworkbench:::.wb_graph_native_matrix_source_authorize(bundle, changed, policy),
        error = identity)
      stopifnot(inherits(error, "wb_graph_error"))
    }
  }
  row <- DBI::dbGetQuery(bundle$con, "SELECT rowid,params_json FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
    params = list(selected$snapshot_id, selected$run_id))
  DBI::dbExecute(bundle$con, "UPDATE prov_runs SET params_json='{}' WHERE rowid=?;", params = list(row$rowid[[1L]]))
  error <- tryCatch(scworkbench:::.wb_graph_native_matrix_source_authorize(bundle, binding, policy), error = identity)
  stopifnot(inherits(error, "wb_graph_error"), grepl("retained hash", conditionMessage(error), fixed = TRUE))
  DBI::dbExecute(bundle$con, "UPDATE prov_runs SET params_json=? WHERE rowid=?;",
    params = list(row$params_json[[1L]], row$rowid[[1L]]))
  stopifnot(scoped >= 1L, identical(before,
    list(cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
      temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]],
      policy = bundle$con@ref$wb_graph_policy, cap = bundle$con@ref$wb_graph_cache_kib)))
  TRUE
}

test_graph_matrix_existing_producer_selection_contract <- function() {
  root <- tempfile("graph_matrix_producer_selection_")
  bundle <- wb_init_bundle(root)
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c1"); features <- c("g2", "g1")
  wb_define_cells(bundle, cells)
  counts <- Matrix::Matrix(matrix(1:4, 2L, dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "RNA", counts)
  wb_attach_matrix(bundle, "other", counts)
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  selected <- scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA", policy)
  exact_ref <- wb_ref_run(selected$run_id, selected$output_name)
  stopifnot(identical(selected,
    scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA", policy, exact_ref)))
  verified <- scworkbench:::.wb_graph_matrix_retained_snapshot(bundle, selected, policy)
  stopifnot(identical(verified$source_payload_closure_identity,
    scworkbench:::.wb_graph_native_matrix_identity(bundle, "RNA", policy)))
  before <- scworkbench:::.wb_manifest_registry_snapshot(bundle$con)
  for (candidate in list(list(id = "other", ref = exact_ref),
    list(id = "RNA", ref = wb_ref_run("pending_session_run", "matrix")),
    list(id = "pending_matrix", ref = NULL))) {
    error <- tryCatch(scworkbench:::.wb_graph_matrix_retained_selector(bundle,
      candidate$id, policy, candidate$ref), error = identity)
    stopifnot(inherits(error, "wb_graph_error"),
      identical(error$code, "GRAPH_SOURCE_AUTHORITY_REQUIRED"))
  }
  stopifnot(identical(before, scworkbench:::.wb_manifest_registry_snapshot(bundle$con)))
  # A genuine later unrelated producer/head cannot replace the selected
  # matrix producer snapshot.
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(),
    outputs = list(vector = wb_prim_cell_vector(stats::setNames(c("a", "b"), cells))))
  wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id), run$run_id, outputs = "vector")
  stopifnot(identical(selected,
    scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA", policy)),
    identical(verified,
      scworkbench:::.wb_graph_matrix_retained_snapshot(bundle, selected, policy)))
  TRUE
}
