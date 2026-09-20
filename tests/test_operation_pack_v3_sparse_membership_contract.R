test_operation_pack_v3_sparse_membership_contract <- function() {
  root <- tempfile("v3-sparse-membership-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- c("q2", "c2", "q1", "c1", "c3")
  wb_define_cells(bundle, cells)
  selector <- .wb_operation_pack_v3_selector_values
  stopifnot(identical(selector(bundle, NULL, "candidate_cells", TRUE), cells),
    identical(selector(bundle, c("q1", "q2"), "query_cells"),
      c("q1", "q2")),
    inherits(try(selector(bundle, c("q1", "q1"), "query_cells"),
      silent = TRUE), "try-error"),
    inherits(try(selector(bundle, "foreign", "query_cells"),
      silent = TRUE), "try-error"))

  grant <- list(schema =
      "scworkbench.operation_pack.sparse_membership_grant.v1",
    output = "neighbors", representation = "obs_table",
    partner_output = "neighbor_distance",
    query_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", list("q1", "q2")),
    candidate_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", list("c1", "c2", "c3")),
    query_count = 2L, candidate_count = 3L, maximum_per_query = 2L,
    row_order = "query_then_rank_v1", unique_pairs = TRUE,
    finite_nonnegative_values = TRUE)
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sparse_membership_grant.v1",
    "grant excluding grant_identity", grant)
  attr(grant, "operation_pack_v3_query_cells") <- c("q1", "q2")
  attr(grant, "operation_pack_v3_candidate_cells") <- c("c1", "c2", "c3")
  table <- data.frame(query_cell_id = c("q1", "q1", "q2"),
    neighbor_rank = c(1L, 2L, 1L), cell_id = c("c2", "c1", "c3"),
    distance = c(.1, .2, .3), stringsAsFactors = FALSE)
  observed <- .wb_operation_pack_v3_sparse_ledger(
    wb_prim_obs_table(table, table_type = "knn_neighbors",
      entity_kind = "cell"), grant)
  stopifnot(observed$edge_count == 3L,
    identical(vapply(observed$edge_ledger, `[[`, character(1), "cell_id"),
      c("c2", "c1", "c3")))
  duplicate <- table; duplicate$cell_id[[2]] <- "c2"
  reordered <- table[c(3L, 1L, 2L), , drop = FALSE]
  foreign <- table; foreign$cell_id[[1]] <- "foreign"
  nonfinite <- table; nonfinite$distance[[1]] <- Inf
  for (bad in list(duplicate, reordered, foreign, nonfinite))
    stopifnot(inherits(try(.wb_operation_pack_v3_sparse_ledger(
      wb_prim_obs_table(bad, table_type = "knn_neighbors",
        entity_kind = "cell"), grant), silent = TRUE), "try-error"))
  family_grant <- grant
  family_grant$representation <- "cell_vector_family"
  family_grant$grant_identity <- NULL
  family_grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sparse_membership_grant.v1",
    "grant excluding grant_identity", family_grant)
  family <- wb_prim_cell_vector_family(table$query_cell_id, table$cell_id,
    table$distance, value_type = "continuous")
  family_observed <- .wb_operation_pack_v3_sparse_ledger(family,
    family_grant)
  stopifnot(identical(observed$edge_ledger,
    family_observed$edge_ledger))
  TRUE
}

