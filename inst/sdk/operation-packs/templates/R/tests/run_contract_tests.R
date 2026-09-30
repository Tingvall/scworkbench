args <- commandArgs(TRUE)
if (length(args)) .libPaths(c(args[[1L]], .libPaths()))
library(scworkbench)
package <- "@PACKAGE@"
operation <- "@NAMESPACE@::matrix_cell_sum"
before <- wb_list_ops()
loadNamespace(package)
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_load(package)
fixture <- wb_operation_pack_sdk_fixture(tempfile("sdk-contract-bundle-"))
bundle <- fixture$bundle
inputs <- function(size) list(matrix = "counts", cell_set = "set:sdk_subset",
  min_cells = 1L, chunk_size = size)
last <- NULL
cases <- lapply(c(1L, 2L, 3L), function(size) function() {
  result <- wb_operation_pack_sdk_run(bundle, operation, inputs(size))
  wb_operation_pack_sdk_assert(result, outputs = list(sums = list(
    cell_id = fixture$selected, value = as.character(fixture$sums),
    value_type = "continuous")), params = list(chunk_size = size, finite_policy = "error"))
  observation <- result$read_observations[[1L]]
  stopifnot(length(observation$calls) == ceiling(length(fixture$selected) / size),
    observation$coverage_status == "exact", observation$duplicate_chunk_axis_count == 0L,
    identical(vapply(observation$calls, `[[`, integer(1), "cell_count"),
      as.integer(lengths(wb_partition_axis(fixture$selected, size)))),
    identical(vapply(observation$calls, `[[`, integer(1), "ordinal"),
      seq_along(observation$calls)),
    all(vapply(observation$calls, `[[`, integer(1), "cell_count") <= size),
    identical(result$result$run$outputs$summary$table$first_cell,
      vapply(wb_partition_axis(fixture$selected, size), `[`, character(1), 1L)))
  last <<- result
  wb_session_discard(result$result$session)
})
names(cases) <- paste0("real_reader_chunk_", c(1L, 2L, 3L))
cases$invalid_chunk_size <- function() {
  result <- wb_operation_pack_sdk_run(bundle, operation, inputs(0L))
  stopifnot(!result$ok, result$unchanged)
}
cases$missing_matrix <- function() {
  bad <- inputs(2L); bad$matrix <- "sdk_absent_matrix"
  result <- wb_operation_pack_sdk_run(bundle, operation, bad)
  stopifnot(!result$ok, result$unchanged)
}
cases$empty_selection <- function() {
  wb_cell_set_replace(bundle, "set:sdk_empty", character(), source = "sdk_fixture")
  bad <- inputs(2L); bad$cell_set <- "set:sdk_empty"
  result <- wb_operation_pack_sdk_run(bundle, operation, bad)
  stopifnot(!result$ok, result$unchanged)
}
for (fault in c("skip_partition", "repeat_partition", "reversed_partition",
    "oversized_partition", "foreign_partition", "missing_terminal", "reordered_output",
    "after_first_terminal", "before_publication", "published")) {
  cases[[paste0("rollback_", fault)]] <- local({ point <- fault; function() {
    result <- wb_operation_pack_sdk_run(bundle, operation, inputs(2L), fault = point)
    stopifnot(!result$ok, result$unchanged,
      !grepl("unexpectedly admitted", conditionMessage(result$error), fixed = TRUE))
  }})
}
cases$retry_and_recipient <- function() {
  result <- wb_operation_pack_sdk_run(bundle, operation, inputs(2L))
  wb_operation_pack_sdk_assert(result)
  promoted <- wb_session_promote_current(bundle, result$result$session, outputs = c("sums", "summary"))
  stopifnot(all(c("sums", "summary") %in% promoted$promoted$output))
  wb_operation_pack_sdk_recipient(bundle, tempfile("sdk-recipient-"), operation)
  wb_session_discard(result$result$session)
}
report <- wb_operation_pack_sdk_cases(cases)
if (length(args) >= 2L) saveRDS(report, args[[2L]])
quit(status = if (isTRUE(report$qualified)) 0L else 1L)
