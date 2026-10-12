test_promotion_runtime_fingerprint_metadata_parity_contract <- function() {
  before <- loadedNamespaces()
  actual <- scworkbench:::.wb_promotion_runtime_fingerprint()
  stopifnot(identical(before, loadedNamespaces()),
    identical(names(actual), c("scworkbench_version", "r_version", "source_revision",
      "container_digest", "packages")),
    identical(names(actual$packages), c("BPCells", "Matrix", "irlba", "uwot", "igraph")))
  # Historical oracle runs after the no-loading assertion, so comparison does
  # not hide namespace-loading side effects in the current implementation.
  legacy <- list(
    scworkbench_version = as.character(utils::packageVersion("scworkbench")),
    r_version = R.version.string,
    source_revision = Sys.getenv("SCWORKBENCH_SOURCE_REVISION", unset = NA_character_),
    container_digest = Sys.getenv("SCWORKBENCH_CONTAINER_DIGEST", unset = NA_character_),
    packages = vapply(c("BPCells", "Matrix", "irlba", "uwot", "igraph"), function(pkg) {
      if (!requireNamespace(pkg, quietly = TRUE)) return(NA_character_)
      as.character(utils::packageVersion(pkg))
    }, character(1)))
  stopifnot(identical(actual, legacy), identical(
    scworkbench:::.wb_operation_pack_canonical_json(actual),
    scworkbench:::.wb_operation_pack_canonical_json(legacy)))
  TRUE
}

test_promotion_runtime_fingerprint_metadata_loadability_contract <- function() {
  core_library <- Sys.getenv("SCWB_CONTRACT_INSTALLED_LIBRARY", unset = "")
  if (!nzchar(core_library)) {
    package_root <- find.package("scworkbench")
    if (file.exists(file.path(package_root, "Meta", "package.rds")))
      core_library <- dirname(normalizePath(package_root, mustWork = TRUE))
  }
  if (nzchar(core_library)) {
    core_target <- normalizePath(core_library, mustWork = TRUE)
    stopifnot(file.exists(file.path(core_target, "scworkbench", "Meta", "package.rds")))
    core_mode <- "installed"
  } else {
    core_target <- normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = getwd()),
      mustWork = TRUE)
    stopifnot(all(file.exists(file.path(core_target, c("DESCRIPTION", "NAMESPACE", "R/primitives.R")))))
    core_mode <- "source"
  }
  root <- tempfile("promotion_fingerprint_metadata_")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  source <- file.path(root, "fixture")
  lib <- file.path(root, "library")
  dir.create(source); dir.create(file.path(source, "R")); dir.create(lib)
  pkg <- "scwbFingerprintUnloadableFixture"
  writeLines(c(paste0("Package: ", pkg), "Version: 0.0.1",
    "Title: Unloadable Package Metadata Fixture", "Description: Tests metadata inventory without namespace evaluation.",
    "Authors@R: person('Fixture', 'Author', email='fixture@example.invalid', role=c('aut','cre'))",
    "License: MIT", "Encoding: UTF-8"), file.path(source, "DESCRIPTION"))
  writeLines(character(), file.path(source, "NAMESPACE"))
  writeLines(c(".onLoad <- function(libname, pkgname) {",
    "  marker <- Sys.getenv('SCWB_FINGERPRINT_FIXTURE_LOAD_MARKER', '')",
    "  if (nzchar(marker)) writeLines('onLoad executed', marker)",
    "  stop('fingerprint fixture intentionally unloadable')", "}"),
    file.path(source, "R", "zzz.R"))
  install <- system2(file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--no-test-load", "--no-multiarch",
      paste0("--library=", shQuote(lib)), shQuote(source)),
    stdout = TRUE, stderr = TRUE)
  status <- attr(install, "status")
  stopifnot(is.null(status) || identical(status, 0L))
  unreadable <- "scwbFingerprintUnreadableFixture"
  dir.create(file.path(lib, unreadable))
  writeLines(c(paste0("Package: ", unreadable), "Title: Missing Version Metadata"),
    file.path(lib, unreadable, "DESCRIPTION"))
  marker <- file.path(root, "onload.marker")
  child <- file.path(root, "verify.R")
  writeLines(c(
    "args <- commandArgs(TRUE)",
    ".libPaths(c(args[[2]], .libPaths()))",
    "if (args[[6]] == 'installed') {",
    "  .libPaths(c(args[[2]], args[[1]], .libPaths()))",
    "  library(scworkbench, lib.loc=args[[1]])",
    "  stopifnot(identical(normalizePath(find.package('scworkbench')), normalizePath(file.path(args[[1]],'scworkbench'))))",
    "} else {",
    "  stopifnot(args[[6]] == 'source')",
    "  devtools::load_all(args[[1]], quiet=TRUE)",
    "  stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('scworkbench'),'path')), normalizePath(args[[1]])))",
    "}",
    "cat('FINGERPRINT_METADATA_BOOTSTRAP mode=', args[[6]], ' target=', args[[1]], '\\n', sep='')",
    "Sys.setenv(SCWB_FINGERPRINT_FIXTURE_LOAD_MARKER=args[[4]])",
    "before <- loadedNamespaces()",
    "version <- scworkbench:::.wb_promotion_package_version(args[[3]])",
    "fingerprint <- scworkbench:::.wb_promotion_runtime_fingerprint()",
    "stopifnot(identical(version, '0.0.1'), !file.exists(args[[4]]), identical(before, loadedNamespaces()), !args[[3]] %in% loadedNamespaces())",
    "stopifnot(is.na(scworkbench:::.wb_promotion_package_version('scwbFingerprintMissingFixture')), is.na(scworkbench:::.wb_promotion_package_version(args[[5]])), identical(before, loadedNamespaces()))",
    "loadable <- requireNamespace(args[[3]], quietly=TRUE)",
    "stopifnot(identical(loadable, FALSE), file.exists(args[[4]]), !args[[3]] %in% loadedNamespaces())",
    "cat('FINGERPRINT_METADATA unloaded_version=PASS no_namespace_or_onLoad=PASS missing_unreadable_NA=PASS independent_loadability_reject=PASS\\n')"), child)
  output <- system2(file.path(R.home("bin"), "Rscript"),
    vapply(c(child, core_target, lib, pkg, marker,
      unreadable, core_mode), shQuote, character(1)), stdout=TRUE, stderr=TRUE)
  status <- attr(output, "status")
  cat(paste(output, collapse="\n"), "\n")
  stopifnot(is.null(status) || identical(status, 0L), file.exists(marker))
  TRUE
}

