args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2L]]; stopifnot(!dir.exists(root)); dir.create(root)
b <- wb_init_bundle(file.path(root, "source.bundle"))
cells <- paste0("cell_", seq_len(300L))
wb_define_cells(b, cells, metadata = data.frame(cell_id = cells,
  group = rep(c("a", "b"), 150L)))
staged <- scworkbench:::.wb_session_stage_bundle(b, wb_session_new())
work <- staged$bundle
rows <- list()
scworkbench:::.wb_with_mutation_context(work, route = "session_execution", code = {
  for (mode in c("baseline", "candidate")) {
    counter <- new.env(parent = emptyenv()); counter$n <- 0L
    options(engine.registry.benchmark.counter = counter)
    trace(".wb_manifest_registry_snapshot", where = asNamespace("scworkbench"),
      print = FALSE, tracer = quote({
        count <- getOption("engine.registry.benchmark.counter")
        count$n <- count$n + 1L
      }))
    before <- proc.time()
    values <- lapply(seq_len(5L), function(i) if (mode == "baseline")
      scworkbench:::.wb_manifest_registry_snapshot(work$con) else
      scworkbench:::.wb_operation_pack_registry_snapshot(work))
    elapsed <- (proc.time() - before)[["elapsed"]]
    untrace(".wb_manifest_registry_snapshot", where = asNamespace("scworkbench"))
    stopifnot(all(vapply(values, identical, logical(1), values[[1L]])))
    if (mode == "baseline") expected <- values[[1L]] else
      stopifnot(identical(expected, values[[1L]]))
    rows[[length(rows) + 1L]] <- data.frame(mode = mode, elapsed = elapsed,
      full_registry_observations = counter$n,
      fingerprint = values[[1L]]$fingerprint)
  }
})
write.csv(do.call(rbind, rows), file.path(root, "measurements.csv"), row.names = FALSE)
print(do.call(rbind, rows), row.names = FALSE)
wb_session_discard(staged$session); wb_close_bundle(b)
cat("REGISTRY_SCOPED_IDENTITY_AND_FIVE_TO_ONE_OK\n")
