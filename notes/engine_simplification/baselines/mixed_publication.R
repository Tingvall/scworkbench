args <- commandArgs(TRUE)
.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2]]; dir.create(root,recursive=TRUE,showWarnings=FALSE)
rows <- list()
measure <- function(case,code) {
  proc_io <- function() {
    z <- strsplit(readLines('/proc/self/io'),': *')
    setNames(vapply(z,function(x) as.numeric(x[2]),0),vapply(z,`[[`,'',1L))
  }
  a <- proc_io(); t <- proc.time(); answer <- force(code); t <- proc.time()-t
  d <- proc_io()-a
  rows[[length(rows)+1L]] <<- data.frame(case=case,elapsed=t[['elapsed']],
    user=t[['user.self']],system=t[['sys.self']],rchar=d[['rchar']],
    wchar=d[['wchar']],read_bytes=d[['read_bytes']],write_bytes=d[['write_bytes']])
  print(rows[[length(rows)]],row.names=FALSE)
  write.csv(do.call(rbind,rows),file.path(root,'mixed.csv'),row.names=FALSE)
  answer
}
cells <- paste0('c',seq_len(300L)); features <- paste0('f',seq_len(25L))
set.seed(4)
input <- list(cells=cells,features=features,
  scores=setNames(rnorm(length(cells)),cells),
  space=data.frame(cell_id=cells,x=rnorm(length(cells)),y=rnorm(length(cells))))
input_file <- file.path(root,'input.rds'); saveRDS(input,input_file,compress=FALSE)
compute <- function(x) list(
  vector=wb_prim_cell_vector(x$scores,value_type='continuous',meta=list(label='score')),
  family=wb_prim_cell_vector_family(rep(c('A','B'),each=length(cells)),
    rep(cells,2L),rep(x$scores,2L),value_type='continuous'),
  features=wb_prim_feature_table(data.frame(feature_id=features,score=seq_along(features))),
  # Existing table JSON uses four decimal places; retain the failed unrounded
  # pilot separately. This storage fixture declares that precision explicitly.
  summary=wb_prim_obs_table(data.frame(n=length(cells),mean=round(mean(x$scores),4L))),
  path=wb_prim_path_2d_family(rep('p',10L),seq_len(10L),seq_len(10L),seq_len(10L)^2))
expected <- compute(input)
measure('direct_complete_read_compute_write_reopen',{
  x <- readRDS(input_file); output <- compute(x)
  con <- DBI::dbConnect(RSQLite::SQLite(),file.path(root,'direct.sqlite'))
  for (name in c('features','summary')) DBI::dbWriteTable(con,name,output[[name]]$table)
  DBI::dbWriteTable(con,'space',x$space); DBI::dbDisconnect(con)
  for (name in c('vector','family','path')) saveRDS(output[[name]],
    file.path(root,paste0(name,'.rds')),compress=FALSE)
  saveRDS(list(contract='storage benchmark',coefficients=x$scores),
    file.path(root,'model.rds'),compress=FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(),file.path(root,'direct.sqlite'))
  stopifnot(identical(DBI::dbReadTable(con,'features'),output$features$table),
    identical(DBI::dbReadTable(con,'space'),x$space))
  DBI::dbDisconnect(con)
  for (name in c('vector','family','path')) stopifnot(identical(
    readRDS(file.path(root,paste0(name,'.rds'))),output[[name]]))
  stopifnot(identical(readRDS(file.path(root,'model.rds'))$coefficients,x$scores))
})
bundle <- file.path(root,'mixed.bundle')
b <- measure('engine_initialize_import',{
  x <- readRDS(input_file); b <- wb_init_bundle(bundle); wb_define_cells(b,x$cells)
  wb_attach_matrix(b,'counts',matrix(0,length(features),length(cells),
    dimnames=list(features,cells)),layer='counts',feature_type='gene')
  wb_attach_space(b,'latent',x$space); b
})
output <- measure('engine_read_compute',compute(readRDS(input_file)))
model <- wb_prim_model_ref('latent','latent',engine='monocle3')
model$model_type <- 'monocle3'
model$model_obj <- list(contract='storage benchmark',coefficients=input$scores)
output$model <- model
# Synthetic storage exercise, not a scientific dispatch: the registered core
# operation supplies its promotable terminal name, while each actual primitive
# is dispatched by kind to the existing promoter. No new executor/registry.
runs <- lapply(output,function(primitive) wb_new_run('metadata_cell_vector',
  inputs=list(cell_set='all',parents=character()),params=list(),
  outputs=list(vector=primitive)))
run_ids <- vapply(runs,`[[`,'','run_id')
names(runs) <- run_ids
promoted <- measure('engine_atomic_promotion',wb_promote_analysis(b,
  runs,head_run_id=run_ids,fail_fast=TRUE))
measure('engine_finalize_readonly_reopen_load',{
  wb_finalize_recipient_bundle(b); wb_close_bundle(b)
  b <- wb_open_bundle(bundle,read_only=TRUE)
  for(name in names(expected)) {
    rid <- run_ids[match(name,names(output))]
    id <- promoted$promoted$artifact_id[promoted$promoted$run_id==rid]
    got <- wb_art_load(b,id)
    stopifnot(identical(unclass(got),unclass(expected[[name]])))
  }
  rid <- run_ids[match('model',names(output))]
  id <- promoted$promoted$artifact_id[promoted$promoted$run_id==rid]
  stopifnot(identical(wb_art_load(b,id)$model_obj$coefficients,input$scores))
  wb_close_bundle(b)
})
cat('MIXED_PUBLICATION_VALUES_REOPEN_OK\n')
