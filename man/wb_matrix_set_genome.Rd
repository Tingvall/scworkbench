\name{wb_matrix_set_genome}
\alias{wb_matrix_set_genome}
\title{Set Genome Metadata For A Matrix}
\usage{
wb_matrix_set_genome(
  bundle,
  matrix_id,
  organism,
  genome_build,
  genome_provider = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{matrix_id}{Matrix identifier.}

\item{organism}{Organism label, for example \code{"human"} or \code{"mouse"}.}

\item{genome_build}{Genome build label, for example \code{"hg38"} or \code{"mm10"}.}

\item{genome_provider}{Optional provider/ref label, for example
\code{"BSgenome.Hsapiens.UCSC.hg38"}.}
}
\value{
Invisibly returns a small summary list.
}
\description{
Canonical engine write path for declaring the organism/build contract of a
matrix. Peak matrices should carry this metadata explicitly.
}
