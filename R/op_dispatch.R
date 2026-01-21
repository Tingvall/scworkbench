# R/op_dispatch.R

# Each runner is responsible for calling wb_op_<op_name> with the right arguments.
.wb_op_dispatch_registry <- function() {
  list(
    leiden = function(bundle,
                      space_id,
                      matrix_id = NULL,
                      labels_df = NULL,
                      effective_cells,
                      inputs,
                      ...) {
      wb_op_leiden(
        bundle = bundle,
        space_id = space_id,
        cells = effective_cells,
        ...
      )
    },
    umap_fit = function(bundle, space_id, ..., inputs, matrix_id = NULL, labels_df = NULL, effective_cells = NULL) {

      source_space_id <- inputs[["space_id"]] %||% space_id
      .wb_assert(!is.null(source_space_id) && nzchar(source_space_id),
                 "umap_fit requires an input space_id (set active space or pass inputs[['space_id']]).")

      wb_op_umap_fit(
        bundle = bundle,
        source_space_id = source_space_id,
        cells = effective_cells,
        dims = inputs[["dims"]] %||% NULL,
        space_id_out = inputs[["space_id_out"]] %||% paste0("umap.", source_space_id),
        n_neighbors = inputs[["n_neighbors"]] %||% 30,
        min_dist = inputs[["min_dist"]] %||% 0.3,
        nn_method = inputs[["nn_method"]] %||% "nndescent",
        seed = inputs[["seed"]] %||% NULL,
        ...
      )
    },
    # inside .wb_op_dispatch_registry()

    umap_transform = function(bundle, space_id = NULL, ..., inputs,
                              matrix_id = NULL, labels_df = NULL, effective_cells = NULL) {

      # in_space_id can come from inputs or fall back to the "space_id" slot
      in_space_id    <- inputs$in_space_id %||% space_id
      model_space_id <- inputs$model_space_id

      .wb_assert(!is.null(in_space_id) && nzchar(in_space_id),
                 "umap_transform requires inputs$in_space_id (or inputs$space_id/active space).")
      .wb_assert(!is.null(model_space_id) && nzchar(model_space_id),
                 "umap_transform requires inputs$model_space_id.")
      .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
                 "umap_transform: effective_cells is empty (coverage filtering removed all cells).")

      # Protect against duplicates sneaking in via ...
      dots <- list(...)
      dots$model_space_id <- NULL
      dots$in_space_id <- NULL
      dots$cells <- NULL
      dots$dims <- NULL
      dots$overwrite <- NULL

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
                         matrix_id = NULL,
                         labels_df = NULL,
                         effective_cells,
                         inputs,
                         ...) {
      wb_op_slingshot(
        bundle = bundle,
        space_id = space_id,
        labels = labels_df,
        cells = effective_cells,
        ...
      )
    },

    meanexpr = function(bundle,
                        space_id = NULL,
                        matrix_id,
                        labels_df = NULL,
                        effective_cells,
                        inputs,
                        ...) {
      wb_op_meanexpr(
        bundle = bundle,
        matrix_id = matrix_id,
        features = inputs$features,
        cells = effective_cells,
        ...
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
