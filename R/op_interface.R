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
    umap_fit = list(
      op_name = "umap_fit",
      title = "UMAP fit (uwot)",
      description = "Fit a 2D UMAP from a high-dimensional space and persist model for later projection.",
      intent = c("embed", "projection"),
      inputs = list(
        in_space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name="dims", type="int_range", default="2:30", help="Dims of source space to use."),
        list(name="space_id_out", type="string", default=NULL, help="Output space id (default: umap.<in_space>)."),
        list(name="n_neighbors", type="int", default=30, min=5, max=200, help="UMAP n_neighbors."),
        list(name="min_dist", type="dbl", default=0.3, min=0.0, max=1.0, help="UMAP min_dist."),
        list(name="metric", type="string", default="euclidean", help="Distance metric."),
        list(name="nn_method", type="string", default="nndescent", help="Nearest-neighbor method."),
        list(name="seed", type="int", default=1, help="Random seed.")
      ),
      side_effects = list(
        space_2d = list(kind="space_2d", description="Writes fitted embedding to space_2d and registers the space."),
        model    = list(kind="space_model", description="Writes uwot model to disk and registers it in space_models.")
      ),
      produces = list()
    ),

    umap_transform = list(
      op_name = "umap_transform",
      title = "UMAP transform (project cells)",
      description = "Project cells into an existing UMAP using a stored uwot model.",
      intent = c("projection", "umap"),

      inputs = list(
        in_space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2),
        model_space = list(required = TRUE, must_be_2d = TRUE, dims_min = 2, dims_max = 2)
      ),

      params = list(
        list(name = "dims", type = "int_range", default = NULL,
             help = "Dims to use from the input space (e.g. 2:30)."),
        list(name = "cell_set", type = "string", default = "all",
             help = "Which cells to project (e.g. 'set:bulkers')."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "Overwrite existing projected coordinates for those cells.")
      ),

      side_effects = list(
        space_2d = list(kind = "space_2d", description = "Writes projected x/y into space_2d for model_space_id.")
      ),
      produces = list()
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
#' Dynamically injects cell_set choices based on bundle contents.
#'
#' @param op_name Operation name
#' @param bundle Optional scworkbench_bundle (needed for set:* choices)
#' @export
wb_op_interface <- function(op_name, bundle = NULL) {
  op_name <- as.character(op_name)
  reg <- .wb_op_interface_registry()

  if (!op_name %in% names(reg)) {
    stop("Unknown op: ", op_name, call. = FALSE)
  }

  spec <- reg[[op_name]]

  # ensure inputs list exists
  if (is.null(spec$inputs)) spec$inputs <- list()

  # ---- kill legacy umap_transform fields (old spec) ----
  if (identical(op_name, "umap_transform")) {

    # If old input block exists, remove it (we use model_space_id instead)
    spec$inputs$model_space <- NULL

    # If an old param named "model_space" exists, remove it
    if (!is.null(spec$params) && length(spec$params)) {
      keep <- vapply(spec$params, function(p) !identical(p$name, "model_space"), logical(1))
      spec$params <- spec$params[keep]
    }
  }


  # ---- inject / normalize cell_set ----
  if (is.null(spec$inputs$cell_set)) {
    spec$inputs$cell_set <- list()
  }

  # dynamic choices
  sets <- c("core", "all")
  if (!is.null(bundle)) {
    sets <- unique(c(sets, wb_cell_sets(bundle)))
  }

  spec$inputs$cell_set$type     <- "select"
  spec$inputs$cell_set$label    <- "Cell set"
  spec$inputs$cell_set$choices  <- sets

  # default varies by op (sensible semantics)
  if (is.null(spec$inputs$cell_set$default)) {
    spec$inputs$cell_set$default <- switch(
      op_name,
      umap_transform = "set:",
      "core"
    )
  }

  # ---- op-specific dynamic inputs (bundle-aware) ----
  if (!is.null(bundle) && identical(op_name, "umap_transform")) {

    # 1) model_space_id choices: spaces that have a stored model
    model_spaces <- character(0)
    if (.wb_table_exists(bundle$con, "space_models")) {
      model_spaces <- DBI::dbGetQuery(
        bundle$con,
        "SELECT space_id FROM space_models ORDER BY created_at DESC;"
      )$space_id
      model_spaces <- as.character(model_spaces)
    }

    if (is.null(spec$inputs$model_space_id)) spec$inputs$model_space_id <- list()
    spec$inputs$model_space_id$type     <- "select"
    spec$inputs$model_space_id$label    <- "Model space (2D UMAP with stored model)"
    spec$inputs$model_space_id$required <- TRUE
    spec$inputs$model_space_id$choices  <- model_spaces

    if (is.null(spec$inputs$model_space_id$default)) {
      spec$inputs$model_space_id$default <- if (length(model_spaces)) model_spaces[1] else ""
    }
    if (!length(model_spaces) && is.null(spec$inputs$model_space_id$help)) {
      spec$inputs$model_space_id$help <- "No stored space models found in this bundle. Run umap_fit first."
    }

    # 2) in_space_id choices: any space in bundle (high-D input space)
    sp <- wb_spaces(bundle)
    in_spaces <- as.character(sp$space_id)

    if (is.null(spec$inputs$in_space_id)) spec$inputs$in_space_id <- list()
    spec$inputs$in_space_id$type     <- "select"
    spec$inputs$in_space_id$label    <- "Input space (high-D space_id)"
    spec$inputs$in_space_id$required <- FALSE
    spec$inputs$in_space_id$choices  <- in_spaces

    if (is.null(spec$inputs$in_space_id$default)) {
      spec$inputs$in_space_id$default <- if ("lsi" %in% in_spaces) "lsi" else if (length(in_spaces)) in_spaces[1] else ""
    }
  }

  spec
}



.wb_validate_op_interface <- function(spec) {
  .wb_assert(!is.null(spec$op_name) && nzchar(spec$op_name), "spec missing op_name")
  .wb_assert(is.list(spec$inputs), "spec$inputs must be a list")
  .wb_assert(is.list(spec$params), "spec$params must be a list")
  .wb_assert(is.list(spec$produces), "spec$produces must be a list")
  invisible(TRUE)
}
