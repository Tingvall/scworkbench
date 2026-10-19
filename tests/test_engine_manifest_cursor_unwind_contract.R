# Independent frozen registry-table.v1 preimage; no optimized helper reuse.
.engine_owned_cursor_oracle <- function(con, table) {
  hash <- function(x) digest::digest(jsonlite::serializeJSON(x, digits = NA),
    algo = "sha256", serialize = FALSE)
  fields <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
  state <- hash(list(schema = "scworkbench.manifest.registry-table.v1", table = table,
    columns = fields[, intersect(c("name", "type", "notnull", "pk"), names(fields)), drop = FALSE]))
  query <- DBI::dbSendQuery(con, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), " ORDER BY rowid;"))
  on.exit(DBI::dbClearResult(query), add = TRUE)
  n <- 0L
  repeat {
    rows <- DBI::dbFetch(query, n = 5000L)
    if (!nrow(rows)) break
    n <- n + nrow(rows)
    json <- as.character(jsonlite::toJSON(rows, dataframe = "rows", auto_unbox = TRUE,
      null = "null", na = "null"))
    state <- hash(list(previous = state,
      rows_sha256 = digest::digest(json, algo = "sha256", serialize = FALSE)))
  }
  list(row_count = n, content_sha256 = state)
}

test_engine_manifest_owned_cursor_unwind_contract <- function() {
  root <- tempfile("manifest_owned_cursor_"); dir.create(root)
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "owned.sqlite"))
  old <- getOption("scworkbench.graph_storage_test_hook")
  on.exit({options(scworkbench.graph_storage_test_hook = old)
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
    unlink(root, recursive = TRUE)}, add = TRUE)
  DBI::dbExecute(con, "PRAGMA journal_mode=DELETE;")
  DBI::dbExecute(con, "PRAGMA cache_size=-321;")
  DBI::dbExecute(con, "PRAGMA temp_store=MEMORY;")
  DBI::dbWriteTable(con, "owned_rows", data.frame(id = seq_len(10020L),
    label = paste0("row_", seq_len(10020L)), value = seq_len(10020L) / 13))
  # Include ordinary nulls/control UTF-8 and deferred fields. The latter force
  # streaming fallback rather than assuming each logical 5000-row chunk fits.
  DBI::dbExecute(con, "UPDATE owned_rows SET label=? WHERE id=1;",
    params = list(paste0(strrep("é", 130L), "\n\r\t\"\\")))
  DBI::dbExecute(con, "UPDATE owned_rows SET value=NULL WHERE id=2;")
  inventory <- function() {
    paths <- sort(list.files(root, all.files = TRUE, no.. = TRUE, recursive = TRUE, full.names = TRUE))
    paths <- paths[!file.info(paths)$isdir]
    data.frame(path = substring(paths, nchar(root) + 2L), bytes = unname(file.info(paths)$size),
      sha256 = unname(vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), "")))
  }
  policy <- function() list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), graph = con@ref$wb_graph_policy,
    graph_cache = con@ref$wb_graph_cache_kib)
  warnings_seen <- character()
  checked <- function(code) withCallingHandlers(force(code), warning = function(w) {
    warnings_seen <<- c(warnings_seen, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  before <- inventory(); before_policy <- policy()
  expected <- checked(.engine_owned_cursor_oracle(con, "owned_rows"))
  normal <- checked(scworkbench:::.wb_manifest_table_identity(con, "owned_rows"))
  stopifnot(identical(expected, normal), identical(before, inventory()),
    identical(before_policy, policy()), length(warnings_seen) == 0L)
  for (target in c("manifest_small_chunk", "manifest_scalar_batch")) {
    hits <- 0L
    options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (identical(event, target)) {
        hits <<- hits + 1L
        stopifnot(identical(state$table, "owned_rows"), state$rows > 0L,
          state$rows <= 5000L)
        stop("OWNED_MANIFEST_CURSOR_ABORT")
      }
    })
    failure <- checked(tryCatch(scworkbench:::.wb_manifest_table_identity(con, "owned_rows"), error = identity))
    stopifnot(inherits(failure, "error"), identical(conditionMessage(failure), "OWNED_MANIFEST_CURSOR_ABORT"),
      hits == 1L, length(warnings_seen) == 0L,
      identical(before_policy, checked(policy())), identical(before, inventory()))
    # Immediate real helper retry, not a cached expectation or function copy.
    # Any remaining live result also causes the following query/read to warn.
    options(scworkbench.graph_storage_test_hook = old)
    stopifnot(identical(checked(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM owned_rows;"))$n[[1L]], 10020L),
      identical(expected, checked(scworkbench:::.wb_manifest_table_identity(con, "owned_rows"))),
      identical(expected, checked(.engine_owned_cursor_oracle(con, "owned_rows"))),
      identical(before_policy, checked(policy())), identical(before, inventory()),
      length(warnings_seen) == 0L)
  }
  TRUE
}
