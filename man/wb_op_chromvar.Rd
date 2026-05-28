\name{wb_op_chromvar}
\alias{wb_op_chromvar}
\title{Run chromVAR With Genome-Backed Motif Matching}
\usage{
wb_op_chromvar(
  bundle,
  matrix_id,
  cells,
  motif_library,
  motifs = NULL,
  motif_match_set = NULL,
  min_motif_peaks = 10L,
  max_motif_peaks = NULL,
  motif_p_cutoff = 5e-05,
  motif_w = 7L,
  seqlevels_mode = c("standard", "all"),
  seqlevels_include = NULL,
  seqlevels_exclude = NULL,
  background_iterations = 50L,
  background_w = 0.1,
  background_bs = 50L
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{matrix_id}{Peak-count matrix identifier.}

\item{cells}{Explicit cell ids. Required in session context.}

\item{motif_library}{Canonical motif-library key from the motif registry.}

\item{motifs}{Optional motif-key subset within \code{motif_library}.}

\item{motif_match_set}{Optional canonical motif-match-set key. When provided,
chromVAR reuses cached motif-to-peak matches instead of rerunning
\code{motifmatchr::matchMotifs()}.}

\item{min_motif_peaks}{Minimum number of matched peaks per retained motif.}

\item{max_motif_peaks}{Optional maximum number of matched peaks per retained
motif.}

\item{motif_p_cutoff}{Motifmatchr p-value cutoff.}

\item{motif_w}{Motifmatchr background window width.}

\item{seqlevels_mode}{Seqlevel policy. \code{"standard"} keeps only standard
chromosomes from the loaded genome by default; \code{"all"} keeps all parsed
seqlevels unless further restricted.}

\item{seqlevels_include}{Optional explicit seqlevels to keep after applying
\code{seqlevels_mode}.}

\item{seqlevels_exclude}{Optional explicit seqlevels to drop after applying
\code{seqlevels_mode}.}

\item{background_iterations}{Number of chromVAR background iterations.}

\item{background_w}{chromVAR background matching window width.}

\item{background_bs}{chromVAR background matching bin count.}
}
\value{
A standard op result list with \code{deviation_z}, \code{deviation_raw}, and
\code{motif_summary}.
}
\description{
Computes chromVAR deviations on a peak matrix using real peak coordinates,
matrix-level genome metadata, GC bias correction, and motif matching from the
motif registry. The op can either compute motif matches internally or reuse a
named cached \code{motif_match_set}. By default it restricts analysis to
standard chromosomes from the loaded genome.
}
