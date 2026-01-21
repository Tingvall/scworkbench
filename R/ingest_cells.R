#' Ingest new cells into an existing bundle as a named cell set
#'
#' @param bundle scworkbench bundle handle (opened)
#' @param set_name Name of ingested set (stored as cell_set = "set:<name>")
#' @param cell_ids Character vector of new cell IDs
#' @param metadata Optional data.frame with rownames or a cell_id column
#' @param spaces Optional named list of spaces. Each entry can be:
#'   - data.frame(cell_id,x,y) for 2D, or
#'   - matrix/data.frame with rownames=cell_id and columns=dims for high-D
#' @param overwrite If TRUE, allows re-ingesting existing cell_ids (not recommended yet)
#' @export
wb_ingest_cells <- function(
    bundle,
    set_name,
    cell_ids,
    metadata = NULL,
    spaces = list(),
    matrices = list(),
    overwrite = FALSE
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  .wb_assert(is.character(set_name) && length(set_name) == 1 && nzchar(set_name), "set_name must be a non-empty string")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids must be a non-empty character vector")
  cell_ids <- unique(as.character(cell_ids))

  cell_set <- paste0("set:", set_name)
  con <- bundle$con

  cl <- .wb_sql_in_json(cell_ids)
  q <- paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";")
  existing <- DBI::dbGetQuery(con, q, params = cl$params)$cell_id


  if (length(existing) > 0) {
    if (!isTRUE(overwrite)) {
      stop(
        "Some cell_ids already exist in bundle (overwrite=FALSE). First few: ",
        paste(head(existing, 10), collapse = ", "),
        call. = FALSE
      )
    } else {
      stop("overwrite=TRUE not implemented yet for safety.", call. = FALSE)
    }
  }

  # --- 2) insert cells (dataset_id can be set_name for now) ---
  # You can refine dataset_id semantics later; this is pragmatic.
  new_cells_df <- data.frame(
    cell_id = cell_ids,
    dataset_id = set_name,
    cell_set = cell_set,
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, "cells", new_cells_df, append = TRUE)

  # --- 3) metadata (optional) ---
  if (!is.null(metadata)) {
    .wb_ingest_cell_metadata(con, cell_ids, metadata)
  }

  # --- 4) spaces (optional) ---
  if (length(spaces)) {
    for (space_id in names(spaces)) {
      coords <- spaces[[space_id]]
      .wb_ingest_space_coords(con, bundle_dir = bundle$dir, space_id = space_id, coords = coords, cell_ids = cell_ids)
    }
  }

  # --- 5) matrices (optional, not yet) ---
  if (length(matrices)) {
    stop("Matrix ingestion not implemented yet (matrices=...).", call. = FALSE)
  }

  invisible(list(
    set_name = set_name,
    cell_set = cell_set,
    n_ingested = length(cell_ids)
  ))
}


