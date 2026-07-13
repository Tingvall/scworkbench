#!/usr/bin/env Rscript

# Guard against a mixed Bioconductor namespace where the standalone Seqinfo
# package overwrites the Seqinfo S4 API provided by release GenomeInfoDb.
if (requireNamespace("Seqinfo", quietly = TRUE)) {
  stop("Standalone Seqinfo must not be installed in the fullstack runtime")
}

required <- c("GenomeInfoDb", "GenomicRanges", "IRanges")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Missing required genomic runtime package(s): ", paste(missing, collapse = ", "))
}

gr <- GenomicRanges::GRanges(
  seqnames = "chr1",
  ranges = IRanges::IRanges(start = 1L, end = 10L)
)
si <- GenomeInfoDb::seqinfo(gr)
if (!methods::is(si, "Seqinfo")) {
  stop("GenomeInfoDb::seqinfo() did not return a Seqinfo object for GRanges")
}
if (!identical(as.character(GenomeInfoDb::seqnames(gr)), "chr1")) {
  stop("GenomeInfoDb sequence-information dispatch returned an unexpected sequence name")
}

cat(
  "GenomicRanges namespace preflight OK: GenomeInfoDb=", as.character(utils::packageVersion("GenomeInfoDb")),
  " GenomicRanges=", as.character(utils::packageVersion("GenomicRanges")),
  "\n",
  sep = ""
)
