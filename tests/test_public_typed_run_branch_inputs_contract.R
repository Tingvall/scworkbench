.typed_replay_tree_fingerprint <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
                           full.names = TRUE, include.dirs = FALSE, no.. = TRUE))
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  list(
    paths = substring(files, nchar(root) + 2L),
    sizes = as.numeric(file.info(files)$size),
    sha256 = vapply(files, scworkbench:::.wb_prov_sha256_file, character(1))
  )
}

test_public_typed_run_branch_inputs_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  required <- c("BPCells", "uwot", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  root <- tempfile("scwb_typed_replay_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("cell_", seq_len(36L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, sample_id = rep(c("s1", "s2"), each = 18L),
    donor = rep(c("d1", "d2", "d3"), each = 12L), stringsAsFactors = FALSE
  ))
  coords <- outer(seq_along(cells), seq_len(30L), function(i, j) sin(i / 3 + j / 7))
  rownames(coords) <- cells
  wb_attach_space(b, "rna.scvi.parent",
                  data.frame(cell_id = cells, coords, check.names = FALSE),
                  source = "typed-replay-fixture")

  fit <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs = list(
    space = "rna.scvi.parent", dims = 1:30, space_id_out = "rna.umap.parent",
    n_neighbors = 5L, min_dist = 0.15, metric = "euclidean",
    nn_method = "annoy", spread = 1, seed = 17L,
    cell_set = "all", min_cells = 2L
  ))
  promoted <- wb_session_promote_current(
    b, fit$session, outputs = "model", created_by = "typed-replay-contract"
  )
  stopifnot(all(promoted$promoted$status == "ok"))
  sid <- promoted$provenance_snapshot_id
  details <- wb_prov_run_details(b, fit$run$run_id, sid)
  stopifnot(is.list(details$run$inputs$user_inputs$dims))

  wb_close_bundle(b)
  b <- wb_open_bundle(root, read_only = TRUE)
  set.seed(4801L)
  seed_before <- .Random.seed
  fingerprint_before <- .typed_replay_tree_fingerprint(root)
  spec <- wb_prov_run_replay_inputs(b, fit$run$run_id, sid)
  fingerprint_after <- .typed_replay_tree_fingerprint(root)
  stopifnot(
    inherits(spec, "wb_prov_run_replay_inputs"),
    identical(spec$schema_version, "scworkbench.provenance.run_replay_inputs.v1"),
    identical(spec$diagnostics$status, "compatible"),
    identical(spec$inputs$dims, 1:30), is.integer(spec$inputs$dims),
    identical(seed_before, .Random.seed), identical(fingerprint_before, fingerprint_after)
  )
  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  invalid_ephemeral_inputs <- spec$inputs
  invalid_ephemeral_inputs$dims <- details$run$inputs$user_inputs$dims
  invalid_ephemeral_inputs$space_id_out <- "rna.umap.must_not_exist"
  invalid_before <- .typed_replay_tree_fingerprint(root)
  invalid_ephemeral <- tryCatch(
    wb_session_run_op(wb_session_new(), b, "umap_fit", inputs = invalid_ephemeral_inputs),
    error = identity
  )
  stopifnot(inherits(invalid_ephemeral, "error"),
            grepl("inputs\\$dims must be numeric and mathematically integral", conditionMessage(invalid_ephemeral)),
            identical(invalid_before, .typed_replay_tree_fingerprint(root)),
            !"rna.umap.must_not_exist" %in% wb_spaces(b, include_history = TRUE)$space_id)
  sibling_inputs <- spec$inputs
  sibling_inputs$space <- "rna.scvi.parent"
  sibling_inputs$space_id_out <- "rna.umap.sibling"
  sibling <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs = sibling_inputs)
  stopifnot(identical(sibling$run$inputs$user_inputs$dims, 1:30))

  # The authoritative rehydrator covers every catalog shape used in persisted
  # provenance, without weakening the operation validator.
  typed <- scworkbench:::.wb_prov_rehydrate_named_inputs(list(
    n_latent = list(30L), dropout = list(0.1), early_stopping = list(TRUE),
    output_space_id = list("rna.scvi.typed"), max_epochs = NULL,
    categorical_covariates = list("sample_id", "donor"),
    batch_key = list("sample_id")
  ), "scvi_train")
  stopifnot(is.integer(typed$n_latent), is.numeric(typed$dropout),
            is.logical(typed$early_stopping), is.character(typed$output_space_id),
            is.null(typed$max_epochs), identical(typed$categorical_covariates, c("sample_id", "donor")),
            identical(typed$batch_key, "sample_id"))
  symbolic <- scworkbench:::.wb_prov_replay_execution_inputs(
    list(space = list(ref_type = "run", run_id = "parent", output = "space"), dims = as.list(1:3)),
    list(space_id_out = "branch", seed = 1L), run_id = "symbolic", op_name = "umap_fit"
  )
  stopifnot(identical(symbolic$space, wb_ref_run("parent", "space")),
            identical(symbolic$dims, 1:3))

  conflict <- DBI::dbGetQuery(b$con,
    "SELECT params_json FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
    params = list(sid, fit$run$run_id))$params_json[[1L]]
  conflict_params <- jsonlite::fromJSON(conflict, simplifyVector = TRUE, simplifyDataFrame = FALSE)
  conflict_params$dims <- 2:30
  DBI::dbExecute(b$con, "UPDATE prov_runs SET params_json=? WHERE snapshot_id=? AND run_id=?;",
    params = list(jsonlite::toJSON(conflict_params, auto_unbox = TRUE, null = "null"), sid, fit$run$run_id))
  collision <- tryCatch(wb_prov_run_replay_inputs(b, fit$run$run_id, sid), error = identity)
  stopifnot(inherits(collision, "error"), grepl("collision", conditionMessage(collision), ignore.case = TRUE))
  DBI::dbExecute(b$con, "UPDATE prov_runs SET params_json=? WHERE snapshot_id=? AND run_id=?;",
    params = list(conflict, sid, fit$run$run_id))

  DBI::dbExecute(b$con, "UPDATE prov_runs SET op_version='999' WHERE snapshot_id=? AND run_id=?;",
    params = list(sid, fit$run$run_id))
  incompatible <- wb_prov_run_replay_inputs(b, fit$run$run_id, sid)
  stopifnot(identical(incompatible$diagnostics$status, "incompatible"),
            !length(incompatible$inputs),
            "OPERATION_VERSION_INCOMPATIBLE" %in% vapply(incompatible$diagnostics$issues, `[[`, character(1), "code"))
  DBI::dbExecute(b$con, "UPDATE prov_runs SET op_version='1' WHERE snapshot_id=? AND run_id=?;",
    params = list(sid, fit$run$run_id))

  duplicate_sid <- paste0(sid, "_historical")
  snapshot_row <- DBI::dbGetQuery(b$con, "SELECT * FROM prov_heads WHERE snapshot_id=?;",
                                  params = list(sid))
  snapshot_row$snapshot_id <- duplicate_sid
  DBI::dbWriteTable(b$con, "prov_heads", snapshot_row, append = TRUE)
  row <- DBI::dbGetQuery(b$con, "SELECT * FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
                         params = list(sid, fit$run$run_id))
  row$snapshot_id <- duplicate_sid
  DBI::dbWriteTable(b$con, "prov_runs", row, append = TRUE)
  ambiguous <- tryCatch(wb_prov_run_replay_inputs(b, fit$run$run_id), error = identity)
  explicit <- wb_prov_run_replay_inputs(b, fit$run$run_id, sid)
  stopifnot(inherits(ambiguous, "scworkbench_provenance_lookup_error"),
            identical(ambiguous$code, "PROVENANCE_RUN_AMBIGUOUS"),
            identical(explicit$snapshot_id, sid), identical(explicit$inputs$dims, 1:30))
  TRUE
}
