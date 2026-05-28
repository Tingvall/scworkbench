#' Coerce Input Into A `wb_primitive`
#'
#' Accepts:
#' - wb_primitive → returned as-is
#' - artifact_id (character scalar) → loaded via wb_art_load()
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param x `wb_primitive` or artifact id string.
#' @param expected_kind Optional primitive kind check such as `"cell_vector"`.
#'
#' @return A `wb_primitive`.
#'
#' @export
wb_as_primitive <- function(bundle, x, expected_kind = NULL) {

  # already primitive
  if (.wb_is_primitive(x)) {
    if (!is.null(expected_kind)) .wb_assert_kind(x, expected_kind)
    return(x)
  }

  # allow passing artifact id strings OR direct ids (space_id etc.)
  if (is.character(x) && length(x) == 1 && nzchar(x)) {

    # artifact id conventions
    is_artifact_id <- startsWith(x, "artifact:") ||
      grepl("^[a-z0-9_]+_[0-9]{8}_[0-9]{6}_[a-z0-9]{8}$", x)

    if (is_artifact_id) {
      art_id <- sub("^artifact:", "", x)
      return(wb_art_load(bundle, art_id, expected_kind = expected_kind))
    }

    # direct IDs depending on expected kind
    if (!is.null(expected_kind)) {
      if (identical(expected_kind, "space")) {
        return(wb_prim_space(space_id = x))
      }
      if (identical(expected_kind, "space_2d")) {
        return(wb_prim_space_2d(space_id = x))
      }
      if (identical(expected_kind, "model_ref")) {
        return(wb_prim_model_ref(
          model_space_id = x,
          in_space_id = ""
        ))
      }
    }
  }

  stop("wb_as_primitive(): expected wb_primitive or artifact_id string.", call. = FALSE)
}
