test_metadata_identity_namespace_closure_contract <- function() {
  root <- tempfile("scwb_metadata_namespace_")
  prior_root <- tempfile("scwb_metadata_namespace_prior_")
  casefold_root <- tempfile("scwb_metadata_namespace_casefold_")
  replay_parent <- tempfile("scwb_metadata_namespace_replay_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  prior <- NULL
  casefold <- NULL
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    try(wb_close_bundle(prior), silent = TRUE)
    try(wb_close_bundle(casefold), silent = TRUE)
    unlink(c(root, prior_root, casefold_root, replay_parent), recursive = TRUE, force = TRUE)
  }, add = TRUE)

  ids <- paste0("c", seq_len(12L))
  md <- data.frame(
    join = ids,
    reserved_cell = paste0("import_cell_", seq_along(ids)),
    stable_same_write = paste0("same_", seq_along(ids)),
    ordinary = rep(c("g1", "g2"), 6L),
    stable_future = paste0("future_", seq_along(ids)),
    core_cell = paste0("core_cell_", seq_along(ids)),
    core_dataset = paste0("core_dataset_", seq_along(ids)),
    p1 = paste0("private1_", seq_along(ids)),
    p2 = rep(c("A", "B"), each = 6L),
    empty = paste0("empty_", seq_along(ids)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(md) <- c(
    "join", "cell_id", "meta:000001", "ordinary", "meta:999999",
    "core:cell_id", "core:dataset_id", "__wb_meta_000001", "__wb_meta_000002", ""
  )
  submitted <- md[-1L]
  wb_define_cells(b, ids, metadata = md, set_name = "core", source = "namespace-closure")

  fields <- wb_metadata_fields(b, include_core = FALSE)
  stopifnot(nrow(fields) == ncol(submitted), !anyDuplicated(fields$field_id))
  stopifnot(identical(as.character(fields$source_name), names(submitted)))
  stopifnot(identical(as.integer(fields$source_position), seq.int(2L, ncol(md))))
  stopifnot(identical(fields$storage_name[fields$source_name == "__wb_meta_000002"], "__wb_meta_000002"))
  reserved_storage <- fields$storage_name[fields$source_name == "cell_id"]
  stopifnot(length(reserved_storage) == 1L, identical(reserved_storage, "__wb_meta_000003"))
  stopifnot(!anyDuplicated(tolower(fields$storage_name)))

  # Every submitted source column has its own stable mapping and values. In
  # particular, source `meta:000001` did not update the earlier field ID.
  for (j in seq_len(nrow(fields))) {
    ref <- wb_ref_metadata_field(fields$field_id[[j]])
    got <- wb_meta(b, cols = list(wb_ref_metadata_field("core:cell_id"), ref))[[2L]]
    stopifnot(identical(as.character(got), as.character(submitted[[j]])))
  }
  ambiguous <- try(wb_meta(b, cols = "meta:000001"), silent = TRUE)
  stopifnot(inherits(ambiguous, "try-error"))
  stopifnot(all(c("meta:000001", fields$field_id[fields$source_name == "meta:000001"][[1L]]) %in%
                  regmatches(as.character(ambiguous), gregexpr("meta:[0-9]+", as.character(ambiguous)))[[1L]]))

  all_meta <- wb_meta(b)
  stopifnot(identical(names(all_meta)[1:2], c("cell_id", "dataset_id")))
  stopifnot(identical(as.character(all_meta$cell_id), ids))
  stopifnot(all(fields$field_id[fields$source_name %in% c("cell_id", "core:cell_id", "core:dataset_id", "meta:000001")] %in% names(all_meta)))
  stopifnot(identical(wb_op_cells_filter(b, cell_id %in% c("c2", "c9")), c("c2", "c9")))

  # The explicit, position-aligned update channel can target every colliding
  # field without interpreting payload names as identities.
  update <- data.frame(join = ids, stringsAsFactors = FALSE, check.names = FALSE)
  expected <- vector("list", nrow(fields))
  for (j in seq_len(nrow(fields))) {
    expected[[j]] <- paste0("f", j, "_", rep(c("A", "B"), each = 6L))
    update[[paste0("payload_", j)]] <- expected[[j]]
  }
  wb_attach_metadata(
    b, update,
    field_refs = lapply(fields$field_id, wb_ref_metadata_field),
    source = "explicit-field-update"
  )
  for (j in seq_len(nrow(fields))) {
    got <- wb_meta(b, cols = wb_ref_metadata_field(fields$field_id[[j]]))[[1L]]
    stopifnot(identical(as.character(got), expected[[j]]))
  }

  group_ref <- wb_ref_metadata_field(fields$field_id[fields$source_name == "__wb_meta_000002"][[1L]])
  group_index <- which(fields$source_name == "__wb_meta_000002")
  group_names <- paste0("f", group_index, "_", c("A", "B"))
  split <- wb_op_cells_split_by(b, group_ref)
  counts <- wb_op_cells_counts_by(b, group_ref)
  selected <- wb_sel_meta(b, group_ref, values = group_names[[1L]])
  stopifnot(identical(sort(names(split)), group_names))
  stopifnot(identical(sort(counts$n_cells), c(6L, 6L)), identical(as.character(selected), ids[1:6]))

  counts_mat <- Matrix::Matrix(
    matrix(seq_len(60L) %% 7L, nrow = 5L,
           dimnames = list(paste0("g", 1:5), ids)), sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_counts", counts_mat, layer = "counts", feature_type = "gene")
  wb_attach_space(b, "umap namespace", data.frame(cell_id = ids, x = seq_along(ids), y = rev(seq_along(ids))))
  plot <- wb_plot_space_2d(b, "umap namespace", color_by = group_ref,
                           label_groups = TRUE, label_by = group_ref, label_min_n = 1L)
  stopifnot(inherits(plot, "ggplot"))
  expr <- wb_op_expr_avg_by(b, "RNA_counts", by = group_ref)
  stopifnot(identical(names(expr), c("feature_id", group_names)))

  stage <- scworkbench:::.wb_scvi_stage_sparse_chunks(
    b, "RNA_counts", rownames(counts_mat), ids,
    batch_key = group_ref, categorical_covariates = list(
      wb_ref_metadata_field(fields$field_id[fields$source_name == "meta:000001"][[1L]])
    ), chunk_cells = 5L
  )
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  staged <- utils::read.delim(file.path(stage, "cell_metadata.tsv"), check.names = FALSE)
  stopifnot(identical(names(staged), c(
    "cell_id", group_ref$field_id,
    fields$field_id[fields$source_name == "meta:000001"][[1L]]
  )))
  stopifnot(identical(as.character(staged$cell_id), ids))

  session <- wb_session_new()
  run <- wb_session_run_op(
    session, b, "metadata_cell_vector",
    inputs = list(source_column = group_ref, vector_name = "namespace_group",
                  value_type = "categorical", missing_policy = "error",
                  cell_set = "all", min_cells = 1L, overwrite = TRUE)
  )
  promoted <- wb_session_promote_current(
    b, run$session, created_by = "namespace-closure",
    outputs = list(wb_ref_run(run$run$run_id, "vector"))
  )
  ok <- promoted$promoted[promoted$promoted$status == "ok", , drop = FALSE]
  stopifnot(nrow(ok) == 1L)
  artifact_id <- as.character(ok$artifact_id[[1L]])
  snapshot_id <- as.character(promoted$provenance_snapshot_id[[1L]])
  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  vec <- wb_art_load(b, artifact_id, expected_kind = "cell_vector")
  stopifnot(identical(as.character(vec$value), expected[[group_index]]))
  cert <- wb_entity_certificate(b, "artifact", artifact_id)
  stopifnot(identical(cert$producer$run$parameters$value$source_field_id, group_ref$field_id))
  replay <- wb_prov_validate_replay(b, snapshot_id = snapshot_id, mode = "symbolic", profile = "strict", strict = TRUE)
  stopifnot(isTRUE(replay$summary$valid), all(replay$per_run$status == "ok"))

  # Prior-write collision: a later source name equal to an already allocated ID
  # creates a new mapping; only the explicit channel updates the old mapping.
  prior <- wb_init_bundle(prior_root, overwrite = TRUE)
  wb_define_cells(prior, c("p1", "p2"), metadata = data.frame(id = c("p1", "p2"), first = 1:2))
  later <- data.frame(id = c("p1", "p2"), second = c(10L, 20L), check.names = FALSE)
  names(later)[2L] <- "meta:000001"
  wb_attach_metadata(prior, later)
  prior_fields <- wb_metadata_fields(prior, include_core = FALSE)
  stopifnot(nrow(prior_fields) == 2L, identical(prior_fields$field_id, c("meta:000001", "meta:000002")))
  stopifnot(identical(as.integer(wb_meta(prior, cols = wb_ref_metadata_field("meta:000001"))[[1L]]), 1:2))
  stopifnot(identical(as.integer(wb_meta(prior, cols = wb_ref_metadata_field("meta:000002"))[[1L]]), c(10L, 20L)))

  casefold <- wb_init_bundle(casefold_root, overwrite = TRUE)
  case_md <- data.frame(id = c("x1", "x2"), reserved = c("r1", "r2"), private = c("p1", "p2"), check.names = FALSE)
  names(case_md) <- c("id", "cell_id", "__WB_META_000001")
  wb_define_cells(casefold, c("x1", "x2"), metadata = case_md)
  case_fields <- wb_metadata_fields(casefold, include_core = FALSE)
  stopifnot(identical(case_fields$storage_name[case_fields$source_name == "cell_id"], "__wb_meta_000002"))
  stopifnot(identical(case_fields$storage_name[case_fields$source_name == "__WB_META_000001"], "__WB_META_000001"))
  TRUE
}
