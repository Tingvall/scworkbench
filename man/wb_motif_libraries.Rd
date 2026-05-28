\name{wb_motif_libraries}
\alias{wb_motif_libraries}
\title{List Motif Libraries}
\usage{
wb_motif_libraries(bundle, organism = NULL, genome_build = NULL, source_type = NULL)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{organism}{Optional organism filter.}

\item{genome_build}{Optional genome-build filter.}

\item{source_type}{Optional source-type filter, for example \code{"jaspar"} or
\code{"custom"}.}
}
\value{
A data frame of motif-library rows.
}
\description{
Canonical registry getter for motif-library definitions.
}
