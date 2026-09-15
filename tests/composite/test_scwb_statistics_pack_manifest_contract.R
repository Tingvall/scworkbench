test_manifest_owned_statistics_boundary <- function() {
  dispatch_sources <- paste(unlist(lapply(c("R/operation_packs_v2.R",
    "R/operation_pack_v2_transition.R"), readLines, warn = FALSE), use.names = FALSE),
    collapse = "\n")
  stopifnot(!grepl("scwbstatistics", dispatch_sources, fixed = TRUE),
    !grepl("migration_catalog_overlay", dispatch_sources, fixed = TRUE),
    !grepl("migrated_result_params", dispatch_sources, fixed = TRUE),
    !grepl("resolve_migrated_params", dispatch_sources, fixed = TRUE))
  source <- Sys.getenv("SCWBSTATISTICS_SOURCE", unset = "")
  stopifnot(nzchar(source), dir.exists(source))
  manifest <- jsonlite::read_json(file.path(source, "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  .wb_operation_pack_v2_outer_validate(manifest)
  .wb_operation_pack_v2_semantic_validate(manifest)

  trend <- manifest$operations[[which(vapply(manifest$operations, function(x)
    identical(x$name, "feature_trend_spearman"), logical(1)))]]
  input <- structure(list(kind = "matrix", matrix_id = "m",
    values = matrix(0, nrow = 5L, ncol = 12L,
      dimnames = list(paste0("g", 1:5), paste0("c", 1:12))),
    dimensions = c(5L, 12L), feature_id = paste0("g", 1:5),
    cell_id = paste0("c", 1:12), storage_profile = "matrix_ordinary_v1"),
    class = "wb_primitive")
  policy <- trend$dimension_policies[[1]]$policy
  declared <- .wb_operation_pack_v2_expected_dimensions(trend$outputs[[1]],
    list(matrix = input), policy)
  undeclared <- .wb_operation_pack_v2_expected_dimensions(trend$outputs[[1]],
    list(matrix = input), NULL)
  stopifnot(identical(declared, c(0L, 0L)), identical(undeclared, c(1L, 1L)))

  other <- manifest
  other$namespace <- "otherstats"
  for (i in seq_along(other$operations)) {
    other$operations[[i]]$qualified_name <- paste0("otherstats::",
      other$operations[[i]]$name)
  }
  .wb_operation_pack_v2_semantic_validate(other)
  stopifnot(identical(.wb_operation_pack_v2_expected_dimensions(
    other$operations[[6]]$outputs[[1]], list(matrix = input),
    other$operations[[6]]$dimension_policies[[1]]$policy), c(0L, 0L)))

  expect_semantic_failure <- function(value) {
    error <- tryCatch({ .wb_operation_pack_v2_semantic_validate(value); NULL },
      error = identity)
    stopifnot(inherits(error, "wb_operation_pack_v2_error"),
      identical(as.character(error$code), "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID"))
  }
  bad <- manifest
  bad$operations[[6]]$dimension_policies[[1]]$output <- "missing"
  expect_semantic_failure(bad)
  for (kind in c("matrix", "space", "model_ref", "cell_set_admission")) {
    bad <- manifest
    bad$operations[[6]]$outputs[[1]]$kind <- kind
    expect_semantic_failure(bad)
  }
  for (field in c("input", "sequence_parameter", "size_parameter", "output",
                  "adjust_parameter")) {
    bad <- manifest
    bad$operations[[6]]$chunking[[field]] <- "missing"
    expect_semantic_failure(bad)
  }
  bad <- manifest
  bad$operations[[6]]$chunking$size_parameter <-
    bad$operations[[6]]$chunking$sequence_parameter
  expect_semantic_failure(bad)
  bad <- manifest
  bad$operations[[6]]$chunking$output <-
    bad$operations[[6]]$chunking$input
  expect_semantic_failure(bad)
  bad <- manifest
  bad$operations[[6]]$dimension_policies <- c(bad$operations[[6]]$dimension_policies,
    bad$operations[[6]]$dimension_policies)
  expect_semantic_failure(bad)
  bad <- manifest
  bad$operations[[6]]$public_interface$parameters[[1]]$type <- "int"
  expect_semantic_failure(bad)

  snapshot <- ls(.wb_operation_pack_registry$operations, all.names = TRUE)
  bad <- manifest
  bad$operations <- c(bad$operations, list(bad$operations[[6]]))
  bad$operations[[7]]$name <- "late_invalid"
  bad$operations[[7]]$qualified_name <- "scwbstatistics::late_invalid"
  bad$operations[[7]]$chunking$input <- "missing"
  expect_semantic_failure(bad)
  stopifnot(identical(ls(.wb_operation_pack_registry$operations, all.names = TRUE), snapshot))
  TRUE
}
