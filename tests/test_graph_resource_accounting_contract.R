test_graph_resource_stage_and_journal_rollback_contract <- function() {
  ns <- asNamespace("scworkbench")
  paths <- character()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "connected") paths <<- c(paths, state$path)
  })
  on.exit(options(old), add = TRUE)
  bad <- tryCatch(scworkbench:::.wb_graph_stage_new("mixed", list(storage_bytes = "1")), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_EXCEEDED", !any(file.exists(paths)))
  bad <- tryCatch(scworkbench:::.wb_graph_budgets(list(memory_bytes = "1")), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_POLICY_INVALID")
  stage <- scworkbench:::.wb_graph_stage_new("mixed", list(wal_bytes = "1"))
  on.exit(scworkbench:::.wb_graph_stage_discard(stage), add = TRUE)
  bad <- tryCatch(scworkbench:::.wb_graph_append(stage, "nodes", list(list(node_id = "n1"))), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_EXCEEDED",
    !RSQLite::sqliteIsTransacting(stage$con),
    DBI::dbGetQuery(stage$con, "SELECT COUNT(*) n FROM artifact_graph_rows;")$n == 0L,
    stage$counts[["nodes"]] == "0")
  stage$budgets$wal_bytes <- "1048576"
  scworkbench:::.wb_graph_append(stage, "nodes", list(list(node_id = "n1")))
  stopifnot(stage$counts[["nodes"]] == "1")
  scworkbench:::.wb_graph_stage_discard(stage)
  stopifnot(!any(file.exists(paths)))
  TRUE
}

test_graph_resource_unlinked_sqlite_spill_contract <- function() {
  if (!dir.exists("/proc/self/fd")) return(contract_test_skip("SQLite transient spill accounting requires Linux procfs"))
  path <- tempfile("graph_sort_accounting_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  cursor <- NULL
  on.exit({if (!is.null(cursor)) try(DBI::dbClearResult(cursor), silent = TRUE)
    DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "PRAGMA temp_store=FILE;")
  DBI::dbExecute(con, "PRAGMA cache_size=-16;")
  DBI::dbExecute(con, "CREATE TABLE sample(value TEXT);")
  DBI::dbExecute(con, paste0("WITH RECURSIVE source(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM source WHERE n<4096) ",
    "INSERT INTO sample SELECT hex(randomblob(8192)) FROM source;"))
  cursor <- DBI::dbSendQuery(con, "SELECT value FROM sample ORDER BY value DESC;")
  stopifnot(nrow(DBI::dbFetch(cursor, n = 1L)) == 1L)
  usage <- scworkbench:::.wb_graph_transient_usage(path)
  stopifnot(usage$temporary_accounting == "procfs_open_descriptors", usage$temporary_bytes > 1048576)
  budgets <- scworkbench:::.wb_graph_budgets(list(token_bytes = "1048576"))
  bad <- tryCatch(scworkbench:::.wb_graph_transient_admit(budgets, path), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_EXCEEDED")
  # Each source-metadata chunk and the unrelated live SQLite sorter fit alone,
  # but their combined open scratch bytes must reject and remove only our sink.
  metadata_path <- tempfile("graph_metadata_accounting_", fileext = ".sqlite")
  metadata_con <- DBI::dbConnect(RSQLite::SQLite(), metadata_path)
  on.exit({DBI::dbDisconnect(metadata_con); unlink(metadata_path)}, add = TRUE)
  DBI::dbExecute(metadata_con, paste0("CREATE TABLE artifact_object_metadata_chunks(",
    "artifact_id TEXT,chunk_ordinal INTEGER,chunk BLOB);"))
  DBI::dbExecute(metadata_con, "INSERT INTO artifact_object_metadata_chunks VALUES('source',0,?);",
    params = list(list(as.raw(rep(65L, 65536L)))))
  budgets$token_bytes <- format(usage$temporary_bytes + 32768, scientific = FALSE, trim = TRUE)
  before_scratch <- list.files(tempdir(), pattern = "^scwb_object_meta_", full.names = TRUE)
  bad <- tryCatch(scworkbench:::.wb_graph_object_metadata_hash(metadata_con, "source", budgets), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_EXCEEDED",
    identical(list.files(tempdir(), pattern = "^scwb_object_meta_", full.names = TRUE), before_scratch),
    scworkbench:::.wb_graph_transient_usage(path)$temporary_bytes == usage$temporary_bytes)
  DBI::dbClearResult(cursor); cursor <- NULL
  stopifnot(scworkbench:::.wb_graph_transient_usage(path)$temporary_bytes == 0)
  stopifnot(scworkbench:::.wb_graph_object_metadata_hash(metadata_con, "source", budgets)$bytes == "65536")
  TRUE
}

test_graph_resource_publication_budget_rollback_contract <- function() {
  root <- tempfile("graph_budget_publication_")
  bundle <- wb_init_bundle(root)
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list())
  stage <- scworkbench:::.wb_graph_stage_small(graph)
  attr(graph, "graph_stage") <- stage
  on.exit({scworkbench:::.wb_graph_stage_discard(stage); wb_close_bundle(bundle);
    unlink(root, recursive = TRUE)}, add = TRUE)
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(), outputs = list(result = graph))
  counts <- function() vapply(c("artifacts", "artifact_graph_meta", "artifact_graph_rows",
    "prov_commits", "prov_runs", "prov_run_outputs", "prov_run_entity_bindings"), function(table)
    as.numeric(DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) n FROM ", table))$n[[1L]]), numeric(1))
  before <- counts()
  stage$budgets$published_bytes <- "1"
  bad <- tryCatch(DBI::dbWithTransaction(bundle$con,
    scworkbench:::.wb_promote_graph(bundle, run, "result", graph)), error = identity)
  stopifnot(inherits(bad, "wb_graph_error"), bad$code == "GRAPH_RESOURCE_EXCEEDED", identical(counts(), before))
  stage$budgets$published_bytes <- "1048576"
  id <- DBI::dbWithTransaction(bundle$con,
    scworkbench:::.wb_promote_graph(bundle, run, "result", graph))
  stopifnot(length(id) == 1L, counts()[["artifacts"]] == 1L)
  TRUE
}

test_graph_resource_padded_mapping_cursor_contract <- function() {
  id <- function(scheme) list(scheme = scheme, sha256 = paste(rep("1", 64L), collapse = ""))
  binding <- list(binding_id = "view", axis_kind = "cell",
    source_ref = list(kind = "retained_cell_axis", source_id = "synthetic"),
    source_snapshot_identity = id("scworkbench.provenance.snapshot_head.v1"),
    axis_content_identity = id("scworkbench.graph.source-axis-content.canonical-json.v1"),
    axis_order_identity = id("scworkbench.cell_order.v1"),
    mapping = list(list(node_id = "n2", axis_id = "c2"), list(node_id = "n1", axis_id = "c1")))
  graph <- wb_prim_graph(list(list(node_id = "n2"), list(node_id = "n1")), list(), list(),
    associations = list(binding))
  stage <- scworkbench:::.wb_graph_stage_small(graph, list(partition_bytes = 2048))
  on.exit(scworkbench:::.wb_graph_stage_discard(stage), add = TRUE)
  rows <- DBI::dbGetQuery(stage$con,
    "SELECT row_ordinal,record_json FROM artifact_graph_rows WHERE component='binding_mappings';")
  for (i in seq_len(nrow(rows))) DBI::dbExecute(stage$con,
    "UPDATE artifact_graph_rows SET record_json=? WHERE component='binding_mappings' AND row_ordinal=?;",
    params = list(paste0(rows$record_json[[i]], paste(rep(" ", 1800L), collapse = "")), rows$row_ordinal[[i]]))
  batches <- 0L
  old <- options(scworkbench.graph_storage_test_hook = function(event, evidence) {
    if (event == "binding_mapping_batch") {
      stopifnot(evidence$rows == 1L, evidence$encoded_bytes <= 2048)
      batches <<- batches + 1L
    }
  })
  on.exit(options(old), add = TRUE)
  stopifnot(identical(scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets)$descriptor_identity,
    wb_graph_identity(graph)$descriptor_identity), batches == 2L)
  TRUE
}
