\name{wb_op_trajectory_vector_smooth}
\alias{wb_op_trajectory_vector_smooth}
\title{Compute Trajectory Smoothing For Cell-Level Signals}
\usage{
wb_op_trajectory_vector_smooth(
  bundle,
  signal,
  model,
  cells = NULL,
  lineage = NULL,
  signal_keys = NULL,
  n_bins = 50L,
  summary_fun = "mean",
  min_cells_per_bin = 5L
)
}
\arguments{
\item{bundle}{Open \code{scworkbench_bundle}.}

\item{signal}{A \code{cell_vector_family} primitive. Direct \code{cell_vector}
primitives are also accepted by the implementation and are lifted to a
single-key family.}

\item{model}{A \code{model_ref} primitive from trajectory fitting.}

\item{cells}{Optional effective cell IDs to restrict analysis.}

\item{lineage}{Optional lineage key subset.}

\item{signal_keys}{Optional signal-key subset within \code{signal}.}

\item{n_bins}{Number of pseudotime bins.}

\item{summary_fun}{One of \code{"mean"} or \code{"median"} across cells within each bin.}

\item{min_cells_per_bin}{Minimum cells required for an output bin.}
}
\value{
A standard op result list with \code{outputs} containing \code{signal_table}
and \code{fit_summary}, plus normalized \code{params}.
}
\description{
Summarizes one or more cell-level signals along lineage pseudotime from a
trajectory model. This is the generic smoothing surface for
\code{cell_vector_family}-style outputs such as chromVAR motif activity, module
scores, or other per-cell signal families.
}