test_promotion_runtime_fingerprint_legacy_public_commit_contract <- function() {
  root <- tempfile("promotion_fingerprint_legacy_")
  bundle <- wb_init_bundle(root)
  session <- NULL
  on.exit({
    if (!is.null(session)) try(wb_session_discard(session), silent=TRUE)
    try(wb_close_bundle(bundle), silent=TRUE)
    unlink(root, recursive=TRUE)
  }, add=TRUE)
  wb_define_cells(bundle, c("cell_b", "cell_a"), metadata=data.frame(
    cell_id=c("cell_b", "cell_a"), label=c("B", "A")))
  result <- wb_session_run_op(wb_session_new(), bundle, "metadata_cell_vector",
    inputs=list(source_column="label", vector_name="labels", value_type="categorical",
      missing_policy="error", cell_set="all", min_cells=1L))
  session <- result$session
  before <- scworkbench:::.wb_prov_payload_identity(bundle, result$run$outputs[[1L]])
  promoted <- wb_session_promote_current(bundle, session)
  stopifnot(nrow(promoted$promoted)==1L)
  loaded <- wb_art_load(bundle, promoted$promoted$artifact_id[[1L]])
  after <- scworkbench:::.wb_prov_payload_identity(bundle, loaded)
  stopifnot(identical(before$content_sha256, after$content_sha256))
  commits <- DBI::dbGetQuery(bundle$con,
    "SELECT runtime_fingerprint_json FROM prov_commits WHERE state='complete';")
  stopifnot(nrow(commits)==1L)
  expected <- scworkbench:::.wb_promotion_runtime_fingerprint()
  stopifnot(identical(commits$runtime_fingerprint_json[[1L]],
    as.character(jsonlite::toJSON(expected, auto_unbox=TRUE, null="null"))))
  TRUE
}
