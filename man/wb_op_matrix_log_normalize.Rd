\name{wb_op_matrix_log_normalize}
\alias{wb_op_matrix_log_normalize}
\title{Log-Normalize A Count Matrix}
\usage{
wb_op_matrix_log_normalize(
  bundle,
  matrix_id,
  output_matrix_id = NULL,
  scale_factor = 10000,
  overwrite = FALSE
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{matrix_id}{Source count matrix id.}

\item{output_matrix_id}{New matrix id. Defaults to
\code{paste0(matrix_id, "_log1p_cp", scale_factor)}.}

\item{scale_factor}{Per-cell target count scale, conventionally \code{10000}.}

\item{overwrite}{Replace an existing output matrix if present.}
}
\value{
Standard op result with \code{outputs$matrix} and \code{outputs$summary}.
}
\description{
Creates a reusable \code{log1p(counts / library_size * scale_factor)} matrix in
the bundle. Version 1 writes a full feature-by-cell BPCells matrix and
registers it under \code{output_matrix_id}.
}
\details{
The operation computes each cell's library size from the selected source matrix,
scales counts to the requested total, applies \code{log1p()}, writes the result
as a BPCells matrix directory, and registers it in the bundle matrix catalog.

The session op is exposed as \code{matrix_log_normalize}. In this first version
it writes full bundle matrices only, so use \code{cell_set = "all"} when running
through \code{wb_session_run_op()}.
}
