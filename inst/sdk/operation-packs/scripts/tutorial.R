# Run from any directory: Rscript --vanilla tutorial.R /new/project/root
# Requires an installed scworkbench and its runtime dependencies; no downloads.
args <- commandArgs(TRUE)
library(scworkbench)
root <- if (length(args)) args[[1L]] else tempfile("sdk-tutorial-")
stopifnot(!file.exists(root)); dir.create(root)
project <- wb_operation_pack_scaffold(file.path(root, "Example Pack"),
  "scwbSdkTutorial", "sdktutorial", "Example Author", "author@example.org")
static <- wb_operation_pack_check(project$path, "static")
stopifnot(static$qualified, static$tests$executed == 0L)
checked <- wb_operation_pack_check(project$path, "contract", trusted = TRUE)
print(checked[c("qualified", "tests", "command_exits", "identity")])
stopifnot(checked$qualified)
.libPaths(c(checked$library, .libPaths()))
before <- wb_list_ops()
loadNamespace(project$package)
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_validate(project$package)
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_load(project$package)
operation <- "sdktutorial::matrix_cell_sum"
print(wb_op_interface(operation))
fixture <- wb_operation_pack_sdk_fixture(file.path(root, "source.bundle"))
result <- wb_operation_pack_sdk_run(fixture$bundle, operation,
  list(matrix = "counts", cell_set = "set:sdk_subset", min_cells = 1L, chunk_size = 2L))
wb_operation_pack_sdk_assert(result, outputs = list(sums = list(
  cell_id = fixture$selected, value = as.character(fixture$sums), value_type = "continuous")))
print(result$result$run$outputs); print(result$result$run$params)
promotion <- wb_session_promote_current(fixture$bundle, result$result$session, outputs = c("sums", "summary"))
stopifnot(all(c("sums", "summary") %in% promotion$promoted$output))
audit <- wb_operation_pack_sdk_recipient(fixture$bundle,
  file.path(root, "relocated.bundle"), operation)
print(audit$evidence)
wb_session_discard(result$result$session)
# Identity-bound replay: with the exact installed pack activated, the same source
# axis and effective parameters reproduce the canonical sums, not run IDs.
bundle <- wb_open_bundle(audit$path)
replay <- wb_operation_pack_sdk_run(bundle, operation,
  list(matrix = "counts", cell_set = "set:sdk_subset", min_cells = 1L, chunk_size = 2L))
wb_operation_pack_sdk_assert(replay, outputs = list(sums = list(
  cell_id = fixture$selected, value = as.character(fixture$sums), value_type = "continuous")))
wb_session_discard(replay$result$session)
wb_close_bundle(bundle)
cat("SDK_INSTALLED_TUTORIAL_OK\n")
