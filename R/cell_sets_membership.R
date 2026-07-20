# R/cell_sets_membership.R

.wb_ensure_cell_set_membership_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_membership (
      cell_set    TEXT NOT NULL,
      cell_id     TEXT NOT NULL,
      source      TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT,
      PRIMARY KEY(cell_set, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_set  ON cell_set_membership(cell_set);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_cell ON cell_set_membership(cell_id);")
  invisible(TRUE)
}
#' Create A Membership-Based Cell Set
#'
#' Create or overwrite a simple membership-backed cell set from explicit cell
#' ids.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param set_name Set name without the `set:` prefix.
#' @param cell_ids Cell ids to include.
#' @param overwrite If `TRUE`, replace any existing membership first.
#' @param source Optional provenance/source label.
#' @param created_by Optional author.
#' @param description Optional description.
#'
#' @return Invisibly returns a small summary list describing the created set.
#'
#' @export
wb_set_create <- function(bundle,
                          set_name,
                          cell_ids,
                          overwrite = TRUE,
                          source = "analysis",
                          created_by = NULL,
                          description = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(set_name) && nzchar(set_name), "set_name invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")

  cell_set <- paste0("set:", set_name)
  cell_ids <- unique(as.character(cell_ids))
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0, "cell_ids empty after cleaning")
  res <- if (isTRUE(overwrite)) {
    wb_cell_set_replace(
      bundle, cell_set = cell_set, cell_ids = cell_ids, source = source,
      created_by = created_by, description = description, strict = TRUE
    )
  } else {
    wb_cell_set_add(
      bundle, cell_set = cell_set, cell_ids = cell_ids, source = source,
      created_by = created_by, description = description
    )
  }

  invisible(list(
    cell_set = cell_set,
    n = as.integer(res$n_written %||% res$n_added %||% length(cell_ids))
  ))
}

#' Add Existing Cells to a Cell Set
#'
#' Adds membership rows without removing current members. For recipe-aware,
#' lifecycle-bearing sets, prefer [wb_cell_set_define()] or
#' [wb_cell_set_derive()].
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_set Target set name, with or without the `"set:"` prefix.
#' @param cell_ids Non-empty character vector of canonical cell ids.
#' @param source Provenance/source label stored with membership rows.
#' @param created_by Optional actor label.
#' @param description Optional membership description.
#'
#' @return Invisibly returns the normalized set name and number of added cells.
#' @export
wb_cell_set_add <- function(bundle,
                            cell_set,
                            cell_ids,
                            source = "manual",
                            created_by = NULL,
                            description = NULL) {

  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids must be non-empty")

  if (!startsWith(cell_set, "set:")) cell_set <- paste0("set:", cell_set)
  cell_ids <- unique(as.character(cell_ids))

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  # validate existence
  cl <- .wb_sql_in_json(cell_ids)
  existing <- DBI::dbGetQuery(
    con,
    paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"),
    params = cl$params
  )$cell_id
  missing <- setdiff(cell_ids, existing)
  .wb_assert(length(existing) > 0, "None of the provided cell_ids exist in this bundle.")
  if (length(missing) > 0) {
    stop("Some cell_ids do not exist in this bundle. First few: ",
         paste(head(missing, 10), collapse = ", "),
         call. = FALSE)
  }

  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  df <- data.frame(
    cell_set    = rep(cell_set, length(existing)),
    cell_id     = existing,
    source      = rep(source, length(existing)),
    created_at  = rep(created_at, length(existing)),
    created_by  = rep(created_by %||% NA_character_, length(existing)),
    description = rep(description %||% NA_character_, length(existing)),
    stringsAsFactors = FALSE
  )

  # insert, ignore duplicates via PK(cell_set, cell_id)
  write_add <- function() {
    stmt <- DBI::dbSendStatement(
      con,
      "INSERT OR IGNORE INTO cell_set_membership
       (cell_set, cell_id, source, created_at, created_by, description)
       VALUES(?, ?, ?, ?, ?, ?);"
    )
    on.exit(DBI::dbClearResult(stmt), add = TRUE)

    for (i in seq_len(nrow(df))) {
      DBI::dbBind(stmt, params = list(
        df$cell_set[i],
        df$cell_id[i],
        df$source[i],
        df$created_at[i],
        df$created_by[i],
        df$description[i]
      ))
    }
  }
  if (isTRUE(getOption("scworkbench.registry_replay_transaction_open"))) write_add() else DBI::dbWithTransaction(con, write_add())

  .wb_journal_registry_mutation(
    bundle, "cell_set", "add",
    key = list(cell_set = cell_set),
    payload = list(
      cell_ids = existing,
      metadata = list(source = source, created_by = created_by, description = description)
    )
  )

  invisible(list(cell_set = cell_set, n_added = length(existing)))
}

