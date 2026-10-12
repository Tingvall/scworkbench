test_graph_resource_owned_spill_alias_and_fd_metadata_admission_contract <- function() {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="1048576",
    sqlite_cache_kib=128L,partition_bytes=1024L,partition_rows=2L,collect_bytes=65536L))
  before <- scworkbench:::.wb_graph_transient_usage(budgets=policy)$owned_spill_bytes
  path <- tempfile("scwb_graph_identity_alias_one_")
  alias <- tempfile("scwb_graph_identity_alias_two_")
  writeBin(raw(4096L),path)
  stopifnot(file.link(path,alias))
  first <- file(path,"rb");second <- file(alias,"rb")
  on.exit({try(close(first),silent=TRUE);try(close(second),silent=TRUE);unlink(c(path,alias))},add=TRUE)
  observed <- scworkbench:::.wb_graph_transient_usage(budgets=policy)
  stopifnot(observed$owned_spill_bytes==before+4096,
    identical(scworkbench:::.wb_graph_file_identity(path),scworkbench:::.wb_graph_file_identity(alias)))
  policy$token_bytes <- as.character(before+4096)
  scworkbench:::.wb_graph_spill_admit(policy,path)
  scworkbench:::.wb_graph_spill_admit(policy,alias)
  close(first)
  scworkbench:::.wb_graph_spill_admit(policy,alias)
  close(second);unlink(c(path,alias))
  scworkbench:::.wb_graph_transient_usage(budgets=policy)
  paths <- vapply(seq_len(60L),function(i)tempfile("fd_metadata_probe_"),character(1))
  handles <- lapply(paths,function(path)file(path,"wb"))
  on.exit({for(handle in handles)try(close(handle),silent=TRUE);unlink(paths)},add=TRUE)
  failed <- tryCatch(scworkbench:::.wb_graph_transient_usage(budgets=policy),error=identity)
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"))
  for(handle in handles)close(handle)
  handles <- list();unlink(paths)
  scworkbench:::.wb_graph_transient_usage(budgets=policy)
  TRUE
}

test_graph_resource_publication_copy_and_temporary_overlap_contract <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(),":memory:")
  on.exit(DBI::dbDisconnect(con),add=TRUE)
  baseline <- scworkbench:::.wb_graph_disk_usage(con)
  policy <- scworkbench:::.wb_graph_budgets(list(token_bytes="4096"))
  attr(policy,"wb_graph_session_copy_bytes") <- 4096
  path <- tempfile("scwb_graph_identity_publication_overlap_")
  sink <- file(path,"wb")
  on.exit({try(close(sink),silent=TRUE);unlink(path)},add=TRUE)
  writeBin(raw(4096L),sink);flush(sink)
  failed <- tryCatch(scworkbench:::.wb_graph_disk_admit(con,policy,baseline),error=identity)
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"))
  policy$token_bytes <- "8192"
  scworkbench:::.wb_graph_disk_admit(con,policy,baseline)
  close(sink);unlink(path)
  policy$token_bytes <- "4096"
  scworkbench:::.wb_graph_disk_admit(con,policy,baseline)
  TRUE
}

test_graph_resource_live_stage_and_selector_spill_overlap_contract <- function() {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",
    partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L,sqlite_cache_kib=2048L))
  stage <- scworkbench:::.wb_graph_stage_new("undirected",policy)
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  DBI::dbExecute(stage$con,"CREATE TABLE admitted_probe(bytes BLOB);")
  DBI::dbExecute(stage$con,"INSERT INTO admitted_probe VALUES(zeroblob(400000));")
  stage_bytes <- scworkbench:::.wb_graph_disk_usage(stage$con)$database_bytes
  copy_bytes <- 131072
  attr(policy,"wb_graph_session_copy_bytes") <- copy_bytes
  policy$token_bytes <- as.character(stage_bytes+copy_bytes+65536)
  scworkbench:::.wb_graph_disk_admit(stage$con,policy)
  path <- tempfile("scwb_graph_identity_overlap_",fileext=".sqlite")
  selector <- DBI::dbConnect(RSQLite::SQLite(),path,cache_size=-64)
  on.exit({if(DBI::dbIsValid(selector))DBI::dbDisconnect(selector);unlink(path)},add=TRUE)
  DBI::dbExecute(selector,"PRAGMA journal_mode=DELETE;")
  DBI::dbExecute(selector,"CREATE TABLE selectors(bytes BLOB);")
  DBI::dbExecute(selector,"INSERT INTO selectors VALUES(zeroblob(131072));")
  selector_bytes <- file.info(path)$size
  actual <- stage_bytes+copy_bytes+selector_bytes
  stopifnot(actual>as.numeric(policy$token_bytes))
  failed <- tryCatch(scworkbench:::.wb_graph_spill_admit(policy,path),error=identity)
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"))
  policy$token_bytes <- as.character(actual)
  scworkbench:::.wb_graph_spill_admit(policy,path)
  scworkbench:::.wb_graph_disk_admit(stage$con,policy)
  scworkbench:::.wb_graph_transient_admit(policy)
  second <- scworkbench:::.wb_graph_stage_new("undirected",scworkbench:::.wb_graph_budgets())
  on.exit(scworkbench:::.wb_graph_stage_discard(second),add=TRUE)
  failed <- tryCatch(scworkbench:::.wb_graph_spill_admit(policy,path),error=identity)
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"))
  scworkbench:::.wb_graph_stage_discard(second)
  scworkbench:::.wb_graph_spill_admit(policy,path)
  DBI::dbDisconnect(selector);unlink(path)
  policy$token_bytes <- as.character(stage_bytes+copy_bytes)
  scworkbench:::.wb_graph_disk_admit(stage$con,policy)
  scworkbench:::.wb_graph_stage_discard(stage)
  policy$token_bytes <- as.character(copy_bytes)
  scworkbench:::.wb_graph_transient_admit(policy)
  TRUE
}

