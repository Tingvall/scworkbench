args <- commandArgs(TRUE)
.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages({library(SingleCellExperiment);library(Matrix);library(BPCells)})
root <- args[[2]]
stopifnot(!dir.exists(root));dir.create(root,recursive=TRUE)
source_path <- '/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds'
expected_sha <- '7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280'
rows <- list(); passes <- list()
io <- function() {
  z <- strsplit(readLines('/proc/self/io'),': *')
  setNames(vapply(z,function(x)as.numeric(x[2]),0),vapply(z,`[[`,'',1L))
}
measure <- function(phase,code) {
  a<-io();t<-proc.time();ans<-force(code);t<-proc.time()-t;d<-io()-a
  rows[[length(rows)+1L]] <<- data.frame(phase=phase,elapsed=t[['elapsed']],
    user=t[['user.self']],system=t[['sys.self']],rchar=d[['rchar']],wchar=d[['wchar']],
    read_bytes=d[['read_bytes']],write_bytes=d[['write_bytes']])
  print(rows[[length(rows)]],row.names=FALSE);flush.console()
  write.csv(do.call(rbind,rows),file.path(root,'timings.csv'),row.names=FALSE)
  ans
}
partition <- function(ids,size) split(ids,ceiling(seq_along(ids)/size))
write_space <- function(mat,path,id) {
  nr<-nrow(mat);nc<-ncol(mat);cr<-min(nr,1024L);cd<-min(nc,16L)
  stopifnot(rhdf5::h5createFile(path))
  rhdf5::h5createDataset(path,'coordinates',dims=dim(mat),chunk=c(cr,cd),
    storage.mode='double',level=0L)
  rhdf5::h5write(mat,path,'coordinates');rhdf5::h5write(rownames(mat),path,'cell_ids')
  rhdf5::h5write(colnames(mat),path,'dim_labels')
  h<-rhdf5::H5Fopen(path);on.exit(rhdf5::H5Fclose(h))
  attrs<-list(schema_version='scworkbench.dense-space.hdf5.v1',space_id=id,
    n_cells=as.integer(nr),n_dims=as.integer(nc),dtype='float64',
    endianness=.Platform$endian,chunk_rows=as.integer(cr),chunk_dims=as.integer(cd))
  for(n in names(attrs))rhdf5::h5writeAttribute(attrs[[n]],h,n)
}
# Match the engine table writer's default JSON precision intentionally; retain
# independent full-precision scientific RDS snapshots for numerical comparison.
write_table <- function(con,name,tab) {
  json<-vapply(seq_len(nrow(tab)),function(i)as.character(jsonlite::toJSON(
    as.list(tab[i,,drop=FALSE]),auto_unbox=TRUE,null='null')),character(1))
  DBI::dbWriteTable(con,name,data.frame(row_idx=seq_len(nrow(tab)),row_json=json))
}
cat('DIRECT_XENOPUS_NO_ENGINE_DISPATCH\n');print(Sys.info());print(.libPaths())
stopifnot(identical(measure('source_checksum',digest::digest(file=source_path,algo='sha256')),expected_sha))
counts<-measure('read_source_rds',{
  sce<-readRDS(source_path);assay(sce,'counts')
})
cells<-colnames(counts);features<-rownames(counts)
stopifnot(identical(dim(counts),c(31535L,13199L)))
saveRDS(list(cells=cells,features=features),file.path(root,'axes.rds'),compress=FALSE)
raw<-measure('write_reopen_source_bpcells',{
  BPCells::write_matrix_dir(counts,file.path(root,'counts'),compress=TRUE)
  BPCells::open_matrix_dir(file.path(root,'counts'))
})
norm_paths<-character();library_sizes<-setNames(numeric(length(cells)),cells)
measure('normalization_read_compute_write',{
  for(part in partition(cells,2000L)) {
    values<-methods::as(raw[,match(part,colnames(raw)),drop=FALSE],'dgCMatrix')
    library_size<-as.numeric(Matrix::colSums(values));denom<-library_size
    denom[!is.finite(denom)|denom<=0]<-Inf
    normalized<-log1p(t(t(as.matrix(values))*(10000/denom)))
    dimnames(normalized)<-list(features,part)
    sparse<-Matrix::Matrix(normalized,sparse=TRUE)
    if(!inherits(sparse,'dgCMatrix'))sparse<-methods::as(sparse,'generalMatrix')
    path<-file.path(root,paste0('norm_',length(norm_paths)+1L))
    BPCells::write_matrix_dir(BPCells::convert_matrix_type(sparse,'double'),path,compress=FALSE)
    norm_paths<-c(norm_paths,path);library_sizes[part]<-library_size
  }
})
norm<-measure('reopen_normalized_fragments',lapply(norm_paths,BPCells::open_matrix_dir))
stopifnot(length(norm)==7L)
indices<-measure('normalization_row_index_build',{
  lapply(seq_along(norm),function(i)BPCells::transpose_storage_order(norm[[i]],
    outdir=file.path(root,paste0('row_index_',i)),load_bytes=4194304L,sort_bytes=67108864L))
})
read_features<-function(ids) {
  pieces<-lapply(indices,function(mat)methods::as(
    mat[match(ids,rownames(mat)),,drop=FALSE],'dgCMatrix'))
  x<-do.call(cbind,pieces);dimnames(x)<-list(ids,cells);x
}
stats<-measure('hvg_read_compute',{
  pieces<-lapply(partition(features,256L),function(ids){
    x<-read_features(ids);n<-ncol(x);mu<-as.numeric(Matrix::rowMeans(x))
    ss<-as.numeric(Matrix::rowSums(x*x))
    variance<-pmax((ss-n*mu*mu)/(n-1L),0)
    detected<-as.numeric(Matrix::rowSums(x>0))
    data.frame(feature_id=ids,mean=mu,variance=variance,
      detected_cells=detected,detected_fraction=detected/max(n,1L))
  })
  stats<-do.call(rbind,pieces)
  stats$dispersion<-stats$variance/pmax(stats$mean,.Machine$double.eps)
  stats$score<-log1p(pmax(stats$dispersion,0));stats$method<-'vst';stats$matrix_id<-'RNA_log_norm'
  passes<-is.finite(stats$score)
  ord<-order(!passes,-stats$score,-stats$variance,stats$feature_id,na.last=TRUE)
  rank<-integer(nrow(stats));rank[ord]<-seq_along(ord)
  selected<-ord[passes[ord]];selected<-selected[seq_len(min(length(selected),2000L))]
  stats$selected<-FALSE;stats$selected[selected]<-TRUE;stats$rank<-rank
  stats<-stats[order(stats$rank),c('feature_id','rank','mean','variance','dispersion','score',
    'detected_cells','detected_fraction','selected','method','matrix_id')]
  rownames(stats)<-NULL;stats
})
selected<-stats$feature_id[stats$selected]
con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'tables.sqlite'))
measure('hvg_write_tables',write_table(con,'selected_features',stats))
pca<-measure('pca_read_compute',{
  blocks<-lapply(partition(selected,256L),function(ids)t(as.matrix(read_features(ids))))
  x<-do.call(cbind,blocks);dimnames(x)<-list(cells,selected)
  feature_mean<-colMeans(x);feature_var<-apply(x,2L,stats::var)
  keep<-is.finite(feature_var)&feature_var>0
  fit_features<-selected[keep];fit_x<-x[,keep,drop=FALSE]
  set.seed(1L);fit<-irlba::prcomp_irlba(fit_x,n=50L,center=TRUE,scale.=TRUE)
  labels<-paste0('PC',seq_len(50L));coords<-fit$x[,seq_len(50L),drop=FALSE]
  dimnames(coords)<-list(cells,labels)
  rotation<-fit$rotation[,seq_len(50L),drop=FALSE]
  if(is.null(rownames(rotation)))rownames(rotation)<-fit_features
  full_rotation<-matrix(0,length(selected),50L,dimnames=list(selected,labels))
  full_rotation[rownames(rotation),]<-rotation
  loadings<-data.frame(feature_id=rep(selected,times=50L),PC=rep(labels,each=length(selected)),
    component=rep(seq_len(50L),each=length(selected)),loading=as.numeric(full_rotation),
    matrix_id='RNA_log_norm',space_id='rna.pca')
  stdev<-as.numeric(fit$sdev[seq_len(50L)]);variance<-stdev^2
  variance_table<-data.frame(PC=labels,component=seq_len(50L),stdev=stdev,
    variance=variance,variance_explained=variance/sum(as.numeric(fit$sdev)^2),
    cumulative_variance_explained=cumsum(variance/sum(as.numeric(fit$sdev)^2)),
    matrix_id='RNA_log_norm',space_id='rna.pca')
  list(coords=coords,loadings=loadings,variance=variance_table,selected=selected)
})
measure('pca_write_hdf5_and_tables',{
  write_space(pca$coords,file.path(root,'pca.h5'),'rna.pca')
  write_table(con,'loadings',pca$loadings);write_table(con,'variance',pca$variance)
})
umap<-measure('umap_read_compute',{
  stopifnot(requireNamespace('uwot',quietly=TRUE),requireNamespace('rnndescent',quietly=TRUE))
  x<-rhdf5::h5read(file.path(root,'pca.h5'),'coordinates',index=list(NULL,1:30))
  dimnames(x)<-list(cells,paste0('PC',1:30))
  set.seed(1L)
  uwot::umap(x,n_neighbors=30L,min_dist=.3,metric='euclidean',nn_method='nndescent',
    spread=1,n_threads=1L,n_sgd_threads=1L,seed=1L,ret_model=TRUE,verbose=FALSE)
})
dimnames(umap$embedding)<-list(cells,c('x','y'))
measure('umap_write_coordinates_and_model',{
  write_space(umap$embedding,file.path(root,'umap.h5'),'rna.umap')
  dir.create(file.path(root,'model'));uwot::save_uwot(umap,file.path(root,'model','model.uwot'),verbose=FALSE)
})
measure('persist_full_precision_scientific_reference',{
  saveRDS(list(hvg=stats,pca=pca,umap=umap$embedding),file.path(root,'scientific_reference.rds'),compress=FALSE)
})
DBI::dbDisconnect(con)
measure('reopen_verify_all_written_outputs',{
  con<-DBI::dbConnect(RSQLite::SQLite(),file.path(root,'tables.sqlite'))
  stopifnot(nrow(DBI::dbReadTable(con,'selected_features'))==31535L,
    nrow(DBI::dbReadTable(con,'loadings'))==100000L)
  DBI::dbDisconnect(con)
  reread<-rhdf5::h5read(file.path(root,'pca.h5'),'coordinates')
  stopifnot(max(abs(reread-pca$coords))==0,
    identical(as.character(rhdf5::h5read(file.path(root,'pca.h5'),'cell_ids')),cells))
  stopifnot(max(abs(rhdf5::h5read(file.path(root,'umap.h5'),'coordinates')-umap$embedding))==0,
    identical(as.character(rhdf5::h5read(file.path(root,'umap.h5'),'cell_ids')),cells))
  loaded<-uwot::load_uwot(file.path(root,'model','model.uwot'),verbose=FALSE)
  stopifnot(max(abs(loaded$embedding-umap$embedding))==0)
})
measure('independent_all_normalized_value_verification',{
  for(i in seq_along(norm_paths)) {
    mat<-BPCells::open_matrix_dir(norm_paths[[i]])
    for(ids in partition(colnames(mat),128L)) {
      expected<-counts[,match(ids,cells),drop=FALSE]
      denom<-as.numeric(Matrix::colSums(expected));denom[denom<=0|!is.finite(denom)]<-Inf
      expected<-log1p(t(t(as.matrix(expected))*(10000/denom)))
      actual<-as.matrix(mat[,match(ids,colnames(mat)),drop=FALSE])
      stopifnot(identical(dimnames(actual),dimnames(expected)),max(abs(actual-expected))<1e-14)
    }
  }
})
jsonlite::write_json(list(source_sha256=expected_sha,dimensions=dim(counts),
  normalized_fragments=7L,normalization_cell_chunks=7L,hvg_feature_chunks=124L,
  pca_feature_chunks=8L,full_passes=list(source_checksum=1L,read_source_rds=1L,
  source_bpcells_write=1L,normalization_read=1L,row_index_build_phase=1L,
  hvg_selected_feature_coverage=1L,pca_2000_feature_coverage=1L,verification_norm=1L),
  storage=list(source='BPCells compressed',normalized='BPCells uncompressed double',
    pca='rhdf5 dense-space.hdf5.v1',umap='rhdf5 dense-space.hdf5.v1',
    tables='SQLite JSON row schema differs; same default JSON precision',model='uwot save_uwot'),
  package_versions=setNames(lapply(c('BPCells','Matrix','rhdf5','irlba','uwot','rnndescent'),
    function(x)as.character(packageVersion(x))),c('BPCells','Matrix','rhdf5','irlba','uwot','rnndescent'))),
  file.path(root,'completion.json'),pretty=TRUE,auto_unbox=TRUE)
cat('DIRECT_XENOPUS_READ_COMPUTE_WRITE_REOPEN_ALL_VALUES_OK\n')
