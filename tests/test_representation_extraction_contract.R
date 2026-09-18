test_representation_leiden_is_pack_owned_contract <- function() {
  ops_before <- wb_list_ops()
  packs_before <- wb_operation_packs()
  identity_before <- wb_operation_catalog_identity()
  stopifnot(!"leiden" %in% ops_before,
    !"scwbrepresentation::leiden" %in% ops_before,
    !"wb_op_leiden" %in% getNamespaceExports("scworkbench"),
    identical(unname(getFromNamespace(".wb_operation_pack_migrated_map",
      "scworkbench")()[["leiden"]]), "scwbrepresentation::leiden"))
  error <- tryCatch(getFromNamespace(".wb_op", "scworkbench")("leiden"),
    error = identity)
  root <- tempfile("representation-missing-pack-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  durable_before <- getFromNamespace(".wb_manifest_registry_snapshot",
    "scworkbench")(bundle$con)$fingerprint
  dispatch_error <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
    "leiden", inputs = list(space = "absent", min_cells = 1L)),
    error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(error$code, "OPERATION_PACK_REQUIRED"),
    identical(error$required_operation, "scwbrepresentation::leiden"),
    inherits(dispatch_error, "wb_operation_pack_error"),
    identical(dispatch_error$code, "OPERATION_PACK_REQUIRED"),
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
