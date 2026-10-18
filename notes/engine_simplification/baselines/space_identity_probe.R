args<-commandArgs(TRUE);.libPaths(c(args[[1]],.libPaths()))
suppressPackageStartupMessages(library(scworkbench))
out<-args[[3]];stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
reference<-readRDS(file.path(args[[2]],'scientific_reference.rds'))
cells<-rownames(reference$pca$coords);values<-reference$pca$coords[,1:30,drop=FALSE]
rows<-list()
measure<-function(case,code){
  gc();t<-proc.time();ans<-force(code);t<-proc.time()-t
  rows[[length(rows)+1L]]<<-data.frame(case=case,elapsed=t[['elapsed']],user=t[['user.self']],
    system=t[['sys.self']],sha256=ans$sha256)
  print(rows[[length(rows)]],row.names=FALSE)
  write.csv(do.call(rbind,rows),file.path(out,'timings.csv'),row.names=FALSE)
  invisible(ans)
}
# Independent vectorized oracle for finite non-subnormal double numbers. It
# deliberately does not invoke the core numeric or canonical-JSON encoders.
# %.14e gives 15 significant digits; strip coefficient zeros, then canonical
# scientific exponent. The probe is bounded; this builds one string and is NOT
# proposed as a production large-space implementation.
numbers<-function(x){
  stopifnot(all(is.finite(x)),all(x==0|abs(x)>=1e-307))
  raw<-sprintf('%.14e',as.numeric(x))
  coefficient<-sub('e.*$','',raw)
  coefficient<-sub('0+$','',coefficient);coefficient<-sub('[.]$','',coefficient)
  exponent<-as.integer(sub('^.*e','',raw))
  z<-paste0(coefficient,'e',exponent);z[x==0]<-'0';z
}
oracle<-function(values,cells){
  tokens<-matrix(numbers(as.numeric(t(values))),nrow=nrow(values),byrow=TRUE)
  pieces<-apply(tokens,1L,function(row)paste0('[',paste(row,collapse=','),']'))
  text<-paste0('{"cell_id":',as.character(jsonlite::toJSON(unname(cells),auto_unbox=FALSE)),
    ',"dimensions":[',paste(numbers(dim(values)),collapse=','),
    '],"schema":"scworkbench.operation_pack.space_slice.content.v1","values":[',
    paste(pieces,collapse=','),']}')
  list(scheme='scworkbench.operation_pack.space_slice.content.v1',
    sha256=digest::digest(text,algo='sha256',serialize=FALSE),bytes=nchar(text,type='bytes'))
}
small<-matrix(c(0,-0,1,1e-5,-4.2,1e5,1.25,-1e-307,1e308),3L,3L)
small_cells<-c('cell_2','cell_10','cell_1')
stopifnot(identical(oracle(small,small_cells)$sha256,
  scworkbench:::.wb_operation_pack_v3_space_content(small,small_cells)$sha256))
actual<-measure('selected_space_13199x30_legacy_projection',
  scworkbench:::.wb_operation_pack_v3_space_content(values,cells))
expected<-measure('independent_vectorized_oracle',oracle(values,cells))
stopifnot(identical(actual$sha256,expected$sha256))
set.seed(8L);scores<-setNames(rnorm(length(cells)),cells)
objects<-list(cell_vector=wb_prim_cell_vector(scores,'continuous',meta=list(label='score')),
  cell_vector_family=wb_prim_cell_vector_family(rep(c('A','B'),each=length(cells)),
    rep(cells,2L),rep(scores,2L),value_type='continuous'),
  relation_family=wb_prim_relation_family(rep(c('A','B'),each=length(cells)),
    rep(cells,2L),weight=rep(abs(scores),2L)),
  model_ref=wb_prim_model_ref('fitted','source',engine='uwot'))
for(name in names(objects)){
  primitive<-objects[[name]]
  measure(paste0(name,'_ordinary_object_provenance_hash'),list(
    sha256=scworkbench:::.wb_prov_sha256_object(unclass(primitive))))
  descriptor<-measure(paste0(name,'_input_descriptor'),{
    value<-scworkbench:::.wb_operation_pack_v2_input_descriptor(name,primitive,
      list(kind=name,alignment='exact'))
    list(sha256=digest::digest(jsonlite::serializeJSON(value,digits=NA),
      algo='sha256',serialize=FALSE),descriptor=value)
  })
  saveRDS(descriptor$descriptor,file.path(out,paste0(name,'_descriptor.rds')),compress=FALSE)
}
saveRDS(list(identity=actual,oracle=expected,dimensions=dim(values),cells=cells),
  file.path(out,'identity.rds'),compress=FALSE)
cat('SPACE_IDENTITY_INDEPENDENT_ORACLE_EXACT_OK canonical_bytes=',expected$bytes,'\n',sep='')
