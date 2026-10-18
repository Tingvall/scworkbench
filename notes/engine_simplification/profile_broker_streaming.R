args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[1L]] %in% c("baseline", "candidate"))
.libPaths(c(args[[2L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
old <- scworkbench:::.wb_operation_pack_v3_broker_source
e <- new.env(parent = asNamespace("scworkbench"))
sys.source("R/operation_pack_typed_slice_broker.R", e)
sys.source("tests/test_engine_broker_streaming_contract.R", e)
fixture <- e$.engine_broker_fixture()
tryCatch({
  for (parts in c(8L, 32L)) {
    bound <- e$.engine_broker_grant(fixture, chunk_size = 64L / parts)
    ctx <- e$.engine_broker_context()
    # Both modes count the same full source-authentication function.
    if (args[[1L]] == "baseline") environment(old) <- ctx
    reader <- NULL
    preparation <- system.time(if (args[[1L]] == "candidate") reader <-
      ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
        fixture$stage, bound$grant, bound$axes))[["elapsed"]]
    elapsed <- system.time(for (cells in wb_partition_axis(fixture$cells, 64L / parts)) {
      value <- if (args[[1L]] == "baseline") old(fixture$staged$bundle,
        fixture$stage, bound$grant, fixture$features, cells) else
          reader$read(fixture$features, cells)
      stopifnot(identical(value, fixture$values[, cells, drop = FALSE]))
    })[["elapsed"]]
    if (!is.null(reader)) reader$close()
    cat(sprintf("BROKER mode=%s parts=%d preparation_seconds=%.6f delivery_seconds=%.6f full_source_checks=%d exact_values=TRUE\n",
      args[[1L]], parts, preparation, elapsed, ctx$full))
  }
}, finally = e$.engine_broker_close(fixture))
