# R/getters_space_models.R

#' Get model metadata for a space
#'
#' @param bundle scworkbench bundle
#' @param space_id space_id of a fitted 2D space
#' @return one-row data.frame from space_models
#' @export
wb_space_model <- function(bundle, space_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle")

  con <- bundle$con

  .wb_assert(.wb_table_exists(con, "space_models"),
             "space_models table does not exist in this bundle")

  df <- DBI::dbGetQuery(
    con,
    "SELECT * FROM space_models WHERE space_id = ?;",
    params = list(space_id)
  )

  .wb_assert(
    nrow(df) == 1,
    paste0("No model registered for space_id: ", space_id)
  )

  df
}

#' Get absolute path to the model file for a space
#'
#' @param bundle scworkbench bundle
#' @param space_id space_id of a fitted 2D space
#' @return absolute file path
#' @export
wb_space_model_path <- function(bundle, space_id) {
  row <- wb_space_model(bundle, space_id)

  rel <- row$model_path
  .wb_assert(is.character(rel) && length(rel) == 1 && nzchar(rel),
             paste0("Invalid model_path stored for space_id: ", space_id))


  abs <- file.path(bundle$dir, rel)

  .wb_assert(
    file.exists(abs),
    paste0("Model file does not exist on disk: ", abs)
  )

  abs
}

#' Load a fitted space model
#'
#' @param bundle scworkbench bundle
#' @param space_id space_id of a fitted 2D space
#' @return model object (uwot model)
#' @export
wb_load_space_model <- function(bundle, space_id) {
  row <- wb_space_model(bundle, space_id)
  path <- wb_space_model_path(bundle, space_id)

  model_type <- row$model_type %||% "uwot_umap"

  if (model_type == "uwot_umap") {
    .wb_require_pkg("uwot", "UMAP transform")
    return(uwot::load_uwot(path))
  }

  stop("Unknown model_type: ", model_type, call. = FALSE)
}

#' List space_ids that have a stored model
#' @export
wb_spaces_with_model <- function(bundle, model_type = NULL) {
  con <- bundle$con
  .wb_assert(DBI::dbExistsTable(con, "space_models"),
             "space_models table not found in bundle. Have you run umap_fit?")

  if (is.null(model_type)) {
    q <- "SELECT space_id FROM space_models ORDER BY created_at DESC;"
    out <- DBI::dbGetQuery(con, q)$space_id
  } else {
    q <- "SELECT space_id FROM space_models WHERE model_type = ? ORDER BY created_at DESC;"
    out <- DBI::dbGetQuery(con, q, params = list(as.character(model_type)))$space_id
  }

  as.character(out)
}


