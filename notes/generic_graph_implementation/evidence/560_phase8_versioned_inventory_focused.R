core_library <- "/tmp/scwb-legacy-content-550.10_683h8/library"
.libPaths(c(core_library, .libPaths()))
library(scworkbench, lib.loc = core_library)
expected_path <- normalizePath(file.path(core_library, "scworkbench"), mustWork = TRUE)
namespace <- asNamespace("scworkbench")
registry <- get(".wb_operation_pack_registry", envir = namespace)
stopifnot(identical(normalizePath(getNamespaceInfo(namespace, "path"), mustWork = TRUE), expected_path))
cat("PHASE8_RUNTIME installed_path=", expected_path,
  " ownership_review_base=441297513b9a1b41fae23764c9a85c3b129cf0b7 hot_reload=NONE\n", sep = "")
tests <- new.env(parent = namespace)
sys.source("tests/test_phase8_no_pack_core_surface_contract.R", envir = tests)
selected <- c("test_phase8_no_pack_core_surface_contract",
  "test_phase8_primitive_exchange_inventory_contract", "test_phase8_test_ownership_inventory_contract")
results <- vapply(selected, function(name) {
  cat("RUN ", name, "\n", sep = "")
  success <- tryCatch({ stopifnot(isTRUE(do.call(get(name, envir = tests), list()))); TRUE },
    error = function(error) { cat("FAIL ", name, " -- ", conditionMessage(error), "\n", sep = ""); FALSE })
  stopifnot(identical(namespace, asNamespace("scworkbench")),
    identical(registry, get(".wb_operation_pack_registry", envir = asNamespace("scworkbench"))),
    identical(normalizePath(getNamespaceInfo(asNamespace("scworkbench"), "path"), mustWork = TRUE), expected_path))
  if (success) cat("PASS ", name, "\n", sep = "")
  success
}, logical(1))
cat("PHASE8_FOCUSED_SUMMARY passed=", sum(results), " failed=", sum(!results),
  " installed_namespace_unchanged=TRUE\n", sep = "")
stopifnot(all(results))
