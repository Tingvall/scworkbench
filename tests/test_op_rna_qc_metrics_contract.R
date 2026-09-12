test_op_rna_qc_metrics_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  tmp <- tempfile("scwb_rna_qc_metrics_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(4))
  features <- c("mt-Nd1", "Rpl3", "GeneA", "GeneB", "mt-Co1")
  counts <- Matrix::Matrix(
    matrix(
      c(
        1, 0, 2, 0,
        0, 3, 0, 0,
        4, 1, 0, 0,
        0, 2, 5, 0,
        5, 0, 3, 0
      ),
      nrow = length(features), byrow = TRUE,
      dimnames = list(features, cells)
    ),
    sparse = TRUE
  )
  wb_define_cells(b, cells)
  wb_attach_matrix(b, "RNA_counts", counts, feature_type = "gene")

  direct <- wb_op_rna_qc_metrics(
    b, "RNA_counts", rev(cells), mitochondrial_pattern = "^mt-",
    ribosomal_features = "Rpl3", chunk_size = 2L
  )
  stopifnot(identical(unique(direct$outputs$metrics$cell_id), cells))

  rr <- wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      mitochondrial_pattern = "^mt-",
      ribosomal_features = "Rpl3",
      chunk_size = 2L
    )
  )

  metrics <- rr$run$outputs$metrics
  stopifnot(identical(metrics$kind, "cell_vector_family"))
  keys <- unique(metrics$key)
  stopifnot(identical(keys, c(
    "total_counts", "detected_features", "mitochondrial_counts",
    "mitochondrial_percent", "ribosomal_counts", "ribosomal_percent"
  )))
  values_for <- function(key) as.numeric(metrics$value[metrics$key == key])
  stopifnot(
    identical(values_for("total_counts"), c(10, 6, 10, 0)),
    identical(values_for("detected_features"), c(3, 3, 3, 0)),
    identical(values_for("mitochondrial_counts"), c(6, 0, 5, 0)),
    isTRUE(all.equal(values_for("mitochondrial_percent"), c(60, 0, 50, 0))),
    identical(values_for("ribosomal_counts"), c(0, 3, 0, 0)),
    isTRUE(all.equal(values_for("ribosomal_percent"), c(0, 50, 0, 0)))
  )
  stopifnot(identical(unique(metrics$cell_id), cells))
  stopifnot(identical(metrics$meta$threshold_selection, "not_performed"))

  qc_features <- rr$run$outputs$qc_features$table
  stopifnot(
    setequal(qc_features$feature_id, c("mt-Nd1", "mt-Co1", "Rpl3")),
    identical(qc_features$metric_group[qc_features$feature_id == "Rpl3"], "ribosomal")
  )
  summary <- rr$run$outputs$summary$table
  stopifnot(
    nrow(summary) == length(keys),
    identical(summary$n_missing[summary$metric == "mitochondrial_percent"], 0L),
    identical(summary$n_zero_denominator[summary$metric == "mitochondrial_percent"], 1L),
    identical(rr$run$params$n_chunks, 2L),
    identical(rr$run$params$threshold_selection, "not_performed")
  )

  promoted <- wb_session_promote_current(
    b, rr$session,
    outputs = c("metrics", "qc_features", "summary"),
    name_prefix = "rna_qc", created_by = "test"
  )
  metric_id <- as.character(promoted$promoted$artifact_id[promoted$promoted$output == "metrics"][[1]])
  wb_close_bundle(b)
  b <- wb_open_bundle(tmp)
  durable <- wb_art_load(b, metric_id, expected_kind = "cell_vector_family")
  stopifnot(identical(unique(durable$cell_id), cells), identical(unique(durable$key), keys))

  TRUE
}

test_op_rna_qc_metrics_failure_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  tmp <- tempfile("scwb_rna_qc_metrics_failure_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c1", "c2")
  wb_define_cells(b, cells)
  fractional <- Matrix::Matrix(
    matrix(c(1, 0.5, 0, 2), nrow = 2, dimnames = list(c("g1", "g2"), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_fractional", fractional, feature_type = "gene")

  negative <- Matrix::Matrix(
    matrix(c(1, -1, 0, 2), nrow = 2, dimnames = list(c("g1", "g2"), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_negative", negative, feature_type = "gene")
  nonfinite <- Matrix::Matrix(
    matrix(c(Inf, 0, 0, 2), nrow = 2, dimnames = list(c("g1", "g2"), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_nonfinite", nonfinite, feature_type = "gene")

  integer_err <- try(wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(matrix = "RNA_fractional", cell_set = "all", min_cells = 1L)
  ), silent = TRUE)
  stopifnot(inherits(integer_err, "try-error"))

  negative_err <- try(wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(matrix = "RNA_negative", cell_set = "all", min_cells = 1L)
  ), silent = TRUE)
  stopifnot(inherits(negative_err, "try-error"))

  nonfinite_err <- try(wb_op_rna_qc_metrics(
    b, "RNA_nonfinite", cells, require_integer_counts = FALSE
  ), silent = TRUE)
  stopifnot(inherits(nonfinite_err, "try-error"))

  missing_err <- try(wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(
      matrix = "RNA_fractional", cell_set = "all", min_cells = 1L,
      require_integer_counts = FALSE,
      mitochondrial_features = "not_present"
    )
  ), silent = TRUE)
  stopifnot(inherits(missing_err, "try-error"))

  rr <- wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(
      matrix = "RNA_fractional", cell_set = "all", min_cells = 1L,
      require_integer_counts = FALSE,
      mitochondrial_features = "not_present",
      missing_feature_policy = "drop"
    )
  )
  stopifnot(
    identical(unique(rr$run$outputs$metrics$key), c("total_counts", "detected_features")),
    nrow(rr$run$outputs$qc_features$table) == 0L,
    identical(rr$run$outputs$summary$meta$mitochondrial_missing_features, "not_present")
  )

  TRUE
}
