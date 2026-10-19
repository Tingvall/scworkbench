.engine_runtime_metadata_core_library <- function() {
  root <- normalizePath(find.package("scworkbench"),mustWork=TRUE)
  stopifnot(file.exists(file.path(root,"Meta","package.rds")))
  dirname(root)
}

.engine_runtime_metadata_fixture <- function(root) {
  source <- file.path(root,"fixture_source");lib<-file.path(root,"fixture_library")
  dir.create(file.path(source,"R"),recursive=TRUE);dir.create(lib)
  writeLines(c("Package: BPCells","Version: 0.0.101","Title: Owned Runtime Metadata Fixture",
    "Description: Tests installed metadata without evaluating namespace loading.",
    "Authors@R: person('Fixture','Author',email='fixture@example.invalid',role=c('aut','cre'))",
    "License: MIT","Encoding: UTF-8",paste0("RemoteSha: ",paste(rep("a",40),collapse=""))),
    file.path(source,"DESCRIPTION"))
  writeLines("export(fixture_marker)",file.path(source,"NAMESPACE"))
  writeLines(c("fixture_marker <- function() TRUE",
    ".onLoad <- function(libname,pkgname) {",
    " p <- Sys.getenv('SCWB_RUNTIME_METADATA_MARKER','')",
    " if(nzchar(p)) writeLines('owned fixture onLoad executed',p)",
    " if(identical(Sys.getenv('SCWB_RUNTIME_METADATA_FAIL',''),'yes')) stop('owned fixture deliberately unloadable')",
    "}"),file.path(source,"R","fixture.R"))
  output <- system2(file.path(R.home("bin"),"R"),c("CMD","INSTALL","--no-test-load",
    "--no-multiarch",paste0("--library=",shQuote(lib)),shQuote(source)),stdout=TRUE,stderr=TRUE)
  stopifnot(is.null(attr(output,"status")) || identical(attr(output,"status"),0L))
  lib
}

.engine_runtime_metadata_child <- function(root,core_library,fixture_library,code,isolated=FALSE) {
  script<-tempfile("runtime_metadata_",tmpdir=root,fileext=".R")
  marker<-paste0(script,".onLoad")
  lines<-c("args<-commandArgs(TRUE)",
    "if(args[[3L]]=='isolated') .libPaths(c(args[[1L]],.Library),include.site=FALSE) else .libPaths(c(args[[2L]],args[[1L]],.libPaths()))",
    "suppressPackageStartupMessages(library(scworkbench,lib.loc=args[[1L]]))",
    "stopifnot(identical(normalizePath(find.package('scworkbench')),normalizePath(args[[4L]])))",
    "Sys.setenv(SCWB_RUNTIME_METADATA_MARKER=args[[5L]],SCWB_RUNTIME_METADATA_FAIL='')",
    "local(",deparse(substitute(code),width.cutoff=500L),")")
  writeLines(lines,script)
  output<-system2(file.path(R.home("bin"),"Rscript"),vapply(c("--vanilla",script,
    core_library,fixture_library,if(isolated)"isolated"else"normal",
    find.package("scworkbench"),marker),shQuote,character(1)),stdout=TRUE,stderr=TRUE)
  cat(paste(output,collapse="\n"),"\n")
  stopifnot(is.null(attr(output,"status")) || identical(attr(output,"status"),0L))
  invisible(TRUE)
}

