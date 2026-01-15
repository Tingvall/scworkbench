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
