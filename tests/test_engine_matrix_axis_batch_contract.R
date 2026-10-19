# Generic getter/axis authority tests, not scientific-method assertions.
.engine_axis_policy <- function(rows = 128L, bytes = 1048576L) {
  scworkbench:::.wb_graph_budgets(list(memory_bytes = "16777216", sqlite_cache_kib = 256L,
    partition_bytes = bytes, partition_rows = rows, collect_bytes = 2097152L))
}
.engine_axis_error <- function(code, expression) {
  error <- tryCatch(force(expression), error = identity)
  stopifnot(inherits(error, "error"), grepl(code, conditionMessage(error), fixed = TRUE))
  invisible(error)
}
.engine_axis_inventory <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  setNames(vapply(paths, function(path) digest::digest(file = path, algo = "sha256"), ""),
    substring(paths, nchar(root) + 2L))
}
.engine_axis_pair <- function(actual, requested = actual, declaration = "TEXT COLLATE BINARY") {
  root <- tempfile("axis_batch_fixture_"); dir.create(root)
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "source.sqlite"))
  scratch <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "scratch.sqlite"))
  DBI::dbExecute(con, paste0("CREATE TABLE members(id ", declaration, ",tag TEXT)"))
  if (length(actual)) DBI::dbAppendTable(con, "members", data.frame(id = actual, tag = "selected"))
  DBI::dbExecute(scratch, "CREATE TABLE requested(axis_id TEXT)")
  if (length(requested)) DBI::dbAppendTable(scratch, "requested", data.frame(axis_id = requested))
  list(con = con, scratch = scratch, root = root,
    source = list(sql = "SELECT id axis_id FROM members WHERE tag=?", params = list("selected")),
    close = function() {
      if (DBI::dbIsValid(scratch)) DBI::dbDisconnect(scratch)
      if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
      unlink(root, recursive = TRUE)
    })
}
.engine_axis_run_membership <- function(fixture, policy, old = FALSE) {
  cursor <- DBI::dbSendQuery(fixture$scratch, "SELECT axis_id FROM requested ORDER BY rowid")
  on.exit(DBI::dbClearResult(cursor), add = TRUE)
  if (!old) return(scworkbench:::.wb_matrix_axis_membership_verify(fixture$con, cursor,
    fixture$source, policy, "axis fixture first missing"))
  # Literal pre-batching scalar predicate, exclusively owned scratch cursor.
  repeat {
    ids <- DBI::dbFetch(cursor, 1L)
    if (!nrow(ids)) break
    found <- DBI::dbGetQuery(fixture$con, paste0("SELECT 1 FROM (", fixture$source$sql,
      ") WHERE axis_id=? LIMIT 1;"), params = c(fixture$source$params, list(ids$axis_id[[1L]])))
    scworkbench:::.wb_graph_require(nrow(found) == 1L, "GRAPH_SOURCE_PAYLOAD_INVALID", "axis fixture first missing")
  }
  invisible(TRUE)
}
.engine_axis_swap <- function(package, name, replacement) {
  ns <- asNamespace(package); original <- get(name, ns, inherits = FALSE)
  unlockBinding(name, ns); assign(name, replacement, ns); lockBinding(name, ns)
  function() { unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns) }
}

