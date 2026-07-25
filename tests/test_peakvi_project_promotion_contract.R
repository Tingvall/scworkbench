test_peakvi_project_promotion_contract <- function() {
  # Bounded mock: pybench execution is replaced, while the registered runner,
  # session, staging overlay, and promotion machinery remain real.
  if (!requireNamespace("BPCells", quietly=TRUE)) return(TRUE)
  root <- tempfile("scwb_peakvi_project_"); b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  ids <- paste0("c",1:4); wb_define_cells(b,ids)
  wb_attach_matrix(b,"ATAC_counts",matrix(seq_len(12),3,dimnames=list(paste0("p",1:3),ids)),feature_type="peak")
  old <- wb_op_peakvi_project
  op_env <- environment(.wb_runner_peakvi_project)
  unlockBinding("wb_op_peakvi_project", op_env)
  assign("wb_op_peakvi_project", function(bundle, peakvi_model, matrix_id, cells, batch_key=NULL, use_gpu=FALSE, space_id_out="peakvi_project_space", ...) {
    wb_add_space(bundle,space_id_out,matrix(seq_len(length(cells)*2),length(cells),2,dimnames=list(cells,c("z1","z2"))),source="mock")
    list(outputs=list(space=wb_prim_space(space_id_out)),params=list(matrix_id=matrix_id,n_cells=length(cells),n_features=3L,model_space_id="peakvi_model",space_id_out=space_id_out,use_gpu=use_gpu,pybench_runtime=list(protocol_version="1",pybench_version="mock",timings=list(total=0))))
  },envir=op_env)
  on.exit({assign("wb_op_peakvi_project",old,envir=op_env); lockBinding("wb_op_peakvi_project", op_env)},add=TRUE)
  model <- wb_prim_model_ref("peakvi_model","peakvi_model",engine="peakvi"); model$model_path <- tempfile(); dir.create(model$model_path)
  # exercise runner contract with the bounded bridge mock
  raw <- .wb_runner_peakvi_project(b,list(matrix=wb_prim_matrix("ATAC_counts"),model=model),ids,list(batch_key="batch",use_gpu=FALSE,space_id_out="projected"))
  stopifnot(all(c("space","fit_summary") %in% names(raw$outputs)), all(c("matrix_id","model_space_id","output_space_id","n_cells","n_features","batch_key","use_gpu","pybench_protocol_version","pybench_version","pybench_timings_json") %in% names(raw$outputs$fit_summary$table)))
  TRUE
}
