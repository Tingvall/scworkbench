args <- commandArgs(trailingOnly = TRUE)
if (length(args)) .libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
e <- new.env(parent = asNamespace("scworkbench"))
if (length(args) > 1L && args[[2L]] == "source") {
  for (file in c("R/operation_pack_v3_transition.R",
      "R/operation_pack_v3_sparse_membership.R")) for (z in parse(file)) {
    if (is.call(z) && identical(z[[1L]], as.name("<-")) &&
        as.character(z[[2L]]) %in% c(
          ".wb_operation_pack_v3_deliver_owned_block",
          ".wb_operation_pack_v3_add_typed_space_readers")) eval(z, e)
  }
}
sys.source("tests/test_engine_owned_block_copy_contract.R", e)
functions <- ls(e, pattern = "^test_")
for (name in functions) {
  stopifnot(isTRUE(e[[name]]()))
  cat(name, "PASS\n")
}
cat(sprintf("FOCUSED discovered=%d executed=%d passed=%d skipped=0 failed=0\n",
  length(functions), length(functions), length(functions)))
helper <- e$.wb_owned_block_test_context()$deliver
for (size in c(512L, 2000L)) {
  value <- e$.wb_owned_block_fixture(size)
  for (mode in c("serialization", "owned")) {
    f <- if (mode == "owned") helper else function(x)
      unserialize(serialize(x, NULL, version = 3L))
    invisible(f(value))
    path <- tempfile("owned_block_profile_")
    Rprofmem(path)
    elapsed <- tryCatch(system.time(for (i in seq_len(20L))
      invisible(f(value)))[["elapsed"]], finally = Rprofmem(NULL))
    lines <- readLines(path, warn = FALSE)
    unlink(path)
    bytes <- sum(as.numeric(sub(" .*", "", lines[grepl("^[0-9]+", lines)])))
    cat(sprintf(paste0("DELIVERY mode=%s rows=%d columns=%d object_bytes=%.0f ",
      "calls=20 elapsed_seconds=%.6f mean_seconds=%.6f allocated_bytes_per_call=%.0f\n"),
      mode, size, size, as.numeric(object.size(value)), elapsed, elapsed / 20,
      bytes / 20))
    if (mode == "owned") stopifnot(bytes / 20 < 1024^2)
  }
}
