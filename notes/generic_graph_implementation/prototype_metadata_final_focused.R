args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-typed-366.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_retained_carriers.R")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",
  sqlite_cache_kib=2048L,partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
cases <- list(NULL,list(),c(TRUE,FALSE,NA),c(1L,NA_integer_),
  c(1/3,-0,1e-20,1e20,NA_real_,NaN,Inf,-Inf),c('é🙂','quote"','backslash\\','line\n',NA_character_),
  list(factor=factor(c('b','a')),date=as.Date('2026-10-11'),nested=list(a=1,b=list())),
  matrix(1:4,2L,dimnames=list(c('a','b'),c('x','y'))),
  ts(1:5,start=c(2001,2),frequency=4),data.frame(x=1:3,y=c('a','b','c')),
  structure(1:3,custom=list(a='é🙂')),as.raw(0:255),as.pairlist(list(a=1,b='x')),
  quote(foo(a=1,b='é🙂')),expression(a+b),
  list(huge=strrep('é🙂',400000L)),
  setNames(rep(c('é🙂','a','quote"'),20000L),rep('long_name',60000L)),
  list(many=as.list(seq_len(10000L))),
  rep(as.raw(0:255),5000L))
for(i in seq_along(cases)) {
  input <- as.character(jsonlite::serializeJSON(cases[[i]],digits=NA))
  expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(input),digits=NA))
  path <- tempfile('scwb_object_meta_canonical_');writeBin(charToRaw(enc2utf8(input)),path)
  time <- system.time(actual <- prototype_metadata_canonical_hash(path,policy))
  stopifnot(identical(actual$sha256,digest::digest(expected,algo='sha256',serialize=FALSE)))
  unlink(path)
  cat('BOUNDED_METADATA case=',i,' bytes=',nchar(input,type='bytes'),
    ' exact_old_roundtrip_hash=TRUE elapsed=',time[['elapsed']],' PASS\n',sep='');flush.console()
}
cat('BOUNDED_METADATA_FOCUSED executed=',length(cases),' passed=',length(cases),
  ' skipped=0 prototype_only=TRUE qualification=FALSE\n',sep='')

args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-typed-366.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_retained_carriers.R")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
check <- function(text,name) {
  path <- tempfile("scwb_object_meta_edge_");writeBin(charToRaw(text),path)
  on.exit(unlink(path))
  expected <- suppressWarnings(as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA)))
  actual <- prototype_metadata_canonical_hash(path,policy)
  stopifnot(identical(actual$sha256,digest::digest(expected,algo="sha256",serialize=FALSE)))
  cat("METADATA_EDGE",name,"bytes=",nchar(text,type="bytes"),"old_hash=PASS\n");flush.console()
}
for(case in list(list(type="double",values='true,1.25,"NA",-0.0'),
  list(type="integer",values='true,1.25,"5",null'),
  list(type="logical",values='true,1.25,"FALSE",null'),
  list(type="character",values='true,1.25,null'),
  list(type="double",values='-0.0,1.25'))) {
  text <- paste0('{"type":"',case$type,'","attributes":{},"value":[',
    paste(rep(case$values,30000L),collapse=','),']}')
  check(text,paste0("large_common_coercion_",case$type))
}
for(value in list(sum,`if`,asNamespace("scworkbench"),
  expression({stop("metadata expression must not execute")}),
  function(x=stop("metadata default must not execute"))stop("metadata body must not execute")))
  check(as.character(jsonlite::serializeJSON(value,digits=NA)),paste0("admitted_",typeof(value)))

paths <- list.files(tempdir(),pattern="^scwb_(object_meta_codec_admission_|graph_identity_metadata_keys_)",full.names=TRUE)
failure <- function(text,code,name) {
  path <- tempfile("scwb_object_meta_reject_");writeBin(charToRaw(text),path)
  on.exit(unlink(path))
  error <- tryCatch(prototype_metadata_canonical_hash(path,policy),error=identity)
  stopifnot(inherits(error,"error"),identical(error$code,code),
    identical(paths,list.files(tempdir(),pattern="^scwb_(object_meta_codec_admission_|graph_identity_metadata_keys_)",full.names=TRUE)))
  cat("METADATA_EDGE",name,"typed_failure=",code,"cleanup=PASS\n");flush.console()
}
failure('{"type":"S4","attributes":{},"value":{"class":"unadmitted","package":"unadmitted"}}',
  "GRAPH_RESOURCE_EXCEEDED","opaque_constructor_before_decode")
failure('{"type":"namespace","attributes":{},"value":{"name":"scwb_unloaded_metadata_package","version":"1"}}',
  "GRAPH_RESOURCE_EXCEEDED","namespace_before_load")
failure('{"type":"integer","attributes":{"class":{"type":"character","attributes":{},"value":["NativeSymbolInfo"]}},"value":[1]}',
  "GRAPH_RESOURCE_EXCEEDED","native_symbol_before_load")
failure('{"type":"builtin","attributes":{},"value":"WAoAAAAD"}',
  "GRAPH_RESOURCE_EXCEEDED","opaque_serialization_before_decode")
failure('{"type":"character","attributes":{},"value":["unterminated]}',
  "GRAPH_SOURCE_PAYLOAD_INVALID","malformed_json")
cat("METADATA_EDGE_FOCUSED old_coercion=5 admitted_decoder=5 typed_failure_cleanup=5 prototype_only=TRUE qualification=FALSE PASS\n")

