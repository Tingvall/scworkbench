.capsule_fixture <- function() {
  root <- tempfile("scwb_capsule_"); b <- wb_init_bundle(root,overwrite=TRUE)
  cells <- paste0("c",1:8); genes <- paste0("g",1:6)
  defined <- wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,capsule_group=rep(c("A","B"),4),stringsAsFactors=FALSE))
  metadata_field_id <- defined$metadata_fields$field_id[defined$metadata_fields$source_name=="capsule_group"][[1L]]
  mat <- Matrix::Matrix(matrix(as.integer(1:48 %% 11),nrow=6,dimnames=list(genes,cells)),sparse=TRUE)
  wb_attach_matrix(b,"counts",mat)
  wb_attach_space(b,"pca",data.frame(cell_id=cells,x=seq_along(cells),y=rev(seq_along(cells))))
  wb_attach_space(b,"scvi",data.frame(cell_id=cells,x=seq_along(cells)+0.25,y=rev(seq_along(cells))+0.5))
  wb_attach_space(b,"custom",data.frame(cell_id=cells,x=seq_along(cells)*2,y=rev(seq_along(cells))*2))
  wb_attach_space(b,"umap",data.frame(cell_id=cells,x=seq_along(cells)*3,y=rev(seq_along(cells))*3))
  source_identity <- list(schema="scworkbench.source_identity.v2",inputs=list(list(scope="public_file",source_id="fixture_counts",path="fixture_counts.mtx.gz",uri="https://example.invalid/fixture",accession="fixture",role="counts",format="mtx",sha256=paste(rep("a",64),collapse=""),bundled=FALSE)))
  scworkbench:::.wb_ingest_report_artifact(b,"core","atomic",list(n_cells=length(cells)),list(),list(),created_by="capsule-test",source="capsule-test",matrix_ids="counts",source_identity=source_identity)
  model <- wb_prim_model_ref("pca","pca",engine="test"); model$model_type <- "test"; model$model_obj <- list(version=1L)
  run <- wb_new_run("slingshot_adopt",inputs=list(cell_set="all"),outputs=list(model=model))
  promoted <- wb_promote_analysis(b,setNames(list(run),run$run_id),run$run_id,name_prefix="capsule fixture",fail_fast=TRUE)
  artifact_id <- promoted$promoted$artifact_id[[1L]]
  vector_run <- wb_session_run_op(wb_session_new(),b,"metadata_cell_vector",inputs=list(source_column="capsule_group",vector_name="capsule_group",value_type="categorical",missing_policy="error",cell_set="all",min_cells=1L))
  vector_promoted <- wb_session_promote_current(b,vector_run$session,outputs=list(wb_ref_run(vector_run$run$run_id,"vector")))
  vector_id <- vector_promoted$promoted$artifact_id[vector_promoted$promoted$status=="ok"][[1L]]
  list(root=root,bundle=b,cells=cells,model_id=artifact_id,artifact_id=artifact_id,vector_id=vector_id,metadata_field_id=metadata_field_id,source_id="fixture_counts")
}

.capsule_register_fixture <- function(f, name="representation comparison", relationships=list(), inputs_override=NULL,
                                      parameters=list(panel_order=c("pca","custom"),subtitle=NULL),
                                      catalog_decision="retain_as_capsule") {
  work <- tempfile("capsule_external_");dir.create(work)
  script <- file.path(work,"compare.R");writeLines(c("# paper-specific three-panel comparison","metrics <- data.frame(label = 'custom')"),script)
  csv<-file.path(work,"metrics.csv");writeLines(c("metric,value","agreement,0.9"),csv)
  md<-file.path(work,"report.md");writeLines("# External terminal report",md)
  png<-file.path(work,"figure.png");writeBin(as.raw(c(137,80,78,71,1:16)),png)
  capsule_inputs <- if (is.null(inputs_override)) list(matrix=wb_ref_entity("matrix","counts"),pca=wb_ref_entity("space","pca"),scvi=wb_ref_entity("space","scvi"),custom=wb_ref_entity("space","custom"),umap=wb_ref_entity("space","umap"),metadata_vector=wb_ref_entity("artifact",f$vector_id),artifact=wb_ref_entity("artifact",f$artifact_id),model=wb_ref_entity("model",f$model_id),metadata=wb_ref_metadata_field(f$metadata_field_id),source=wb_ref_entity("external_source",f$source_id)) else inputs_override
  cap <- wb_capsule_register(f$bundle,name,
    inputs=capsule_inputs,
    script=script,outputs=list(metrics=list(path=csv,role="metrics_table",media_type="text/csv",structural_metadata=list(columns=2L)),figure=list(path=png,role="figure",media_type="image/png"),report=list(path=md,role="report",media_type="text/markdown")),
    parameters=parameters,command=c("Rscript","compare.R"),runtime=list(r_version="declared"),executed_at="2026-08-17T12:00:00Z",created_by="researcher",purpose="custom_visualization",rationale="paper-specific terminal layout not represented by a scientific operation",catalog_review=list(catalog_identity="scworkbench.operation_catalog",catalog_version="0.1.0",reviewed_at="2026-08-17T11:00:00Z",candidate_op_names=list(),decision=catalog_decision),family_hint="representation-comparison",relationships=relationships)
  list(capsule=cap,work=work,script=script,outputs=c(csv=csv,png=png,md=md))
}

