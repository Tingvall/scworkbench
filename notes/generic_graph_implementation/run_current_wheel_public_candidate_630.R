lib <- "/tmp/scwb-provisional-output-625.vcr1ylu6/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
manifest <- "/tmp/scwb-final-python-588/lib/python3.11/site-packages/scwbpython/operation-pack.json"
wb_operation_pack_activate(manifest,python="/tmp/scwb-final-python-588/bin/python")
root <- tempfile("v1_public_positive_source_");workspace <- tempfile("v1_public_positive_workspace_")
b <- wb_init_bundle(root);cells <- paste0("c",1:12)
wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,signal=1:12))
s <- wb_session_create(b,workspace,session_id="public_positive")
source <- wb_session_run_op(s,b,"metadata_cell_vector",inputs=list(source_column="signal",vector_name="signal",value_type="continuous",missing_policy="error",min_cells=1L))
cat("CORE_SOURCE_RUN PASS\n")
result <- wb_session_run_op(source$session,b,"scwbpython::affine_cell_vector",inputs=list(signal=wb_ref_run(source$run$run_id,"vector"),scale=2,min_cells=1L))
stopifnot(identical(as.numeric(result$run$outputs$vector$value),2*seq_len(12L)))
cat("PYTHON_PUBLIC_RUN EXACT_VALUES PASS\n")
promotion <- wb_session_promote_current(b,result$session,outputs=c("vector","summary"))
stopifnot(sum(promotion$promoted$status=="ok")==2L)
id <- promotion$promoted$artifact_id[promotion$promoted$output=="vector"][[1L]]
stopifnot(identical(unclass(wb_art_load(b,id)),unclass(result$run$outputs$vector)),wb_entity_certificate(b,"artifact",id)$identity$verification_status=="content_verified")
cat("PUBLIC_PROMOTION CERTIFIED_PERSISTENCE PASS\n")
wb_session_discard(promotion$session);wb_close_bundle(b);unlink(c(root,workspace),recursive=TRUE)
