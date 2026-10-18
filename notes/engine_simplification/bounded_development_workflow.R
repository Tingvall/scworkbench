args<-commandArgs(TRUE)
stopifnot(length(args)==3L)
.libPaths(c(args[[1]],args[[2]],.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
main<-function(){
  root<-args[[3]];stopifnot(!dir.exists(root));dir.create(root,recursive=TRUE)
  lib<-find.package('scworkbench')
  identity_files<-file.path(lib,c('R/scworkbench.rdb','R/scworkbench.rdx','libs/scworkbench.so'))
  identity_files<-identity_files[file.exists(identity_files)]
  identity<-vapply(identity_files,function(path)digest::digest(file=path,algo='sha256'),'')
  saveRDS(identity,file.path(root,'installed_identity.rds'),compress=FALSE)
  stopifnot(identical(as.numeric(getOption('scworkbench.max_dense_materialize_mb',256)),256))
  cat('BOUNDED_DEVELOPMENT_ONLY source=4000x1000 density=.05 zero_library=1 default_guard=256\n')
  cat('LIBRARY ',lib,'\n',sep='')
  print(system('ps -o pid,etime,pcpu,rss,args -C R',intern=TRUE))
  wb_operation_pack_load('scwbRNA',lib.loc=args[[2]])
  wb_operation_pack_load('scwbRepresentation',lib.loc=args[[2]])
  counts<-new.env(parent=emptyenv());counts$calls<-list();counts$time<-list()
  options(scwb.bounded.development.census=counts)
  ns<-asNamespace('scworkbench')
  trace_names<-c('.wb_operation_pack_v2_execute','.wb_operation_pack_v3_request',
    '.wb_operation_pack_v3_matrix_consumed_identity','.wb_operation_pack_matrix_stream_identity',
    '.wb_operation_pack_v3_space_content','.wb_operation_pack_v2_input_descriptor',
    '.wb_prov_table_content_sha256','.wb_prov_stored_table_content_sha256',
    '.wb_prov_file_tree_sha256','.wb_prov_sha256_file','.wb_manifest_registry_snapshot',
    '.wb_schema_status','.wb_session_checkpoint','.wb_session_source_identity',
    '.wb_session_validate_payloads','.wb_session_sqlite_backup',
    '.wb_operation_pack_v3_publish_materializations','.wb_operation_pack_v2_audit',
    '.wb_operation_pack_v3_model_tree_manifest','.wb_operation_pack_v3_full_space_assert_current')
  traced<-character()
  for(n in trace_names){
    if(!exists(n,envir=ns,inherits=FALSE))next
    trace(n,where=ns,print=FALSE,
      tracer=substitute({
        .scwb_probe_t<-proc.time()[['elapsed']]
        .scwb_probe_c<-getOption('scwb.bounded.development.census')
        .scwb_probe_c$calls[[NAME]]<-(.scwb_probe_c$calls[[NAME]]%||%0L)+1L
      },list(NAME=n)),
      exit=substitute({
        .scwb_probe_c<-getOption('scwb.bounded.development.census')
        .scwb_probe_c$time[[NAME]]<-(.scwb_probe_c$time[[NAME]]%||%0)+
          proc.time()[['elapsed']]-.scwb_probe_t
      },list(NAME=n)))
    traced<-c(traced,n)
  }
  on.exit({for(n in traced)try(untrace(n,where=ns),silent=TRUE)},add=TRUE)
  rows<-list();census<-list()
  io<-function(){z<-strsplit(readLines('/proc/self/io'),': *');
    setNames(vapply(z,function(x)as.numeric(x[2]),0),vapply(z,`[[`,'',1L))}
  measure<-function(phase,code){
    before_calls<-counts$calls;before_time<-counts$time;a<-io();p<-proc.time()
    profile<-file.path(root,paste0(phase,'.Rprof'))
    Rprof(profile,interval=.01);on.exit(Rprof(NULL))
    answer<-force(code);Rprof(NULL);p<-proc.time()-p;d<-io()-a
    rows[[length(rows)+1L]]<<-data.frame(phase=phase,elapsed=p[['elapsed']],user=p[['user.self']],
      system=p[['sys.self']],rchar=d[['rchar']],wchar=d[['wchar']],read_bytes=d[['read_bytes']],write_bytes=d[['write_bytes']])
    print(rows[[length(rows)]],row.names=FALSE);flush.console()
    write.csv(do.call(rbind,rows),file.path(root,'timings.csv'),row.names=FALSE)
    prof<-summaryRprof(profile)
    write.csv(prof$by.self,file.path(root,paste0(phase,'_self.csv')))
    write.csv(prof$by.total,file.path(root,paste0(phase,'_total.csv')))
    cat('PHASE_PROFILE ',phase,' sampled_seconds=',prof$sampling.time,'\n',sep='')
    print(head(prof$by.self,12L))
    for(n in names(counts$calls)){
      calls<-counts$calls[[n]]-if(is.null(before_calls[[n]]))0L else before_calls[[n]]
      elapsed<-counts$time[[n]]-if(is.null(before_time[[n]]))0 else before_time[[n]]
      if(calls)census[[length(census)+1L]]<<-data.frame(phase=phase,function_name=n,calls=calls,inclusive_elapsed=elapsed)
    }
    write.csv(do.call(rbind,census),file.path(root,'census.csv'),row.names=FALSE)
    invisible(answer)
  }
  set.seed(18L);cells<-paste0('cell_',seq_len(1000L));features<-paste0('feature_',seq_len(4000L))
  raw<-Matrix::rsparsematrix(4000L,1000L,density=.05)
  raw@x<-as.numeric(abs(round(raw@x*100))+1);dimnames(raw)<-list(features,cells);raw[,1L]<-0
  b<-measure('initialize_import',{
    b<-wb_init_bundle(file.path(root,'synthetic.bundle'));wb_define_cells(b,cells)
    wb_attach_matrix(b,'counts',raw,layer='counts',feature_type='gene');b
  })
  on.exit(try(wb_close_bundle(b),silent=TRUE),add=TRUE)
  s<-measure('durable_session_create',wb_session_create(b,file.path(root,'sessions'),'bounded'))
  norm<-measure('normalization',wb_session_run_op(s,b,'scwbrna::matrix_log_normalize',inputs=list(
    matrix='counts',cell_set='all',output_matrix_id='RNA_log_norm',scale_factor=10000,
    chunk_size=2000L,overwrite=FALSE)))
  hvg<-measure('hvg',wb_session_run_op(norm$session,b,'scwbrna::hvg_select',inputs=list(
    matrix='RNA_log_norm',cell_set='all',n_features=2000L,method='vst',chunk_size=256L,seed=1L)))
  pca<-measure('pca',wb_session_run_op(hvg$session,b,'scwbrepresentation::pca_fit',inputs=list(
    matrix='RNA_log_norm',features=wb_ref_run(hvg$run$run_id,'selected_features'),cell_set='all',
    n_components=50L,center=TRUE,scale=TRUE,backend='irlba',seed=1L,space_id_out='rna.pca',
    overwrite=FALSE,max_dense_gb=8,chunk_size=256L)))
  umap<-measure('umap',wb_session_run_op(pca$session,b,'scwbrepresentation::umap_fit',inputs=list(
    space=wb_ref_run(pca$run$run_id,'space'),cell_set='all',dims=1:30,space_id_out='rna.umap',
    n_neighbors=30L,min_dist=.3,spread=1,metric='euclidean',nn_method='nndescent',seed=1L)))
  measure('normalization_reference_check',{
    view<-wb_session_view(umap$session)
    for(part in wb_partition_axis(cells,128L)){
      input<-as.matrix(raw[,match(part,cells),drop=FALSE]);denom<-colSums(input);denom[denom<=0]<-Inf
      expected<-log1p(t(t(input)*(10000/denom)))
      actual<-as.matrix(wb_slice(view,'RNA_log_norm',features,part))
      stopifnot(identical(dimnames(actual),dimnames(expected)),max(abs(actual-expected))<1e-14)
    }
    stopifnot(as.integer(norm$run$outputs$summary$table$n_zero_library_cells)==1L)
  })
  outputs<-list(wb_ref_run(norm$run$run_id,'summary'),wb_ref_run(hvg$run$run_id,'selected_features'),
    wb_ref_run(hvg$run$run_id,'fit_summary'),wb_ref_run(pca$run$run_id,'loadings'),
    wb_ref_run(pca$run$run_id,'variance'),wb_ref_run(pca$run$run_id,'fit_summary'),wb_ref_run(umap$run$run_id,'model'))
  promotion<-measure('promotion',wb_session_promote_current(b,umap$session,outputs=outputs,fail_fast=TRUE))
  stopifnot(all(promotion$promoted$status=='ok'))
  measure('finalize_close',{wb_finalize_recipient_bundle(b);wb_close_bundle(b)})
  b<-measure('readonly_reopen',wb_open_bundle(file.path(root,'synthetic.bundle'),read_only=TRUE))
  stopifnot(all(c('rna.pca','rna.umap')%in%wb_spaces(b)$space_id));wb_close_bundle(b)
  stopifnot(identical(vapply(identity_files,function(path)digest::digest(file=path,algo='sha256'),''),identity),
    identical(as.numeric(getOption('scworkbench.max_dense_materialize_mb',256)),256))
  cat('BOUNDED_DEVELOPMENT_DURABLE_FOUR_OP_PROMOTE_FINALIZE_READONLY_OK\n')
}
main()
