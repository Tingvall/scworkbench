test_parse_rna_workflow_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }
  if (!requireNamespace("irlba", quietly = TRUE)) {
    return(contract_test_skip("irlba is not installed."))
  }

  tmp <- tempfile("scwb_parse_rna_workflow_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("parse_", sprintf("%02d", seq_len(12)))
  features <- c("MT-CO1", "RPS3", paste0("Gene", seq_len(8)))
  counts <- matrix(
    c(
      0, 20, 1, 0, 2, 1, 0, 2, 1, 0, 1, 2,
      0,  1, 3, 2, 1, 2, 3, 1, 2, 3, 2, 1,
      0,  1, 4, 3, 2, 3, 4, 2, 3, 4, 3, 2,
      0,  1, 2, 4, 3, 2, 3, 4, 2, 3, 4, 3,
      0,  1, 3, 2, 4, 3, 2, 3, 4, 2, 3, 4,
      0,  1, 4, 3, 2, 4, 3, 2, 3, 4, 2, 3,
      0,  1, 2, 4, 3, 2, 4, 3, 2, 3, 4, 2,
      0,  1, 3, 2, 4, 3, 2, 4, 3, 2, 3, 4,
      0,  1, 4, 3, 2, 4, 3, 2, 4, 3, 2, 3,
      0,  1, 2, 4, 3, 2, 4, 3, 2, 4, 3, 2
    ),
    nrow = length(features), byrow = TRUE,
    dimnames = list(features, cells)
  )
  counts <- Matrix::Matrix(counts, sparse = TRUE)

  wb_define_cells(
    b, cells,
    metadata = data.frame(cell_id = cells, sample_id = "parse_fixture", stringsAsFactors = FALSE),
    dataset_id = "parse_fixture"
  )
  wb_attach_matrix(b, "RNA_counts", counts, feature_type = "gene")

  qc <- wb_session_run_op(
    wb_session_new(), b, "rna_qc_metrics",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      mitochondrial_pattern = "^MT-",
      ribosomal_pattern = "^RP[SL]",
      chunk_size = 4L
    )
  )
  promoted_qc <- wb_session_promote_current(
    b, qc$session,
    outputs = c("metrics", "qc_features", "summary"),
    name_prefix = "parse_fixture_qc", created_by = "contract-test"
  )
  qc_artifact <- as.character(promoted_qc$promoted$artifact_id[
    promoted_qc$promoted$output == "metrics"
  ][1])
  stopifnot(nzchar(qc_artifact))

  selected <- wb_sel_vector_family(
    b, vector_id = paste0("artifact:", qc_artifact),
    key = "total_counts", min = 10
  )
  selected <- wb_sel_vector_family(
    selected, vector_id = paste0("artifact:", qc_artifact),
    key = "detected_features", min = 3, bundle = b
  )
  selected <- wb_sel_vector_family(
    selected, vector_id = paste0("artifact:", qc_artifact),
    key = "mitochondrial_percent", max = 40, bundle = b
  )
  stopifnot(
    !"parse_01" %in% selected,
    !"parse_02" %in% selected,
    identical(as.character(selected), cells[3:12])
  )

  derived <- wb_cell_set_derive(
    bundle = b,
    cell_set = "set:parse_qc_accepted",
    cells = selected,
    role = "analysis_universe",
    status = "accepted",
    source = "registered RNA QC metrics",
    created_by = "contract-test",
    description = "Synthetic Parse RNA cells passing predeclared depth, feature and mitochondrial thresholds"
  )
  rules <- derived$outputs$rule_table$table
  stopifnot(
    nrow(rules) == 3L,
    all(rules$rule_type == "wb_sel_vector_family"),
    identical(as.character(wb_cells(b, cell_set = "set:parse_qc_accepted")), cells[3:12]),
    identical(as.character(wb_cells(b, cell_set = "all")), cells)
  )

  normalized <- wb_session_run_op(
    wb_session_new(), b, "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts", cell_set = "all", min_cells = 1L,
      output_matrix_id = "RNA_log1p_cp10k", overwrite = FALSE
    )
  )
  hvg <- wb_session_run_op(
    normalized$session, b, "hvg_select",
    inputs = list(
      matrix = "RNA_log1p_cp10k",
      cell_set = "set:parse_qc_accepted",
      min_cells = 3L,
      n_features = 5L,
      method = "vst",
      chunk_size = 3L
    )
  )
  promoted_hvg <- wb_session_promote_current(
    b, hvg$session,
    outputs = c("selected_features", "fit_summary"),
    name_prefix = "parse_fixture_hvg", created_by = "contract-test"
  )
  hvg_artifact <- as.character(promoted_hvg$promoted$artifact_id[
    promoted_hvg$promoted$output == "selected_features"
  ][1])

  pca <- wb_session_run_op(
    hvg$session, b, "pca_fit",
    inputs = list(
      matrix = "RNA_log1p_cp10k",
      features = wb_ref_artifact(hvg_artifact, "selected_features"),
      cell_set = "set:parse_qc_accepted",
      min_cells = 3L,
      n_components = 3L,
      backend = "irlba",
      seed = 17L,
      space_id_out = "parse.pca",
      overwrite = FALSE,
      max_dense_gb = 1
    )
  )
  pca_coords <- .wb_as_coord_matrix(
    wb_space(wb_session_view(pca$session), "parse.pca", cells = cells[3:12])
  )
  stopifnot(
    identical(as.character(pca$run$outputs$space$space_id), "parse.pca"),
    identical(rownames(pca_coords), cells[3:12]),
    identical(as.integer(ncol(pca_coords)), 3L),
    identical(as.integer(pca$run$inputs$coverage$effective_n), 10L)
  )

  TRUE
}
