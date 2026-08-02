test_chromvar_seqlevels_contract <- function(bundle_dir) {
  if (!requireNamespace("BSgenome.Mmusculus.UCSC.mm10", quietly = TRUE)) {
    return(contract_test_skip("BSgenome.Mmusculus.UCSC.mm10 is not installed."))
  }
  genome_obj <- getExportedValue("BSgenome.Mmusculus.UCSC.mm10", "BSgenome.Mmusculus.UCSC.mm10")

  gr <- GenomicRanges::GRanges(
    seqnames = c("chr1", "chr2", "GL456233.1", "chrM"),
    ranges = IRanges::IRanges(start = c(1, 10, 20, 30), width = 50)
  )

  filt_std <- .wb_chromvar_filter_seqlevels(
    peak_ranges = gr,
    genome_obj = genome_obj,
    seqlevels_mode = "standard"
  )
  stopifnot(identical(filt_std$keep, c(TRUE, TRUE, FALSE, TRUE)))
  stopifnot(identical(filt_std$seqlevels_kept, c("chr1", "chr2", "chrM")))
  stopifnot(identical(filt_std$seqlevels_dropped, "GL456233.1"))

  filt_all <- .wb_chromvar_filter_seqlevels(
    peak_ranges = gr,
    genome_obj = genome_obj,
    seqlevels_mode = "all"
  )
  stopifnot(all(filt_all$keep))

  filt_excl <- .wb_chromvar_filter_seqlevels(
    peak_ranges = gr,
    genome_obj = genome_obj,
    seqlevels_mode = "standard",
    seqlevels_exclude = "chrM"
  )
  stopifnot(identical(filt_excl$keep, c(TRUE, TRUE, FALSE, FALSE)))

  TRUE
}
