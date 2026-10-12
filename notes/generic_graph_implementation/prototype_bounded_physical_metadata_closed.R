# Diagnostic getter: pre-admit each physical chunk, copy via the owning
# RSQLite engine's incremental byte API, retain snapshot and file lifetimes.
prototype_physical_metadata_stream <- function(con,id,budgets,descriptor,callback) {
  path <- tempfile("scwb_object_meta_stream_")
  on.exit(unlink(path),add=TRUE)
  sink <- file(path,"wb")
  on.exit(if(!is.null(sink))close(sink),add=TRUE)
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  stopifnot(!is.null(observer))
  on.exit(observer$close(),add=TRUE)
  next_row <- "0";bytes <- 0
  repeat {
    row <- DBI::dbGetQuery(con,paste0("SELECT CAST(rowid AS TEXT) source_rowid,",
      "CAST(chunk_ordinal AS TEXT) ordinal,typeof(chunk) type,length(chunk) bytes ",
      "FROM artifact_object_metadata_chunks WHERE artifact_id=? AND chunk_ordinal>=CAST(? AS INTEGER) ",
      "ORDER BY chunk_ordinal LIMIT 1;"),params=list(id,next_row))
    if(!nrow(row))break
    scworkbench:::.wb_graph_require(nrow(row)==1L && identical(row$ordinal[[1L]],next_row) &&
      row$type[[1L]]=="blob" && row$bytes[[1L]]>0L && row$bytes[[1L]]<=min(65536L,budgets$partition_bytes),
      "GRAPH_SOURCE_PAYLOAD_INVALID","Physical metadata chunk failed admission.")
    size <- observer$column(row$source_rowid[[1L]],"chunk","artifact_object_metadata_chunks")
    scworkbench:::.wb_graph_require(identical(attr(size,"wb_sqlite_type"),"blob") && size==row$bytes[[1L]],
      "GRAPH_SOURCE_PAYLOAD_INVALID","Physical metadata chunk changed before copying.")
    bytes <- bytes+as.numeric(size)
    scworkbench:::.wb_graph_require(is.finite(bytes) && bytes<=as.numeric(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED","Physical metadata file exceeds spill admission.")
    offset <- 0
    while(offset<size) {
      take <- min(4096L,size-offset)
      writeBin(observer$read(offset,take),sink);offset <- offset+take
    }
    flush(sink);scworkbench:::.wb_graph_spill_admit(budgets,path)
    next_row <- scworkbench:::.wb_graph_add_count(next_row,1L)
  }
  close(sink);sink <- NULL
  scworkbench:::.wb_graph_require(bytes==as.numeric(descriptor$metadata_bytes) &&
    identical(digest::digest(file=path,algo="sha256",serialize=FALSE),descriptor$metadata_sha256),
    "GRAPH_SOURCE_PAYLOAD_INVALID","Physical metadata bytes differ from independently verified descriptor.")
  guard <- file(path,"rb");on.exit(close(guard),add=TRUE)
  scworkbench:::.wb_graph_spill_admit(budgets,path)
  result <- callback(path)
  observer$finish()
  result
}
