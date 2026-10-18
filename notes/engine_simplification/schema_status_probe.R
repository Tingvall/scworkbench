args<-commandArgs(TRUE);.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
patch<-new.env(parent=asNamespace('scworkbench'));sys.source('R/schema_migrations.R',patch)
con<-DBI::dbConnect(RSQLite::SQLite(),args[[2]],flags=RSQLite::SQLITE_RO)
old<-get('.wb_schema_status',asNamespace('scworkbench'))
new<-patch$.wb_schema_status
expected<-old(con)
repetitions<-50L;rows<-list()
for(mode in c('repaired','source_patch_cold','source_patch_repeated','source_patch_explicit_full')){
  if(mode=='source_patch_cold')con@ref$wb_schema_structure_observation<-NULL
  n<-if(mode=='source_patch_cold')1L else repetitions
  t<-proc.time()
  for(i in seq_len(n)){
    actual<-if(mode=='repaired')old(con)else new(con,verify_structure=mode=='source_patch_explicit_full')
    stopifnot(identical(actual,expected))
  }
  t<-proc.time()-t
  rows[[length(rows)+1L]]<-data.frame(mode=mode,n=n,elapsed=t[['elapsed']],per_call=t[['elapsed']]/n)
}
DBI::dbDisconnect(con);print(do.call(rbind,rows),row.names=FALSE)
write.csv(do.call(rbind,rows),args[[3]],row.names=FALSE)
cat('SCHEMA_STATUS_SOURCE_PATCH_TIMINGS_IDENTICAL\n')
