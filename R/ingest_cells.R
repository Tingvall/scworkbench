#' Ingest new cells into an existing bundle as a named membership-based cell set
#'
#' - Inserts new rows into `cells` (cell_id + dataset_id)
#' - Writes membership rows into `cell_set_membership` for set:<set_name>
#' - Optionally ingests metadata and spaces for those cells
#' - Optionally ingests matrices via wb_attach_to_cells() (recommended canonical path)
#'
#' NOTE: dev-mode, fresh bundles only: we do NOT use legacy `cells.cell_set`.
#'
#' @param bundle scworkbench bundle handle (opened)
#' @param set_name Name of ingested set (stored in membership as cell_set = "set:<name>")
#' @param cell_ids Character vector of new cell IDs
#' @param metadata Optional data.frame. First column treated as cell_id if no "cell_id" column.
#' @param spaces Optional named list of spaces. Each entry can be:
#'   - 2D wide df: first col cell_id, next cols x,y (no colnames required)
#'   - high-D wide matrix/df: rownames=cell_id OR first col cell_id
#'   - long df: first col cell_id, second col dim, third col value (no colnames required)
#' @param matrices Optional named list passed to wb_attach_to_cells(matrices=...)
#' @param overwrite If TRUE, allow re-ingesting existing cell_ids (NOT implemented yet)
#' @param source Provenance string stored in membership rows / space registry
#' @param created_by Optional provenance
#' @export
wb_ingest_cells <- function(
    bundle,
    set_name,
    cell_ids,
    metadata = NULL,
    spaces = list(),
    matrices = list(),
    overwrite = FALSE,
    source = "ingest",
    created_by = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  .wb_assert_mutation_context(
    bundle = bundle, action = "Low-level cell ingestion writer wb_ingest_cells()",
    allowed = c("assembly", "ingestion"),
    replacement = "wb_ingest_apply() or a wb_bundle_from_*() declared ingestion transaction"
  )
  .wb_assert(is.character(set_name) && length(set_name) == 1 && nzchar(set_name),
             "set_name must be a non-empty string")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0,
             "cell_ids must be a non-empty character vector")

  con <- bundle$con
  cell_ids <- as.character(cell_ids)
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0, "cell_ids empty after cleaning")
  .wb_assert(!anyDuplicated(cell_ids), "wb_ingest_cells(): duplicate cell IDs are forbidden")

  cell_set <- paste0("set:", set_name)

  # Ensure schema primitives exist

  .wb_ensure_cell_set_membership_table(con)

  # -------------------------
  # 1) Validate non-existence (dev safety)
  # -------------------------
  cl <- .wb_sql_in_json(cell_ids)
  existing <- DBI::dbGetQuery(
    con,
    paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"),
    params = cl$params
  )$cell_id
  existing <- as.character(existing)

  if (length(existing) > 0) {
    if (!isTRUE(overwrite)) {
      stop(
        "Some cell_ids already exist in bundle (overwrite=FALSE). First few: ",
        paste(head(existing, 10), collapse = ", "),
        call. = FALSE
      )
    }
    stop("overwrite=TRUE not implemented yet for safety.", call. = FALSE)
  }

  # -------------------------
  # 2) Insert into cells table (NO cell_set column used)
  # -------------------------
  # minimal row: cell_id + dataset_id. (dataset_id can be set_name for now.)
  new_cells_df <- data.frame(
    cell_id    = cell_ids,
    dataset_id = set_name,
    stringsAsFactors = FALSE
  )

  # -------------------------
  # 3) Add membership rows and metadata atomically
  # -------------------------
  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  ins <- data.frame(
    cell_set    = cell_set,
    cell_id     = cell_ids,
    source      = source,
    created_at  = created_at,
    created_by  = created_by %||% NA_character_,
    description = paste0("ingested cells for ", cell_set),
    stringsAsFactors = FALSE
  )
  metadata_report <- NULL
  .wb_metadata_with_transaction(con, {
    DBI::dbWriteTable(con, "cells", new_cells_df, append = TRUE)
    DBI::dbWriteTable(con, "cell_set_membership", ins, append = TRUE)
    if (!is.null(metadata)) {
      metadata_report <- .wb_write_cell_metadata(
        con, metadata, target_cell_ids = cell_ids, source = source, created_by = created_by
      )
    }
  })

  # -------------------------
  # 5) Spaces (optional)
  # -------------------------
  if (length(spaces)) {
    for (space_id in names(spaces)) {
      coords <- spaces[[space_id]]
      .wb_ingest_space_coords(
        bundle     = bundle,
        space_id   = space_id,
        coords     = coords,
        cell_ids   = cell_ids,
        source     = source
      )
    }
  }

  # -------------------------
  # 6) Matrices (optional) — canonical path: attach fragments to THESE new cells
  # -------------------------
  if (length(matrices)) {
    wb_attach_to_cells(
      bundle   = bundle,
      matrices = matrices,
      cell_ids = cell_ids,     # restrict to these new cells
      source   = source,
      created_by = created_by
    )
  }

  invisible(list(
    set_name     = set_name,
    cell_set     = cell_set,
    n_ingested   = length(cell_ids),
    n_spaces     = length(spaces),
    n_matrices   = length(matrices),
    metadata_fields = metadata_report$fields %||% data.frame()
  ))
}


