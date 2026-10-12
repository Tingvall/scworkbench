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
  dependencies <- utils::read.csv("inst/phase8/dependency_audit.csv",
    stringsAsFactors = FALSE)
  suggested <- trimws(strsplit(read.dcf("DESCRIPTION")[[1L, "Suggests"]],
    ",", fixed = TRUE)[[1L]])
  stopifnot(!anyDuplicated(dependencies$package),
    setequal(dependencies$package[dependencies$disposition == "retained"],
      suggested),
    !any(dependencies$package[dependencies$disposition == "removed"] %in%
      suggested))
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
  graph_schema <- jsonlite::read_json("inst/protocol/operation-pack-v4.schema.json",
    simplifyVector = FALSE)
  graph_schema_kinds <- unlist(graph_schema$`$defs`$primitive_kind$enum,
    use.names = FALSE)
  legacy_kinds <- c("matrix", "space", "space_2d", "cell_vector",
    "cell_vector_family", "feature_table", "obs_table", "model_ref",
    "relation_family", "path_2d_family", "space_path_family")
  graph <- inventory[inventory$primitive_kind == "graph", , drop = FALSE]
  stopifnot(
    nrow(inventory) == 12L,
    !anyDuplicated(inventory$primitive_kind),
    identical(schema_kinds, legacy_kinds),
    identical(graph_schema_kinds, c(legacy_kinds, "graph")),
    !"graph" %in% schema_kinds,
    setequal(inventory$primitive_kind, catalog_kinds),
    setequal(inventory$primitive_kind[inventory$minimum_pack_abi_version == 2L], schema_kinds),
    setequal(inventory$primitive_kind, graph_schema_kinds),
    nrow(graph) == 1L, graph$minimum_pack_abi_version == 4L,
    graph$r_read == "issued_bounded_component_cursor",
    graph$r_write == "granted_open_graph_write_part_finish",
    grepl("test_graph_small_out_of_core_contract.R", graph$qualification_evidence, fixed = TRUE),
    grepl("test_graph_small_r_parity.py", graph$python_qualification_evidence, fixed = TRUE),
    grepl("Beyond-host-RAM and 8x physical stress are deferred", graph$limits, fixed = TRUE),
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
  current <- utils::read.csv("inst/phase8/current_core_test_ownership_inventory.csv",
    stringsAsFactors = FALSE)
  references <- utils::read.csv("inst/phase8/migrated_operation_test_references.csv",
    stringsAsFactors = FALSE)
  operations <- utils::read.csv("inst/phase8/packed_operation_names.csv",
    stringsAsFactors = FALSE)
  additions <- utils::read.csv("inst/phase8/graph_and_core_test_additions.csv",
    stringsAsFactors = FALSE)
  files <- sort(list.files("tests", pattern = "^test_.*\\.R$", full.names = TRUE))
  discovered <- unlist(lapply(files, function(path) {
    parsed <- parse(path)
    vapply(Filter(function(expr) is.call(expr) &&
      identical(expr[[1L]], as.name("<-")) && is.symbol(expr[[2L]]) &&
      startsWith(as.character(expr[[2L]]), "test_") &&
      is.call(expr[[3L]]) && identical(expr[[3L]][[1L]], as.name("function")),
      parsed), function(expr) as.character(expr[[2L]]), character(1))
  }), use.names = FALSE)
  sdk_tests <- paste0("test_operation_pack_sdk_", c("scaffold_safety",
    "manifest_negatives", "catalog_coverage", "case_accounting",
    "installed_contract", "installed_tutorial", "activation_negatives"))
  stopifnot(
    nrow(ownership) == 242L,
    !anyDuplicated(ownership$test_identity),
    all(nzchar(ownership$key_assertions)),
    nrow(current) == 336L,
    nrow(additions) == 85L,
    !anyDuplicated(additions$test_identity),
    all(additions$owner == "core_engine"),
    all(additions$disposition == "retain_core"),
    all(nzchar(additions$justification)),
    all(additions$ownership_decision_commit == "441297513b9a1b41fae23764c9a85c3b129cf0b7"),
    all(additions$source_checkpoint_commit == "441297513b9a1b41fae23764c9a85c3b129cf0b7"),
    !anyDuplicated(current$test_identity),
    identical(sort(current$test_identity), sort(discovered)),
    all(nzchar(current$key_assertions)),
    all(current$owner == "core_engine"),
    all(current$disposition == "retain_core"),
    all(nzchar(current$destination)),
    all(!nzchar(current$old_owner_commit[current$test_identity %in% c(
      "test_phase8_no_pack_core_surface_contract",
      "test_phase8_primitive_exchange_inventory_contract",
      "test_phase8_test_ownership_inventory_contract")])),
    identical(current$origin_baseline_test_identity[
      current$test_identity ==
        "test_operation_pack_v3_pseudobulk_zero_neighbor_grant_contract"],
      "test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract"),
    identical(sort(setdiff(current$test_identity, ownership$test_identity)),
      sort(c("test_operation_pack_v3_pseudobulk_zero_neighbor_grant_contract",
        "test_phase8_no_pack_core_surface_contract",
        "test_phase8_primitive_exchange_inventory_contract",
        "test_phase8_test_ownership_inventory_contract", sdk_tests, additions$test_identity))),
    identical(current$source_path[match(additions$test_identity, current$test_identity)], additions$source_path),
    identical(current$new_owner_commit[match(additions$test_identity, current$test_identity)], additions$ownership_decision_commit),
    all(!nzchar(current$old_owner_commit[current$test_identity %in% additions$test_identity])),
    all(current$new_owner_commit[!current$test_identity %in% c(sdk_tests, additions$test_identity)] ==
      "03f5a5bf699ac36ed44fc0a3cc56a2d750e76f7e"),
    all(current$owner[current$test_identity %in% sdk_tests] == "core_engine"),
    all(current$new_owner_commit[current$test_identity %in% sdk_tests] ==
      "baf5cb40650a6a6a0e5219b03785e5bed0c4d2b3"),
    identical(sort(setdiff(ownership$test_identity, current$test_identity)),
      sort(c("test_immutable_history_state_machine_closure_contract",
        "test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract"))),
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
