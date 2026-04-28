\name{wb_motif_library_register}
\alias{wb_motif_library_register}
\title{Register A Motif Library}
\usage{
wb_motif_library_register(
  bundle,
  motif_library,
  source_type,
  organism = NULL,
  genome_build = NULL,
  collection = NULL,
  source_id = NULL,
  source_version = NULL,
  description = NULL,
  created_by = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_library}{Canonical engine key for the library.}

\item{source_type}{Source type, for example \code{"jaspar"} or \code{"custom"}.}

\item{organism}{Optional organism label.}

\item{genome_build}{Optional genome-build label.}

\item{collection}{Optional collection label, for example \code{"CORE"}.}

\item{source_id}{Optional source identifier.}

\item{source_version}{Optional source version.}

\item{description}{Optional description.}

\item{created_by}{Optional author tag.}
}
\value{
Invisibly returns a small summary list.
}
\description{
Writes one motif-library definition row. Motif definitions themselves are stored
separately in the \code{motifs} registry.
}
