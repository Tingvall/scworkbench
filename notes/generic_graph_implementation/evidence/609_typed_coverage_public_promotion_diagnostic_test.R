test_typed_effective_cell_coverage_contract <- function() {
  contract_test_activate_core_conformance_pack()
  root <- tempfile("scwb_typed_coverage_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)

  cells <- paste0("cell_", sprintf("%02d", seq_len(12L)))
  wb_define_cells(b, cells)

  matrix_cells <- cells[c(8, 2, 11, 4, 1, 7, 5, 10)]
  counts <- Matrix::Matrix(
    matrix(seq_len(4L * length(matrix_cells)), nrow = 4L,
           dimnames = list(paste0("g", 1:4), matrix_cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "partial_matrix", counts, feature_type = "gene")
  stopifnot(identical(wb_cells_with_matrix(b, "partial_matrix"), cells[c(1, 2, 4, 5, 7, 8, 10, 11)]))

  duplicate_counts <- counts[, seq_len(4L), drop = FALSE]
  wb_attach_matrix(b, "duplicate_matrix", duplicate_counts, feature_type = "gene")
  duplicate_registration <- try(wb_register_matrix_fragment(
    b$con, "duplicate_matrix", "mat/duplicate_fragment",
    feature_ids = rownames(counts), cell_ids = c(matrix_cells[4], cells[12]), source = "test"
  ), silent = TRUE)
  stopifnot(inherits(duplicate_registration, "try-error"))
  DBI::dbExecute(
    b$con,
    paste(
      "INSERT INTO matrix_fragments(fragment_id, matrix_id, storage, path, n_features, n_cells,",
      "feature_ids_json, cell_ids_json, source, created_at, description)",
      "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
    ),
    params = list(
      "corrupt_duplicate_fragment", "duplicate_matrix", "bpcells", "mat/corrupt_duplicate_fragment",
      4L, 2L, as.character(jsonlite::toJSON(as.list(rownames(counts)), auto_unbox = TRUE)),
      as.character(jsonlite::toJSON(as.list(c(matrix_cells[4], cells[12])), auto_unbox = TRUE)),
      "test-corruption", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "duplicate identity regression"
    )
  )
  duplicate_coverage <- try(wb_cells_with_matrix(b, "duplicate_matrix"), silent = TRUE)
  stopifnot(inherits(duplicate_coverage, "try-error"),
            grepl("multiple fragments", as.character(duplicate_coverage), fixed = TRUE))

  space_cells <- cells[c(10, 1, 7, 4, 11, 2, 8)]
  coords <- matrix(seq_len(length(space_cells) * 3L), ncol = 3L,
                   dimnames = list(space_cells, paste0("d", 1:3)))
  wb_add_space(b, "partial_space", coords)
  stopifnot(
    identical(wb_cells_with_space(b, "partial_space", 1:2), cells[c(1, 2, 4, 7, 8, 10, 11)]),
    identical(wb_cells_with_space(b, "partial_space", 1:3), cells[c(1, 2, 4, 7, 8, 10, 11)]),
    inherits(try(wb_cells_with_space(b, "partial_space", c(1, 1)), silent = TRUE), "try-error"),
    inherits(try(wb_cells_with_space(b, "partial_space", c(1, 4)), silent = TRUE), "try-error")
  )

  wide_coords <- matrix(
    seq_len(8L), nrow = 4L, ncol = 2L,
    dimnames = list(cells[1:4], c("x", "y"))
  )
  wb_add_space(b, "partial_wide", wide_coords)
  stopifnot(
    identical(wb_cells_with_space(b, "partial_wide", 1L), cells[1:4]),
    identical(wb_cells_with_space(b, "partial_wide", 2L), cells[1:4]),
    identical(wb_cells_with_space(b, "partial_wide", 1:2), cells[1:4])
  )

  a_ids <- cells[c(11, 2, 8, 4, 1, 10)]
  b_ids <- cells[c(4, 10, 2, 12, 8)]
  a <- wb_prim_cell_vector(setNames(seq_along(a_ids), a_ids), value_type = "continuous")
  bvec <- wb_prim_cell_vector(setNames(c("x", "y", "x", "y", "x"), b_ids), value_type = "categorical")
  explicit <- cells[c(10, 8, 2, 4, 1, 11)]
  typed <- scworkbench:::.wb_typed_effective_cells(
    b, "all", list(cell_ids = explicit), list(a = a, b = bvec),
    list(a = "cell_vector", b = "cell_vector"), "scwbv2reference::two_table_terminal", 1L
  )
  stopifnot(
    identical(typed$cells, c("cell_10", "cell_08", "cell_02", "cell_04")),
    identical(typed$diagnostics$schema_version, "scworkbench.effective_cell_coverage.v1"),
    identical(typed$diagnostics$requested_source, "cell_ids"),
    identical(typed$diagnostics$per_input$a$available_n, 6L),
    identical(typed$diagnostics$per_input$b$dropped_n, 2L)
  )

  dup_explicit <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(cell_ids = c(cells[1], cells[1])), list(a = a),
    list(a = "cell_vector"), "scwbv2reference::two_table_terminal", 1L
  ), silent = TRUE)
  unknown_explicit <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(cell_ids = c(cells[1], "absent")), list(a = a),
    list(a = "cell_vector"), "scwbv2reference::two_table_terminal", 1L
  ), silent = TRUE)
  bad_a <- a
  bad_a$cell_id[2] <- bad_a$cell_id[1]
  dup_vector <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(), list(a = bad_a), list(a = "cell_vector"),
    "scwbv2reference::two_table_terminal", 1L
  ), silent = TRUE)
  small <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(), list(a = a, b = bvec),
    list(a = "cell_vector", b = "cell_vector"), "scwbv2reference::two_table_terminal", 5L
  ), silent = TRUE)
  stopifnot(inherits(dup_explicit, "try-error"), inherits(unknown_explicit, "try-error"),
            inherits(dup_vector, "try-error"), inherits(small, "try-error"))

  path <- wb_prim_space_path_family(
    space_id = rep("partial_space", 6L), path_id = rep("p1", 6L),
    point = rep(1:2, each = 3L), dim = rep(1:3, 2L), value = seq_len(6L)
  )
  path_cov <- scworkbench:::.wb_typed_effective_cells(
    b, "all", list(), list(space = wb_prim_space("partial_space"), path = path),
    list(space = "space", path = "space_path_family"),
    "slingshot_adopt", 1L
  )
  stopifnot(identical(path_cov$cells, cells[c(1, 2, 4, 7, 8, 10, 11)]))

  family <- wb_prim_cell_vector_family("L1", a_ids, seq_along(a_ids))
  model <- wb_prim_model_ref("partial_space", "partial_space", engine = "slingshot")
  model$cells <- cells[c(3, 5, 6)]
  incompatible <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(), list(signal = family, model = model),
    list(signal = "cell_vector_family", model = "model_ref"),
    "slingshot_adopt", 1L
  ), silent = TRUE)
  orphan_model <- wb_prim_model_ref("missing_model_space", "", engine = "slingshot")
  missing_model_coverage <- try(scworkbench:::.wb_typed_effective_cells(
    b, "all", list(), list(model = orphan_model), list(model = "model_ref"),
    "slingshot_adopt", 1L
  ), silent = TRUE)
  stopifnot(inherits(incompatible, "try-error"), inherits(missing_model_coverage, "try-error"))

  source_run <- wb_new_run(
    op_name = "metadata_cell_vector",
    inputs = list(cell_set = "all", effective_n = length(a_ids), parents = character(),
                  provenance_refs = list(), user_inputs = list()),
    params = list(), outputs = list(vector = a)
  )
  session <- wb_session_add_run(wb_session_new(), source_run)
  rr_run <- wb_session_run_op(
    session, b, "scwbv2reference::two_table_terminal",
    inputs = list(a = wb_ref_run(source_run$run_id, "vector"), b = bvec,
                  cell_ids = explicit, min_cells = 1L)
  )
  stopifnot(
    identical(rr_run$run$inputs$effective_n, 4L),
    identical(rr_run$run$inputs$coverage$effective_n, 4L),
    identical(rr_run$run$inputs$coverage$per_input$a$kind, "cell_vector"),
    identical(rr_run$run$inputs$coverage$per_input$b$overlap_n, 4L)
  )

  promoted_source <- wb_promote_analysis(
    b, stats::setNames(list(source_run), source_run$run_id),
    head_run_id = source_run$run_id, outputs = "vector", created_by = "test"
  )
  artifact_id <- promoted_source$promoted$artifact_id[[1L]]
  rr_art <- wb_session_run_op(
    wb_session_new(), b, "scwbv2reference::two_table_terminal",
    inputs = list(a = wb_ref_artifact(artifact_id, "vector"), b = bvec,
                  cell_ids = explicit, min_cells = 1L)
  )
  stopifnot(identical(rr_art$run$inputs$effective_n, 4L),
            identical(rr_art$run$inputs$coverage$per_input$a$available_n, 6L))

  matrix_cov <- wb_cell_coverage(
    b, "all", inputs = list(), resolved = list(matrix = wb_prim_matrix("partial_matrix")),
    requirements = list(matrix = "matrix"),
    op_name = "scwbv2reference::two_table_terminal"
  )
  stopifnot(
    identical(matrix_cov$effective, 8L),
    identical(matrix_cov$diagnostics$per_input$matrix$source_id, "partial_matrix"),
    identical(matrix_cov$diagnostics$per_input$matrix$available_n, 8L)
  )

  TRUE
}
