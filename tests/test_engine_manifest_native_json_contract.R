.engine_manifest_native_json <- function(rows, keys = NULL, bound = 1e8) {
  if (is.null(keys)) keys <- vapply(names(rows), function(name)
    as.character(jsonlite::toJSON(name, auto_unbox = TRUE)), character(1))
  .Call(get("C_scwb_manifest_scalar_json", asNamespace("scworkbench")), rows, keys, as.double(bound))
}
.engine_manifest_native_old_json <- function(rows) as.character(jsonlite::toJSON(rows,
  dataframe = "rows", auto_unbox = TRUE, null = "null", na = "null"))

test_engine_manifest_native_json_positive_compact_prefix_contract <- function() {
  rows <- data.frame(label = c("a", NA_character_, "NA"), id = c(1L, 2L, 3L),
    flag = c(TRUE, FALSE, NA))
  literal <- paste0('[{"label":"a","id":1,"flag":true},',
    '{"label":null,"id":2,"flag":false},{"label":"NA","id":3,"flag":null}]')
  for (sign in c(1L, -1L)) {
    actual_rows <- rows
    attr(actual_rows, "row.names") <- c(NA_integer_, sign * 3L)
    stopifnot(identical(.row_names_info(actual_rows, type = 0L), c(NA_integer_, sign * 3L)))
    expected <- .engine_manifest_native_old_json(actual_rows)
    actual <- .engine_manifest_native_json(actual_rows)
    stopifnot(!is.null(actual), identical(expected, literal), identical(actual, literal),
      identical(charToRaw(actual), charToRaw(expected)),
      identical(Encoding(actual), Encoding(expected)), identical(Encoding(actual), Encoding(literal)))
  }
  # Reproduce actual first-prefix subset metadata, not just manually set attrs.
  original <- data.frame(label = rep("a", 5000L), id = rep(1L, 5000L), flag = rep(TRUE, 5000L))
  prefix <- original[seq_len(3675L), , drop = FALSE]
  stopifnot(identical(.row_names_info(prefix, type = 0L), c(NA_integer_, 3675L)))
  expected <- paste0("[", paste(rep('{"label":"a","id":1,"flag":true}', 3675L), collapse = ","), "]")
  actual <- .engine_manifest_native_json(prefix)
  stopifnot(!is.null(actual), identical(actual, expected),
    identical(charToRaw(actual), charToRaw(.engine_manifest_native_old_json(prefix))))
  for (raw_names in list(c(NA_integer_, 4L), c(NA_integer_, -4L),
      c(NA_integer_, NA_integer_))) {
    malformed <- rows; attr(malformed, "row.names") <- raw_names
    stopifnot(is.null(.engine_manifest_native_json(malformed)))
  }
  deferred <- rows; attr(deferred, "row.names") <- as.character(1:3)
  altrep <- rows; altrep$id <- 1:3
  stopifnot(is.null(.engine_manifest_native_json(deferred)), is.null(.engine_manifest_native_json(altrep)))
  TRUE
}

test_engine_manifest_native_json_literal_oracle_contract <- function() {
  for (n in c(1L, 2L, 512L, 1000L, 5000L)) {
    rows <- data.frame(label = rep(c("", "NA", NA_character_, "space /under_score:dot.-"), length.out = n),
      ordinal = rep(c(-2147483647L, 2147483647L, NA_integer_, 0L), length.out = n),
      flag = rep(c(TRUE, FALSE, NA), length.out = n))
    # Default compact rownames are passed directly, not expanded by the helper.
    actual <- .engine_manifest_native_json(rows)
    expected <- .engine_manifest_native_old_json(rows)
    stopifnot(!is.null(actual), identical(actual, expected), identical(Encoding(actual), Encoding(expected)),
      identical(charToRaw(actual), charToRaw(expected)))
    rownames(rows) <- sprintf("%d", rev(seq_len(n)))
    stopifnot(identical(.engine_manifest_native_json(rows), .engine_manifest_native_old_json(rows)))
  }
  rows <- data.frame(a = c("x", "y", "z"), b = c(1L, NA_integer_, 3L))
  rownames(rows) <- c("03", "1", "2")
  stopifnot(identical(.engine_manifest_native_json(rows), .engine_manifest_native_old_json(rows)))
  rows <- data.frame(label = strrep("x", 256L))
  stopifnot(identical(.engine_manifest_native_json(rows), .engine_manifest_native_old_json(rows)))
  wide <- as.data.frame(setNames(rep(list(c("a", NA_character_)), 8L), paste0("field", 1:8)))
  stopifnot(identical(.engine_manifest_native_json(wide), .engine_manifest_native_old_json(wide)))
  TRUE
}

