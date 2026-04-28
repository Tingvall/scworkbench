\name{wb_op_cell_vector_family_reduce}
\alias{wb_op_cell_vector_family_reduce}
\title{Reduce A Cell Vector Family}
\usage{
wb_op_cell_vector_family_reduce(
  signal,
  signal_keys = NULL,
  rule = c("argmax"),
  min_score = NULL,
  min_margin = NULL,
  unknown_label = "unknown",
  ties = c("unknown", "first"),
  tie_tol = 1e-08
)
}
\arguments{
  \item{signal}{A \code{cell\_vector\_family} primitive.}
  \item{signal_keys}{Optional character vector of keys to consider.}
  \item{rule}{Reduction rule. Currently only \code{"argmax"} is implemented.}
  \item{min_score}{Optional minimum winning score required to emit a label.}
  \item{min_margin}{Optional minimum top-vs-second margin required to emit a label.}
  \item{unknown_label}{Fallback label emitted when thresholds or ties abstain.}
  \item{ties}{How to handle tied top scores: \code{"unknown"} or \code{"first"}.}
  \item{tie_tol}{Numeric tolerance for tie detection.}
}
\value{
Standard op result list with \code{label}, \code{top\_score},
\code{score\_margin}, \code{label\_summary}, and normalized \code{params}.
}
\description{
Compresses a family of per-cell continuous scores into one categorical label per
cell using an explicit rule. The default rule is \code{argmax}, with optional
abstention thresholds on absolute score and winner margin.
}
