test_operation_pack_v2_observed_chunk_trace_fail_closed_contract <- function() {
  contract_test_activate_core_conformance_pack()
  bundle <- wb_init_bundle(tempfile("scwb_chunk_trace_fail_"), overwrite = TRUE)
  on.exit(wb_close_bundle(bundle), add = TRUE)
  cells <- paste0("c", 1:12); features <- paste0("g", 1:5)
  values <- matrix(seq_len(60), nrow = 5L, dimnames = list(features, cells))
  matrix_input <- structure(list(kind = "matrix", matrix_id = "fixture",
    values = values, dimensions = as.integer(dim(values)), feature_id = features,
    cell_id = cells, storage_profile = "matrix_ordinary_v1"), class = "wb_primitive")
  pack_record <- .wb_operation_pack_registry$packs$scwbv2reference
  registration <- pack_record$registration
  original <- registration$runners[["scwbv2reference::chunked_feature_table"]]
  registration$runners[["scwbv2reference::chunked_feature_table"]] <-
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
  .wb_operation_pack_registry$packs$scwbv2reference <- pack_record
  on.exit({
    current <- .wb_operation_pack_registry$packs$scwbv2reference
    current$registration$runners[["scwbv2reference::chunked_feature_table"]] <- original
    .wb_operation_pack_registry$packs$scwbv2reference <- current
  }, add = TRUE)
  root <- file.path(bundle$dir, "operation_pack_v2")
  before <- if (dir.exists(root)) list.files(root, recursive = TRUE, all.files = TRUE) else character()
  error <- tryCatch(.wb_operation_pack_v2_execute(bundle,
    "scwbv2reference::chunked_feature_table", list(matrix = matrix_input),
    list(items = as.list(features), adjustment_method = "BH", batch_size = 2L)),
    error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v2_error"),
    identical(as.character(error$code), "PYBENCH_CAPABILITY_MISMATCH"))
  after <- if (dir.exists(root)) list.files(root, recursive = TRUE, all.files = TRUE) else character()
  stopifnot(identical(before, after))
  TRUE
}
