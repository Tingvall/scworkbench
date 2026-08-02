test_promotion_workspace_matrix_atomicity_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  root <- tempfile("scwb_promotion_workspace_matrix_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12L))
  counts <- matrix(seq_len(48L), nrow = 4L,
                   dimnames = list(paste0("g", seq_len(4L)), cells))
  wb_define_cells(b, cells)
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = counts, feature_type = "gene")

  s <- wb_session_new()
  staged <- wb_session_run_op(
    s, b, "matrix_log_normalize",
    inputs = list(matrix = "RNA_counts", output_matrix_id = "RNA_log", scale_factor = 1000)
  )
  s <- staged$session
  missing_payload <- try(
    scworkbench:::.wb_prov_resolve_payload_location(
      b, "mat/definitely_missing_fragment", staging_bundle = wb_session_view(s),
      kind = "matrix fragment", id = "RNA_log"
    ),
    silent = TRUE
  )
  stopifnot(inherits(missing_payload, "try-error"),
            grepl("matrix fragment.*RNA_log.*session_staging", as.character(missing_payload)))
  hook_calls <- 0L
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    hook_calls <<- hook_calls + 1L
    if (hook_calls == 2L) stop("forced workspace publication failure", call. = FALSE)
  })

  failed <- try(wb_promote_analysis(
    b, s$runs, head_run_id = staged$run$run_id,
    outputs = "summary", staging_bundle = wb_session_view(s)
  ), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), hook_calls >= 2L)
  stopifnot(!"RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(!dir.exists(file.path(root, "mat", "RNA_log")))
  pending_root <- file.path(root, "provenance", ".pending")
  stopifnot(!dir.exists(pending_root) || !length(list.files(pending_root, all.files = FALSE, no.. = TRUE)))
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_heads;")$n[1] == 0L)
  stopifnot(nrow(wb_art_list(b)) == 0L)

  TRUE
}

test_promotion_workspace_mixed_matrix_space_atomicity_contract <- function() {
  required <- c("BPCells", "Matrix", "irlba", "uwot")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE))) {
    missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  root <- tempfile("scwb_promotion_workspace_mixed_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  set.seed(19)
  cells <- paste0("c", seq_len(20L))
  counts <- matrix(stats::rpois(240L, lambda = 3), nrow = 12L,
                   dimnames = list(paste0("g", seq_len(12L)), cells))
  wb_define_cells(b, cells)
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = counts, feature_type = "gene")

  s <- wb_session_new()
  r_norm <- wb_session_run_op(s, b, "matrix_log_normalize",
                              inputs = list(matrix = "RNA_counts", output_matrix_id = "RNA_log", scale_factor = 1000)); s <- r_norm$session
  r_pca <- wb_session_run_op(s, b, "pca_fit",
                             inputs = list(matrix = "RNA_log", n_components = 3L, space_id_out = "pca")); s <- r_pca$session
  r_umap <- wb_session_run_op(s, b, "umap_fit",
                              inputs = list(space = "pca", space_id_out = "umap", nn_method = "annoy", n_neighbors = 5L, seed = 1L)); s <- r_umap$session
  staged_bundle <- wb_session_view(s)
  model_rel <- as.character(wb_space_model(staged_bundle, "umap")$model_path[1])

  hook_calls <- 0L
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    hook_calls <<- hook_calls + 1L
    if (hook_calls == 3L) stop("forced mixed workspace publication failure", call. = FALSE)
  })
  failed <- try(wb_promote_analysis(
    b, s$runs, head_run_id = r_umap$run$run_id,
    outputs = c("model", "space_2d"), staging_bundle = staged_bundle
  ), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), hook_calls >= 3L)
  stopifnot(!"RNA_log" %in% as.character(wb_matrices(b)$matrix_id))
  stopifnot(!any(c("pca", "umap") %in% as.character(wb_spaces(b)$space_id)))
  stopifnot(!file.exists(file.path(root, model_rel)))
  pending_root <- file.path(root, "provenance", ".pending")
  stopifnot(!dir.exists(pending_root) || !length(list.files(pending_root, all.files = FALSE, no.. = TRUE)))
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_heads;")$n[1] == 0L)
  stopifnot(nrow(wb_art_list(b)) == 0L)
  stopifnot(!.wb_table_exists(b$con, "space_models") || DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM space_models;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM artifact_model_ref;")$n[1] == 0L)
  TRUE
}
