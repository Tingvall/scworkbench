# This is a sourced, process-local distribution profile, not package-load code.
# Installation does not activate any operation pack.

.scwb_profile_fail <- function(code, message) {
  stop(paste0("STANDARD_PROFILE_", code, ": ", message), call. = FALSE)
}

.scwb_profile_scalar <- function(value, field) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(value)) .scwb_profile_fail("LOCK_INVALID", paste0(field, " must be one nonempty string"))
  value
}

.scwb_profile_identity_field <- function(identity, field) {
  switch(field,
    namespace = identity$namespace,
    version = identity$package$version,
    manifest_source_sha256 = identity$manifest_source_identity$sha256,
    manifest_sha256 = identity$manifest_sha256,
    pack_sha256 = identity$pack_sha256)
}

.scwb_profile_check_identity <- function(identity, pinned) {
  fields <- c("namespace", "version", "manifest_source_sha256", "manifest_sha256")
  if (!is.null(pinned$pack_sha256)) fields <- c(fields, "pack_sha256")
  for (field in fields) {
    actual <- .scwb_profile_identity_field(identity, field)
    expected <- pinned[[field]]
    if (!identical(as.character(actual), as.character(expected))) {
      .scwb_profile_fail("WRONG_PIN", paste0(pinned$package, " ", field,
        " differs from the standard profile lock"))
    }
  }
  if (!identical(as.character(identity$package$name), as.character(pinned$package))) {
    .scwb_profile_fail("WRONG_PIN", paste0(pinned$package, " installed package identity differs"))
  }
  invisible(TRUE)
}

.scwb_profile_read_lock <- function() {
  path <- system.file("standard_profile", "profile.json", package = "scworkbench",
                      mustWork = TRUE)
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

.scwb_profile_tree_sha256 <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, include.dirs = FALSE, no.. = TRUE), method = "radix")
  if (any(nzchar(Sys.readlink(paths)))) .scwb_profile_fail(
    "TREE_INVALID", "installed package contains a symbolic link")
  relative <- substring(paths, nchar(root) + 2L)
  digest::digest(lapply(seq_along(paths), function(index) list(
    path = relative[[index]], sha256 = digest::digest(paths[[index]],
      algo = "sha256", file = TRUE))), algo = "sha256")
}

.scwb_profile_read_receipt <- function(receipt_path) {
  if (!is.character(receipt_path) || length(receipt_path) != 1L ||
      is.na(receipt_path) || !file.exists(receipt_path)) .scwb_profile_fail(
    "RECEIPT_REQUIRED", "a profile-installer receipt path is required")
  jsonlite::fromJSON(receipt_path, simplifyVector = FALSE)
}

