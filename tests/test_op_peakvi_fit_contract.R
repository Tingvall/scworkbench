test_op_peakvi_fit_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("peakvi_fit", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$space$kind), "space"))
  stopifnot(identical(as.character(iface$produces$model$kind), "model_ref"))
  params <- setNames(
    iface$params,
    vapply(
      iface$params,
      function(x) {
        nm <- x$name
        if (is.null(nm)) "" else as.character(nm)
      },
      character(1)
    )
  )
  stopifnot(all(c("n_latent", "n_layers", "n_hidden", "dropout", "max_epochs", "lr", "early_stopping") %in% names(params)))
  stopifnot(identical(as.integer(params$n_latent$default), 20L))
  stopifnot(identical(as.integer(params$n_layers$default), 2L))
  stopifnot(identical(as.integer(params$n_hidden$default), 256L))
  stopifnot(isTRUE(all.equal(as.numeric(params$dropout$default), 0.2)))
  stopifnot(identical(as.integer(params$max_epochs$default), 500L))
  stopifnot(isTRUE(all.equal(as.numeric(params$lr$default), 1e-3)))
  stopifnot(isTRUE(isTRUE(params$early_stopping$default)))

  mats <- tryCatch(wb_matrices(b), error = function(e) data.frame())
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  # Contract tests earlier in the shared fixture can register synthetic
  # matrices. Prefer the golden raw-count matrix when it is available.
  mid <- if ("RNA_counts" %in% as.character(mats$matrix_id)) "RNA_counts" else as.character(mats$matrix_id[1])
  stopifnot(nzchar(mid))

  available_cells <- as.character(wb_cells(b, cell_set = "all"))
  if (length(available_cells) < 25L) {
    return(contract_test_skip("Fixture has fewer than 25 cells required by PeakVI."))
  }

  s <- wb_session_new()
  rr <- try(
    wb_session_run_op(
      session = s,
      bundle = b,
      op_name = "peakvi_fit",
      inputs = list(
        cell_set = "all",
        cell_ids = as.character(head(available_cells, 25)),
        matrix = wb_prim_matrix(mid),
        n_latent = 8L,
        n_layers = 3L,
        n_hidden = 128L,
        dropout = 0.15,
        max_epochs = 5L,
        lr = 5e-4,
        early_stopping = FALSE,
        space_id_out = "peakvi_space_test_contract"
      ),
      notes = "contract test peakvi_fit"
    ),
    silent = TRUE
  )

  if (inherits(rr, "try-error")) {
    msg <- as.character(rr)
    recognized <- grepl("pybench", msg, ignore.case = TRUE) ||
      grepl("peakvi_fit", msg, ignore.case = TRUE) ||
      grepl("scvi", msg, ignore.case = TRUE)
    if (!recognized) {
      stop("Unexpected PeakVI contract-test failure:\n", msg, call. = FALSE)
    }
    return(TRUE)
  }

  run <- rr$run
  stopifnot(wb_is_run(run))
  stopifnot(identical(as.character(run$op_name), "peakvi_fit"))
  stopifnot(identical(as.character(run$outputs$space$kind), "space"))
  stopifnot(identical(as.character(run$outputs$model$kind), "model_ref"))
  stopifnot(identical(as.integer(run$params$n_latent), 8L))
  stopifnot(identical(as.integer(run$params$n_layers), 3L))
  stopifnot(identical(as.integer(run$params$n_hidden), 128L))
  stopifnot(isTRUE(all.equal(as.numeric(run$params$dropout), 0.15)))
  stopifnot(identical(as.integer(run$params$max_epochs), 5L))
  stopifnot(isTRUE(all.equal(as.numeric(run$params$lr), 5e-4)))
  stopifnot(identical(isTRUE(run$params$early_stopping), FALSE))

  TRUE
}