test_analysis_capsule_registration_contract <- function() {
  required<-c("BPCells","Matrix","rhdf5");missing<-required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)];if(length(missing))return(contract_test_skip(paste("Missing runtime dependencies:",paste(missing,collapse=", "))))
  f<-.capsule_fixture();on.exit({try(wb_close_bundle(f$bundle),silent=TRUE);unlink(f$root,recursive=TRUE,force=TRUE)},add=TRUE)
  before_seed<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv) else NULL
  reg<-.capsule_register_fixture(f);cap<-reg$capsule
  after_seed<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv) else NULL
  stopifnot(identical(before_seed,after_seed),nrow(wb_capsules(f$bundle))==1L,identical(wb_capsule(f$bundle,cap$capsule_id)$capsule_id,cap$capsule_id))
  ins<-wb_capsule_inputs(f$bundle,cap$capsule_id);outs<-wb_capsule_outputs(f$bundle,cap$capsule_id)
  stopifnot(identical(ins$entity_kind,c("matrix","space","space","space","space","artifact","artifact","model","metadata_field","external_source")),all(grepl("^[0-9a-f]{64}$",ins$content_sha256)),identical(outs$output_name,c("metrics","figure","report")),all(grepl("^[0-9a-f]{64}$",outs$content_sha256)))
  stopifnot(identical(readBin(wb_capsule_script_path(f$bundle,cap$capsule_id),"raw",n=file.info(reg$script)$size),readBin(reg$script,"raw",n=file.info(reg$script)$size)))
  for(nm in outs$output_name)stopifnot(file.exists(wb_capsule_output_path(f$bundle,cap$capsule_id,nm)))
  dag<-wb_prov_bundle_dag(f$bundle);cid<-paste0("capsule:",cap$capsule_id)
  stopifnot(cid%in%dag$nodes$id,all(paste0(ins$entity_kind,":",ins$entity_id)%in%dag$nodes$id),all(paste0("capsule_output:",outs$output_id)%in%dag$nodes$id),!anyDuplicated(dag$nodes$id),!anyDuplicated(dag$edges$semantic_key))
  for(input in paste0(ins$entity_kind,":",ins$entity_id))for(output in paste0("capsule_output:",outs$output_id))stopifnot(output%in%scworkbench:::.wb_certificate_reachable(dag$edges,input,FALSE))
  cc<-wb_entity_certificate(f$bundle,"capsule",cap$capsule_id);oc<-wb_entity_certificate(f$bundle,"capsule_output",outs$output_id[[1L]])
  stopifnot(cc$details$assurance_level=="content_registered",cc$details$replay_status=="not_verified",oc$producer$capsule_id==cap$capsule_id)
  kg<-wb_kg_provenance_graph(f$bundle);stopifnot(cid%in%kg$nodes$id,all(paste0("capsule_output:",outs$output_id)%in%kg$nodes$id),!anyDuplicated(kg$edges$id),!any(grepl(normalizePath(dirname(f$root),winslash="/",mustWork=TRUE),kg$nodes$payload_json,fixed=TRUE)))
  stopifnot(cap$execution_mode=="externally_executed",cap$assurance_level=="content_registered",cap$replay_status=="not_verified",cap$catalog_review$decision=="retain_as_capsule",grepl("^scworkbench.analysis_capsule",cap$input_shape_signature))
  TRUE
}
