args <- commandArgs(TRUE)
f <- readRDS('/tmp/scwb-graph-native-long-axis-90000-development/measurement-9a11d1f.rds')
original <- f
f$core_library <- '/tmp/scwb-graph-forge-duplicate-sensitive-444.ps0av2oi/library'
.libPaths(c(f$core_library,.libPaths()))
library(scworkbench,lib.loc=f$core_library)
stopifnot(!file.exists(args[[1]]),f$source_axis_count==90000L,f$source_axis_utf8_bytes==18258618L,identical(f$source_bundle,original$source_bundle),identical(f$seed_graph_artifact_id,original$seed_graph_artifact_id),identical(f$pack_identity,original$pack_identity))
f$development_checkpoint <- list(name='collector445_original90000_2x_development',tuple=445L,qualification=FALSE,source_ledger='notes/generic_graph_implementation/evidence/445_complete_duplicate_sensitive_review_tuple.sha256',source_ledger_sha256='86d447800453ac16eebae9ad6322fdea848a914801b851120fe963c777ee90db',original_db_sha256=digest::digest(file=file.path(f$source_bundle,'db/app.sqlite'),algo='sha256'),source_closure_function_sha256=digest::digest(paste(deparse(body(getFromNamespace('.wb_graph_object_closure','scworkbench'))),collapse='\n'),algo='sha256',serialize=FALSE),dll_sha256=digest::digest(file=getLoadedDLLs()[['scworkbench']][['path']],algo='sha256'))
stopifnot(identical(f$development_checkpoint$dll_sha256,'ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56'))
saveRDS(f,args[[1]])
cat('PREPARED_ORIGINAL_LIFECYCLE original_axes=90000 original_axis_utf8_bytes=18258618 runtime=',find.package('scworkbench'),' fixture=',args[[1]],' run_started=FALSE qualification=FALSE\n',sep='')
