test_op_umap_runtime_preflight_contract <- function() {
  iface <- wb_op_interface("umap_fit")
  stopifnot("nn_method" %in% vapply(iface$params, function(x) as.character(x$name %||% ""), character(1)))
  nn_idx <- which(vapply(iface$params, function(x) identical(as.character(x$name %||% "")[1], "nn_method"), logical(1)))
  stopifnot(length(nn_idx) == 1L)
  nn_param <- iface$params[[nn_idx]]
  stopifnot(identical(as.character(nn_param$default), "nndescent"))
  stopifnot(all(c("nndescent", "annoy", "fnn") %in% as.character(nn_param$choices)))

  err_missing <- try(
    .wb_umap_preflight("nndescent", pkg_available = function(pkg) FALSE),
    silent = TRUE
  )
  stopifnot(inherits(err_missing, "try-error"))
  stopifnot(grepl("requires the R package 'rnndescent'", as.character(err_missing)))

  err_bad <- try(.wb_umap_preflight("made_up_backend"), silent = TRUE)
  stopifnot(inherits(err_bad, "try-error"))
  stopifnot(grepl("unsupported nn_method", as.character(err_bad)))

  if (!requireNamespace("uwot", quietly = TRUE)) {
    message("Skipping executable umap_fit preflight contract test: uwot not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_umap_preflight_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12))
  wb_define_cells(b, cells)
  wb_cell_set_replace(b, "set:fit", cells[1:8], source = "test")
  wb_cell_set_replace(b, "set:project", cells[9:12], source = "test")
  coords <- matrix(
    seq_len(12 * 4) / 10,
    nrow = 12,
    ncol = 4,
    dimnames = list(cells, paste0("PC", seq_len(4)))
  )
  wb_add_space(b, "rna.pca", coords, source = "test", overwrite = TRUE)

  rr <- wb_session_run_op(
    wb_session_new(),
    b,
    "umap_fit",
    inputs = list(
      space = "rna.pca",
      cell_set = "set:fit",
      min_cells = 1L,
      dims = 1:4,
      space_id_out = "rna.umap",
      n_neighbors = 3L,
      min_dist = 0.1,
      metric = "euclidean",
      nn_method = "annoy",
      spread = 1,
      seed = 1L
    )
  )

  stopifnot(identical(as.character(rr$run$outputs$space_2d$kind), "space_2d"))
  stopifnot(identical(as.character(rr$run$outputs$model$kind), "model_ref"))
  # UMAP output remains in the session staging overlay until promotion.
  staged <- wb_session_view(rr$session)
  stopifnot("rna.umap" %in% as.character(wb_spaces(staged)$space_id))
  stopifnot(identical(as.character(rr$run$params$uwot$nn_method), "annoy"))
  stopifnot(identical(as.integer(rr$run$params$uwot$n_neighbors), 3L))

  sm <- DBI::dbGetQuery(staged$con, "SELECT uwot_args_json FROM space_models WHERE space_id = ?;", params = list("rna.umap"))
  stopifnot(nrow(sm) == 1L)
  args <- jsonlite::fromJSON(sm$uwot_args_json[1])
  stopifnot(identical(as.character(args$nn_method), "annoy"))

  promoted <- wb_session_promote_current(b, rr$session, outputs = c("model", "space_2d"), created_by = "test")
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot("rna.umap" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(nrow(wb_space_model(b, "rna.umap")) == 1L)
  stopifnot(file.exists(wb_space_model_path(b, "rna.umap")))
  stopifnot(!is.null(wb_load_space_model(b, "rna.umap")))
  stopifnot(all(as.character(promoted$promoted$lineage_status[promoted$promoted$status == "ok"]) == "complete"))
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  model_artifact_id <- as.character(promoted$promoted$artifact_id[
    as.character(promoted$promoted$output) == "model" & as.character(promoted$promoted$status) == "ok"
  ][1])
  before_n <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM space_2d WHERE space_id = 'rna.umap';")$n[1]
  stopifnot(identical(as.integer(before_n), 8L))

  projected <- wb_session_run_op(
    wb_session_new(),
    b,
    "umap_transform",
    inputs = list(
      model = wb_ref_artifact(model_artifact_id, "model"),
      cell_set = "set:project",
      min_cells = 1L,
      overwrite = TRUE
    )
  )
  projected_promotion <- wb_session_promote_current(
    b, projected$session, outputs = "space_2d", created_by = "test"
  )
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  after_n <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM space_2d WHERE space_id = 'rna.umap';")$n[1]
  stopifnot(identical(as.integer(after_n), 12L))
  stopifnot(all(cells %in% DBI::dbGetQuery(b$con, "SELECT cell_id FROM space_2d WHERE space_id = 'rna.umap';")$cell_id))
  stopifnot(all(as.character(projected_promotion$promoted$lineage_status[projected_promotion$promoted$status == "ok"]) == "complete"))
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  TRUE
}

test_op_umap_same_session_transform_promotion_contract <- function() {
  if (!requireNamespace("uwot", quietly = TRUE)) {
    message("Skipping same-session UMAP transform promotion contract: uwot not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_umap_same_session_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12))
  wb_define_cells(b, cells)
  wb_cell_set_replace(b, "set:fit", cells[1:8], source = "test")
  wb_cell_set_replace(b, "set:project", cells[9:12], source = "test")
  coords <- matrix(
    seq_len(12 * 4) / 10,
    nrow = 12,
    dimnames = list(cells, paste0("PC", seq_len(4)))
  )
  wb_add_space(b, "rna.pca", coords, source = "test", overwrite = TRUE)

  fit <- wb_session_run_op(
    wb_session_new(), b, "umap_fit",
    inputs = list(space = "rna.pca", cell_set = "set:fit", min_cells = 1L,
                  dims = 1:4, space_id_out = "rna.umap", n_neighbors = 3L,
                  min_dist = 0.1, metric = "euclidean", nn_method = "annoy", seed = 1L)
  )
  projected <- wb_session_run_op(
    fit$session, b, "umap_transform",
    inputs = list(model = wb_ref_run(fit$run$run_id, "model"),
                  cell_set = "set:project", min_cells = 1L, overwrite = FALSE)
  )
  stopifnot(!"rna.umap" %in% as.character(wb_spaces(b)$space_id))

  promoted <- wb_session_promote_current(
    b, projected$session, outputs = "space_2d", created_by = "test"
  )
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot("rna.umap" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(nrow(wb_space(b, "rna.umap")) == length(cells))
  stopifnot(nrow(wb_space_model(b, "rna.umap")) == 1L)
  stopifnot(file.exists(wb_space_model_path(b, "rna.umap")))
  stopifnot(!is.null(wb_load_space_model(b, "rna.umap")))
  stopifnot(all(as.character(promoted$promoted$lineage_status[promoted$promoted$status == "ok"]) == "complete"))
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  TRUE
}