.scwb_profile_preflight <- function(lock, receipt, lib.loc = NULL) {
  if (!identical(lock$schema_version, "scworkbench.standard_profile.v1") ||
      !is.list(lock$packs) || length(lock$packs) != 7L ||
      !is.list(lock$core_operations) || length(lock$core_operations) != 5L ||
      !identical(as.integer(lock$packed_operation_count), 57L) ||
      !identical(lock$core_start_commit,
        "0aaa68893e595993c2664e104f7e0dc20702f960") ||
      !identical(lock$pybench_source_commit,
        "f815def0127b7a63a5e81455c270cff6572dc8ea")) {
    .scwb_profile_fail("LOCK_INVALID", "profile shape or declared operation totals differ")
  }
  lock_path <- system.file("standard_profile", "profile.json",
    package = "scworkbench", mustWork = TRUE)
  profile_sha <- digest::digest(lock_path, algo = "sha256", file = TRUE)
  if (!identical(receipt$schema_version,
        "scworkbench.standard_profile.installation_receipt.v1") ||
      !identical(receipt$profile_sha256, profile_sha) ||
      !identical(receipt$pybench_source_commit, lock$pybench_source_commit) ||
      !is.character(receipt$core_source_commit) ||
      length(receipt$core_source_commit) != 1L ||
      !grepl("^[0-9a-f]{40}$", receipt$core_source_commit) ||
      !is.character(receipt$latent_python_entry) ||
      length(receipt$latent_python_entry) != 1L ||
      !nzchar(receipt$latent_python_entry) ||
      !is.list(receipt$packs) || length(receipt$packs) != 7L) {
    .scwb_profile_fail("RECEIPT_MISMATCH", "installation receipt does not bind this profile and PyBench pin")
  }
  configured_python <- Sys.getenv("SCWB_LATENT_PYTHON", unset = "")
  if (!nzchar(configured_python) || !file.exists(configured_python) ||
      !identical(file.path(normalizePath(dirname(configured_python),
        winslash = "/", mustWork = TRUE), basename(configured_python)),
        receipt$latent_python_entry)) .scwb_profile_fail(
    "RECEIPT_MISMATCH", "latent Python entry differs from the verified installation")
  core_path <- find.package("scworkbench")
  if (!identical(receipt$core_installed_tree_sha256,
      .scwb_profile_tree_sha256(core_path)) ||
      !identical(receipt$core_version,
        as.character(utils::packageVersion("scworkbench")))) {
    .scwb_profile_fail("RECEIPT_MISMATCH", "installed core package differs from the receipt")
  }
  core <- vapply(lock$core_operations, .scwb_profile_scalar, character(1), "core operation")
  pinned <- lock$packs
  packages <- vapply(pinned, function(x) .scwb_profile_scalar(x$package, "package"), character(1))
  namespaces <- vapply(pinned, function(x) .scwb_profile_scalar(x$namespace, "namespace"), character(1))
  if (anyDuplicated(packages) || anyDuplicated(namespaces) || anyDuplicated(core)) {
    .scwb_profile_fail("LOCK_COLLISION", "duplicate package, namespace, or core operation")
  }
  active <- scworkbench::wb_operation_packs()
  if (nrow(active) && any(!active$namespace %in% namespaces)) {
    .scwb_profile_fail("ACTIVE_COLLISION", "an operation pack outside the locked standard set is active")
  }
  for (index in seq_along(pinned)) {
    entry <- pinned[[index]]
    installed <- receipt$packs[[index]]
    for (field in c("version", "source_commit", "manifest_source_sha256",
                    "manifest_sha256")) {
      .scwb_profile_scalar(entry[[field]], paste0(entry$package, " ", field))
    }
    if (!identical(installed$source_commit, entry$source_commit) ||
        !identical(installed$package, entry$package) ||
        !identical(installed$namespace, entry$namespace) ||
        !identical(installed$version, entry$version) ||
        !identical(as.integer(installed$operation_count),
          as.integer(entry$operation_count)) ||
        !identical(installed$manifest_source_sha256, entry$manifest_source_sha256) ||
        !identical(installed$manifest_sha256, entry$manifest_sha256)) {
      .scwb_profile_fail("RECEIPT_MISMATCH", paste0(entry$package,
        " receipt source or manifest pin differs"))
    }
    .scwb_profile_scalar(installed$pack_sha256,
      paste0(entry$package, " installed pack identity"))
    if (length(entry$operation_count) != 1L || is.na(entry$operation_count) ||
        as.integer(entry$operation_count) < 1L) {
      .scwb_profile_fail("LOCK_INVALID", paste0(entry$package, " operation_count is invalid"))
    }
    if (!requireNamespace(entry$package, quietly = TRUE, lib.loc = lib.loc)) {
      .scwb_profile_fail("MISSING_PACK", paste0(entry$package, " is not installed in the selected library"))
    }
  }
  validated <- lapply(seq_along(pinned), function(index) {
    entry <- pinned[[index]]
    record <- scworkbench::wb_operation_pack_validate(entry$package, lib.loc = lib.loc)
    .scwb_profile_check_identity(record$identity, entry)
    .scwb_profile_check_identity(record$identity, receipt$packs[[index]])
    operations <- names(record$identity$operation_definition_sha256)
    if (!identical(length(operations), as.integer(entry$operation_count)) ||
        anyDuplicated(operations)) {
      .scwb_profile_fail("WRONG_PIN", paste0(entry$package, " operation inventory differs"))
    }
    record
  })
  all_packed <- unlist(lapply(validated, function(x)
    names(x$identity$operation_definition_sha256)), use.names = FALSE)
  if (length(all_packed) != 57L || anyDuplicated(all_packed)) {
    .scwb_profile_fail("OPERATION_COLLISION", "the seven packs do not define 57 distinct operations")
  }
  if (nrow(active)) {
    for (index in seq_len(nrow(active))) {
      found <- which(namespaces == active$namespace[[index]])
      inspected <- scworkbench::wb_operation_pack_inspect(active$namespace[[index]])
      .scwb_profile_check_identity(inspected$identity, pinned[[found]])
      .scwb_profile_check_identity(inspected$identity, receipt$packs[[found]])
    }
  }
  active_names <- if (!nrow(active)) character() else unlist(lapply(active$namespace,
    function(namespace) paste0(namespace, "::",
      names(scworkbench::wb_operation_pack_inspect(namespace)$operations))),
    use.names = FALSE)
  observed_core <- setdiff(scworkbench::wb_list_ops(), active_names)
  if (!identical(sort(observed_core, method = "radix"), sort(core, method = "radix"))) {
    .scwb_profile_fail("CORE_CATALOG", "the no-pack core operation catalog differs from the five-operation profile")
  }
  if (length(intersect(core, all_packed))) {
    .scwb_profile_fail("OPERATION_COLLISION", "a packed operation shadows the core catalog")
  }
  list(pinned = pinned, installed = receipt$packs, validated = validated, core = core,
       packed = all_packed, initially_active = active$namespace)
}

