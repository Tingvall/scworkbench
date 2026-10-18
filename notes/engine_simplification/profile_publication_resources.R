# Coordinator-only component measurement. Separate baseline/candidate processes;
# exact fingerprints are compared outside the timed loops. Not a workflow claim.
args <- commandArgs(TRUE); stopifnot(length(args) == 3L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2L]]; mode <- args[[3L]]
stopifnot(!file.exists(root), mode %in% c("baseline", "candidate"))
dir.create(root, recursive = TRUE)
ns <- asNamespace("scworkbench")
con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "registry.sqlite"))
for (table in get(".wb_manifest_registry_table_names", ns)()) {
  quoted <- DBI::dbQuoteIdentifier(con, table)
  DBI::dbExecute(con, paste0("CREATE TABLE ", quoted,
    " (id INTEGER PRIMARY KEY,label TEXT,value REAL);"))
  DBI::dbExecute(con, paste0("INSERT INTO ", quoted, " VALUES(1,'same',1.5);"))
}
snapshot <- get(".wb_manifest_registry_snapshot", ns)
saveRDS(snapshot(con), file.path(root, "snapshot.rds"), version = 3)
# dbConnect generic entry counts are an instrumented resource observation, not
# a claim about arbitrary SQLite connections elsewhere in the workflow.
counter <- new.env(parent = emptyenv()); counter$value <- 0L
options(scwb.publication.connection_counter = counter)
trace("dbConnect", where = asNamespace("DBI"), print = FALSE,
  tracer = quote({c <- getOption("scwb.publication.connection_counter");
    c$value <- c$value + 1L}))
rows <- list()
for (i in seq_len(3L)) {
  counter$value <- 0L; start <- proc.time()
  value <- snapshot(con); elapsed <- (proc.time() - start)[["elapsed"]]
  rows[[i]] <- data.frame(mode = mode, replicate = i,
    elapsed_seconds = elapsed, observed_dbConnect_entries = counter$value)
}
untrace("dbConnect", where = asNamespace("DBI"))
options(scwb.publication.connection_counter = NULL)
DBI::dbDisconnect(con)
timings <- do.call(rbind, rows); print(timings, row.names = FALSE)
write.csv(timings, file.path(root, "snapshot_timings.csv"), row.names = FALSE)
if (mode == "candidate") {
  b <- wb_init_bundle(file.path(root, "witness.bundle"))
  wb_refresh_manifest(b)
  stopifnot(get(".wb_manifest_publication_reusable", ns)(b))
  n <- 100L; start <- proc.time()
  for (i in seq_len(n)) stopifnot(get(".wb_manifest_publication_reusable", ns)(b))
  elapsed <- (proc.time() - start)[["elapsed"]]
  result <- data.frame(checks = n, elapsed_seconds = elapsed,
    seconds_per_check = elapsed / n, budget_seconds_per_check = .1,
    budget_pass = elapsed / n <= .1)
  print(result, row.names = FALSE)
  write.csv(result, file.path(root, "witness_timings.csv"), row.names = FALSE)
  wb_close_bundle(b)
}
cat("PUBLICATION_RESOURCE_COMPONENT_MEASUREMENT_COMPLETE\n")
