.representation_registry_snapshot <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs,
    operations = registry$operations)
}

.representation_registry_restore <- function(snapshot) {
  snapshot$registry$packs <- snapshot$packs
  snapshot$registry$operations <- snapshot$operations
  invisible(TRUE)
}

test_representation_catalog_activation_identity_contract <- function() {
  baseline <- .representation_registry_snapshot()
  on.exit(.representation_registry_restore(baseline), add = TRUE)
  before_ops <- wb_list_ops()
  before_identity <- wb_operation_catalog_identity()
  stopifnot(!"leiden" %in% before_ops,
    !"scwbrepresentation::leiden" %in% before_ops)
  contract_test_activate_representation_pack()
  after_ops <- wb_list_ops()
  after_identity <- wb_operation_catalog_identity()
  stopifnot(setequal(setdiff(after_ops, before_ops),
      "scwbrepresentation::leiden"),
    identical(wb_op_interface("leiden")$op_name,
      "scwbrepresentation::leiden"),
    !identical(before_identity$sha256, after_identity$sha256))
  manifest <- wb_operation_pack_inspect("scwbrepresentation")
  stopifnot(identical(manifest$manifest$pack_abi_version, "3"),
    identical(manifest$manifest$namespace, "scwbrepresentation"),
    identical(vapply(manifest$manifest$operations, `[[`, "", "name"),
      "leiden"))
  TRUE
}

test_representation_failed_activation_has_zero_catalog_residue_contract <- function() {
  baseline <- .representation_registry_snapshot()
  on.exit(.representation_registry_restore(baseline), add = TRUE)
  before <- list(ops = wb_list_ops(), packs = wb_operation_packs(),
    identity = wb_operation_catalog_identity())
  contract_test_activate_representation_pack()
  installed <- system.file("scworkbench", "operation-pack.json",
    package = "scwbRepresentation",
    lib.loc = .contract_test_representation_state$library)
  dirty <- tempfile(fileext = ".json")
  text <- readLines(installed, warn = FALSE)
  writeLines(sub('"namespace": "scwbrepresentation"',
    '"namespace": "wrongrepresentation"', text, fixed = TRUE), dirty,
    useBytes = TRUE)
  .representation_registry_restore(baseline)
  error <- tryCatch(wb_operation_pack_activate(dirty,
    lib.loc = .contract_test_representation_state$library), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(before$ops, wb_list_ops()),
    identical(before$packs, wb_operation_packs()),
    identical(before$identity, wb_operation_catalog_identity()))
  TRUE
}
