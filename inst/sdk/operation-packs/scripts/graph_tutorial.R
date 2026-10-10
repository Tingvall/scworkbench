args <- commandArgs(TRUE)
library(scworkbench)
root <- if (length(args)) args[[1L]] else tempfile("graph-sdk-tutorial-")
stopifnot(!file.exists(root)); dir.create(root)
project <- wb_operation_pack_scaffold(file.path(root, "Graph Reference"),
  "scwbGraphSdkTutorial", "graphsdktutorial", "Example Author", "author@example.org",
  template = "graph")
stopifnot(project$pack_abi_version == "4",
  wb_operation_pack_capabilities(pack_abi_version = "4", kind = "graph")$pack_abi_version == "4")
static <- wb_operation_pack_check(project$path, "static")
stopifnot(static$qualified, static$tests$executed == 0L)
checked <- wb_operation_pack_check(project$path, "contract", trusted = TRUE)
saveRDS(checked, file.path(root, "installed_graph_contract_report.rds"))
for (name in names(checked$diagnostics)) {
  cat("GRAPH_SDK_DIAGNOSTIC", name, "\n")
  cat(paste(checked$diagnostics[[name]], collapse = "\n"), "\n")
}
print(checked[c("qualified", "tests", "command_exits", "identity")])
stopifnot(checked$qualified, checked$tests$skipped == 0L, checked$tests$failed == 0L)
cat("GRAPH_SDK_INSTALLED_TUTORIAL PASS\n")
