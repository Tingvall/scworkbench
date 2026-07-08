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
      cell_set = "all",
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
  stopifnot("rna.umap" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(identical(as.character(rr$run$params$uwot$nn_method), "annoy"))
  stopifnot(identical(as.integer(rr$run$params$uwot$n_neighbors), 3L))

  sm <- DBI::dbGetQuery(b$con, "SELECT uwot_args_json FROM space_models WHERE space_id = ?;", params = list("rna.umap"))
  stopifnot(nrow(sm) == 1L)
  args <- jsonlite::fromJSON(sm$uwot_args_json[1])
  stopifnot(identical(as.character(args$nn_method), "annoy"))

  TRUE
}
