test_targeted_reproduction_plan_contract <- function() {
  if (!requireNamespace("uwot", quietly = TRUE)) return(TRUE)
  root <- tempfile("scwb_target_plan_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", seq_len(12)); coords <- matrix(seq_len(48)/10, nrow=12, dimnames=list(cells,paste0("d",1:4)))
  wb_define_cells(b, cells); wb_add_space(b, "pca_source", coords, source="test", overwrite=TRUE)
  source_plan <- wb_target_reproduction_plan(b, "space:pca_source")
  stopifnot(inherits(source_plan, "wb_target_reproduction_plan"), identical(source_plan$status, "source_state"), !source_plan$reproducible)
  res <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs=list(space="pca_source", cell_set="all", min_cells=1L, dims=1:4, space_id_out="umap_target", n_neighbors=3L, min_dist=.1, metric="euclidean", nn_method="annoy", seed=1L))
  promoted <- wb_session_promote_current(b, res$session, outputs=c("model","space_2d"))
  plan <- wb_target_reproduction_plan(b, "space:umap_target")
  stopifnot(identical(plan$status,"ok"), identical(plan$run_order, res$run$run_id), all(c("model","space_2d") %in% plan$terminal_outputs$output_name), all(plan$terminal_outputs$verification_level == "content"))
  stopifnot(identical(plan$run_order, wb_target_reproduction_plan(b, paste0("run:", res$run$run_id))$run_order))
  model_id <- paste("uwot", "umap_target", "pca_source", sep="|")
  stopifnot(identical(wb_target_reproduction_plan(b, paste0("model:",model_id))$status,"ok"))
  script <- wb_target_emit_r_script(plan)
  stopifnot(length(script)==1L, grepl("wb_session_promote_current",script,fixed=TRUE), grepl("writable ingestion-ready",script,fixed=TRUE))
  stopifnot(nrow(promoted$promoted) >= 2L,
            !"wb_target_reproduction_branch_template" %in% getNamespaceExports("scworkbench"))
  TRUE
}
