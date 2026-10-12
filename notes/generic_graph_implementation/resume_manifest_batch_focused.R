args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(args[[1L]], "library", "scworkbench"))))
tests <- new.env(parent = globalenv())
sys.source("tests/test_manifest_stream_identity_contract.R", tests)
names <- sort(ls(tests, pattern = "^test_"))
for (name in names) {
  stopifnot(isTRUE(tests[[name]]()))
  cat(name, "PASS\n")
}
cat("MANIFEST_BATCH_INSTALLED_FOCUSED executed=", length(names), " skipped=0 qualification=FALSE\n", sep = "")