# -------------------------
# Metadata ingestion (first column == cell_id if no explicit column)
# -------------------------
.wb_ingest_cell_metadata <- function(con, cell_ids, metadata) {
  .wb_write_cell_metadata(con, metadata, target_cell_ids = cell_ids, source = "ingest")
}


# -------------------------
# Space ingestion normalizes supported tabular shapes into the one canonical
# file-backed dense-space writer. First column is always treated as cell_id.
# -------------------------
.wb_ingest_space_coords <- function(bundle, space_id, coords, cell_ids, source = "ingest") {
  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id), "space_id invalid")
  if (is.data.frame(coords)) {
    df <- as.data.frame(coords, stringsAsFactors = FALSE, check.names = FALSE)
    .wb_assert(ncol(df) >= 3L, "coords data.frame must contain cell_id and coordinate columns")
    ids <- as.character(df[[1L]])
    df <- df[ids %in% cell_ids, , drop = FALSE]
    ids <- ids[ids %in% cell_ids]
    if (!nrow(df)) return(invisible(TRUE))
    looks_long <- ncol(df) == 3L &&
      all(suppressWarnings(!is.na(as.integer(df[[2L]])))) &&
      !anyDuplicated(paste(ids, as.integer(df[[2L]]), sep = "\r")) &&
      anyDuplicated(ids)
    if (looks_long) {
      dim_index <- as.integer(df[[2L]])
      n_dims <- max(dim_index)
      ordered_cells <- unique(ids)
      mat <- matrix(NA_real_, nrow = length(ordered_cells), ncol = n_dims,
                    dimnames = list(ordered_cells, paste0("dim", seq_len(n_dims))))
      mat[cbind(match(ids, ordered_cells), dim_index)] <- as.numeric(df[[3L]])
      .wb_assert(!anyNA(mat), "Long dense-space input is incomplete.")
    } else {
      mat <- as.matrix(df[, -1L, drop = FALSE])
      rownames(mat) <- ids
    }
  } else {
    mat <- as.matrix(coords)
    .wb_assert(!is.null(rownames(mat)), "High-D coordinates require rownames=cell_id.")
    mat <- mat[rownames(mat) %in% cell_ids, , drop = FALSE]
  }
  if (!nrow(mat)) return(invisible(TRUE))
  wb_add_space(bundle, space_id, mat, source = source, description = space_id)
}


# Register space in `spaces` if missing
.wb_ensure_space_registered <- function(con, space_id, dims, storage, source, description) {
  exists <- DBI::dbGetQuery(con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (!nrow(exists)) {
    DBI::dbWriteTable(con, "spaces", data.frame(
      space_id = space_id,
      source = source,
      dims = as.integer(dims),
      storage = storage,
      description = description,
      stringsAsFactors = FALSE
    ), append = TRUE)
  } else {
    # keep existing, but ensure dims/storage are not empty
    DBI::dbExecute(con, "
      UPDATE spaces
      SET dims = COALESCE(dims, ?),
          storage = COALESCE(storage, ?),
          source = COALESCE(source, ?),
          description = COALESCE(description, ?)
      WHERE space_id = ?;",
                   params = list(as.integer(dims), storage, source, description, space_id)
    )
  }
  invisible(TRUE)
}
