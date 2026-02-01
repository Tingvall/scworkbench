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

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  cell_set <- paste0("set:", set_name)
  cell_ids <- unique(as.character(cell_ids))
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0, "cell_ids empty after cleaning")

  # validate existence
  existing <- wb_cells(bundle, cell_set = "all")
  miss <- setdiff(cell_ids, existing)
  .wb_assert(length(miss) == 0, paste0("Some cell_ids do not exist in bundle. Example: ", miss[[1]]))

  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  DBI::dbWithTransaction(con, {
    if (isTRUE(overwrite)) {
      DBI::dbExecute(con, "DELETE FROM cell_set_membership WHERE cell_set = ?;", params = list(cell_set))
    }

    stmt <- DBI::dbSendStatement(con, "
      INSERT OR IGNORE INTO cell_set_membership(
        cell_set, cell_id, source, created_at, created_by, description
      ) VALUES(?, ?, ?, ?, ?, ?);
    ")
    on.exit(DBI::dbClearResult(stmt), add = TRUE)

    for (cid in cell_ids) {
      DBI::dbBind(stmt, list(cell_set, cid, source, created_at, created_by, description))
    }
  })

  invisible(list(cell_set = cell_set, n = length(cell_ids)))
}

#' Add existing cells to a set (membership-based)
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
  DBI::dbWithTransaction(con, {
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
  })

  invisible(list(cell_set = cell_set, n_added = length(existing)))
}

#' Remove cells from a set
#' If cell_ids is NULL, removes ALL membership for that set.
#' @export
wb_cell_set_remove <- function(bundle, cell_set, cell_ids = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")
  if (!startsWith(cell_set, "set:")) cell_set <- paste0("set:", cell_set)

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  if (is.null(cell_ids)) {
    DBI::dbExecute(con, "DELETE FROM cell_set_membership WHERE cell_set = ?;",
                   params = list(cell_set))
    return(invisible(list(cell_set = cell_set, n_removed = NA_integer_)))
  }

  cell_ids <- unique(as.character(cell_ids))
  js <- jsonlite::toJSON(as.list(cell_ids), auto_unbox = TRUE)

  DBI::dbExecute(
    con,
    "DELETE FROM cell_set_membership
     WHERE cell_set = ?
       AND cell_id IN (SELECT value FROM json_each(?));",
    params = list(cell_set, js)
  )

  invisible(list(cell_set = cell_set, n_removed = length(cell_ids)))
}

#' Overwrite membership for a set (replace with exactly cell_ids)
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

  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "DELETE FROM cell_set_membership WHERE cell_set = ?;",
                   params = list(cell_set))
    wb_cell_set_add(bundle, cell_set = cell_set, cell_ids = cell_ids,
                    source = source, created_by = created_by, description = description)
  })

  invisible(list(cell_set = cell_set, n = length(unique(cell_ids))))
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

  DBI::dbWithTransaction(con, {
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
  })

  invisible(list(
    cell_set = cell_set,
    n_requested = length(cell_ids),
    n_written = length(existing),
    n_missing = length(missing),
    missing_head = head(missing, 20)
  ))
}

