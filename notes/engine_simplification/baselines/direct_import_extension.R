# Separate, explicitly timed import-IO completion after direct_xenopus.R.
# Do not edit/restart the scientific run to add these source payloads.
args<-commandArgs(TRUE);.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages(library(SingleCellExperiment))
root<-args[[2]];stopifnot(file.exists(file.path(root,'completion.json')))
rows<-list()
measure<-function(phase,code){
  io<-function(){z<-strsplit(readLines('/proc/self/io'),': *');
    setNames(vapply(z,function(x)as.numeric(x[2]),0),vapply(z,`[[`,'',1L))}
  a<-io();t<-proc.time();ans<-force(code);t<-proc.time()-t;d<-io()-a
  rows[[length(rows)+1L]]<<-data.frame(phase=phase,elapsed=t[['elapsed']],
    user=t[['user.self']],system=t[['sys.self']],rchar=d[['rchar']],wchar=d[['wchar']],
    read_bytes=d[['read_bytes']],write_bytes=d[['write_bytes']])
  print(rows[[length(rows)]],row.names=FALSE)
  write.csv(do.call(rbind,rows),file.path(root,'import_extension_timings.csv'),row.names=FALSE)
  ans
}
sce<-measure('extension_read_source_rds_again',readRDS(
  '/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds'))
axes<-readRDS(file.path(root,'axes.rds'))
stopifnot(identical(colnames(sce),axes$cells),identical(rownames(sce),axes$features))
write_space<-function(mat,path,id){
  nr<-nrow(mat);nc<-ncol(mat);cr<-min(nr,1024L);cd<-min(nc,16L)
  stopifnot(rhdf5::h5createFile(path))
  rhdf5::h5createDataset(path,'coordinates',dims=dim(mat),chunk=c(cr,cd),
    storage.mode='double',level=0L)
  rhdf5::h5write(mat,path,'coordinates');rhdf5::h5write(axes$cells,path,'cell_ids')
  labels<-colnames(mat);if(is.null(labels))labels<-paste0('dim',seq_len(nc))
  rhdf5::h5write(labels,path,'dim_labels')
  h<-rhdf5::H5Fopen(path);on.exit(rhdf5::H5Fclose(h))
  attrs<-list(schema_version='scworkbench.dense-space.hdf5.v1',space_id=id,
    n_cells=as.integer(nr),n_dims=as.integer(nc),dtype='float64',endianness=.Platform$endian,
    chunk_rows=as.integer(cr),chunk_dims=as.integer(cd))
  for(n in names(attrs))rhdf5::h5writeAttribute(attrs[[n]],h,n)
}
measure('extension_write_metadata_axes_and_source_reductions',{
  con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'source_metadata.sqlite'))
  col<-as.data.frame(colData(sce));row<-as.data.frame(rowData(sce))
  # Include ordered axes separately, even when the source rowData has no fields.
  DBI::dbWriteTable(con,'cells',data.frame(ordinal=seq_along(axes$cells),cell_id=axes$cells))
  DBI::dbWriteTable(con,'features',data.frame(ordinal=seq_along(axes$features),feature_id=axes$features))
  col$cell_id<-axes$cells;row$feature_id<-axes$features
  DBI::dbWriteTable(con,'cell_metadata',col);DBI::dbWriteTable(con,'feature_metadata',row)
  DBI::dbDisconnect(con)
  saveRDS(list(colData=colData(sce),rowData=rowData(sce),metadata=metadata(sce)),
    file.path(root,'source_metadata_lossless.rds'),compress=FALSE)
  reductions<-reducedDims(sce)
  for(n in names(reductions)){
    mat<-as.matrix(reductions[[n]]);storage.mode(mat)<-'double'
    stopifnot(nrow(mat)==length(axes$cells));rownames(mat)<-axes$cells
    write_space(mat,file.path(root,paste0('source_',n,'.h5')),n)
  }
})
measure('extension_reopen_compare_source_metadata_axes_reductions',{
  con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'source_metadata.sqlite'))
  stopifnot(identical(DBI::dbReadTable(con,'cells')$cell_id,axes$cells),
    identical(DBI::dbReadTable(con,'features')$feature_id,axes$features),
    identical(DBI::dbReadTable(con,'cell_metadata')$cell_id,axes$cells),
    identical(DBI::dbReadTable(con,'feature_metadata')$feature_id,axes$features))
  got<-DBI::dbReadTable(con,'cell_metadata')
  for(n in names(colData(sce)))stopifnot(identical(as.character(got[[n]]),as.character(colData(sce)[[n]])))
  got<-DBI::dbReadTable(con,'feature_metadata')
  for(n in names(rowData(sce)))stopifnot(identical(as.character(got[[n]]),as.character(rowData(sce)[[n]])))
  DBI::dbDisconnect(con)
  lossless<-readRDS(file.path(root,'source_metadata_lossless.rds'))
  stopifnot(identical(lossless$colData,colData(sce)),identical(lossless$rowData,rowData(sce)),
    identical(lossless$metadata,metadata(sce)))
  for(n in names(reducedDims(sce)))stopifnot(max(abs(
    rhdf5::h5read(file.path(root,paste0('source_',n,'.h5')),'coordinates')-
      as.matrix(reducedDim(sce,n))))==0)
})
cat('DIRECT_SOURCE_METADATA_AXES_REDUCTIONS_REOPEN_EXACT_OK\n')
