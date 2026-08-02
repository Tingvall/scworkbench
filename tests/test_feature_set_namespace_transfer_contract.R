test_feature_set_namespace_transfer_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  tmp <- tempfile("scwb_feature_set_transfer_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(4))
  wb_define_cells(b, cells)
  mat <- Matrix::Matrix(
    matrix(
      c(
        1, 0, 3, 2,
        0, 2, 4, 1,
        5, 1, 0, 3
      ),
      nrow = 3,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  wb_feature_set_replace(
    bundle = b,
    feature_set = "SET_A",
    matrix_id = "RNA_counts",
    feature_ids = c("g1", "g2"),
    namespace = "test_ns",
    organism = "mouse",
    source_id = "test_source",
    source_version = "v1",
    origin = "test",
    strict = TRUE,
    created_by = "test"
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = "SET_B",
    matrix_id = "RNA_counts",
    feature_ids = c("g2", "g3"),
    namespace = "test_ns",
    organism = "mouse",
    source_id = "test_source",
    source_version = "v1",
    origin = "test",
    strict = TRUE,
    created_by = "test"
  )

  r_norm <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b,
    op_name = "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log_norm",
      scale_factor = 10000,
      overwrite = TRUE
    )
  )
  stopifnot(identical(as.character(r_norm$run$outputs$matrix$matrix_id), "RNA_log_norm"))

  iface <- wb_op_interface("feature_set_namespace_transfer")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$transfer_manifest$kind), "obs_table"))
  stopifnot("feature_set_namespace_transfer" %in% wb_list_ops())

  s <- r_norm$session
  r <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "feature_set_namespace_transfer",
    inputs = list(
      cell_set = "all",
      min_cells = 1L,
      source_matrix = "RNA_counts",
      target_matrix = "RNA_log_norm",
      namespace = "test_ns",
      mode = "mirror",
      overwrite = TRUE,
      strict = TRUE,
      created_by = "test",
      notes = "contract test"
    ),
    notes = "test feature-set namespace transfer"
  )
  s <- r$session
  manifest <- r$run$outputs$transfer_manifest
  stopifnot(inherits(manifest, "wb_primitive"))
  stopifnot(identical(as.character(manifest$table_type), "feature_set_transfer_manifest"))
  stopifnot(nrow(manifest$table) == 2L)
  stopifnot(all(as.character(manifest$table$status) == "transferred"))
  stopifnot(all(as.character(manifest$table$source_matrix_id) == "RNA_counts"))
  stopifnot(all(as.character(manifest$table$target_matrix_id) == "RNA_log_norm"))
  stopifnot(all(as.character(manifest$table$mode) == "mirror"))
  stopifnot(all(as.integer(manifest$table$n_dropped_features) == 0L))

  fs_target <- wb_feature_sets(wb_session_view(s), matrix_id = "RNA_log_norm", namespace = "test_ns")
  stopifnot(is.data.frame(fs_target), nrow(fs_target) == 2L)
  stopifnot(setequal(as.character(fs_target$feature_set), c("SET_A", "SET_B")))
  stopifnot(identical(wb_feature_set_get(wb_session_view(s), "SET_A", "RNA_log_norm"), c("g1", "g2")))

  prom <- wb_session_promote_current(
    bundle = b,
    session = s,
    name_prefix = "Feature Set Transfer Test",
    fail_fast = TRUE,
    outputs = "transfer_manifest"
  )
  manifest_artifact_id <- as.character(prom$promoted$artifact_id[
    as.character(prom$promoted$output) == "transfer_manifest"
  ][1])
  stopifnot(nzchar(manifest_artifact_id))
  loaded_manifest <- wb_art_load(b, manifest_artifact_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_manifest$table_type), "feature_set_transfer_manifest"))

  dag <- wb_prov_bundle_dag(b)
  mut <- dag$edges[
    as.character(dag$edges$artifact_id) == manifest_artifact_id &
      as.character(dag$edges$edge_type) == "MUTATES_REGISTRY",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(mut) >= 2L)
  stopifnot(any(grepl("^feature_set:test_ns:", as.character(mut$to))))
  stopifnot(any(as.character(dag$edges$edge_type) == "TRANSFERRED_TO"))

  qc <- wb_op_feature_set_overlap_qc(
    bundle = b,
    matrix_id = "RNA_log_norm",
    namespace = "test_ns",
    min_set_size = 1L
  )
  stopifnot(inherits(qc$outputs$overlap_qc, "wb_primitive"))
  stopifnot(nrow(qc$outputs$overlap_qc$table) == 2L)

  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  TRUE
}

test_feature_set_namespace_transfer_intersect_contract <- function() {
  tmp <- tempfile("scwb_feature_set_transfer_intersect_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(3))
  wb_define_cells(b, cells)
  mat_source <- Matrix::Matrix(
    matrix(
      c(
        1, 0, 3,
        0, 2, 4,
        5, 1, 0
      ),
      nrow = 3,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3"), cells)
    ),
    sparse = TRUE
  )
  mat_target <- mat_source[c("g1", "g2"), , drop = FALSE]
  wb_attach_matrix(b, matrix_id = "RNA_source", mat = mat_source, feature_type = "gene")
  wb_attach_matrix(b, matrix_id = "RNA_target", mat = mat_target, feature_type = "gene")

  wb_feature_set_replace(
    bundle = b,
    feature_set = "SET_LOSSY",
    matrix_id = "RNA_source",
    feature_ids = c("g1", "g3"),
    namespace = "lossy_ns",
    strict = TRUE
  )

  strict_err <- try(
    wb_feature_set_namespace_transfer(
      bundle = b,
      source_matrix_id = "RNA_source",
      target_matrix_id = "RNA_target",
      namespace = "lossy_ns",
      mode = "intersect",
      strict = TRUE,
      min_retained_fraction = 0.75
    ),
    silent = TRUE
  )
  stopifnot(inherits(strict_err, "try-error"))
  stopifnot(length(wb_feature_set_get(b, "SET_LOSSY", "RNA_target")) == 0L)

  ok <- wb_feature_set_namespace_transfer(
    bundle = b,
    source_matrix_id = "RNA_source",
    target_matrix_id = "RNA_target",
    namespace = "lossy_ns",
    mode = "intersect",
    strict = FALSE,
    min_retained_features = 1L,
    min_retained_fraction = 0.4,
    overwrite = TRUE
  )
  stopifnot(identical(as.character(ok$outputs$transfer_manifest$table$status[1]), "transferred"))
  stopifnot(identical(as.integer(ok$outputs$transfer_manifest$table$n_retained_features[1]), 1L))
  stopifnot(identical(wb_feature_set_get(b, "SET_LOSSY", "RNA_target"), "g1"))

  mirror_err <- try(
    wb_feature_set_namespace_transfer(
      bundle = b,
      source_matrix_id = "RNA_source",
      target_matrix_id = "RNA_target",
      namespace = "lossy_ns",
      mode = "mirror"
    ),
    silent = TRUE
  )
  stopifnot(inherits(mirror_err, "try-error"))

  TRUE
}
