#' Open an scworkbench bundle
#'
#' Opens a bundle directory and returns a handle containing:
#' - manifest
#' - SQLite connection
#' - bundle path
#'
#' @param bundle_dir Path to bundle directory
#' @param validate If TRUE, run wb_validate_bundle().
#' @param read_only If TRUE, open SQLite explicitly read-only and disable all
#'   schema migration or bundle mutation. Use for recipient inspection mounts.
#' @return A bundle handle
# pybench-parity: yes
# pybench-counterpart: pybench.bundle.open_bundle
# contract-note: manifest.json + manifest$storage$sqlite$path resolution must stay aligned
#' @export
wb_open_bundle <- function(bundle_dir, validate = FALSE, read_only = FALSE) {
  if (!dir.exists(bundle_dir)) stop("Bundle directory does not exist: ", bundle_dir)

  man_path <- file.path(bundle_dir, "manifest.json")
  if (!file.exists(man_path)) stop("Missing manifest.json in bundle: ", bundle_dir)

  manifest <- jsonlite::read_json(man_path, simplifyVector = TRUE)

  db_rel <- manifest$storage$sqlite$path
  if (is.null(db_rel)) stop("manifest.json missing storage$sqlite$path")

  db_path <- file.path(bundle_dir, db_rel)
  if (!file.exists(db_path)) stop("SQLite DB not found: ", db_path)

  con <- if (isTRUE(read_only)) {
    DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
  } else DBI::dbConnect(RSQLite::SQLite(), db_path)
  attr(con, "scworkbench_read_only") <- isTRUE(read_only)

  bundle <- list(
    dir = bundle_dir,
    manifest = manifest,
    con = con, read_only = isTRUE(read_only)
  )
  class(bundle) <- "scworkbench_bundle"

  if (isTRUE(validate)) {
    wb_validate_bundle(bundle_dir, read_only = read_only)
  }
  if (!isTRUE(read_only)) wb_migrate_artifacts(bundle)

  bundle
}

.wb_assert_bundle_writable <- function(bundle, action = "mutation") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(!isTRUE(bundle$read_only), paste0(action, " is unavailable: bundle was opened read_only=TRUE."))
  invisible(TRUE)
}

#' Close an scworkbench bundle
#'
#' @param bundle Bundle handle from [wb_open_bundle()].
#'
#' @return `TRUE` invisibly after closing the SQLite connection.
# pybench-parity: yes
# pybench-counterpart: pybench.bundle.close_bundle
#' @export
wb_close_bundle <- function(bundle) {
  if (inherits(bundle, "scworkbench_bundle") && !is.null(bundle$con)) {
    DBI::dbDisconnect(bundle$con)
  }
  invisible(TRUE)
}
