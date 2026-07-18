test_transitive_promotion_pbmc_vertical_slice_contract <- function() {
  required <- c("BPCells", "Matrix", "irlba", "uwot", "igraph")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE))) {
    message("Skipping transitive promotion PBMC slice: missing runtime dependency.")
    return(TRUE)
  }

  set.seed(11)
  root <- tempfile("scwb_transitive_promotion_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)

  cell_ids <- paste0("c", seq_len(30L))
  feature_ids <- paste0("g", seq_len(12L))
  counts <- matrix(stats::rpois(length(cell_ids) * length(feature_ids), lambda = 3),
                   nrow = length(feature_ids), dimnames = list(feature_ids, cell_ids))
  wb_define_cells(b, cell_ids)
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = counts, feature_type = "gene")

  # A staged session must leave the source bundle unchanged until promotion.
  s_discard <- wb_session_new()
  x_discard <- wb_session_run_op(
    s_discard, b, "matrix_log_normalize",
    inputs = list(matrix = "RNA_counts", output_matrix_id = "RNA_discard", scale_factor = 1000)
  )
  stopifnot(!"RNA_discard" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(nrow(wb_prov_list_heads(b)) == 0L, nrow(wb_art_list(b)) == 0L)
  s_discard <- wb_session_discard(x_discard$session)
  stopifnot(is.null(s_discard$staging_bundle), !dir.exists(file.path(root, "mat", "RNA_discard")))

  s <- wb_session_new()
  r_norm <- wb_session_run_op(
    s, b, "matrix_log_normalize",
    inputs = list(matrix = "RNA_counts", output_matrix_id = "RNA_log", scale_factor = 1000)
  ); s <- r_norm$session
  r_hvg <- wb_session_run_op(
    s, b, "hvg_select", inputs = list(matrix = "RNA_log", n_features = 8L)
  ); s <- r_hvg$session
  r_pca <- wb_session_run_op(
    s, b, "pca_fit",
    inputs = list(matrix = "RNA_log", features = wb_ref_run(r_hvg$run$run_id, "selected_features"),
                  n_components = 3L, space_id_out = "pca")
  ); s <- r_pca$session
  r_umap <- wb_session_run_op(
    s, b, "umap_fit",
    inputs = list(space = "pca", space_id_out = "umap", nn_method = "annoy", n_neighbors = 5L, seed = 1L)
  ); s <- r_umap$session
  r_leiden <- wb_session_run_op(
    s, b, "leiden", inputs = list(space = "pca", k = 5L, resolution = 0.5, seed = 1L)
  ); s <- r_leiden$session
  r_markers <- wb_session_run_op(
    s, b, "markers_topn",
    inputs = list(matrix = "RNA_log", clusters = wb_ref_run(r_leiden$run$run_id, "clusters"), top_n = 2L, min_pct = 0)
  ); s <- r_markers$session

  stopifnot(!"RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(!"pca" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(!"umap" %in% as.character(wb_spaces(b)$space_id))

  # The session API requires explicit selection for the multi-output UMAP head.
  ambiguous <- try(wb_session_promote_current(b, r_umap$session), silent = TRUE)
  stopifnot(inherits(ambiguous, "try-error"))

  promoted <- wb_session_promote_current(
    b, s, outputs = c("space_2d", "clusters", "markers"), created_by = "test"
  )
  ok <- promoted$promoted[as.character(promoted$promoted$status) == "ok", , drop = FALSE]
  stopifnot(setequal(as.character(ok$output), c("space_2d", "clusters", "markers")))
  arts <- wb_art_list(b)
  stopifnot(nrow(arts) == 3L)
  stopifnot(setequal(as.character(arts$source_op), c("umap_fit", "leiden", "markers_topn")))
  stopifnot(all(as.character(ok$lineage_status) == "complete"))
  stopifnot("RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(all(c("pca", "umap") %in% as.character(wb_spaces(b)$space_id)))

  sid <- as.character(promoted$provenance_snapshot_id)
  runs <- DBI::dbGetQuery(b$con, "SELECT run_id, op_name, runtime_fingerprint_json FROM prov_runs WHERE snapshot_id = ?;", params = list(sid))
  stopifnot(setequal(as.character(runs$op_name), c("matrix_log_normalize", "hvg_select", "pca_fit", "umap_fit", "leiden", "markers_topn")))
  stopifnot(all(nzchar(as.character(runs$runtime_fingerprint_json))))
  mats <- DBI::dbGetQuery(b$con, "SELECT * FROM prov_materializations WHERE commit_id = ?;", params = list(DBI::dbGetQuery(b$con, "SELECT commit_id FROM prov_heads WHERE snapshot_id = ?;", params = list(sid))$commit_id[1]))
  stopifnot(nrow(mats) >= 6L, all(file.exists(file.path(b$dir, mats$path))))

  # A bad terminal request must not create a completed promotion branch.
  before_commits <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits WHERE state = 'complete';")$n[1]
  bad <- try(wb_promote_analysis(b, s$runs, head_run_id = r_markers$run$run_id, outputs = "not_an_output", staging_bundle = wb_session_view(s)), silent = TRUE)
  stopifnot(inherits(bad, "try-error"))
  after_commits <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits WHERE state = 'complete';")$n[1]
  stopifnot(identical(before_commits, after_commits))

  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  dag <- wb_prov_bundle_dag(b, snapshot_id = sid)
  run_nodes <- as.character(dag$nodes$run_id[dag$nodes$node_type == "run"])
  stopifnot(all(c(r_norm$run$run_id, r_hvg$run$run_id, r_pca$run$run_id, r_umap$run$run_id, r_leiden$run$run_id, r_markers$run$run_id) %in% run_nodes))
  edges <- dag$edges
  key <- paste(edges$from, edges$to, edges$edge_type, sep = "|")
  stopifnot(any(key == paste(paste0("run:", r_pca$run$run_id), paste0("run:", r_umap$run$run_id), "DERIVED_FROM", sep = "|")))
  stopifnot(any(key == paste(paste0("run:", r_pca$run$run_id), paste0("run:", r_leiden$run$run_id), "DERIVED_FROM", sep = "|")))
  stopifnot(!any(key == paste(paste0("run:", r_umap$run$run_id), paste0("run:", r_leiden$run$run_id), "DERIVED_FROM", sep = "|")))

  TRUE
}