.wb_ingest_cell_metadata <- function(con, cell_ids, metadata) {
  .wb_assert(is.data.frame(metadata), "metadata must be a data.frame")

  # Normalize metadata row addressing
  if ("cell_id" %in% colnames(metadata)) {
    md <- metadata
  } else if (!is.null(rownames(metadata)) && all(nzchar(rownames(metadata)))) {
    md <- metadata
    md$cell_id <- rownames(md)
  } else {
    stop("metadata must have a cell_id column or rownames as cell_id", call. = FALSE)
  }

  md$cell_id <- as.character(md$cell_id)
  md <- md[md$cell_id %in% cell_ids, , drop = FALSE]

  # Convert factor/logical as in publish
  for (nm in setdiff(colnames(md), "cell_id")) {
    x <- md[[nm]]
    if (is.factor(x)) x <- as.character(x)
    if (is.logical(x)) x <- as.integer(x)
    md[[nm]] <- x
  }

  # Add missing columns
  existing_cols <- DBI::dbListFields(con, "cells")
  new_cols <- setdiff(colnames(md), existing_cols)
  for (nm in new_cols) {
    col_type <- if (is.numeric(md[[nm]])) "REAL" else "TEXT"
    if (is.integer(md[[nm]])) col_type <- "INTEGER"
    DBI::dbExecute(con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
  }

  # Update rows per column using parameterized UPDATE
  # (This is not the fastest, but fine for v1.)
  cols_to_write <- setdiff(colnames(md), "cell_id")
  for (nm in cols_to_write) {
    stmt <- sprintf('UPDATE cells SET "%s" = ? WHERE cell_id = ?;', nm)
    vals <- md[[nm]]
    for (i in seq_len(nrow(md))) {
      DBI::dbExecute(con, stmt, params = list(vals[i], md$cell_id[i]))
    }
  }

  invisible(TRUE)
}

.wb_ingest_space_coords <- function(con, bundle_dir, space_id, coords, cell_ids) {

  if (is.data.frame(coords) && all(c("cell_id","dim","value") %in% colnames(coords))) {
    coords <- .wb_coords_long_to_mat(coords)
  }

  .wb_assert(!is.null(rownames(coords)) && all(nzchar(rownames(coords))),
             "High-D space coords must have rownames = cell_id")

  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id), "space_id invalid")

  # Normalize coords to include only ingested cells
  if (is.data.frame(coords) && all(c("cell_id", "x", "y") %in% colnames(coords))) {
    df <- coords
    df$cell_id <- as.character(df$cell_id)
    df <- df[df$cell_id %in% cell_ids, , drop = FALSE]

    # Register space if missing
    .wb_ensure_space_registered(con, space_id, dims = 2, storage = "wide:space_2d",
                                source = "ingest", description = space_id)

    # Write
    out <- df[, c("cell_id","x","y")]
    out$space_id <- space_id
    out <- out[, c("space_id","cell_id","x","y")]
    DBI::dbWriteTable(con, "space_2d", out, append = TRUE)

    return(invisible(TRUE))
  }

  # High-D: accept matrix/data.frame with rownames=cell_id
  m <- coords
  if (is.data.frame(m)) m <- as.matrix(m)
  .wb_assert(is.matrix(m), "space coords must be either df(cell_id,x,y) or a matrix-like object")

  if (is.null(rownames(m))) stop("High-D space coords must have rownames = cell_id", call. = FALSE)
  m <- m[intersect(cell_ids, rownames(m)), , drop = FALSE]

  dims <- ncol(m)
  .wb_ensure_space_registered(con, space_id, dims = dims, storage = "long:space_coords",
                              source = "ingest", description = space_id)

  # Write long format in chunks
  chunk <- 20000
  idx <- seq_len(nrow(m))
  for (s in seq(1, length(idx), by = chunk)) {
    ii <- idx[s:min(s + chunk - 1, length(idx))]
    sub <- m[ii, , drop = FALSE]

    df_long <- do.call(rbind, lapply(seq_len(dims), function(d) {
      data.frame(
        space_id = space_id,
        cell_id  = rownames(sub),
        dim      = d,
        value    = as.numeric(sub[, d]),
        stringsAsFactors = FALSE
      )
    }))

    DBI::dbWriteTable(con, "space_coords", df_long, append = TRUE)
  }

  invisible(TRUE)
}

.wb_ensure_space_registered <- function(con, space_id, dims, storage, source, description) {
  exists <- DBI::dbGetQuery(con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (nrow(exists) == 0) {
    DBI::dbWriteTable(con, "spaces", data.frame(
      space_id = space_id,
      source = source,
      dims = as.integer(dims),
      storage = storage,
      description = description,
      stringsAsFactors = FALSE
    ), append = TRUE)
  }
  invisible(TRUE)
}

.wb_coords_long_to_mat <- function(df) {
  .wb_assert(is.data.frame(df), "coords long must be a data.frame")
  .wb_assert(all(c("cell_id","dim","value") %in% colnames(df)),
             "coords long must have columns: cell_id, dim, value")

  df$cell_id <- as.character(df$cell_id)
  df$dim <- as.integer(df$dim)

  cells <- unique(df$cell_id)
  dims  <- sort(unique(df$dim))

  mat <- matrix(NA_real_, nrow = length(cells), ncol = length(dims))
  rownames(mat) <- cells
  colnames(mat) <- paste0("dim", dims)

  i <- match(df$cell_id, cells)
  j <- match(df$dim, dims)
  mat[cbind(i, j)] <- as.numeric(df$value)

  mat
}


