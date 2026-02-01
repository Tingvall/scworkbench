# R/db_helpers.R  (internal helpers)

.wb_db_has_table <- function(con, table_name) {
  .wb_assert(!missing(con), "con is required")
  .wb_assert(is.character(table_name) && length(table_name) == 1 && nzchar(table_name),
             "table_name must be a single non-empty string")

  q <- "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
  res <- DBI::dbGetQuery(con, q, params = list(table_name))
  nrow(res) == 1
}

.wb_db_has_column <- function(con, table_name, column_name) {
  .wb_assert(!missing(con), "con is required")
  .wb_assert(is.character(table_name) && length(table_name) == 1 && nzchar(table_name),
             "table_name must be a single non-empty string")
  .wb_assert(is.character(column_name) && length(column_name) == 1 && nzchar(column_name),
             "column_name must be a single non-empty string")

  if (!.wb_db_has_table(con, table_name)) return(FALSE)

  cols <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s);", DBI::dbQuoteIdentifier(con, table_name)))$name
  column_name %in% as.character(cols)
}
