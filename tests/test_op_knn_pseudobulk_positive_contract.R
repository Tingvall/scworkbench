test_op_knn_pseudobulk_positive_contract <- function() {
  root <- tempfile("knn-pseudobulk-positive-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("q1", "q2", "c1", "c2", "c3")
  features <- c("f1", "f2")
  values <- matrix(c(0, 0, 1, 2, 10, 0, 0, 10, 20, 100),
    nrow = 2L, byrow = TRUE, dimnames = list(features, cells))
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "gene")
  coordinates <- cbind(x = c(0, 10, 1, 2, 9), y = rep(0, 5L))
  rownames(coordinates) <- cells
  wb_add_space(bundle, "latent", coordinates, overwrite = TRUE)

  expected <- list(sum = c(3, 30, 12, 120),
    mean = c(1.5, 15, 6, 60))
  for (aggregate in names(expected)) {
    executed <- wb_session_run_op(wb_session_new(), bundle,
      "knn_pseudobulk", inputs = list(matrix = "RNA", space = "latent",
        query_cells = c("q1", "q2"),
        candidate_cells = c("c1", "c2", "c3"), features = features,
        k = 2L, include_query = FALSE, aggregate = aggregate,
        min_cells = 1L))
    table <- executed$run$outputs$pseudobulk_table$table
    distance <- executed$run$outputs$neighbor_distance
    stopifnot(
      identical(table$feature_id, rep(features, 2L)),
      identical(table$query_cell_id, rep(c("q1", "q2"), each = 2L)),
      identical(table$n_neighbors, rep(2L, 4L)),
      identical(table$aggregate, rep(aggregate, 4L)),
      identical(table$value, expected[[aggregate]]),
      identical(distance$key, rep(c("q1", "q2"), each = 2L)),
      identical(distance$cell_id, c("c1", "c2", "c3", "c2")),
      identical(distance$value, c(1, 2, 1, 8)),
      identical(executed$run$params$matrix_id, "RNA"),
      identical(executed$run$params$space_id, "latent"),
      identical(executed$run$params$n_query, 2L),
      identical(executed$run$params$n_candidates, 3L),
      identical(executed$run$params$n_features, 2L),
      identical(executed$run$params$k, 2L),
      identical(executed$run$params$aggregate, aggregate),
      identical(executed$run$params$include_query, FALSE))

    promotion <- wb_session_promote_current(bundle, executed$session,
      outputs = names(executed$run$outputs), created_by = "contract")
    stopifnot(all(promotion$promoted$status == "ok"))
    details <- wb_prov_run_details(bundle, executed$run$run_id,
      promotion$provenance_snapshot_id)
    output <- details$outputs[order(details$outputs$output_name,
      method = "radix"), , drop = FALSE]
    stopifnot(
      identical(as.character(details$run$op_name), "knn_pseudobulk"),
      identical(as.character(output$output_name),
        c("neighbor_distance", "pseudobulk_table")),
      identical(as.character(output$primitive_kind),
        c("cell_vector_family", "feature_table")),
      all(as.character(output$verification_status) == "content_verified"),
      all(as.character(output$replay_equivalence_policy) ==
        "exact_canonical_value"),
      all(!is.na(output$content_sha256) & nzchar(output$content_sha256)),
      identical(as.character(details$run$params$aggregate), aggregate),
      identical(as.character(details$run$symbolic_inputs$matrix), "RNA"),
      identical(as.character(details$run$symbolic_inputs$space), "latent"))
    executed$session <- wb_session_discard(executed$session)
  }
  TRUE
}
