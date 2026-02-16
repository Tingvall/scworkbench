#' Convert a wb_primitive into a normalized data.frame
#'
#' This is a client/view wrangler: it preserves primitive-native engine contracts,
#' while projecting outputs to stable tabular shapes for display/export.
#'
#' @param prim wb_primitive
#' @param key Optional key for `cell_vector_family` projection
#' @param include_context If TRUE, append context columns (`kind`, `table_type`, `entity_kind`)
#' @export
wb_primitive_to_table <- function(prim, key = NULL, include_context = TRUE) {
  .wb_assert(.wb_is_primitive(prim), "prim must be a wb_primitive")
  k <- as.character(prim$kind %||% "")

  df <- switch(
    k,
    feature_table = {
      .wb_assert(is.data.frame(prim$table), "feature_table primitive must contain data.frame 'table'")
      x <- prim$table
      .wb_assert("feature_id" %in% names(x), "feature_table requires 'feature_id' column")
      .wb_table_reorder_cols(x, priority = c("feature_id"))
    },
    obs_table = {
      .wb_assert(is.data.frame(prim$table), "obs_table primitive must contain data.frame 'table'")
      x <- prim$table
      pri <- intersect(c("entity_id", "sample_id", "cluster_id", "pathway_id"), names(x))
      .wb_table_reorder_cols(x, priority = pri)
    },
    cell_vector = {
      data.frame(
        cell_id = as.character(prim$cell_id),
        value = if (identical(prim$value_type %||% "", "continuous")) as.numeric(prim$value) else as.character(prim$value),
        value_type = as.character(prim$value_type %||% "categorical"),
        stringsAsFactors = FALSE
      )
    },
    cell_vector_family = {
      x <- data.frame(
        key = as.character(prim$key),
        cell_id = as.character(prim$cell_id),
        value = as.numeric(prim$value),
        value_type = as.character(prim$value_type %||% "continuous"),
        stringsAsFactors = FALSE
      )
      if (!is.null(key)) {
        kk <- as.character(key)[1]
        x <- x[x$key == kk, , drop = FALSE]
      }
      .wb_table_reorder_cols(x, priority = c("key", "cell_id"))
    },
    space_2d = {
      if (is.data.frame(prim$df)) {
        x <- prim$df
        .wb_assert(all(c("cell_id", "x", "y") %in% names(x)),
                   "space_2d primitive df must contain columns: cell_id, x, y")
        .wb_table_reorder_cols(x, priority = c("cell_id", "x", "y"))
      } else {
        data.frame(
          space_id = as.character(prim$space_id %||% NA_character_),
          stringsAsFactors = FALSE
        )
      }
    },
    stop("wb_primitive_to_table(): unsupported kind for table projection: ", k, call. = FALSE)
  )

  rownames(df) <- NULL
  if (isTRUE(include_context)) {
    df$kind <- k
    if (k %in% c("feature_table", "obs_table")) {
      df$table_type <- as.character(prim$table_type %||% "generic")
    }
    if (k == "obs_table") {
      df$entity_kind <- as.character(prim$entity_kind %||% "generic")
    }
  }

  df
}

#' Client Facade: Load and wrangle reference into normalized table
#'
#' @param bundle scworkbench bundle handle
#' @param ref Primitive-like reference accepted by `wb_client_load()`
#' @param session Optional wb_session for run refs
#' @param runs Optional runs list
#' @param expected_kind Optional primitive kind assertion before wrangling
#' @param key Optional key for `cell_vector_family`
#' @param include_context If TRUE, append context columns (`kind`, `table_type`, `entity_kind`)
#' @export
wb_client_load_table <- function(bundle,
                                 ref,
                                 session = NULL,
                                 runs = NULL,
                                 expected_kind = NULL,
                                 key = NULL,
                                 include_context = TRUE) {
  prim <- wb_client_load(
    bundle = bundle,
    ref = ref,
    session = session,
    runs = runs,
    expected_kind = expected_kind
  )
  wb_primitive_to_table(prim, key = key, include_context = include_context)
}

.wb_table_reorder_cols <- function(df, priority = character(0)) {
  .wb_assert(is.data.frame(df), "df must be data.frame")
  nm <- names(df)
  pri <- intersect(priority, nm)
  rest <- setdiff(nm, pri)
  df[, c(pri, rest), drop = FALSE]
}

