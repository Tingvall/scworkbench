test_file_backed_dense_space_staged_workflow_contract <- function() {
  required <- c("BPCells", "Matrix", "irlba", "uwot", "rhdf5")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  root <- tempfile("scwb_dense_workflow_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("cell_", seq_len(20L)); genes <- paste0("gene_", seq_len(12L))
  wb_define_cells(b, cells)
  counts <- outer(seq_along(genes), seq_along(cells), function(i, j) {
    as.integer((i * 7L + j * 3L + (i <= 4L) * (j <= 10L) * 11L) %% 19L)
  })
  counts <- Matrix::Matrix(counts, sparse = TRUE,
                           dimnames = list(genes, cells))
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")

  # Strict replay executes in a clean source-boundary clone so immutable
  # materialized outputs in the accepted bundle cannot mask replay behavior.
  wb_close_bundle(b)
  replay_parent <- tempfile("scwb_dense_workflow_replay_")
  dir.create(replay_parent)
  on.exit(unlink(replay_parent, recursive = TRUE, force = TRUE), add = TRUE)
  stopifnot(isTRUE(file.copy(root, replay_parent, recursive = TRUE)))
  replay_root <- file.path(replay_parent, basename(root))
  b <- wb_open_bundle(root)

  s <- wb_session_new()
  norm <- wb_session_run_op(s, b, "matrix_log_normalize", inputs = list(
    matrix = "RNA_counts", cell_set = "all", min_cells = 2L,
    output_matrix_id = "RNA_log_norm", overwrite = TRUE
  )); s <- norm$session
  pca <- wb_session_run_op(s, b, "pca_fit", inputs = list(
    matrix = wb_ref_run(norm$run$run_id, "matrix"),
    feature_ids = genes[seq_len(8L)],
    cell_set = "all", min_cells = 2L, n_components = 4L,
    backend = "irlba", seed = 7L, space_id_out = "rna.pca.workflow",
    overwrite = TRUE, max_dense_gb = 1
  )); s <- pca$session
  umap <- wb_session_run_op(s, b, "umap_fit", inputs = list(
    space = wb_ref_run(pca$run$run_id, "space"), cell_set = "all", min_cells = 2L,
    dims = 1:4, space_id_out = "rna.umap.workflow", n_neighbors = 4L,
    min_dist = 0.1, metric = "euclidean", nn_method = "annoy", seed = 7L
  ))
  promoted <- wb_session_promote_current(
    b, umap$session, outputs = c("model", "space_2d"), created_by = "dense-workflow-contract"
  )
  terminal_rows <- promoted$promoted$run_id == umap$run$run_id &
    promoted$promoted$output %in% c("model", "space_2d")
  if (!all(promoted$promoted$status[terminal_rows] == "ok")) {
    stop("workflow promotion failed: ", paste(capture.output(print(promoted$promoted)), collapse = "\n"), call. = FALSE)
  }
  stopifnot(all(promoted$promoted$status[terminal_rows] == "ok"),
            all(c(norm$run$run_id, pca$run$run_id, umap$run$run_id) %in%
                  DBI::dbGetQuery(b$con, "SELECT run_id FROM prov_runs")$run_id))
  snapshot <- as.character(promoted$provenance_snapshot_id)[1L]
  wb_close_bundle(b); b <- wb_open_bundle(root)
  registered <- wb_spaces(b)
  stopifnot(all(c("rna.pca.workflow", "rna.umap.workflow") %in% registered$space_id),
            all(registered$storage[registered$space_id %in% c("rna.pca.workflow", "rna.umap.workflow")] ==
                  scworkbench:::.wb_space_payload_storage()),
            ncol(wb_space(b, "rna.pca.workflow")) == 4L,
            nrow(wb_space(b, "rna.umap.workflow")) == length(cells),
            isTRUE(wb_validate_bundle(root)))
  replay_bundle <- wb_open_bundle(replay_root)
  on.exit(try(wb_close_bundle(replay_bundle), silent = TRUE), add = TRUE)
  replay <- wb_prov_validate_replay(
    b, snapshot_id = snapshot, profile = "strict", strict = TRUE,
    destination_bundle = replay_bundle
  )
  if (!isTRUE(replay$summary$valid) || !all(replay$per_output$output_match)) {
    stop("workflow strict replay mismatch: ",
         paste(capture.output(print(
           replay$per_output[!replay$per_output$output_match,
                             c("output_name", "replay_equivalence_policy", "kind_match", "hash_match", "equivalence_verified")],
           width = 1000L
         )), collapse = "\n"), call. = FALSE)
  }
  stopifnot(isTRUE(replay$summary$valid), all(replay$per_output$output_match))
  TRUE
}
