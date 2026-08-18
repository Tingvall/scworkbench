.capsule_process_literal <- function(x) paste(deparse(as.character(x)), collapse = "")

.capsule_process_spawn <- function(repo, root, source_file, output_file, marker, log, boundary) {
  child <- tempfile("capsule_sigkill_", fileext = ".R")
  literal <- .capsule_process_literal
  writeLines(c(
    sprintf("devtools::load_all(%s, quiet=TRUE)", literal(repo)),
    sprintf("bundle <- wb_open_bundle(%s)", literal(root)),
    "on.exit(wb_close_bundle(bundle), add=TRUE)",
    sprintf("target <- %s", literal(boundary)),
    sprintf("marker <- %s", literal(marker)),
    "options(scworkbench.analysis_capsule_fault_hook=function(boundary,...){if(identical(boundary,target)){writeLines(boundary,marker);while(TRUE) Sys.sleep(1)}})",
    sprintf(paste0(
      "wb_capsule_register(bundle,'sigkill-capsule',",
      "inputs=list(cells=wb_ref_metadata_field('core:cell_id')),",
      "script=%s,outputs=list(report=list(path=%s,role='report',media_type='text/plain')),",
      "purpose='custom_terminal_summary',rationale='process-death publication contract',",
      "catalog_review=list(catalog_identity='scworkbench.operation_catalog',catalog_version='0.1.0',",
      "reviewed_at='2026-08-18T00:00:00Z',decision='retain_as_capsule'))"
    ), literal(source_file), literal(output_file))
  ), child)
  pid <- suppressWarnings(as.integer(system(paste(
    shQuote(file.path(R.home("bin"), "Rscript")), shQuote(child),
    ">", shQuote(log), "2>&1 & echo $!"
  ), intern=TRUE)))
  stopifnot(!is.na(pid), pid > 1L)
  pid
}

