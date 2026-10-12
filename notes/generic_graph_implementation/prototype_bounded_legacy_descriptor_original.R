args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],'library'),.libPaths()))
library(scworkbench)
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load('/tmp/scwb-bounded-json-lexer-prototype-291.so')
initializer <- DBI::dbConnect(RSQLite::SQLite(),':memory:',default.extensions=FALSE)
DBI::dbGetQuery(initializer,'SELECT load_extension(?,?);',params=list(
  '/tmp/scwb-bounded-json-lexer-prototype-291.so','sqlite3_scwbjsonprototype_init'))
DBI::dbDisconnect(initializer)
source('notes/generic_graph_implementation/prototype_bounded_json_walk.R')
source('notes/generic_graph_implementation/prototype_bounded_legacy_descriptor.R')
fixture <- readRDS('/tmp/scwb-graph-manifest-batch-lifecycle-246.rds')
path <- '/tmp/scwb-graph-original-artifact-certificate-copy-263/source.bundle/db/app.sqlite'
before <- digest::digest(file=path,algo='sha256',serialize=FALSE)
con <- DBI::dbConnect(RSQLite::SQLite(),path,flags=RSQLite::SQLITE_RO,cache_size=-64)
selector <- DBI::dbConnect(RSQLite::SQLite(),path,flags=RSQLite::SQLITE_RO,cache_size=-64)
DBI::dbExecute(selector,'PRAGMA temp_store=FILE;')
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes='8388608',sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
restore <- scworkbench:::.wb_graph_scoped_connection_budget(con,policy,cache_kib=64L)
time <- system.time(observed <- prototype_legacy_descriptor(con,selector,fixture$source_axis_artifact_id,policy))
stopifnot(observed$rows==90000,observed$metadata_bytes==183)
cat('BOUNDED_LEGACY_DESCRIPTOR_ORIGINAL',paste(readLines('/proc/self/status')[grepl('^(VmRSS|VmHWM):',readLines('/proc/self/status'))],collapse=' '),
  ' rows=',observed$rows,' metadata_bytes=',observed$metadata_bytes,' elapsed=',time[['elapsed']],
  ' prototype_only=TRUE qualification=FALSE\n',sep='')
saveRDS(observed,'/tmp/scwb-bounded-legacy-descriptor-original-318.rds')
restore();DBI::dbDisconnect(selector);DBI::dbDisconnect(con)
stopifnot(identical(before,digest::digest(file=path,algo='sha256',serialize=FALSE)))
cat('BOUNDED_LEGACY_DESCRIPTOR original_isolated_copy_primary_DB=UNCHANGED PASS\n')
