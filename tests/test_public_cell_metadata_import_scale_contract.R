test_public_cell_metadata_import_scale_contract <- function() {
  root<-tempfile("scwb_metadata_import_scale_");work<-tempfile("scwb_metadata_import_scale_source_");dir.create(work)
  b<-wb_init_bundle(root,overwrite=TRUE);on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(c(root,work),recursive=TRUE,force=TRUE)},add=TRUE)
  n<-120895L;ids<-sprintf("cell_%06d",seq_len(n));wb_define_cells(b,ids)
  set.seed(270605L);order<-sample.int(n)
  table<-data.frame(
    stage=c("egg","larva","pupa","adult")[1L+order%%4L],
    cell_key=ids[order], batch=as.integer(1L+order%%5L),
    score=as.numeric(order)/n, pass=order%%7L!=0L,
    stringsAsFactors=FALSE,check.names=FALSE
  )
  path<-file.path(work,"honeybee_metadata.csv");utils::write.csv(table,path,row.names=FALSE,quote=TRUE)
  source<-wb_source_input(path=path,source_id="honeybee_scale",accession="fixture-honeybee-scale",role="cell_metadata",format="csv",scope="external_file")
  started<-proc.time()[["elapsed"]]
  result<-wb_metadata_import(b,path,"cell_key",source)
  elapsed<-proc.time()[["elapsed"]]-started
  stopifnot(result$counts$matched==n,result$counts$unknown==0L,nrow(result$fields)==4L)
  probe_idx<-c(1L,2L,n%/%2L,n-1L,n)
  probe<-wb_meta(b,cells=ids[probe_idx],cols=c("cell_id","stage","batch","score","pass"))
  stopifnot(identical(as.character(probe$cell_id),ids[probe_idx]),
            identical(as.character(probe$stage),c("egg","larva","pupa","adult")[1L+probe_idx%%4L]),
            identical(as.integer(probe$batch),as.integer(1L+probe_idx%%5L)),
            isTRUE(all.equal(as.numeric(probe$score),as.numeric(probe_idx)/n)))
  evidence<-wb_art_load(b,result$report_artifact_id,"obs_table")
  stopifnot(nrow(evidence$table)==4L,evidence$meta$rejected_evidence$limit==100L,
            evidence$meta$counts$matched==n)
  message(sprintf("metadata import scale evidence: rows=%d fields=%d evidence_rows=%d elapsed=%.3fs",n,4L,nrow(evidence$table),elapsed))
  TRUE
}
