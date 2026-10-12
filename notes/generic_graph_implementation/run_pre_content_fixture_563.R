args <- commandArgs(TRUE);stopifnot(length(args)==2L)
lib <- args[[1]];root <- args[[2]]
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
b <- wb_init_bundle(file.path(root,"authentic_pre_content.bundle"))
wb_define_cells(b,c("c1","c2","c3"))
primitive <- wb_prim_cell_vector(c(c1="a",c2="b",c3="a"),value_type="categorical")
run <- wb_new_run("metadata_cell_vector",inputs=list(),params=list(vector_name="legacy",source_column="group"),outputs=list(vector=primitive))
promoted <- wb_promote_analysis(b,stats::setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="vector")
id <- promoted$promoted$artifact_id[[1]]
loaded <- wb_art_load(b,id)
stopifnot(identical(unclass(loaded),unclass(primitive)))
columns <- DBI::dbGetQuery(b$con,"PRAGMA table_info(prov_run_outputs);")$name
cat("ORIGINAL_PROV_OUTPUT_COLUMNS\n");print(columns)
stopifnot(!"content_sha256" %in% columns)
cat("AUTHENTIC_PRE_CONTENT ordinary_public_load=PASS exact_primitive=TRUE content_certificate=ABSENT no_new_graph_proof=TRUE\n")
saveRDS(list(id=id,primitive=loaded),file.path(root,"authentic_pre_content_expected.rds"))
wb_close_bundle(b)
