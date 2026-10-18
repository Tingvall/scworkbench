# Frozen-candidate affected-workflow harness. Root reviews/pins before running.
# Usage: Rscript THIS.R INSTALLED_CORE_LIBRARY NEW_CHAMBER DIRECT_REFERENCE_ROOT [PACK_LIBRARY [ORIGINAL_REFERENCE_ROOT]]
args<-commandArgs(TRUE);stopifnot(length(args)%in%c(3L,4L,5L))
pack_library<-if(length(args)>=4L)args[[4L]] else
  '/tmp/scwb-matrix-streaming-forge-20261018/verified-library'
.libPaths(c(args[[1]],pack_library,.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
`%||%`<-function(x,y)if(is.null(x))y else x
root<-args[[2]];direct<-args[[3]]
original_direct<-if(length(args)==5L)args[[5L]] else direct
stopifnot(!dir.exists(root),file.exists(file.path(direct,'completion.json')))
dir.create(root,recursive=TRUE)
writeLines(capture.output(sessionInfo()),file.path(root,'session_info.txt'))
write.csv(data.frame(variable=c('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'),
  value=Sys.getenv(c('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'),unset='<unset>')),
  file.path(root,'thread_environment.csv'),row.names=FALSE)
source_path<-'/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds'
guard_before<-getOption('scworkbench.max_dense_materialize_mb',256)
stopifnot(identical(as.numeric(guard_before),256))
cat('ORDINARY_DENSE_GUARD_MB ',guard_before,'\n',sep='')
expected_reference_sha<-Sys.getenv('SCWB_DIRECT_REFERENCE_SHA256',
  'bb8a84d8cd68c494f7735509539d2b5362a2f257f511f05ca3cabdf4874ee5fb')
stopifnot(grepl('^[a-f0-9]{64}$',expected_reference_sha),
  identical(digest::digest(file=file.path(direct,'scientific_reference.rds'),algo='sha256'),
  expected_reference_sha),
  identical(digest::digest(file=file.path(direct,'axes.rds'),algo='sha256'),
    '3eff7c4344afbf4a5f58c7643a167bf454f9160bcad5351945d9aa1d0e398ed5'))
if(!identical(original_direct,direct)) {
  direct_record<-jsonlite::read_json(file.path(direct,'completion.json'))
  stopifnot(identical(direct_record$normalization_transport,
    'existing_native_matrix_market_15g_roundtrip_v1'),
    identical(digest::digest(file=file.path(original_direct,'scientific_reference.rds'),algo='sha256'),
      'bb8a84d8cd68c494f7735509539d2b5362a2f257f511f05ca3cabdf4874ee5fb'))
}
reference<-readRDS(file.path(direct,'scientific_reference.rds'))
original_reference<-readRDS(file.path(original_direct,'scientific_reference.rds'))
axes<-readRDS(file.path(direct,'axes.rds'));cells<-axes$cells;features<-axes$features
stopifnot(identical(c(length(features),length(cells)),c(31535L,13199L)))
rows<-list();census<-new.env(parent=emptyenv());census$counts<-list();census$elapsed<-list()
census$file_bytes<-list();census$source_checks<-list();census$semantic_projections<-list()
options(scwb.engine.benchmark.census=census)
trace_names<-c('wb_source_sha256','.wb_session_validate_source',
  '.wb_session_validate_payloads','.wb_session_checkpoint','.wb_session_sqlite_backup',
  '.wb_operation_pack_v3_matrix_consumed_identity','.wb_operation_pack_matrix_stream_identity',
  '.wb_prov_file_tree_sha256','.wb_prov_sha256_file','.wb_prov_table_content_sha256',
  '.wb_prov_stored_table_content_sha256','.wb_session_source_identity',
  '.wb_operation_pack_registry_snapshot','.wb_manifest_registry_snapshot',
  '.wb_operation_pack_v3_publish_materializations','.wb_matrix_stream_reader')
ns<-asNamespace('scworkbench');traced<-character();missing<-character()
for(name in trace_names){
  if(!exists(name,envir=ns,inherits=FALSE)){missing<-c(missing,name);next}
  trace(name,where=ns,print=FALSE,
    tracer=substitute({
      .scwb_census_start<-proc.time()[['elapsed']]
      .scwb_census<-getOption('scwb.engine.benchmark.census')
      .scwb_census$counts[[NAME]]<-(.scwb_census$counts[[NAME]]%||%0L)+1L
      if(NAME%in%c('wb_source_sha256','.wb_prov_sha256_file'))
        .scwb_census$file_bytes[[NAME]]<-(.scwb_census$file_bytes[[NAME]]%||%0)+file.info(path)$size
      if(NAME=='.wb_operation_pack_v3_matrix_consumed_identity')
        .scwb_census$source_checks[[length(.scwb_census$source_checks)+1L]]<-
          data.frame(matrix_id=matrix_id,phase=phase)
      if(NAME=='.wb_operation_pack_matrix_stream_identity')
        .scwb_census$semantic_projections[[length(.scwb_census$semantic_projections)+1L]]<-
          data.frame(features=length(features),cells=length(cells),chunk_size=chunk_size)
    },list(NAME=name)),
    exit=substitute({
      .scwb_census<-getOption('scwb.engine.benchmark.census')
      .scwb_census$elapsed[[NAME]]<-(.scwb_census$elapsed[[NAME]]%||%0)+
        proc.time()[['elapsed']]-.scwb_census_start
    },list(NAME=name)))
  traced<-c(traced,name)
}
io<-function(){z<-strsplit(readLines('/proc/self/io'),': *');
  setNames(vapply(z,function(x)as.numeric(x[2]),0),vapply(z,`[[`,'',1L))}
measure<-function(phase,code){
  a<-io();t<-proc.time();ans<-force(code);t<-proc.time()-t;d<-io()-a
  rows[[length(rows)+1L]]<<-data.frame(phase=phase,elapsed=t[['elapsed']],
    user=t[['user.self']],system=t[['sys.self']],rchar=d[['rchar']],wchar=d[['wchar']],
    read_bytes=d[['read_bytes']],write_bytes=d[['write_bytes']])
  print(rows[[length(rows)]],row.names=FALSE);flush.console()
  write.csv(do.call(rbind,rows),file.path(root,'timings.csv'),row.names=FALSE)
  names<-names(census$counts)
  write.csv(data.frame(function_name=names,calls=vapply(census$counts,as.integer,1L),
    inclusive_elapsed=vapply(names,function(n)census$elapsed[[n]]%||%0,0),
    explicitly_traced_file_bytes=vapply(names,function(n)census$file_bytes[[n]]%||%NA_real_,0)),
    file.path(root,'trace_census.csv'),row.names=FALSE)
  if(length(census$source_checks))write.csv(do.call(rbind,census$source_checks),
    file.path(root,'full_matrix_source_checks.csv'),row.names=FALSE)
  if(length(census$semantic_projections))write.csv(do.call(rbind,census$semantic_projections),
    file.path(root,'semantic_projection_shapes.csv'),row.names=FALSE)
  invisible(ans)
}
numeric_equal<-function(actual,expected,atol,rtol,label){
  stopifnot(identical(dim(actual),dim(expected)),length(actual)==length(expected),
    all(is.finite(actual)),all(is.finite(expected)))
  delta<-abs(actual-expected)
  if(any(delta>atol+rtol*abs(expected)))stop(label,' numerical comparison failed; max abs=',max(delta))
  cat('NUMERICAL_PASS ',label,' max_abs=',max(delta),' atol=',atol,' rtol=',rtol,'\n',sep='')
}
space_values<-function(bundle,id){
  x<-wb_space(bundle,id,cells=cells)
  if(is.data.frame(x)){
    stopifnot(identical(as.character(x$cell_id),cells))
    x<-as.matrix(x[,setdiff(names(x),'cell_id'),drop=FALSE]);rownames(x)<-cells
  }
  stopifnot(identical(rownames(x),cells));x
}
inputs<-list(
  normalization=list(matrix='counts',cell_set='all',output_matrix_id='RNA_log_norm',
    scale_factor=10000,chunk_size=2000L,overwrite=FALSE),
  hvg=list(matrix='RNA_log_norm',cell_set='all',n_features=2000L,method='vst',chunk_size=256L,seed=1L),
  pca=list(matrix='RNA_log_norm',cell_set='all',n_components=50L,center=TRUE,scale=TRUE,
    backend='irlba',seed=1L,space_id_out='rna.pca',overwrite=FALSE,max_dense_gb=8,chunk_size=256L),
  umap=list(cell_set='all',dims=1:30,space_id_out='rna.umap',n_neighbors=30L,
    min_dist=.3,spread=1,metric='euclidean',nn_method='nndescent',seed=1L))
saveRDS(inputs,file.path(root,'declared_scientific_inputs.rds'),compress=FALSE)
source<-measure('source_input',wb_source_input(path=source_path,
  source_id='aztekin_tail_2019_sce_rds',accession='not_supplied',role='source_object',
  format='rds',scope='external_file'))
stopifnot(identical(source$sha256,'7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280'))
preflight<-measure('source_preflight',wb_source_preflight(list(inputs=list(source))))
stopifnot(isTRUE(preflight$valid),nrow(preflight$diagnostics)==0L)
bundle_path<-file.path(root,'xenopus.bundle')
b<-measure('fresh_import',wb_bundle_from_sce(source_path,bundle_path,
  source_identity=preflight$source_identity,created_by='forge_engine_simplification_acceptance'))
stopifnot(identical(wb_cells(b,'all'),cells),identical(wb_features(b,'counts')$feature_id,features))
original_spaces<-wb_spaces(b)$space_id
original_coordinates<-setNames(lapply(original_spaces,function(id)space_values(b,id)),original_spaces)
saveRDS(original_coordinates,file.path(root,'original_imported_spaces.rds'),compress=FALSE)
wb_operation_pack_load('scwbRNA',lib.loc=pack_library)
wb_operation_pack_load('scwbRepresentation',lib.loc=pack_library)
write.csv(wb_operation_packs(),file.path(root,'activated_pack_identities.csv'),row.names=FALSE)
s<-measure('durable_session_create',wb_session_create(b,file.path(root,'sessions'),'baseline_rna'))
norm<-measure('normalization',wb_session_run_op(s,b,'scwbrna::matrix_log_normalize',inputs=inputs$normalization))
hvg<-measure('hvg',wb_session_run_op(norm$session,b,'scwbrna::hvg_select',inputs=inputs$hvg))
inputs$pca$features<-wb_ref_run(hvg$run$run_id,'selected_features')
pca<-measure('pca',wb_session_run_op(hvg$session,b,'scwbrepresentation::pca_fit',inputs=inputs$pca))
inputs$umap$space<-wb_ref_run(pca$run$run_id,'space')
umap<-measure('umap',wb_session_run_op(pca$session,b,'scwbrepresentation::umap_fit',inputs=inputs$umap))
for(pair in list(list(run=norm$run,input=inputs$normalization),list(run=hvg$run,input=inputs$hvg),
    list(run=pca$run,input=inputs$pca),list(run=umap$run,input=inputs$umap))){
  keys<-setdiff(names(pair$input),c('matrix','cell_set','features','space'))
  stopifnot(all(keys%in%names(pair$run$params)))
  for(key in keys){
    actual<-unlist(pair$run$params[[key]],use.names=FALSE)
    expected<-unlist(pair$input[[key]],use.names=FALSE)
    stopifnot(isTRUE(all.equal(actual,expected,check.attributes=FALSE)))
  }
}
s<-umap$session;view<-wb_session_view(s)
measure('scientific_direct_comparison',{
  tab<-hvg$run$outputs$selected_features$table
  stopifnot(identical(names(tab),names(reference$hvg)),
    identical(tab$feature_id,reference$hvg$feature_id),
    identical(as.integer(tab$rank),as.integer(reference$hvg$rank)),
    identical(as.logical(tab$selected),as.logical(reference$hvg$selected)),
    identical(tab$method,reference$hvg$method),identical(tab$matrix_id,reference$hvg$matrix_id))
  for(n in c('mean','variance','dispersion','score','detected_cells','detected_fraction'))
    numeric_equal(as.numeric(tab[[n]]),as.numeric(reference$hvg[[n]]),1e-12,1e-10,paste0('HVG_',n))
  coords<-space_values(view,'rna.pca');expected<-reference$pca$coords
  stopifnot(identical(dimnames(coords),dimnames(expected)))
  jsonlite::write_json(list(
    reference_sha256=expected_reference_sha,
    exact_input=identical(unname(coords[,1:30,drop=FALSE]),unname(expected[,1:30,drop=FALSE])),
    max_abs_input_difference=max(abs(coords[,1:30,drop=FALSE]-expected[,1:30,drop=FALSE])),
    interpretation='Actual leading PCA coordinates consumed by each end-to-end UMAP; no conditional rerun substituted'),
    file.path(root,'umap_input_comparison.json'),auto_unbox=TRUE,pretty=TRUE,digits=NA)
  signs<-sign(colSums(coords*expected));stopifnot(all(signs!=0))
  numeric_equal(sweep(coords,2L,signs,'*'),expected,1e-7,1e-6,'PCA_signed_coordinates')
  loadings<-pca$run$outputs$loadings$table;expected_loadings<-reference$pca$loadings
  stopifnot(identical(names(loadings),names(expected_loadings)))
  for(n in setdiff(names(loadings),'loading'))
    stopifnot(identical(loadings[[n]],expected_loadings[[n]]))
  numeric_equal(as.numeric(loadings$loading)*signs[as.integer(loadings$component)],
    as.numeric(expected_loadings$loading),1e-7,1e-6,'PCA_signed_loadings')
  variance<-pca$run$outputs$variance$table
  stopifnot(identical(names(variance),names(reference$pca$variance)))
  for(n in c('PC','component','matrix_id','space_id'))
    stopifnot(identical(variance[[n]],reference$pca$variance[[n]]))
  for(n in c('stdev','variance','variance_explained','cumulative_variance_explained'))
    numeric_equal(as.numeric(variance[[n]]),as.numeric(reference$pca$variance[[n]]),0,1e-8,paste0('PCA_',n))
  coords<-space_values(view,'rna.umap')
  stopifnot(identical(dimnames(coords),dimnames(reference$umap)))
  numeric_equal(coords,reference$umap,1e-6,0,'UMAP_coordinates')
  for(i in seq_len(7L)){
    mat<-BPCells::open_matrix_dir(file.path(direct,paste0('norm_',i)))
    original_mat<-if(identical(original_direct,direct))mat else
      BPCells::open_matrix_dir(file.path(original_direct,paste0('norm_',i)))
    ids<-colnames(mat)
    for(part in wb_partition_axis(ids,128L)){
      actual<-as.matrix(wb_slice(view,'RNA_log_norm',features,part))
      expected<-as.matrix(mat[,match(part,colnames(mat)),drop=FALSE])
      stopifnot(identical(dimnames(actual),dimnames(expected)))
      numeric_equal(actual,expected,1e-14,0,paste0('normalization_',i,'_',part[1]))
      if(!identical(original_direct,direct)) {
        old_expected<-as.matrix(original_mat[,match(part,colnames(original_mat)),drop=FALSE])
        stopifnot(identical(dimnames(actual),dimnames(old_expected)))
        numeric_equal(actual,old_expected,1e-14,0,
          paste0('original_full_precision_normalization_',i,'_',part[1]))
      }
    }
  }
  saveRDS(list(signs=signs,staged_hvg=tab,staged_loadings=loadings,staged_variance=variance),
    file.path(root,'scientific_comparison.rds'),compress=FALSE)
})
# This supplemental record does not turn an unmatched-input comparison into a
# passing end-to-end gate. Preserve every original threshold and disclose MISS.
original_thresholds<-list()
measure('original_reference_scientific_thresholds',{
  check_original<-function(label,code){
    outcome<-tryCatch({force(code);NULL},error=identity)
    original_thresholds[[length(original_thresholds)+1L]]<<-data.frame(
      output=label,status=if(inherits(outcome,'error'))'threshold_not_met' else 'passed',
      message=if(inherits(outcome,'error'))conditionMessage(outcome) else 'Original criteria met')
    write.csv(do.call(rbind,original_thresholds),file.path(root,'original_reference_thresholds.csv'),row.names=FALSE)
    invisible(NULL)
  }
  check_original('HVG',{
    got<-hvg$run$outputs$selected_features$table;old<-original_reference$hvg
    stopifnot(identical(names(got),names(old)))
    for(n in c('feature_id','rank','selected','method','matrix_id'))stopifnot(identical(got[[n]],old[[n]]))
    for(n in c('mean','variance','dispersion','score','detected_cells','detected_fraction'))
      numeric_equal(as.numeric(got[[n]]),as.numeric(old[[n]]),1e-12,1e-10,paste0('original_HVG_',n))
  })
  check_original('PCA',{
    got<-space_values(view,'rna.pca');old<-original_reference$pca
    stopifnot(identical(dimnames(got),dimnames(old$coords)))
    old_signs<-sign(colSums(got*old$coords));stopifnot(all(old_signs!=0))
    numeric_equal(sweep(got,2L,old_signs,'*'),old$coords,1e-7,1e-6,'original_PCA_coordinates')
    load<-pca$run$outputs$loadings$table
    for(n in setdiff(names(load),'loading'))stopifnot(identical(load[[n]],old$loadings[[n]]))
    numeric_equal(as.numeric(load$loading)*old_signs[as.integer(load$component)],
      as.numeric(old$loadings$loading),1e-7,1e-6,'original_PCA_loadings')
    variance<-pca$run$outputs$variance$table
    for(n in c('PC','component','matrix_id','space_id'))stopifnot(identical(variance[[n]],old$variance[[n]]))
    for(n in c('stdev','variance','variance_explained','cumulative_variance_explained'))
      numeric_equal(as.numeric(variance[[n]]),as.numeric(old$variance[[n]]),0,1e-8,paste0('original_PCA_',n))
  })
  check_original('UMAP_1e-6_absolute',{
    got<-space_values(view,'rna.umap');stopifnot(identical(dimnames(got),dimnames(original_reference$umap)))
    numeric_equal(got,original_reference$umap,1e-6,0,'original_UMAP_coordinates')
  })
})
dag<-wb_session_dag(s,bundle=b,include_artifacts=TRUE,include_active=TRUE)
saveRDS(dag,file.path(root,'session_dag.rds'),compress=FALSE)
outputs<-list(wb_ref_run(norm$run$run_id,'summary'),
  wb_ref_run(hvg$run$run_id,'selected_features'),wb_ref_run(hvg$run$run_id,'fit_summary'),
  wb_ref_run(pca$run$run_id,'loadings'),wb_ref_run(pca$run$run_id,'variance'),
  wb_ref_run(pca$run$run_id,'fit_summary'),wb_ref_run(umap$run$run_id,'model'))
promotion<-measure('promotion',wb_session_promote_current(b,s,outputs=outputs,
  name_prefix='baseline_rna',created_by='forge_acceptance',fail_fast=TRUE))
expected_terminals<-vapply(outputs,function(x)paste(x$run_id,x$output,sep='::'),'')
actual_terminals<-with(promotion$promoted,paste(run_id,output,sep='::'))
stopifnot(all(promotion$promoted$status=='ok'),
  !anyDuplicated(actual_terminals),setequal(actual_terminals,expected_terminals),
  all(nzchar(promotion$promoted$artifact_id)))
saveRDS(list(promotion=promotion,runs=list(norm=norm$run,hvg=hvg$run,pca=pca$run,umap=umap$run)),
  file.path(root,'promotion_and_runs.rds'),compress=FALSE)
measure('finalize_close',{
  readiness<-wb_finalize_recipient_bundle(b);stopifnot(isTRUE(readiness$ready))
  saveRDS(readiness,file.path(root,'recipient_readiness.rds'),compress=FALSE)
  wb_close_bundle(b)
})
# The explicit recipient report below is the authoritative reopen verification;
# avoid performing the same full content verification twice at this boundary.
b<-measure('readonly_reopen',wb_open_bundle(bundle_path,read_only=TRUE,validate=FALSE))
measure('persisted_scientific_inspection',{
  stopifnot('RNA_log_norm'%in%wb_matrices(b)$matrix_id,
    all(c('rna.pca','rna.umap')%in%wb_spaces(b)$space_id),
    identical(wb_cells(b,'all'),cells),
    identical(wb_features(b,'counts')$feature_id,features),
    identical(wb_features(b,'RNA_log_norm')$feature_id,features))
  for(id in original_spaces)
    stopifnot(identical(space_values(b,id),original_coordinates[[id]]))
  compare<-readRDS(file.path(root,'scientific_comparison.rds'))
  coords<-space_values(b,'rna.pca')
  numeric_equal(sweep(coords,2L,compare$signs,'*'),reference$pca$coords,1e-7,1e-6,'persisted_PCA')
  numeric_equal(space_values(b,'rna.umap'),reference$umap,1e-6,0,'persisted_UMAP')
  model_row<-promotion$promoted$run_id==umap$run$run_id&promotion$promoted$output=='model'
  stopifnot(sum(model_row)==1L)
  model<-wb_art_load(b,promotion$promoted$artifact_id[model_row])
  stopifnot(identical(model$kind,'model_ref'),identical(model$engine,'uwot'),
    identical(model$model_type,'uwot_umap'),identical(model$in_space_id,'rna.pca'),
    identical(model$model_space_id,'rna.umap'),!is.null(model$model_tree_manifest))
  fitted<-uwot::load_uwot(file.path(model$model_tree_root,model$model_primary_path),verbose=FALSE)
  numeric_equal(unname(fitted$embedding),unname(reference$umap),1e-6,0,'persisted_UMAP_model_embedding')
  for(n in c('selected_features','loadings','variance')){
    rid<-if(n=='selected_features')hvg$run$run_id else pca$run$run_id
    matches<-promotion$promoted$run_id==rid&promotion$promoted$output==n
    stopifnot(sum(matches)==1L)
    stored<-wb_art_load(b,promotion$promoted$artifact_id[matches])$table
    stage<-switch(n,selected_features=compare$staged_hvg,loadings=compare$staged_loadings,
      variance=compare$staged_variance)
    stopifnot(identical(names(stored),names(stage)),nrow(stored)==nrow(stage))
    # Existing table JSON default precision is explicit, separate from the
    # full-precision scientific comparisons above. Compare all persisted rows.
    for(field in names(stage)){
      if(is.numeric(stage[[field]])){
        canonical<-jsonlite::fromJSON(as.character(jsonlite::toJSON(unname(stage[[field]]),
          auto_unbox=FALSE,null='null')))
        stopifnot(identical(as.numeric(stored[[field]]),as.numeric(canonical)))
      }else stopifnot(identical(as.character(stored[[field]]),as.character(stage[[field]])))
    }
  }
  for(part in list(head(cells,128L),tail(cells,128L))){
    actual<-as.matrix(wb_slice(b,'RNA_log_norm',head(features,8L),part))
    fragment<-if(identical(part,head(cells,128L)))1L else 7L
    mat<-BPCells::open_matrix_dir(file.path(direct,paste0('norm_',fragment)))
    expected<-as.matrix(mat[match(head(features,8L),rownames(mat)),match(part,colnames(mat)),drop=FALSE])
    stopifnot(identical(dimnames(actual),dimnames(expected)))
    numeric_equal(actual,expected,1e-14,0,'persisted_normalization_boundary_block')
  }
})
wb_close_bundle(b)
report<-measure('recipient_validation',wb_bundle_validation_report(bundle_path,level='recipient'))
stopifnot(isTRUE(report$ok),identical(report$pre_validation_fingerprint,report$post_validation_fingerprint))
saveRDS(report,file.path(root,'recipient_report.rds'),compress=FALSE)
stopifnot(identical(getOption('scworkbench.max_dense_materialize_mb',256),guard_before))
jsonlite::write_json(list(ok=TRUE,recipient_status=report$status,
  recipient_elapsed=report$elapsed_seconds,default_dense_guard_mb=guard_before,
  installed_core_library=args[[1]],installed_pack_library=pack_library,
  source_sha256=source$sha256,source_file_size=file.info(source_path)$size,
  trace_missing=missing,trace_inclusive_times_are_nested=TRUE,
  numerical_criteria='notes/engine_simplification/baselines/BUDGETS.md',
  original_reference_root=original_direct,
  original_reference_thresholds_met=all(do.call(rbind,original_thresholds)$status=='passed'),
  direct_reference_sha256=digest::digest(file=file.path(direct,'scientific_reference.rds'),algo='sha256')),
  file.path(root,'completion.json'),auto_unbox=TRUE,pretty=TRUE)
cat('FULL_XENOPUS_IMPORT_ANALYSIS_PROMOTION_FINALIZE_REOPEN_RECIPIENT_DIRECT_OK\n')
