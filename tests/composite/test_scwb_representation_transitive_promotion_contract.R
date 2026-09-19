test_scwb_representation_transitive_promotion_pbmc_vertical_slice_contract <- function() {
  contract_test_activate_core_conformance_pack()
  contract_test_activate_rna_pack()
  contract_test_activate_representation_pack()
  required <- c("BPCells", "Matrix", "irlba", "uwot", "igraph", "RANN")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE))) {
    missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  set.seed(11)
  root <- tempfile("scwb_transitive_promotion_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)

  cell_ids <- paste0("c", seq_len(30L))
  feature_ids <- paste0("g", seq_len(12L))
  counts <- matrix(stats::rpois(length(cell_ids) * length(feature_ids), lambda = 3),
                   nrow = length(feature_ids), dimnames = list(feature_ids, cell_ids))
  ingested <- wb_ingest_apply(
    b, set_name = "core", cell_ids = cell_ids,
    matrices = list(RNA_counts = counts), source = "pbmc_fixture",
    created_by = "test", emit_report_artifact = TRUE
  )
  ingest_artifact <- attr(ingested, "ingest_report_artifact_id", exact = TRUE)
  stopifnot(nzchar(as.character(ingest_artifact)[1]))
  ingest_heads <- nrow(wb_prov_list_heads(b))
  ingest_artifacts <- nrow(wb_art_list(b))

  # A staged session must leave the source bundle unchanged until promotion.
  s_discard <- wb_session_new()
  x_discard <- wb_session_run_op(
    s_discard, b, "matrix_log_normalize",
    inputs = list(matrix = "RNA_counts", output_matrix_id = "RNA_discard", scale_factor = 1000)
  )
  stopifnot(!"RNA_discard" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(nrow(wb_prov_list_heads(b)) == ingest_heads, nrow(wb_art_list(b)) == ingest_artifacts)
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
    inputs = list(space = "pca", dims = 1:3, space_id_out = "umap",
      nn_method = "annoy", n_neighbors = 5L, seed = 1L)
  ); s <- r_umap$session
  r_leiden <- wb_session_run_op(
    s, b, "scwbrepresentation::leiden",
    inputs = list(space = "pca", k = 5L, resolution = 0.5, seed = 1L)
  ); s <- r_leiden$session
  r_markers <- wb_session_run_op(
    s, b, "scwbv2reference::feature_table_from_matrix",
    inputs = list(matrix = "RNA_log", labels = wb_ref_run(r_leiden$run$run_id, "clusters"), result_limit = 2L)
  ); s <- r_markers$session

  stopifnot(!"RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(!"pca" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(!"umap" %in% as.character(wb_spaces(b)$space_id))

  promoted <- wb_session_promote_current(
    b, s, outputs = c("selected_features", "model", "clusters", "result"), created_by = "test"
  )
  ok <- promoted$promoted[as.character(promoted$promoted$status) == "ok", , drop = FALSE]
  stopifnot(setequal(as.character(ok$output), c("selected_features", "model", "clusters", "result")))
  arts <- wb_art_list(b)
  stopifnot(nrow(arts) == 5L)
  stopifnot(setequal(as.character(arts$source_op), c("ingest_apply", "scwbrna::hvg_select", "scwbrepresentation::umap_fit", "scwbrepresentation::leiden", "scwbv2reference::feature_table_from_matrix")))
  stopifnot(all(as.character(ok$lineage_status) == "complete"))
  stopifnot("RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(all(c("pca", "umap") %in% as.character(wb_spaces(b)$space_id)))

  sid <- as.character(promoted$provenance_snapshot_id)
  runs <- DBI::dbGetQuery(b$con, "SELECT run_id, op_name, runtime_fingerprint_json FROM prov_runs WHERE snapshot_id = ?;", params = list(sid))
  expected_run_ops <- vapply(list(r_norm, r_hvg, r_pca, r_umap,
    r_leiden, r_markers), function(x) as.character(x$run$op_name), character(1))
  stopifnot(setequal(as.character(runs$op_name), expected_run_ops))
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
  dag <- wb_prov_bundle_dag(b)
  run_nodes <- as.character(dag$nodes$run_id[dag$nodes$node_type == "run"])
  stopifnot(all(c(r_norm$run$run_id, r_hvg$run$run_id, r_pca$run$run_id, r_umap$run$run_id, r_leiden$run$run_id, r_markers$run$run_id) %in% run_nodes))
  edges <- dag$edges
  key <- paste(edges$from, edges$to, edges$edge_type, sep = "|")
  bindings <- DBI::dbGetQuery(b$con, "SELECT run_id, entity_kind, entity_id, relationship_type FROM prov_run_entity_bindings;")
  ingest_run <- DBI::dbGetQuery(b$con, paste(
    "SELECT run_id FROM prov_run_entity_bindings WHERE entity_kind='matrix' AND entity_id='RNA_counts'",
    "AND relationship_type IN ('PRODUCES','MATERIALIZES');"
  ))$run_id[1]
  aggregate_run <- DBI::dbGetQuery(b$con, "SELECT run_id FROM prov_runs WHERE op_name = 'ingest_apply';")$run_id[1]
  stopifnot(any(bindings$run_id == ingest_run & bindings$entity_kind == "matrix" & bindings$entity_id == "RNA_counts" & bindings$relationship_type == "MATERIALIZES"))
  stopifnot(!any(bindings$run_id == aggregate_run & bindings$entity_kind == "matrix" & bindings$entity_id == "RNA_counts" & bindings$relationship_type %in% c("PRODUCES","MATERIALIZES")))
  stopifnot(any(key == paste("matrix:RNA_counts", paste0("run:", r_norm$run$run_id), "CONSUMES", sep = "|")))
  stopifnot(any(key == paste(paste0("run:", ingest_run), "matrix:RNA_counts", "MATERIALIZES", sep = "|")))
  umap_model <- .wb_prov_primitive_entity_binding(r_umap$run$outputs$model)$entity_id
  stopifnot(any(key == paste(paste0("run:", r_umap$run$run_id), paste0("model_ref:", umap_model), "MATERIALIZES", sep = "|")))
  stopifnot(any(key == paste(paste0("run:", r_pca$run$run_id), paste0("run:", r_umap$run$run_id), "DERIVED_FROM", sep = "|")))
  stopifnot(any(key == paste(paste0("run:", r_pca$run$run_id), paste0("run:", r_leiden$run$run_id), "DERIVED_FROM", sep = "|")))
  stopifnot(!any(key == paste(paste0("run:", r_umap$run$run_id), paste0("run:", r_leiden$run$run_id), "DERIVED_FROM", sep = "|")))

  # The composed graph must retain a directed, durable entity/run route from
  # ingestion through all persisted PBMC intermediates to the final artifact.
  artifact_for <- function(run_id, output) {
    as.character(ok$artifact_id[as.character(ok$run_id) == run_id & as.character(ok$output) == output][1])
  }
  hvg_artifact <- artifact_for(r_hvg$run$run_id, "selected_features")
  cluster_artifact <- artifact_for(r_leiden$run$run_id, "clusters")
  markers_artifact <- artifact_for(r_markers$run$run_id, "result")
  stopifnot(all(nzchar(c(hvg_artifact, cluster_artifact, markers_artifact))))
  next_nodes <- split(as.character(edges$to), as.character(edges$from))
  directed_path <- function(from, to) {
    seen <- from; queue <- from; parent <- stats::setNames(NA_character_, from)
    while (length(queue)) {
      here <- queue[[1]]; queue <- queue[-1]
      if (identical(here, to)) break
      for (there in next_nodes[[here]] %||% character(0)) if (!(there %in% seen)) {
        seen <- c(seen, there); parent[[there]] <- here; queue <- c(queue, there)
      }
    }
    if (!(to %in% seen)) return(character(0))
    path <- to
    while (!identical(path[[1]], from)) path <- c(parent[[path[[1]]]], path)
    path
  }
  required_route_nodes <- c(
    paste0("run:", ingest_run), "matrix:RNA_counts", paste0("run:", r_norm$run$run_id),
    "matrix:RNA_log", paste0("run:", r_hvg$run$run_id), paste0("artifact:", hvg_artifact),
    paste0("run:", r_pca$run$run_id), "space:pca", paste0("run:", r_leiden$run$run_id),
    paste0("artifact:", cluster_artifact), paste0("run:", r_markers$run$run_id),
    paste0("artifact:", markers_artifact)
  )
  route_parts <- lapply(seq_len(length(required_route_nodes) - 1L), function(i) {
    directed_path(required_route_nodes[i], required_route_nodes[i + 1L])
  })
  stopifnot(all(lengths(route_parts) > 0L))
  route <- unique(unlist(route_parts, use.names = FALSE))
  .wb_assert(all(required_route_nodes %in% route), paste0(
    "Directed provenance route omitted: ",
    paste(setdiff(required_route_nodes, route), collapse = ", ")
  ))

  manifest <- wb_manifest(b)
  overview <- wb_bundle_overview(b, validate = FALSE)
  live_matrices <- wb_matrices(b)
  live_spaces <- wb_spaces(b)
  live_artifacts <- wb_art_list(b)
  stopifnot(
    identical(as.integer(manifest$counts$n_matrices), nrow(live_matrices)),
    identical(as.integer(manifest$counts$n_spaces), nrow(live_spaces)),
    identical(as.integer(manifest$counts$n_artifacts), nrow(live_artifacts)),
    identical(nrow(overview$matrices), nrow(live_matrices)),
    identical(nrow(overview$spaces), nrow(live_spaces))
  )
  reports <- wb_ingest_reports(b)
  stopifnot(any(as.character(reports$artifact_id) == as.character(ingest_artifact)[1]),
            any(as.character(reports$report_type) == "ingest_report"))
  before_manifest <- wb_manifest(b)
  failed_attach <- try(wb_attach_matrix(b, "RNA_invalid", matrix(1, nrow = 1), feature_type = "gene"), silent = TRUE)
  stopifnot(inherits(failed_attach, "try-error"),
            identical(wb_manifest(b)$counts, before_manifest$counts))

  TRUE
}