args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-typed-366.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_retained_carriers.R")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
inventory <- function()list.files(tempdir(),pattern="^scwb_(object_meta_codec_admission_|graph_identity_metadata_keys_|graph_identity_)",full.names=TRUE)
check <- function(text,name) {
  path <- tempfile("scwb_object_meta_emitter_");writeBin(charToRaw(enc2utf8(text)),path)
  on.exit(unlink(path));before <- inventory()
  expected <- suppressWarnings(as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA)))
  actual <- scworkbench:::.wb_graph_token_hash(function(emit)
    prototype_metadata_canonical_hash(path,policy,external_emit=emit),policy)
  stopifnot(identical(actual,digest::digest(expected,algo="sha256",serialize=FALSE)),identical(before,inventory()))
  cat("METADATA_EMITTER",name,"bytes=",nchar(text,type="bytes"),"old_hash=PASS cleanup=PASS\n");flush.console()
}
for(case in list(
  list(text='{"type":"integer","attributes":{"names":{"type":"character","attributes":{},"value":["a"]}},"value":[1,2]}',name="small_names_padding"),
  list(text='{"type":"integer","attributes":{"foo":{"type":"NULL"}},"value":[1]}',name="small_null_attribute_removed"),
  list(text='{"type":"integer","attributes":{".Names":{"type":"character","attributes":{},"value":["x"]}},"value":[1]}',name="small_structure_alias")))
  check(case$text,case$name)
for(value in list(list(huge=strrep("é🙂",50000L)),factor(rep(c("a","b"),100000L)),
  matrix(seq_len(60000L),ncol=2L),data.frame(x=seq_len(20000L),y=rep("é🙂",20000L))))
  check(as.character(jsonlite::serializeJSON(value,digits=NA)),paste0("large_canonical_",class(value)[[1L]]))
failure <- function(text,code,name,change=FALSE) {
  path <- tempfile("scwb_object_meta_emitter_reject_");writeBin(charToRaw(enc2utf8(text)),path)
  on.exit(unlink(path));before <- inventory();changed <- FALSE
  emit <- if(change)function(value) {
    if(!changed){out <- file(path,"r+b");seek(out,where=file.info(path)$size-4L);writeBin(charToRaw("b"),out);close(out);changed <<- TRUE}
  } else NULL
  error <- tryCatch(prototype_metadata_canonical_hash(path,policy,external_emit=emit),error=identity)
  stopifnot(inherits(error,"error"),identical(error$code,code),identical(before,inventory()))
  cat("METADATA_EMITTER",name,"code=",code,"cleanup=PASS\n");flush.console()
}
failure('{"type":"integer","attributes":{"class":{"type":"integer","attributes":{},"value":[1]}},"value":[1]}',"GRAPH_SOURCE_PAYLOAD_INVALID","small_invalid_class")
bigvalue <- paste0('["',strrep("a",300000L),'"]')
for(case in list(
  list(attrs='"names":{"type":"character","attributes":{},"value":["a","b"]}',name="large_names_transform"),
  list(attrs='"foo":{"type":"NULL"}',name="large_null_transform"),
  list(attrs='".Names":{"type":"character","attributes":{},"value":["a"]}',name="large_structure_alias"),
  list(attrs='"class":{"type":"integer","attributes":{},"value":[1]}',name="large_class_transform"),
  list(attrs='"class":{"type":"character","attributes":{},"value":["NativeSymbolInfo"]}',name="large_native_symbol_predecode")))
  failure(paste0('{"type":"character","attributes":{',case$attrs,'},"value":',bigvalue,'}'),"GRAPH_RESOURCE_EXCEEDED",case$name)
failure(paste0('{"type":"character","attributes":{},"value":',bigvalue,'}'),"GRAPH_SOURCE_PAYLOAD_INVALID","late_file_change",TRUE)
failure(paste0('{"type":"integer","attributes":{},"value":[',paste(rep("1",10000L),collapse=","),']}'),"GRAPH_RESOURCE_EXCEEDED","small_old_codec_carrier_bound")
cat("METADATA_EMITTER_HOSTILE executed=15 passed=15 prototype_only=TRUE qualification=FALSE PASS\n")

args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load("/tmp/scwb-json-typed-366.so")
initializer <- DBI::dbConnect(RSQLite::SQLite(),":memory:",default.extensions=FALSE)
DBI::dbGetQuery(initializer,"SELECT load_extension(?,?);",params=list(
  "/tmp/scwb-json-typed-366.so","sqlite3_scwbjsonprototype_init"))
DBI::dbDisconnect(initializer)
dyn.load("/tmp/scwb-json-typed-366.so")
source("notes/generic_graph_implementation/prototype_bounded_json_walk.R")
source("notes/generic_graph_implementation/prototype_bounded_legacy_descriptor_families.R")
source("notes/generic_graph_implementation/prototype_bounded_metadata_retained_carriers.R")
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
  stopifnot(identical(expected,payload$sha256),descriptor$rows==4L)
  DBI::dbDisconnect(selector);count <- count+1L
  cat("LEGACY_PHYSICAL_METADATA case=",count," kind=",kind," bytes=",payload$metadata_bytes,
    " whole_old_getter_sha=PASS prototype_only=TRUE\n",sep="");flush.console()
}
restore();wb_close_bundle(bundle);unlink(root,recursive=TRUE)
cat("LEGACY_PHYSICAL_METADATA_FOCUSED executed=6 passed=6 skipped=0 qualification=FALSE PASS\n")
