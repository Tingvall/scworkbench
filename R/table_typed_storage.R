# Additive table storage version. Absence of the primitive field means the
# historical row-json contract, including its frozen identity preimage.
.wb_table_storage_declaration <- function(table) {
  list(format = "scworkbench.table.typed-json.v1", columns = list(
    names = names(table), types = unname(vapply(table, function(x) {
      if (is.null(attributes(x)) && typeof(x) %in%
          c("integer", "double", "logical", "character")) typeof(x) else "legacy"
    }, character(1)))))
}

.wb_table_storage <- function(prim) {
  storage <- prim$table_storage
  if (is.null(storage)) return(NULL)
  .wb_assert(is.list(storage) && identical(storage$format,
    "scworkbench.table.typed-json.v1"), "Unsupported table storage version")
  .wb_assert(!anyDuplicated(names(prim$table)) && !anyNA(names(prim$table)) &&
    all(nzchar(names(prim$table))), "Typed tables require unique non-empty column names")
  .wb_assert(!any(vapply(prim$table, function(x) is.list(x) || !is.null(dim(x)), logical(1))),
    "List/matrix table columns have no supported scalar round-trip contract")
  current <- .wb_table_storage_declaration(prim$table)$columns
  declared <- storage$columns
  .wb_assert(nrow(prim$table) > 0L || !any(declared$types == "legacy"),
    "Empty attributed table columns have no supported scalar round-trip contract")
  .wb_assert(identical(current$names, declared$names) &&
    length(current$types) == length(declared$types) &&
    all(declared$types == "legacy" | declared$types == current$types),
    "Table columns no longer match their declared types; construct a new table primitive")
  declared
}

.wb_table_decode_meta <- function(meta, typed = FALSE) {
  if (!isTRUE(typed)) return(list(meta = meta, storage = NULL))
  .wb_assert(is.list(meta) && identical(meta$storage_format,
      "scworkbench.table.typed-json.v1") &&
      identical(names(meta), c("storage_format", "columns", "meta")),
    "Missing or invalid typed table metadata envelope")
  storage <- meta$columns
  storage$names <- as.character(storage$names)
  storage$types <- as.character(storage$types)
  .wb_assert(length(storage$names) == length(storage$types) &&
    !anyDuplicated(storage$names) && !anyNA(storage$names) &&
    all(nzchar(storage$names)) &&
    all(storage$types %in% c("integer", "double", "logical", "character", "legacy")),
    "Invalid typed table column metadata")
  list(meta = meta$meta, storage = storage)
}

.wb_table_artifact_is_typed <- function(con, artifact_id) {
  row <- DBI::dbGetQuery(con,
    "SELECT provenance_json FROM artifacts WHERE artifact_id=?;", params = list(artifact_id))
  .wb_assert(nrow(row) == 1L, "Missing table artifact provenance")
  text <- row$provenance_json[[1L]]
  if (is.na(text) || !nzchar(text)) return(FALSE)
  provenance <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  format <- provenance$table_storage
  if (is.null(format)) return(FALSE)
  .wb_assert(identical(format, "scworkbench.table.typed-json.v1"),
    "Unsupported stored table storage version")
  TRUE
}

.wb_table_identity_scheme <- function(storage) {
  unname(.wb_content_identity_schemes()[[if (is.null(storage)) "table" else "table_typed"]])
}

.wb_table_stored_identity_scheme <- function(con, artifact_id) {
  row <- DBI::dbGetQuery(con,
    "SELECT meta_json FROM artifact_tables WHERE artifact_id=?;", params = list(artifact_id))
  .wb_assert(nrow(row) == 1L, "Missing table storage metadata")
  text <- row$meta_json[[1L]]
  meta <- if (is.na(text) || !nzchar(text)) list() else
    jsonlite::fromJSON(text, simplifyVector = TRUE)
  .wb_table_identity_scheme(.wb_table_decode_meta(meta, .wb_table_artifact_is_typed(con, artifact_id))$storage)
}