test_analysis_capsule_process_death_contract <- function() {
  repo <- normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset="."), winslash="/", mustWork=TRUE)
  cases <- list(
    staged=list(boundary="after_private_payload_staging", diagnostic="CAPSULE_PENDING_RESIDUE", committed=FALSE),
    renamed=list(boundary="after_final_directory_rename_before_sqlite_commit", diagnostic="CAPSULE_ORPHAN_PAYLOAD", committed=FALSE),
    committed=list(boundary="after_sqlite_commit_before_manifest_publication", diagnostic=NA_character_, committed=TRUE)
  )
  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    root <- tempfile(paste0("scwb_capsule_sigkill_",case_name,"_"))
    work <- tempfile(paste0("scwb_capsule_sigkill_work_",case_name,"_"));dir.create(work)
    marker <- file.path(work,"marker");log <- file.path(work,"child.log")
    source_file <- file.path(work,"terminal.R");output_file <- file.path(work,"report.txt")
    writeLines("result <- 'externally prepared terminal evidence'",source_file)
    writeLines("process-death publication evidence",output_file)
    b <- wb_init_bundle(root,overwrite=TRUE);wb_define_cells(b,c("c1","c2"));wb_close_bundle(b)
    b <- wb_open_bundle(root)
    cleanup <- function(){try(wb_close_bundle(b),silent=TRUE);unlink(c(root,work),recursive=TRUE,force=TRUE)}
    pid <- .capsule_process_spawn(repo,root,source_file,output_file,marker,log,case$boundary)
    deadline <- Sys.time()+30
    while(!file.exists(marker)&&Sys.time()<deadline)Sys.sleep(0.1)
    if(!file.exists(marker)){
      child_log<-if(file.exists(log))paste(readLines(log,warn=FALSE),collapse="\n") else "<missing>"
      cleanup();stop("capsule child did not reach ",case$boundary,":\n",child_log,call.=FALSE)
    }
    tools::pskill(pid,signal=9L);Sys.sleep(0.5)
    lock<-wb_bundle_writer_lock_info(root,stale_after_seconds=0)
    stopifnot(isTRUE(lock$locked))
    wb_recover_bundle_writer_lock(root,"RECOVER STALE SCWORKBENCH WRITER LOCK",stale_after_seconds=0,allow_unknown_owner=TRUE)
    try(DBI::dbGetQuery(b$con,"PRAGMA wal_checkpoint(TRUNCATE);"),silent=TRUE)

    residue <- scworkbench:::.wb_capsule_residue_inventory(root,b$con)
    rows <- wb_capsules(b)
    if(isTRUE(case$committed)){
      stopifnot(!length(residue$pending),!length(residue$orphan),nrow(rows)==1L,
                file.exists(wb_capsule_script_path(b,rows$capsule_id[[1L]])),
                file.exists(wb_capsule_output_path(b,rows$capsule_id[[1L]],"report")))
    } else if(identical(case_name,"staged")) {
      stopifnot(length(residue$pending)==1L,!length(residue$orphan),nrow(rows)==0L)
    } else {
      stopifnot(!length(residue$pending),length(residue$orphan)==1L,nrow(rows)==0L)
    }
    report_before <- wb_bundle_validation_report(root,"content")
    codes_before <- as.character(report_before$diagnostics$code)
    if(isTRUE(case$committed)) stopifnot(!any(c("CAPSULE_PENDING_RESIDUE","CAPSULE_ORPHAN_PAYLOAD")%in%codes_before))
    else stopifnot(case$diagnostic%in%codes_before)

    if(isTRUE(case$committed)){
      manifest_before<-jsonlite::read_json(file.path(root,"manifest.json"),simplifyVector=TRUE)
      stopifnot(as.integer(manifest_before$counts$n_analysis_capsules)==0L)
      finalized<-wb_finalize_recipient_bundle(b);stopifnot(isTRUE(finalized$ready))
      manifest_after<-jsonlite::read_json(file.path(root,"manifest.json"),simplifyVector=TRUE)
      stopifnot(as.integer(manifest_after$counts$n_analysis_capsules)==1L)
      duplicate<-try(wb_capsule_register(b,"sigkill-capsule",inputs=list(cells=wb_ref_metadata_field("core:cell_id")),script=source_file,outputs=list(report=list(path=output_file,role="report")),purpose="custom_terminal_summary",rationale="retry must not duplicate committed state",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule")),silent=TRUE)
      stopifnot(inherits(duplicate,"try-error"),nrow(wb_capsules(b))==1L)
    } else {
      blocked<-try(wb_finalize_recipient_bundle(b),silent=TRUE)
      stopifnot(inherits(blocked,"try-error"),grepl("CAPSULE_UNRESOLVED_PUBLICATION_RESIDUE",as.character(blocked),fixed=TRUE))
      wb_close_bundle(b);b<-wb_open_bundle(root)
      recovered<-scworkbench:::.wb_capsule_residue_inventory(root,b$con)
      stopifnot(!length(recovered$pending),!length(recovered$orphan),nrow(wb_capsules(b))==0L)
      retried<-wb_capsule_register(b,"sigkill-capsule",inputs=list(cells=wb_ref_metadata_field("core:cell_id")),script=source_file,outputs=list(report=list(path=output_file,role="report")),purpose="custom_terminal_summary",rationale="safe retry after process death",catalog_review=list(catalog_identity="x",catalog_version="x",reviewed_at="x",decision="retain_as_capsule"))
      stopifnot(nrow(wb_capsules(b))==1L,file.exists(wb_capsule_script_path(b,retried$capsule_id)))
      finalized<-wb_finalize_recipient_bundle(b);stopifnot(isTRUE(finalized$ready))
    }
    wb_close_bundle(b);b<-NULL
    final_report<-wb_bundle_validation_report(root,"recipient")
    stopifnot(isTRUE(final_report$ok),!any(c("CAPSULE_PENDING_RESIDUE","CAPSULE_ORPHAN_PAYLOAD")%in%as.character(final_report$diagnostics$code)))
    ro<-wb_open_bundle(root,read_only=TRUE)
    stopifnot(nrow(wb_capsules(ro))==1L,file.exists(wb_capsule_script_path(ro,wb_capsules(ro)$capsule_id[[1L]])))
    wb_close_bundle(ro)
    unlink(c(root,work),recursive=TRUE,force=TRUE)
  }
  TRUE
}
