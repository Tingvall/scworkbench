test_metadata_identifier_consumers_contract <- function() {
  root <- tempfile("scwb_metadata_consumers_")
  sce_root <- tempfile("scwb_metadata_sce_")
  clone_parent <- tempfile("scwb_metadata_replay_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  sce_bundle <- NULL
  on.exit({ try(wb_close_bundle(b), silent = TRUE); try(wb_close_bundle(sce_bundle), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE); unlink(sce_root, recursive = TRUE, force = TRUE); unlink(clone_parent, recursive = TRUE, force = TRUE) }, add = TRUE)
  ids <- paste0("c", seq_len(12L))
  md <- data.frame(join = ids, group = rep(c("ctrl", "drug"), each = 6L), score = seq_len(12L), labels = rep(c("L1", "L2", "L3"), 4L), check.names = FALSE)
  names(md) <- c("join", "batch key", "numeric score%", "label/by")
  wb_define_cells(b, ids, metadata = md, set_name = "core", source = "consumer-contract")
  wb_attach_space(b, "umap weird", data.frame(cell_id = ids, x = seq_along(ids), y = rev(seq_along(ids))))
  plot <- wb_plot_space_2d(b, "umap weird", color_by = "batch key", label_groups = TRUE, label_by = "label/by", label_min_n = 1L)
  stopifnot(inherits(plot, "ggplot"))
  inventory <- wb_cell_metadata_columns(b)
  stopifnot(all(c("field_id", "source_name", "storage_name", "collision_status", "import_source") %in% names(inventory)))
  stopifnot(all(c("batch key", "numeric score%", "label/by") %in% inventory$source_name))

  counts <- Matrix::Matrix(matrix(seq_len(60L) %% 5L, nrow = 5L, dimnames = list(paste0("g", 1:5), ids)), sparse = TRUE)
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")
  selected_meta <- wb_meta(b, cells = ids, cols = c("cell_id", "batch key",
    "label/by", "numeric score%"))
  stopifnot(identical(names(selected_meta), c("cell_id", "batch key",
    "label/by", "numeric score%")))
  stopifnot(identical(as.character(selected_meta$cell_id), ids))
  split <- wb_op_cells_split_by(b, "batch key")
  stopifnot(identical(sort(names(split)), c("ctrl", "drug")), sum(lengths(split)) == length(ids))

  sce_counts <- Matrix::Matrix(matrix(seq_len(16L), nrow = 4L,
                                      dimnames = list(paste0("g", 1:4), paste0("s", 1:4))), sparse = TRUE)
  sce_md <- S4Vectors::DataFrame(a = c("x", "x", "y", "y"), b = 1:4)
  names(sce_md) <- c("container field/雪", "select")
  sce <- SingleCellExperiment::SingleCellExperiment(assays = list(counts = sce_counts), colData = sce_md)
  sce_bundle <- wb_bundle_from_sce(
    sce, bundle_dir = sce_root, assays = "counts", reduced_dims = character(0),
    overwrite = TRUE, emit_report_artifact = FALSE
  )
  sce_fields <- wb_metadata_fields(sce_bundle)
  stopifnot(all(c("container field/雪", "select") %in% sce_fields$source_name))
  stopifnot(identical(as.character(wb_meta(sce_bundle, cols = c("cell_id", "container field/雪"))[[2L]]), c("x", "x", "y", "y")))

  session <- wb_session_new()
  result <- wb_session_run_op(
    session, b, "metadata_cell_vector",
    inputs = list(source_column = "batch key", vector_name = "batch_key", value_type = "categorical",
                  missing_policy = "error", cell_set = "all", min_cells = 1L, overwrite = TRUE)
  )
  promoted <- wb_session_promote_current(
    b, result$session, created_by = "metadata-consumer-contract",
    outputs = list(wb_ref_run(result$run$run_id, "vector"))
  )
  hit <- promoted$promoted[promoted$promoted$status == "ok", , drop = FALSE]
  stopifnot(nrow(hit) == 1L, identical(hit$lineage_status, "complete"))
  artifact_id <- as.character(hit$artifact_id[[1L]])
  snapshot_id <- as.character(promoted$provenance_snapshot_id[[1L]])
  wb_close_bundle(b); b <- NULL
  b <- wb_open_bundle(root)
  vector <- wb_art_load(b, artifact_id, expected_kind = "cell_vector")
  stopifnot(identical(as.character(vector$value), rep(c("ctrl", "drug"), each = 6L)))
  cert <- wb_entity_certificate(b, "artifact", artifact_id)
  stopifnot(identical(cert$producer$run$parameters$value$source_column, "batch key"))
  replay <- wb_prov_validate_replay(b, snapshot_id = snapshot_id, mode = "symbolic", profile = "strict", strict = TRUE)
  stopifnot(isTRUE(replay$summary$valid), all(replay$per_run$status == "ok"))
  TRUE
}
