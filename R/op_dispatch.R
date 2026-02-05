# R/op_dispatch.R  (NEW CANONICAL OP REGISTRY + RUNNERS)
# Replace your old .wb_op_dispatch_registry() completely.
# Session should call ops via: op <- .wb_ops()[[op_name]] ; op$runner(...)


# ---- Canonical op registry ----
# Each op entry:
# - requires: named list input_name -> primitive kind
# - produces: named list output_name -> primitive kind
# - promotable: which outputs can be persisted
# - runner: MUST return list(outputs=<named list of primitives>, params=<list>)
.wb_ops <- function() {
  list(
    leiden = list(
      requires   = list(space = "space"),
      produces   = list(clusters = "cell_vector"),
      runner     = .wb_get_op_runner("leiden"),
      promotable = c("clusters")
    ),
    slingshot = list(
      requires   = list(space_2d = "space_2d", clusters = "cell_vector"),
      produces   = list(pseudotime = "cell_vector_family", curves = "path_2d_family"),
      runner     = .wb_get_op_runner("slingshot"),
      promotable = c("pseudotime","curves")
    ),
    umap_fit = list(
      requires   = list(space = "space"),
      produces   = list(space_2d = "space_2d", model = "model_ref"),
      runner     = .wb_get_op_runner("umap_fit"),
      promotable = c("space_2d","model")
    ),
    umap_transform = list(
      requires   = list(in_space = "space", model = "model_ref"),
      produces   = list(space_2d = "space_2d"),
      runner     = .wb_get_op_runner("umap_transform"),
      promotable = c("space_2d")
    )
  )
}



