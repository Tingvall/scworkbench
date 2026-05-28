\name{wb_motifs}
\alias{wb_motifs}
\title{List Motifs}
\usage{
wb_motifs(bundle, motif_library = NULL, motif_keys = NULL)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_library}{Optional motif-library filter.}

\item{motif_keys}{Optional explicit motif-key filter.}
}
\value{
A data frame of motif-definition rows.
}
\description{
Canonical registry getter for motif definitions.
}
