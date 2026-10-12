args <- commandArgs(TRUE)
stopifnot(length(args) == 1L, args[[1L]] %in% c("original", "pinned"))
mode <- args[[1L]]
core_lib <- "/tmp/scwb-graph-final-valid-522.hxhra5_g/library"
.libPaths(c(core_lib, .libPaths()))
library(scworkbench, lib.loc = core_lib)
options(warn = 1)
original_ns <- asNamespace("scworkbench")
original_registry <- get(".wb_operation_pack_registry", envir = original_ns)
original_fn <- scworkbench::wb_operation_pack_capabilities
snapshot <- function(label) {
  current_ns <- asNamespace("scworkbench")
  attached_fn <- get("wb_operation_pack_capabilities", envir = as.environment("package:scworkbench"))
  current_fn <- scworkbench::wb_operation_pack_capabilities
  current_registry <- get(".wb_operation_pack_registry", envir = current_ns)
  cat("STATE", label, "mode=", mode, "namespace_path=", getNamespaceInfo(current_ns, "path"),
    "system_file_root=", base::system.file(package = "scworkbench"),
    "system_file_sdk=", base::system.file("sdk", "operation-packs", "capabilities.json", package = "scworkbench"),
    "attached_fn_env=", format(environment(attached_fn)), "current_fn_env=", format(environment(current_fn)),
    "attached_current_env_identical=", identical(environment(attached_fn), environment(current_fn)),
    "original_current_ns_identical=", identical(original_ns, current_ns),
    "original_current_registry_identical=", identical(original_registry, current_registry),
    "original_fn_current_env_identical=", identical(environment(original_fn), environment(current_fn)), "\n")
  if ("scwbV2Reference" %in% loadedNamespaces()) {
    entry <- getExportedValue("scwbV2Reference", "register_operation_pack")
    cat("FIXTURE_STATE namespace_path=", getNamespaceInfo(asNamespace("scwbV2Reference"), "path"),
      "entry_env=", format(environment(entry)), "\n")
  }
}
run_case <- function(label, fn) {
  result <- tryCatch({stopifnot(isTRUE(fn())); TRUE}, error = function(e) {
    cat("CASE_ERROR", label, "class=", paste(class(e), collapse = ","), "code=", e$code %||% "",
      "message=", conditionMessage(e), "\n"); FALSE
  })
  cat("CASE", label, if (result) "PASS" else "FAIL", "\n")
  result
}
sdk <- new.env(parent = globalenv()); sys.source("tests/test_operation_pack_sdk_contract.R", envir = sdk)
v2 <- new.env(parent = globalenv()); sys.source("tests/test_operation_pack_v2_feature_set_registry_read_contract.R", envir = v2)
docs <- new.env(parent = globalenv())
sys.source("tests/test_operation_docs_single_source_contract.R", envir = docs)
if (mode == "pinned") {
  copied_generator <- normalizePath("notes/generic_graph_implementation/evidence/545_generate_operation_docs_pinned.R")
  original <- readLines("inst/dev/generate_operation_docs.R", warn = FALSE)
  replacement <- '  stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("scworkbench"), "path")), normalizePath(file.path(core_lib, "scworkbench"))))'
  stopifnot(sum(grepl('  devtools::load_all(".", quiet = TRUE)', original, fixed = TRUE)) == 1L)
  original[original == '  devtools::load_all(".", quiet = TRUE)'] <- replacement
  writeLines(original, copied_generator)
  test_source <- readLines("tests/test_operation_docs_single_source_contract.R", warn = FALSE)
  test_source <- sub('source("inst/dev/generate_operation_docs.R", local = TRUE)',
    'source(copied_generator, local = TRUE)', test_source, fixed = TRUE)
  eval(parse(text = test_source), envir = docs)
}
snapshot("before_docs")
stopifnot(run_case("sdk_before_docs", sdk$test_operation_pack_sdk_catalog_coverage))
doc_pass <- run_case("docs_unchanged_assertions", docs$test_operation_docs_single_source_contract)
snapshot("after_docs")
sdk_pass <- run_case("sdk_after_docs", sdk$test_operation_pack_sdk_catalog_coverage)
v2_pass <- run_case("v2_feature_set_registry_fail_closed", v2$test_operation_pack_v2_feature_set_registry_fail_closed_contract)
snapshot("after_v2")
stopifnot(doc_pass)
if (mode == "original") stopifnot(!sdk_pass, !v2_pass) else stopifnot(sdk_pass, v2_pass,
  identical(original_ns, asNamespace("scworkbench")),
  identical(original_registry, get(".wb_operation_pack_registry", envir = asNamespace("scworkbench"))))
cat("DIAGNOSTIC_EXPECTATIONS PASS mode=", mode, "\n", sep = "")