.wb_op_dispatch_registry <- function() {

  # pass-through dots (excluding keys we explicitly manage)
  .dots <- function(...) as.list(match.call(expand.dots = TRUE)$`...`)
  .drop_keys <- function(x, keys) { for (k in keys) x[[k]] <- NULL; x }

  list(

    # ---- LEIDEN ----
    leiden = function(bundle, resolved, effective_cells, inputs = list(), ...) {
      .wb_assert(!is.null(resolved$space), "leiden runner: missing resolved$space (space primitive).")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "leiden runner: effective_cells is empty.")

      space_id <- resolved$space$space_id

      dots <- .drop_keys(.dots(...), c("bundle","resolved","effective_cells","inputs"))

      raw <- do.call(
        wb_op_leiden,
        c(list(
          bundle   = bundle,
          space_id = space_id,
          cells    = as.character(effective_cells)
        ), dots)
      )

      # raw op may already return normalized {outputs, params}
      if (!is.null(raw$outputs) && is.list(raw$outputs)) return(raw)

      # otherwise normalize legacy return (labels df -> primitive)
      .wb_assert(!is.null(raw$labels), "leiden op must return labels (legacy) or outputs (new).")
      labs <- raw$labels
      .wb_assert(is.data.frame(labs) && all(c("cell_id","cluster") %in% names(labs)),
                 "leiden legacy labels must be data.frame(cell_id, cluster).")

      cl <- as.character(labs$cluster); names(cl) <- as.character(labs$cell_id)

      list(
        outputs = list(
          clusters = wb_prim_cell_vector(cl, value_type = "categorical")
        ),
        params = raw$params %||% list()
      )
    },

    # ---- SLINGSHOT ----
    slingshot = function(bundle, resolved, effective_cells, inputs = list(), ...) {
      .wb_assert(!is.null(resolved$space_2d),  "slingshot runner: missing resolved$space_2d.")
      .wb_assert(!is.null(resolved$clusters),  "slingshot runner: missing resolved$clusters.")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "slingshot runner: effective_cells is empty.")

      space_id <- resolved$space_2d$space_id

      # clusters primitive -> named vector
      clp <- resolved$clusters
      clusters_vec <- as.character(clp$value)
      names(clusters_vec) <- as.character(clp$cell_id)

      dots <- .drop_keys(.dots(...), c("bundle","resolved","effective_cells","inputs"))

      raw <- do.call(
        wb_op_slingshot,
        c(list(
          bundle   = bundle,
          space_id = space_id,
          clusters = clusters_vec,
          cells    = as.character(effective_cells)
        ), dots)
      )

      # slingshot op should already return normalized {outputs, params}
      .wb_assert(is.list(raw) && is.list(raw$outputs),
                 "slingshot must return list(outputs=<list>, params=<list>).")
      raw
    },

    # ---- UMAP FIT ----
    umap_fit = function(bundle, resolved, effective_cells, inputs = list(), ...) {
      .wb_assert(!is.null(resolved$space), "umap_fit runner: missing resolved$space.")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "umap_fit runner: effective_cells is empty.")

      source_space_id <- resolved$space$space_id

      # params are allowed to come from inputs
      dims         <- inputs$dims %||% NULL
      space_id_out <- inputs$space_id_out %||% paste0("umap.", source_space_id)
      n_neighbors  <- inputs$n_neighbors %||% 30
      min_dist     <- inputs$min_dist %||% 0.3
      metric       <- inputs$metric %||% "euclidean"
      nn_method    <- inputs$nn_method %||% "nndescent"
      spread       <- inputs$spread %||% 1.0
      seed         <- inputs$seed %||% 1

      dots <- .drop_keys(.dots(...), c("bundle","resolved","effective_cells","inputs"))

      raw <- do.call(
        wb_op_umap_fit,
        c(list(
          bundle          = bundle,
          source_space_id = source_space_id,
          cells           = as.character(effective_cells),
          dims            = dims,
          space_id_out    = space_id_out,
          n_neighbors     = n_neighbors,
          min_dist        = min_dist,
          metric          = metric,
          nn_method       = nn_method,
          spread          = spread,
          seed            = seed
        ), dots)
      )

      # If your wb_op_umap_fit already returns normalized outputs, keep it.
      if (!is.null(raw$outputs) && is.list(raw$outputs)) return(raw)

      # Otherwise normalize: it writes to bundle; outputs are references
      list(
        outputs = list(
          space_2d = wb_prim_space_2d(space_id_out),
          # model_ref primitive not shown in your list; keep as a placeholder primitive if you have one
          model   = structure(list(kind="model_ref", space_id=space_id_out), class="wb_primitive")
        ),
        params = raw$params %||% list()
      )
    },

    # ---- UMAP TRANSFORM ----
    umap_transform = function(bundle, resolved, effective_cells, inputs = list(), ...) {
      .wb_assert(!is.null(resolved$in_space), "umap_transform runner: missing resolved$in_space.")
      .wb_assert(!is.null(resolved$model),    "umap_transform runner: missing resolved$model.")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "umap_transform runner: effective_cells is empty.")

      in_space_id <- resolved$in_space$space_id

      # model_ref: you likely store space_id in it
      model_space_id <- resolved$model$space_id %||% resolved$model$model_space_id
      .wb_assert(!is.null(model_space_id) && nzchar(model_space_id),
                 "umap_transform runner: model_ref must contain $space_id (the fitted umap space).")

      dims      <- inputs$dims %||% NULL
      overwrite <- inputs$overwrite %||% TRUE

      dots <- .drop_keys(.dots(...), c("bundle","resolved","effective_cells","inputs"))

      raw <- do.call(
        wb_op_umap_transform,
        c(list(
          bundle         = bundle,
          model_space_id = model_space_id,
          in_space_id    = in_space_id,
          cells          = as.character(effective_cells),
          dims           = dims,
          overwrite      = overwrite
        ), dots)
      )

      if (!is.null(raw$outputs) && is.list(raw$outputs)) return(raw)

      list(
        outputs = list(
          space_2d = wb_prim_space_2d(model_space_id)
        ),
        params = raw$params %||% list()
      )
    }
  )
}

.wb_get_op_runner <- function(op_name) {
  reg <- .wb_op_dispatch_registry()
  if (!op_name %in% names(reg)) stop("No runner registered for op: ", op_name, call. = FALSE)
  reg[[op_name]]
}


# Convenience
.wb_get_op <- function(op_name) {
  ops <- .wb_ops()
  .wb_assert(op_name %in% names(ops), paste0("Unknown op: ", op_name))
  ops[[op_name]]
}
