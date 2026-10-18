# Explicit final component probe; the coordinating supervisor runs it in
# isolation, not alongside qualification/reviewer jobs. No scientific claim.
args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2L]]; stopifnot(!file.exists(root)); dir.create(root, recursive = TRUE)
old_source <- system2("git", c("show", "fff50517c9838481ff2a49bb1ebd8f5f20ead8dd:R/graph_storage.R"),
  stdout = TRUE)
stopifnot(is.null(attr(old_source, "status")))
old_env <- new.env(parent = asNamespace("scworkbench"))
for (expr in parse(text = old_source)) if (is.call(expr) &&
    identical(expr[[1L]], as.name("<-")) &&
    identical(expr[[2L]], as.name(".wb_graph_page"))) eval(expr, old_env)
stopifnot(is.function(old_env$.wb_graph_page))
new <- scworkbench:::.wb_graph_page; old <- old_env$.wb_graph_page
path <- file.path(root, "pages.sqlite")
con <- DBI::dbConnect(RSQLite::SQLite(), path, bigint = "integer64")
DBI::dbExecute(con, paste0("CREATE TABLE artifact_graph_rows(artifact_id TEXT,",
  "component TEXT,row_ordinal INTEGER,record_json TEXT,",
  "PRIMARY KEY(artifact_id,component,row_ordinal));"))
DBI::dbAppendTable(con, "artifact_graph_rows", data.frame(artifact_id = "fixture",
  component = "nodes", row_ordinal = seq_len(5120L) - 1L,
  record_json = sprintf('{"node_id":"node_%05d"}', seq_len(5120L))))
DBI::dbDisconnect(con)
con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO, bigint = "integer64")
before <- digest::digest(file = path, algo = "sha256")
starts <- as.character(seq.int(0L, 4608L, by = 512L))
for (start in starts) stopifnot(identical(
  old(con, "fixture", "nodes", start, 512L, 1048576L),
  new(con, "fixture", "nodes", start, 512L, 1048576L)))
measure <- function(fn, mode, replicate) {
  time <- proc.time(); count <- 0L
  for (i in seq_len(1000L)) count <- count + nrow(fn(con, "fixture", "nodes",
    starts[[(i - 1L) %% length(starts) + 1L]], 512L, 1048576L))
  time <- proc.time() - time; stopifnot(count == 512000L)
  data.frame(mode = mode, replicate = replicate, pages = 1000L, rows = count,
    elapsed = time[["elapsed"]], user = time[["user.self"]], system = time[["sys.self"]])
}
results <- list()
for (replicate in seq_len(3L)) {
  # Alternate direction to avoid assigning all warm-cache advantage to one side.
  modes <- if (replicate %% 2L) c("old", "new") else c("new", "old")
  for (mode in modes) results[[length(results) + 1L]] <-
    measure(if (mode == "old") old else new, mode, replicate)
}
DBI::dbDisconnect(con)
stopifnot(identical(before, digest::digest(file = path, algo = "sha256")))
result <- do.call(rbind, results); print(result, row.names = FALSE)
write.csv(result, file.path(root, "timings.csv"), row.names = FALSE)
comparison <- merge(result[result$mode == "old", ], result[result$mode == "new", ],
  by = "replicate", suffixes = c("_old", "_new"))
comparison$budget <- 1.2 * comparison$elapsed_old + .1
comparison$budget_pass <- comparison$elapsed_new <= comparison$budget
write.csv(comparison, file.path(root, "budget_comparison.csv"), row.names = FALSE)
cat("GRAPH_PAGER_ORDERED_ROWS_EXACT_READONLY_PURE; ELAPSED_BUDGETS_RECORDED_NOT_WAIVED\n")
