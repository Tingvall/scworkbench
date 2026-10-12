.graph_collector_policy <- function()scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",
  sqlite_cache_kib=2048L,partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))

test_graph_bounded_legacy_public_certificate_parity_and_cache_contract <- function() {
  root <- tempfile("bounded_legacy_certificate_");bundle <- wb_init_bundle(root)
  previous <- options("scworkbench.graph_storage_test_hook")
  on.exit({options(previous);wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  cells <- c("é","c2","c1","🙂");wb_define_cells(bundle,cells)
  metadata <- list(list(factor=factor(c("b","a")),date=as.Date("2026-10-11")),
    list(long=strrep("é🙂",50000L)),list(markers=rep(c("NA","Inf","NaN","x","é🙂"),10000L)))
  cases <- list()
  for(kind in c("cell_vector","cell_vector_family"))for(meta in metadata)
    cases[[length(cases)+1L]] <- if(kind=="cell_vector")wb_prim_cell_vector(setNames(c("a","b","c","d"),rev(cells)),meta=meta) else
      wb_prim_cell_vector_family(key=c("k2","k1","k2","k1"),cell_id=rev(cells),value=c(NA_real_,1/3,1e-20,1e20),meta=meta)
  for(prim in cases) {
    run <- wb_new_run("metadata_cell_vector",list(),list(),list(vector=prim))
    promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="vector")
    id <- promoted$promoted$artifact_id[promoted$promoted$output=="vector"][[1L]]
    baseline <- wb_entity_certificate(bundle,"artifact",id)
    expected <- scworkbench:::.wb_prov_payload_identity(bundle,wb_art_load(bundle,id))$content_sha256
    before <- digest::digest(file=file.path(root,"db/app.sqlite"),algo="sha256",serialize=FALSE)
    caches <- DBI::dbGetQuery(bundle$con,"PRAGMA cache_size;")[[1L]][[1L]]
    restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),.graph_collector_policy())
    payload_started <- FALSE;metadata_open <- FALSE
    options(scworkbench.graph_storage_test_hook=function(event,state) {
      if(event=="legacy_object_payload_start") {stopifnot(state$selector_closed);payload_started <<- TRUE}
      if(event=="source_metadata_cache") {
        stopifnot(payload_started,state$cache_kib==64L,
          -DBI::dbGetQuery(state$con,"PRAGMA cache_size;")[[1L]][[1L]]==64L,
          bundle$con@ref$wb_graph_cache_kib+128L<=2048L)
        metadata_open <<- TRUE
      }
    })
    actual <- wb_entity_certificate(bundle,"artifact",id)
    observed <- scworkbench:::.wb_getter_legacy_object_identity(bundle,id)
    stopifnot(identical(actual,baseline),identical(observed$content_sha256,expected),payload_started,
      if(nchar(jsonlite::serializeJSON(prim$meta,digits=NA),type="bytes")>262144L)metadata_open else TRUE)
    restore();options(previous)
    stopifnot(identical(caches,DBI::dbGetQuery(bundle$con,"PRAGMA cache_size;")[[1L]][[1L]]),
      identical(before,digest::digest(file=file.path(root,"db/app.sqlite"),algo="sha256",serialize=FALSE)))
  }
  TRUE
}

test_graph_bounded_legacy_metadata_fault_cleanup_contract <- function() {
  root <- tempfile("bounded_legacy_cleanup_");bundle <- wb_init_bundle(root)
  previous <- options("scworkbench.graph_storage_test_hook")
  on.exit({options(previous);wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  wb_define_cells(bundle,"c1")
  prim <- wb_prim_cell_vector(c(c1="a"),meta=list(long=strrep("é🙂",50000L)))
  run <- wb_new_run("metadata_cell_vector",list(),list(),list(vector=prim))
  promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="vector")
  id <- promoted$promoted$artifact_id[promoted$promoted$output=="vector"][[1L]]
  inventory <- function()sort(list.files(tempdir(),pattern="^scwb_(graph_identity_|object_meta_|graph_identity_metadata_keys_)",full.names=TRUE))
  before <- inventory();cache <- DBI::dbGetQuery(bundle$con,"PRAGMA cache_size;")[[1L]][[1L]]
  restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),.graph_collector_policy())
  options(scworkbench.graph_storage_test_hook=function(event,state)if(event=="source_metadata_cache")
    scworkbench:::.wb_graph_error("GRAPH_RESOURCE_EXCEEDED","METADATA_CACHE_INJECTED"))
  error <- tryCatch(wb_entity_certificate(bundle,"artifact",id),error=base::identity)
  stopifnot(inherits(error,"wb_graph_error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"),identical(before,inventory()))
  restore();options(previous)
  stopifnot(identical(cache,DBI::dbGetQuery(bundle$con,"PRAGMA cache_size;")[[1L]][[1L]]))
  TRUE
}

