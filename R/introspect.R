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

#' Bundle status summary (developer helper)
#'
#' Prints core table existence and summarizes spaces/matrices/artifacts.
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @return Invisible list with tables.
#' @export
wb_status <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")

  tabs <- DBI::dbListTables(con)

  has <- function(x) if (x %in% tabs) "yes" else "no"

  cat("scworkbench bundle status\n")
  cat("  dir: ", bundle$dir %||% "<unknown>", "\n", sep = "")
  cat("  sqlite tables: ", length(tabs), "\n", sep = "")

  cat("  core tables:\n")
  core <- c(
    "cells",
    "spaces",
    "space_2d",
    "matrices",
    "features",
    "cell_sets",
    "cell_set_membership",
    "cell_set_recipes",
    "artifacts"
  )
  for (nm in core) {
    cat("    ", format(nm, width = 18), has(nm), "\n", sep = "")
  }

  # ---- spaces summary ----
  if ("spaces" %in% tabs) {
    have <- DBI::dbListFields(con, "spaces")
    want <- c("space_id", "dims", "storage", "source")
    cols <- intersect(want, have)

    sp <- DBI::dbGetQuery(
      con,
      paste0("SELECT ", paste(cols, collapse = ", "),
             " FROM spaces ORDER BY space_id;")
    )

    cat("\nspaces (", nrow(sp), "):\n", sep = "")
    if (nrow(sp) > 0) print(sp)

    # 2D coverage info if available
    if ("space_2d" %in% tabs) {
      cov <- DBI::dbGetQuery(con, "
        SELECT space_id, COUNT(*) AS n_cells
        FROM space_2d
        GROUP BY space_id
        ORDER BY space_id;
      ")
      cat("\nspace_2d coverage:\n")
      if (nrow(cov) > 0) print(cov) else cat("  <no rows>\n")
    }
  }

  # ---- matrices summary ----
  if ("matrices" %in% tabs) {
    have <- DBI::dbListFields(con, "matrices")
    want <- c("matrix_id", "assay", "layer", "feature_type", "n_features", "n_cells", "storage", "path")
    cols <- intersect(want, have)

    mats <- DBI::dbGetQuery(
      con,
      paste0("SELECT ", paste(cols, collapse = ", "),
             " FROM matrices ORDER BY matrix_id;")
    )

    cat("\nmatrices (", nrow(mats), "):\n", sep = "")
    if (nrow(mats) > 0) print(mats)
  }

  # ---- artifacts summary ----
  if ("artifacts" %in% tabs) {
    have <- DBI::dbListFields(con, "artifacts")
    if (all(c("type") %in% have)) {
      tab <- DBI::dbGetQuery(con, "
        SELECT type, COUNT(*) AS n
        FROM artifacts
        GROUP BY type
        ORDER BY n DESC, type;
      ")
      cat("\nartifacts by type:\n")
      if (nrow(tab) > 0) print(tab) else cat("  <no rows>\n")
    }
  }

  # ---- migration hints (keep minimal + accurate) ----
  needs <- character(0)
  if ("matrices" %in% tabs && !"matrix_cells" %in% tabs) {
    needs <- c(needs, "matrix_cells (optional; only if you want modality/cell coverage queries)")
  }
  if (length(needs)) {
    cat("\n⚠ missing recommended tables:\n")
    for (x in needs) cat("  - ", x, "\n", sep = "")
    cat("Run: wb_migrate_bundle(bundle)\n")
  }

  invisible(list(tables = tabs))
}

