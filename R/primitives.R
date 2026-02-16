.wb_is_primitive <- function(x) {
  inherits(x, "wb_primitive") && is.list(x) && !is.null(x$kind)
}

.wb_assert_kind <- function(x, expected_kind, where = "") {
  .wb_assert(.wb_is_primitive(x), paste0("Expected primitive object", where, "."))
  .wb_assert(identical(as.character(x$kind), as.character(expected_kind)),
             paste0("Expected kind '", expected_kind, "'", where, ", got '", x$kind, "'."))
  invisible(TRUE)
}

wb_prim_cell_vector_family <- function(key, cell_id, value, value_type = "continuous") {

  structure(
    list(
      kind = "cell_vector_family",
      key = as.character(key),
      cell_id = as.character(cell_id),
      value = as.numeric(value),
      value_type = as.character(value_type)
    ),
    class = "wb_primitive"
  )
}

wb_prim_space  <- function(space_id)  structure(list(kind="space",  space_id=as.character(space_id)),  class="wb_primitive")
wb_prim_matrix <- function(matrix_id) structure(list(kind="matrix", matrix_id=as.character(matrix_id)), class="wb_primitive")
wb_prim_space_2d <- function(space_id) {
  structure(
    list(kind = "space_2d", space_id = as.character(space_id)),
    class = "wb_primitive"
  )
}


wb_prim_cell_vector <- function(x, value_type = "categorical") {
  stopifnot(is.atomic(x), !is.null(names(x)))
  structure(
    list(
      kind = "cell_vector",
      cell_id = names(x),
      value = as.character(x),
      value_type = value_type
    ),
    class = "wb_primitive"
  )
}

wb_prim_path_2d_family <- function(key, point, x, y) {
  structure(
    list(
      kind  = "path_2d_family",
      key   = as.character(key),       # lineage_id
      point = as.integer(point),       # point index along curve
      x     = as.numeric(x),
      y     = as.numeric(y)
    ),
    class = "wb_primitive"
  )
}


wb_prim_model_ref <- function(model_space_id, in_space_id, engine = "uwot", artifact_id = NULL) {
  structure(
    list(
      kind = "model_ref",
      engine = engine,
      model_space_id = as.character(model_space_id),
      in_space_id    = as.character(in_space_id),
      artifact_id    = artifact_id
    ),
    class = "wb_primitive"
  )
}
