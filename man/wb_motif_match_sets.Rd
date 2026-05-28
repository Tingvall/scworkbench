\name{wb_motif_match_sets}
\alias{wb_motif_match_sets}
\title{List Motif Match Sets}
\usage{
wb_motif_match_sets(
  bundle,
  matrix_id = NULL,
  motif_library = NULL,
  motif_match_set = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{matrix_id}{Optional matrix filter.}

\item{motif_library}{Optional motif-library filter.}

\item{motif_match_set}{Optional exact motif-match-set key filter.}
}
\value{
A data frame of motif-match-set rows.
}
\description{
Canonical registry getter for motif-to-peak match sets.
}
