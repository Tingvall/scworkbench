# R/bundle_spaces.R

#' (Advanced) Add a space (embedding) to an existing bundle
#'
#' Writes coordinates through the canonical file-backed dense-space payload
#' contract. SQLite stores only registry, shape, path, and content identity.
#'
#' Prefer a fitting operation such as `pca_fit` or `umap_fit` for ordinary
#' analysis. This low-level writer is for controlled bundle assembly.
#'
#' @param bundle Bundle handle (from wb_open_bundle())
#' @param space_id String id for the space (user-defined)
#' @param coords A matrix/data.frame of coordinates with rownames = cell_id.
#'   If a data.frame, must contain either:
#'   - rownames as cell_id and numeric columns, OR
#'   - a "cell_id" column plus numeric columns.
#' @param description Optional description
#' @param source Optional source label (e.g., "PeakVI", "Scanpy")
#' @param overwrite If TRUE, replaces an existing space with same space_id
#' @param chunk Deprecated compatibility argument; HDF5 chunking is selected
#'   by the canonical writer.
# pybench-parity: yes
# pybench-counterpart: pybench.spaces_write.add_space / pybench.add_space
# contract-note: writes spaces + space_payloads, validates cell IDs, and refreshes manifest spaces
#' @export
wb_add_space <- function(bundle,
                         space_id,
                         coords,
                         description = NULL,
                         source = NULL,
                         overwrite = FALSE,
                         chunk = 20000) {
  .wb_assert_bundle_writable(bundle, "space mutation")
  mutation_route <- .wb_assert_mutation_context(
    bundle = bundle, action = "Low-level space writer wb_add_space()",
    allowed = c("assembly", "session_execution", "promotion", "ingestion"),
    replacement = "wb_attach_space()/wb_attach_apply() for declared ingestion, or a registered fitting operation through wb_session_run_op() and promotion"
  )
  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id),
             "space_id must be a non-empty string.")
  .wb_assert(!is.null(coords), "coords is required.")

  # ---- normalize coords to numeric matrix with rownames = cell_id ----
  if (is.data.frame(coords)) {
    if ("cell_id" %in% colnames(coords)) {
      cell_id <- as.character(coords$cell_id)
      mat <- coords[, setdiff(colnames(coords), "cell_id"), drop = FALSE]
      mat <- as.matrix(mat)
      rownames(mat) <- cell_id
    } else {
      mat <- as.matrix(coords)
      if (is.null(rownames(mat))) stop("coords data.frame must have rownames or a cell_id column.", call. = FALSE)
    }
  } else {
    mat <- as.matrix(coords)
    if (is.null(rownames(mat))) stop("coords matrix must have rownames = cell_id.", call. = FALSE)
  }

  storage.mode(mat) <- "double"
  .wb_assert(is.numeric(mat), "coords must be numeric.")
  .wb_assert(!anyNA(mat), "coords contains NA values.")
  .wb_assert(all(is.finite(mat)), "coords contains non-finite values (Inf/NaN).")

  cell_ids <- rownames(mat)
  dims <- ncol(mat)
  .wb_assert(dims >= 2, "coords must have at least 2 dimensions (ncol >= 2).")

  created_source <- if (is.null(source)) "ingest" else as.character(source)
  created_desc <- if (is.null(description)) space_id else as.character(description)
  .wb_space_payload_write(
    bundle, space_id = space_id, coords = mat, source = created_source,
    description = created_desc, overwrite = overwrite,
    provenance_identity = created_source
  )

  .wb_entity_lifecycle_upsert(bundle$con, "space", space_id, state = "current",
    bound = .wb_entity_is_provenance_bound(bundle, "space", space_id))

  # ---- update manifest.json from authoritative storage ----
  if (exists("wb_refresh_manifest", mode = "function")) {
    try(wb_refresh_manifest(bundle), silent = TRUE)
  }

  if (identical(mutation_route, "assembly")) {
    .wb_record_declared_ingestion(
      bundle = bundle, transaction_name = "assembly_add_space",
      space_ids = space_id, source = created_source
    )
  }


  invisible(list(
    space_id = space_id,
    dims = dims,
    n_cells = length(cell_ids),
    storage = .wb_space_payload_storage()
  ))
}
