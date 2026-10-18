# Bounded emission of the existing artifact row JSON. Keep the legacy fallback
# for attributed/list columns: dataframe JSON and scalar-list JSON do not share
# all class/missing-value rules. This changes no durable representation.
.wb_prov_table_row_json <- function(table, rows) {
  block <- table[rows, , drop = FALSE]
  ordinary <- ncol(block) > 0L && !anyDuplicated(names(block)) &&
    all(nzchar(names(block))) && all(vapply(block, function(x)
      is.null(attributes(x)) && typeof(x) %in%
        c("integer", "double", "logical", "character"), logical(1)))
  if (!ordinary) return(vapply(seq_len(nrow(block)), function(i)
    as.character(jsonlite::toJSON(
      .wb_json_sanitize(as.list(block[i, , drop = FALSE])),
      auto_unbox = TRUE, null = "null")), character(1)))
  for (name in names(block)) {
    column <- block[[name]]
    if (is.numeric(column) && any(!is.finite(column)))
      block[[name]] <- lapply(column, function(value) {
        if (is.nan(value)) "NaN" else if (is.na(value)) "NA" else
          if (!is.finite(value)) as.character(value) else value
      })
  }
  # Row names are not part of scalar-list row JSON; stream_out otherwise emits
  # non-default row names as an additional `_row` field.
  rownames(block) <- NULL
  lines <- character()
  con <- textConnection("lines", "w", local = TRUE)
  on.exit(close(con), add = TRUE)
  # Scalar-list toJSON uses digits=4 and numeric NA/NaN/Inf strings, but
  # character/logical missing values are null. Do not inherit stream defaults.
  jsonlite::stream_out(block, con, verbose = FALSE, pagesize = 1000L,
    auto_unbox = TRUE, null = "null", na = "null", digits = 4)
  lines
}

# Serialize the constant two-digest R object shape once, then substitute only
# fixed-width hexadecimal values. The preimage is still serializeJSON(...,
# digits=NA), not a new fold/identity scheme or an R-serialization digest.
.wb_prov_table_fold <- function(state) {
  force(state)
  previous <- paste(rep("a", 64L), collapse = "")
  row <- paste(rep("b", 64L), collapse = "")
  template <- jsonlite::serializeJSON(list(previous = previous,
    row_sha256 = row), digits = NA)
  first <- strsplit(template, previous, fixed = TRUE)[[1L]]
  rest <- strsplit(first[[2L]], row, fixed = TRUE)[[1L]]
  function(row_json) {
    for (text in row_json) {
      sha <- digest::digest(text, algo = "sha256", serialize = FALSE)
      state <<- digest::digest(paste0(first[[1L]], state, rest[[1L]],
        sha, rest[[2L]]), algo = "sha256", serialize = FALSE)
    }
    state
  }
}
