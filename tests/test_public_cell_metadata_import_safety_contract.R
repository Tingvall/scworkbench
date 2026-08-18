.metadata_import_state <- function(bundle) {
  tables <- c("metadata_fields","artifacts","artifact_tables","artifact_table_rows","prov_heads","prov_runs","prov_source_inputs","prov_run_entity_bindings")
  counts <- vapply(tables,function(x)if(scworkbench:::.wb_table_exists(bundle$con,x))DBI::dbGetQuery(bundle$con,paste0("SELECT COUNT(*) n FROM ",x,";"))$n[[1L]] else 0,numeric(1))
  files <- sort(list.files(bundle$dir,recursive=TRUE,all.files=TRUE,full.names=TRUE,include.dirs=FALSE))
  list(counts=counts,columns=DBI::dbListFields(bundle$con,"cells"),files=setNames(vapply(files,wb_source_sha256,character(1)),substring(files,nchar(bundle$dir)+2L)))
}

test_public_cell_metadata_import_safety_contract <- function() {
  root<-tempfile("scwb_metadata_import_safety_");work<-tempfile("scwb_metadata_import_source_");dir.create(work)
  b<-wb_init_bundle(root,overwrite=TRUE);on.exit({options(scworkbench.metadata_import_test_hook=NULL,scworkbench.metadata_writer_test_hook=NULL);try(wb_close_bundle(b),silent=TRUE);unlink(c(root,work),recursive=TRUE,force=TRUE)},add=TRUE)
  cells<-paste0("c",1:5);wb_define_cells(b,cells)
  make_file<-function(name,lines){p<-file.path(work,name);writeLines(lines,p);p}
  source_for<-function(p,id="source",format=if(grepl("csv$",p))"csv" else "tsv")wb_source_input(
    path=p,source_id=id,accession=paste0("fixture-",id),role="cell_metadata",
    format=format,scope="external_file"
  )

  good<-make_file("good.csv",c("value,cell","1,c1","2,c2"));src<-source_for(good)
  before<- .metadata_import_state(b)
  lock_before<-wb_bundle_writer_lock_info(root)
  invisible(wb_metadata_import(b,good,"cell",src,validate_only=TRUE))
  lock_after<-wb_bundle_writer_lock_info(root)
  stopifnot(identical(before,.metadata_import_state(b)),
            identical(lock_before$locked,lock_after$locked),
            identical(lock_before$owner$token,lock_after$owner$token))

  failures<-list(
    duplicate=make_file("duplicate.csv",c("cell,x","c1,1","c1,2")),
    empty=make_file("empty.csv",c("cell,x",",1")),
    unknown=make_file("unknown.csv",c("cell,x","outside,1")),
    missing_col=make_file("missing.csv",c("id,x","c1,1"))
  )
  for(nm in names(failures)) {
    got<-try(wb_metadata_import(b,failures[[nm]],"cell",source_for(failures[[nm]],paste0("bad_",nm)),validate_only=TRUE),silent=TRUE)
    stopifnot(inherits(got,"try-error"),identical(before,.metadata_import_state(b)))
  }
  missing_field<-try(wb_metadata_import(b,good,"cell",src,fields="absent",validate_only=TRUE),silent=TRUE)
  duplicate_fields<-try(wb_metadata_import(b,good,"cell",src,fields=c("value","value"),validate_only=TRUE),silent=TRUE)
  bad_ref<-try(wb_metadata_import(b,good,"cell",src,field_refs=list(wb_ref_metadata_field("meta:999999")),validate_only=TRUE),silent=TRUE)
  stopifnot(inherits(missing_field,"try-error"),inherits(duplicate_fields,"try-error"),inherits(bad_ref,"try-error"))
  malformed<-try(wb_metadata_import(b,good,"cell",list(inputs=list(list(scope="external_file"))),validate_only=TRUE),silent=TRUE)
  mismatch_src<-src;mismatch_src$sha256<-paste(rep("0",64),collapse="");mismatch_src$checksum<-mismatch_src$sha256
  mismatch<-try(wb_metadata_import(b,good,"cell",mismatch_src,validate_only=TRUE),silent=TRUE)
  stopifnot(inherits(malformed,"try-error"),inherits(mismatch,"try-error"),identical(before,.metadata_import_state(b)))

  mixed<-make_file("mixed.csv",c("cell,x","c1,1","outside,2","c3,3"))
  mixed_result<-suppressWarnings(wb_metadata_import(b,mixed,"cell",source_for(mixed,"mixed"),unknown_cell_policy="warn_drop"))
  mixed_evidence<-wb_art_load(b,mixed_result$report_artifact_id,"obs_table")
  stopifnot(mixed_result$counts$matched==2L,mixed_result$counts$rejected==1L,mixed_result$counts$unsupplied_known==3L,
            any(mixed_evidence$table$record_type=="rejected_row" & mixed_evidence$table$cell_id=="outside"))

  rollback<-make_file("rollback.csv",c("cell,rollback_field","c1,1","c2,2"));rollback_src<-source_for(rollback,"rollback")
  for(event in c("metadata_writer_after_staging","before_provenance_publication")) {
    state<- .metadata_import_state(b)
    if(identical(event,"metadata_writer_after_staging")) {
      options(scworkbench.metadata_writer_test_hook=function(event,...){if(identical(event,"after_staging"))stop("forced staged metadata import fault",call.=FALSE)})
    } else {
      options(scworkbench.metadata_import_test_hook=function(event,...){if(identical(event,"before_provenance_publication"))stop("forced metadata import provenance fault",call.=FALSE)})
    }
    failed<-try(wb_metadata_import(b,rollback,"cell",rollback_src),silent=TRUE)
    options(scworkbench.metadata_import_test_hook=NULL,scworkbench.metadata_writer_test_hook=NULL)
    after<- .metadata_import_state(b)
    stopifnot(inherits(failed,"try-error"),identical(state$counts,after$counts),
              identical(state$columns,after$columns),identical(names(state$files),names(after$files)),
              identical(unname(state$files[["manifest.json"]]),unname(after$files[["manifest.json"]])),
              !("rollback_field"%in%DBI::dbListFields(b$con,"cells")),
              !any(grepl("pending|staging",names(after$files))))
  }

  wb_finalize_recipient_bundle(b);wb_close_bundle(b);b<-wb_open_bundle(root,read_only=TRUE)
  ro<-try(wb_metadata_import(b,good,"cell",src),silent=TRUE);stopifnot(inherits(ro,"try-error"))
  wb_close_bundle(b);b<-wb_open_bundle(root)
  child<-file.path(work,"lock_child.R");ready<-file.path(work,"lock.ready");release<-file.path(work,"lock.release")
  literal<-function(x)paste(deparse(as.character(x)),collapse="")
  writeLines(c(
    sprintf("devtools::load_all(%s,quiet=TRUE)",literal(normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT",unset="."),mustWork=TRUE))),
    sprintf("lock<-scworkbench:::.wb_bundle_writer_lock_acquire(%s,operation='metadata import contention')",literal(root)),
    sprintf("file.create(%s)",literal(ready)),sprintf("while(!file.exists(%s))Sys.sleep(0.05)",literal(release)),
    "scworkbench:::.wb_bundle_writer_lock_release(lock)"
  ),child)
  pid<-as.integer(system(paste(shQuote(file.path(R.home("bin"),"Rscript")),shQuote(child),">/dev/null 2>&1 & echo $!"),intern=TRUE))
  deadline<-Sys.time()+20;while(!file.exists(ready)&&Sys.time()<deadline)Sys.sleep(0.05);stopifnot(file.exists(ready),!is.na(pid))
  old_timeout<-getOption("scworkbench.writer_lock_timeout_seconds");options(scworkbench.writer_lock_timeout_seconds=0.2)
  contended<-try(wb_metadata_import(b,rollback,"cell",rollback_src),silent=TRUE)
  options(scworkbench.writer_lock_timeout_seconds=old_timeout);file.create(release)
  deadline<-Sys.time()+20;while(isTRUE(wb_bundle_writer_lock_info(root)$locked)&&Sys.time()<deadline)Sys.sleep(0.05)
  stopifnot(inherits(contended,"try-error"),!isTRUE(wb_bundle_writer_lock_info(root)$locked))
  wb_finalize_recipient_bundle(b);wb_close_bundle(b);b<-NULL
  stopifnot(isTRUE(wb_bundle_validation_report(root,"recipient")$ok),isTRUE(wb_recipient_readiness(root)$ready))
  b<-wb_open_bundle(root,read_only=TRUE)
  stopifnot(nrow(wb_metadata_fields(b,FALSE))==1L)
  wb_close_bundle(b);b<-NULL
  bytes<-readBin(file.path(root,"db","app.sqlite"),"raw",n=file.info(file.path(root,"db","app.sqlite"))$size)
  manifest<-readBin(file.path(root,"manifest.json"),"raw",n=file.info(file.path(root,"manifest.json"))$size)
  host<-charToRaw(enc2utf8(normalizePath(work,winslash="/",mustWork=TRUE)))
  contains<-function(raw,needle)grepl(paste(format(needle),collapse=""),paste(format(raw),collapse=""),fixed=TRUE)
  stopifnot(!contains(bytes,host),!contains(manifest,host))
  TRUE
}