test_graph_resource_owned_session_copy_admission_contract <- function() {
  bundle <- wb_init_bundle(tempfile("graph_session_copy_admission_"))
  session <- wb_session_new()
  on.exit({wb_session_discard(session);root<-bundle$dir;wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  tree <- file.path(bundle$dir,"operation_pack_v2")
  dir.create(tree)
  payload <- file.path(tree,"copy_accounting_probe")
  writeBin(as.raw(seq_len(128L)-1L),payload)
  Sys.chmod(payload,"0600")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",
    partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L,sqlite_cache_kib=2048L))
  baseline <- scworkbench:::.wb_graph_disk_usage(bundle$con)$database_bytes
  bytes <- scworkbench:::.wb_session_graph_copy_bytes(bundle,policy)
  stopifnot(bytes>=baseline+8192)
  too_small <- policy
  too_small$token_bytes <- as.character(bytes-1)
  restore <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con,too_small)
  failed <- tryCatch(scworkbench:::.wb_session_stage_bundle(bundle,session),error=identity)
  restore()
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"),
    is.null(session$staging_bundle),file.exists(payload),identical(readBin(payload,"raw",128L),as.raw(seq_len(128L)-1L)))
  budgets <- policy
  attr(budgets,"wb_graph_session_copy_bytes") <- bytes
  budgets <- scworkbench:::.wb_graph_budgets(budgets)
  stopifnot(identical(scworkbench:::.wb_graph_session_copy_reservation(budgets),bytes))
  scratch <- tempfile("graph_session_copy_spill_")
  on.exit(unlink(scratch),add=TRUE)
  writeBin(raw(4096L),scratch)
  budgets$token_bytes <- as.character(bytes+4095)
  failed <- tryCatch(scworkbench:::.wb_graph_spill_admit(budgets,scratch),error=identity)
  stopifnot(inherits(failed,"error"),identical(failed$code,"GRAPH_RESOURCE_EXCEEDED"))
  budgets$token_bytes <- as.character(bytes+4096)
  scworkbench:::.wb_graph_spill_admit(budgets,scratch)
  restore <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con,policy)
  staged <- scworkbench:::.wb_session_stage_bundle(bundle,session)
  restore()
  session <- staged$session
  copied <- file.path(staged$bundle$dir,"operation_pack_v2","copy_accounting_probe")
  stopifnot(!nzchar(Sys.readlink(copied)),
    identical(readBin(copied,"raw",128L),readBin(payload,"raw",128L)),
    identical(file.info(copied)$mode,file.info(payload)$mode),
    staged$bundle$con@ref$wb_graph_session_copy_bytes>=bytes)
  writeBin(as.raw(255L),copied)
  stopifnot(identical(readBin(payload,"raw",128L),as.raw(seq_len(128L)-1L)))
  for(source in list(NULL,structure(list(),class="scworkbench_bundle"))) {
    reopened <- scworkbench:::.wb_session_stage_open(source,staged$bundle$dir)
    stopifnot(inherits(reopened,"scworkbench_bundle"),DBI::dbIsValid(reopened$con))
    wb_close_bundle(reopened)
  }
  TRUE
}

