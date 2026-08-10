.wb_scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  if (length(x) != 1) stop("Expected scalar (length 1), got length ", length(x), call. = FALSE)
  as.character(x)
}
# internal: force a scalar string (or NA)
.wb_scalar_chr <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_character_)
  as.character(x[[1]])
}

# internal: force a scalar int (or NA)
.wb_scalar_int <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_integer_)
  as.integer(x[[1]])
}

# internal: force a scalar dbl (or NA)
.wb_scalar_dbl <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  as.numeric(x[[1]])
}


# internal: build a safe SQL IN (...) clause with DBI params
.wb_sql_in_clause <- function(x) {
  if (is.null(x) || length(x) == 0) {
    stop("IN clause cannot be built for empty vector.", call. = FALSE)
  }

  x <- as.list(x)  # DBI wants params as list
  n <- length(x)

  sql <- paste0("IN (", paste(rep("?", n), collapse = ", "), ")")

  list(
    sql = sql,
    params = x
  )
}
# Robust for large vectors
.wb_sql_in_json <- function(x) {
  .wb_assert(!is.null(x) && length(x) > 0, "Vector must be non-empty.")
  list(
    sql = "(SELECT value FROM json_each(?))",
    params = list(jsonlite::toJSON(as.character(x), auto_unbox = TRUE))
  )
}



.wb_db_get_in_chunks <- function(con, sql_prefix, ids, chunk = 1000, params_prefix = list()) {
  out <- list()
  ids <- as.character(ids)
  for (i in seq(1, length(ids), by = chunk)) {
    sub <- ids[i:min(i + chunk - 1, length(ids))]
    cl <- .wb_sql_in_clause(sub)
    q <- paste0(sql_prefix, " ", cl$sql)
    out[[length(out) + 1]] <- DBI::dbGetQuery(con, q, params = c(params_prefix, cl$params))
  }
  do.call(rbind, out)
}


.wb_ensure_space_models_table <- function(con) {
  if (.wb_schema_component_is_current(
    con, "space_models", list(space_models = "provenance_json")
  )) return(invisible(TRUE))
  # 1) Create the legacy/current table if it doesn't exist (keeps your schema)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_models (
      space_id        TEXT PRIMARY KEY,
      model_type      TEXT NOT NULL,      -- 'uwot_umap'
      source_space_id TEXT NOT NULL,      -- e.g. 'lsi' or 'peakvi_latent'
      dims_json       TEXT,               -- JSON array, e.g. [2,3,...,30]
      cell_set        TEXT NOT NULL,      -- 'core' or 'all' or 'set:...'
      uwot_args_json  TEXT NOT NULL,      -- JSON list of uwot args
      seed            INTEGER,
      model_path      TEXT NOT NULL,      -- relative path inside bundle
      created_at      TEXT NOT NULL
    );
  ")

  # 2) Contract addition: provenance_json
  # This lets us satisfy the "stable contract" without breaking anything.
  if (!.wb_db_has_column(con, "space_models", "provenance_json")) {
    DBI::dbExecute(con, "ALTER TABLE space_models ADD COLUMN provenance_json TEXT;")
  }

  # 3) Indexes (idempotent)
  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_space_models_source_space
    ON space_models(source_space_id);
  ")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_space_models_space_id
    ON space_models(space_id);
  ")

  invisible(TRUE)
}
