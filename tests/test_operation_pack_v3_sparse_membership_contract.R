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
  grant <- list(schema = "scworkbench.operation_pack.pseudobulk_grant.v1",
    output = "summary", membership_output = "neighbors",
    query_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", list("q1", "q2")),
    feature_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", list("f1", "f2")),
    query_cells = list("q1", "q2"), features = list("f1", "f2"),
    aggregate = "sum", zero_neighbor_policy = "zero_rows_forbidden_v1",
    row_order = "query_then_feature_v1")
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.pseudobulk_grant.v1",
    "grant excluding grant_identity", grant)
  ledger <- list(list(query_cell_id = "q1", neighbor_rank = 1L,
    cell_id = "c1", distance = 1),
    list(query_cell_id = "q2", neighbor_rank = 1L,
      cell_id = "c2", distance = 1))
  membership <- list(edge_ledger = ledger,
    edge_ledger_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.sparse_edge_ledger.v1", ledger))
  value <- wb_prim_obs_table(data.frame(feature_id = rep(c("f1", "f2"), 2L),
    query_cell_id = rep(c("q1", "q2"), each = 2L), n_neighbors = rep(1L, 4L),
    aggregate = rep("sum", 4L), value = c(1, 2, 3, 4)),
    table_type = "synthetic_pseudobulk", entity_kind = "query_feature")
  observed <- .wb_operation_pack_v3_pseudobulk_observe(value, grant,
    membership)
  missing <- membership
  missing$edge_ledger <- ledger[1L]
  zero <- tryCatch(.wb_operation_pack_v3_pseudobulk_observe(value, grant,
    missing), error = identity)
  unknown_grant <- grant
  unknown_grant$zero_neighbor_policy <- "unknown_policy_v1"
  unknown <- tryCatch(.wb_operation_pack_v3_pseudobulk_observe(value,
    unknown_grant, membership), error = identity)
  stopifnot(identical(observed$status, "validated"),
    identical(observed$row_count, 4L),
    identical(setdiff(names(observed), "schema"), c("grant_identity",
      "edge_ledger_identity", "row_count", "aggregate", "status",
      "observation_identity")),
    inherits(zero, "wb_operation_pack_error"),
    identical(zero$code, "PYBENCH_OUTPUT_INVALID"),
    identical(zero$phase, "audit"),
    grepl("zero_rows_forbidden_v1", conditionMessage(zero), fixed = TRUE),
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