# Literal function from ca8e4f62759f6f415193fe01dfc1b14ce53b231e:R/graph_sources.R113–158.
# Only its symbol is renamed; helpers resolve in the actual installed namespace.
.engine_axis_old_ca8e_hash <- function(bundle, source_ref, axis_kind, budgets) {
  query <- .wb_graph_source_axis_query(bundle, source_ref, axis_kind)
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore_budget <- .wb_graph_scoped_connection_budget(con, budgets)
  on.exit(restore_budget(), add = TRUE)
  database <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  database_path <- database$file[database$name == "main"][[1L]]
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM (", query$sql,
    ") WHERE octet_length(axis_id)>? LIMIT 1;"), params = c(query$params,
      list(min(256, budgets$partition_bytes))))
  .wb_graph_require(!nrow(oversized), "GRAPH_SOURCE_AUTHORITY_INVALID", "Invalid/oversized source axis ID.")
  emit_axis <- function(emit, membership = FALSE) {
    cursor <- DBI::dbSendQuery(con, paste0("SELECT axis_id FROM (", query$sql,
      ") ORDER BY ", if (membership) "CAST(axis_id AS BLOB)" else "axis_ordinal", ";"),
      params = query$params)
    first <- TRUE; previous <- NULL; count <- "0"
    tryCatch(repeat {
      if (as.numeric(count) %% budgets$partition_rows == 0)
        .wb_graph_transient_admit(budgets, database_path)
      rows <- DBI::dbFetch(cursor, n = 1L)
      if (!nrow(rows)) break
      id <- rows$axis_id[[1]]
      .wb_graph_require(.wb_graph_string(id) && (!membership || !identical(id, previous)),
        "GRAPH_SOURCE_AUTHORITY_INVALID", "Invalid/duplicate source axis ID.")
      if (!first) emit(",")
      emit(.wb_operation_pack_canonical_json(id))
      first <- FALSE; previous <- id; count <- .wb_graph_add_count(count, 1L)
    }, finally = DBI::dbClearResult(cursor))
    count
  }
  count <- "0"
  ordered <- .wb_graph_token_hash(function(emit) {
    emit("["); count <<- emit_axis(emit); emit("]")
  }, budgets)
  membership <- .wb_graph_token_hash(function(emit) {
    emit(paste0('{"axis_ids":[')); emit_axis(emit, TRUE)
    emit(paste0('],"axis_kind":', .wb_operation_pack_canonical_json(axis_kind),
      ',"schema":"scworkbench.graph.source-axis-content.v1","source_ref":',
      .wb_operation_pack_canonical_json(source_ref), "}"))
  }, budgets)
  list(axis_content_identity = list(
    scheme = "scworkbench.graph.source-axis-content.canonical-json.v1", sha256 = membership),
    axis_order_identity = list(scheme = paste0("scworkbench.", axis_kind, "_order.v1"),
      sha256 = ordered), axis_count = count)
}
.engine_axis_hash_fixture <- function(ids) {
  root <- tempfile("axis_hash_fixture_"); dir.create(root)
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "source.sqlite"))
  DBI::dbExecute(con, "CREATE TABLE matrices(matrix_id TEXT)")
  DBI::dbExecute(con, "INSERT INTO matrices VALUES('fixture')")
  # No column affinity: permits genuine malformed numeric/BLOB/NULL test rows.
  DBI::dbExecute(con, "CREATE TABLE features(feature_id,matrix_id TEXT)")
  if (length(ids)) DBI::dbAppendTable(con, "features", data.frame(feature_id = ids, matrix_id = "fixture"))
  list(bundle = list(con = con, dir = root), con = con, root = root,
    close = function() { if (DBI::dbIsValid(con)) DBI::dbDisconnect(con); unlink(root, recursive = TRUE) })
}
.engine_axis_hash <- function(fixture, old = FALSE, policy = .engine_axis_policy()) {
  fun <- if (old) .engine_axis_old_ca8e_hash else scworkbench:::.wb_graph_source_axis_hash
  if (old) environment(fun) <- asNamespace("scworkbench")
  fun(fixture$bundle, list(kind = "matrix", source_id = "fixture"), "feature", policy)
}

test_engine_matrix_axis_page_boundaries_and_scalar_oracle_contract <- function() {
  policy <- .engine_axis_policy()
  stopifnot(identical(scworkbench:::.wb_matrix_axis_page_rows(policy), 128L),
    identical(scworkbench:::.wb_matrix_axis_page_rows(.engine_axis_policy(bytes = 1024L)), 1L),
    scworkbench:::.wb_matrix_axis_page_rows(policy, params = as.list(seq_len(899L))) == 1L)
  for (n in c(0L, 1L, 127L, 128L, 129L, 385L)) {
    ids <- if (n) paste0("axis_", rev(seq_len(n))) else character()
    fixture <- .engine_axis_pair(ids)
    tryCatch({
      for (p in list(policy, .engine_axis_policy(rows = 1L), .engine_axis_policy(bytes = 1024L))) {
        stopifnot(isTRUE(.engine_axis_run_membership(fixture, p)),
          identical(.engine_axis_run_membership(fixture, p), .engine_axis_run_membership(fixture, p, old = TRUE)))
      }
      stopifnot(length(DBI::dbListResults(fixture$scratch)) == 0L)
    }, finally = fixture$close())
  }
  # Same row count, exactly one missing ID at both sides of each page boundary.
  for (position in c(127L, 128L, 129L, 385L)) {
    actual <- paste0("axis_", seq_len(385L)); requested <- actual
    requested[[position]] <- paste0("FOREIGN_", position)
    fixture <- .engine_axis_pair(actual, requested)
    tryCatch({
      for (old in c(TRUE, FALSE)) .engine_axis_error("GRAPH_SOURCE_PAYLOAD_INVALID",
        .engine_axis_run_membership(fixture, policy, old))
      stopifnot(length(DBI::dbListResults(fixture$scratch)) == 0L)
    }, finally = fixture$close())
  }
  TRUE
}

