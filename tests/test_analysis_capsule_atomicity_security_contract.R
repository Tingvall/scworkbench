.capsule_helper_env <- new.env(parent=environment())
.capsule_helper_file <- {
  source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = "")
  candidates <- c(
    if (nzchar(source_root)) file.path(source_root, "tests", "test_analysis_capsule_registration_contract.R"),
    file.path("tests", "test_analysis_capsule_registration_contract.R"),
    "test_analysis_capsule_registration_contract.R"
  )
  candidates[file.exists(candidates)][[1L]]
}
sys.source(.capsule_helper_file, envir=.capsule_helper_env)
.capsule_fixture <- .capsule_helper_env$.capsule_fixture
.capsule_register_fixture <- .capsule_helper_env$.capsule_register_fixture

test_analysis_capsule_atomicity_security_contract <- function() {
  required<-c("BPCells","Matrix","rhdf5");missing<-required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)];if(length(missing))return(contract_test_skip(paste("Missing runtime dependencies:",paste(missing,collapse=", "))))
  f<-.capsule_fixture();on.exit({try(wb_close_bundle(f$bundle),silent=TRUE);unlink(f$root,recursive=TRUE,force=TRUE)},add=TRUE)
  boundaries<-c("before_payload_publication","during_multifile_publication","before_sqlite_commit")
  for(boundary in boundaries){
    # Lexical hook avoids coupling to implementation stack frames.
    options(scworkbench.analysis_capsule_fault_hook=local({wanted<-boundary;function(boundary,...){if(identical(boundary,wanted))stop("injected")}}))
    failed<-try(.capsule_register_fixture(f,name=paste0("fault-",boundary)),silent=TRUE);options(scworkbench.analysis_capsule_fault_hook=NULL)
    stopifnot(inherits(failed,"try-error"),nrow(wb_capsules(f$bundle))==0L,!dir.exists(file.path(f$root,"analysis","capsules"))||!length(list.files(file.path(f$root,"analysis","capsules"),all.files=TRUE,no..=TRUE)))
  }
  options(scworkbench.analysis_capsule_fault_hook=function(boundary,...){if(boundary=="commit_point")stop("post-commit injected")})
  post<-try(.capsule_register_fixture(f,name="commit-point"),silent=TRUE);options(scworkbench.analysis_capsule_fault_hook=NULL)
  stopifnot(inherits(post,"try-error"),nrow(wb_capsules(f$bundle))==1L)
  committed<-wb_capsules(f$bundle)$capsule_id[[1L]];stopifnot(file.exists(wb_capsule_script_path(f$bundle,committed)),wb_manifest(f$bundle)$counts$n_analysis_capsules==1L)

  # Safe retry after every pre-commit fault and immutable distinct identifiers.
  second_reg<-.capsule_register_fixture(f,name="retry-success");second<-second_reg$capsule
  stopifnot(second$capsule_id!=committed,length(unique(wb_capsule_outputs(f$bundle,second$capsule_id)$output_id))==3L)

  # Invalid entity state and malformed/unsupported public references fail
  # before either registry or payload publication.
  before_invalid<-nrow(wb_capsules(f$bundle))
  missing<-try(.capsule_register_fixture(f,name="missing-input",inputs_override=list(space=wb_ref_entity("space","absent"))),silent=TRUE)
  malformed<-try(.capsule_register_fixture(f,name="ambiguous-input",inputs_override=list(space=list(ref_type="bundle_entity",entity_kind="space",entity_id="pca",extra="ambiguous"))),silent=TRUE)
  unsupported<-try(wb_ref_entity("cell_set","all"),silent=TRUE)
  DBI::dbExecute(f$bundle$con,"UPDATE entity_lifecycle SET lifecycle_state='superseded' WHERE entity_kind='space' AND entity_id='pca';")
  tombstoned<-try(.capsule_register_fixture(f,name="historical-input",inputs_override=list(space=wb_ref_entity("space","pca"))),silent=TRUE)
  DBI::dbExecute(f$bundle$con,"UPDATE entity_lifecycle SET lifecycle_state='current' WHERE entity_kind='space' AND entity_id='pca';")
  stopifnot(all(vapply(list(missing,malformed,unsupported,tombstoned),inherits,logical(1),what="try-error")),nrow(wb_capsules(f$bundle))==before_invalid)

  register_direct<-function(name,script=second_reg$script,outputs=list(report=list(path=second_reg$outputs[["md"]],role="report",media_type="text/markdown"))){
    wb_capsule_register(f$bundle,name,inputs=list(space=wb_ref_entity("space","pca")),script=script,outputs=outputs,purpose="custom_terminal_summary",rationale="security contract terminal evidence",catalog_review=list(catalog_identity="scworkbench.operation_catalog",catalog_version="0.1.0",reviewed_at="2026-08-17T11:00:00Z",decision="retain_as_capsule"))
  }
  duplicate_outputs<-list(a=list(path=second_reg$outputs[["csv"]]),b=list(path=second_reg$outputs[["md"]]));names(duplicate_outputs)<-c("duplicate","duplicate")
  traversal_outputs<-list(list(path=second_reg$outputs[["md"]],role="report"));names(traversal_outputs)<-"../escape"
  bundle_source<-try(register_direct("bundle-source",script=wb_capsule_script_path(f$bundle,second$capsule_id)),silent=TRUE)
  duplicate<-try(register_direct("duplicate-output",outputs=duplicate_outputs),silent=TRUE)
  traversal<-try(register_direct("traversal-output",outputs=traversal_outputs),silent=TRUE)
  stopifnot(all(vapply(list(bundle_source,duplicate,traversal),inherits,logical(1),what="try-error")),nrow(wb_capsules(f$bundle))==before_invalid)

  same_dir<-tempfile("capsule_same_size_");dir.create(same_dir);a<-file.path(same_dir,"a.bin");b<-file.path(same_dir,"b.bin");writeBin(as.raw(1:16),a);writeBin(as.raw(16:1),b)
  exact<-register_direct("same-size-distinct-bytes",outputs=list(a=list(path=a),b=list(path=b)))
  exact_rows<-wb_capsule_outputs(f$bundle,exact$capsule_id)
  stopifnot(length(unique(exact_rows$size_bytes))==1L,length(unique(exact_rows$content_sha256))==2L,all(grepl("^[0-9a-f]{64}$",exact_rows$content_sha256)))
  # A separate process owns the exclusive writer lock; registration follows
  # the ordinary timeout contract and publishes nothing.
  wb_close_bundle(f$bundle);f$bundle<-wb_open_bundle(f$root)
  lock_dir<-tempfile("capsule_lock_");dir.create(lock_dir);ready<-file.path(lock_dir,"ready");release<-file.path(lock_dir,"release");child<-file.path(lock_dir,"hold.R")
  literal<-function(x)paste(deparse(as.character(x)),collapse="")
  source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = "")
  if (!nzchar(source_root) && file.exists("DESCRIPTION") && dir.exists("R")) source_root <- normalizePath(".", winslash="/", mustWork=TRUE)
  bootstrap <- if (nzchar(source_root)) sprintf("devtools::load_all(%s, quiet=TRUE)", literal(source_root)) else c(sprintf(".libPaths(c(%s, .libPaths()))", literal(.libPaths())),"library(scworkbench)")
  writeLines(c(bootstrap,sprintf("lock <- scworkbench:::.wb_bundle_writer_lock_acquire(%s, operation='capsule contention', timeout_seconds=5)",literal(f$root)),sprintf("file.create(%s)",literal(ready)),sprintf("while(!file.exists(%s)) Sys.sleep(0.05)",literal(release)),"scworkbench:::.wb_bundle_writer_lock_release(lock)"),child)
  system2(file.path(R.home("bin"),"Rscript"),child,wait=FALSE,stdout=FALSE,stderr=FALSE)
  for(i in 1:200){if(file.exists(ready))break;Sys.sleep(0.05)};stopifnot(file.exists(ready))
  old_timeout<-options(scworkbench.writer_lock_timeout_seconds=0.2);contended<-try(.capsule_register_fixture(f,name="contended"),silent=TRUE);options(old_timeout);file.create(release)
  stopifnot(inherits(contended,"try-error"),!"contended"%in%wb_capsules(f$bundle)$name)
  work<-tempfile();dir.create(work);writeLines("x",file.path(work,"x"));file.symlink(file.path(work,"x"),file.path(work,"link"))
  bad<-function(...)inherits(try(wb_capsule_register(f$bundle,"bad",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"link"),outputs=list(x=list(path=file.path(work,"x"))),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule"),...),silent=TRUE),"try-error")
  stopifnot(bad())
  fifo<-file.path(work,"fifo");system2("mkfifo",fifo);stopifnot(inherits(try(scworkbench:::.wb_capsule_assert_external_file(f$bundle,fifo,"fifo"),silent=TRUE),"try-error"))
  stopifnot(inherits(try(wb_capsule_register(f$bundle,"authoritative",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"x"),outputs=list(x=list(path=file.path(work,"x"),role="matrix")),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule")),silent=TRUE),"try-error"))
  stopifnot(inherits(try(wb_capsule_register(f$bundle,"existing-op",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"x"),outputs=list(x=list(path=file.path(work,"x"))),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="use_existing_op")),silent=TRUE),"try-error"))
  stopifnot(inherits(try(wb_capsule_register(f$bundle,"unsplit",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"x"),outputs=list(x=list(path=file.path(work,"x"))),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="split_standard_and_custom")),silent=TRUE),"try-error"))
  stopifnot(inherits(try(wb_capsule_register(f$bundle,"broad",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"x"),outputs=list(x=list(path=file.path(work,"x"))),purpose="other",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule")),silent=TRUE),"try-error"))
  writeLines("wb_op_umap_fit()",file.path(work,"umap.R"));stopifnot(inherits(try(wb_capsule_register(f$bundle,"wrapped-umap",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"umap.R"),outputs=list(x=list(path=file.path(work,"x"))),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule")),silent=TRUE),"try-error"))
  writeLines("rr <- wb_session_run_op(wb_session_new(), bundle, 'umap_fit', inputs = list())",file.path(work,"public-umap.R"))
  public_umap<-try(wb_capsule_register(f$bundle,"wrapped-public-umap",inputs=list(x=wb_ref_metadata_field("core:cell_id")),script=file.path(work,"public-umap.R"),outputs=list(x=list(path=file.path(work,"x"))),purpose="custom_terminal_summary",rationale="x",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule")),silent=TRUE)
  stopifnot(inherits(public_umap,"try-error"),grepl("CAPSULE_MINIMUM_CUSTOM_SURFACE",as.character(public_umap),fixed=TRUE))
  writeLines(c("# wb_session_run_op(session, bundle, op_name = 'umap_fit') is report prose only","caption <- \"The strings umap_fit and wb_op_umap_fit() describe prior registered-op evidence.\"","writeLines(caption, output_path)"),file.path(work,"prose.R"))
  prose<-wb_capsule_register(f$bundle,"custom-pca-umap-report",inputs=list(pca=wb_ref_entity("space","pca"),umap=wb_ref_entity("space","umap")),script=file.path(work,"prose.R"),outputs=list(report=list(path=file.path(work,"x"),role="report",media_type="text/plain")),purpose="custom_terminal_summary",rationale="paper-specific terminal comparison prose",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule"))
  stopifnot(prose$assurance_level=="content_registered",identical(wb_capsule_inputs(f$bundle,prose$capsule_id)$entity_id,c("pca","umap")))
  TRUE
}
