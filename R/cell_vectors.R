wb_attach_cell_vector <- function(bundle, vector_id, values, overwrite = TRUE) {
  con <- bundle$con
  wb_ensure_cell_vectors_tables(con)

  # normalize
  if (is.data.frame(values)) {
    stopifnot(all(c("cell_id","value") %in% colnames(values)))
    cell_id <- as.character(values$cell_id)
    v <- values$value
    names(v) <- cell_id
  } else {
    stopifnot(is.atomic(values))
    stopifnot(!is.null(names(values)))
    v <- values
    cell_id <- names(v)
  }

  # filter to cells that exist
  cl <- .wb_sql_in_json(unique(cell_id))
  have <- DBI::dbGetQuery(con, paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"), params = cl$params)$cell_id
  v <- v[have]
  if (!length(v)) stop("No provided cell_ids exist in bundle.", call. = FALSE)

  # optionally clear existing
  if (isTRUE(overwrite)) {
    cl2 <- .wb_sql_in_json(names(v))
    DBI::dbExecute(con, paste0(
      "DELETE FROM cell_vector_values WHERE vector_id = ? AND cell_id IN ", cl2$sql, ";"
    ), params = c(list(vector_id), cl2$params))
  }

  # write (numeric for now; extend later for value_type)
  df <- data.frame(
    vector_id = vector_id,
    cell_id   = names(v),
    value_num = as.numeric(v),
    value_txt = NA_character_,
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, "cell_vector_values", df, append = TRUE)

  invisible(list(vector_id = vector_id, n = nrow(df)))
}

wb_read_cell_vector <- function(bundle, vector_id, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")
  con <- bundle$con
  .wb_ensure_cell_vectors_tables(con)

  cell_ids <- as.character(cell_ids)
  out <- rep(NA_real_, length(cell_ids))
  names(out) <- cell_ids

  cl <- .wb_sql_in_json(cell_ids)  # you already have this helper
  df <- DBI::dbGetQuery(con, paste0(
    "SELECT cell_id, value FROM cell_vector_values
     WHERE vector_id = ? AND cell_id IN ", cl$sql, ";"
  ), params = c(list(vector_id), cl$params))

  if (nrow(df) == 0) return(out)
  out[df$cell_id] <- as.numeric(df$value)
  out
}



wb_list_cell_vectors <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_ensure_cell_vectors_tables(con)

  DBI::dbGetQuery(con, "
    SELECT vector_id, name, description, value_type, source, created_at, created_by
    FROM cell_vectors
    ORDER BY created_at DESC;
  ")
}


wb_register_cell_vector <- function(
    bundle,
    vector_id,
    name = vector_id,
    description = NULL,
    value_type = "numeric",
    source = NULL,
    created_by = NULL,
    provenance = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con

  .wb_ensure_cell_vectors_tables(con)

  # coerce optionals to scalar strings (NO NULLs!)
  description <- if (is.null(description)) NA_character_ else as.character(description)
  source      <- if (is.null(source))      NA_character_ else as.character(source)
  created_by  <- if (is.null(created_by))  NA_character_ else as.character(created_by)

  prov_json <- if (is.null(provenance)) {
    NA_character_
  } else {
    as.character(jsonlite::toJSON(provenance, auto_unbox = TRUE))
  }

  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  # upsert-ish: delete then insert (simple + safe for v1)
  DBI::dbExecute(con, "DELETE FROM cell_vectors WHERE vector_id = ?;", params = list(vector_id))

  DBI::dbWriteTable(
    con,
    "cell_vectors",
    data.frame(
      vector_id = as.character(vector_id),
      name = as.character(name),
      description = description,
      value_type = as.character(value_type),
      source = source,
      created_at = as.character(created_at),
      created_by = created_by,
      provenance_json = prov_json,
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )

  invisible(vector_id)
}

wb_write_cell_vector <- function(
    bundle,
    vector_id,
    values,
    subset_cell_ids = NULL,
    overwrite = TRUE
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")
  con <- bundle$con
  .wb_ensure_cell_vectors_tables(con)

  # normalize -> df(cell_id,value)
  df <- NULL
  if (is.data.frame(values)) {
    .wb_assert(all(c("cell_id","value") %in% colnames(values)), "values df must have cell_id,value")
    df <- values[, c("cell_id","value")]
  } else {
    .wb_assert(is.atomic(values), "values must be atomic or data.frame")
    .wb_assert(!is.null(names(values)) && all(nzchar(names(values))), "named vector required (names=cell_id)")
    df <- data.frame(cell_id = names(values), value = as.numeric(values), stringsAsFactors = FALSE)
  }

  df$cell_id <- as.character(df$cell_id)
  df$value <- as.numeric(df$value)

  if (!is.null(subset_cell_ids)) {
    subset_cell_ids <- as.character(subset_cell_ids)
    df <- df[df$cell_id %in% subset_cell_ids, , drop = FALSE]
  }

  # drop NA values => sparse storage
  df <- df[!is.na(df$value) & nzchar(df$cell_id), , drop = FALSE]
  if (nrow(df) == 0) return(invisible(0L))

  # optional: validate cells exist
  have <- DBI::dbGetQuery(
    con,
    "SELECT cell_id FROM cells WHERE cell_id IN (SELECT value FROM json_each(?));",
    params = list(jsonlite::toJSON(as.list(unique(df$cell_id)), auto_unbox = TRUE))
  )$cell_id
  df <- df[df$cell_id %in% have, , drop = FALSE]
  if (nrow(df) == 0) return(invisible(0L))

  if (isTRUE(overwrite)) {
    DBI::dbExecute(con, "DELETE FROM cell_vector_values WHERE vector_id = ?;", params = list(vector_id))
  } else {
    # keep existing; we'll insert/replace per key
    DBI::dbExecute(con, "DELETE FROM cell_vector_values WHERE vector_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
                   params = list(vector_id, jsonlite::toJSON(as.list(unique(df$cell_id)), auto_unbox = TRUE))
    )
  }

  df$vector_id <- vector_id
  df <- df[, c("vector_id","cell_id","value")]
  DBI::dbWriteTable(con, "cell_vector_values", df, append = TRUE)

  invisible(nrow(df))
}

wb_vector_choices <- function(bundle) {
  df <- wb_list_cell_vectors(bundle)
  if (!nrow(df)) return(character(0))
  paste0("vec:", df$vector_id)
}