test_engine_runtime_metadata_cold_unloadable_loaded_contract <- function() {
  core<-.engine_runtime_metadata_core_library();root<-tempfile("runtime_metadata_owned_");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  lib<-.engine_runtime_metadata_fixture(root)
  .engine_runtime_metadata_child(root,core,lib,{
    stopifnot(!"BPCells" %in% loadedNamespaces(),!file.exists(args[[5L]]))
    before<-sort(loadedNamespaces())
    fingerprint<-scworkbench:::.wb_prov_runtime_fingerprint("metadata_cell_vector")
    stopifnot(identical(fingerprint$schema,"scworkbench.runtime_attestation.v2"),
      identical(fingerprint$bpcells$version,"0.0.101"),
      identical(fingerprint$bpcells$native_provenance,paste(rep("a",40),collapse="")),
      identical(before,sort(loadedNamespaces())),!file.exists(args[[5L]]),
      !"BPCells" %in% names(fingerprint$namespaces))
    cat("COLD_INSTALLED_METADATA_NO_NAMESPACE_OR_ONLOAD\n")
  })
  .engine_runtime_metadata_child(root,core,lib,{
    Sys.setenv(SCWB_RUNTIME_METADATA_FAIL="yes")
    before<-sort(loadedNamespaces())
    fingerprint<-scworkbench:::.wb_prov_runtime_fingerprint("metadata_cell_vector")
    stopifnot(identical(fingerprint$bpcells$version,"0.0.101"),
      identical(before,sort(loadedNamespaces())),!file.exists(args[[5L]]))
    actual_load<-requireNamespace("BPCells",quietly=TRUE)
    stopifnot(identical(actual_load,FALSE),file.exists(args[[5L]]),!"BPCells" %in% loadedNamespaces())
    cat("INSTALLED_UNLOADABLE_VERSION_RECORDED_BEFORE_INDEPENDENT_ONLOAD_FAILURE\n")
  })
  .engine_runtime_metadata_child(root,core,lib,{
    cold<-scworkbench:::.wb_prov_runtime_fingerprint("before_owned_namespace_load")
    stopifnot(!"BPCells" %in% names(cold$namespaces),!file.exists(args[[5L]]))
    loadNamespace("BPCells",lib.loc=args[[2L]])
    stopifnot(file.exists(args[[5L]]),identical(as.character(getNamespaceVersion("BPCells")),"0.0.101"))
    marker<-readLines(args[[5L]])
    # Modify ONLY this test's owned installed metadata, never real deps. R4.4
    # packageDescription prefers Meta/package.rds$DESCRIPTION over the flat file.
    description<-file.path(args[[2L]],"BPCells","DESCRIPTION")
    fields<-read.dcf(description);fields[1L,"Version"]<-"0.0.102"
    fields[1L,"RemoteSha"]<-paste(rep("b",40),collapse="")
    write.dcf(fields,description)
    metadata_path<-file.path(args[[2L]],"BPCells","Meta","package.rds")
    metadata<-readRDS(metadata_path)
    metadata$DESCRIPTION[["Version"]]<-"0.0.102"
    metadata$DESCRIPTION[["RemoteSha"]]<-paste(rep("b",40),collapse="")
    saveRDS(metadata,metadata_path)
    stopifnot(identical(as.character(utils::packageVersion("BPCells")),"0.0.102"),
      identical(as.character(utils::packageDescription("BPCells")$RemoteSha),paste(rep("b",40),collapse="")),
      identical(as.character(getNamespaceVersion("BPCells")),"0.0.101"))
    before<-sort(loadedNamespaces())
    fingerprint<-scworkbench:::.wb_prov_runtime_fingerprint("metadata_cell_vector")
    stopifnot(identical(fingerprint$bpcells$version,"0.0.102"),
      identical(fingerprint$bpcells$native_provenance,paste(rep("b",40),collapse="")),
      identical(as.character(getNamespaceVersion("BPCells")),"0.0.101"),
      "BPCells" %in% names(fingerprint$namespaces),
      identical(before,sort(loadedNamespaces())),identical(marker,readLines(args[[5L]])))
    cat("INSTALLED_DESCRIPTION_NOT_LOADED_NATIVE_VERSION_PROOF\n")
  })
  TRUE
}

