test_operation_pack_v3_latent_union_protocol_contract <- function() {
  root <- file.path("tests", "fixtures", "phase6_latent_union")
  request <- jsonlite::read_json(file.path(root, "request.json"),
    simplifyVector = FALSE)
  receipt <- jsonlite::read_json(file.path(root, "receipt.json"),
    simplifyVector = FALSE)
  .wb_operation_pack_v3_schema_assert(request, "request",
    "PYBENCH_CAPABILITY_MISMATCH")
  .wb_operation_pack_v3_schema_assert(receipt, "receipt",
    "PYBENCH_RECEIPT_MISMATCH")
  .wb_operation_pack_v3_assert_self_identity(request, "request_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_assert_self_identity(receipt, "receipt_identity",
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  stopifnot(identical(receipt$request_identity, request$request_identity))
  for (grant in request$typed_space_grants) {
    .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
    cells <- as.character(unlist(grant$full_source_cell_axis$
      ordered_cell_ids, use.names = FALSE))
    stopifnot(identical(grant$selector_parameter, NULL),
      identical(length(cells), as.integer(grant$full_source_cell_axis$
        cell_count)),
      identical(grant$full_source_cell_axis$cell_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(cells)))))
  }
  lineage <- request$producer_lineage_grants[[1L]]
  .wb_operation_pack_v3_assert_self_identity(lineage, "grant_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_producer_lineage_receipt_audit(receipt, request)
  source_cells <- lapply(request$typed_space_grants, function(grant)
    as.character(unlist(grant$full_source_cell_axis$ordered_cell_ids,
      use.names = FALSE)))
  g7 <- request$derived_cell_output_axis_grants[[1L]]
  private <- list(cells = source_cells)
  attr(request, "operation_pack_v3_derived_axis_state") <-
    list(union_cells = private)
  final <- unlist(source_cells, use.names = FALSE)
  declaration <- wb_derived_cell_output_axis_declaration(g7,
    final_cell_ids = final, member_selections = source_cells)
  sealed <- .wb_operation_pack_v3_g7_seal(request, list(declaration))[[1L]]
  space <- request$outputs[[1L]]
  cardinality <- .wb_operation_pack_v3_g7_sealed_cardinality(space, sealed)
  stopifnot(identical(cardinality$expected_dimensions,
    list(as.integer(length(final)),
      as.integer(request$typed_space_grants[[1L]]$dimension_count))))
  wrong_dimensions <- sealed
  wrong_dimensions$grant$source_axes[[2L]]$source_dimension_count <-
    as.integer(wrong_dimensions$grant$source_axes[[2L]]$
      source_dimension_count) + 1L
  stopifnot(inherits(try(.wb_operation_pack_v3_g7_sealed_cardinality(
    space, wrong_dimensions), silent = TRUE), "try-error"))
  bad_members <- source_cells
  bad_members[[1L]] <- bad_members[[1L]][-1L]
  partial <- wb_derived_cell_output_axis_declaration(g7,
    final_cell_ids = c(bad_members[[1L]], bad_members[[2L]]),
    member_selections = bad_members)
  stopifnot(inherits(try(.wb_operation_pack_v3_g7_seal(request,
    list(partial)), silent = TRUE), "try-error"))
  foreign_members <- source_cells
  foreign_members[[2L]][[1L]] <- "foreign_cell"
  foreign <- wb_derived_cell_output_axis_declaration(g7,
    final_cell_ids = unlist(foreign_members, use.names = FALSE),
    member_selections = foreign_members)
  stopifnot(inherits(try(.wb_operation_pack_v3_g7_seal(request,
    list(foreign)), silent = TRUE), "try-error"))
  overlap <- request
  attr(overlap, "operation_pack_v3_derived_axis_state") <- list(
    union_cells = list(cells = list(source_cells[[1L]],
      c(source_cells[[1L]][[1L]], source_cells[[2L]]))))
  overlap_members <- list(source_cells[[1L]],
    c(source_cells[[1L]][[1L]], source_cells[[2L]]))
  overlapping <- wb_derived_cell_output_axis_declaration(g7,
    final_cell_ids = final, member_selections = overlap_members)
  stopifnot(inherits(try(.wb_operation_pack_v3_g7_seal(overlap,
    list(overlapping)), silent = TRUE), "try-error"))
  altered <- .wb_operation_pack_v2_deep_copy(receipt)
  altered$producer_lineage_reads[[1L]]$grant_identity$sha256 <-
    paste0("0", substring(altered$producer_lineage_reads[[1L]]$
      grant_identity$sha256, 2L))
  observed <- altered$producer_lineage_reads[[1L]]
  observed$observation_identity <- NULL
  observed$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    observed$schema, "observation excluding observation_identity", observed)
  altered$producer_lineage_reads[[1L]] <- observed
  altered$receipt_identity <- NULL
  altered$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", altered)
  stopifnot(inherits(try(.wb_operation_pack_v3_producer_lineage_receipt_audit(
    altered, request), silent = TRUE), "try-error"))
  TRUE
}
