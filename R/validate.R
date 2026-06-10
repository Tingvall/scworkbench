#' Validate an scworkbench bundle on disk
#'
#' Ensures internal consistency between:
#' - manifest
#' - SQLite tables
#' - BPCells matrices
#'
#' @param bundle_dir Path to bundle directory
#' @return TRUE if valid, otherwise errors
#' @export
wb_validate_bundle <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir, validate = FALSE)
  on.exit(wb_close_bundle(b), add = TRUE)

  con <- b$con
  manifest <- b$manifest

  # ---- required tables ----
  required_tables <- c("cells", "datasets", "features", "matrices")
  existing_tables <- DBI::dbListTables(con)

  missing <- setdiff(required_tables, existing_tables)
  if (length(missing) > 0) {
    stop("Missing required tables: ", paste(missing, collapse = ", "))
  }

  # ---- cells ----
  cells <- DBI::dbReadTable(con, "cells")
  if (!"cell_id" %in% colnames(cells)) stop("cells table missing cell_id")
  if (anyDuplicated(cells$cell_id)) stop("Duplicate cell_id values in cells table")

  n_cells <- nrow(cells)

  # ---- datasets ----
  ds <- DBI::dbReadTable(con, "datasets")
  if (sum(ds$n_cells) != n_cells) {
    stop("Dataset cell counts do not sum to total n_cells")
  }

  # ---- matrices ----
  mats <- DBI::dbReadTable(con, "matrices")

  for (i in seq_len(nrow(mats))) {
    mrow <- mats[i, ]

    mat_path <- file.path(bundle_dir, mrow$path)
    if (!dir.exists(mat_path)) stop("Missing BPCells matrix directory: ", mat_path)

    # open matrix lazily
    m <- wb_matrix(b, mrow$matrix_id)
    d <- dim(m)

    if (length(d) != 2) stop("Matrix has invalid dim(): ", mrow$matrix_id)
    if (d[2] != n_cells) stop("Matrix n_cells mismatch: ", mrow$matrix_id)
    if (d[1] != mrow$n_features) stop("Matrix n_features mismatch: ", mrow$matrix_id)
  }

  TRUE
}