test_engine_runtime_metadata_missing_without_dependency_mutation_contract <- function() {
  core<-.engine_runtime_metadata_core_library();root<-tempfile("runtime_metadata_missing_");dir.create(root)
  on.exit(unlink(root,recursive=TRUE),add=TRUE)
  farm<-file.path(root,"isolated_library");dir.create(farm)
  # A fresh child's library consists of read-only symlinks to installed packages,
  # excluding BPCells. No real package directory or metadata is modified.
  for(lib in unique(c(core,.libPaths())))for(path in list.dirs(lib,recursive=FALSE,full.names=TRUE)){
    name<-basename(path);target<-file.path(farm,name)
    if(name=="BPCells" || file.exists(target) || !file.exists(file.path(path,"Meta","package.rds")))next
    stopifnot(file.symlink(normalizePath(path),target))
  }
  stopifnot(!file.exists(file.path(.Library,"BPCells")))
  .engine_runtime_metadata_child(root,farm,farm,{
    stopifnot(!"BPCells" %in% loadedNamespaces(),!length(find.package("BPCells",quiet=TRUE)))
    before<-sort(loadedNamespaces());warnings<-character()
    fingerprint<-withCallingHandlers(scworkbench:::.wb_prov_runtime_fingerprint("metadata_cell_vector"),
      warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    stopifnot(identical(fingerprint$schema,"scworkbench.runtime_attestation.v2"),
      is.na(fingerprint$bpcells$version),is.na(fingerprint$bpcells$native_provenance),
      identical(before,sort(loadedNamespaces())),!file.exists(args[[5L]]),
      is.na(scworkbench:::.wb_promotion_package_version("scwbDefinitelyMissingOwnedFixture")))
    # The existing RemoteSha lookup may warn for missing DESCRIPTION; the new
    # version helper suppresses its own inventory warning, without loading.
    cat("MISSING_PACKAGE_METADATA_NA warnings=",length(warnings),"\n",sep="")
  },isolated=TRUE)
  TRUE
}

test_engine_runtime_metadata_fresh_environment_pack_contract <- function() {
  variables<-c("SCWORKBENCH_RUNTIME_IMAGE_SHA256","SCWORKBENCH_SOURCE_REVISION","SCWORKBENCH_CONTAINER_DIGEST")
  prior<-Sys.getenv(variables,unset=NA_character_)
  on.exit(for(name in variables)if(is.na(prior[[name]]))Sys.unsetenv(name)else
    do.call(Sys.setenv,setNames(list(prior[[name]]),name)),add=TRUE)
  registry<-scworkbench:::.wb_operation_pack_registry
  packs<-registry$packs;operations<-registry$operations
  on.exit({registry$packs<-packs;registry$operations<-operations},add=TRUE)
  name<-"scwbRuntimeMetadataOwned::probe";namespace<-"scwbRuntimeMetadataOwned"
  stopifnot(is.null(registry$packs[[namespace]]),is.null(registry$operations[[name]]))
  # Generic unit fixture for the existing registry lookup, not a claim that this
  # synthetic identity executed or represents a qualified scientific pack.
  identity<-list(namespace=namespace,pack_sha256=paste(rep("c",64),collapse=""))
  registry$packs[[namespace]]<-list(runtime_attestation=list(backend="R",marker="first"))
  registry$operations[[name]]<-list(definition=list(source_pack=identity))
  Sys.setenv(SCWORKBENCH_RUNTIME_IMAGE_SHA256="image_first",SCWORKBENCH_SOURCE_REVISION="revision_first",SCWORKBENCH_CONTAINER_DIGEST="container_first")
  first<-scworkbench:::.wb_prov_runtime_fingerprint(name)
  supplied<-list(backend="R",receipt_evidence="second",unknown_field=list(value=17L))
  Sys.setenv(SCWORKBENCH_RUNTIME_IMAGE_SHA256="image_second",SCWORKBENCH_SOURCE_REVISION="revision_second",SCWORKBENCH_CONTAINER_DIGEST="container_second")
  second<-scworkbench:::.wb_prov_runtime_fingerprint(name,operation_pack_runtime=supplied)
  registry$packs[[namespace]]$runtime_attestation<-list(backend="R",marker="third")
  third<-scworkbench:::.wb_prov_runtime_fingerprint(name)
  plain<-scworkbench:::.wb_prov_runtime_fingerprint("metadata_cell_vector")
  stopifnot(identical(first$schema,"scworkbench.runtime_attestation.v2"),
    identical(names(first),c("schema","r_version","platform","scworkbench_version","operation","namespaces","bpcells","image","runtime_provenance","operation_pack","operation_pack_runtime")),
    identical(first$operation,list(name=name,version="1")),
    identical(first$operation_pack,identity),identical(second$operation_pack,identity),
    identical(first$operation_pack_runtime,list(backend="R",marker="first")),
    identical(second$operation_pack_runtime,supplied),identical(third$operation_pack_runtime,list(backend="R",marker="third")),
    identical(first$image$sha256,"image_first"),identical(second$image$sha256,"image_second"),
    identical(second$runtime_provenance,list(source_revision="revision_second",container_digest="container_second")),
    identical(plain$operation$name,"metadata_cell_vector"),is.null(plain$operation_pack))
  TRUE
}

test_engine_runtime_metadata_v1_readonly_checkpoint_certificate_contract <- function() {
  root<-tempfile("runtime_metadata_history_");work<-tempfile("runtime_metadata_workspace_")
  b<-wb_init_bundle(root);s<-NULL;ephemeral<-NULL
  on.exit({if(!is.null(s))try(wb_session_discard(s),silent=TRUE)
    if(!is.null(ephemeral))try(wb_session_discard(ephemeral),silent=TRUE)
    if(DBI::dbIsValid(b$con))try(wb_close_bundle(b),silent=TRUE)
    unlink(root,recursive=TRUE);unlink(work,recursive=TRUE)},add=TRUE)
  cells<-c("c3","c1","c2")
  wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,group=c("A","B","A")))
  s<-wb_session_create(b,work,"legacy_metadata")
  stopifnot(identical(s$durable$runtime_attestations$session$schema,"scworkbench.runtime_attestation.v2"))
  legacy<-list(schema="scworkbench.runtime_attestation.v1",r_version="historical R",platform="historical platform",
    scworkbench_version="0.0.1",operation=list(name="session",version="1"),namespaces=list(),
    bpcells=list(version=NA_character_,native_provenance=NA_character_),
    image=list(status="unavailable",sha256=NA_character_),
    runtime_provenance=list(source_revision=NA_character_,container_digest=NA_character_))
  # Owned fixture models a historical informational record. The ordinary
  # checkpoint writer binds it; no old receipt or integrity proof is bypassed.
  s$durable$runtime_attestations$session<-legacy
  s<-scworkbench:::.wb_session_checkpoint(s,"active")
  checkpoint<-scworkbench:::.wb_session_checkpoint_file(s)
  before_checkpoint<-digest::digest(file=checkpoint,algo="sha256")
  stopifnot(identical(readRDS(checkpoint)$durable$runtime_attestations$session,legacy))
  wb_close_bundle(b);b<-wb_open_bundle(root)
  s<-wb_session_resume(b,file.path(work,"legacy_metadata"))
  stopifnot(identical(s$durable$runtime_attestations$session,legacy),
    identical(before_checkpoint,digest::digest(file=checkpoint,algo="sha256")))
  wb_session_discard(s);s<-NULL
  result<-wb_session_run_op(wb_session_new(),b,"metadata_cell_vector",inputs=list(
    source_column="group",vector_name="history_group",value_type="categorical",
    missing_policy="error",cell_set="all",min_cells=1L))
  ephemeral<-result$session
  promoted<-wb_session_promote_current(b,ephemeral,outputs="vector")
  run_id<-result$run$run_id
  fresh<-wb_prov_run_details(b,run_id)
  stopifnot(identical(fresh$run$runtime_fingerprint$schema,"scworkbench.runtime_attestation.v2"))
  legacy$operation$name<-"metadata_cell_vector"
  bytes<-as.character(jsonlite::toJSON(legacy,auto_unbox=TRUE,null="null"))
  DBI::dbExecute(b$con,"UPDATE prov_runs SET runtime_fingerprint_json=? WHERE run_id=?;",params=list(bytes,run_id))
  wb_refresh_manifest(b);stopifnot(isTRUE(wb_finalize_recipient_bundle(b)$ready))
  wb_close_bundle(b);b<-wb_open_bundle(root,read_only=TRUE,validate=FALSE)
  before<-scworkbench:::.wb_prov_file_tree_sha256(root)
  detail<-wb_prov_run_details(b,run_id)
  certificate<-wb_entity_certificate(b,"run",run_id)
  stored<-DBI::dbGetQuery(b$con,"SELECT runtime_fingerprint_json FROM prov_runs WHERE run_id=?;",params=list(run_id))
  stopifnot(identical(detail$run$runtime_fingerprint$schema,"scworkbench.runtime_attestation.v1"),
    identical(certificate$details$runtime_attestation$value$schema,"scworkbench.runtime_attestation.v1"),
    identical(stored$runtime_fingerprint_json[[1L]],bytes),
    identical(before,scworkbench:::.wb_prov_file_tree_sha256(root)))
  TRUE
}
