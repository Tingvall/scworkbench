.wb_as_coord_matrix <- function(space_obj) {
  if (is.data.frame(space_obj)) {
    .wb_assert(all(c("cell_id", "x", "y") %in% colnames(space_obj)),
               "2D space data.frame must have columns cell_id, x, y")
    X <- cbind(space_obj$x, space_obj$y)
    rownames(X) <- space_obj$cell_id
    colnames(X) <- c("dim1", "dim2")
    return(X)
  }
  if (is.matrix(space_obj)) {
    .wb_assert(!is.null(rownames(space_obj)), "Space matrix must have rownames = cell_id")
    return(space_obj)
  }
  stop("Unsupported space object type returned by wb_space().", call. = FALSE)
}

.wb_space_2d_safe <- function(bundle, space_id, cells = NULL) {
  con <- bundle$con

  # Pull all coords for this space (fast enough for 50k; and avoids IN(...) limits)
  df <- DBI::dbGetQuery(
    con,
    "SELECT cell_id, x, y FROM space_2d WHERE space_id = ?;",
    params = list(space_id)
  )

  if (!nrow(df)) {
    return(df)
  }

  df$cell_id <- as.character(df$cell_id)

  if (!is.null(cells)) {
    cells <- as.character(cells)
    ii <- match(cells, df$cell_id)
    keep <- !is.na(ii)
    df <- df[ii[keep], , drop = FALSE]   # preserves requested order
    # Note: missing cells are silently dropped (projection-friendly)
  }

  df
}

# Order cell_ids by bundle canonical order (cells.rowid)
# Internal helper used by selectors + wranglers.
.wb_order_like_bundle <- function(bundle, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_ids), "cell_ids must be character")

  cell_ids <- unique(as.character(cell_ids))
  if (!length(cell_ids)) return(character(0))

  con <- bundle$con

  # Use JSON IN because SQLite has param limits; you already use this pattern elsewhere.
  js <- jsonlite::toJSON(as.list(cell_ids), auto_unbox = TRUE)

  # Pull in canonical order. This also implicitly drops unknown ids (left join not needed).
  ord <- DBI::dbGetQuery(
    con,
    "
    SELECT c.cell_id
    FROM cells c
    WHERE c.cell_id IN (SELECT value FROM json_each(?))
    ORDER BY c.rowid;
    ",
    params = list(js)
  )$cell_id

  # Preserve any ids not in cells (shouldn't happen for normal use, but keep deterministic)
  # Append them in original input order at the end.
  missing <- setdiff(cell_ids, ord)
  if (length(missing)) ord <- c(ord, missing)

  ord
}

