.engine_owned_closure_fixture <- function(code) {
  root <- tempfile("owned_graph_closure_")
  bundle <- NULL; stages <- list(); undos <- list(); ns <- asNamespace("scworkbench")
  hooks <- options(scworkbench.graph_storage_test_hook = NULL,
    scworkbench.promotion_transaction_test_hook = NULL)
  on.exit(tryCatch({
    for (undo in rev(undos)) {
      unlockBinding(undo$name, ns); assign(undo$name, undo$original, ns); lockBinding(undo$name, ns)
    }
    options(hooks)
    for (stage in stages) try(scworkbench:::.wb_graph_stage_discard(stage), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
  }, finally = unlink(root, recursive = TRUE)), add = TRUE)
  bundle <- wb_init_bundle(root)
  wb_define_cells(bundle, c("c2", "c1"))
  x <- new.env(parent = emptyenv()); x$bundle <- bundle
  x$graph <- wb_prim_graph(list(list(node_id = "c2"), list(node_id = "c1")),
    list(), list(), direction_mode = "undirected")
  x$replace <- function(name, replacement) {
    original <- get(name, ns)
    undos[[length(undos)+1L]] <<- list(name = name, original = original)
    unlockBinding(name, ns); assign(name, replacement(original), ns); lockBinding(name, ns)
  }
  x$stage <- function(graph = x$graph) {
    stage <- scworkbench:::.wb_graph_stage_small(graph)
    stages[[length(stages)+1L]] <<- stage
    stage
  }
  x$run <- function(graph = x$graph) wb_new_run("metadata_cell_vector",
    inputs = list(), params = list(), outputs = list(vector = graph))
  x$promote <- function(run) wb_promote_analysis(bundle, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  x$artifact_rows <- function() lapply(c("artifacts", "artifact_graph_meta", "artifact_graph_rows"),
    function(table) DBI::dbGetQuery(bundle$con, paste0("SELECT * FROM ", table, " ORDER BY rowid;")))
  x$logical_rows <- function() list(artifacts = x$artifact_rows(),
    registry = scworkbench:::.wb_manifest_registry_snapshot(bundle$con))
  x$pending <- function() list(
    bundle_files = sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)),
    pending_files = sort(list.files(file.path(root, "provenance", ".pending"),
      recursive = TRUE, all.files = TRUE, no.. = TRUE)),
    graph_scratch = sort(list.files(tempdir(),
      pattern = "^scwb_graph_(stage_|tokens_|identity_)", full.names = TRUE)))
  x$policy <- function() list(policy = bundle$con@ref$wb_graph_policy,
    cap = bundle$con@ref$wb_graph_cache_kib,
    cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]])
  code(x)
  TRUE
}

test_engine_graph_owned_closure_single_pass_and_default_contract <- function() {
  .engine_owned_closure_fixture(function(x) {
    staged_calls <- 0L; retained <- list(); sources <- 0L
    x$replace(".wb_graph_sql_content_hash", function(original) function(con, artifact_id, budgets) {
      if (identical(artifact_id, "staged")) staged_calls <<- staged_calls + 1L else
        retained[[length(retained)+1L]] <<- list(id = artifact_id, ref = con@ref)
      original(con, artifact_id, budgets)
    })
    x$replace(".wb_graph_sources_assert", function(original) function(...) {
      sources <<- sources + 1L; original(...)
    })
    default <- x$stage()
    stopifnot(staged_calls == 1L, length(retained) == 0L, !is.null(default$content))
    scworkbench:::.wb_graph_stage_discard(default)
    staged_calls <- 0L
    paths <- character()
    options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "configured") paths <<- c(paths, state$path)
    })
    promoted <- x$promote(x$run())
    id <- promoted$promoted$artifact_id[[1L]]
    stopifnot(staged_calls == 1L, length(retained) == 1L,
      identical(retained[[1L]]$id, id), identical(retained[[1L]]$ref, x$bundle$con@ref),
      sources == 2L, length(paths) == 1L, !any(file.exists(paths)))
    literal <- paste0('{"attributes":{"edge":[],"graph":[],"incidence":[],"node":[]},',
      '"direction_mode":"undirected","edges":[],"incidences":[],"nodes":[{"node_id":"c2"},{"node_id":"c1"}],',
      '"schema":"scworkbench.graph.content.v1"}')
    expected <- digest::digest(charToRaw(literal), algo = "sha256", serialize = FALSE)
    stopifnot(identical(wb_art_graph_info(x$bundle, id)$content_identity$sha256, expected),
      identical(vapply(wb_art_graph_slice(x$bundle, id, "nodes"), `[[`, "", "node_id"), c("c2", "c1")))
  })
}

