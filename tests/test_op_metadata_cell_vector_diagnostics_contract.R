test_op_metadata_cell_vector_diagnostics_contract <- function() {
  contract_test_activate_statistics_pack()
  stopifnot(all(c("metadata_cell_vector", "scwbstatistics::cell_vector_association") %in% wb_list_ops()))
  stopifnot(identical(wb_op_interface("metadata_cell_vector")$produces$vector$kind, "cell_vector"))
  stopifnot(identical(wb_op_interface("cell_vector_association")$produces$summary$kind, "obs_table"))

  root <- tempfile("scwb_metadata_vector_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  ids <- paste0("c", 1:8)
  md <- data.frame(cell_id = ids, perturbation = rep(c("ctrl", "drug"), each = 4),
                   lane = rep(c("L1", "L2"), times = 4), qc = c(1, 2, 3, 4, 10, 11, 12, 13), stringsAsFactors = FALSE)
  wb_define_cells(b, ids, metadata = md, set_name = "core")
  wb_attach_space(b, "umap", data.frame(cell_id = ids, x = seq_along(ids), y = rev(seq_along(ids))))

  s <- wb_session_new()
  p <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "perturbation", vector_name = "perturbation", value_type = "categorical", missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- p$session
  l <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "lane", vector_name = "lane", value_type = "auto", missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- l$session
  q <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "qc", vector_name = "qc", value_type = "auto", missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- q$session
  cc <- wb_session_run_op(s, b, "cell_vector_association", inputs = list(a = wb_ref_run(p$run$run_id, "vector"), b = wb_ref_run(l$run$run_id, "vector"), cell_set = "all", min_cells = 1L)); s <- cc$session
  cg <- wb_session_run_op(s, b, "cell_vector_association", inputs = list(a = wb_ref_run(q$run$run_id, "vector"), b = wb_ref_run(p$run$run_id, "vector"), cell_set = "all", min_cells = 1L)); s <- cg$session
  promoted <- wb_session_promote_current(b, s, created_by = "test", outputs = list(
    wb_ref_run(p$run$run_id, "vector"), wb_ref_run(l$run$run_id, "vector"), wb_ref_run(q$run$run_id, "vector"),
    wb_ref_run(cc$run$run_id, "summary"), wb_ref_run(cc$run$run_id, "detail"),
    wb_ref_run(cg$run$run_id, "summary"), wb_ref_run(cg$run$run_id, "detail")
  ))
  ok <- promoted$promoted[promoted$promoted$status == "ok", , drop = FALSE]
  stopifnot(nrow(ok) == 7L, all(ok$lineage_status == "complete"))
  vector_ids <- ok$artifact_id[ok$run_id %in% c(p$run$run_id, l$run$run_id, q$run$run_id)]
  wb_close_bundle(b); b <- wb_open_bundle(root)
  vecs <- lapply(vector_ids, function(id) wb_art_load(b, id, expected_kind = "cell_vector"))
  stopifnot(identical(vecs[[1]]$value_type, "categorical"), identical(vecs[[3]]$value_type, "continuous"))
  cert <- wb_entity_certificate(b, "artifact", vector_ids[[1]])
  persisted_params <- cert$producer$run$parameters$value
  stopifnot(identical(persisted_params$source_column, "perturbation"), identical(persisted_params$cell_set, "all"), identical(persisted_params$missing_policy, "error"))
  cc_summary <- cc$run$outputs$summary$table
  stopifnot(identical(cc_summary$association_type, "categorical_x_categorical"), identical(cc_summary$effect_size_name, "cramers_v"), "min_expected" %in% names(cc_summary))
  stopifnot(identical(cg$run$outputs$summary$table$association_type, "continuous_x_categorical"))
  cont <- wb_session_run_op(wb_session_new(), b, "cell_vector_association", inputs = list(
    a = vecs[[3]], b = wb_prim_cell_vector(stats::setNames(seq_along(ids), ids),
      value_type = "continuous"), cell_set = "all", min_cells = 1L))
  stopifnot(identical(cont$run$outputs$summary$table$association_type,
    "continuous_x_continuous"), "spearman" %in% names(cont$run$outputs$summary$table))
  duplicate <- try(wb_session_run_op(wb_session_new(), b, "metadata_cell_vector", inputs = list(source_column = "lane", vector_name = "lane", cell_set = "all", min_cells = 1L)), silent = TRUE)
  stopifnot(inherits(duplicate, "try-error"))
  plot <- wb_wrangle_plot_dataset("embedding_overlay", list(space = wb_prim_space_2d("umap"), color = vecs[[1]]), b)
  stopifnot(nrow(plot$table) == length(ids), all(c("cell_id", "color_value", "color_type") %in% names(plot$table)))
  TRUE
}
