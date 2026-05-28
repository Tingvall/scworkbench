\name{wb_motif_library_import_jaspar}
\alias{wb_motif_library_import_jaspar}
\title{Import JASPAR Motifs Into The Registry}
\usage{
wb_motif_library_import_jaspar(
  bundle,
  motif_library,
  jaspar_pkg = "JASPAR2020",
  species,
  collection = "CORE",
  motif_ids = NULL,
  motif_names = NULL,
  organism = NULL,
  genome_build = NULL,
  description = NULL,
  created_by = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_library}{Canonical engine key for the library.}

\item{jaspar_pkg}{Installed JASPAR data package name.}

\item{species}{JASPAR species filter.}

\item{collection}{JASPAR collection filter.}

\item{motif_ids}{Optional exact JASPAR motif ids to retain.}

\item{motif_names}{Optional motif names to retain.}

\item{organism}{Optional organism label for the library row.}

\item{genome_build}{Optional genome-build label for the library row.}

\item{description}{Optional description.}

\item{created_by}{Optional author tag.}
}
\value{
Invisibly returns a small summary list.
}
\description{
Convenience importer for populating a motif library from an installed JASPAR
data package.
}