.scwb_standard_profile_activate_locked <- function(lock, receipt, lib.loc = NULL) {
  preflight <- .scwb_profile_preflight(lock, receipt, lib.loc)
  newly_active <- character()
  committed <- FALSE
  on.exit(if (!committed) for (namespace in rev(newly_active))
    scworkbench::wb_operation_pack_unload(namespace), add = TRUE)
  for (index in seq_along(preflight$pinned)) {
    entry <- preflight$pinned[[index]]
    if (entry$namespace %in% preflight$initially_active) next
    manifest <- system.file("scworkbench", "operation-pack.json",
      package = entry$package, lib.loc = lib.loc, mustWork = TRUE)
    activated <- tryCatch(scworkbench::wb_operation_pack_activate(manifest,
      lib.loc = lib.loc), error = function(error) .scwb_profile_fail(
        "ACTIVATION_FAILED", paste0(entry$package, ": ", conditionMessage(error))))
    newly_active <- c(newly_active, entry$namespace)
    .scwb_profile_check_identity(activated$identity, entry)
    .scwb_profile_check_identity(activated$identity, preflight$installed[[index]])
  }
  observed <- scworkbench::wb_operation_packs()
  operations <- scworkbench::wb_list_ops()
  if (!identical(sort(observed$namespace, method = "radix"),
                 sort(vapply(preflight$pinned, `[[`, character(1), "namespace"), method = "radix")) ||
      length(operations) != 62L ||
      !setequal(operations, c(preflight$core, preflight$packed))) {
    .scwb_profile_fail("PUBLICATION_INCOMPLETE", "activated catalog differs from the locked 62 operations")
  }
  committed <- TRUE
  invisible(list(schema_version = "scworkbench.standard_profile.activation.v1",
    core_source_commit = receipt$core_source_commit,
    pybench_source_commit = receipt$pybench_source_commit,
    profile_sha256 = digest::digest(
      system.file("standard_profile", "profile.json", package = "scworkbench", mustWork = TRUE),
      algo = "sha256", file = TRUE),
    packs = observed, operations = operations))
}

#' Explicitly activate the seven pinned standard operation packs.
#'
#' Source this file into the calling R process after installing scworkbench and
#' the seven pack packages. Activation is never triggered by installation or
#' library(scworkbench). SCWB_LATENT_PYTHON must name the intended CPU Python
#' runtime before scwbLatent can pass its own activation preflight.
#'
#' @param receipt_path Receipt written by the official source-verifying
#'   installer for this installed package instance. A caller-authored receipt
#'   does not establish source authenticity.
#' @param lib.loc Optional R library containing the exact pinned pack packages.
#' @return An invisible activation record. wb_operation_packs() and each
#'   operation's source_pack show the authenticated runtime identities.
scwb_standard_profile_activate <- function(receipt_path, lib.loc = NULL) {
  .scwb_standard_profile_activate_locked(.scwb_profile_read_lock(),
    .scwb_profile_read_receipt(receipt_path), lib.loc)
}
