test_bdev_ko_peakvi_mapping_workflow_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  required <- c("BPCells", "Matrix", "uwot")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }
  python <- .wb_pybench_default_python()
  if (!file.exists(python)) {
    return(contract_test_skip(paste("PyBench interpreter not found at", python)))
  }

  old_mock <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1")
  on.exit({
    if (is.na(old_mock)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = old_mock)
  }, add = TRUE)

  root <- tempfile("scwb_bdev_ko_peakvi_")
  workspace <- tempfile("scwb_bdev_ko_peakvi_sessions_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
    unlink(workspace, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  reference_cells <- paste0("bdev_", sprintf("%02d", seq_len(12L)))
  query_cells <- paste0("ko_", sprintf("%02d", seq_len(6L)))
  cells <- c(reference_cells, query_cells)
  peaks <- paste0("chr1:", seq(1000L, by = 500L, length.out = 9L), "-", seq(1249L, by = 500L, length.out = 9L))
  counts <- Matrix::Matrix(
    matrix((seq_len(length(peaks) * length(cells)) * 7L) %% 5L,
           nrow = length(peaks), dimnames = list(peaks, cells)),
    sparse = TRUE
  )
  wb_define_cells(
    b, cells,
    metadata = data.frame(
      cell_id = cells,
      dataset = c(rep("Bdev_reference", length(reference_cells)), rep("KO_query", length(query_cells))),
      genotype = c(rep("reference", length(reference_cells)), rep("KO", length(query_cells))),
      genome_build = "fixture_build",
      stringsAsFactors = FALSE
    )
  )
  wb_attach_matrix(b, "ATAC_common_peaks", counts, layer = "counts", feature_type = "peak")
  wb_cell_set_replace(
    b, "set:bdev_reference", reference_cells,
    source = "fixture metadata", created_by = "contract-test",
    description = "Bdev-only PeakVI training universe"
  )
  wb_cell_set_replace(
    b, "set:ko_query", query_cells,
    source = "fixture metadata", created_by = "contract-test",
    description = "KO-only PeakVI projection universe"
  )

  session <- wb_session_create(b, workspace, "bdev_ko_peakvi_mapping")
  fit <- wb_session_run_op(
    session, b, "peakvi_fit",
    inputs = list(
      matrix = "ATAC_common_peaks",
      cell_set = "set:bdev_reference",
      min_cells = 10L,
      n_latent = 4L,
      max_epochs = 1L,
      use_gpu = FALSE,
      seed = 29L,
      space_id_out = "peakvi.bdev_reference"
    ),
    notes = "Mock-runtime Bdev-only PeakVI fit contract"
  )
  stopifnot(
    identical(as.integer(fit$run$inputs$coverage$effective_n), 12L),
    identical(as.character(fit$run$outputs$model$engine), "peakvi")
  )

  projected <- wb_session_run_op(
    fit$session, b, "peakvi_project",
    inputs = list(
      matrix = "ATAC_common_peaks",
      model = wb_ref_run(fit$run$run_id, "model"),
      cell_set = "set:ko_query",
      min_cells = 1L,
      use_gpu = FALSE,
      space_id_out = "peakvi.ko_projected"
    ),
    notes = "Mock-runtime KO-only projection through retained Bdev model"
  )
  stopifnot(
    identical(as.integer(projected$run$inputs$coverage$effective_n), 6L),
    identical(as.character(projected$run$outputs$fit_summary$table$model_space_id), "peakvi.bdev_reference"),
    identical(as.character(projected$run$outputs$fit_summary$table$output_space_id), "peakvi.ko_projected")
  )

  union <- wb_session_run_op(
    projected$session, b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi.bdev_reference",
      query_space = "peakvi.ko_projected",
      model = wb_ref_run(fit$run$run_id, "model"),
      projection_summary = wb_ref_run(projected$run$run_id, "fit_summary"),
      cell_set = "all",
      min_cells = 1L,
      space_id_out = "peakvi.bdev_ko_joint"
    ),
    notes = "Exact coordinate union under the fitted Bdev PeakVI model identity"
  )
  union_table <- union$run$outputs$union_summary$table
  stopifnot(
    identical(as.integer(union_table$n_reference_cells), 12L),
    identical(as.integer(union_table$n_query_cells), 6L),
    identical(as.integer(union_table$n_cells), 18L),
    identical(as.character(union_table$coordinate_operation), "row_bind_without_transformation")
  )
  joint <- .wb_as_coord_matrix(wb_space(wb_session_view(union$session), "peakvi.bdev_ko_joint"))
  stopifnot(identical(rownames(joint), cells), identical(as.integer(ncol(joint)), 4L))

  umap <- wb_session_run_op(
    union$session, b, "umap_fit",
    inputs = list(
      space = "peakvi.bdev_ko_joint",
      cell_set = "all",
      min_cells = 3L,
      dims = 1:4,
      space_id_out = "umap.peakvi.bdev_ko_joint",
      n_neighbors = 3L,
      min_dist = 0.3,
      nn_method = "nndescent",
      seed = 31L
    ),
    notes = "Joint display UMAP downstream of the model-bound latent union"
  )
  joint_umap <- .wb_as_coord_matrix(wb_space(wb_session_view(umap$session), "umap.peakvi.bdev_ko_joint"))
  stopifnot(identical(rownames(joint_umap), cells), identical(as.integer(ncol(joint_umap)), 2L))

  promoted <- wb_session_promote_current(
    b, umap$session,
    outputs = list(
      wb_ref_run(fit$run$run_id, "model"),
      wb_ref_run(projected$run$run_id, "fit_summary"),
      wb_ref_run(union$run$run_id, "union_summary"),
      wb_ref_run(umap$run$run_id, "model")
    ),
    name_prefix = "Bdev KO PeakVI mapping fixture",
    created_by = "contract-test"
  )
  stopifnot(
    all(promoted$promoted$status == "ok"),
    all(c("peakvi.bdev_reference", "peakvi.ko_projected", "peakvi.bdev_ko_joint", "umap.peakvi.bdev_ko_joint") %in% wb_spaces(b)$space_id),
    isTRUE(wb_validate_bundle(root))
  )

  TRUE
}
