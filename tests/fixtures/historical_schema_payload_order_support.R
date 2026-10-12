# Test fixtures that lower the migration ledger must remove version-11 columns.
# Preserve every historical payload column, constraint and row; production
# migrations retain their exact historical-layout guard.
fixture_restore_pre_graph_payload_layout <- function(con) {
  # artifacts_schema.R historically supports both string-only labels and the
  # additive typed-scalar value_type/value_num form. Preserve whichever exists.
  labels <- as.character(DBI::dbGetQuery(con, "PRAGMA table_info(artifact_labels);")$name)
  labels <- labels[labels != "payload_ordinal"]
  stopifnot(identical(labels, c("artifact_id", "cell_id", "label")) ||
    identical(labels, c("artifact_id", "cell_id", "label", "value_type", "value_num")))
  layouts <- list(artifact_labels = labels,
    artifact_pseudotime = c("artifact_id", "cell_id", "lineage_id", "pseudotime"))
  for (table in names(layouts)) {
    before <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", table, ");"))
    foreign <- DBI::dbGetQuery(con, paste0("PRAGMA foreign_key_list(", table, ");"))
    rows <- DBI::dbGetQuery(con, paste0("SELECT ", paste(layouts[[table]], collapse = ","),
      " FROM ", table, " ORDER BY rowid;"))
    if ("payload_ordinal" %in% before$name) {
      DBI::dbExecute(con, paste0("DROP INDEX IF EXISTS ", table, "_payload_order;"))
      DBI::dbExecute(con, paste0("ALTER TABLE ", table, " DROP COLUMN payload_ordinal;"))
    }
    after <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", table, ");"))
    stopifnot(identical(as.character(after$name), layouts[[table]]),
      identical(before[before$name != "payload_ordinal", c("name", "type", "notnull", "dflt_value", "pk")],
        after[, c("name", "type", "notnull", "dflt_value", "pk")]),
      identical(foreign, DBI::dbGetQuery(con, paste0("PRAGMA foreign_key_list(", table, ");"))),
      identical(rows, DBI::dbGetQuery(con, paste0("SELECT ", paste(layouts[[table]], collapse = ","),
        " FROM ", table, " ORDER BY rowid;"))))
  }
  invisible(TRUE)
}
