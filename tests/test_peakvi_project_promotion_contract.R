test_peakvi_project_promotion_contract <- function() {
  # Bounded mock: pybench execution is replaced, while the registered runner,
  # session, staging overlay, and promotion machinery remain real.
  if (!requireNamespace("BPCells", quietly = TRUE)) return(contract_test_skip("BPCells is not installed."))
  root <- tempfile("scwb_peakvi_project_"); b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  ids <- paste0("cell_",letters[1:4]); wb_define_cells(b,ids)
  wb_attach_matrix(b,"ATAC_counts",matrix(seq_len(12),3,dimnames=list(paste0("p",1:3),ids)),feature_type="peak")
  wb_attach_space(
    b, "peakvi_model",
    data.frame(
      cell_id = ids,
      z1 = seq_along(ids),
      z2 = rev(seq_along(ids)),
      stringsAsFactors = FALSE
    ),
    source = "retained fitted-model fixture"
  )
  op_env <- environment(wb_op_peakvi_project); old <- .wb_pybench_bridge_run_or_stop
  captured_requests <- list()
  unlockBinding(".wb_pybench_bridge_run_or_stop", op_env)
  assign(".wb_pybench_bridge_run_or_stop", function(module, request, ...) {
    captured_requests[[length(captured_requests) + 1L]] <<- request
    sb <- wb_open_bundle(request$bundle_dir); on.exit(wb_close_bundle(sb),add=TRUE)
    cells <- as.character(request$inputs$cell_ids); sid <- as.character(request$params$space_id_out)
    wb_add_space(sb,sid,matrix(seq_len(length(cells)*2),length(cells),2,dimnames=list(cells,c("z1","z2"))),source="mock")
    list(receipt=list(status="ok",protocol_version="1",pybench=list(version="mock"),timings=list(total=0)))
  },envir=op_env)
  on.exit({assign(".wb_pybench_bridge_run_or_stop",old,envir=op_env); lockBinding(".wb_pybench_bridge_run_or_stop",op_env)},add=TRUE)
  model_dir <- file.path(root, "artifact_models", "peakvi_contract")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("contained PeakVI fixture", file.path(model_dir, "model.txt"))
  model <- wb_prim_model_ref("peakvi_model","peakvi_model",engine="peakvi")
  model$model_path <- normalizePath(model_dir, winslash = "/", mustWork = TRUE)
  rr <- wb_session_run_op(wb_session_new(),b,"peakvi_project",inputs=list(matrix="ATAC_counts",model=model,cell_set="all",min_cells=1L,batch_key="batch",space_id_out="projected"))
  stopifnot(length(captured_requests) == 1L,
            identical(captured_requests[[1]]$inputs$model_path, "artifact_models/peakvi_contract"),
            !.wb_path_is_absolute(captured_requests[[1]]$inputs$model_path),
            !startsWith(captured_requests[[1]]$inputs$model_path,
                        normalizePath(root, winslash = "/", mustWork = TRUE)))
  stopifnot(all(c("space","fit_summary") %in% names(rr$run$outputs)), "projected" %in% wb_spaces(wb_session_view(rr$session))$space_id,
            identical(rr$run$inputs$coverage$per_input$matrix$available_n, length(ids)),
            identical(rr$run$inputs$coverage$per_input$model$coverage_mode, "reference_only"),
            identical(rr$run$inputs$coverage$effective_n, length(ids)))
  p <- wb_session_promote_current(b,rr$session,outputs="fit_summary")
  wb_close_bundle(b); b <- wb_open_bundle(root)
  projected <- wb_space(b, "projected", cells = ids)
  wb_finalize_recipient_bundle(b)
  stopifnot("projected" %in% wb_spaces(b)$space_id,
            identical(as.character(projected$cell_id), ids),
            identical(rownames(projected), ids),
            nrow(p$promoted[p$promoted$output=="fit_summary",])==1L,
            isTRUE(wb_validate_bundle(root)))
  failed <- wb_session_run_op(wb_session_new(),b,"peakvi_project",inputs=list(matrix="ATAC_counts",model=model,cell_set="all",min_cells=1L,space_id_out="rollback_projected"))
  before_heads <- nrow(wb_prov_list_heads(b)); before_peak_artifacts <- sum(wb_art_list(b)$source_op=="peakvi_project"); old_hook <- getOption("scworkbench.promotion_workspace_publish_hook"); on.exit(options(scworkbench.promotion_workspace_publish_hook=old_hook),add=TRUE)
  options(scworkbench.promotion_workspace_publish_hook=function(...) stop("forced",call.=FALSE))
  bad <- try(wb_session_promote_current(b,failed$session,outputs="fit_summary"),silent=TRUE); options(scworkbench.promotion_workspace_publish_hook=old_hook)
  bind_n <- DBI::dbGetQuery(b$con,"SELECT COUNT(*) n FROM prov_run_entity_bindings WHERE run_id=?;",params=list(failed$run$run_id))$n[1]
  mat_n <- DBI::dbGetQuery(b$con,"SELECT COUNT(*) n FROM prov_materializations WHERE run_id=?;",params=list(failed$run$run_id))$n[1]
  stopifnot(inherits(bad,"try-error"), !"rollback_projected" %in% wb_spaces(b)$space_id, nrow(wb_prov_list_heads(b))==before_heads, bind_n==0L, mat_n==0L, sum(wb_art_list(b)$source_op=="peakvi_project")==before_peak_artifacts, isTRUE(wb_validate_bundle(root)))
  TRUE
}
