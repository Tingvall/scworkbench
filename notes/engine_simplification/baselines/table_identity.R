args <- commandArgs(TRUE)
.libPaths(c(args[[1]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
out <- args[[2]]; dir.create(out, recursive = TRUE, showWarnings = FALSE)
rows <- list()
measure <- function(case, n, expr) {
  gc(); t <- proc.time(); answer <- force(expr); t <- proc.time() - t
  rows[[length(rows)+1L]] <<- data.frame(case=case, n=n,
    elapsed=unname(t[['elapsed']]), user=unname(t[['user.self']]),
    system=unname(t[['sys.self']]), sha256=answer)
  print(rows[[length(rows)]], row.names=FALSE)
  write.csv(do.call(rbind,rows),file.path(out,'table_identity.csv'),row.names=FALSE)
}
for (n in c(100L,1000L,5000L)) {
  tab <- data.frame(id=paste0('row_',seq_len(n)),
    number=rep(c(NA_real_,0,1.2,-4.5,1e-10,Inf),length.out=n),
    count=rep(c(NA_integer_,1L,2L),length.out=n),
    label=rep(c(NA_character_,'Unicode α','quote" slash\\',''),length.out=n),
    flag=rep(c(TRUE,FALSE,NA),length.out=n),stringsAsFactors=FALSE)
  prim <- wb_prim_obs_table(tab, table_type='baseline', entity_kind='row',
    meta=list(label='identity parity',version=1L))
  measure('complete_table_hash',n,scworkbench:::.wb_prov_table_content_sha256(prim))
  measure('object_fold_only',n,{
    state <- paste(rep('0',64),collapse='')
    row <- paste(rep('a',64),collapse='')
    for(i in seq_len(n)) state <- scworkbench:::.wb_prov_sha256_object(
      list(previous=state,row_sha256=row))
    state
  })
}
cat('TABLE_IDENTITY_BASELINE_OK\n')
