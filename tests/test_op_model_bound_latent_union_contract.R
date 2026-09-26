test_op_model_bound_latent_union_contract <- function() {
  root <- tempfile("scwb_model_bound_union_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  reference_cells <- paste0("ref_", seq_len(8L))
  query_cells <- paste0("ko_", seq_len(5L))
  cells <- c(reference_cells, query_cells)
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells,
    genotype = c(rep("reference", length(reference_cells)), rep("knockout", length(query_cells))),
    stringsAsFactors = FALSE
  ))
  reference <- matrix(
    seq_len(length(reference_cells) * 4L) / 10,
    nrow = length(reference_cells), ncol = 4L,
    dimnames = list(reference_cells, paste0("z", seq_len(4L)))
  )
  query <- matrix(
    100 + seq_len(length(query_cells) * 4L) / 10,
    nrow = length(query_cells), ncol = 4L,
    dimnames = list(query_cells, paste0("z", seq_len(4L)))
  )
  wb_attach_space(
    b, "peakvi_reference",
    data.frame(cell_id = reference_cells, reference, check.names = FALSE),
    source = "fixture"
  )
  wb_attach_space(
    b, "peakvi_projected_ko",
    data.frame(cell_id = query_cells, query, check.names = FALSE),
    source = "fixture"
  )

  model_dir <- file.path(root, "artifact_models", "peakvi_fixture")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("contained PeakVI model fixture", file.path(model_dir, "model.txt"))
  model_output <- wb_prim_model_ref("peakvi_reference", "peakvi_reference", engine = "scvi")
  model_output$model_path <- model_dir
  model_output$model_type <- "scvi"
  model_run <- wb_new_run(
    "scvi_train",
    inputs = list(cell_set = "all", parents = character(0)),
    outputs = list(model = model_output)
  )
  model_session <- wb_session_add_run(wb_session_new(), model_run)
  model_promotion <- wb_session_promote_current(
    b, model_session, outputs = "model", created_by = "contract test"
  )
  model_artifact_id <- as.character(model_promotion$promoted$artifact_id[[1L]])
  model <- wb_art_load(b, model_artifact_id)
  projection_summary <- wb_prim_obs_table(
    data.frame(
      engine = "scvi",
      projection_mode = "transform_without_refit",
      output_space_id = "peakvi_projected_ko",
      model_space_id = "peakvi_reference",
      model_artifact_id = model_artifact_id,
      n_latent = 4L,
      stringsAsFactors = FALSE
    ),
    table_type = "scvi_project_summary",
    entity_kind = "space"
  )

  union <- wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference",
      query_space = "peakvi_projected_ko",
      model = model,
      projection_summary = projection_summary,
      cell_set = "all",
      min_cells = 1L,
      space_id_out = "peakvi_joint"
    )
  )
  stopifnot(
    identical(union$run$outputs$space$space_id, "peakvi_joint"),
    identical(union$run$outputs$union_summary$table$coordinate_operation[[1]], "row_bind_without_transformation"),
    identical(union$run$outputs$union_summary$table$n_reference_cells[[1]], 8L),
    identical(union$run$outputs$union_summary$table$n_query_cells[[1]], 5L),
    identical(union$run$outputs$union_summary$table$n_dimensions[[1]], 4L)
  )
  staged <- wb_space(wb_session_view(union$session), "peakvi_joint")
  stopifnot(
    identical(as.character(rownames(staged)), cells),
    identical(as.numeric(staged), as.numeric(rbind(reference, query)))
  )

  promoted <- wb_session_promote_current(
    b, union$session,
    outputs = "union_summary",
    name_prefix = "PeakVI joint latent",
    created_by = "contract test"
  )
  stopifnot(nrow(promoted$promoted[promoted$promoted$output == "union_summary" & promoted$promoted$status == "ok", ]) == 1L)
  durable <- wb_space(b, "peakvi_joint")
  stopifnot(identical(as.character(rownames(durable)), cells))

  bad_receipt <- projection_summary
  bad_receipt$table$model_artifact_id <- "another_model"
  bad_model <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference",
      query_space = "peakvi_projected_ko",
      model = model,
      projection_summary = bad_receipt,
      cell_set = "all",
      min_cells = 1L,
      space_id_out = "bad_model_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(bad_model, "try-error"), !"bad_model_union" %in% wb_spaces(b)$space_id)

  wrong_output_receipt <- projection_summary
  wrong_output_receipt$table$output_space_id <- "another_query_space"
  wrong_output <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_ko",
      model = model, projection_summary = wrong_output_receipt,
      cell_set = "all", min_cells = 1L, space_id_out = "wrong_output_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(wrong_output, "try-error"), !"wrong_output_union" %in% wb_spaces(b)$space_id)

  wrong_type_receipt <- projection_summary
  wrong_type_receipt$table_type <- "generic"
  wrong_type <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_ko",
      model = model, projection_summary = wrong_type_receipt,
      cell_set = "all", min_cells = 1L, space_id_out = "wrong_type_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(wrong_type, "try-error"), !"wrong_type_union" %in% wb_spaces(b)$space_id)

  wrong_dimensions_receipt <- projection_summary
  wrong_dimensions_receipt$table$n_latent <- 3L
  wrong_dimensions_receipt_err <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_ko",
      model = model, projection_summary = wrong_dimensions_receipt,
      cell_set = "all", min_cells = 1L, space_id_out = "wrong_receipt_dimensions_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(wrong_dimensions_receipt_err, "try-error"),
            !"wrong_receipt_dimensions_union" %in% wb_spaces(b)$space_id)

  query_three_dimensions <- query[, seq_len(3L), drop = FALSE]
  wb_attach_space(
    b, "peakvi_projected_ko_3d",
    data.frame(cell_id = query_cells, query_three_dimensions, check.names = FALSE),
    source = "fixture"
  )
  three_dimensional_receipt <- projection_summary
  three_dimensional_receipt$table$output_space_id <- "peakvi_projected_ko_3d"
  three_dimensional_receipt$table$n_latent <- 3L
  dimension_mismatch <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_ko_3d",
      model = model, projection_summary = three_dimensional_receipt,
      cell_set = "all", min_cells = 1L, space_id_out = "dimension_mismatch_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(dimension_mismatch, "try-error"), !"dimension_mismatch_union" %in% wb_spaces(b)$space_id)

  overlapping_cells <- c(reference_cells[[1L]], query_cells)
  overlapping_coords <- rbind(reference[1L, , drop = FALSE], query)
  wb_attach_space(
    b, "peakvi_projected_overlap",
    data.frame(cell_id = overlapping_cells, overlapping_coords, check.names = FALSE),
    source = "fixture"
  )
  overlap_receipt <- projection_summary
  overlap_receipt$table$output_space_id <- "peakvi_projected_overlap"
  overlap_error <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_overlap",
      model = model, projection_summary = overlap_receipt,
      cell_set = "all", min_cells = 1L, space_id_out = "overlap_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(overlap_error, "try-error"), !"overlap_union" %in% wb_spaces(b)$space_id)

  existing_output <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference", query_space = "peakvi_projected_ko",
      model = model, projection_summary = projection_summary,
      cell_set = "all", min_cells = 1L, space_id_out = "peakvi_reference"
    )
  ), silent = TRUE)
  stopifnot(inherits(existing_output, "try-error"))

  incomplete <- try(wb_session_run_op(
    wb_session_new(), b, "model_bound_latent_union",
    inputs = list(
      reference_space = "peakvi_reference",
      query_space = "peakvi_projected_ko",
      model = model,
      projection_summary = projection_summary,
      cell_ids = cells[-1],
      min_cells = 1L,
      space_id_out = "incomplete_union"
    )
  ), silent = TRUE)
  stopifnot(inherits(incomplete, "try-error"), !"incomplete_union" %in% wb_spaces(b)$space_id)

  TRUE
}