test_engine_manifest_native_json_fallback_before_allocation_contract <- function() {
  base <- data.frame(label = rep("ordinary", 2L), ordinal = rep(1L, 2L))
  variants <- lapply(c("late\n", "late\r\n", "quote\"", "slash\\", "</", "é",
    strrep("a", 257L), paste0("DEL", intToUtf8(127L))), function(value) {
      x <- base; x$label[[2L]] <- value; x
    })
  x <- base; names(x)[[1L]] <- "東京"; variants[[length(variants) + 1L]] <- x
  x <- base; names(x)[[1L]] <- "quoted\"name"; variants[[length(variants) + 1L]] <- x
  x <- base; names(x) <- c("label", "label"); variants[[length(variants) + 1L]] <- x
  x <- base; rownames(x) <- c("real", "names"); variants[[length(variants) + 1L]] <- x
  x <- base; x$ordinal <- as.numeric(x$ordinal); variants[[length(variants) + 1L]] <- x
  x <- base; x$ordinal <- bit64::as.integer64(x$ordinal); variants[[length(variants) + 1L]] <- x
  x <- base; x$ordinal <- factor(x$ordinal); variants[[length(variants) + 1L]] <- x
  x <- base; x$ordinal <- as.Date(c("2020-01-01", "2020-01-02")); variants[[length(variants) + 1L]] <- x
  x <- base; attr(x$label, "custom") <- TRUE; variants[[length(variants) + 1L]] <- x
  x <- base; attr(x, "custom") <- TRUE; variants[[length(variants) + 1L]] <- x
  x <- structure(list(label = rep("ordinary", 2L), ordinal = 1:2),
    class = "data.frame", row.names = c(NA_integer_, -2L))
  variants[[length(variants) + 1L]] <- x # compact ALTREP integer column
  x <- base; attr(x, "row.names") <- as.character(1:2)
  variants[[length(variants) + 1L]] <- x # deferred string rownames, no DF setter
  variants[[length(variants) + 1L]] <- base[FALSE, , drop = FALSE]
  variants[[length(variants) + 1L]] <- as.data.frame(setNames(rep(list(base$label), 9L), paste0("f", 1:9)))
  for (rows in variants) stopifnot(is.null(.engine_manifest_native_json(rows)))
  # Independent name/token association, exact old bound and shape checks.
  stopifnot(is.null(.engine_manifest_native_json(base, c('"wrong"', '"ordinal"'))),
    is.null(.engine_manifest_native_json(base, bound = 1)),
    is.null(.engine_manifest_native_json(base[rep(1L, 5001L), , drop = FALSE])))
  # Classed rownames cannot dispatch a length method in C eligibility.
  x <- base; attr(x, "row.names") <- structure(c("1", "2"), class = "opaque")
  stopifnot(identical(class(attr(x, "row.names")), "opaque"), is.null(.engine_manifest_native_json(x)))
  TRUE
}

test_engine_manifest_native_json_actual_identity_fault_retry_contract <- function() {
  path <- tempfile("manifest_native_json_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  DBI::dbAppendTable(con, "entries", data.frame(id = rep(1:5, length.out = 5001L),
    label = rep(c(strrep("a", 64L), NA_character_, "NA"), length.out = 5001L)))
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
    reservation = con@ref$wb_graph_cache_kib)
  hits <- 0L; misses <- 0L
  known_pair <- identical(as.character(getRversion()), "4.4.1") &&
    identical(as.character(getNamespaceVersion("jsonlite")), "1.8.8")
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_json") {
      if (state$mode == "native") {
        hits <<- hits + 1L
        stopifnot(state$actual_bytes <= state$encoded_bytes,
          state$buffer_ledger_bytes == 6 * (state$actual_bytes + 1) + 256,
          state$buffer_ledger_bytes <= 8 * state$encoded_bytes)
      } else misses <<- misses + 1L
    }
  })
  on.exit(options(old), add = TRUE)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")),
    if (known_pair) hits > 0L else hits == 0L && misses > 0L)
  DBI::dbExecute(con, "UPDATE entries SET label=? WHERE rowid=5000;", params = list("late\n"))
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")), misses > 0L)
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_json") stop("NATIVE_MANIFEST_JSON_FAULT")
  })
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries"), error = identity)
  options(old)
  stopifnot(inherits(failure, "error"), grepl("NATIVE_MANIFEST_JSON_FAULT", conditionMessage(failure), fixed = TRUE),
    identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")),
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
      reservation = con@ref$wb_graph_cache_kib)))
  TRUE
}
