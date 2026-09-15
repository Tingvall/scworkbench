test_operation_pack_v2_manifest_owned_statistics_contract <- function() {
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

test_operation_pack_v2_observed_chunk_trace_fail_closed_contract <- function() {
  contract_test_activate_statistics_pack()
  bundle <- wb_init_bundle(tempfile("scwb_chunk_trace_fail_"), overwrite = TRUE)
  on.exit(wb_close_bundle(bundle), add = TRUE)
  cells <- paste0("c", 1:12); features <- paste0("g", 1:5)
  values <- matrix(seq_len(60), nrow = 5L,
    dimnames = list(features, cells))
  matrix_input <- structure(list(kind = "matrix", matrix_id = "fixture",
    values = values, dimensions = as.integer(dim(values)), feature_id = features,
    cell_id = cells, storage_profile = "matrix_ordinary_v1"), class = "wb_primitive")
  pseudotime <- wb_prim_cell_vector(stats::setNames(seq_along(cells), cells),
    "continuous")
  pack_record <- .wb_operation_pack_registry$packs$scwbstatistics
  registration <- pack_record$registration
  original <- registration$runners[["scwbstatistics::feature_trend_spearman"]]
  registration$runners[["scwbstatistics::feature_trend_spearman"]] <-
    function(readers, writers, params, context) {
      full <- readers$matrix()
      proxy <- readers
      proxy$matrix <- function(features = NULL, cells = NULL) {
        features <- as.character(features %||% full$feature_id)
        cells <- as.character(cells %||% full$cell_id)
        value <- full
        value$values <- full$values[match(features, full$feature_id),
          match(cells, full$cell_id), drop = FALSE]
        value$feature_id <- features; value$cell_id <- cells
        value$dimensions <- as.integer(dim(value$values)); value
      }
      original(proxy, writers, params, context)
    }
  pack_record$registration <- registration
  .wb_operation_pack_registry$packs$scwbstatistics <- pack_record
  on.exit({
    current <- .wb_operation_pack_registry$packs$scwbstatistics
    current$registration$runners[["scwbstatistics::feature_trend_spearman"]] <- original
    .wb_operation_pack_registry$packs$scwbstatistics <- current
  }, add = TRUE)
  root <- file.path(bundle$dir, "operation_pack_v2")
  before <- if (dir.exists(root)) list.files(root, recursive = TRUE, all.files = TRUE) else character()
  error <- tryCatch(.wb_operation_pack_v2_execute(bundle,
    "scwbstatistics::feature_trend_spearman",
    list(matrix = matrix_input, pseudotime = pseudotime),
    list(features = as.list(features), min_pct_nonzero = 0, min_sd = 0,
      p_adjust_method = "BH", chunk_size = 2L)), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v2_error"),
    identical(as.character(error$code), "PYBENCH_CAPABILITY_MISMATCH"))
  after <- if (dir.exists(root)) list.files(root, recursive = TRUE, all.files = TRUE) else character()
  stopifnot(identical(before, after))
  TRUE
}
