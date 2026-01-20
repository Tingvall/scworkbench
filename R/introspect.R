#' Bundle schema snapshot (debug helper)
#' @export
wb_bundle_schema <- function(bundle) {
  con <- bundle$con
  tabs <- DBI::dbListTables(con)

  info <- function(tbl) {
    if (!tbl %in% tabs) return(NULL)
    DBI::dbGetQuery(con, paste0("PRAGMA table_info(", tbl, ");"))
  }

  list(
    tables = tabs,
    cells = info("cells"),
    spaces = info("spaces"),
    space_2d = info("space_2d"),
    space_coords = info("space_coords"),
    matrices = info("matrices"),
    matrix_cells = info("matrix_cells"),
    artifacts = info("artifacts"),
    runs = info("runs")
  )
}

# R/status.R

#' Bundle status summary (developer helper)
#'
#' Prints what core tables exist, and summarizes spaces/matrices.
#' @export
wb_status <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")

  con <- bundle$con
  tabs <- DBI::dbListTables(con)

  has <- function(x) if (x %in% tabs) "yes" else "no"

  cat("scworkbench bundle status\n")
  cat("  dir: ", bundle$dir %||% "<unknown>", "\n", sep = "")
  cat("  sqlite tables: ", length(tabs), "\n", sep = "")
  cat("  core tables:\n")
  cat("    cells:        ", has("cells"), "\n", sep = "")
  cat("    spaces:       ", has("spaces"), "\n", sep = "")
  cat("    space_2d:     ", has("space_2d"), "\n", sep = "")
  cat("    space_coords: ", has("space_coords"), "\n", sep = "")
  cat("    matrices:     ", has("matrices"), "\n", sep = "")
  cat("    matrix_cells: ", has("matrix_cells"), "\n", sep = "")
  cat("    artifacts:    ", has("artifacts"), "\n", sep = "")
  cat("    runs:         ", has("runs"), "\n", sep = "")

  if ("spaces" %in% tabs) {
    sp <- DBI::dbGetQuery(con, "SELECT space_id, dims, storage, source FROM spaces ORDER BY space_id;")
    cat("\nspaces (", nrow(sp), "):\n", sep = "")
    if (nrow(sp) > 0) print(sp)
  }

  if ("matrices" %in% tabs) {
    mats <- DBI::dbGetQuery(con, "SELECT matrix_id, assay, layer, feature_type, n_features, n_cells, storage, path FROM matrices ORDER BY matrix_id;")
    cat("\nmatrices (", nrow(mats), "):\n", sep = "")
    if (nrow(mats) > 0) print(mats)
  }

  # migration hints
  needs <- character(0)
  if ("matrices" %in% tabs && !"matrix_cells" %in% tabs) needs <- c(needs, "matrix_cells (needed for modality coverage)")
  if (length(needs)) {
    cat("\n⚠ missing recommended tables:\n")
    for (x in needs) cat("  - ", x, "\n", sep = "")
    cat("Run: wb_migrate_bundle(bundle)\n")
  }

  invisible(list(tables = tabs))
}

