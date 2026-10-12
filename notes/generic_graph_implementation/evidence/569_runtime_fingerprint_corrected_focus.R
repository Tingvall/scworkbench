core_library <- "/tmp/scwb-legacy-inspection-566.e46ahol2/library"
.libPaths(c(core_library, .libPaths()))
library(scworkbench, lib.loc = core_library)
Sys.setenv(SCWB_CONTRACT_INSTALLED_LIBRARY = core_library)
namespace <- asNamespace("scworkbench")
registry <- get(".wb_operation_pack_registry", envir = namespace)
repo <- normalizePath(".", mustWork = TRUE)
cat("CORRECTED_FOCUS installed_parent=", getNamespaceInfo(namespace, "path"),
  " explicit_child_library=", core_library, " simulated_source_lookup=", repo,
  " parent_hot_reload=NONE\n", sep = "")
test_env <- new.env(parent = namespace)
sys.source("tests/test_promotion_runtime_fingerprint_metadata_contract.R", envir = test_env)
test_env$find.package <- function(package, ...) {
  if (identical(package, "scworkbench")) repo else base::find.package(package, ...)
}
names <- c("test_promotion_runtime_fingerprint_metadata_loadability_contract",
  "test_promotion_runtime_fingerprint_metadata_parity_contract",
  "test_promotion_runtime_fingerprint_legacy_public_commit_contract")
results <- vapply(names, function(name) {
  cat("RUN ", name, "\n", sep = "")
  success <- tryCatch({ stopifnot(isTRUE(do.call(get(name, envir = test_env), list()))); TRUE },
    error = function(error) { cat("FAIL ", name, " -- ", conditionMessage(error), "\n", sep = ""); FALSE })
  stopifnot(identical(namespace, asNamespace("scworkbench")),
    identical(registry, get(".wb_operation_pack_registry", envir = asNamespace("scworkbench"))),
    identical(normalizePath(getNamespaceInfo(namespace, "path")), normalizePath(file.path(core_library, "scworkbench"))))
  if (success) cat("PASS ", name, "\n", sep = "")
  success
}, logical(1))
cat("FINGERPRINT_CORRECTED_SUMMARY passed=", sum(results), " failed=", sum(!results),
  " installed_parent_namespace_unchanged=TRUE\n", sep = "")
stopifnot(all(results))
