test_geneprograms_extraction_contract <- function() {
  moved <- c("addmodulescore", "ucell", "cell_vector_family_reduce",
    "cell_vector_family_calibrate", "cell_vector_family_qc",
    "cell_vector_family_graph_smooth", "cell_vector_winners",
    "winner_cell_sets", "feature_set_overlap_qc", "pathway_enrich")
  qualified <- paste0("scwbgeneprograms::", moved)
  stopifnot(length(wb_list_ops()) == 10L,
    !any(moved %in% wb_list_ops()), !any(qualified %in% wb_list_ops()))
  map <- getFromNamespace(".wb_operation_pack_migrated_map", "scworkbench")()
  stopifnot(identical(unname(map[moved]), qualified))
  for (name in moved) {
    error <- tryCatch(getFromNamespace(".wb_op", "scworkbench")(name),
      error = identity)
    stopifnot(inherits(error, "wb_operation_pack_error"),
      identical(error$code, "OPERATION_PACK_REQUIRED"),
      identical(error$required_operation, map[[name]]))
  }
  exports <- getNamespaceExports("scworkbench")
  retired <- c("wb_op_addmodulescore", "wb_op_cell_vector_family_reduce",
    "wb_op_cell_vector_family_calibrate", "wb_op_cell_vector_family_qc",
    "wb_op_cell_vector_family_graph_smooth", "wb_op_cell_vector_winners",
    "wb_cell_vector_winners_from_artifact", "wb_register_winner_cell_sets",
    "wb_op_feature_set_overlap_qc", "wb_op_pathway_enrich")
  stopifnot(!any(retired %in% exports))
  retired_runners <- paste0(".wb_runner_", moved)
  ns <- asNamespace("scworkbench")
  stopifnot(!any(vapply(
    retired_runners,
    exists,
    logical(1),
    envir = ns,
    inherits = FALSE
  )))
  TRUE
}