#' Remove Cells From a Cell Set
#'
#' If `cell_ids` is `NULL`, removes all membership rows for the set.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_set Target set name, with or without the `"set:"` prefix.
#' @param cell_ids Optional character vector of member cell ids to remove.
#'
#' @return Invisibly returns the normalized set name, aliases considered, and
#'   removal count when available.
#' @export
wb_cell_set_remove <- function(bundle, cell_set, cell_ids = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")
  cell_set <- as.character(cell_set)[1]
  aliases <- unique(c(
    cell_set,
    if (startsWith(cell_set, "set:")) sub("^set:", "", cell_set) else paste0("set:", cell_set)
  ))
  aliases <- aliases[nzchar(aliases)]

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  if (is.null(cell_ids)) {
    q <- .wb_sql_in_json(aliases)
    DBI::dbExecute(
      con,
      paste0("DELETE FROM cell_set_membership WHERE cell_set IN ", q$sql, ";"),
      params = q$params
    )
    .wb_journal_registry_mutation(
      bundle, "cell_set", "remove",
      key = list(cell_set = cell_set),
      payload = list(cell_ids = NULL)
    )
    return(invisible(list(cell_set = cell_set, aliases = aliases, n_removed = NA_integer_)))
  }

  cell_ids <- unique(as.character(cell_ids))
  js <- jsonlite::toJSON(as.list(cell_ids), auto_unbox = TRUE)
  q <- .wb_sql_in_json(aliases)

  DBI::dbExecute(
    con,
    paste0(
      "DELETE FROM cell_set_membership
       WHERE cell_set IN ", q$sql, "
         AND cell_id IN (SELECT value FROM json_each(?));"
    ),
    params = c(q$params, list(js))
  )

  .wb_journal_registry_mutation(
    bundle, "cell_set", "remove",
    key = list(cell_set = cell_set),
    payload = list(cell_ids = cell_ids)
  )

  invisible(list(cell_set = cell_set, aliases = aliases, n_removed = length(cell_ids)))
}

#' Set Cell Set Membership
#'
#' Replace membership with exactly `cell_ids`. Unlike [wb_cell_set_derive()],
#' this low-level helper does not persist a selector recipe or lifecycle
#' manifest.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_set Target set name, with or without the `"set:"` prefix.
#' @param cell_ids Non-empty character vector of canonical cell ids.
#' @param source Provenance/source label stored with membership rows.
#' @param created_by Optional actor label.
#' @param description Optional membership description.
#'
#' @return Invisibly returns the normalized set name and member count.
#' @export
wb_cell_set_set <- function(bundle,
                            cell_set,
                            cell_ids,
                            source = "manual",
                            created_by = NULL,
                            description = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids must be non-empty")
  if (!startsWith(cell_set, "set:")) cell_set <- paste0("set:", cell_set)

  res <- wb_cell_set_replace(
    bundle = bundle,
    cell_set = cell_set,
    cell_ids = cell_ids,
    source = source,
    created_by = created_by,
    description = description,
    strict = TRUE
  )

  invisible(list(cell_set = cell_set, n = as.integer(res$n_written)))
}

#' Replace membership of a set (set becomes exactly these cells)
#'
#' - Clears existing membership for cell_set
#' - Inserts membership rows for provided cell_ids (must exist in bundle)
#'
#' @param bundle scworkbench_bundle
#' @param cell_set "set:<name>" or "<name>"
#' @param cell_ids character vector (can be empty -> set becomes empty)
#' @param source provenance
#' @param created_by optional
#' @param description optional
#' @param strict if TRUE, error if any cell_ids are missing from bundle
#'
#' @return Invisibly returns the normalized set name, inserted cell ids, and
#'   any ignored missing ids when `strict = FALSE`.
#' @export
wb_cell_set_replace <- function(bundle,
                                cell_set,
                                cell_ids,
                                source = "manual",
                                created_by = NULL,
                                description = NULL,
                                strict = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")
  if (!startsWith(cell_set, "set:")) cell_set <- paste0("set:", cell_set)

  .wb_assert(is.character(cell_ids), "cell_ids must be character (can be empty)")
  cell_ids <- unique(as.character(cell_ids))

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  # Validate existence (but allow empty)
  existing <- character(0)
  missing <- character(0)
  if (length(cell_ids) > 0) {
    cl <- .wb_sql_in_json(cell_ids)
    existing <- DBI::dbGetQuery(
      con,
      paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"),
      params = cl$params
    )$cell_id
    existing <- as.character(existing)
    missing <- setdiff(cell_ids, existing)

    if (isTRUE(strict) && length(missing) > 0) {
      stop("Some cell_ids do not exist in this bundle. First few: ",
           paste(head(missing, 10), collapse = ", "),
           call. = FALSE)
    }
  }

  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  write_replace <- function() {
    # 1) clear set
    DBI::dbExecute(con, "DELETE FROM cell_set_membership WHERE cell_set = ?;",
                   params = list(cell_set))

    # 2) insert new membership
    if (length(existing) > 0) {
      stmt <- DBI::dbSendStatement(
        con,
        "INSERT OR IGNORE INTO cell_set_membership
         (cell_set, cell_id, source, created_at, created_by, description)
         VALUES(?, ?, ?, ?, ?, ?);"
      )
      on.exit(DBI::dbClearResult(stmt), add = TRUE)

      for (cid in existing) {
        DBI::dbBind(stmt, params = list(
          cell_set,
          cid,
          source,
          created_at,
          created_by %||% NA_character_,
          description %||% NA_character_
        ))
      }
    }
  }
  if (isTRUE(getOption("scworkbench.registry_replay_transaction_open"))) write_replace() else DBI::dbWithTransaction(con, write_replace())

  .wb_journal_registry_mutation(
    bundle, "cell_set", "replace",
    key = list(cell_set = cell_set),
    payload = list(
      cell_ids = existing,
      metadata = list(source = source, created_by = created_by, description = description)
    )
  )

  invisible(list(
    cell_set = cell_set,
    n_requested = length(cell_ids),
    n_written = length(existing),
    n_missing = length(missing),
    missing_head = head(missing, 20)
  ))
}
