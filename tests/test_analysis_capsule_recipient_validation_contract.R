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

.capsule_fs_fingerprint <- function(root){files<-sort(list.files(root,recursive=TRUE,all.files=TRUE,full.names=TRUE,include.dirs=FALSE,no..=TRUE));list(paths=substring(files,nchar(normalizePath(root,winslash="/",mustWork=TRUE))+2L),sha=vapply(files,scworkbench:::.wb_prov_sha256_file,character(1)))}

test_analysis_capsule_recipient_validation_contract <- function() {
  required<-c("BPCells","Matrix","rhdf5");missing<-required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)];if(length(missing))return(contract_test_skip(paste("Missing runtime dependencies:",paste(missing,collapse=", "))))
  f<-.capsule_fixture();on.exit({try(wb_close_bundle(f$bundle),silent=TRUE);unlink(f$root,recursive=TRUE,force=TRUE)},add=TRUE)
  first<-.capsule_register_fixture(f,"original")$capsule
  second<-.capsule_register_fixture(f,"variant",relationships=list(list(type="variant_of",capsule_id=first$capsule_id)))$capsule
  stopifnot(identical(first$input_shape_signature,second$input_shape_signature),identical(first$parameter_shape_signature,second$parameter_shape_signature),identical(first$output_shape_signature,second$output_shape_signature),identical(first$similarity_signature,second$similarity_signature),identical(first$script_sha256,second$script_sha256))
  stopifnot(nrow(second$relationships)==1L,second$relationships$relationship_type=="variant_of")
  parameter_variant<-.capsule_register_fixture(f,"parameter variant",parameters=list(panel_order=c("pca","scvi","custom"),subtitle=NULL))$capsule
  stopifnot(identical(second$input_shape_signature,parameter_variant$input_shape_signature),identical(second$output_shape_signature,parameter_variant$output_shape_signature),identical(second$script_sha256,parameter_variant$script_sha256),!identical(second$parameter_shape_signature,parameter_variant$parameter_shape_signature),!identical(second$similarity_signature,parameter_variant$similarity_signature))
  candidate<-.capsule_register_fixture(f,"portable candidate evidence",catalog_decision="propose_new_op")$capsule
  stopifnot(candidate$catalog_review$decision=="propose_new_op",candidate$assurance_level=="content_registered",candidate$replay_status=="not_verified",!candidate$name%in%wb_list_ops())
  graph<-wb_prov_bundle_dag(f$bundle);stopifnot(any(graph$edges$from==paste0("capsule:",second$capsule_id)&graph$edges$to==paste0("capsule:",first$capsule_id)&graph$edges$edge_type=="VARIANT_OF"))
  stopifnot(wb_entity_certificate(f$bundle,"capsule",second$capsule_id)$details$declared_relationships$relationship_type[[1L]]=="variant_of")
  before_shapes<-second[c("input_shape_signature","parameter_shape_signature","output_shape_signature","similarity_signature","script_sha256")]
  scaffold<-tempfile("capsule_scaffold_");wb_capsule_scaffold(f$bundle,"draft",list(space=wb_ref_entity("space","pca"),field=wb_ref_metadata_field("core:cell_id")),list(report=list(role="report",media_type="text/markdown",extension=".md")),"R",scaffold,"dataset_specific_reporting","question-specific report")
  script_text<-paste(readLines(file.path(scaffold,"analysis.R")),collapse="\n");stopifnot(grepl("read_only = TRUE",script_text,fixed=TRUE),grepl("wb_entity_certificate",script_text,fixed=TRUE),grepl("wb_metadata_field_resolve",script_text,fixed=TRUE),!grepl(normalizePath(f$root,winslash="/",mustWork=TRUE),script_text,fixed=TRUE),!grepl("scworkbench:::",script_text,fixed=TRUE))
  export<-tempfile("capsule_export_");wb_capsule_emit_reproduction(f$bundle,second$capsule_id,export)
  repro<-jsonlite::fromJSON(file.path(export,"reproduction.json"),simplifyVector=FALSE);stopifnot(repro$export_status=="source_exported",identical(repro$replay_ready,FALSE),identical(repro$replay_verified,FALSE),!grepl("scworkbench:::",paste(readLines(file.path(export,"inspect.R")),collapse="\n"),fixed=TRUE),identical(scworkbench:::.wb_prov_sha256_file(file.path(export,second$entrypoint)),second$script_sha256))
  wb_finalize_recipient_bundle(f$bundle);wb_close_bundle(f$bundle)
  moved_parent<-tempfile("capsule_moved_");dir.create(moved_parent);stopifnot(file.copy(f$root,moved_parent,recursive=TRUE));moved<-file.path(moved_parent,basename(f$root));ro<-wb_open_bundle(moved,read_only=TRUE);on.exit({try(wb_close_bundle(ro),silent=TRUE);unlink(moved_parent,recursive=TRUE,force=TRUE)},add=TRUE)
  before<-.capsule_fs_fingerprint(moved);moved_cap<-wb_capsule(ro,second$capsule_id);stopifnot(identical(moved_cap[c("input_shape_signature","parameter_shape_signature","output_shape_signature","similarity_signature","script_sha256")],before_shapes),file.exists(wb_capsule_script_path(ro,second$capsule_id)),paste0("capsule:",second$capsule_id)%in%wb_prov_bundle_dag(ro)$nodes$id)
  source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset="")
  if (!nzchar(source_root) && file.exists("DESCRIPTION") && dir.exists("R")) source_root <- normalizePath(".",winslash="/",mustWork=TRUE)
  source_wrapper<-file.path(export,"inspect.R")
  if (nzchar(source_root)) {
    source_wrapper<-file.path(export,"inspect-source-test.R");wrapper_lines<-readLines(file.path(export,"inspect.R"));wrapper_lines[wrapper_lines=="library(scworkbench)"]<-sprintf("devtools::load_all('%s', quiet=TRUE)",normalizePath(source_root,winslash="/",mustWork=TRUE));writeLines(wrapper_lines,source_wrapper)
  }
  wrapper_status<-system2(file.path(R.home("bin"),"Rscript"),c(source_wrapper,moved),stdout=TRUE,stderr=TRUE);stopifnot(is.null(attr(wrapper_status,"status"))||identical(as.integer(attr(wrapper_status,"status")),0L))
  wb_entity_certificate(ro,"capsule",second$capsule_id);wb_kg_provenance_graph(ro);after<-.capsule_fs_fingerprint(moved);stopifnot(identical(before,after),inherits(try(.capsule_register_fixture(list(bundle=ro,model_id=f$model_id,artifact_id=f$artifact_id,source_id=f$source_id),"read-only"),silent=TRUE),"try-error"))
  TRUE
}

