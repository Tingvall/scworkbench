args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop("usage: profile_process.R MODE LIB CORE_LIB PROFILE_SOURCE RECEIPT")
mode <- args[[1L]]
library <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
core_library <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
.libPaths(c(library, core_library, .libPaths()))
base::library(scworkbench, lib.loc = core_library)
sys.source(args[[4L]], envir = .GlobalEnv)

expect_error_code <- function(expr, code) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(error) || !grepl(paste0("STANDARD_PROFILE_", code),
      conditionMessage(error), fixed = TRUE)) {
    stop("expected profile error ", code, "; observed: ",
      if (is.null(error)) "success" else conditionMessage(error))
  }
  invisible(TRUE)
}

core <- c("feature_set_import", "feature_set_namespace_transfer",
          "cell_set_derive", "metadata_cell_vector", "slingshot_adopt")
stopifnot(setequal(wb_list_ops(), core), nrow(wb_operation_packs()) == 0L)

receipt_path <- args[[5L]]

if (identical(mode, "core_only")) {
  stopifnot(setequal(wb_list_ops(), core), nrow(wb_operation_packs()) == 0L)
  cat("PASS core_only: clean five-operation catalog and no ambient activation\n")
} else if (startsWith(mode, "pack:")) {
  package <- sub("^pack:", "", mode)
  pinned <- Filter(function(x) identical(x$package, package), .scwb_profile_read_lock()$packs)
  stopifnot(length(pinned) == 1L)
  manifest <- system.file("scworkbench", "operation-pack.json", package = package,
    lib.loc = library, mustWork = TRUE)
  record <- wb_operation_pack_validate(package, lib.loc = library)
  stopifnot(nrow(wb_operation_packs()) == 0L)
  .scwb_profile_check_identity(record$identity, pinned[[1L]])
  activated <- wb_operation_pack_activate(manifest, lib.loc = library)
  .scwb_profile_check_identity(activated$identity, pinned[[1L]])
  stopifnot(nrow(wb_operation_packs()) == 1L,
    length(wb_list_ops()) == 5L + as.integer(pinned[[1L]]$operation_count))
  operation <- names(record$identity$operation_definition_sha256)[[1L]]
  interface <- wb_op_interface(operation)
  stopifnot(identical(interface$source_pack$pack_sha256, activated$identity$pack_sha256))
  cat("PASS pack:", package, " operations=", pinned[[1L]]$operation_count,
      " pack_sha256=", activated$identity$pack_sha256, "\n", sep = "")
} else if (identical(mode, "missing_pack")) {
  absent_library <- tempfile("profile-absent-pack-library-")
  dir.create(absent_library)
  expect_error_code(scwb_standard_profile_activate(receipt_path,
    lib.loc = absent_library), "MISSING_PACK")
  stopifnot(nrow(wb_operation_packs()) == 0L)
  cat("PASS missing_pack: activation rejected before catalog registration\n")
} else if (identical(mode, "profile")) {
  lock <- .scwb_profile_read_lock()
  receipt <- .scwb_profile_read_receipt(receipt_path)
  wrong <- lock
  wrong$packs[[1L]]$manifest_sha256 <- paste0("0", substring(
    wrong$packs[[1L]]$manifest_sha256, 2L))
  expect_error_code(.scwb_standard_profile_activate_locked(wrong, receipt,
    lib.loc = library), "RECEIPT_MISMATCH")
  wrong_receipt <- receipt
  wrong_receipt$packs[[1L]]$pack_sha256 <- paste0("0", substring(
    wrong_receipt$packs[[1L]]$pack_sha256, 2L))
  expect_error_code(.scwb_standard_profile_activate_locked(lock,
    wrong_receipt, lib.loc = library), "WRONG_PIN")
  stopifnot(nrow(wb_operation_packs()) == 0L)

  colliding <- lock
  colliding$packs[[2L]]$namespace <- colliding$packs[[1L]]$namespace
  expect_error_code(.scwb_standard_profile_activate_locked(colliding, receipt,
    lib.loc = library), "LOCK_COLLISION")
  stopifnot(nrow(wb_operation_packs()) == 0L)

  previous <- getOption("scworkbench.operation_pack_v2_test_hook", NULL)
  options(scworkbench.operation_pack_v2_test_hook = function(event, namespace = NULL, ...) {
    if (identical(event, "catalog_before_commit") &&
        identical(namespace, "scwbrepresentation")) stop("injected profile activation fault")
  })
  expect_error_code(.scwb_standard_profile_activate_locked(lock, receipt,
    lib.loc = library),
    "ACTIVATION_FAILED")
  options(scworkbench.operation_pack_v2_test_hook = previous)
  stopifnot(nrow(wb_operation_packs()) == 0L, setequal(wb_list_ops(), core))

  result <- scwb_standard_profile_activate(receipt_path, lib.loc = library)
  stopifnot(nrow(result$packs) == 7L, length(result$operations) == 61L,
    sum(result$packs$operation_count) == 56L,
    all(!result$packs$used),
    setequal(names(table(result$packs$namespace)),
      vapply(lock$packs, `[[`, character(1), "namespace")))
  for (entry in lock$packs) {
    inspected <- wb_operation_pack_inspect(entry$namespace)
    .scwb_profile_check_identity(inspected$identity, entry)
    installation <- Filter(function(x) identical(x$package, entry$package), receipt$packs)[[1L]]
    .scwb_profile_check_identity(inspected$identity, installation)
    operation <- names(inspected$identity$operation_definition_sha256)[[1L]]
    stopifnot(identical(wb_op_interface(operation)$source_pack$pack_sha256,
      installation$pack_sha256))
  }
  repeated <- scwb_standard_profile_activate(receipt_path, lib.loc = library)
  stopifnot(identical(result$packs$pack_sha256, repeated$packs$pack_sha256),
    identical(result$profile_sha256, repeated$profile_sha256))
  cat("PASS profile: wrong pin, lock collision, publication rollback, 61 ops, identities, idempotence\n")
} else if (identical(mode, "active_collision")) {
  fixture <- "scwbV2Reference"
  manifest <- system.file("scworkbench", "operation-pack.json", package = fixture,
    lib.loc = library, mustWork = TRUE)
  wb_operation_pack_activate(manifest, lib.loc = library)
  before <- wb_operation_packs()
  expect_error_code(scwb_standard_profile_activate(receipt_path,
    lib.loc = library), "ACTIVE_COLLISION")
  after <- wb_operation_packs()
  stopifnot(identical(before, after))
  cat("PASS active_collision: unapproved pack remains, standard set absent\n")
} else stop("unknown profile mode: ", mode)
