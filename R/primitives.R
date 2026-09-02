.wb_is_primitive <- function(x) {
  inherits(x, "wb_primitive") && is.list(x) && !is.null(x$kind)
}

.wb_assert_kind <- function(x, expected_kind, where = "") {
  .wb_assert(.wb_is_primitive(x), paste0("Expected primitive object", where, "."))
  .wb_assert(identical(as.character(x$kind), as.character(expected_kind)),
             paste0("Expected kind '", expected_kind, "'", where, ", got '", x$kind, "'."))
  invisible(TRUE)
}

#' Create a `cell_vector_family` Primitive
#'
#' Construct a long-form cell-by-key numeric primitive. Typical uses include
#' pseudotime, lineage weights, and per-cell signature families.
#'
#' @param key Family-member key for each row.
#' @param cell_id Canonical cell id for each row.
#' @param value Numeric value for each row.
#' @param value_type Semantic value type, usually `"continuous"`.
#' @param meta Optional named list of identity-bearing contract metadata. Its
#'   exact R representation is restored after durable promotion.
#'
#' @return A `wb_primitive` of kind `cell_vector_family`.
#' @export
wb_prim_cell_vector_family <- function(key, cell_id, value, value_type = "continuous", meta = list()) {
  if (is.null(meta)) meta <- list()

  structure(
    list(
      kind = "cell_vector_family",
      key = as.character(key),
      cell_id = as.character(cell_id),
      value = as.numeric(value),
      value_type = as.character(value_type),
      meta = meta
    ),
    class = "wb_primitive"
  )
}

#' Create a `relation_family` Primitive
#'
#' Sparse long-form relation family (edge-table-like shape).
#' Optional row-wise fields (`weight`, `value`, `distance`) must match the row count when provided.
#'
#' @param key Relation-family key for each row.
#' @param cell_id Canonical cell id for each row.
#' @param weight Optional numeric relation weight.
#' @param value Optional numeric relation value.
#' @param distance Optional numeric relation distance.
#' @param meta Optional named list of identity-bearing contract metadata. Its
#'   exact R representation is restored after durable promotion.
#'
#' @return A `wb_primitive` of kind `relation_family`.
#' @export
wb_prim_relation_family <- function(key, cell_id, weight = NULL, value = NULL, distance = NULL, meta = list()) {
  n <- length(key)
  .wb_assert(length(cell_id) == n, "relation_family: key/cell_id length mismatch")
  if (!is.null(weight)) .wb_assert(length(weight) == n, "relation_family: key/weight length mismatch")
  if (!is.null(value)) .wb_assert(length(value) == n, "relation_family: key/value length mismatch")
  if (!is.null(distance)) .wb_assert(length(distance) == n, "relation_family: key/distance length mismatch")
  if (is.null(meta)) meta <- list()

  structure(
    list(
      kind = "relation_family",
      key = as.character(key),
      cell_id = as.character(cell_id),
      weight = if (is.null(weight)) NULL else as.numeric(weight),
      value = if (is.null(value)) NULL else as.numeric(value),
      distance = if (is.null(distance)) NULL else as.numeric(distance),
      meta = meta
    ),
    class = "wb_primitive"
  )
}

#' Create a `space` Primitive
#'
#' @param space_id Registered space identifier.
#'
#' @return A `wb_primitive` of kind `space`.
#' @export
wb_prim_space  <- function(space_id)  structure(list(kind="space",  space_id=as.character(space_id)),  class="wb_primitive")
#' Create a `matrix` Primitive
#'
#' @param matrix_id Registered logical matrix identifier.
#'
#' @return A `wb_primitive` of kind `matrix`.
#' @export
wb_prim_matrix <- function(matrix_id) structure(list(kind="matrix", matrix_id=as.character(matrix_id)), class="wb_primitive")
#' Create a `space_2d` Primitive
#'
#' @param space_id Registered two-dimensional space identifier.
#'
#' @return A `wb_primitive` of kind `space_2d`.
#' @export
wb_prim_space_2d <- function(space_id) {
  structure(
    list(kind = "space_2d", space_id = as.character(space_id)),
    class = "wb_primitive"
  )
}


#' Create a `cell_vector` Primitive
#'
#' @param x Named atomic vector. Names must be canonical cell ids.
#' @param value_type Semantic value type, such as `"categorical"` or
#'   `"continuous"`.
#' @param meta Optional named list of identity-bearing metadata. Its exact R
#'   representation is restored after durable promotion.
#'
#' @return A `wb_primitive` of kind `cell_vector`.
#' @export
wb_prim_cell_vector <- function(x, value_type = "categorical", meta = list()) {
  stopifnot(is.atomic(x), !is.null(names(x)))
  .wb_assert(is.null(meta) || is.list(meta),
             "cell_vector meta must be NULL or a named list.")
  payload <- list(
    kind = "cell_vector",
    cell_id = as.character(names(x)),
    value = as.character(x),
    value_type = as.character(value_type)
  )
  # Preserve the historical no-metadata object shape and identity. A non-empty
  # metadata contract is explicit, durable, and identity-bearing.
  if (length(meta)) payload$meta <- meta
  structure(payload, class = "wb_primitive")
}