test_engine_graph_owned_closure_malformed_actual_sql_contract <- function() {
  .engine_owned_closure_fixture(function(x) {
    broken <- TRUE; validated <- 0L; retained <- 0L; paths <- character()
    options(scworkbench.graph_storage_test_hook = function(event, state)
      if (event == "configured") paths <<- c(paths, state$path))
    x$replace(".wb_graph_sql_content_hash", function(original) function(con, artifact_id, budgets) {
      staged <- identical(artifact_id, "staged")
      if (staged) validated <<- validated + 1L else retained <<- retained + 1L
      # Active promotion already has a pending provenance commit. Check full
      # registry equality after rollback, not against this legitimate live row.
      if (broken && staged) stopifnot(identical(before$artifacts, x$artifact_rows()))
      if (broken && staged) DBI::dbExecute(con,
        "UPDATE artifact_graph_rows SET record_json='{}' WHERE component='nodes' AND row_ordinal=0;")
      original(con, artifact_id, budgets)
    })
    before <- x$logical_rows(); pending <- x$pending()
    old_failure <- tryCatch(x$stage(), error = identity)
    stopifnot(inherits(old_failure, "wb_graph_error"), validated == 1L, !any(file.exists(paths)))
    run <- x$run()
    failure <- tryCatch(x$promote(run), error = identity)
    stopifnot(inherits(failure, "error"), validated == 2L, retained == 0L,
      grepl(conditionMessage(old_failure), conditionMessage(failure), fixed = TRUE),
      identical(before, x$logical_rows()), identical(pending, x$pending()),
      !any(file.exists(paths)), !RSQLite::sqliteIsTransacting(x$bundle$con))
    broken <- FALSE
    retry <- x$promote(run)
    stopifnot(identical(retry$promoted$status, "ok"), validated == 3L, retained == 1L, !any(file.exists(paths)))
  })
}

test_engine_graph_owned_closure_resource_fault_rollback_retry_contract <- function() {
  .engine_owned_closure_fixture(function(x) {
    policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
      partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
      sqlite_cache_kib = 2048L))
    restore <- scworkbench:::.wb_graph_scoped_connection_budget(x$bundle$con, policy)
    on.exit(restore(), add = TRUE)
    before <- x$logical_rows(); pending <- x$pending(); admitted <- x$policy()
    # Construction's original materialization admission still precedes malformed
    # primitive diagnostics, in both default and promoter-deferred modes.
    malformed <- x$graph; malformed$content$nodes[[1L]] <- list(node_id = NA_character_)
    faults <- lapply(c(FALSE, TRUE), function(defer) tryCatch(
      scworkbench:::.wb_graph_stage_small(malformed, list(collect_bytes = 100),
        .defer_content_closure = defer), error = identity))
    stopifnot(all(vapply(faults, inherits, logical(1), "wb_graph_error")),
      identical(faults[[1L]]$code, "GRAPH_RESOURCE_EXCEEDED"),
      identical(faults[[1L]]$code, faults[[2L]]$code),
      identical(conditionMessage(faults[[1L]]), conditionMessage(faults[[2L]])))
    paths <- character(); mode <- "identity"; identity_faults <- 0L
    options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "configured") {
        paths <<- c(paths, state$path)
        source <- -DBI::dbGetQuery(x$bundle$con, "PRAGMA cache_size;")[[1L]][[1L]]
        stage <- -DBI::dbGetQuery(state$con, "PRAGMA cache_size;")[[1L]][[1L]]
        stopifnot(source + stage + 128L <= policy$sqlite_cache_kib,
          identical(state$budgets$memory_bytes, policy$memory_bytes))
      }
      if (event == "identity_budget" && mode == "identity") {
        identity_faults <<- identity_faults + 1L
        stop("OWNED_GRAPH_IDENTITY_RESOURCE_FAULT")
      }
    }, scworkbench.promotion_transaction_test_hook = function(event, ...)
      if (event == "graph_component_rows" && mode == "copy") stop("OWNED_GRAPH_COPY_ROLLBACK_FAULT"))
    run <- x$run()
    for (selected in c("identity", "copy")) {
      mode <- selected
      failure <- tryCatch(x$promote(run), error = identity)
      stopifnot(inherits(failure, "error"), grepl(if (selected == "identity")
        "OWNED_GRAPH_IDENTITY_RESOURCE_FAULT" else "OWNED_GRAPH_COPY_ROLLBACK_FAULT",
        conditionMessage(failure), fixed = TRUE), identical(before, x$logical_rows()),
        identical(pending, x$pending()), identical(admitted, x$policy()),
        !any(file.exists(paths)), !RSQLite::sqliteIsTransacting(x$bundle$con))
    }
    stopifnot(identity_faults == 1L)
    mode <- "success"
    stopifnot(identical(x$promote(run)$promoted$status, "ok"), !any(file.exists(paths)),
      identical(admitted, x$policy()))
  })
}

