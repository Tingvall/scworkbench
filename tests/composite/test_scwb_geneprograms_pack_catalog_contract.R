.geneprograms_registry_snapshot <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs,
    operations = registry$operations)
}

.geneprograms_registry_restore <- function(snapshot) {
  snapshot$registry$packs <- snapshot$packs
  snapshot$registry$operations <- snapshot$operations
  invisible(TRUE)
}

test_geneprograms_catalog_activation_orders_contract <- function() {
  baseline <- .geneprograms_registry_snapshot()
  on.exit(.geneprograms_registry_restore(baseline), add = TRUE)
  stopifnot(length(wb_list_ops()) == 37L)
  none <- wb_operation_catalog_identity()

  contract_test_activate_statistics_pack()
  stopifnot(length(wb_list_ops()) == 43L)
  statistics <- wb_operation_catalog_identity()
  contract_test_activate_geneprograms_pack()
  stopifnot(length(wb_list_ops()) == 53L)
  statistics_then_geneprograms <- wb_operation_catalog_identity()

  .geneprograms_registry_restore(baseline)
  contract_test_activate_geneprograms_pack()
  stopifnot(length(wb_list_ops()) == 47L)
  geneprograms <- wb_operation_catalog_identity()
  contract_test_activate_statistics_pack()
  stopifnot(length(wb_list_ops()) == 53L)
  geneprograms_then_statistics <- wb_operation_catalog_identity()
  stopifnot(identical(statistics_then_geneprograms,
      geneprograms_then_statistics),
    length(unique(vapply(list(none, statistics, geneprograms,
      statistics_then_geneprograms), function(x) x$sha256, character(1)))) == 4L)

  expected <- paste0("scwbgeneprograms::", c("addmodulescore", "ucell",
    "cell_vector_family_reduce", "cell_vector_family_calibrate",
    "cell_vector_family_qc", "cell_vector_family_graph_smooth",
    "cell_vector_winners", "winner_cell_sets", "feature_set_overlap_qc",
    "pathway_enrich"))
  stopifnot(all(expected %in% wb_list_ops()),
    identical(wb_op_interface("addmodulescore")$op_name,
      "scwbgeneprograms::addmodulescore"))
  duplicate <- wb_operation_pack_load("scwbGenePrograms",
    lib.loc = .contract_test_geneprograms_state$library)
  stopifnot(identical(duplicate$identity$pack_sha256,
    wb_operation_pack_inspect("scwbgeneprograms")$identity$pack_sha256),
    length(wb_list_ops()) == 53L)
  TRUE
}

test_geneprograms_dirty_manifest_zero_residue_contract <- function() {
  baseline <- .geneprograms_registry_snapshot()
  on.exit(.geneprograms_registry_restore(baseline), add = TRUE)
  contract_test_activate_geneprograms_pack()
  before <- list(ops = wb_list_ops(), packs = wb_operation_packs(),
    identity = wb_operation_catalog_identity())
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbGenePrograms", lib.loc = .contract_test_geneprograms_state$library)
  dirty <- tempfile(fileext = ".json")
  text <- readLines(manifest, warn = FALSE)
  writeLines(sub('"namespace": "scwbgeneprograms"',
    '"namespace": "wronggeneprograms"', text, fixed = TRUE), dirty,
    useBytes = TRUE)
  error <- tryCatch(wb_operation_pack_activate(dirty,
    lib.loc = .contract_test_geneprograms_state$library), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(before$ops, wb_list_ops()),
    identical(before$packs, wb_operation_packs()),
    identical(before$identity, wb_operation_catalog_identity()))
  TRUE
}
