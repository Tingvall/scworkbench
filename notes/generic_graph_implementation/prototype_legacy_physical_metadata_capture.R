args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load("/tmp/scwb-bounded-json-lexer-prototype-291.so")
initializer <- DBI::dbConnect(RSQLite::SQLite(),":memory:",default.extensions=FALSE)
DBI::dbGetQuery(initializer,"SELECT load_extension(?,?);",params=list(
  "/tmp/scwb-bounded-json-lexer-prototype-291.so","sqlite3_scwbjsonprototype_init"))
DBI::dbDisconnect(initializer)
dyn.load("/tmp/scwb-json-file-lexer-353.so")
source("notes/generic_graph_implementation/prototype_bounded_json_walk.R")
source("notes/generic_graph_implementation/prototype_bounded_legacy_descriptor_families.R")
source("notes/generic_graph_implementation/prototype_bounded_metadata_emitter.R")
source("notes/generic_graph_implementation/prototype_bounded_physical_metadata_closed.R")
source("notes/generic_graph_implementation/prototype_bounded_legacy_payload_metadata_stream.R")
root <- tempfile("legacy_physical_metadata_");bundle <- wb_init_bundle(root)
cells <- c("é","c2","c1","🙂");wb_define_cells(bundle,cells)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
restore <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con,policy,cache_kib=64L)
metadata <- list(list(factor=factor(c("b","a")),date=as.Date("2026-10-11"),nested=list()),
  list(long=strrep("é🙂",50000L)),list(markers=rep(c("NA","Inf","NaN","x","é🙂"),10000L)))
count <- 0L
for(kind in c("cell_vector","cell_vector_family"))for(meta in metadata) {
  prim <- if(kind=="cell_vector")wb_prim_cell_vector(setNames(c("a","b","c","d"),rev(cells)),meta=meta) else
    wb_prim_cell_vector_family(key=c("k2","k1","k2","k1"),cell_id=rev(cells),value=c(NA_real_,1/3,1e-20,1e20),meta=meta)
  run <- wb_new_run("metadata_cell_vector",list(),list(),list(vector=prim))
  promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs="vector")
  id <- promoted$promoted$artifact_id[promoted$promoted$output=="vector"][[1L]]
  actual <- wb_art_load(bundle,id)
  expected <- scworkbench:::.wb_prov_payload_identity(bundle,actual)$content_sha256
  selector <- DBI::dbConnect(RSQLite::SQLite(),file.path(root,"db/app.sqlite"),flags=RSQLite::SQLITE_RO,cache_size=-64)
  DBI::dbExecute(selector,"PRAGMA temp_store=FILE;")
  descriptor <- prototype_legacy_descriptor_families(bundle$con,selector,id,policy)
  fun <- if(kind=="cell_vector")prototype_legacy_cell_vector_stream_hash else prototype_legacy_cell_family_stream_hash
  payload <- fun(bundle$con,selector,id,policy,descriptor)
  if(!identical(expected,payload$sha256)) {
    expected_text <- as.character(jsonlite::serializeJSON(unclass(actual),digits=NA))
    writeBin(charToRaw(expected_text),"/tmp/scwb-metadata-365.expected")
    capture_hash <- function(emitter,budgets) {
      sink <- file("/tmp/scwb-metadata-365.actual","wb");on.exit(close(sink))
      scworkbench:::.wb_graph_token_hash(function(emit)emitter(function(text){writeBin(charToRaw(enc2utf8(text)),sink);emit(text)}),budgets)
    }
    rewrite <- function(x) {
      if(!is.call(x))return(x)
      if(is.call(x[[1L]]) && identical(as.character(x[[1L]]),c(":::" ,"scworkbench",".wb_graph_token_hash")))x[[1L]] <- as.name("capture_hash")
      for(j in seq_along(x)[-1L])x[j] <- list(rewrite(x[[j]]))
      x
    }
    body(fun) <- rewrite(body(fun));fun(bundle$con,selector,id,policy,descriptor)
    stop("CAPTURED legacy metadata mismatch")
  }
  stopifnot(identical(expected,payload$sha256),descriptor$rows==4L)
  DBI::dbDisconnect(selector);count <- count+1L
  cat("LEGACY_PHYSICAL_METADATA case=",count," kind=",kind," bytes=",payload$metadata_bytes,
    " whole_old_getter_sha=PASS prototype_only=TRUE\n",sep="");flush.console()
}
restore();wb_close_bundle(bundle);unlink(root,recursive=TRUE)
cat("LEGACY_PHYSICAL_METADATA_FOCUSED executed=6 passed=6 skipped=0 qualification=FALSE PASS\n")