test_graph_bounded_legacy_refs_parser_and_fileless_contract <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(),":memory:",cache_size=-64)
  on.exit(DBI::dbDisconnect(con),add=TRUE)
  DBI::dbExecute(con,"CREATE TABLE artifacts(provenance_json TEXT);")
  DBI::dbExecute(con,"INSERT INTO artifacts VALUES('');")
  policy <- .graph_collector_policy()
  for(text in c('{}','{"parent_artifacts":["a","a","b"]}',
    '{"inputs":{},"inputs":{"provenance_refs":["ignored"]}}',
    '{"parent_artifacts":["a",]}','{"inputs":{"provenance_refs":["a"]}}garbage')) {
    DBI::dbExecute(con,"UPDATE artifacts SET provenance_json=?;",params=list(text))
    stopifnot(identical(scworkbench:::.wb_getter_artifact_provenance_refs(con,"1",policy),
      scworkbench:::.wb_art_refs_from_prov_json(text)))
  }
  DBI::dbExecute(con,"UPDATE artifacts SET provenance_json=NULL;")
  stopifnot(identical(scworkbench:::.wb_getter_artifact_provenance_refs(con,"1",policy),character()))
  DBI::dbExecute(con,"UPDATE artifacts SET provenance_json=?;",params=list(paste0('{"ignored":"',strrep("a",262145L),'"}')))
  error <- tryCatch(scworkbench:::.wb_getter_artifact_provenance_refs(con,"1",policy),error=base::identity)
  stopifnot(inherits(error,"wb_graph_error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"))
  TRUE
}

# R structure() can coerce factor storage and expand compact row.names.
# The large fast path must reject unsupported transformations before hashing
# their original input as though it were the legacy getter's preimage.
test_graph_bounded_legacy_structure_transformation_admission_contract <- function() {
  policy <- .graph_collector_policy()
  scalar <- function(x)paste0('{"type":"',x,'","attributes":{},"value":')
  cases <- list(
    list(text=paste0(scalar("double"),'[',paste(rep("1.25,2.75",30000L),collapse=","),']}'),attrs='"class":{"type":"character","attributes":{},"value":["factor"]}',old_error=FALSE),
    list(text=paste0(scalar("double"),'[',paste(rep("1.25,2.75",30000L),collapse=","),']}'),attrs='"class":{"type":"character","attributes":{},"value":[null]}',old_error=TRUE),
    list(text=paste0(scalar("list"),'[',scalar("character"),'["',strrep("a",300000L),'"]}]}'),attrs='"row.names":{"type":"integer","attributes":{},"value":[null,-3]}',old_error=FALSE))
  for(case in cases) {
    text <- sub('"attributes":{}',paste0('"attributes":{',case$attrs,'}'),case$text,fixed=TRUE)
    baseline <- tryCatch(as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA)),error=base::identity)
    if(case$old_error)stopifnot(inherits(baseline,"error")) else stopifnot(!inherits(baseline,"error"),!identical(baseline,text))
    path <- tempfile("scwb_object_meta_transform_");writeBin(charToRaw(text),path)
    error <- tryCatch(scworkbench:::.wb_getter_metadata_canonical_hash(path,policy),error=base::identity);unlink(path)
    stopifnot(inherits(error,"wb_graph_error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"))
    # The same old-valid transform remains exact under admitted small decoding.
    small <- gsub(strrep("a",300000L),"a",text,fixed=TRUE)
    if(case$attrs==cases[[1L]]$attrs)small <- sub(paste(rep("1.25,2.75",30000L),collapse=","),"1.25,2.75",text,fixed=TRUE)
    if(!case$old_error) {
      path <- tempfile("scwb_object_meta_transform_small_");writeBin(charToRaw(small),path)
      actual <- scworkbench:::.wb_getter_metadata_canonical_hash(path,policy);unlink(path)
      expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(small),digits=NA))
      stopifnot(identical(actual$sha256,digest::digest(expected,algo="sha256",serialize=FALSE)))
    }
  }
  TRUE
}
