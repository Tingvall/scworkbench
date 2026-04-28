\name{wb_motif_match_replace}
\alias{wb_motif_match_replace}
\title{Replace Motif Match Membership For A Match Set}
\usage{
wb_motif_match_replace(
  bundle,
  motif_match_set,
  matrix_id,
  motif_library,
  matches,
  organism = NULL,
  genome_build = NULL,
  genome_provider = NULL,
  match_engine = "motifmatchr",
  match_params = NULL,
  description = NULL,
  created_by = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_match_set}{Canonical engine key for this match set.}

\item{matrix_id}{Matrix identifier the matches are defined over.}

\item{motif_library}{Motif-library key used for matching.}

\item{matches}{Data frame with required columns \code{motif_key} and \code{feature_id}.}

\item{organism}{Optional organism label.}

\item{genome_build}{Optional genome-build label.}

\item{genome_provider}{Optional genome provider or ref label.}

\item{match_engine}{Match engine label, for example \code{"motifmatchr"}.}

\item{match_params}{Optional list or JSON string of matching parameters.}

\item{description}{Optional description.}

\item{created_by}{Optional author tag.}
}
\value{
Invisibly returns a small summary list.
}
\description{
Canonical engine write path for a motif-to-peak match materialization.
}
