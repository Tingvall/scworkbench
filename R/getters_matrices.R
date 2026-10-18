#' List matrices available in the bundle
#'
#' Lists registered matrices from the bundle SQLite (matrices table).
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param include_history Include ephemeral, superseded, rejected, and retracted identities.
#'
#' @return A data.frame with columns:
#'   matrix_id, layer, feature_type, n_features, n_cells, storage, path,
#'   organism, genome_build, genome_provider
#'
# pybench-parity: yes
# pybench-counterpart: pybench.getters.matrices
# contract-note: ordered by matrix_id
#' @export
wb_matrices <- function(bundle, include_history = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "matrices"),
             "matrices table not found in SQLite")
  .wb_ensure_matrix_contract_columns(con)

  # Strict schema: no dynamic column negotiation.
  history_filter <- if (.wb_table_exists(con, "entity_lifecycle")) "
    WHERE ? OR NOT EXISTS (
      SELECT 1 FROM entity_lifecycle el
      WHERE el.entity_kind = 'matrix' AND el.entity_id = matrices.matrix_id
        AND el.lifecycle_state <> 'current'
    )" else ""
  q <- paste0("
    SELECT matrix_id,
           layer,
           feature_type,
           n_features,
           n_cells,
           storage,
           path,
           organism,
           genome_build,
           genome_provider
    FROM matrices", history_filter, "
    ORDER BY matrix_id;
  ")

  DBI::dbGetQuery(con, q, params = if (nzchar(history_filter)) list(as.integer(isTRUE(include_history))) else NULL)
}


#' Read Multiple Features Across Cells
#'
#' Read a feature-by-cell block from a virtual matrix assembled from registered
#' fragments.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix id.
#' @param feature_ids Requested feature ids.
#' @param cell_ids Requested cell ids.
#' @param missing How to represent missing entries: `"zero"` or `"NA"`.
#' @param prefer_newest If `TRUE`, newer fragments overwrite older values when
#'   overlaps exist.
#'
#' @return A feature-by-cell matrix-like object aligned to `feature_ids` and
#'   `cell_ids`.
#'
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
    abs_path <- .wb_bundle_path_require(bundle, row$path[1], expected_type = "directory",
                                        purpose = paste0("matrix fragment ", row$fragment_id[1]))
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

# Core-owned, invocation-local physical read plan. Pack callbacks never receive
# it or its paths. A feature-partitioned scan gets one row-major scratch index
# rather than decoding the complete column-major source for every partition.
# This is a disposable equivalent representation, not a new logical fragment.
.wb_matrix_stream_reader <- function(bundle, matrix_id, chunk_axis,
    features = NULL, cells = NULL) {
  fragments <- wb_matrix_fragments(bundle, matrix_id)
  selected_features <- if (is.null(features)) NULL else as.character(features)
  selected_cells <- if (is.null(cells)) NULL else as.character(cells)
  fragment_features <- lapply(fragments$feature_ids_json, function(ids)
    as.character(jsonlite::fromJSON(ids)))
  fragment_cells <- lapply(fragments$cell_ids_json, function(ids)
    as.character(jsonlite::fromJSON(ids)))
  validate_selection <- function(selected, axes) {
    if (is.null(selected)) return(invisible(TRUE))
    .wb_assert(length(selected) > 0L && !anyNA(selected) &&
      all(nzchar(selected)) && !anyDuplicated(selected) &&
      all(selected %in% unlist(axes, use.names = FALSE)),
      "Matrix reader projection must select unique registered axis identities.")
  }
  validate_selection(selected_features, fragment_features)
  validate_selection(selected_cells, fragment_cells)
  root <- tempfile("scwb_matrix_reader_")
  dir.create(root)
  ready <- FALSE
  on.exit(if (!ready) unlink(root, recursive = TRUE), add = TRUE)
  matrices <- lapply(seq_len(nrow(fragments)), function(i) {
    matrix <- .wb_bp_open_matrix_dir(.wb_bundle_path_require(bundle,
      fragments$path[[i]], expected_type = "directory", purpose = "matrix reader"))
    features <- fragment_features[[i]]
    cells <- fragment_cells[[i]]
    .wb_assert(identical(as.integer(dim(matrix)),
      as.integer(c(length(features), length(cells)))),
      "Physical fragment dimensions differ from its registered axes.")
    # Registry feature/fragment axes remain authoritative. Do not reinterpret
    # incidental payload labels as a new feature identity namespace. Mirror
    # wb_slice's existing single-fragment physical-column alignment only.
    if (nrow(fragments) == 1L && length(colnames(matrix))) {
      physical <- as.character(colnames(matrix))
      .wb_assert(!anyDuplicated(physical) && setequal(physical, cells),
        "Physical fragment cell identities differ from registered coverage.")
      cells <- physical
    }
    # A lazy BPCells selection precedes the one-time physical index build.
    # It keeps grant order while excluding unrelated rows/columns from every
    # later read. No complete selected numerical matrix is materialized in R.
    if (!is.null(selected_features) || !is.null(selected_cells)) {
      keep_features <- if (is.null(selected_features)) features else
        selected_features[selected_features %in% features]
      keep_cells <- if (is.null(selected_cells)) cells else
        selected_cells[selected_cells %in% cells]
      if (!length(keep_features) || !length(keep_cells)) return(NULL)
      matrix <- matrix[match(keep_features, features),
        match(keep_cells, cells), drop = FALSE]
      features <- keep_features; cells <- keep_cells
    }
    if (identical(chunk_axis, "features") &&
        identical(BPCells::storage_order(matrix), "col"))
      matrix <- BPCells::transpose_storage_order(matrix,
        outdir = file.path(root, paste0("fragment_", i)), tmpdir = root,
        load_bytes = 4194304L, sort_bytes = 67108864L)
    list(matrix = matrix, features = features, cells = cells)
  })
  matrices <- Filter(Negate(is.null), matrices)
  read <- function(features, cells) {
    .wb_assert((is.null(selected_features) || all(features %in% selected_features)) &&
      (is.null(selected_cells) || all(cells %in% selected_cells)),
      "Requested matrix block is outside its selected reader projection.")
    out <- NULL
    for (source in matrices) {
      ri <- match(features, source$features)
      ci <- match(cells, source$cells)
      rr <- which(!is.na(ri)); cc <- which(!is.na(ci))
      if (!length(rr) || !length(cc)) next
      block <- .wb_as_sparse(source$matrix[ri[rr], ci[cc], drop = FALSE])
      if (length(rr) == length(features) && length(cc) == length(cells)) {
        dimnames(block) <- list(features, cells)
        return(block)
      }
      if (is.null(out)) out <- Matrix::sparseMatrix(i = integer(),
        j = integer(), x = numeric(), dims = c(length(features), length(cells)),
        dimnames = list(features, cells))
      out[rr, cc] <- block
    }
    if (is.null(out)) out <- Matrix::sparseMatrix(i = integer(), j = integer(), x = numeric(),
      dims = c(length(features), length(cells)), dimnames = list(features, cells))
    out
  }
  ready <- TRUE
  list(read = read, close = function() unlink(root, recursive = TRUE), root = root)
}
