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

test_operation_pack_v3_sparse_pack_free_catalog_contract <- function() {
  stopifnot(!"knn_neighbors" %in% wb_list_ops(),
    !"knn_pseudobulk" %in% wb_list_ops(),
    !exists("wb_op_knn_neighbors", envir = asNamespace("scworkbench"),
      inherits = FALSE),
    !exists("wb_op_knn_pseudobulk", envir = asNamespace("scworkbench"),
      inherits = FALSE))
  TRUE
}