.wb_table_typed_row_json <- function(table, rows, storage) {
  block <- table[rows, , drop = FALSE]
  ordinary <- ncol(block) > 0L && !any(storage$types == "legacy") &&
    all(vapply(block, function(x) is.null(attributes(x)) &&
      typeof(x) %in% c("integer", "double", "logical", "character"), logical(1)))
  if (ordinary) {
    for (j in seq_along(block)) {
      column <- block[[j]]
      if (is.double(column) && any(is.nan(column) | is.infinite(column))) {
        # List scalars let JSON retain finite numbers/null NA while encoding
        # only NaN/Inf as the typed format's existing string sentinels.
        values <- as.list(column)
        nan <- which(is.nan(column)); infinite <- which(is.infinite(column))
        if (length(nan)) values[nan] <- rep(list("NaN"), length(nan))
        if (length(infinite)) values[infinite] <- as.list(as.character(column[infinite]))
        block[[j]] <- values
      }
    }
    # Scalar-list row JSON excludes dataframe row names. Preserve its bytes,
    # including 17-digit doubles, signed zero, column order and null spelling.
    rownames(block) <- NULL
    lines <- character()
    con <- textConnection("lines", "w", local = TRUE)
    on.exit(close(con), add = TRUE)
    jsonlite::stream_out(block, con, verbose = FALSE, pagesize = 1000L,
      auto_unbox = TRUE, null = "null", na = "null", digits = 17)
    return(lines)
  }
  # Ordinary columns bypass the historical sanitizer, which turns numeric NA
  # into strings. Non-finite doubles retain the already supported value domain;
  # the declared double type makes their string encodings unambiguous.
  vapply(seq_len(nrow(block)), function(i) {
    row <- as.list(block[i, , drop = FALSE])
    if (!length(row)) return("{}")
    for (j in seq_along(row)) {
      value <- row[[j]]
      if (storage$types[[j]] == "legacy") {
        row[j] <- list(.wb_json_sanitize(value))
      } else if (is.double(value) && !is.na(value) && !is.finite(value)) {
        row[[j]] <- as.character(value)
      } else if (is.double(value) && is.nan(value)) row[[j]] <- "NaN"
    }
    as.character(jsonlite::toJSON(row, auto_unbox = TRUE,
      null = "null", na = "null", digits = 17))
  }, character(1))
}

.wb_table_typed_rows_to_df <- function(rows, storage) {
  rr <- lapply(rows$row_json, jsonlite::fromJSON, simplifyVector = FALSE)
  n <- length(rr)
  keys <- as.character(storage$names); types <- as.character(storage$types)
  .wb_assert(all(vapply(rr, function(row) identical(as.character(names(row)), keys), logical(1))),
    "Typed table rows do not match declared columns")
  out <- vector("list", length(keys)); names(out) <- keys
  for (j in seq_along(keys)) {
    type <- types[[j]]
    if (type == "legacy") {
      # Keep attributed/list fallback semantics. These were never class-preserving.
      # Reject fallback shapes that expand rows/columns rather than silently flattening.
      if (!n) stop("Empty attributed/list table columns remain unsupported", call. = FALSE)
      legacy_rows <- vapply(rr, function(row) as.character(jsonlite::toJSON(
        setNames(list(row[[j]]), keys[j]), auto_unbox = TRUE, null = "null",
        na = "null", digits = 17)), character(1))
      legacy <- .wb_art_table_rows_to_df(data.frame(row_json = legacy_rows))
      .wb_assert(nrow(legacy) == n && ncol(legacy) == 1L,
        "Attributed/list table column expands the historical fallback shape")
      out[[j]] <- legacy[[1L]]
      next
    }
    column <- switch(type, integer = rep.int(NA_integer_, n),
      double = rep.int(NA_real_, n), logical = rep.int(NA, n),
      character = rep.int(NA_character_, n))
    for (i in seq_len(n)) {
      value <- rr[[i]][[j]]
      if (is.null(value)) next
      .wb_assert(length(value) == 1L && !is.list(value),
        "Non-scalar value in typed table column")
      if (type == "double" && is.character(value)) {
        .wb_assert(value %in% c("NaN", "Inf", "-Inf"),
          "Invalid non-finite double encoding")
        value <- switch(value, `NaN` = NaN, `Inf` = Inf, `-Inf` = -Inf)
      }
      .wb_assert(switch(type, integer = is.integer(value),
        double = is.numeric(value), logical = is.logical(value),
        character = is.character(value)), "Value does not match declared table type")
      column[i] <- value
    }
    out[[j]] <- column
  }
  structure(out, names = keys, row.names = if (n) c(NA_integer_, -as.integer(n)) else integer(),
    class = "data.frame")
}
