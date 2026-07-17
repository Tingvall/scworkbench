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
  if (!is.character(bundle_dir) || length(bundle_dir) != 1L || is.na(bundle_dir) || !nzchar(bundle_dir)) {
    stop(
      "wb_validate_bundle(): bundle_dir must be one non-empty path string; pass bundle$dir, not an open scworkbench_bundle handle.",
      call. = FALSE
    )
  }
  failed_marker <- file.path(bundle_dir, "INGEST_FAILED.json")
  if (file.exists(failed_marker)) {
    stop("Bundle ingestion failed/incomplete; see marker: ", failed_marker, call. = FALSE)
  }

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

    frags <- tryCatch(wb_matrix_fragments(b, as.character(mrow$matrix_id)), error = function(e) data.frame())
    if (nrow(frags) > 1L) {
      feat_seen <- character(0)
      cell_seen <- character(0)
      for (j in seq_len(nrow(frags))) {
        frow <- frags[j, , drop = FALSE]
        frag_path <- file.path(bundle_dir, frow$path[1])
        if (!dir.exists(frag_path)) stop("Missing BPCells matrix fragment directory: ", frag_path)
        fm <- .wb_bp_open_matrix_dir(frag_path)
        fd <- dim(fm)
        if (length(fd) != 2) stop("Matrix fragment has invalid dim(): ", frow$fragment_id[1])
        if (fd[1] != frow$n_features[1]) stop("Matrix fragment n_features mismatch: ", frow$fragment_id[1])
        if (fd[2] != frow$n_cells[1]) stop("Matrix fragment n_cells mismatch: ", frow$fragment_id[1])
        feat_seen <- unique(c(feat_seen, as.character(jsonlite::fromJSON(frow$feature_ids_json[1]))))
        cell_seen <- unique(c(cell_seen, as.character(jsonlite::fromJSON(frow$cell_ids_json[1]))))
      }
      if (length(feat_seen) != mrow$n_features) stop("Logical matrix n_features mismatch across fragments: ", mrow$matrix_id)
      if (length(cell_seen) != mrow$n_cells) stop("Logical matrix n_cells mismatch across fragments: ", mrow$matrix_id)
      next
    }

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
