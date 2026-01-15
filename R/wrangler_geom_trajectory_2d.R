# R/wranglers/wrangler_geom_trajectory_2d.R

#' Add trajectory curves (2D) as a ggplot layer
#'
#' @param bundle Bundle handle
#' @param trajectory Either:
#'   - a trajectory artifact_id (character)
#'   - a session (containing head_run_id) OR a run list (with outputs$curves)
#' @param linewidth Line width for curves
#' @param alpha Line alpha
#' @return a ggplot2 layer (geom_path)
#' @export
wb_geom_trajectory_2d <- function(bundle,
                                  trajectory,
                                  linewidth = 1.0,
                                  alpha = 1.0) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  curves <- NULL

  # case 1: artifact id
  if (is.character(trajectory) && length(trajectory) == 1) {
    con <- bundle$con
    curves <- DBI::dbGetQuery(
      con,
      "SELECT lineage_id, point, x, y
       FROM artifact_curves_2d
       WHERE artifact_id = ?
       ORDER BY lineage_id, point;",
      params = list(trajectory)
    )
  } else {
    # case 2: session or run object
    # session: list with runs + head_run_id
    if (is.list(trajectory) && !is.null(trajectory$head_run_id) && !is.null(trajectory$runs)) {
      run <- trajectory$runs[[trajectory$head_run_id]]
      if (!is.null(run$outputs$curves)) curves <- run$outputs$curves
    } else if (is.list(trajectory) && !is.null(trajectory$outputs)) {
      # run object
      if (!is.null(trajectory$outputs$curves)) curves <- trajectory$outputs$curves
    } else if (is.list(trajectory) && !is.null(trajectory$curves)) {
      # direct list(curves=..., pseudotime=...) etc
      curves <- trajectory$curves
    }
  }

  if (is.null(curves) || !is.data.frame(curves) || nrow(curves) == 0) {
    stop("Could not resolve trajectory curves. Provide a trajectory artifact_id or an object containing outputs$curves.",
         call. = FALSE)
  }
  req <- c("lineage_id", "point", "x", "y")
  if (!all(req %in% colnames(curves))) {
    stop("Curves must have columns: lineage_id, point, x, y", call. = FALSE)
  }

  ggplot2::geom_path(
    data = curves,
    ggplot2::aes(x = x, y = y, group = lineage_id),
    inherit.aes = FALSE,
    linewidth = linewidth,
    alpha = alpha
  )
}
