# Internal op registry (v1)
# Declares which outputs of each op are saveable and how they should be promoted.

# ---- Op registry: define REQUIRED input TYPES and PRODUCED output TYPES ----
.wb_session_op_registry <- function() {
  list(
    leiden    = list(requires = c("space"),    produces = c("clusters")),
    slingshot = list(requires = c("space_2d", "clusters"), produces = c("trajectory")),


    meanexpr = list(
      requires  = c("matrix", "features"),
      produces  = c("cell_vector") # or "cell_vector" if you treat scores as numeric vector primitive
    ),

    umap_fit = list(
      requires  = c("space"),
      produces  = c("space_2d")   # optional but useful for provenance
    ),

    umap_transform = list(
      requires  = c("in_space", "model_space"),
      produces  = c("space_2d")   # optional but useful for provenance
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

