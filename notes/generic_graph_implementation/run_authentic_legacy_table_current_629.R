lib <- "/tmp/scwb-provisional-output-625.vcr1ylu6/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
root <- "/tmp/scwb-pre-content-562.u8hg2ft6"
source <- file.path(root,"authentic_legacy_table_626.bundle")
copy <- file.path(root,"current_legacy_table_629.bundle")
fs::dir_copy(source,copy)
expected <- readRDS(file.path(root,"authentic_legacy_table_626_expected.rds"))
oldcon <- DBI::dbConnect(RSQLite::SQLite(),file.path(copy,"db/app.sqlite"))
rows_before <- DBI::dbGetQuery(oldcon,"SELECT * FROM artifact_table_rows ORDER BY artifact_id,row_idx;")
columns <- DBI::dbGetQuery(oldcon,"PRAGMA table_info(prov_run_outputs);")$name
stopifnot(!"replay_equivalence_policy"%in%columns)
DBI::dbDisconnect(oldcon)
b <- wb_open_bundle(copy)
loaded <- wb_art_load(b,expected$id)
stopifnot(identical(unclass(loaded),unclass(expected$primitive)),identical(rows_before,DBI::dbGetQuery(b$con,"SELECT * FROM artifact_table_rows ORDER BY artifact_id,row_idx;")))
row <- DBI::dbGetQuery(b$con,"SELECT replay_equivalence_policy,replay_equivalence_status,verification_status FROM prov_run_outputs WHERE artifact_id=?;",params=list(expected$id))
stopifnot(nrow(row)==1L,row$replay_equivalence_policy=="not_comparable",row$replay_equivalence_status=="legacy_not_comparable",row$verification_status=="legacy_structural_only")
cat("AUTHENTIC_TABLE_LEGACY_REPLAY_BACKFILL exact_primitive=PASS original_scientific_table_rows=UNCHANGED original_missingpolicy=TRUE not_comparable=PASS legacy_status=PASS\n")
wb_close_bundle(b)