test_graph_resource_unstaged_direct_transaction_restoration_contract <- function() {
  bundle <- wb_init_bundle(tempfile("graph_owned_direct_"))
  on.exit({root <- bundle$dir; wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  restore <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con, policy)
  on.exit(restore(), add = TRUE)
  before <- list(cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
    policy = bundle$con@ref$wb_graph_policy, cap = bundle$con@ref$wb_graph_cache_kib,
    temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]])
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list())
  run <- wb_new_run("metadata_cell_vector", list(), list(), list(vector = graph))
  paths <- character()
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "configured") paths <<- c(paths, state$path)
  })
  on.exit(options(hook), add = TRUE)
  for (fault in c(TRUE, FALSE)) {
    options(scworkbench.promotion_transaction_test_hook = if (fault)
      function(event, ...) if (event == "graph_component_rows") stop("direct owned-stage fault") else NULL)
    DBI::dbBegin(bundle$con)
    result <- tryCatch(scworkbench:::.wb_promote_graph(bundle, run, "vector", graph), error = identity)
    DBI::dbRollback(bundle$con)
    stopifnot(if (fault) inherits(result, "error") &&
      grepl("direct owned-stage fault", conditionMessage(result), fixed = TRUE) else is.character(result),
      identical(before, list(cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
        policy = bundle$con@ref$wb_graph_policy, cap = bundle$con@ref$wb_graph_cache_kib,
        temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]])),
      !any(file.exists(paths)))
  }
  options(scworkbench.promotion_transaction_test_hook = NULL)
  stopifnot(length(paths) == 2L)
  TRUE
}

test_graph_resource_unstaged_public_promotion_cache_contract <- function() {
  bundle <- wb_init_bundle(tempfile("graph_unstaged_admission_"))
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  on.exit({root <- bundle$dir; wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  initial <- DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]]
  restore <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con, policy)
  on.exit(restore(), add = TRUE)
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list())
  stopifnot(is.null(attr(graph, "graph_stage", exact = TRUE)))
  run <- wb_new_run("metadata_cell_vector", list(), list(), list(vector = graph))
  configured <- 0L; paths <- character()
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "configured") {
      configured <<- configured + 1L; paths <<- c(paths, state$path)
      source <- -DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]]
      stage <- -DBI::dbGetQuery(state$con, "PRAGMA cache_size;")[[1L]][[1L]]
      stopifnot(source + stage + 128L <= policy$sqlite_cache_kib,
        state$budgets$memory_bytes == policy$memory_bytes)
    }
  }, scworkbench.promotion_transaction_test_hook = function(event, ...)
    if (event == "graph_component_rows") stop("owned-stage rollback fixture"))
  on.exit(options(hook), add = TRUE)
  before <- DBI::dbGetQuery(bundle$con, "SELECT COUNT(*) n FROM artifacts;")$n[[1L]]
  failed <- tryCatch(wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector"), error = identity)
  stopifnot(inherits(failed, "error"), grepl("owned-stage rollback", conditionMessage(failed), fixed = TRUE),
    DBI::dbGetQuery(bundle$con, "SELECT COUNT(*) n FROM artifacts;")$n[[1L]] == before,
    !any(file.exists(paths)), DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]] == -2048)
  options(scworkbench.promotion_transaction_test_hook = NULL)
  promoted <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  stopifnot(configured == 2L, !any(file.exists(paths)),
    DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]] == -2048,
    identical(wb_art_graph_info(bundle, promoted$promoted$artifact_id[[1L]], policy)$content_identity,
      wb_graph_identity(graph)$content_identity))
  restore()
  stopifnot(DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]] == initial)
  TRUE
}

