#' List matrices available in the bundle
#' @export
wb_matrices <- function(bundle) {
  man <- bundle$manifest
  mats <- man$storage$matrices %||% list()

  if (length(mats) == 0) {
    return(data.frame(
      matrix_id = character(0),
      assay = character(0),
      feature_type = character(0),
      storage = character(0),
      stringsAsFactors = FALSE
    ))
  }

  df <- do.call(rbind, lapply(mats, function(m) {
    data.frame(
      matrix_id = m$matrix_id %||% NA_character_,
      assay = m$assay %||% NA_character_,
      feature_type = m$feature_type %||% NA_character_,
      storage = m$path %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }))
  df
}
