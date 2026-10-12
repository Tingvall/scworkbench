# Diagnostic admission for the existing codec, including opaque decoder cost.
# JSON carrier bounds do not establish an arbitrary S4 constructor/package
# loader's memory bound. These operations fail operational admission first.
prototype_metadata_admitted_old_codec <- function(text,budgets) {
  bytes <- nchar(text,type="bytes")
  fail <- function(message)scworkbench:::.wb_graph_error("GRAPH_RESOURCE_EXCEEDED",message)
  if(bytes>budgets$partition_bytes)fail("Metadata old-codec input exceeds decoded partition.")
  usage <- scworkbench:::.wb_graph_transient_usage(budgets=budgets)
  if(usage$owned_spill_bytes+scworkbench:::.wb_graph_session_copy_reservation(budgets)+bytes>
      as.numeric(budgets$token_bytes))fail("Metadata old-codec temporary copy exceeds combined spill admission.")
  path <- tempfile("scwb_object_meta_codec_admission_")
  writeBin(charToRaw(enc2utf8(text)),path);on.exit(unlink(path),add=TRUE)
  pointer <- .Call("prototype_json_lexer_file_open",path,as.numeric(budgets$token_bytes))
  on.exit(.Call("prototype_json_lexer_close",pointer),add=TRUE,after=FALSE)
  scworkbench:::.wb_graph_spill_admit(budgets,path)
  count <- 0
  tryCatch(repeat {
    token <- .Call("prototype_json_lexer_next",pointer);count <- count+1
    if(4*bytes+256*count>8*budgets$partition_bytes)
      fail("Metadata old-codec JSON carriers exceed decoded admission.")
    if(token$type=="end")break
  },finally=.Call("prototype_json_lexer_close",pointer))
  parsed <- jsonlite::fromJSON(text,simplifyVector=FALSE)
  code_bytes <- 0
  primitive_binary <- function(value,type) {
    if(!is.character(value) || length(value)!=1L || nchar(value)>2048L)
      fail("Opaque R primitive decoder cannot be admitted.")
    raw <- tryCatch(jsonlite::base64_dec(value),error=function(e)NULL)
    if(is.null(raw) || length(raw)<22L || !identical(raw[1:2],charToRaw("X\n")))
      fail("Opaque R serialization format has no bounded decoder proof.")
    uint <- function(at) {
      if(at+3L>length(raw))fail("Opaque R serialization header cannot be admitted.")
      sum(as.integer(raw[at+0:3])*c(16777216,65536,256,1))
    }
    version <- uint(3L);at <- 15L
    if(version==3L) {
      encoding_bytes <- uint(at);at <- at+4L+encoding_bytes
      if(encoding_bytes>128L)fail("Opaque R serialization encoding exceeds admission.")
    } else if(version!=2L)fail("Opaque R serialization version has no decoder proof.")
    if(uint(at)!=if(type=="builtin")8L else 7L)
      fail("Opaque R primitive root/attributes require an unadmitted decoder.")
    name_bytes <- uint(at+4L)
    if(name_bytes>128L || at+7L+name_bytes!=length(raw))
      fail("Opaque R primitive payload exceeds bounded name-only admission.")
  }
  audit <- function(object,depth=1L) {
    if(depth>min(256L,floor(budgets$partition_bytes/2048)))fail("Metadata decoder stack exceeds admission.")
    if(!is.list(object))return(invisible(NULL))
    type <- object$type
    if(!is.character(type) || length(type)!=1L)return(invisible(NULL))
    if(type=="NULL")return(invisible(NULL))
    if(type=="S4")fail("S4 constructor memory cannot be admitted from its encoded metadata size.")
    if(type=="namespace") {
      name <- object$value$name
      if(!is.character(name) || length(name)!=1L || !isNamespaceLoaded(name))
        fail("Namespace loading memory cannot be admitted from encoded metadata size.")
    }
    if(type %in% c("builtin","special"))primitive_binary(object$value,type)
    for(name in c("class",".Class")) {
    class <- object$attributes[[name]]
    if(is.list(class) && identical(class$type,"character") &&
      "NativeSymbolInfo" %in% unlist(class$value,use.names=FALSE))
      fail("Native symbol loading memory cannot be admitted from encoded metadata size.")
    }
    if(type %in% c("language","expression","name","symbol")) {
      source <- unlist(object$value,recursive=FALSE,use.names=FALSE)
      code_bytes <<- code_bytes+sum(nchar(as.character(source),type="bytes"))
      if(4*bytes+256*count+1024*code_bytes>8*budgets$partition_bytes)
        fail("R code parser carriers exceed metadata decoded admission.")
    }
    if(is.list(object$attributes))for(attribute in object$attributes)audit(attribute,depth+1L)
    if(type %in% c("list","pairlist","closure") && is.list(object$value))
      for(child in object$value)audit(child,depth+1L)
    invisible(NULL)
  }
  audit(parsed)
  decoded <- jsonlite::unserializeJSON(text)
  canonical <- as.character(jsonlite::serializeJSON(decoded,digits=NA))
  if(nchar(canonical,type="bytes")>budgets$partition_bytes)
    fail("Metadata old-codec encoded result exceeds decoded admission.")
  list(text=canonical,type=typeof(decoded),length=length(decoded),
    attribute_count=length(attributes(decoded)))
}
