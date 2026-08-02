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
  policy <- setNames(plan$terminal_outputs$replay_equivalence_policy, plan$terminal_outputs$output_name)
  stopifnot(identical(plan$status,"ok"), identical(plan$run_order, res$run$run_id), all(c("model","space_2d") %in% plan$terminal_outputs$output_name), all(plan$terminal_outputs$verification_level == "content"), identical(policy[["model"]], "loadable_reference"), identical(policy[["space_2d"]], "exact_canonical_value"))
  stopifnot(identical(plan$run_order, wb_target_reproduction_plan(b, paste0("run:", res$run$run_id))$run_order))
  model_id <- paste("uwot", "umap_target", "pca_source", sep="|")
  stopifnot(identical(wb_target_reproduction_plan(b, paste0("model:",model_id))$status,"ok"))
  script <- wb_target_emit_r_script(plan)
  stopifnot(length(script)==1L, grepl("wb_session_promote_current",script,fixed=TRUE), grepl("writable ingestion-ready",script,fixed=TRUE))
  stopifnot(nrow(promoted$promoted) >= 2L,
            !"wb_target_reproduction_branch_template" %in% getNamespaceExports("scworkbench"))
  TRUE
}

# Executable cross-snapshot closure: durable string/entity inputs must pull
# their producing runs into the plan, then replay into a source-only clone.
test_targeted_reproduction_execute_contract <- function() {
  if (!requireNamespace("BPCells", quietly=TRUE) || !requireNamespace("irlba", quietly=TRUE) || !requireNamespace("uwot", quietly=TRUE)) return(TRUE)
  root <- tempfile("scwb_target_execute_")
  cleanup <- character(0)
  b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE); if (length(cleanup)) unlink(cleanup,recursive=TRUE,force=TRUE); unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  cells <- paste0("cell_",letters[1:12]); wb_define_cells(b,cells)
  mat <- Matrix::Matrix(matrix(rep(c(10,1,0,8,2,6),each=12),nrow=6,dimnames=list(paste0("g",1:6),cells)),sparse=TRUE)
  wb_attach_matrix(b,"RNA_counts",mat,feature_type="gene")
  copy_bundle <- function(source, label) {
    parent <- tempfile(paste0("scwb_", label, "_")); dir.create(parent)
    stopifnot(isTRUE(file.copy(source, parent, recursive=TRUE)))
    cleanup <<- c(cleanup, parent)
    file.path(parent, basename(source))
  }
  run_emitted <- function(script) {
    path <- tempfile(fileext=".R"); wrapper <- tempfile(fileext=".R")
    writeLines(script,path)
    writeLines(c("options(error = function() { traceback(2); q(status = 1) })", paste0("devtools::load_all('",normalizePath(getwd(),winslash="/"),"', quiet=TRUE)"),paste0("source('",path,"')")),wrapper)
    out <- suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),wrapper,stdout=TRUE,stderr=TRUE))
    list(status=as.integer(attr(out,"status") %||% 0L), output=out)
  }
  # Copy only a checkpointed immutable/source boundary; copying SQLite while
  # its writer is open can omit WAL frames and is not a valid execution clone.
  wb_close_bundle(b)
  clone <- copy_bundle(root, "target_clone")
  b <- wb_open_bundle(root)
  n <- wb_session_run_op(wb_session_new(),b,"matrix_log_normalize",inputs=list(matrix="RNA_counts",cell_set="all",min_cells=1L,output_matrix_id="RNA_log_norm",overwrite=FALSE))
  wb_session_promote_current(b,n$session,outputs="summary")
  wb_close_bundle(b); b <- wb_open_bundle(root)
  h <- wb_session_run_op(wb_session_new(),b,"hvg_select",inputs=list(matrix="RNA_log_norm",cell_set="all",min_cells=1L,n_features=4L,method="vst",chunk_size=2L))
  ph <- wb_session_promote_current(b,h$session,outputs="selected_features"); aid <- as.character(ph$promoted$artifact_id[ph$promoted$output=="selected_features"][1])
  wb_close_bundle(b); b <- wb_open_bundle(root)
  p <- wb_session_run_op(wb_session_new(),b,"pca_fit",inputs=list(matrix="RNA_log_norm",features=wb_ref_artifact(aid,"selected_features"),cell_set="all",min_cells=1L,n_components=2L,center=TRUE,scale=TRUE,backend="irlba",seed=1L,space_id_out="rna_pca",overwrite=FALSE,max_dense_gb=1))
  pp <- wb_session_promote_current(b,p$session,outputs=c("loadings","variance","fit_summary"))
  wb_close_bundle(b); b <- wb_open_bundle(root)
  u <- wb_session_run_op(wb_session_new(),b,"umap_fit",inputs=list(space="rna_pca",cell_set="all",min_cells=1L,dims=1:2,space_id_out="rna_umap",n_neighbors=3L,min_dist=.1,metric="euclidean",nn_method="annoy",seed=1L))
  wb_session_promote_current(b,u$session,outputs=c("model","space_2d"))
  plan <- wb_target_reproduction_plan(b,"space:rna_umap")
  run_ids <- c(n$run$run_id,h$run$run_id,p$run$run_id,u$run$run_id)
  snapshots <- DBI::dbGetQuery(b$con,paste0("SELECT DISTINCT run_id, snapshot_id FROM prov_runs WHERE run_id IN (",paste(rep("?",4),collapse=","),")"),params=as.list(run_ids))
  stopifnot(nrow(snapshots)==4L,length(unique(snapshots$snapshot_id))==4L,identical(plan$run_order,run_ids))
  mid <- paste("uwot","rna_umap","rna_pca",sep="|")
  required_nodes <- c("matrix:RNA_counts","matrix:RNA_log_norm",paste0("artifact:",aid),"space:rna_pca","space:rna_umap",paste0("model_ref:",mid),paste0("run:",run_ids))
  stopifnot(identical(plan$status,"ok"),all(required_nodes %in% plan$subgraph$nodes$id),nrow(plan$excluded_siblings)==0L)
  has_edge <- function(from,to,type) any(plan$subgraph$edges$from==from & plan$subgraph$edges$to==to & plan$subgraph$edges$edge_type==type)
  stopifnot(
    has_edge("matrix:RNA_counts",paste0("run:",n$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",n$run$run_id),"matrix:RNA_log_norm","MATERIALIZES"),
    has_edge("matrix:RNA_log_norm",paste0("run:",h$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",h$run$run_id),paste0("artifact:",aid),"PRODUCES"),
    has_edge(paste0("artifact:",aid),paste0("run:",p$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",p$run$run_id),"space:rna_pca","MATERIALIZES"),
    has_edge("space:rna_pca",paste0("run:",u$run$run_id),"CONSUMES"),
    has_edge(paste0("run:",u$run$run_id),"space:rna_umap","MATERIALIZES"),
    has_edge(paste0("run:",u$run$run_id),paste0("model_ref:",mid),"MATERIALIZES")
  )
  artifact_plan <- wb_target_reproduction_plan(b,paste0("artifact:",aid))
  matrix_plan <- wb_target_reproduction_plan(b,"matrix:RNA_log_norm")
  pca_plan <- wb_target_reproduction_plan(b,"space:rna_pca")
  model_plan <- wb_target_reproduction_plan(b,paste0("model:",mid))
  run_plan <- wb_target_reproduction_plan(b,paste0("run:",u$run$run_id))
  target_plans <- list(artifact=artifact_plan,matrix=matrix_plan,space=pca_plan,model=model_plan,run=run_plan)
  target_status <- vapply(target_plans,function(x) as.character(x$status),character(1))
  if (!all(target_status=="ok")) stop(paste(names(target_status),target_status,collapse="; "))
  stopifnot(identical(model_plan$run_order,run_ids),identical(run_plan$run_order,run_ids))
  policy <- setNames(plan$terminal_outputs$replay_equivalence_policy,plan$terminal_outputs$output_name)
  stopifnot(identical(policy[["space_2d"]],"exact_canonical_value"),identical(policy[["model"]],"loadable_reference"))
  source_umap <- wb_space(b,"rna_umap")

  # Every preflight rejection executes the real emitted script and must fail
  # before any analytical replay begins.
  source_reject <- run_emitted(wb_target_emit_r_script(plan,root))
  nonexistent <- tempfile("scwb_target_missing_destination_")
  nonexistent_reject <- run_emitted(wb_target_emit_r_script(plan,nonexistent))
  missing_boundary <- tempfile("scwb_target_missing_boundary_"); cleanup <- c(cleanup,missing_boundary)
  mb <- wb_init_bundle(missing_boundary,overwrite=TRUE); wb_define_cells(mb,cells); wb_close_bundle(mb)
  boundary_reject <- run_emitted(wb_target_emit_r_script(plan,missing_boundary))
  wb_close_bundle(b); collision <- copy_bundle(root,"target_collision"); b <- wb_open_bundle(root)
  collision_reject <- run_emitted(wb_target_emit_r_script(plan,collision))
  stopifnot(source_reject$status!=0L,grepl("Refusing to mutate",paste(source_reject$output,collapse="\n")),nonexistent_reject$status!=0L,grepl("existing writable",paste(nonexistent_reject$output,collapse="\n")),boundary_reject$status!=0L,grepl("Missing immutable boundary",paste(boundary_reject$output,collapse="\n")),collision_reject$status!=0L,grepl("Durable output collision",paste(collision_reject$output,collapse="\n")))

  success <- run_emitted(wb_target_emit_r_script(plan,clone))
  if (success$status!=0L) stop(paste(success$output,collapse="\n"))
  cb <- wb_open_bundle(clone); on.exit(try(wb_close_bundle(cb),silent=TRUE),add=TRUE)
  eq <- wb_prov_replay_equivalence_results(cb)
  eq_policy <- setNames(eq$replay_equivalence_policy,eq$original_output_name)
  stopifnot(isTRUE(wb_validate_bundle(clone)),"rna_umap" %in% wb_spaces(cb)$space_id,identical(wb_space(cb,"rna_umap"),source_umap),nrow(eq)==2L,all(eq$equivalence_verified==1L),identical(eq_policy[["space_2d"]],"exact_canonical_value"),identical(eq_policy[["model"]],"loadable_reference"),eq$payload_identical[eq$original_output_name=="space_2d"]==1L,all(grepl("^[0-9a-f]{64}$",eq$original_content_sha256)),all(grepl("^[0-9a-f]{64}$",eq$replayed_content_sha256)),!is.null(wb_load_space_model(cb,"rna_umap")))
  model_art <- eq$replay_artifact_id[eq$original_output_name=="model"]
  model_link <- wb_art_birth_certificate(cb,model_art)$persisted_provenance$links
  stopifnot(identical(as.character(model_link$verification_status[model_link$output_name=="model"]),"content_verified"))
  bad_path <- tempfile("unloadable_uwot_",tmpdir=clone,fileext=".uwot"); saveRDS(list(not_a_uwot_model=TRUE),bad_path)
  bad_model <- wb_prim_model_ref("rna_umap","rna_pca",engine="uwot"); bad_model$model_path <- bad_path
  bad_identity <- scworkbench:::.wb_prov_payload_identity(cb,bad_model)
  bad_verification <- try(scworkbench:::.wb_prov_verify_replay_output(
    cb,"original_bad_model","model","model_ref",bad_identity$content_sha256,
    "loadable_reference",scworkbench:::.wb_replay_model_reference(bad_model),bad_model,
    "replay_bad_model",eq$replay_snapshot_id[1],NA_character_
  ),silent=TRUE)
  failed_result <- wb_prov_replay_equivalence_results(cb,eq$replay_snapshot_id[1])
  stopifnot(inherits(bad_verification,"try-error"),any(failed_result$verification_status=="failed"))

  # A second producer for the same durable entity is rejected structurally and
  # cannot be emitted. This deliberately models a malformed/legacy bundle.
  wb_close_bundle(b); b <- NULL
  amb <- copy_bundle(root,"target_ambiguous"); ab <- wb_open_bundle(amb); on.exit(try(wb_close_bundle(ab),silent=TRUE),add=TRUE)
  sid <- as.character(plan$terminal_outputs$snapshot_id[plan$terminal_outputs$output_name=="space_2d"])[1]
  dup_run <- paste0(u$run$run_id,"_duplicate")
  DBI::dbExecute(ab$con,"INSERT INTO prov_runs SELECT snapshot_id, ?, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash, op_version, runtime_fingerprint_json, contract_json, contract_hash FROM prov_runs WHERE snapshot_id=? AND run_id=?",params=list(dup_run,sid,u$run$run_id))
  DBI::dbExecute(ab$con,"INSERT INTO prov_run_outputs SELECT snapshot_id, ?, output_name, primitive_kind, output_hash, artifact_id, materialization_class, materialization_path, structural_fingerprint, content_sha256, verification_level, verification_status, replay_equivalence_policy, replay_equivalence_reference, replay_equivalence_status FROM prov_run_outputs WHERE snapshot_id=? AND run_id=? AND output_name='space_2d'",params=list(dup_run,sid,u$run$run_id))
  DBI::dbExecute(ab$con,"INSERT INTO prov_run_entity_bindings SELECT snapshot_id, commit_id, ?, direction, binding_name, entity_kind, entity_id, relationship_type, path, content_hash, source FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? AND direction='output' AND entity_kind='space'",params=list(dup_run,sid,u$run$run_id))
  ambiguous <- wb_target_reproduction_plan(ab,"space:rna_umap")
  stopifnot(identical(ambiguous$status,"ambiguous"),!isTRUE(ambiguous$reproducible),nrow(ambiguous$candidates)>=2L,inherits(try(wb_target_emit_r_script(ambiguous,clone),silent=TRUE),"try-error"))
  TRUE
}
