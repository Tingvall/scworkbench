#' Apply runtime compute profile options
#'
#' Sets package runtime options for memory/performance tradeoffs.
#' Use conservative defaults for local development and higher limits on
#' cluster nodes with large RAM.
#'
#' @param profile One of `local`, `cluster`, or `custom`.
#' @param max_dense_materialize_mb Numeric MB limit for dense fallback
#'   materialization in matrix coercion (`scworkbench.max_dense_materialize_mb`).
#'   For `custom`, this value is required.
#' @param feature_plan_chunk_size Integer chunk size used by
#'   `wb_exec_feature_selection_plan()` for prevalence/variance rules
#'   (`scworkbench.feature_plan_chunk_size`).
#'   For `custom`, this value is required.
#'
#' @return Named list of applied option values.
#' @export
wb_compute_profile <- function(profile = c("local", "cluster", "custom"),
                               max_dense_materialize_mb = NULL,
                               feature_plan_chunk_size = NULL) {
  profile <- match.arg(profile)

  if (identical(profile, "local")) {
    max_dense_materialize_mb <- 256
    feature_plan_chunk_size <- 500L
  } else if (identical(profile, "cluster")) {
    max_dense_materialize_mb <- 32768
    feature_plan_chunk_size <- 2000L
  } else {
    .wb_assert(!is.null(max_dense_materialize_mb),
               "custom profile requires max_dense_materialize_mb")
    .wb_assert(!is.null(feature_plan_chunk_size),
               "custom profile requires feature_plan_chunk_size")
  }

  max_dense_materialize_mb <- suppressWarnings(as.numeric(max_dense_materialize_mb))
  feature_plan_chunk_size <- suppressWarnings(as.integer(feature_plan_chunk_size))

  .wb_assert(is.finite(max_dense_materialize_mb) && max_dense_materialize_mb > 0,
             "max_dense_materialize_mb must be a positive number")
  .wb_assert(is.finite(feature_plan_chunk_size) && feature_plan_chunk_size > 0L,
             "feature_plan_chunk_size must be a positive integer")

  options(
    scworkbench.max_dense_materialize_mb = max_dense_materialize_mb,
    scworkbench.feature_plan_chunk_size = feature_plan_chunk_size
  )

  list(
    profile = profile,
    scworkbench.max_dense_materialize_mb = getOption("scworkbench.max_dense_materialize_mb"),
    scworkbench.feature_plan_chunk_size = getOption("scworkbench.feature_plan_chunk_size")
  )
}

