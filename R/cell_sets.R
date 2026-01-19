#' List available cell sets in a bundle
#' @export
wb_cell_sets <- function(bundle) {
  con <- bundle$con

  sets <- DBI::dbGetQuery(con, "SELECT DISTINCT cell_set FROM cells ORDER BY cell_set;")$cell_set
  sets <- as.character(sets)

  # ensure core first
  if ("core" %in% sets) {
    sets <- c("core", setdiff(sets, "core"))
  }
  sets
}

#' Resolve a cell_set selector to cell_ids
#' @export
wb_resolve_cell_set <- function(bundle, cell_set = "core") {

  con <- bundle$con
  cell_set <- as.character(cell_set)

  if (identical(cell_set, "all")) {
    return(DBI::dbGetQuery(con, "SELECT cell_id FROM cells ORDER BY cell_id;")$cell_id)
  }

  avail <- wb_cell_sets(bundle)
  .wb_assert(cell_set %in% avail,
             paste0(
               "Unknown cell_set: ", cell_set, "\n",
               "Available: ", paste(avail, collapse = ", "), "\n",
               "Use 'all' for all cells."
             )
  )

  DBI::dbGetQuery(
    con,
    "SELECT cell_id FROM cells WHERE cell_set = ? ORDER BY cell_id;",
    params = list(cell_set)
  )$cell_id
}
