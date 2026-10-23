.listing_fixture <- function(text = "{}") {
  b <- wb_init_bundle(tempfile("listing_fixture_")); con <- b$con
  for (id in c("a", "z", "hidden")) DBI::dbExecute(con,
    "INSERT INTO artifacts(artifact_id,type,name,created_at,provenance_json) VALUES(?,?,'same','2026-10-24',?)",
    params = list(id, if (id == "z") "obs_table" else "feature_table", text))
  DBI::dbExecute(con, "INSERT INTO entity_lifecycle(entity_kind,entity_id,lifecycle_state,provenance_bound,created_at,updated_at) VALUES('artifact','hidden','retracted',1,'2026-10-24','2026-10-24')")
  b
}

test_artifact_listing_projection_filters_and_history_contract <- function() {
  b <- .listing_fixture(paste0('{"notes":"', strrep("x", 1024^2), '"}'))
  on.exit({wb_close_bundle(b);unlink(b$dir,recursive=TRUE)}, add = TRUE)
  queries <- character(); ns <- asNamespace("DBI"); old <- get("dbGetQuery", ns)
  unlockBinding("dbGetQuery", ns)
  assign("dbGetQuery", function(conn, statement, ...) {
    queries <<- c(queries, as.character(statement)); old(conn, statement, ...)
  }, ns); lockBinding("dbGetQuery", ns)
  on.exit({unlockBinding("dbGetQuery", ns);assign("dbGetQuery", old, ns);lockBinding("dbGetQuery", ns)}, add = TRUE)
  light <- wb_art_list(b)
  sql <- tail(queries, 1L)
  stopifnot(!grepl("provenance_json|a\\.\\*|json_extract", sql),
    !"provenance_json" %in% names(light), identical(light$artifact_id, c("z", "a")),
    all(light$lifecycle_state == "current"), all(light$provenance_bound == 0L))
  full <- wb_art_list(b, include_provenance = TRUE)
  stopifnot(identical(light, full[, setdiff(names(full), "provenance_json")]),
    identical(wb_art_list(b, type = "feature_table")$artifact_id, "a"))
  history <- wb_art_list(b, include_history = TRUE)
  stopifnot(identical(history$artifact_id, c("z", "hidden", "a")),
    history$lifecycle_state[2] == "retracted", history$provenance_bound[2] == 1L)
  DBI::dbExecute(b$con, "DROP TABLE entity_lifecycle")
  stopifnot(nrow(wb_art_list(b)) == 3L, all(wb_art_list(b)$lifecycle_state == "current"))
  TRUE
}

test_artifact_listing_public_load_dag_and_purity_contract <- function() {
  root <- tempfile("listing_public_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE);unlink(root, recursive = TRUE)}, add = TRUE)
  table <- data.frame(feature_id = c("a", "b"), value = c(.0499545077, NA_real_))
  prim <- wb_prim_feature_table(table)
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim))
  p <- wb_promote_analysis(b, setNames(list(run), run$run_id),run$run_id,outputs="vector")
  id <- p$promoted$artifact_id[[1L]]
  s <- wb_session_add_run(wb_session_new(), run)
  dag <- wb_session_dag(s, bundle = b, include_artifacts = TRUE)
  stopifnot(any(dag$edges$edge_type == "promoted_to_artifact"),
    id %in% wb_session_dag_run_details(s, run$run_id, bundle = b)$promoted_artifacts$artifact_id)
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- wb_open_bundle(root, read_only = TRUE)
  fingerprint <- function() {
    paths <- sort(list.files(root, full.names=TRUE, recursive=TRUE, all.files=TRUE, no..=TRUE))
    paths <- paths[!file.info(paths)$isdir]
    vapply(paths, function(path) digest::digest(file=path,algo="sha256"), "")
  }
  before <- fingerprint()
  retained <- wb_art_list(b, include_provenance = TRUE)$provenance_json
  light <- wb_art_list(b)
  stopifnot(!"provenance_json" %in% names(light), identical(wb_art_load(b,id)$table,table),
    identical(wb_art_table_slice(b,id),table), identical(before,fingerprint()),
    identical(retained,wb_art_list(b,include_provenance=TRUE)$provenance_json))
  TRUE
}