test_engine_matrix_axis_left_affinity_collation_and_first_missing_contract <- function() {
  cases <- list(list(type = "TEXT COLLATE NOCASE", actual = c("Alpha", "01"), requested = c("alpha", "01"), valid = TRUE),
    list(type = "TEXT COLLATE BINARY", actual = c("Alpha", "01"), requested = c("alpha", "01"), valid = FALSE),
    list(type = "NUMERIC", actual = c("01", "2"), requested = c("1", "02"), valid = TRUE),
    list(type = "TEXT", actual = c("01", "2"), requested = c("1", "02"), valid = FALSE),
    list(type = "TEXT", actual = c("雪", "quote\"slash\\", "line\nreturn\r", strrep("x", 256L)),
      requested = c("雪", "quote\"slash\\", "line\nreturn\r", strrep("x", 256L)), valid = TRUE))
  for (case in cases) {
    fixture <- .engine_axis_pair(case$actual, case$requested, case$type)
    tryCatch({
      for (old in c(TRUE, FALSE)) if (case$valid) stopifnot(isTRUE(.engine_axis_run_membership(fixture, .engine_axis_policy(), old))) else
        .engine_axis_error("GRAPH_SOURCE_PAYLOAD_INVALID", .engine_axis_run_membership(fixture, .engine_axis_policy(), old))
    }, finally = fixture$close())
  }
  fixture <- .engine_axis_pair(paste0("id_", 1:129), c("FOREIGN_first", "FOREIGN_second", paste0("id_", 3:129)))
  on.exit(fixture$close(), add = TRUE)
  query <- get("dbGetQuery", asNamespace("DBI")); observed <- NULL
  undo <- .engine_axis_swap("DBI", "dbGetQuery", function(conn, statement, ...) {
    result <- query(conn, statement, ...)
    if (startsWith(statement, "WITH requested")) observed <<- result
    result
  })
  tryCatch({
    .engine_axis_error("GRAPH_SOURCE_PAYLOAD_INVALID", .engine_axis_run_membership(fixture, .engine_axis_policy()))
    stopifnot(nrow(observed) == 1L, as.numeric(observed$ordinal[[1L]]) == 1)
  }, finally = undo())
  stopifnot(length(DBI::dbListResults(fixture$scratch)) == 0L)
  TRUE
}

test_engine_matrix_axis_hash_old_literal_and_independent_preimage_contract <- function() {
  for (n in c(0L, 1L, 127L, 128L, 129L, 257L)) {
    ids <- if (n) sprintf("axis_%04d", rev(seq_len(n))) else character()
    fixture <- .engine_axis_hash_fixture(ids)
    tryCatch({
      actual <- .engine_axis_hash(fixture)
      stopifnot(identical(actual, .engine_axis_hash(fixture, old = TRUE)))
      array <- function(x) paste0("[", paste(paste0('"', x, '"'), collapse = ","), "]")
      # paste0(character()) is not an empty JSON array; explicitly guard it.
      if (!length(ids)) array <- function(x) "[]"
      membership <- paste0('{"axis_ids":', array(sort(ids, method = "radix")),
        ',"axis_kind":"feature","schema":"scworkbench.graph.source-axis-content.v1",',
        '"source_ref":{"kind":"matrix","source_id":"fixture"}}')
      stopifnot(identical(actual$axis_count, as.character(n)),
        identical(actual$axis_order_identity$sha256, digest::digest(array(ids), algo = "sha256", serialize = FALSE)),
        identical(actual$axis_content_identity$sha256, digest::digest(membership, algo = "sha256", serialize = FALSE)),
        length(DBI::dbListResults(fixture$con)) == 0L)
      if (n %in% c(0L, 128L, 129L)) {
        # Observe actual source-admission calls in both real implementations;
        # never infer schedule equality merely from a proposed page size.
        admit <- get(".wb_graph_transient_admit", asNamespace("scworkbench"))
        calls <- character()
        undo <- .engine_axis_swap("scworkbench", ".wb_graph_transient_admit", function(budgets, path = "") {
          calls <<- c(calls, path); admit(budgets, path)
        })
        tryCatch({
          .engine_axis_hash(fixture, old = TRUE); old_calls <- calls; calls <- character()
          .engine_axis_hash(fixture); new_calls <- calls
          stopifnot(length(old_calls) > 0L, identical(old_calls, new_calls))
        }, finally = undo())
      }
    }, finally = fixture$close())
  }
  TRUE
}

