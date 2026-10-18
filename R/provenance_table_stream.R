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
    # Compute only independent row digests in one bounded call. The predicate
    # rejects deferred/unsupported carriers BEFORE any element preflight, so an
    # ineligible input still reaches the untouched ordered loop/error boundary.
    hashes <- tryCatch({
      if (!isTRUE(.Call("scwb_table_row_hash_eligible", row_json,
          PACKAGE = "scworkbench"))) NULL else {
        limit <- getOption("scworkbench.max_dense_materialize_mb", 256)
        if (!is.numeric(limit) || is.object(limit) || !is.null(attributes(limit)) ||
            length(limit) != 1L || !is.finite(limit) || limit <= 0) NULL else {
          bytes <- nchar(row_json, type = "bytes")
          reservation <- sum(bytes) + 256 * length(bytes) + 4096
          if (anyNA(bytes) || !is.finite(reservation) ||
              reservation > min(32 * 1024^2, limit * 1024^2 / 4)) NULL else {
            value <- unclass(as.character(openssl::sha256(row_json)))
            if (!is.character(value) || length(value) != length(row_json) ||
                anyNA(value) || !all(grepl("^[0-9a-f]{64}$", value))) NULL else value
          }
        }
      }
    }, error = function(e) NULL)
    if (is.null(hashes)) {
      for (text in row_json) {
        sha <- digest::digest(text, algo = "sha256", serialize = FALSE)
        state <<- digest::digest(paste0(first[[1L]], state, rest[[1L]],
          sha, rest[[2L]]), algo = "sha256", serialize = FALSE)
      }
    } else for (sha in hashes) {
      state <<- digest::digest(paste0(first[[1L]], state, rest[[1L]],
        sha, rest[[2L]]), algo = "sha256", serialize = FALSE)
    }
    state
  }
}
