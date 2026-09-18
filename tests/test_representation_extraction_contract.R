test_representation_methods_are_pack_owned_contract <- function() {
  migrated <- c(leiden = "scwbrepresentation::leiden",
    pca_fit = "scwbrepresentation::pca_fit")
  ops_before <- wb_list_ops()
  packs_before <- wb_operation_packs()
  identity_before <- wb_operation_catalog_identity()
  stopifnot(!any(names(migrated) %in% ops_before),
    !any(unname(migrated) %in% ops_before),
    !any(paste0("wb_op_", names(migrated)) %in%
      getNamespaceExports("scworkbench")),
    identical(unname(getFromNamespace(".wb_operation_pack_migrated_map",
      "scworkbench")()[names(migrated)]), unname(migrated)))
  root <- tempfile("representation-missing-pack-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  durable_before <- getFromNamespace(".wb_manifest_registry_snapshot",
    "scworkbench")(bundle$con)$fingerprint
  leiden_error <- tryCatch(getFromNamespace(".wb_op", "scworkbench")(
    "leiden"), error = identity)
  leiden_dispatch <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
    op_name = "leiden", inputs = list(space = "absent", min_cells = 1L)),
    error = identity)
  pca_error <- tryCatch(getFromNamespace(".wb_op", "scworkbench")(
    "pca_fit"), error = identity)
  pca_dispatch <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
    op_name = "pca_fit", inputs = list(matrix = "absent", min_cells = 1L)),
    error = identity)
  stopifnot(inherits(leiden_error, "wb_operation_pack_error"),
    identical(leiden_error$code, "OPERATION_PACK_REQUIRED"),
    identical(leiden_error$required_operation, migrated[["leiden"]]),
    inherits(leiden_dispatch, "wb_operation_pack_error"),
    identical(leiden_dispatch$code, "OPERATION_PACK_REQUIRED"),
    inherits(pca_error, "wb_operation_pack_error"),
    identical(pca_error$code, "OPERATION_PACK_REQUIRED"),
    identical(pca_error$required_operation, migrated[["pca_fit"]]),
    inherits(pca_dispatch, "wb_operation_pack_error"),
    identical(pca_dispatch$code, "OPERATION_PACK_REQUIRED"))
  stopifnot(
    identical(durable_before, getFromNamespace(
      ".wb_manifest_registry_snapshot", "scworkbench")(
        bundle$con)$fingerprint),
    nrow(wb_art_list(bundle)) == 0L,
    !dir.exists(file.path(bundle$dir, "operation_pack_v2")),
    identical(ops_before, wb_list_ops()),
    identical(packs_before, wb_operation_packs()),
    identical(identity_before, wb_operation_catalog_identity()))
  TRUE
}
