args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-typed-366.so")
source("notes/generic_graph_implementation/prototype_metadata_admitted_old_codec_predicate_guard.R")
text <- paste0('{"type":"integer","attributes":{},"value":[',paste(rep("1",100L),collapse=","),']}')
path <- tempfile("scwb_object_meta_boundary_");writeBin(charToRaw(text),path)
pointer <- .Call("prototype_json_lexer_file_open",path,1e6);count <- 0
repeat {token <- .Call("prototype_json_lexer_next",pointer);count <- count+1;if(token$type=="end")break}
.Call("prototype_json_lexer_close",pointer);unlink(path)
required <- ceiling((4*nchar(text,type="bytes")+256*count)/8)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=as.integer(required),partition_rows=256L,collect_bytes=4194304L))
actual <- prototype_metadata_admitted_old_codec(text,policy)
stopifnot(identical(actual$text,as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA))))
policy$partition_bytes <- policy$partition_bytes-1L
error <- tryCatch(prototype_metadata_admitted_old_codec(text,policy),error=identity)
stopifnot(inherits(error,"error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"))
cat("METADATA_CODEC_BOUNDARY tokens=",count," bytes=",nchar(text,type="bytes")," partition_exact=",required,
  " exactPASS below1ResourcePASS\n",sep="")
source("notes/generic_graph_implementation/prototype_bounded_metadata_retained_carriers.R")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
path <- tempfile("scwb_object_meta_class_")
text <- as.character(jsonlite::serializeJSON(structure(strrep("a",300000L),class=rep("ordinary_custom_class",2000L)),digits=NA))
writeBin(charToRaw(text),path)
error <- tryCatch(prototype_metadata_canonical_hash(path,policy),error=identity);unlink(path)
stopifnot(inherits(error,"error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"))
cat("METADATA_RETAINED_CLASS global_carrier_rejection=PASS\n")
# Conditional native-symbol class predicates would be arbitrary user code.
# Reject before the legacy decoder can invoke methods::is or symbol loading.
methods::setClass("NativeSymbolInfo",contains="list")
executed <- FALSE
methods::setClass("scwb_metadata_decoder_test",contains="numeric")
methods::setIs("scwb_metadata_decoder_test","NativeSymbolInfo",test=function(object){executed <<- TRUE;TRUE},coerce=function(object)list())
text <- '{"type":"double","attributes":{"class":{"type":"character","attributes":{},"value":["scwb_metadata_decoder_test"]}},"value":[1]}'
error <- tryCatch(prototype_metadata_admitted_old_codec(text,policy),error=identity)
stopifnot(inherits(error,"error"),identical(error$code,"GRAPH_RESOURCE_EXCEEDED"),!executed)
cat("METADATA_PREDICATE before_arbitrary_test=PASS no_execution=PASS\n")
cat("METADATA_ADMISSION_BOUNDARY executed=4 passed=4 prototype_only=TRUE qualification=FALSE PASS\n")
