args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],'library'),.libPaths()))
library(scworkbench)
`%||%` <- getFromNamespace('%||%','scworkbench')
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load('/tmp/scwb-json-typed-366.so')
initializer <- DBI::dbConnect(RSQLite::SQLite(),':memory:',default.extensions=FALSE)
DBI::dbGetQuery(initializer,'SELECT load_extension(?,?);',params=list(
  '/tmp/scwb-json-typed-366.so','sqlite3_scwbjsonprototype_init'))
DBI::dbDisconnect(initializer)
source('notes/generic_graph_implementation/prototype_bounded_json_walk_typed.R')
source('notes/generic_graph_implementation/prototype_bounded_provenance_refs_typed.R')
path <- tempfile(fileext='.sqlite');con <- DBI::dbConnect(RSQLite::SQLite(),path,cache_size=-64)
DBI::dbExecute(con,'CREATE TABLE artifacts(provenance_json TEXT);')
DBI::dbExecute(con,"INSERT INTO artifacts VALUES('');")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes='8388608',sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
texts <- c('{}','{"parent_artifacts":[]}','{"parent_artifacts":"a"}',
  '{"parent_artifacts":["a","a","b"]}',
  '{"parent_artifacts":[{"ref_type":"artifact","artifact_id":"a","children":["ignored"]}]}',
  '{"parent_artifacts":[{"ref_type":"matrix","artifact_id":"ignored","children":["a","b"]}]}',
  '{"inputs":{"provenance_refs":[{"artifact_id":"é🙂"},["a",null,false,2]]}}',
  '{"parent_artifacts":["a"],"inputs":{"provenance_refs":["a","b"]}}',
  '{"parent_artifacts":{"":"a","":"b"}}',
  '{"parent_artifacts":[{"artifact_id":"a","artifact_id":"b"}]}',
  '{"inputs":{},"inputs":{"provenance_refs":["ignored"]}}',
  '{"inputs":{"provenance_refs":["a"]},"inputs":{"provenance_refs":["ignored"]}}',
  as.character(jsonlite::toJSON(list(parent_artifacts=list('a'),
    primitive_payload=list(row_order=as.list(rep(strrep('é🙂',100L),5000L)))),auto_unbox=TRUE)))
for(text in texts) {
  DBI::dbExecute(con,'UPDATE artifacts SET provenance_json=?;',params=list(text))
  observed <- prototype_provenance_refs(con,'1',policy)
  expected <- scworkbench:::.wb_art_refs_from_prov_json(text)
  stopifnot(identical(observed,expected))
}
for(text in c('{','{"parent_artifacts":["a",]}','{"parent_artifacts":"unterminated}',
  '{"inputs":{"provenance_refs":["a"]}}garbage','[true false]')) {
  DBI::dbExecute(con,'UPDATE artifacts SET provenance_json=?;',params=list(text))
  stopifnot(identical(prototype_provenance_refs(con,'1',policy),scworkbench:::.wb_art_refs_from_prov_json(text)))
}
for(text in c(paste0('{"parent_artifacts":["',strrep('a',262145L),'"]}'),
  paste0(strrep('[',130L),'0',strrep(']',130L)),paste0('{"other":',strrep('9',129L),'}'))) {
  DBI::dbExecute(con,'UPDATE artifacts SET provenance_json=?;',params=list(text))
  error <- tryCatch(prototype_provenance_refs(con,'1',policy),error=identity)
  stopifnot(inherits(error,'error'),identical(error$code,'GRAPH_RESOURCE_EXCEEDED'))
}
DBI::dbExecute(con,'PRAGMA journal_mode=WAL;')
text <- '{"parent_artifacts":["a"]}'
DBI::dbExecute(con,'UPDATE artifacts SET provenance_json=?;',params=list(text))
walk <- prototype_json_walk
prototype_json_walk <- function(con,rowid,column,table,callback,budgets) {
  changed <- FALSE
  wrap <- function(...) {if(!changed){DBI::dbExecute(con,'UPDATE artifacts SET provenance_json=?;',params=list('{"parent_artifacts":["b"]}'));changed <<- TRUE};callback(...)}
  walk(con,rowid,column,table,wrap,budgets)
}
error <- tryCatch(prototype_provenance_refs(con,'1',policy),error=identity)
stopifnot(inherits(error,'error'),identical(error$code,'GRAPH_SOURCE_PAYLOAD_INVALID'))
cat('BOUNDED_REFS_TYPED malformed_empty=5 resource_propagation=3 latechange_authority=1 PASS\n')
DBI::dbDisconnect(con);unlink(c(path,paste0(path,'-wal'),paste0(path,'-shm')))
cat('BOUNDED_PROVENANCE_REFS small_old_semantic_differential=',length(texts),' ignored_multimegabyte_row_order=TRUE PASS prototype_only=TRUE\n',sep='')
