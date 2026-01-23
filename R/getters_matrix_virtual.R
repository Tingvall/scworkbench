wb_matrix_fragments <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && nzchar(matrix_id), "matrix_id invalid")
  con <- bundle$con

  .wb_ensure_matrix_fragments_table(con)

  DBI::dbGetQuery(
    con,
    "SELECT fragment_id, matrix_id, storage, path,
            n_features, n_cells,
            feature_ids_json, cell_ids_json,
            source, created_at, description
     FROM matrix_fragments
     WHERE matrix_id = ?
     ORDER BY created_at ASC;",
    params = list(matrix_id)
  )
}

# Read ONE feature vector for a set of cells, resolving across fragments.
# Returns: named numeric vector (names = requested cell_ids), NA where missing.
wb_matrix_read_feature <- function(bundle, matrix_id, feature_id, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(feature_id) && length(feature_id) == 1 && nzchar(feature_id), "feature_id invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")

  cell_ids <- as.character(cell_ids)
  out <- rep(NA_real_, length(cell_ids))
  names(out) <- cell_ids

  frags <- wb_matrix_fragments(bundle, matrix_id)
  if (nrow(frags) == 0) return(out)

  .wb_require_pkg("BPCells", "matrix read")

  for (i in seq_len(nrow(frags))) {
    row <- frags[i, , drop = FALSE]

    # IMPORTANT: scalar extraction with [1]
    feat_json <- row$feature_ids_json[1]
    cell_json <- row$cell_ids_json[1]

    if (is.null(feat_json) || is.na(feat_json) || !nzchar(feat_json)) next
    if (is.null(cell_json) || is.na(cell_json) || !nzchar(cell_json)) next

    feat_ids <- jsonlite::fromJSON(feat_json)
    cell_ids_frag <- jsonlite::fromJSON(cell_json)

    # feature present?
    rix <- match(feature_id, feat_ids)
    if (is.na(rix)) next

    # requested cells present?
    cix <- match(cell_ids, cell_ids_frag)
    keep <- which(!is.na(cix))
    if (!length(keep)) next

    abs_path <- file.path(bundle$dir, row$path[1])
    .wb_assert(dir.exists(abs_path), paste0("Missing BPCells dir for fragment: ", abs_path))

    mat <- .wb_bp_open_matrix_dir(abs_path)

    # Read slice and coerce robustly (THIS is the big fix)
    slice <- mat[rix, cix[keep], drop = TRUE]

    # slice might be S4; force to plain numeric vector
    vals <- as.numeric(as.matrix(slice))

    # Assign back
    out[keep] <- vals
  }

  out
}