test_engine_matrix_axis_hash_malformed_cross_page_and_policy_contract <- function() {
  for (ids in list(c(sprintf("axis_%04d", 1:128), "axis_0128"), strrep("x", 257L), NA_character_)) {
    fixture <- .engine_axis_hash_fixture(ids)
    tryCatch({
      .engine_axis_error("GRAPH_SOURCE_AUTHORITY_INVALID", .engine_axis_hash(fixture))
      .engine_axis_error("GRAPH_SOURCE_AUTHORITY_INVALID", .engine_axis_hash(fixture, old = TRUE))
      stopifnot(length(DBI::dbListResults(fixture$con)) == 0L)
    }, finally = fixture$close())
  }
  for (sql in c("INSERT INTO features VALUES(42,'fixture')", "INSERT INTO features VALUES(X'61','fixture')")) {
    fixture <- .engine_axis_hash_fixture(character())
    tryCatch({
      DBI::dbExecute(fixture$con, sql)
      .engine_axis_error("GRAPH_SOURCE_AUTHORITY_INVALID", .engine_axis_hash(fixture))
      stopifnot(length(DBI::dbListResults(fixture$con)) == 0L)
    }, finally = fixture$close())
  }
  fixture <- .engine_axis_hash_fixture(c("雪", "quote\"slash\\", "line\nreturn\r", strrep("x", 256L)))
  on.exit(fixture$close(), add = TRUE)
  stopifnot(identical(.engine_axis_hash(fixture), .engine_axis_hash(fixture, old = TRUE)),
    identical(.engine_axis_hash(fixture, policy = .engine_axis_policy(bytes = 1024L)), .engine_axis_hash(fixture, old = TRUE, policy = .engine_axis_policy(bytes = 1024L))))
  # Real mixed SQL types in one projected page; not a uniformly numeric result.
  mixed <- .engine_axis_hash_fixture(c("alpha", "omega"))
  tryCatch({
    DBI::dbExecute(mixed$con, "UPDATE features SET feature_id=42 WHERE rowid=2")
    .engine_axis_error("GRAPH_SOURCE_AUTHORITY_INVALID", .engine_axis_hash(mixed))
    # Pre-execution backend premise correction: the old *ordered cursor* can
    # coerce a later INTEGER into character and warns. This says nothing about
    # old full-hash acceptance: its second BLOB-sorted pass may reorder types.
    cursor <- DBI::dbSendQuery(mixed$con, "SELECT feature_id FROM features ORDER BY rowid")
    warnings <- character()
    rows <- tryCatch(withCallingHandlers({
      list(DBI::dbFetch(cursor, 1L), DBI::dbFetch(cursor, 1L), DBI::dbFetch(cursor, 1L))
    }, warning = function(warning) {
      warnings <<- c(warnings, conditionMessage(warning))
      # Capture and assert this explicit backend warning; not silent suppression.
      invokeRestart("muffleWarning")
    }), finally = DBI::dbClearResult(cursor))
    stopifnot(identical(rows[[1L]]$feature_id, "alpha"), identical(rows[[2L]]$feature_id, "42"),
      nrow(rows[[3L]]) == 0L, length(warnings) > 0L,
      all(grepl("mixed type.*coercing", warnings)))
    stopifnot(length(DBI::dbListResults(mixed$con)) == 0L)
  }, finally = mixed$close())
  # Change committed source AFTER the actual octet-length preflight. The
  # projected cursor must reject it without ever fetching its 1MiB TEXT in R.
  late <- .engine_axis_hash_fixture(c("alpha", "omega"))
  writer <- DBI::dbConnect(RSQLite::SQLite(), file.path(late$root, "source.sqlite"))
  on.exit({if (DBI::dbIsValid(writer)) DBI::dbDisconnect(writer); late$close()}, add = TRUE)
  .engine_axis_hash(late) # Warm the native SQL/resource observation once.
  cache <- DBI::dbGetQuery(late$con, "PRAGMA cache_size")
  fd <- if (dir.exists("/proc/self/fd")) length(list.files("/proc/self/fd")) else NULL
  original_query <- get("dbGetQuery", asNamespace("DBI"))
  original_fetch <- get("dbFetch", asNamespace("DBI"))
  original_send <- get("dbSendQuery", asNamespace("DBI"))
  mutated <- FALSE; projected <- FALSE; axis_fetches <- 0L
  undo_query <- .engine_axis_swap("DBI", "dbGetQuery", function(conn, statement, ...) {
    value <- original_query(conn, statement, ...)
    if (!mutated && grepl("WHERE octet_length(axis_id)>? LIMIT 1", statement, fixed = TRUE)) {
      stopifnot(nrow(value) == 0L,
        DBI::dbExecute(writer, "UPDATE features SET feature_id=? WHERE rowid=2",
          params = list(strrep("X", 1048576L))) == 1L)
      mutated <<- TRUE
    }
    value
  })
  undo_send <- .engine_axis_swap("DBI", "dbSendQuery", function(conn, statement, ...) {
    if (startsWith(statement, "SELECT CASE WHEN typeof(axis_id)")) {
      stopifnot(mutated); projected <<- TRUE
    }
    original_send(conn, statement, ...)
  })
  undo_fetch <- .engine_axis_swap("DBI", "dbFetch", function(res, n = -1, ...) {
    value <- original_fetch(res, n = n, ...)
    if ("axis_id" %in% names(value)) {
      axis_fetches <<- axis_fetches + 1L
      if (is.character(value$axis_id)) stopifnot(all(is.na(value$axis_id) | nchar(value$axis_id, type = "bytes") <= 256L))
    }
    value
  })
  tryCatch(.engine_axis_error("GRAPH_SOURCE_AUTHORITY_INVALID", .engine_axis_hash(late)),
    finally = {undo_fetch(); undo_send(); undo_query()})
  stopifnot(mutated, projected, axis_fetches > 0L,
    length(DBI::dbListResults(late$con)) == 0L,
    identical(cache, DBI::dbGetQuery(late$con, "PRAGMA cache_size")),
    is.null(fd) || length(list.files("/proc/self/fd")) == fd)
  stopifnot(DBI::dbExecute(writer, "UPDATE features SET feature_id='omega' WHERE rowid=2") == 1L,
    identical(.engine_axis_hash(late), .engine_axis_hash(late, old = TRUE)))
  TRUE
}

