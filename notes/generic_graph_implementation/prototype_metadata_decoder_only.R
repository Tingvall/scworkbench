args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-file-lexer-353.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_admitted.R")
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
for(value in list(sum,`if`,asNamespace("base"),
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
cat("METADATA_DECODER_ONLY admitted_decoder=5 typed_failure_cleanup=5 prototype_only=TRUE qualification=FALSE PASS\n")
