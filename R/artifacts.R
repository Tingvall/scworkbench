wb_art_list <- function(bundle, type = NULL) {
  con <- bundle$con
  if (is.null(type)) {
    DBI::dbGetQuery(con, "SELECT * FROM artifacts ORDER BY created_at DESC;")
  } else {
    DBI::dbGetQuery(con, "SELECT * FROM artifacts WHERE type = ? ORDER BY created_at DESC;", params = list(type))
  }
}

wb_art_get_labels <- function(bundle, artifact_id) {
  con <- bundle$con
  DBI::dbGetQuery(con, "SELECT cell_id, label FROM artifact_labels WHERE artifact_id = ? ORDER BY cell_id;", params = list(artifact_id))
}

