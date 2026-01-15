# Internal op registry (v1)
# Declares which outputs of each op are saveable and how they should be promoted.

.wb_op_registry <- function() {
  list(

    leiden = list(
      saveable_outputs = list(
        labels = list(
          artifact_type = "labels",
          promoter = ".wb_promote_labels"
        )
      )
    ),

    slingshot = list(
      saveable_outputs = list(
        trajectory = list(
          artifact_type = "trajectory",
          promoter = ".wb_promote_trajectory_2d",
          # hard dependency: needs labels
          depends_on = "labels"
        )
      )
    )

  )
}

.wb_op_spec <- function(op_name) {
  reg <- .wb_op_registry()
  if (!op_name %in% names(reg)) {
    stop("Unknown op in registry: ", op_name, call. = FALSE)
  }
  reg[[op_name]]
}


#' List ops with titles/intents
#' @export
wb_ops <- function() {
  ops <- wb_list_ops()
  rows <- lapply(ops, function(op) {
    spec <- wb_op_interface(op)
    data.frame(
      op_name = spec$op_name %||% op,
      title = spec$title %||% "",
      intent = paste(spec$intent %||% character(0), collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

