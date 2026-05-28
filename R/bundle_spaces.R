# R/bundle_spaces.R

#' Add a space (embedding) to an existing bundle
#'
#' Writes the space into SQLite:
#' - spaces (registry)
#' - space_2d (fast path if 2D)
#' - space_coords (long format otherwise)
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
#' @param chunk Long-format write chunk size (only used for dims > 2)
# pybench-parity: yes
# pybench-counterpart: pybench.spaces_write.add_space / pybench.add_space
# contract-note: writes spaces + (space_2d|space_coords), validates cell IDs, and refreshes manifest spaces
#' @export
wb_add_space <- function(bundle,
                         space_id,
                         coords,
                         description = NULL,
                         source = NULL,
                         overwrite = FALSE,
                         chunk = 20000) {
  con <- bundle$con

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

  # ---- validate cell ids exist in bundle ----
  # Ensure all supplied cell_ids are present in bundle (order can be subset)
  # Use a cheap existence query in chunks
  chunk_ids <- function(x, n = 500) split(x, ceiling(seq_along(x) / n))
  present <- logical(length(cell_ids))
  names(present) <- cell_ids

  for (blk in chunk_ids(cell_ids, n = 500)) {
    q <- paste0("SELECT cell_id FROM cells WHERE cell_id IN (",
                paste(rep("?", length(blk)), collapse = ","),
                ");")
    got <- DBI::dbGetQuery(con, q, params = as.list(blk))$cell_id
    present[blk] <- blk %in% got
  }
  if (any(!present)) {
    miss <- names(present)[!present]
    stop("Some cell_ids in coords are not present in bundle. First few missing: ",
         paste(head(miss, 10), collapse = ", "),
         call. = FALSE)
  }

  # ---- handle overwrite / conflicts ----
  created_source <- if (is.null(source)) "ingest" else as.character(source)
  created_desc <- if (is.null(description)) space_id else as.character(description)

  DBI::dbWithTransaction(con, {
    exists_space <- DBI::dbGetQuery(con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
    if (nrow(exists_space) > 0) {
      if (!isTRUE(overwrite)) stop("space_id already exists: ", space_id, " (set overwrite=TRUE to replace)", call. = FALSE)

      DBI::dbExecute(con, "DELETE FROM space_2d WHERE space_id = ?;", params = list(space_id))
      DBI::dbExecute(con, "DELETE FROM space_coords WHERE space_id = ?;", params = list(space_id))
      DBI::dbExecute(con, "DELETE FROM spaces WHERE space_id = ?;", params = list(space_id))
    }

    if (dims == 2) {
      DBI::dbExecute(con, "
        INSERT INTO spaces(space_id, source, dims, storage, description)
        VALUES(?, ?, ?, ?, ?);
      ", params = list(
        .wb_scalar_chr(space_id),
        .wb_scalar_chr(created_source),
        .wb_scalar_int(dims),
        .wb_scalar_chr("wide:space_2d"),
        .wb_scalar_chr(created_desc)
      ))

      df2 <- data.frame(
        space_id = space_id,
        cell_id  = cell_ids,
        x        = as.numeric(mat[, 1]),
        y        = as.numeric(mat[, 2]),
        stringsAsFactors = FALSE
      )
      DBI::dbWriteTable(con, "space_2d", df2, append = TRUE)

    } else {
      DBI::dbExecute(con, "
        INSERT INTO spaces(space_id, source, dims, storage, description)
        VALUES(?, ?, ?, ?, ?);
      ", params = list(
        .wb_scalar_chr(space_id),
        .wb_scalar_chr(created_source),
        .wb_scalar_int(dims),
        .wb_scalar_chr("long:space_coords"),
        .wb_scalar_chr(created_desc)
      ))

      n <- nrow(mat)
      idx <- seq_len(n)

      for (s in seq(1, n, by = chunk)) {
        ii <- idx[s:min(s + chunk - 1, n)]
        sub <- mat[ii, , drop = FALSE]

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
    }
  })

  # ---- indexes ----
  # If these already exist, SQLite will error. So wrap in try.
  try(DBI::dbExecute(con, "CREATE INDEX idx_space_2d_space ON space_2d(space_id);"), silent = TRUE)
  try(DBI::dbExecute(con, "CREATE INDEX idx_space_2d_cell  ON space_2d(cell_id);"), silent = TRUE)
  try(DBI::dbExecute(con, "CREATE INDEX idx_space_coords_space ON space_coords(space_id);"), silent = TRUE)
  try(DBI::dbExecute(con, "CREATE INDEX idx_space_coords_cell ON space_coords(cell_id);"), silent = TRUE)

  # ---- update manifest.json from authoritative storage ----
  if (exists("wb_refresh_manifest", mode = "function")) {
    try(wb_refresh_manifest(bundle), silent = TRUE)
  }


  invisible(list(
    space_id = space_id,
    dims = dims,
    n_cells = length(cell_ids),
    storage = if (dims == 2) "wide:space_2d" else "long:space_coords"
  ))
}