test_engine_matrix_axis_query_fetch_fault_cleanup_retry_contract <- function() {
  fixture <- .engine_axis_hash_fixture(sprintf("axis_%04d", 1:129))
  on.exit(fixture$close(), add = TRUE)
  before <- DBI::dbGetQuery(fixture$con, "PRAGMA cache_size")
  stopifnot(identical(.engine_axis_hash(fixture), .engine_axis_hash(fixture, old = TRUE)))
  descriptors_before <- if (dir.exists("/proc/self/fd")) length(list.files("/proc/self/fd")) else NULL
  for (name in c("dbGetQuery", "dbFetch")) {
    original <- get(name, asNamespace("DBI")); fired <- FALSE
    replacement <- local({ fun <- original; selected <- name; function(...) {
      args <- list(...)
      # Reach an owned positive-page axis cursor, not dbGetQuery's setup fetch.
      selected_call <- selected != "dbFetch" || (!is.null(args$n) && args$n > 0)
      if (!fired && selected_call) { fired <<- TRUE; stop("AXIS_INJECTED_QUERY_OR_FETCH") }
      fun(...)
    } })
    undo <- .engine_axis_swap("DBI", name, replacement)
    tryCatch(.engine_axis_error("AXIS_INJECTED_QUERY_OR_FETCH", .engine_axis_hash(fixture)), finally = undo())
    stopifnot(fired, length(DBI::dbListResults(fixture$con)) == 0L,
      identical(before, DBI::dbGetQuery(fixture$con, "PRAGMA cache_size")),
      identical(.engine_axis_hash(fixture), .engine_axis_hash(fixture, old = TRUE)),
      is.null(descriptors_before) || length(list.files("/proc/self/fd")) == descriptors_before)
  }
  # Exercise failures in membership itself AFTER a successful first128-row
  # batch, not merely an early source-hash setup query. Caller owns its cursor.
  member <- .engine_axis_pair(paste0("axis_", 1:385))
  on.exit(member$close(), add = TRUE)
  for (name in c("dbGetQuery", "dbFetch")) {
    active_cursor <- DBI::dbSendQuery(member$scratch, "SELECT axis_id FROM requested ORDER BY rowid")
    original <- get(name, asNamespace("DBI")); successes <- 0L; fired <- FALSE
    replacement <- local({ fun <- original; selected <- name; function(...) {
      args <- list(...)
      target <- if (selected == "dbGetQuery")
        length(args) >= 2L && startsWith(args[[2L]], "WITH requested") else
        length(args) >= 2L && identical(args[[1L]], active_cursor)
      if (target && successes == 1L && !fired) { fired <<- TRUE; stop("AXIS_MEMBERSHIP_AFTER_FIRST_BATCH") }
      value <- fun(...)
      if (target) successes <<- successes + 1L
      value
    } })
    undo <- .engine_axis_swap("DBI", name, replacement)
    tryCatch(.engine_axis_error("AXIS_MEMBERSHIP_AFTER_FIRST_BATCH",
      scworkbench:::.wb_matrix_axis_membership_verify(member$con, active_cursor,
        member$source, .engine_axis_policy(), "axis fixture first missing")),
      finally = {undo(); DBI::dbClearResult(active_cursor)})
    stopifnot(fired, successes == 1L, length(DBI::dbListResults(member$scratch)) == 0L,
      isTRUE(.engine_axis_run_membership(member, .engine_axis_policy())))
  }
  # A late resource admission failure, after a real earlier admission, must
  # unwind the live axis cursor/token file and restore policy before retry.
  # Both member fixture connections remain intentionally live here. The exact
  # diagnostic reproduces7→9 FDs at member creation, unchanged through faults;
  # compare this phase with its own baseline, not the earlier one-connection phase.
  descriptors_before_late <- if (dir.exists("/proc/self/fd")) length(list.files("/proc/self/fd")) else NULL
  admit <- get(".wb_graph_transient_admit", asNamespace("scworkbench")); admitted <- 0L
  undo <- .engine_axis_swap("scworkbench", ".wb_graph_transient_admit", function(budgets, path = "") {
    admitted <<- admitted + 1L
    if (admitted == 2L) stop("AXIS_LATE_TRANSIENT_ADMISSION")
    admit(budgets, path)
  })
  tryCatch(.engine_axis_error("AXIS_LATE_TRANSIENT_ADMISSION", .engine_axis_hash(fixture)), finally = undo())
  stopifnot(admitted == 2L, length(DBI::dbListResults(fixture$con)) == 0L,
    identical(before, DBI::dbGetQuery(fixture$con, "PRAGMA cache_size")),
    is.null(descriptors_before_late) || length(list.files("/proc/self/fd")) == descriptors_before_late,
    identical(.engine_axis_hash(fixture), .engine_axis_hash(fixture, old = TRUE)))
  TRUE
}

