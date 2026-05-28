test_op_chromvar_contract <- function(bundle_dir) {
  if (!requireNamespace("chromVAR", quietly = TRUE) ||
      !requireNamespace("motifmatchr", quietly = TRUE) ||
      !requireNamespace("BSgenome.Hsapiens.UCSC.hg19", quietly = TRUE)) {
    message("Skipping chromvar contract test: chromVAR motif dependencies not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_chromvar_contract_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  data("mini_counts", package = "chromVAR", envir = environment())
  x <- mini_counts
  rr <- SummarizedExperiment::rowRanges(x)
  cells <- colnames(x)
  wb_define_cells(b, cells)

  peak_ids <- paste0(
    as.character(GenomicRanges::seqnames(rr)),
    ":",
    as.integer(GenomicRanges::start(rr)),
    "-",
    as.integer(GenomicRanges::end(rr))
  )
  counts_dense <- SummarizedExperiment::assay(x, "counts")
  rownames(counts_dense) <- peak_ids
  dimnames(counts_dense) <- list(peak_ids, cells)

  mat <- Matrix::Matrix(
    counts_dense,
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "ATAC_counts", mat = mat, feature_type = "peak")
  wb_matrix_set_genome(
    b,
    matrix_id = "ATAC_counts",
    organism = "human",
    genome_build = "hg19",
    genome_provider = "BSgenome.Hsapiens.UCSC.hg19"
  )
  wb_motif_library_import_jaspar(
    b,
    motif_library = "jaspar2020_core_human",
    jaspar_pkg = "JASPAR2020",
    species = "9606",
    collection = "CORE",
    organism = "human",
    genome_build = "hg19",
    motif_ids = c("MA0139.1", "MA1102.2", "MA0140.2")
  )

  iface <- wb_op_interface("chromvar", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "chromvar"))
  stopifnot(identical(as.character(iface$produces$deviation_z$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$motif_summary$kind), "obs_table"))
  stopifnot(any(vapply(iface$params, function(x) identical(x$name, "seqlevels_mode"), logical(1))))
  stopifnot("chromvar" %in% wb_list_ops())

  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "chromvar",
    inputs = list(
      matrix = "ATAC_counts",
      cell_set = "all",
      cell_ids = cells,
      motif_library = "jaspar2020_core_human",
      min_motif_peaks = 3L,
      motif_p_cutoff = 5e-05,
      motif_w = 7L,
      background_iterations = 3L,
      background_bs = 10L,
      background_w = 0.1
    ),
    notes = "test chromvar: run"
  )

  run <- rr$run
  stopifnot(all(c("deviation_z", "deviation_raw", "motif_summary") %in% names(run$outputs)))
  z <- run$outputs$deviation_z
  raw <- run$outputs$deviation_raw
  sm <- run$outputs$motif_summary

  stopifnot(inherits(z, "wb_primitive"), identical(as.character(z$kind), "cell_vector_family"))
  stopifnot(inherits(raw, "wb_primitive"), identical(as.character(raw$kind), "cell_vector_family"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(sm$table_type), "chromvar_summary"))
  stopifnot(length(unique(as.character(z$key))) >= 1L)
  stopifnot(nrow(sm$table) >= 1L)
  stopifnot(all(c("motif_key", "motif_id", "motif_name", "motif_library", "matched_peaks", "variability", "mean_abs_z") %in% colnames(sm$table)))
  stopifnot(all(as.character(sm$table$genome_pkg) == "BSgenome.Hsapiens.UCSC.hg19"))
  stopifnot(all(as.character(sm$table$motif_library) == "jaspar2020_core_human"))

  TRUE
}
