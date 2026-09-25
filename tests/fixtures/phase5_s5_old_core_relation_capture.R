library(scworkbench)
ident <- getFromNamespace('.wb_operation_pack_v2_identity_plain','scworkbench')
mk_m3 <- function() {
  cells <- c('z10','c2','a9','m1','b20','q3','d7','x4','e12','r5','f11','p6','g18','n8','h14','o13','i17','l15','j19','k16','u21','v22','w23','t24')
  t <- seq(0.15,1.2,length.out=8)
  xy <- rbind(cbind(t,rep(0,8)),cbind(-t,0.25*t),cbind(rep(0,8),-t))
  rownames(xy)<-cells; colnames(xy)<-c('d1','d2')
  list(cells=cells,coordinates=xy,inputs=list(cell_set='all',cell_ids=cells,fit_space=wb_prim_space('latent'),dims=as.character(1:2),root_cells=cells[1],k=5L,random_seed=13L,use_partition=FALSE,close_loop=FALSE))
}
mk_pal <- function() {
  cells <- c(sprintf('c%02d',0:9),sprintf('a%02d',0:9),sprintf('b%02d',0:9))
  xy <- t(vapply(seq_along(cells),function(j){
    i<-(j-1L)%%10L
    if(j<=10L) return(c(i/9,0.02*sin(j),0.02*cos(j)))
    t<-(i+1)/10; sign<-if(j<=20L) 1 else -1
    c(1+t,sign*t+0.02*sin(j),0.02*cos(j))
  },numeric(3)))
  rownames(xy)<-cells; colnames(xy)<-c('d1','d2','d3')
  list(cells=cells,coordinates=xy,inputs=list(cell_set='all',cell_ids=cells,fit_space=wb_prim_space('latent'),root_cell='c00',terminal_cells=c('a09','b09'),dims=as.character(1:3),knn=5L,n_diffusion_components=3L,n_waypoints=10L,seed=7L))
}
capture <- function(name, data, closure) {
  root <- tempfile(paste0('s5_oracle_',name,'_'))
  b <- wb_init_bundle(root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(b),silent=TRUE); unlink(root,recursive=TRUE,force=TRUE)},add=TRUE)
  wb_define_cells(b,data$cells)
  wb_add_space(b,'latent',data$coordinates)
  rr <- wb_session_run_op(wb_session_new(),b,name,inputs=data$inputs)
  outputs <- rr$run$outputs
  stopifnot(setequal(names(outputs),closure))
  rf <- outputs$branch_membership
  stopifnot(length(rf$key)>0L,length(rf$key)!=length(data$cells),!is.null(rf$weight),is.null(rf$value),is.null(rf$distance))
  direct_id <- ident('scworkbench.relation_family.content.v1',unclass(rf))
  prom <- wb_session_promote_current(b,rr$session,name_prefix=paste0('s5_',name),created_by='oracle',outputs=closure,fail_fast=TRUE)
  tab <- prom$promoted
  tab <- tab[as.character(tab$status)=='ok',,drop=FALSE]
  stopifnot(setequal(as.character(tab$output),closure))
  aid <- as.character(tab$artifact_id[tab$output=='branch_membership'])
  loaded <- wb_art_load(b,aid,expected_kind='relation_family')
  stopifnot(identical(rf$key,loaded$key),identical(rf$cell_id,loaded$cell_id),identical(rf$weight,loaded$weight),identical(is.null(rf$value),is.null(loaded$value)),identical(is.null(rf$distance),is.null(loaded$distance)))
  loaded_id <- ident('scworkbench.relation_family.content.v1',unclass(loaded))
  terminal_ids <- lapply(setdiff(closure,'model'),function(output_name){
    original <- outputs[[output_name]]
    artifact <- wb_art_load(b,as.character(tab$artifact_id[tab$output==output_name]),expected_kind=original$kind)
    scheme <- paste0('scworkbench.',original$kind,'.content.v1')
    list(direct=ident(scheme,unclass(original)),reopened=ident(scheme,unclass(artifact)))
  })
  names(terminal_ids) <- setdiff(closure,'model')
  model_aid <- as.character(tab$artifact_id[tab$output=='model'])
  model <- wb_art_load(b,model_aid,expected_kind='model_ref')
  stopifnot(identical(as.character(model$engine),sub('_fit$','',name)),file.exists(as.character(model$model_path)))
  list(op=name,source_cells=as.list(data$cells),source_cell_count=length(data$cells),row_count=length(rf$key),ordered_keys=as.list(unique(as.character(rf$key))),ordered_rows=lapply(seq_along(rf$key),function(i) list(key=as.character(rf$key[i]),cell_id=as.character(rf$cell_id[i]),weight_hex=sprintf('%a',as.numeric(rf$weight[i])))),optional_numeric_presence=list(weight=TRUE,value=FALSE,distance=FALSE),content_identity=direct_id,reopened_content_identity=loaded_id,terminal_content_identities=terminal_ids,closure=as.list(closure),promoted_count=nrow(tab),model=list(engine=as.character(model$engine),model_type=as.character(model$model_type),path_suffix=tools::file_ext(as.character(model$model_path))))
}
mon <- capture('monocle3_fit',mk_m3(),c('pseudotime','branch_membership','model'))
pal <- capture('palantir_fit',mk_pal(),c('pseudotime','branch_membership','branch_summary','entropy','model'))
out <- list(schema='scworkbench.phase5_s5.old_core_relation_oracle.v1',core_commit='6e0438c90fe51bacda1604aa7c5cc3b1cd1e5646',pybench_commit='9ad8a7a3bd2298fdc6f426032e54ccb07eee0402',oracles=list(monocle3=mon,palantir=pal))
args <- commandArgs(trailingOnly=TRUE)
target <- if (length(args) == 1L) args[[1]] else
  'tests/fixtures/phase5_s5_old_core_relation_oracle.json'
jsonlite::write_json(out,target,auto_unbox=TRUE,pretty=TRUE,digits=NA)
cat('PASS old-core M3',mon$row_count,'/',mon$source_cell_count,'Palantir',pal$row_count,'/',pal$source_cell_count,'\n')
