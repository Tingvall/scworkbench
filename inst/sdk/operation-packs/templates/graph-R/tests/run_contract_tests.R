args <- commandArgs(TRUE)
if (length(args)) .libPaths(c(args[[1L]], .libPaths()))
library(scworkbench)
before <- wb_list_ops()
loadNamespace("@PACKAGE@")
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_load("@PACKAGE@")
fixture <- wb_operation_pack_sdk_fixture(tempfile("graph-sdk-source-"))
bundle <- fixture$bundle
graph_id <- NULL
cases <- list()
cases$matrix_graph_promotion <- function() {
  result <- wb_operation_pack_sdk_run(bundle, "@NAMESPACE@::matrix_to_graph",
    list(matrix = "counts", cell_set = "set:sdk_subset", min_cells = 1L))
  wb_operation_pack_sdk_assert(result)
  promoted <- wb_session_promote_current(bundle, result$result$session, outputs = "result")
  graph_id <<- as.character(promoted$promoted$artifact_id[[1L]])
  stopifnot(identical(vapply(wb_art_graph_slice(bundle, graph_id, "nodes"),
    `[[`, character(1), "node_id"), fixture$selected))
  wb_session_discard(result$result$session)
}
cases$bounded_graph_summary <- function() {
  result <- wb_operation_pack_sdk_run(bundle, "@NAMESPACE@::graph_to_table",
    list(source = wb_ref_artifact(graph_id, "result")))
  wb_operation_pack_sdk_assert(result)
  stopifnot(result$result$run$outputs$summary$table$nodes == as.character(length(fixture$selected)))
  wb_session_promote_current(bundle, result$result$session, outputs = "summary")
  wb_session_discard(result$result$session)
}
for (fault in c("before_publication", "published")) cases[[paste0("rollback_", fault)]] <-
  local({point <- fault; function() {
    result <- wb_operation_pack_sdk_run(bundle, "@NAMESPACE@::graph_to_table",
      list(source = wb_ref_artifact(graph_id, "result")), fault = point)
    stopifnot(!result$ok, result$unchanged,
      grepl("SDK injected publication failure", conditionMessage(result$error), fixed = TRUE))
  }})
cases$authenticated_annotations <- function() {
  vector <- wb_prim_cell_vector(stats::setNames(rep("label", length(fixture$selected)), fixture$selected))
  run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "set:sdk_subset"),
    params = list(), outputs = list(vector = vector))
  promoted <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
    run$run_id, outputs = "vector")
  source_id <- as.character(promoted$promoted$artifact_id[[1L]])
  result <- wb_operation_pack_sdk_run(bundle, "@NAMESPACE@::graph_and_cell_metadata",
    list(source = wb_ref_artifact(graph_id, "result"), metadata = wb_ref_artifact(source_id, "vector"),
      cell_set = "set:sdk_subset", min_cells = 1L))
  wb_operation_pack_sdk_assert(result)
  promoted <- wb_session_promote_current(bundle, result$result$session, outputs = "result")
  stopifnot(nrow(promoted$promoted) == 2L)
  id <- as.character(promoted$promoted$artifact_id[promoted$promoted$output == "result"][[1L]])
  stopifnot(wb_art_graph_info(bundle, id)$source_authority$status == "verified")
  wb_session_discard(result$result$session)
}
cases$recipient <- function() {
  audit <- wb_operation_pack_sdk_recipient(bundle,
    tempfile("graph-sdk-recipient-"), "@NAMESPACE@::matrix_to_graph")
  bundle <<- NULL
  report <- wb_bundle_validation_report(audit$path, level = "recipient")
  stopifnot(report$ok, identical(report$pre_validation_fingerprint, report$post_validation_fingerprint))
}
report <- wb_operation_pack_sdk_cases(cases)
if (length(args) >= 2L) saveRDS(report, args[[2L]])
if (!is.null(bundle)) wb_close_bundle(bundle)
quit(status = if (isTRUE(report$qualified)) 0L else 1L)
