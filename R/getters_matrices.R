#' List matrices available in the bundle
#' @export
wb_matrices <- function(bundle) {
  man <- bundle$manifest
  mats <- man$storage$matrices %||% list()

  if (length(mats) == 0) {
    return(data.frame(
      matrix_id = character(0),
      assay = character(0),
      feature_type = character(0),
      storage = character(0),
      stringsAsFactors = FALSE
    ))
  }

  df <- do.call(rbind, lapply(mats, function(m) {
    data.frame(
      matrix_id = m$matrix_id %||% NA_character_,
      assay = m$assay %||% NA_character_,
      feature_type = m$feature_type %||% NA_character_,
      storage = m$path %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }))
  df
}

#' @export
wb_matrix_read_features <- function(bundle,
                                    matrix_id,
                                    feature_ids,
                                    cell_ids,
                                    missing = c("zero", "NA"),
                                    prefer_newest = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(feature_ids) && length(feature_ids) > 0, "feature_ids invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")

  missing <- match.arg(missing)
  feature_ids <- as.character(feature_ids)
  cell_ids <- as.character(cell_ids)

  .wb_require_pkg("Matrix", "matrix batch read")
  .wb_require_pkg("BPCells", "matrix batch read")

  # Output skeleton
  nF <- length(feature_ids)
  nC <- length(cell_ids)

  if (missing == "zero") {
    out <- Matrix::Matrix(0, nrow = nF, ncol = nC, sparse = TRUE)
  } else {
    # NA-mode: start dense NA then convert to sparse only if you want later.
    # v1: keep dense for correctness; you can optimize later.
    out <- matrix(NA_real_, nrow = nF, ncol = nC)
  }
  rownames(out) <- feature_ids
  colnames(out) <- cell_ids

  frags <- wb_matrix_fragments(bundle, matrix_id)
  if (nrow(frags) == 0) return(out)

  # Order fragments: newest-wins means apply old -> new (later overwrites)
  # created_at is text; order it safely
  if ("created_at" %in% colnames(frags)) {
    ord <- order(frags$created_at, na.last = TRUE)
    if (isTRUE(prefer_newest)) frags <- frags[ord, , drop = FALSE] else frags <- frags[rev(ord), , drop = FALSE]
  }

  # precompute position maps in output
  feat_pos <- setNames(seq_along(feature_ids), feature_ids)
  cell_pos <- setNames(seq_along(cell_ids), cell_ids)

  for (i in seq_len(nrow(frags))) {
    row <- frags[i, , drop = FALSE]

    # Parse indices for this fragment
    feat_ids_frag <- jsonlite::fromJSON(row$feature_ids_json[1])
    cell_ids_frag <- jsonlite::fromJSON(row$cell_ids_json[1])

    # Which requested features/cells are in this fragment?
    feats_keep <- intersect(feature_ids, feat_ids_frag)
    cells_keep <- intersect(cell_ids, cell_ids_frag)
    if (!length(feats_keep) || !length(cells_keep)) next

    # Indices in fragment matrix
    rix <- match(feats_keep, feat_ids_frag)
    cix <- match(cells_keep, cell_ids_frag)

    # Open BPCells
    abs_path <- file.path(bundle$dir, row$path[1])
    .wb_assert(dir.exists(abs_path), paste0("Missing BPCells dir for fragment: ", abs_path))
    mat <- .wb_bp_open_matrix_dir(abs_path)

    # Slice
    block <- mat[rix, cix, drop = FALSE]

    # Normalize block to something we can write
    # If it's a base matrix -> ok; if it's a sparse Matrix -> ok; if BPCells returns S4 -> coerce
    if (!inherits(block, "Matrix") && !is.matrix(block)) {
      # many S4 numeric containers can be coerced via as.matrix
      block <- as.matrix(block)
    }

    # Map into output positions
    rr <- unname(feat_pos[feats_keep])
    cc <- unname(cell_pos[cells_keep])

    if (missing == "zero") {
      # write values into sparse out
      # simplest: assign into a sparse Matrix works but can be slow; v1 ok.
      out[rr, cc] <- as.matrix(block)
    } else {
      # NA-mode: overwrite with values, leaving NA where still missing
      out[rr, cc] <- as.matrix(block)
    }
  }

  out
}