test_engine_graph_owned_closure_borrowed_seal_and_collision_contract <- function() {
  .engine_owned_closure_fixture(function(x) {
    stage <- x$stage()
    stage$seal <- scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets)
    borrowed <- x$graph; attr(borrowed, "graph_stage") <- stage
    run <- x$run(borrowed); before <- x$logical_rows(); pending <- x$pending()
    DBI::dbExecute(stage$con,
      "UPDATE artifact_graph_rows SET record_json='{\"node_id\":\"changed\"}' WHERE component='nodes' AND row_ordinal=0;")
    failure <- tryCatch(x$promote(run), error = identity)
    stopifnot(inherits(failure, "error"), grepl("GRAPH_SEAL_MISMATCH", conditionMessage(failure), fixed = TRUE),
      identical(before, x$logical_rows()), identical(pending, x$pending()),
      file.exists(stage$path), DBI::dbIsValid(stage$con))
    DBI::dbExecute(stage$con,
      "UPDATE artifact_graph_rows SET record_json='{\"node_id\":\"c2\"}' WHERE component='nodes' AND row_ordinal=0;")
    first <- x$promote(run); id <- first$promoted$artifact_id[[1L]]
    before <- x$logical_rows(); pending <- x$pending(); collision <- TRUE
    x$replace(".wb_new_artifact_id", function(original) function(...) {
      if (collision) id else original(...)
    })
    owned_run <- x$run()
    failure <- tryCatch(x$promote(owned_run), error = identity)
    stopifnot(inherits(failure, "error"), grepl("UNIQUE constraint failed", conditionMessage(failure), fixed = TRUE),
      identical(before, x$logical_rows()), identical(pending, x$pending()), file.exists(stage$path))
    collision <- FALSE
    stopifnot(identical(x$promote(owned_run)$promoted$status, "ok"))
  })
}

test_engine_graph_owned_closure_bound_source_freshness_contract <- function() {
  .engine_owned_closure_fixture(function(x) {
    value <- wb_prim_cell_vector(setNames(c("a", "b"), c("c2", "c1")))
    source_run <- x$run(value); source <- x$promote(source_run)$promoted$artifact_id[[1L]]
    snapshot <- DBI::dbGetQuery(x$bundle$con,
      "SELECT h.* FROM prov_heads h JOIN artifacts a ON a.provenance_snapshot_id=h.snapshot_id WHERE a.artifact_id=?;",
      params = list(source))
    snapshot_identity <- scworkbench:::.wb_operation_pack_v3_head_snapshot(snapshot)$source_snapshot_identity
    snapshot_identity$scope <- NULL
    ref <- list(kind = "retained_cell_axis", source_id = source)
    axis <- scworkbench:::.wb_graph_source_axis_hash(x$bundle, ref, "cell", scworkbench:::.wb_graph_budgets())
    binding <- list(binding_id = "bound_cells", axis_kind = "cell", source_ref = ref,
      source_snapshot_identity = snapshot_identity, axis_content_identity = axis$axis_content_identity,
      axis_order_identity = axis$axis_order_identity,
      mapping = list(list(node_id = "c2", axis_id = "c2"), list(node_id = "c1", axis_id = "c1")))
    graph <- wb_prim_graph(x$graph$content$nodes, list(), list(), associations = list(binding), direction_mode = "undirected")
    run <- x$run(graph)
    source_rows <- DBI::dbGetQuery(x$bundle$con,
      "SELECT * FROM artifact_labels WHERE artifact_id=? ORDER BY payload_ordinal;", params = list(source))
    original <- source_rows$label[[1L]]
    DBI::dbExecute(x$bundle$con,
      "UPDATE artifact_labels SET label='changed_source' WHERE artifact_id=? AND payload_ordinal=0;", params = list(source))
    before <- x$logical_rows(); pending <- x$pending()
    failure <- tryCatch(x$promote(run), error = identity)
    stopifnot(inherits(failure, "error"), grepl("GRAPH_", conditionMessage(failure), fixed = TRUE),
      identical(before, x$logical_rows()), identical(pending, x$pending()))
    DBI::dbExecute(x$bundle$con,
      "UPDATE artifact_labels SET label=? WHERE artifact_id=? AND payload_ordinal=0;", params = list(original, source))
    stopifnot(identical(source_rows, DBI::dbGetQuery(x$bundle$con,
      "SELECT * FROM artifact_labels WHERE artifact_id=? ORDER BY payload_ordinal;", params = list(source))))
    promoted <- x$promote(run); info <- wb_art_graph_info(x$bundle, promoted$promoted$artifact_id[[1L]])
    expected <- wb_graph_identity(graph)
    stopifnot(identical(info$content_identity, expected$content_identity),
      identical(info$binding_identity, expected$binding_identity),
      identical(info$descriptor_identity, expected$descriptor_identity))
  })
}
