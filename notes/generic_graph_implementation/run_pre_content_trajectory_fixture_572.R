lib <- "/tmp/scwb-pre-content-562.u8hg2ft6/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
root <- "/tmp/scwb-pre-content-562.u8hg2ft6"
b <- wb_init_bundle(file.path(root,"authentic_legacy_trajectory_572.bundle"))
wb_define_cells(b,c("c1","c2","c3"))
primitive <- wb_prim_cell_vector_family(c("L1","L1","L1"),c("c1","c2","c3"),c(0,0.5,1),value_type="continuous")
run <- wb_new_run("slingshot_fit",inputs=list(),
 params=list(trajectory_fit_id="legacy_fit_96a37",trajectory_engine="slingshot",n_lineages=1L),outputs=list(pseudotime=primitive))
promoted <- wb_promote_analysis(b,stats::setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="pseudotime")
id <- promoted$promoted$artifact_id[[1]]
loaded <- wb_art_load(b,id)
stopifnot(identical(loaded$meta$trajectory_fit_id,"legacy_fit_96a37"),
 identical(loaded$meta$engine,"slingshot"),identical(loaded$meta$family_kind,"trajectory_pseudotime"),
 identical(loaded$value,primitive$value))
saveRDS(list(id=id,primitive=loaded),file.path(root,"authentic_legacy_trajectory_572_expected.rds"))
cat("AUTHENTIC_96A37_LEGACY_TRAJECTORY public_promote=PASS public_load=PASS fit_metadata_backfill=PASS original_values=PASS\n")
wb_close_bundle(b)
