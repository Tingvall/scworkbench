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

  lifecycle <- wb_entity_lifecycle(bundle, entity_kind = "model", entity_id = space_id)
  df$lifecycle_state <- as.character(lifecycle$lifecycle_state[1] %||% "current")
  df$provenance_bound <- as.integer(lifecycle$provenance_bound[1] %||% 0L)

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


  .wb_bundle_path_require(bundle, rel, expected_type = "either", must_exist = TRUE,
                          purpose = paste0("space model ", space_id))
}

#' Load a fitted space model
#'
#' @param bundle scworkbench bundle
#' @param space_id space_id of a fitted 2D space
#' @param allow_untrusted_deserialization Explicitly authorize loading a
#'   contained serialized model that is not provenance-bound. Never authorizes
#'   an absolute, traversing, or symlink-escaping path.
#' @param trusted_runtime Whether the caller is an engine-controlled trusted
#'   execution runtime.
#' @return model object (uwot model)
#' @export
wb_load_space_model <- function(bundle, space_id,
                                allow_untrusted_deserialization = FALSE,
                                trusted_runtime = FALSE) {
  row <- wb_space_model(bundle, space_id)
  path <- wb_space_model_path(bundle, space_id)
  trust <- .wb_model_deserialization_status(
    bundle, as.character(row$model_path[1]),
    provenance_bound = identical(as.integer(row$provenance_bound[1] %||% 0L), 1L),
    trusted_runtime = trusted_runtime
  )
  .wb_assert(
    isTRUE(trust$deserialization_allowed) || isTRUE(allow_untrusted_deserialization),
    "MODEL_DESERIALIZATION_TRUST_REQUIRED: loading serialized model state requires trusted provenance/runtime or allow_untrusted_deserialization=TRUE."
  )

  model_type <- row$model_type %||% "uwot_umap"

  if (model_type == "uwot_umap") {
    .wb_require_pkg("uwot", "UMAP transform")
    return(uwot::load_uwot(path))
  }

  stop("Unknown model_type: ", model_type, call. = FALSE)
}

#' List Space IDs That Have a Stored Model
#'
#' @param bundle An open scworkbench bundle.
#' @param model_type Optional model type filter.
#' @param include_history Include ephemeral, superseded, rejected, and retracted models.
#' @return Character vector of space identifiers.
#' @export
wb_spaces_with_model <- function(bundle, model_type = NULL, include_history = FALSE) {
  con <- bundle$con
  .wb_assert(DBI::dbExistsTable(con, "space_models"),
             "space_models table not found in bundle. Have you run umap_fit?")

  if (!isTRUE(bundle$read_only)) .wb_entity_lifecycle_migrate(bundle)
  where <- character(0)
  params <- list()
  if (!is.null(model_type)) {
    where <- c(where, "sm.model_type = ?")
    params <- c(params, list(as.character(model_type)[1]))
  }
  if (!isTRUE(include_history) && .wb_table_exists(con, "entity_lifecycle")) {
    where <- c(where, "NOT EXISTS (SELECT 1 FROM entity_lifecycle el WHERE el.entity_kind = 'model' AND el.entity_id = sm.space_id AND el.lifecycle_state <> 'current')")
  }
  q <- paste0(
    "SELECT sm.space_id FROM space_models sm",
    if (length(where)) paste0(" WHERE ", paste(where, collapse = " AND ")) else "",
    " ORDER BY sm.created_at DESC;"
  )
  out <- if (length(params)) DBI::dbGetQuery(con, q, params = params)$space_id else DBI::dbGetQuery(con, q)$space_id

  as.character(out)
}
