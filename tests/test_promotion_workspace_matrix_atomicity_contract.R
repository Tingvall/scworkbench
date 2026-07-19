test_promotion_workspace_matrix_atomicity_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    message("Skipping promotion workspace matrix atomicity contract: BPCells unavailable.")
    return(TRUE)
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

  space_run <- wb_new_run(
    op_name = "umap_fit",
    inputs = list(parents = character(0), user_inputs = list()),
    params = list(),
    outputs = list(space_2d = wb_prim_space_2d(space_id = "staged_umap"))
  )
  guarded <- try(wb_promote_analysis(
    b, list(space_run), head_run_id = space_run$run_id,
    outputs = "space_2d", staging_bundle = b
  ), silent = TRUE)
  stopifnot(inherits(guarded, "try-error"),
            grepl("Staged-space atomic promotion is not yet implemented", as.character(guarded), fixed = TRUE))
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == 0L)
  TRUE
}
