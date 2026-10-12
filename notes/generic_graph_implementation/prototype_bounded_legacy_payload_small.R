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
source('notes/generic_graph_implementation/prototype_bounded_legacy_payload.R')
root <- tempfile('legacy_payload_differential_');bundle <- wb_init_bundle(root)
cells <- c('é','c2','c1','🙂');wb_define_cells(bundle,cells)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes='8388608',sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
cases <- list(
  wb_prim_cell_vector(setNames(c('quote"','backslash\\','line\n','é🙂'),rev(cells))),
  wb_prim_cell_vector(setNames(c(1/3,-0,1e-20,1e20),rev(cells)),value_type='continuous'),
  wb_prim_cell_vector(setNames(c('a','b','c','d'),cells),meta=list(factor=factor(c('b','a')),
    date=as.Date('2026-10-11'),integer=c(1L,NA_integer_),boolean=c(TRUE,NA),nested=list())),
  wb_prim_cell_vector(setNames(c('a','b','c','d'),cells),meta=list(long=strrep('é🙂',1000L))))
for(i in seq_along(cases)) {
  run <- wb_new_run('metadata_cell_vector',list(),list(),list(vector=cases[[i]]))
  promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs='vector')
  id <- promoted$promoted$artifact_id[promoted$promoted$output=='vector'][[1L]]
  actual <- wb_art_load(bundle,id)
  expected <- scworkbench:::.wb_prov_payload_identity(bundle,actual)$content_sha256
  selector <- DBI::dbConnect(RSQLite::SQLite(),file.path(root,'db/app.sqlite'),flags=RSQLite::SQLITE_RO,cache_size=-64)
  DBI::dbExecute(selector,'PRAGMA temp_store=FILE;')
  descriptor <- prototype_legacy_descriptor(bundle$con,selector,id,policy)
  payload <- prototype_legacy_cell_vector_hash(bundle$con,selector,id,policy,descriptor)
  stopifnot(identical(expected,payload$sha256))
  DBI::dbDisconnect(selector)
  cat('BOUNDED_LEGACY_PAYLOAD_SMALL case=',i,' exact_old_loader_hash=TRUE PASS\n',sep='')
}
wb_close_bundle(bundle);unlink(root,recursive=TRUE)
cat('BOUNDED_LEGACY_PAYLOAD_SMALL executed=4 passed=4 skipped=0 prototype_only=TRUE\n')