test_engine_matrix_axis_native_source_registry_rollback_and_readonly_purity_contract <- function() {
  root <- tempfile("axis_public_bundle_"); b <- wb_init_bundle(root)
  on.exit({if (DBI::dbIsValid(b$con)) wb_close_bundle(b); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- paste0("cell_", 129:1); features <- paste0("feature_", 3:1)
  values <- Matrix::sparseMatrix(i = rep(1:3, length.out = 129), j = 1:129,
    x = rep(1, 129), dims = c(3, 129), dimnames = list(features, cells))
  wb_define_cells(b, cells); wb_attach_matrix(b, "fixture", values)
  policy <- .engine_axis_policy()
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy)))
  fragment <- wb_matrix_fragments(b, "fixture")$fragment_id[[1L]]
  original <- DBI::dbGetQuery(b$con, "SELECT * FROM matrix_fragment_features WHERE fragment_id=? ORDER BY feature_id", params = list(fragment))
  # Source-only fixture correction: changing temp_store inside a caller TX is
  # illegal SQLite, unrelated to membership. Preselect the existing policy first.
  temp_store <- DBI::dbGetQuery(b$con, "PRAGMA temp_store")[[1L]]
  cache <- DBI::dbGetQuery(b$con, "PRAGMA cache_size")
  policy_con <- b$con
  on.exit({
    if (DBI::dbIsValid(policy_con) && !RSQLite::sqliteIsTransacting(policy_con))
      DBI::dbExecute(policy_con, paste0("PRAGMA temp_store=", as.integer(temp_store)))
  }, add = TRUE)
  DBI::dbExecute(b$con, "PRAGMA temp_store=FILE")
  active_policy <- b$con@ref$wb_graph_policy
  DBI::dbBegin(b$con)
  tryCatch({
    stopifnot(DBI::dbExecute(b$con, "UPDATE matrix_fragment_features SET feature_id='FOREIGN' WHERE fragment_id=? AND feature_id=?",
      params = list(fragment, features[[1L]])) == 1L)
    .engine_axis_error("GRAPH_SOURCE_PAYLOAD_INVALID", scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy))
    stopifnot(RSQLite::sqliteIsTransacting(b$con),
      identical(cache, DBI::dbGetQuery(b$con, "PRAGMA cache_size")),
      identical(active_policy, b$con@ref$wb_graph_policy),
      DBI::dbGetQuery(b$con, "PRAGMA temp_store")[[1L]] == 1L)
  }, finally = DBI::dbRollback(b$con))
  DBI::dbExecute(b$con, paste0("PRAGMA temp_store=", as.integer(temp_store)))
  stopifnot(identical(original, DBI::dbGetQuery(b$con, "SELECT * FROM matrix_fragment_features WHERE fragment_id=? ORDER BY feature_id", params = list(fragment))),
    !RSQLite::sqliteIsTransacting(b$con),
    identical(cache, DBI::dbGetQuery(b$con, "PRAGMA cache_size")),
    identical(active_policy, b$con@ref$wb_graph_policy),
    isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy)))
  # Real separately committed WAL mutation after successful membership, while
  # axes/counts stay valid: the original native observer finish must reject.
  DBI::dbGetQuery(b$con, "PRAGMA journal_mode=WAL")
  database <- DBI::dbGetQuery(b$con, "PRAGMA database_list")
  writer <- DBI::dbConnect(RSQLite::SQLite(), database$file[database$name == "main"][[1L]])
  on.exit(if (DBI::dbIsValid(writer)) DBI::dbDisconnect(writer), add = TRUE)
  description <- DBI::dbGetQuery(b$con, "SELECT description FROM matrices WHERE matrix_id='fixture'")$description[[1L]]
  membership <- get(".wb_matrix_axis_membership_verify", asNamespace("scworkbench")); changed <- FALSE
  undo <- .engine_axis_swap("scworkbench", ".wb_matrix_axis_membership_verify", function(...) {
    value <- membership(...)
    if (!changed) {
      stopifnot(DBI::dbExecute(writer, "UPDATE matrices SET description='WAL observation changed' WHERE matrix_id='fixture'") == 1L)
      changed <<- TRUE
    }
    value
  })
  tryCatch(.engine_axis_error("GRAPH_SOURCE_PAYLOAD_INVALID",
    scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy)), finally = undo())
  tryCatch({
    stopifnot(changed, DBI::dbExecute(writer, "UPDATE matrices SET description=? WHERE matrix_id='fixture'",
      params = list(description)) == 1L)
  }, finally = DBI::dbDisconnect(writer))
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy)),
    isTRUE(wb_finalize_recipient_bundle(b)$ready))
  wb_close_bundle(b)
  b <- wb_open_bundle(root, read_only = TRUE, validate = FALSE)
  # Warm the observational SQL measurement before recording the full FS baseline.
  state <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  before <- .engine_axis_inventory(root)
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "fixture", policy)))
  actual <- wb_matrix_read_features(b, "fixture", features, cells)
  stopifnot(identical(rownames(actual), features), identical(colnames(actual), cells),
    identical(as.matrix(actual), as.matrix(values)), isTRUE(b$read_only),
    identical(state, scworkbench:::.wb_manifest_registry_snapshot(b$con)),
    identical(before, .engine_axis_inventory(root)))
  TRUE
}
