test_operation_pack_v3_typed_slice_chunking_catalog_contract <- function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-reference", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  operation <- Filter(function(item) identical(item$name, "chunked_family"),
    manifest$operations)[[1L]]
  catalog <- getFromNamespace(".wb_operation_pack_v3_catalog_definition",
    "scworkbench")
  with_default <- operation
  with_default$params_schema$properties$chunk_size$default <- 128L
  projected <- catalog(with_default)$chunking
  stopifnot(identical(projected, list(chunkable = TRUE, axis = "cells",
      chunk_size_param = "chunk_size", status = "v3_typed_slice_capability",
      chunk_size_default = 128L)),
    is.null(projected$merge))

  without_default <- catalog(operation)$chunking
  stopifnot(identical(without_default,
    projected[setdiff(names(projected), "chunk_size_default")]))

  absent <- operation
  absent$typed_slice_reads <- NULL
  stopifnot(is.null(catalog(absent)$chunking))

  duplicate <- operation
  duplicate$typed_slice_reads[[2L]] <- duplicate$typed_slice_reads[[1L]]
  duplicate$typed_slice_reads[[2L]]$name <- "other_chunks"
  stopifnot(is.null(catalog(duplicate)$chunking))
  duplicate$typed_slice_reads[[2L]]$chunk_axis <- "features"
  stopifnot(is.null(catalog(duplicate)$chunking))

  invalid <- operation
  invalid$typed_slice_reads[[1L]]$chunk_axis <- "features"
  stopifnot(is.null(catalog(invalid)$chunking))
  invalid <- operation
  invalid$params_schema$properties$chunk_size$type <- "number"
  stopifnot(is.null(catalog(invalid)$chunking))
  invalid <- with_default
  invalid$params_schema$properties$chunk_size$default <- 0L
  stopifnot(is.null(catalog(invalid)$chunking))
  TRUE
}
