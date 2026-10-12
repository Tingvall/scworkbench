core_library <- "/tmp/scwb-legacy-inspection-566.e46ahol2/library"
.libPaths(c(core_library, .libPaths()))
library(scworkbench, lib.loc = core_library)
namespace <- asNamespace("scworkbench")
repo <- normalizePath(".", mustWork = TRUE)
cat("UNCHANGED_TEST stimulus=source_package_find_lookup repo=", repo,
  " wrong_child_library=", dirname(repo), " installed_parent=", getNamespaceInfo(namespace, "path"),
  " parent_hot_reload=NONE\n", sep = "")
test_env <- new.env(parent = namespace)
sys.source("tests/test_promotion_runtime_fingerprint_metadata_contract.R", envir = test_env)
# Mimic only the package lookup observed in polluted525; keep the original
# test function and the installed namespace unchanged throughout diagnosis.
test_env$find.package <- function(package, ...) {
  if (identical(package, "scworkbench")) repo else base::find.package(package, ...)
}
result <- tryCatch(test_env$test_promotion_runtime_fingerprint_metadata_loadability_contract(),
  error = function(error) { cat("UNCHANGED_TEST_ERROR ", conditionMessage(error), "\n", sep = ""); FALSE })
stopifnot(identical(namespace, asNamespace("scworkbench")))
cat("UNCHANGED_TEST_RESULT accepted=", isTRUE(result), " namespace_unchanged=TRUE\n", sep = "")
if (!isTRUE(result)) quit(status = 1L)
