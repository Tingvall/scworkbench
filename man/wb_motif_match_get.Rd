\name{wb_motif_match_get}
\alias{wb_motif_match_get}
\title{Load Motif Match Membership}
\usage{
wb_motif_match_get(bundle, motif_match_set, motif_keys = NULL)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_match_set}{Motif-match-set key.}

\item{motif_keys}{Optional motif-key subset.}
}
\value{
A data frame with \code{motif_key} and \code{feature_id} membership rows.
}
\description{
Canonical getter for motif-to-peak membership rows.
}
