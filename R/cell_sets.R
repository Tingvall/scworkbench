#' List available cell sets in a bundle.
#'
#' Returns membership-backed set names from `cell_set_membership`.
#' The legacy `cells.cell_set` column is not used.
#'
#' @param bundle Open `scworkbench_bundle`.
#'
#' @param include_history Include ephemeral, superseded, rejected, and retracted set names.
#' @return Character vector of membership-backed set names with `"core"`
#'   first when present.
# pybench-parity: yes
# pybench-counterpart: pybench.getters.cell_sets
# contract-note: canonical display ordering puts 'core' first
#' @export
wb_cell_sets <- function(bundle, include_history = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con

  .wb_assert(.wb_db_has_table(con, "cell_set_membership"),
             "cell_set_membership table missing. Bundle schema not initialized.")

  history_filter <- if (.wb_table_exists(con, "entity_lifecycle")) "
       AND (? OR NOT EXISTS (
         SELECT 1 FROM entity_lifecycle el
         WHERE el.entity_kind = 'cell_set'
           AND el.entity_id = cell_set_membership.cell_set
           AND el.lifecycle_state <> 'current'
       ))" else ""
  sets <- DBI::dbGetQuery(
    con, paste0("SELECT DISTINCT cell_set
     FROM cell_set_membership
     WHERE cell_set IS NOT NULL AND cell_set <> ''
     ", history_filter, " ORDER BY cell_set;"),
    params = if (nzchar(history_filter)) list(as.integer(isTRUE(include_history))) else NULL
  )$cell_set
  sets <- as.character(sets)
  sets <- sets[nzchar(sets)]

  # canonical ordering: core first
  if ("core" %in% sets) sets <- c("core", setdiff(sets, "core"))

  sets
}




#' Resolve a cell_set selector to cell_ids
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_set Set name, `"core"`, or `"all"`.
#'
#' @return Character vector of canonical member cell ids in stable bundle
#'   order.
# pybench-parity: yes
# pybench-counterpart: pybench.getters.resolve_cell_set
# contract-note: keep 'all' semantics and stable ordering aligned with wb_cells()/membership path
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
