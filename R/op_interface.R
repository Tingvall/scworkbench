# R/op_interface.R

# Internal registry for UI/agent interface specs (v1)
.wb_op_interface_registry <- function() {
  list(

    leiden = list(
      op_name = "leiden",
      title = "Leiden clustering",
      description = "Graph clustering on a kNN graph derived from an embedding space.",
      intent = c("cluster"),
      inputs = list(
        space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "dims", type = "int_range", default = "1:30",
             help = "Which dimensions of the space to use (1-indexed)."),
        list(name = "k", type = "int", default = 30, min = 5, max = 200,
             help = "Number of neighbors for kNN graph."),
        list(name = "resolution", type = "dbl", default = 1.0, min = 0.01, max = 10,
             help = "Leiden resolution parameter."),
        list(name = "seed", type = "int", default = 1,
             help = "Random seed.")
      ),
      produces = list(
        labels = list(
          kind = "labels",
          description = "Cluster label per cell.",
          colorable = TRUE,
          color_type = "categorical",
          label = "Leiden clusters"
        )
      )
    ),

    slingshot = list(
      op_name = "slingshot",
      title = "Slingshot trajectory",
      description = "Infer lineage curves and pseudotime from clusters in a 2D space.",
      intent = c("trajectory"),
      inputs = list(
        space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2),
        plot_space = list(required = FALSE, must_be_2d = TRUE, dims_min = 2, dims_max = 2),
        labels = list(required = TRUE)
      ),
      params = list(
        list(name = "start.clus", type = "string", default = NULL,
             help = "Starting cluster id."),
        list(name = "end.clus", type = "string_vec", default = NULL,
             help = "Ending cluster id(s)."),
        list(name = "exclude_clusters", type = "string_vec", default = character(0),
             help = "Cluster id(s) to exclude before fitting."),
        list(name = "stretch", type = "dbl", default = 2, min = 0, max = 10,
             help = "Slingshot curve stretching."),
        list(name = "reweight", type = "bool", default = TRUE,
             help = "Whether to reweight assignments during fitting.")
      ),
      produces = list(
        trajectory = list(
          kind = "trajectory",
          description = "Pseudotime + fitted curves.",
          # trajectory itself overlays as curves, but also exposes pseudotime vectors per lineage
          colorables = list(
            pseudotime = list(
              kind = "vector_family",
              value_kind = "continuous",
              key = "lineage_id",
              label = "Slingshot pseudotime"
            )
          )
        )
      )
    ),

    meanexpr = list(
      op_name = "meanexpr",
      title = "Mean expression score",
      description = "Compute mean expression over a feature set per cell.",
      intent = c("score"),
      inputs = list(
        matrix = list(required = TRUE),
        features = list(required = TRUE, kind = "features")
      ),
      params = list(),
      produces = list(
        scores = list(
          kind = "scores",
          description = "Per-cell numeric score.",
          colorable = TRUE,
          color_type = "continuous",
          label = "Mean expression"
        )
      )
    )

  )
}


#' List available ops (UI/agent interface)
#' @export
wb_list_ops <- function() {
  names(.wb_op_interface_registry())
}

#' High-level op interface spec (for UIs and agents)
#'
#' JSON-serializable description of inputs/params/outputs.
#'
#' @param op_name Operation name
#' @export
wb_op_interface <- function(op_name) {
  op_name <- as.character(op_name)
  reg <- .wb_op_interface_registry()
  if (!op_name %in% names(reg)) {
    stop("Unknown op: ", op_name, call. = FALSE)
  }
  reg[[op_name]]
}


.wb_validate_op_interface <- function(spec) {
  .wb_assert(!is.null(spec$op_name) && nzchar(spec$op_name), "spec missing op_name")
  .wb_assert(is.list(spec$inputs), "spec$inputs must be a list")
  .wb_assert(is.list(spec$params), "spec$params must be a list")
  .wb_assert(is.list(spec$produces), "spec$produces must be a list")
  invisible(TRUE)
}
