# R/preprocess.R

# internal: safe scalar token for provenance
.wb_cell_set_token <- function(cells, label = "cells") {
  # simple + stable enough for now; later replace with digest::digest()
  paste0(label, ":", length(cells))
}

#' Resolve cells after universal include/exclude filters
#' @keywords internal
.wb_resolve_cells <- function(bundle,
                              cells = NULL,
                              exclude_cells = NULL,
                              include_datasets = NULL,
                              exclude_datasets = NULL) {

  all_cells <- wb_cells(bundle)
  if (is.null(cells)) cells <- all_cells
  cells <- as.character(cells)

  if (!is.null(exclude_cells) && length(exclude_cells) > 0) {
    cells <- setdiff(cells, as.character(exclude_cells))
  }

  # dataset filters (uses cells table column dataset_id)
  if (!is.null(include_datasets) || !is.null(exclude_datasets)) {
    con <- bundle$con
    # map cell -> dataset_id
    df <- DBI::dbGetQuery(
      con,
      "SELECT cell_id, dataset_id FROM cells WHERE cell_id IN (SELECT value FROM json_each(?));",
      params = list(jsonlite::toJSON(as.list(cells), auto_unbox = TRUE))
    )
    # fallback if json_each is unavailable in your sqlite build:
    # (then do chunked IN queries; but try json_each first)

    keep <- rep(TRUE, length(cells))
    names(keep) <- cells
    ds_map <- setNames(df$dataset_id, df$cell_id)

    if (!is.null(include_datasets)) {
      inc <- as.character(include_datasets)
      keep <- keep & (ds_map[names(keep)] %in% inc)
    }
    if (!is.null(exclude_datasets)) {
      exc <- as.character(exclude_datasets)
      keep <- keep & !(ds_map[names(keep)] %in% exc)
    }
    cells <- names(keep)[keep]
  }

  list(
    cells = cells,
    cell_set = .wb_cell_set_token(cells)
  )
}

#' Filter labels by include/exclude clusters and return aligned labels + cells
#' labels_df must be data.frame(cell_id, cluster)
#' @keywords internal
.wb_filter_labels <- function(labels_df,
                              cells,
                              include_clusters = NULL,
                              exclude_clusters = NULL) {

  stopifnot(is.data.frame(labels_df))
  stopifnot(all(c("cell_id", "cluster") %in% colnames(labels_df)))

  labels_df$cell_id <- as.character(labels_df$cell_id)
  labels_df$cluster <- as.character(labels_df$cluster)

  lab <- labels_df[match(cells, labels_df$cell_id), , drop = FALSE]
  if (anyNA(lab$cell_id)) stop("Some cells missing from labels.", call. = FALSE)

  cl <- lab$cluster

  if (!is.null(include_clusters) && length(include_clusters) > 0) {
    inc <- as.character(include_clusters)
    keep <- cl %in% inc
    lab <- lab[keep, , drop = FALSE]
    cells <- cells[keep]
    cl <- cl[keep]
  }

  if (!is.null(exclude_clusters) && length(exclude_clusters) > 0) {
    exc <- as.character(exclude_clusters)
    keep <- !(cl %in% exc)
    lab <- lab[keep, , drop = FALSE]
    cells <- cells[keep]
  }

  list(
    cells = cells,
    labels = lab
  )
}
