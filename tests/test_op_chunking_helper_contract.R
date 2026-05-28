test_op_chunking_helper_contract <- function() {
  parts <- scworkbench:::.wb_chunk_partition(c("c1", "c2", "c3", "c4", "c5"), chunk_size = 2)
  stopifnot(length(parts) == 3L)
  stopifnot(identical(parts[[1]], c("c1", "c2")))
  stopifnot(identical(parts[[3]], c("c5")))

  runner_cells <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
    vals <- stats::setNames(seq_along(effective_cells), as.character(effective_cells))
    list(
      outputs = list(
        score = wb_prim_cell_vector(vals, value_type = "continuous"),
        score_family = wb_prim_cell_vector_family(
          key = rep("sig", length(effective_cells)),
          cell_id = as.character(effective_cells),
          value = as.numeric(seq_along(effective_cells)),
          value_type = "continuous"
        )
      ),
      params = list(n_cells = length(effective_cells))
    )
  }

  rr_cells <- scworkbench:::.wb_run_op_in_chunks(
    bundle = NULL,
    resolved = list(),
    effective_cells = c("c1", "c2", "c3", "c4", "c5"),
    inputs = list(),
    runner = runner_cells,
    chunk_axis = "cells",
    chunk_size = 2L,
    merge_spec = list(
      score = "row_bind_cell_vector",
      score_family = "row_bind_cell_vector_family"
    ),
    context = list(
      score = list(cell_order = c("c1", "c2", "c3", "c4", "c5")),
      score_family = list(cell_order = c("c1", "c2", "c3", "c4", "c5"), key_order = "sig")
    )
  )

  stopifnot(is.list(rr_cells$outputs))
  stopifnot(identical(as.integer(rr_cells$params$chunking$n_chunks), 3L))
  stopifnot(identical(as.character(rr_cells$outputs$score$cell_id), c("c1", "c2", "c3", "c4", "c5")))
  stopifnot(identical(as.character(rr_cells$outputs$score_family$cell_id), c("c1", "c2", "c3", "c4", "c5")))
  stopifnot(identical(as.character(rr_cells$outputs$score_family$key), rep("sig", 5L)))

  runner_features <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
    feats <- as.character(inputs$features)
    tbl <- data.frame(
      feature_id = feats,
      rho = as.numeric(seq_along(feats)) / 10,
      stringsAsFactors = FALSE
    )
    sum_tbl <- data.frame(
      entity_id = paste0("chunk_", length(feats)),
      n_features = length(feats),
      stringsAsFactors = FALSE
    )
    list(
      outputs = list(
        trend_table = wb_prim_feature_table(tbl, table_type = "trend"),
        fit_summary = wb_prim_obs_table(sum_tbl, table_type = "fit_summary", entity_kind = "chunk")
      ),
      params = list(n_features = length(feats))
    )
  }

  rr_features <- scworkbench:::.wb_run_op_in_chunks(
    bundle = NULL,
    resolved = list(),
    effective_cells = c("c1", "c2"),
    inputs = list(features = c("g3", "g1", "g2")),
    runner = runner_features,
    chunk_axis = "features",
    chunk_size = 2L,
    merge_spec = list(
      trend_table = "row_bind_feature_table",
      fit_summary = "row_bind_obs_table"
    ),
    context = list(
      trend_table = list(feature_order = c("g3", "g1", "g2"))
    )
  )

  stopifnot(identical(as.character(rr_features$outputs$trend_table$table$feature_id), c("g3", "g1", "g2")))
  stopifnot(nrow(rr_features$outputs$fit_summary$table) == 2L)

  TRUE
}
