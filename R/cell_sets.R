#' List available cell sets in a bundle.
#'
#' Returns membership-backed set names from `cell_set_membership`.
#' The legacy `cells.cell_set` column is not used.
#' @export
wb_cell_sets <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con

  .wb_assert(.wb_db_has_table(con, "cell_set_membership"),
             "cell_set_membership table missing. Bundle schema not initialized.")

  sets <- DBI::dbGetQuery(
    con,
    "SELECT DISTINCT cell_set
     FROM cell_set_membership
     WHERE cell_set IS NOT NULL AND cell_set <> ''
     ORDER BY cell_set;"
  )$cell_set
  sets <- as.character(sets)
  sets <- sets[nzchar(sets)]

  # canonical ordering: core first
  if ("core" %in% sets) sets <- c("core", setdiff(sets, "core"))

  sets
}




#' Resolve a cell_set selector to cell_ids
#' @export
wb_resolve_cell_set <- function(bundle, cell_set = "core") {
  con <- bundle$con
  cell_set <- as.character(cell_set)

  if (identical(cell_set, "all")) {
    return(DBI::dbGetQuery(con, "SELECT cell_id FROM cells ORDER BY rowid;")$cell_id)
  }

  avail <- wb_cell_sets(bundle)
  .wb_assert(cell_set %in% avail,
             paste0("Unknown cell_set: ", cell_set, "\nAvailable: ", paste(avail, collapse=", "))
  )

  if (.wb_db_has_table(con, "cell_set_membership")) {
    return(DBI::dbGetQuery(con,
                           "SELECT cell_id FROM cell_set_membership WHERE cell_set=? ORDER BY rowid;",
                           params = list(cell_set)
    )$cell_id)
  }

  DBI::dbGetQuery(con,
                  "SELECT cell_id FROM cells WHERE cell_set=? ORDER BY rowid;",
                  params = list(cell_set)
  )$cell_id
}