#' Create a `path_2d_family` Primitive
#'
#' @param key Path-family key for each point, often a lineage or segment id.
#' @param point Integer point index along each path.
#' @param x,y Numeric display coordinates for each path point.
#' @param meta Optional named list of identity-bearing display and provenance
#'   metadata. Its exact R representation is restored after durable promotion.
#'
#' @return A `wb_primitive` of kind `path_2d_family`.
#' @export
wb_prim_path_2d_family <- function(key, point, x, y, meta = list()) {
  if (is.null(meta)) meta <- list()
  structure(
    list(
      kind  = "path_2d_family",
      key   = as.character(key),       # lineage_id
      point = as.integer(point),       # point index along curve
      x     = as.numeric(x),
      y     = as.numeric(y),
      meta  = meta
    ),
    class = "wb_primitive"
  )
}

#' Create a `space_path_family` Primitive
#'
#' @param space_id Registered space identifier for each path point.
#' @param path_id Path identifier for each point.
#' @param point Integer point index along each path.
#' @param dim Coordinate dimension for each value.
#' @param value Numeric coordinate value.
#' @param meta Optional named list of identity-bearing contract metadata. Its
#'   exact R representation is restored after durable promotion.
#'
#' @return A `wb_primitive` of kind `space_path_family`.
#' @export
wb_prim_space_path_family <- function(space_id, path_id, point, dim, value, meta = list()) {
  n <- length(path_id)
  .wb_assert(length(space_id) == n, "space_path_family: space_id/path_id length mismatch")
  .wb_assert(length(point) == n, "space_path_family: path_id/point length mismatch")
  .wb_assert(length(dim) == n, "space_path_family: path_id/dim length mismatch")
  .wb_assert(length(value) == n, "space_path_family: path_id/value length mismatch")
  if (is.null(meta)) meta <- list()

  structure(
    list(
      kind = "space_path_family",
      space_id = as.character(space_id),
      path_id = as.character(path_id),
      point = as.integer(point),
      dim = as.integer(dim),
      value = as.numeric(value),
      meta = meta
    ),
    class = "wb_primitive"
  )
}


#' Create a `model_ref` Primitive
#'
#' @param model_space_id Identifier of the space containing model coordinates.
#' @param in_space_id Identifier of the model input space.
#' @param engine Model engine name.
#' @param artifact_id Optional promoted model artifact id.
#'
#' @return A `wb_primitive` of kind `model_ref`.
#' @export
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

#' Create A `feature_table` Primitive
#'
#' Wrap a data frame as a canonical `feature_table` primitive. Use
#' `table_type` and `meta` to specialize the table contract while keeping the
#' primitive kind stable.
#'
#' @param table Data frame payload.
#' @param table_type Specialization label for downstream contracts, for example
#'   `"trajectory_de"` or `"markers"`.
#' @param meta Optional named list of additional contract metadata.
#'
#' @return A `wb_primitive` of kind `feature_table`.
#'
#' @export
wb_prim_feature_table <- function(table, table_type = "generic", meta = list()) {
  .wb_assert(is.data.frame(table), "table must be a data.frame")
  if (is.null(meta)) meta <- list()
  structure(
    list(
      kind = "feature_table",
      table_type = as.character(table_type)[1],
      table = table,
      meta = meta
    ),
    class = "wb_primitive"
  )
}

#' Create An `obs_table` Primitive
#'
#' Wrap a data frame as a canonical `obs_table` primitive. Use `table_type`,
#' `entity_kind`, and `meta` to describe specialized observation-style tables
#' without inventing new primitive kinds.
#'
#' @param table Data frame payload.
#' @param table_type Specialization label for downstream contracts, for example
#'   `"trajectory_smooth"` or `"trajectory_signature_smooth"`.
#' @param entity_kind Observation entity label used by downstream consumers.
#' @param meta Optional named list of additional contract metadata.
#'
#' @return A `wb_primitive` of kind `obs_table`.
#'
#' @export
wb_prim_obs_table <- function(table, table_type = "generic", entity_kind = "generic", meta = list()) {
  .wb_assert(is.data.frame(table), "table must be a data.frame")
  if (is.null(meta)) meta <- list()
  structure(
    list(
      kind = "obs_table",
      table_type = as.character(table_type)[1],
      entity_kind = as.character(entity_kind)[1],
      table = table,
      meta = meta
    ),
    class = "wb_primitive"
  )
}