test_graph_resource_aggregate_cache_and_nested_policy_contract <- function() {
  bundle <- wb_init_bundle(tempfile("graph_aggregate_budget_"))
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list())
  stages <- lapply(1:2, function(i) scworkbench:::.wb_graph_stage_small(graph, policy))
  connections <- c(list(bundle$con), lapply(stages, function(stage) stage$con))
  on.exit({for (stage in stages) scworkbench:::.wb_graph_stage_discard(stage)
    root <- bundle$dir; wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cache <- function() vapply(connections, function(con)
    DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]], numeric(1))
  before <- cache()
  restore <- scworkbench:::.wb_graph_aggregate_connection_budget(connections, policy)
  on.exit(restore(), add = TRUE)
  admitted <- cache()
  stopifnot(all(admitted < 0), sum(-admitted) * 1024 + 65536 <= 2048 * 1024)
  inner <- scworkbench:::.wb_graph_scoped_connection_budget(bundle$con,
    scworkbench:::.wb_graph_budgets())
  stopifnot(identical(cache(), admitted), identical(
    scworkbench:::.wb_operation_pack_canonical_json(scworkbench:::.wb_graph_effective_budgets(bundle$con)),
    scworkbench:::.wb_operation_pack_canonical_json(policy)))
  inner()
  branches <- character()
  hook <- options(scworkbench.graph_storage_test_hook = function(event, evidence) {
    if (event != "identity_budget") return(invisible(NULL))
    calls <- vapply(sys.calls(), function(call) {
      if (!is.call(call) || is.function(call[[1L]])) return("<anonymous>")
      paste(deparse(call[[1L]]), collapse = " ")
    }, character(1))
    if (!any(grepl("wb_prov_payload_identity|wb_prov_write_snapshot", calls))) return(invisible(NULL))
    stopifnot(evidence$budgets$memory_bytes == "8388608",
      evidence$budgets$partition_bytes == 262144,
      evidence$budgets$sqlite_cache_kib == 2048,
      -DBI::dbGetQuery(evidence$con, "PRAGMA cache_size;")[[1L]][[1L]] <= max(-admitted))
    branches <<- c(branches, if (any(grepl("wb_graph_retained_identities", calls)))
      "retained_reference" else if (identical(evidence$artifact_id, "staged"))
        "stage_payload" else "published_certificate")
  })
  on.exit(options(hook), add = TRUE)
  attr(graph, "graph_stage") <- stages[[1L]]
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(),
    outputs = list(vector = graph))
  promoted <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  retained <- scworkbench:::.wb_graph_load_reference(bundle, id)
  observed <- scworkbench:::.wb_prov_payload_identity(bundle, retained)
  stopifnot(identical(observed$content_sha256, wb_graph_identity(graph)$content_identity$sha256),
    identical(cache(), admitted), identical(bundle$con@ref$wb_graph_policy, policy),
    all(c("stage_payload", "published_certificate", "retained_reference") %in% branches))
  restore()
  stopifnot(identical(cache(), before), is.null(bundle$con@ref$wb_graph_policy))
  TRUE
}

test_graph_resource_late_transaction_admission_rejects_contract <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  before <- DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]]
  DBI::dbBegin(con)
  error <- tryCatch(scworkbench:::.wb_graph_scoped_connection_budget(con,
    scworkbench:::.wb_graph_budgets()), error = identity)
  stopifnot(inherits(error, "wb_graph_error"),
    error$code == "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    RSQLite::sqliteIsTransacting(con),
    DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]] == before,
    is.null(con@ref$wb_graph_policy))
  DBI::dbRollback(con)
  TRUE
}

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
  restore_budget <- scworkbench:::.wb_graph_aggregate_connection_budget(
    list(bundle$con, stage$con), stage$budgets)
  on.exit(restore_budget(), add = TRUE)
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

