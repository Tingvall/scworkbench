# Efficient ordinary direct-table alternative; separate evidence, never replaces
# or edits the completed matched-JSON phase records.
args<-commandArgs(TRUE);.libPaths(c(args[[1]],.libPaths()))
root<-args[[2]];stopifnot(file.exists(file.path(root,'completion.json')))
rows<-list()
measure<-function(phase,code){
  t<-proc.time();ans<-force(code);t<-proc.time()-t
  rows[[length(rows)+1L]]<<-data.frame(phase=phase,elapsed=t[['elapsed']],
    user=t[['user.self']],system=t[['sys.self']])
  print(rows[[length(rows)]],row.names=FALSE)
  write.csv(do.call(rbind,rows),file.path(root,'native_table_extension_timings.csv'),row.names=FALSE)
  ans
}
ref<-measure('native_extension_read_precision_reference',readRDS(file.path(root,'scientific_reference.rds')))
measure('native_sqlite_tables_write_close_reopen_compare',{
  con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'native_tables_verified.sqlite'))
  tables<-list(selected_features=ref$hvg,loadings=ref$pca$loadings,variance=ref$pca$variance)
  types<-lapply(tables,function(tab)vapply(tab,typeof,''))
  saveRDS(types,file.path(root,'native_table_types.rds'),compress=FALSE)
  for(n in names(tables))DBI::dbWriteTable(con,n,tables[[n]])
  DBI::dbDisconnect(con)
  con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'native_tables_verified.sqlite'))
  types<-readRDS(file.path(root,'native_table_types.rds'))
  for(n in names(tables)){
    got<-DBI::dbReadTable(con,n)
    for(field in names(types[[n]])[types[[n]]=='logical']){
      stopifnot(all(is.na(got[[field]])|got[[field]]%in%c(0L,1L)))
      got[[field]]<-as.logical(got[[field]])
    }
    stopifnot(identical(got,tables[[n]]))
  }
  DBI::dbDisconnect(con)
})
measure('native_alternative_pca_hdf5_write_reopen',{
  mat<-ref$pca$coords;path<-file.path(root,'native_alternative_pca.h5')
  stopifnot(rhdf5::h5createFile(path))
  cr<-min(nrow(mat),1024L);cd<-min(ncol(mat),16L)
  rhdf5::h5createDataset(path,'coordinates',dims=dim(mat),chunk=c(cr,cd),storage.mode='double',level=0L)
  rhdf5::h5write(mat,path,'coordinates');rhdf5::h5write(rownames(mat),path,'cell_ids')
  rhdf5::h5write(colnames(mat),path,'dim_labels')
  h<-rhdf5::H5Fopen(path)
  attrs<-list(schema_version='scworkbench.dense-space.hdf5.v1',space_id='rna.pca',
    n_cells=as.integer(nrow(mat)),n_dims=as.integer(ncol(mat)),dtype='float64',endianness=.Platform$endian,
    chunk_rows=as.integer(cr),chunk_dims=as.integer(cd))
  for(n in names(attrs))rhdf5::h5writeAttribute(attrs[[n]],h,n)
  rhdf5::H5Fclose(h)
  stopifnot(max(abs(rhdf5::h5read(path,'coordinates')-mat))==0)
})
cat('DIRECT_NATIVE_SQLITE_FULL_PRECISION_TABLES_REOPEN_EXACT_OK\n')
