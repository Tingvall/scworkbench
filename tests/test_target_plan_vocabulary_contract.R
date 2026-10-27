test_target_plan_structure_eligibility_and_verified_execution_contract <- function() {
  root <- tempfile("target_vocabulary_");clone<-tempfile("target_vocabulary_clone_")
  b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(c(root,clone),recursive=TRUE)},add=TRUE)
  wb_define_cells(b,c("a","b"),metadata=data.frame(cell_id=c("a","b"),group=c("A","B")))
  stopifnot(wb_finalize_recipient_bundle(b)$ready);wb_close_bundle(b)
  fs::dir_copy(root,clone);b<-wb_open_bundle(root)
  result<-wb_session_run_op(wb_session_new(),b,"metadata_cell_vector",inputs=list(
    source_column="group",vector_name="group",value_type="categorical",
    missing_policy="error",cell_set="all",min_cells=1L,overwrite=FALSE))
  on.exit(wb_session_discard(result$session),add=TRUE)
  promoted<-wb_session_promote_current(b,result$session,outputs="vector")
  id<-promoted$promoted$artifact_id[[1L]];target<-paste0("artifact:",id)
  before<-DBI::dbGetQuery(b$con,"SELECT COUNT(*) n FROM prov_runs")$n
  plan<-wb_target_reproduction_plan(b,target)
  stopifnot(identical(plan$status,"ok"),isTRUE(plan$reproducible),
    !"verification" %in% names(plan),
    DBI::dbGetQuery(b$con,"SELECT COUNT(*) n FROM prov_runs")$n==before,
    is.character(wb_target_emit_r_script(plan,clone)))
  # Only execution and comparison produce passing replay receipts.
  wb_close_bundle(b);b<-NULL
  replay<-wb_target_execute_plan(plan,clone)
  stopifnot(identical(replay$status,"promoted_and_verified"),nrow(replay$verification)==1L,
    all(replay$verification$equivalence_verified==1L),
    all(replay$verification$verification_status=="verified"))
  original<-wb_open_bundle(root,read_only=TRUE);actual<-wb_open_bundle(clone,read_only=TRUE)
  stopifnot(identical(wb_art_load(original,id)$value,
    wb_art_load(actual,replay$promotion$promoted$artifact_id[[1L]])$value))
  wb_close_bundle(original);wb_close_bundle(actual)
  # Controlled legacy-policy fixture: structure remains acyclic but static
  # admission refuses it. This mutates only this disposable test bundle.
  b<-wb_open_bundle(root)
  DBI::dbExecute(b$con,"UPDATE prov_run_outputs SET replay_equivalence_policy='not_comparable' WHERE artifact_id=?",params=list(id))
  legacy<-wb_target_reproduction_plan(b,target)
  codes<-vapply(legacy$diagnostics,`[[`,"","code")
  stopifnot(identical(legacy$status,"ok"),isTRUE(legacy$reproducible),
    "legacy_not_comparable" %in% codes)
  rejection<-try(wb_target_emit_r_script(legacy,clone),silent=TRUE)
  stopifnot(inherits(rejection,"try-error"),grepl("supported replay-equivalence policy",rejection,fixed=TRUE))
  # A persisted cycle must return its structural diagnostic, not attempt an
  # operation lookup from a run omitted by the topological order.
  DBI::dbExecute(b$con,"INSERT INTO prov_run_edges(snapshot_id,parent_run_id,child_run_id,edge_type,edge_label) VALUES(?,?,?,?,?)",
    params=list(promoted$provenance_snapshot_id,result$run$run_id,result$run$run_id,"depends_on_run","cycle fixture"))
  cyclic<-wb_target_reproduction_plan(b,target)
  stopifnot(identical(cyclic$status,"cyclic"),!cyclic$reproducible,
    "cyclic" %in% vapply(cyclic$diagnostics,`[[`,"","code"),
    inherits(try(wb_target_emit_r_script(cyclic,clone),silent=TRUE),"try-error"))
  TRUE
}