# Imported stages reserve all surviving output slots before opening SQLite.
test_graph_resource_import_connection_reservation_contract <- function() {
  graph <- wb_prim_graph(nodes = list(list(node_id = "n1")), edges = list(), incidences = list())
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "1048576",
    sqlite_cache_kib = 256L, partition_bytes = 4096L, partition_rows = 2L, collect_bytes = 8192L))
  seed <- scworkbench:::.wb_graph_stage_small(graph)
  token <- tempfile("graph_import_reservation_")
  source <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  durable <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  connections <- list(source, durable); stages <- list(); restore <- NULL
  old <- options("scworkbench.graph_storage_test_hook")
  on.exit({options(old); for (stage in stages) scworkbench:::.wb_graph_stage_discard(stage)
    scworkbench:::.wb_graph_stage_discard(seed); if (!is.null(restore)) restore()
    DBI::dbDisconnect(source); DBI::dbDisconnect(durable); unlink(token)}, add = TRUE)
  snapshot <- function(con) list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)
  before <- lapply(connections, snapshot)
  scworkbench:::.wb_graph_export_parts(seed$con, "staged", token, policy)
  restore <- scworkbench:::.wb_graph_aggregate_connection_budget(connections, policy, extra = 2L)
  observed <- numeric()
  options(scworkbench.graph_storage_test_hook = function(event, state) if (event == "configured") {
    all <- c(connections, lapply(stages, function(stage) stage$con), list(state$con))
    reservation <- 128 + sum(vapply(all, function(con)
      -DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]], numeric(1)))
    stopifnot(reservation <= 256L); observed <<- c(observed, reservation)
  })
  stages[[1L]] <- scworkbench:::.wb_graph_import_parts(token, policy,
    connections = connections, cache_slots = 2L)
  stages[[2L]] <- scworkbench:::.wb_graph_import_parts(token, policy,
    connections = c(connections, list(stages[[1L]]$con)), cache_slots = 1L)
  stopifnot(identical(observed, c(224, 256)))
  for (stage in stages) scworkbench:::.wb_graph_stage_discard(stage)
  stages <- list()
  # Imported admission must carry the active lowest policy, not just its cache.
  higher <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    sqlite_cache_kib = 2048L, partition_bytes = 8192L, partition_rows = 4L, collect_bytes = 65536L))
  stages[[1L]] <- scworkbench:::.wb_graph_import_parts(token, higher,
    connections = connections, cache_slots = 2L)
  stopifnot(identical(stages[[1L]]$budgets$memory_bytes, "1048576"),
    stages[[1L]]$budgets$sqlite_cache_kib == 256L,
    stages[[1L]]$budgets$partition_bytes == 4096L, stages[[1L]]$budgets$partition_rows == 2L,
    stages[[1L]]$budgets$collect_bytes == 8192L)
  for (stage in stages) scworkbench:::.wb_graph_stage_discard(stage)
  stages <- list(); restore(); restore <- NULL
  stopifnot(identical(before, lapply(connections, snapshot)))
  paths <- character()
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "connected") paths <<- c(paths, state$path)
    if (event == "configured") stop("import-configured-fault")
  })
  failed <- tryCatch(scworkbench:::.wb_graph_import_parts(token, policy,
    connections = connections), error = identity)
  stopifnot(inherits(failed, "error"), grepl("import-configured-fault", conditionMessage(failed)),
    !any(file.exists(paths)), identical(before, lapply(connections, snapshot)),
    scworkbench:::.wb_graph_budgets()$sqlite_cache_kib == 8192L)
  options(scworkbench.graph_storage_test_hook = NULL)
  too_small <- policy; too_small$sqlite_cache_kib <- 128L
  failed <- tryCatch(scworkbench:::.wb_graph_import_parts(token, too_small,
    connections = connections), error = identity)
  stopifnot(inherits(failed, "wb_graph_error"), failed$code == "GRAPH_RESOURCE_EXCEEDED",
    identical(before, lapply(connections, snapshot)))
  TRUE
}

# Descriptor targets are a reusable current slot; only owned inode metadata is retained.
test_graph_resource_unrelated_descriptor_slot_contract <- function() {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "1048576",
    sqlite_cache_kib = 256L, partition_bytes = 4096L, partition_rows = 2L, collect_bytes = 8192L))
  root <- tempfile("graph_fd_live_slots_"); dir.create(root)
  paths <- file.path(root, paste0(sprintf("%02d", seq_len(12L)), strrep("p", 220L)))
  handles <- list(); owned <- NULL; spill <- tempfile("scwb_graph_identity_live_slot_")
  on.exit({for (handle in handles) try(close(handle), silent = TRUE)
    if (!is.null(owned)) try(close(owned), silent = TRUE)
    unlink(c(root, spill), recursive = TRUE)}, add = TRUE)
  before <- scworkbench:::.wb_graph_transient_usage(budgets = policy)$owned_spill_bytes
  handles <- lapply(paths, function(path) file(path, "wb"))
  writeBin(raw(4096), spill); owned <- file(spill, "rb")
  usage <- scworkbench:::.wb_graph_transient_usage(budgets = policy)
  stopifnot(usage$owned_spill_bytes == before + 4096)
  unlink(spill)
  usage <- scworkbench:::.wb_graph_transient_usage(budgets = policy)
  stopifnot(usage$owned_spill_bytes == before + 4096)
  close(owned); owned <- NULL
  stopifnot(scworkbench:::.wb_graph_transient_usage(budgets = policy)$owned_spill_bytes == before)
  TRUE
}

test_graph_resource_owned_inode_metadata_overflow_contract <- function() {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "1048576",
    sqlite_cache_kib = 256L, partition_bytes = 4096L, partition_rows = 2L, collect_bytes = 8192L))
  paths <- vapply(seq_len(28L), function(i) tempfile("scwb_graph_identity_owned_overflow_"), character(1))
  handles <- list()
  on.exit({for (handle in handles) try(close(handle), silent = TRUE); unlink(paths)}, add = TRUE)
  for (path in paths) writeBin(raw(1L), path)
  handles <- lapply(paths, function(path) file(path, "rb"))
  failed <- tryCatch(scworkbench:::.wb_graph_transient_usage(budgets = policy), error = identity)
  stopifnot(inherits(failed, "wb_graph_error"), failed$code == "GRAPH_RESOURCE_EXCEEDED")
  for (handle in handles) close(handle)
  handles <- list(); unlink(paths)
  scworkbench:::.wb_graph_transient_usage(budgets = policy)
  TRUE
}
