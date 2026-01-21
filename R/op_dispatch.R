# R/op_dispatch.R

# Each runner is responsible for calling wb_op_<op_name> with the right arguments.
.wb_op_dispatch_registry <- function() {

  # Helper: capture ... safely as list
  .dots <- function(...) {
    as.list(match.call(expand.dots = TRUE)$`...`)
  }

  # Helper: remove keys that could collide with explicit args we pass
  .drop_keys <- function(x, keys) {
    for (k in keys) x[[k]] <- NULL
    x
  }

  list(

    leiden = function(bundle,
                      space_id,
                      ...,
                      inputs,
                      effective_cells = NULL,
                      matrix_id = NULL,
                      labels_df = NULL) {

      dots <- .drop_keys(.dots(...), c("bundle","space_id","cells","cell_set"))
      do.call(
        wb_op_leiden,
        c(
          list(
            bundle = bundle,
            space_id = space_id,
            cells = effective_cells
          ),
          dots
        )
      )
    },

    umap_fit = function(bundle,
                        space_id,
                        ...,
                        inputs,
                        effective_cells = NULL,
                        matrix_id = NULL,
                        labels_df = NULL) {

      source_space_id <- inputs[["space_id"]] %||% space_id
      .wb_assert(!is.null(source_space_id) && nzchar(source_space_id),
                 "umap_fit requires an input space_id (set active space or pass inputs[['space_id']]).")

      dots <- .drop_keys(.dots(...),
                         c("bundle","source_space_id","space_id","cells","dims","space_id_out",
                           "n_neighbors","min_dist","nn_method","seed"))

      do.call(
        wb_op_umap_fit,
        c(
          list(
            bundle = bundle,
            source_space_id = source_space_id,
            cells = effective_cells,
            dims = inputs[["dims"]] %||% NULL,
            space_id_out = inputs[["space_id_out"]] %||% paste0("umap.", source_space_id),
            n_neighbors = inputs[["n_neighbors"]] %||% 30,
            min_dist = inputs[["min_dist"]] %||% 0.3,
            nn_method = inputs[["nn_method"]] %||% "nndescent",
            seed = inputs[["seed"]] %||% NULL
          ),
          dots
        )
      )
    },

    umap_transform = function(bundle,
                              space_id = NULL,
                              ...,
                              inputs,
                              effective_cells = NULL,
                              matrix_id = NULL,
                              labels_df = NULL) {

      # Allow in_space_id to come from inputs or fallback to active/space_id slot
      in_space_id    <- inputs$in_space_id %||% space_id
      model_space_id <- inputs$model_space_id

      .wb_assert(!is.null(in_space_id) && nzchar(in_space_id),
                 "umap_transform requires inputs$in_space_id (or inputs$space_id/active space).")
      .wb_assert(!is.null(model_space_id) && nzchar(model_space_id),
                 "umap_transform requires inputs$model_space_id.")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "umap_transform: effective_cells is empty (coverage filtering removed all cells).")

      dots <- .drop_keys(.dots(...),
                         c("bundle","model_space_id","in_space_id","cells","dims","overwrite"))

      do.call(
        wb_op_umap_transform,
        c(
          list(
            bundle = bundle,
            model_space_id = model_space_id,
            in_space_id = in_space_id,
            cells = effective_cells,
            dims = inputs$dims %||% NULL,
            overwrite = inputs$overwrite %||% TRUE
          ),
          dots
        )
      )
    },

    slingshot = function(bundle,
                         space_id,
                         ...,
                         inputs,
                         effective_cells = NULL,
                         matrix_id = NULL,
                         labels_df = NULL) {

      dots <- .drop_keys(.dots(...), c("bundle","space_id","labels","labels_df","cells","cell_set"))
      do.call(
        wb_op_slingshot,
        c(
          list(
            bundle = bundle,
            space_id = space_id,
            labels = labels_df,
            cells = effective_cells
          ),
          dots
        )
      )
    },

    meanexpr = function(bundle,
                        space_id = NULL,
                        matrix_id,
                        ...,
                        inputs,
                        effective_cells = NULL,
                        labels_df = NULL) {

      .wb_assert(!is.null(matrix_id) && nzchar(matrix_id),
                 "meanexpr requires a matrix_id (set active matrix or pass inputs[['matrix_id']]).")
      .wb_assert(!is.null(inputs$features) && length(inputs$features) > 0,
                 "meanexpr requires inputs$features (character vector).")

      dots <- .drop_keys(.dots(...), c("bundle","matrix_id","features","cells","cell_set"))

      do.call(
        wb_op_meanexpr,
        c(
          list(
            bundle = bundle,
            matrix_id = matrix_id,
            features = inputs$features,
            cells = effective_cells
          ),
          dots
        )
      )
    }

  )
}


.wb_get_op_runner <- function(op_name) {
  reg <- .wb_op_dispatch_registry()
  if (!op_name %in% names(reg)) {
    stop("No runner registered for op: ", op_name, call. = FALSE)
  }
  reg[[op_name]]
}
