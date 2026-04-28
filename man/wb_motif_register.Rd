\name{wb_motif_register}
\alias{wb_motif_register}
\title{Register A Motif Definition}
\usage{
wb_motif_register(
  bundle,
  motif_library,
  motif_key,
  motif_name = NULL,
  motif_id = NULL,
  source_type = NULL,
  matrix_class = NULL,
  payload_json = NULL,
  metadata = NULL,
  created_by = NULL
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{motif_library}{Existing motif-library key.}

\item{motif_key}{Canonical engine key for the motif.}

\item{motif_name}{Optional human-readable motif name.}

\item{motif_id}{Optional external catalog id, for example a JASPAR id.}

\item{source_type}{Optional source type override.}

\item{matrix_class}{Optional motif matrix class label, for example \code{"PWMatrix"}.}

\item{payload_json}{Optional serialized motif payload JSON.}

\item{metadata}{Optional list or JSON string of extra metadata.}

\item{created_by}{Optional author tag.}
}
\value{
Invisibly returns a small summary list.
}
\description{
Writes one motif definition row into the motif registry. \code{payload_json} is
the canonical place for the serialized motif definition until a dedicated motif
primitive or loader surface is introduced.
}
