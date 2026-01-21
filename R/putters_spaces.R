# R/putters_spaces.R

.wb_upsert_space_row <- function(con, space_id, source, dims, storage, description = NULL) {
  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id), "space_id must be a string")
  .wb_assert(is.character(source) && length(source) == 1 && nzchar(source), "source must be a string")
  .wb_assert(is.numeric(dims) && length(dims) == 1 && !is.na(dims) && dims >= 1, "dims must be a positive integer")
  .wb_assert(is.character(storage) && length(storage) == 1 && nzchar(storage), "storage must be a string")

  dims <- as.integer(dims)

  # SQLite upsert
  DBI::dbExecute(
    con,
    "
    INSERT INTO spaces(space_id, source, dims, storage, description)
    VALUES(?, ?, ?, ?, ?)
    ON CONFLICT(space_id) DO UPDATE SET
      source = excluded.source,
      dims = excluded.dims,
      storage = excluded.storage,
      description = excluded.description;
    ",
    params = list(space_id, source, dims, storage, description %||% space_id)
  )

  invisible(TRUE)
}
