#' Open an scworkbench bundle
#'
#' Opens a bundle directory and returns a handle containing:
#' - manifest
#' - SQLite connection
#' - bundle path
#'
#' @param bundle_dir Path to bundle directory
#' @param validate If TRUE, run wb_validate_bundle()
#' @return A bundle handle
#' @export
wb_open_bundle <- function(bundle_dir, validate = FALSE) {
  if (!dir.exists(bundle_dir)) stop("Bundle directory does not exist: ", bundle_dir)

  man_path <- file.path(bundle_dir, "manifest.json")
  if (!file.exists(man_path)) stop("Missing manifest.json in bundle: ", bundle_dir)

  manifest <- jsonlite::read_json(man_path, simplifyVector = TRUE)

  db_rel <- manifest$storage$sqlite$path
  if (is.null(db_rel)) stop("manifest.json missing storage$sqlite$path")

  db_path <- file.path(bundle_dir, db_rel)
  if (!file.exists(db_path)) stop("SQLite DB not found: ", db_path)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  bundle <- list(
    dir = bundle_dir,
    manifest = manifest,
    con = con
  )
  class(bundle) <- "scworkbench_bundle"

  if (isTRUE(validate)) {
    wb_validate_bundle(bundle_dir)
  }
  wb_migrate_artifacts(bundle)

  bundle
}

#' Close an scworkbench bundle
#' @param bundle Bundle handle from wb_open_bundle()
#' @export
wb_close_bundle <- function(bundle) {
  if (inherits(bundle, "scworkbench_bundle") && !is.null(bundle$con)) {
    DBI::dbDisconnect(bundle$con)
  }
  invisible(TRUE)
}

