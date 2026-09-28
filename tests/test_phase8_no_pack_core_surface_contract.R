test_phase8_no_pack_core_surface_contract <- function() {
  expected <- c("feature_set_import", "feature_set_namespace_transfer",
    "cell_set_derive", "metadata_cell_vector", "slingshot_adopt")
  stopifnot(identical(sort(wb_list_ops()), sort(expected)))

  exports <- getNamespaceExports("scworkbench")
  retired <- c("wb_op_knn_graph", "wb_op_meanexpr")
  stopifnot(!any(retired %in% exports))
  namespace <- asNamespace("scworkbench")
  stopifnot(!any(vapply(c("wb_op_py_protocol_hello",
    "wb_op_feature_set_overlap_qc", ".wb_de_wilcox_core"),
    exists, logical(1), envir = namespace, inherits = FALSE)))
  # The generic selector still serves authenticated pack grants.
  stopifnot(exists(".wb_resolve_group_cells", envir = namespace,
    inherits = FALSE))
  TRUE
}

test_phase8_primitive_exchange_inventory_contract <- function() {
  inventory <- utils::read.csv("inst/phase8/primitive_exchange_inventory.csv",
    stringsAsFactors = FALSE)
  catalog <- wb_primitive_catalog_semantic()$primitives
  catalog_kinds <- vapply(catalog, `[[`, character(1), "primitive_kind")
  schema <- jsonlite::read_json("inst/protocol/operation-pack-v2.schema.json",
    simplifyVector = FALSE)
  schema_kinds <- unlist(schema$`$defs`$primitive_kind$enum,
    use.names = FALSE)
  stopifnot(
    nrow(inventory) == 11L,
    !anyDuplicated(inventory$primitive_kind),
    setequal(inventory$primitive_kind, catalog_kinds),
    setequal(inventory$primitive_kind, schema_kinds),
    all(inventory$classification %in% c("exchangeable_and_qualified",
      "deliberately_core_only", "r_only_python_fail_closed", "actual_gap")),
    !any(inventory$classification == "actual_gap"),
    all(nzchar(inventory$qualification_evidence)),
    all(nzchar(inventory$python_qualification_evidence)),
    all(nzchar(inventory$recipient_validation))
  )
  TRUE
}

test_phase8_test_ownership_inventory_contract <- function() {
  ownership <- utils::read.csv("inst/phase8/core_test_ownership_inventory.csv",
    stringsAsFactors = FALSE)
  references <- utils::read.csv("inst/phase8/migrated_operation_test_references.csv",
    stringsAsFactors = FALSE)
  operations <- utils::read.csv("inst/phase8/packed_operation_names.csv",
    stringsAsFactors = FALSE)
  stopifnot(
    nrow(ownership) == 242L,
    !anyDuplicated(ownership$test_identity),
    all(nzchar(ownership$key_assertions)),
    all(ownership$owner %in% c("core_engine", "pack_method",
      "pinned_composite", "migration_evidence")),
    all(nzchar(ownership$destination)),
    nrow(operations) == 56L,
    !anyDuplicated(operations$qualified_name),
    all(references$test_identity %in% ownership$test_identity),
    all(references$migrated_operation %in% c(
      operations$operation_name, operations$qualified_name)),
    all(grepl("^[0-9a-f]{40}$", references$old_owner_commit)),
    all(grepl("^[0-9a-f]{40}$", references$new_owner_commit)),
    any(references$test_identity == "test_navigation_contract" &
      references$migrated_operation == "trajectory_de"),
    any(references$test_identity == "test_trajectory_family_helpers_contract" &
      references$migrated_operation == "palantir_project")
  )
  TRUE
}
