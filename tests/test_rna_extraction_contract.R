test_rna_methods_are_pack_owned_contract <- function() {
  migrated <- c(
    cell_suffix_label = "scwbrna::cell_suffix_label",
    rna_qc_metrics = "scwbrna::rna_qc_metrics",
    hvg_select = "scwbrna::hvg_select",
    matrix_log_normalize = "scwbrna::matrix_log_normalize"
  )
  ops_before <- wb_list_ops()
  packs_before <- wb_operation_packs()
  identity_before <- wb_operation_catalog_identity()
  map <- getFromNamespace(".wb_operation_pack_migrated_map", "scworkbench")()
  stopifnot(
    !any(names(migrated) %in% ops_before),
    !any(unname(migrated) %in% ops_before),
    !any(paste0("wb_op_", names(migrated)) %in% getNamespaceExports("scworkbench")),
    identical(unname(map[names(migrated)]), unname(migrated))
  )
  root <- tempfile("rna-missing-pack-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  durable_before <- getFromNamespace(".wb_manifest_registry_snapshot",
    "scworkbench")(bundle$con)$fingerprint
  for (name in names(migrated)) {
    lookup_error <- tryCatch(getFromNamespace(".wb_op", "scworkbench")(name),
      error = identity)
    dispatch_error <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
      name, inputs = list()), error = identity)
    stopifnot(
      inherits(lookup_error, "wb_operation_pack_error"),
      identical(lookup_error$code, "OPERATION_PACK_REQUIRED"),
      identical(lookup_error$required_operation, unname(migrated[[name]])),
      inherits(dispatch_error, "wb_operation_pack_error"),
      identical(dispatch_error$code, "OPERATION_PACK_REQUIRED")
    )
  }
  stopifnot(
    identical(durable_before, getFromNamespace(
      ".wb_manifest_registry_snapshot", "scworkbench")(bundle$con)$fingerprint),
    nrow(wb_art_list(bundle)) == 0L,
    !dir.exists(file.path(bundle$dir, "operation_pack_v2")),
    identical(ops_before, wb_list_ops()),
    identical(packs_before, wb_operation_packs()),
    identical(identity_before, wb_operation_catalog_identity())
  )
  TRUE
}