test_analysis_capsule_tamper_validation_contract <- function() {
  required<-c("BPCells","Matrix","rhdf5");missing<-required[!vapply(required,requireNamespace,logical(1),quietly=TRUE)];if(length(missing))return(contract_test_skip(paste("Missing runtime dependencies:",paste(missing,collapse=", "))))
  for(target in c("script","output","manifest")){
    f<-.capsule_fixture();reg<-.capsule_register_fixture(f,paste0("tamper-",target));cap<-reg$capsule
    path<-switch(target,script=wb_capsule_script_path(f$bundle,cap$capsule_id),output=wb_capsule_output_path(f$bundle,cap$capsule_id,"metrics"),manifest=file.path(f$root,cap$manifest_path));writeBin(as.raw(c(1,2,3,4)),path)
    report<-wb_bundle_validation_report(f$root,"content");codes<-as.character(report$diagnostics$code)
    expected<-switch(target,script="CAPSULE_SCRIPT_CONTENT_MISMATCH",output="CAPSULE_OUTPUT_CONTENT_MISMATCH",manifest="CAPSULE_MANIFEST_CONTENT_MISMATCH")
    stopifnot(expected%in%codes)
    wb_close_bundle(f$bundle);unlink(f$root,recursive=TRUE,force=TRUE)
  }
  TRUE
}
