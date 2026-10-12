args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-file-lexer-353.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_emitter.R")
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
  list(text='{"type":"integer","attributes":{".Names":{"type":"character","attributes":{},"value":["x"]}},"value":[1]}',name="small_structure_alias"),
  list(text='{"type":"integer","attributes":{"class":{"type":"integer","attributes":{},"value":[1]}},"value":[1]}',name="small_class_coercion")))
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