test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract <- function() {
  contract_test_activate_representation_pack()
  root <- tempfile("v3-pseudobulk-zero-neighbor-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  session <- wb_session_new()
  on.exit({
    options(scworkbench.operation_pack_v3_output_test_hook = NULL)
    try(session <- wb_session_discard(session), silent = TRUE)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("q1", "q2", "c1", "c2")
  features <- c("f1", "f2")
  values <- matrix(c(0, 0, 1, 10, 0, 0, 10, 100), nrow = 2L,
    byrow = TRUE, dimnames = list(features, cells))
  coordinates <- cbind(x = c(0, 10, 1, 9), y = rep(0, 4L))
  rownames(coordinates) <- cells
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "gene")
  wb_add_space(bundle, "latent", coordinates, overwrite = TRUE)

  staged <- .wb_session_stage_bundle(bundle, session)
  session <- staged$session
  counts <- function(candidate) vapply(c("artifacts", "prov_runs",
      "prov_commits"), function(table) as.integer(DBI::dbGetQuery(
        candidate$con, paste0("SELECT COUNT(*) AS n FROM ", table,
          ";"))$n[[1L]]), integer(1))
  transition_inventory <- function() {
    path <- file.path(session$staging_dir, "operation_pack_v2")
    if (!dir.exists(path)) return(character())
    sort(list.files(path, recursive = TRUE, all.files = TRUE,
      no.. = TRUE, include.dirs = TRUE), method = "radix")
  }
  before <- list(source = counts(bundle), staged = counts(staged$bundle),
    transitions = transition_inventory())

  omit_q2_membership <- function(writes, ...) {
    family <- writes$neighbor_distance$value
    keep <- family$key == "q1"
    family$key <- family$key[keep]
    family$cell_id <- family$cell_id[keep]
    family$value <- family$value[keep]
    writes$neighbor_distance$value <- family
    table <- writes$pseudobulk_table$value$table
    q2 <- table$query_cell_id == "q2"
    table$n_neighbors[q2] <- 0L
    table$value[q2] <- 999
    writes$pseudobulk_table$value$table <- table
    writes
  }
  options(scworkbench.operation_pack_v3_output_test_hook =
    omit_q2_membership)
  failed <- tryCatch(wb_session_run_op(session, bundle,
    "knn_pseudobulk", inputs = list(matrix = "RNA", space = "latent",
      query_cells = c("q1", "q2"), candidate_cells = c("c1", "c2"),
      features = features, k = 1L, include_query = FALSE,
      aggregate = "sum", min_cells = 1L)), error = identity)
  options(scworkbench.operation_pack_v3_output_test_hook = NULL)
  after <- list(source = counts(bundle), staged = counts(staged$bundle),
    transitions = transition_inventory())
  stopifnot(inherits(failed, "wb_operation_pack_error"),
    identical(failed$code, "PYBENCH_OUTPUT_INVALID"),
    identical(failed$phase, "audit"),
    grepl("zero_rows_forbidden_v1", conditionMessage(failed), fixed = TRUE),
    identical(before, after), !dir.exists(file.path(session$staging_dir,
      "operation_pack_v2")))

  positive <- wb_session_run_op(session, bundle, "knn_pseudobulk",
    inputs = list(matrix = "RNA", space = "latent",
      query_cells = c("q1", "q2"), candidate_cells = c("c1", "c2"),
      features = features, k = 1L, include_query = FALSE,
      aggregate = "sum", min_cells = 1L))
  session <- positive$session
  table <- positive$run$outputs$pseudobulk_table$table
  stopifnot(all(table$n_neighbors > 0L),
    identical(unique(table$query_cell_id), c("q1", "q2")))
  transition_id <- positive$run$operation_pack_transition$transition_id
  record <- .wb_operation_pack_v2_record_validate(file.path(
    session$staging_dir, "operation_pack_v2", transition_id),
    load_payloads = TRUE)
  output_names <- vapply(record$receipt$outputs, `[[`, character(1), "name")
  observation <- record$receipt$outputs[[match("pseudobulk_table",
    output_names)]]$descriptor$observed_pseudobulk
  request_names <- vapply(record$request$outputs, `[[`, character(1), "name")
  grant <- record$request$outputs[[match("pseudobulk_table",
    request_names)]]$descriptor$pseudobulk_grant
  membership <- record$receipt$outputs[[match("neighbor_distance",
    output_names)]]$descriptor$observed_sparse_membership
  grant$zero_neighbor_policy <- "unknown_policy_v1"
  unknown <- tryCatch(.wb_operation_pack_v3_pseudobulk_observe(
    positive$run$outputs$pseudobulk_table, grant, membership),
    error = identity)
  stopifnot(isTRUE(record$ok), identical(setdiff(names(observation),
      "schema"), c("grant_identity", "edge_ledger_identity", "row_count",
        "aggregate", "status", "observation_identity")),
    identical(observation$status, "validated"),
    inherits(unknown, "wb_operation_pack_error"),
    identical(unknown$code, "PYBENCH_OUTPUT_INVALID"),
    identical(unknown$phase, "audit"))
  TRUE
}

test_operation_pack_v3_sparse_pack_free_catalog_contract <- function() {
  stopifnot(!"knn_neighbors" %in% wb_list_ops(),
    !"knn_pseudobulk" %in% wb_list_ops(),
    !exists("wb_op_knn_neighbors", envir = asNamespace("scworkbench"),
      inherits = FALSE),
    !exists("wb_op_knn_pseudobulk", envir = asNamespace("scworkbench"),
      inherits = FALSE))
  TRUE
}
