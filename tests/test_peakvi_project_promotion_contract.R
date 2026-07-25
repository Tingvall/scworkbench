test_peakvi_project_promotion_contract <- function() {
  # Bounded mock: pybench execution is replaced, while the registered runner,
  # session, staging overlay, and promotion machinery remain real.
  if (!requireNamespace("BPCells", quietly=TRUE)) return(TRUE)
  root <- tempfile("scwb_peakvi_project_"); b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  ids <- paste0("c",1:4); wb_define_cells(b,ids)
  wb_attach_matrix(b,"ATAC_counts",matrix(seq_len(12),3,dimnames=list(paste0("p",1:3),ids)),feature_type="peak")
  op_env <- environment(wb_op_peakvi_project); old <- .wb_palantir_bridge_run_or_stop
  unlockBinding(".wb_palantir_bridge_run_or_stop", op_env)
  assign(".wb_palantir_bridge_run_or_stop", function(module, request, ...) {
    sb <- wb_open_bundle(request$bundle_dir); on.exit(wb_close_bundle(sb),add=TRUE)
    cells <- as.character(request$inputs$cell_ids); sid <- as.character(request$params$space_id_out)
    wb_add_space(sb,sid,matrix(seq_len(length(cells)*2),length(cells),2,dimnames=list(cells,c("z1","z2"))),source="mock")
    list(receipt=list(status="ok",protocol_version="1",pybench=list(version="mock"),timings=list(total=0)))
  },envir=op_env)
  on.exit({assign(".wb_palantir_bridge_run_or_stop",old,envir=op_env); lockBinding(".wb_palantir_bridge_run_or_stop",op_env)},add=TRUE)
  model <- wb_prim_model_ref("peakvi_model","peakvi_model",engine="peakvi"); model$model_path <- tempfile(); dir.create(model$model_path)
  rr <- wb_session_run_op(wb_session_new(),b,"peakvi_project",inputs=list(matrix="ATAC_counts",model=model,cell_set="all",min_cells=1L,batch_key="batch",space_id_out="projected"))
  stopifnot(all(c("space","fit_summary") %in% names(rr$run$outputs)), "projected" %in% wb_spaces(wb_session_view(rr$session))$space_id)
  p <- wb_session_promote_current(b,rr$session,outputs="fit_summary")
  wb_close_bundle(b); b <- wb_open_bundle(root)
  stopifnot("projected" %in% wb_spaces(b)$space_id, nrow(p$promoted[p$promoted$output=="fit_summary",])==1L, isTRUE(wb_validate_bundle(root)))
  TRUE
}
