lib <- "/tmp/scwb-pre-content-562.u8hg2ft6/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
root <- "/tmp/scwb-pre-content-562.u8hg2ft6"
b <- wb_init_bundle(file.path(root,"authentic_legacy_table_626.bundle"))
ids <- paste0("c",1:12);wb_define_cells(b,ids)
a <- wb_prim_cell_vector(stats::setNames(rep(c("ctrl","drug"),each=6),ids),value_type="categorical")
bv <- wb_prim_cell_vector(stats::setNames(rep(c("L1","L2"),6),ids),value_type="categorical")
r <- wb_session_run_op(wb_session_new(),b,"cell_vector_association",inputs=list(a=a,b=bv,cell_set="all",min_n_per_group=3L,method="fisher"))
p <- wb_session_promote_current(b,r$session,outputs=c("summary","detail"))
row <- p$promoted[p$promoted$output=="detail",,drop=FALSE]
id <- as.character(row$artifact_id[[1L]])
primitive <- wb_art_load(b,id)
columns <- DBI::dbGetQuery(b$con,"PRAGMA table_info(prov_run_outputs);")$name
stopifnot(!"replay_equivalence_policy" %in% columns,!"content_sha256" %in% columns)
saveRDS(list(id=id,run_id=r$run$run_id,snapshot_id=p$provenance_snapshot_id,primitive=primitive,original_columns=columns),file.path(root,"authentic_legacy_table_626_expected.rds"))
cat("AUTHENTIC_96A37_TABLE old_public_association_run=PASS public_promote=PASS public_load=PASS replay_policy_columns_absent=TRUE\n")
wb_close_bundle(b)
