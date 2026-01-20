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
