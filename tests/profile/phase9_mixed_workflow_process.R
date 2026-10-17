args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop(paste(
  "usage: phase9_mixed_workflow_process.R LIB RECEIPT BUNDLE"), call. = FALSE)
library_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
receipt_path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
bundle_path <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
if (dir.exists(bundle_path)) stop("Mixed workflow bundle already exists")
if (!identical(Sys.getenv("PYTHONDONTWRITEBYTECODE"), "1")) stop(
  "The frozen CPU interpreter must disable installed-pack bytecode writes")
.libPaths(c(library_path, .libPaths()))
base::library(scworkbench, lib.loc = library_path)
sys.source(system.file("standard_profile", "activate.R",
  package = "scworkbench", lib.loc = library_path, mustWork = TRUE),
  envir = globalenv())
profile <- scwb_standard_profile_activate(receipt_path, lib.loc = library_path)
stopifnot(nrow(profile$packs) == 7L, length(wb_list_ops()) == 62L)

cells <- paste0("cell_", seq_len(24L))
features <- paste0("gene_", seq_len(32L))
values <- matrix(seq_len(length(cells) * length(features)) %% 11L,
  nrow = length(features), dimnames = list(features, cells))
bundle <- wb_init_bundle(bundle_path)
on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
wb_define_cells(bundle, cells)
wb_attach_matrix(bundle, "RNA_counts", Matrix::Matrix(values, sparse = TRUE),
  layer = "counts", feature_type = "gene", cell_ids = cells)
wb_cell_set_replace(bundle, "set:start", cells[1:4], source = "phase9-profile")
wb_cell_set_replace(bundle, "set:end", cells[21:24], source = "phase9-profile")
wb_close_bundle(bundle)
source_only <- file.path(dirname(bundle_path), "source_only",
  basename(bundle_path))
dir.create(dirname(source_only), recursive = TRUE)
if (!isTRUE(file.copy(bundle_path, dirname(source_only), recursive = TRUE)))
  stop("Could not retain the mixed workflow source-only bundle")
bundle <- wb_open_bundle(bundle_path)

rna <- wb_session_run_op(wb_session_new(), bundle,
  "scwbrna::matrix_log_normalize", inputs = list(matrix = "RNA_counts",
    cell_set = "all", min_cells = 1L, output_matrix_id = "RNA_log",
    scale_factor = 1000, chunk_size = 6L))
stopifnot("RNA_log" %in% wb_matrices(wb_session_view(rna$session))$matrix_id,
  !"RNA_log" %in% wb_matrices(bundle)$matrix_id)

pca_inputs <- list(matrix = "RNA_log", cell_set = "all", min_cells = 1L,
  n_components = 3L, backend = "prcomp", scale = FALSE,
  space_id_out = "pca", chunk_size = 8L, max_dense_gb = 1)
old_hook <- getOption("scworkbench.operation_pack_v2_test_hook", NULL)
options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
  if (identical(event, "before_publication"))
    stop("phase9 injected cross-pack publication fault")
})
failed <- try(wb_session_run_op(rna$session, bundle,
  "scwbrepresentation::pca_fit", inputs = pca_inputs), silent = TRUE)
options(scworkbench.operation_pack_v2_test_hook = old_hook)
stopifnot(inherits(failed, "try-error"),
  !"pca" %in% wb_spaces(wb_session_view(rna$session))$space_id,
  !"pca" %in% wb_spaces(bundle)$space_id)
pca <- wb_session_run_op(rna$session, bundle,
  "scwbrepresentation::pca_fit", inputs = pca_inputs)
stopifnot("pca" %in% wb_spaces(wb_session_view(pca$session))$space_id)

programs <- wb_session_run_op(pca$session, bundle,
  "scwbgeneprograms::addmodulescore", inputs = list(matrix = "RNA_log",
    cell_set = "all", min_cells = 1L,
    features = list(program_A = features[1:3],
      program_B = features[4:6]), nbin = 4L, ctrl = 2L, seed = 17L))
stopifnot(identical(names(programs$run$outputs), "module_scores"))

latent <- wb_session_run_op(programs$session, bundle,
  "scwblatent::scvi_train", inputs = list(matrix = "RNA_counts",
    cell_set = "all", min_cells = 1L, n_latent = 2L, n_layers = 1L,
    n_hidden = 16L, max_epochs = 1L, chunk_size = 6L, seed = 17L))
latent_space <- as.character(latent$run$outputs$space$space_id)
stopifnot(latent_space %in% wb_spaces(wb_session_view(latent$session))$space_id)

path <- wb_session_run_op(latent$session, bundle,
  "scwbtrajectory::space_path_define", inputs = list(space = "pca",
    checkpoint_sets = c("set:start", "set:end"), n_path_points = 8L,
    path_id_out = "phase9_path", min_cells = 1L))
promoted <- wb_session_promote_current(bundle, path$session,
  outputs = c("path", "module_scores", "model"),
  created_by = "phase9-source-profile")
ok <- promoted$promoted[as.character(promoted$promoted$status) == "ok", ,
  drop = FALSE]
stopifnot(setequal(as.character(ok$op_name), c(
    "scwbtrajectory::space_path_define",
    "scwbgeneprograms::addmodulescore", "scwblatent::scvi_train")),
  all(c("pca", latent_space) %in% wb_spaces(bundle)$space_id),
  "RNA_log" %in% wb_matrices(bundle)$matrix_id,
  isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
wb_close_bundle(bundle)
cat("PHASE9_MIXED_WORKFLOW_OK packs=5 cross_pack_fault_retried=TRUE",
  " promoted=", nrow(ok), " bundle=", bundle_path,
  " source_only=", source_only, "\n", sep = "")
