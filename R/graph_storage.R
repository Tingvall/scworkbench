# Graph SQLite profile: all component data are ordered rows, never header arrays.
.wb_graph_components <- function() c("nodes", "edges", "incidences",
  "attribute_fields", "attribute_values", "bindings", "binding_mappings")

.wb_graph_budgets <- function(overrides = list()) {
  defaults <- list(storage_bytes = "8589934592", token_bytes = "8589934592",
    published_bytes = "8589934592", wal_bytes = "8589934592", memory_bytes = "67108864",
    partition_bytes = 1048576, partition_rows = 512L, collect_bytes = 16777216,
    sqlite_cache_kib = 8192L)
  .wb_graph_require(is.list(overrides) && !anyDuplicated(names(overrides)) &&
    all(names(overrides) %in% names(defaults)), "GRAPH_RESOURCE_POLICY_INVALID",
    "Unknown or duplicate resource budget.")
  defaults[names(overrides)] <- overrides
  byte_fields <- c("storage_bytes", "token_bytes", "published_bytes", "wal_bytes", "memory_bytes")
  for (name in byte_fields)
    .wb_graph_require(.wb_graph_int64(defaults[[name]]) &&
      !startsWith(defaults[[name]], "-") && defaults[[name]] != "0",
      "GRAPH_RESOURCE_POLICY_INVALID", name)
  for (name in setdiff(names(defaults), byte_fields))
    .wb_graph_require(is.numeric(defaults[[name]]) && length(defaults[[name]]) == 1L &&
      is.finite(defaults[[name]]) && defaults[[name]] > 0 &&
      defaults[[name]] <= 2147483647 && defaults[[name]] == floor(defaults[[name]]),
      "GRAPH_RESOURCE_POLICY_INVALID", name)
  .wb_graph_require(defaults$sqlite_cache_kib * 1024 + 8 * defaults$partition_bytes <=
    as.numeric(defaults$memory_bytes) && defaults$collect_bytes <= as.numeric(defaults$memory_bytes),
    "GRAPH_RESOURCE_POLICY_INVALID", "Cache/decoded-partition or collect reservation exceeds working-memory admission.")
  defaults
}

.wb_graph_disk_usage <- function(con) {
  database <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  path <- database$file[database$name == "main"][[1L]]
  pages <- as.double(DBI::dbGetQuery(con, "PRAGMA page_count;")[[1L]][[1L]])
  page_bytes <- as.double(DBI::dbGetQuery(con, "PRAGMA page_size;")[[1L]][[1L]])
  c(list(database_bytes = pages * page_bytes), .wb_graph_transient_usage(path))
}

.wb_graph_transient_usage <- function(path = "") {
  journal_paths <- paste0(path, c("-wal", "-journal", "-shm"))
  journal <- file.info(journal_paths)$size
  # SQLite unlinks temporary sort/spill files while their descriptors are
  # still open. Directory inventories alone would silently omit these bytes.
  # Procfs is used only inside core resource accounting; never exposed to packs.
  temp_bytes <- 0
  fd_root <- "/proc/self/fd"
  .wb_graph_require(dir.exists(fd_root), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    "Bounded graph SQLite runtime requires Linux procfs for unlinked temporary spill accounting.")
  if (dir.exists(fd_root)) {
    fds <- list.files(fd_root, full.names = TRUE)
    targets <- Sys.readlink(fds)
    temporary <- !is.na(targets) & grepl("(^|/)(etilqs_|scwb_graph_tokens_|scwb_graph_identity_|scwb_object_meta_)", targets)
    selected <- fds[temporary][!duplicated(targets[temporary])]
    sizes <- suppressWarnings(file.info(selected)$size)
    temp_bytes <- sum(sizes[!is.na(sizes)])
  }
  list(journal_bytes = sum(journal[!is.na(journal)]), temporary_bytes = temp_bytes,
    temporary_accounting = if (dir.exists(fd_root)) "procfs_open_descriptors" else "unavailable")
}

.wb_graph_transient_admit <- function(budgets, path = "") {
  usage <- .wb_graph_transient_usage(path)
  .wb_graph_require(usage$journal_bytes <= as.numeric(budgets$wal_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph SQLite WAL/journal/SHM budget exceeded.")
  .wb_graph_require(usage$temporary_bytes <= as.numeric(budgets$token_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph combined canonical-token/SQLite temporary spill budget exceeded.")
  invisible(usage)
}

.wb_graph_spill_admit <- function(budgets, scratch_path = NULL) {
  usage <- .wb_graph_transient_usage()
  scratch_bytes <- if (is.null(scratch_path)) 0 else file.info(scratch_path)$size
  .wb_graph_require(is.finite(scratch_bytes) && scratch_bytes + usage$temporary_bytes <=
    as.numeric(budgets$token_bytes), "GRAPH_RESOURCE_EXCEEDED",
    "Combined graph scratch database/canonical-token/temporary spill budget exceeded.")
  invisible(usage)
}

.wb_graph_disk_admit <- function(con, budgets, baseline = NULL) {
  usage <- .wb_graph_disk_usage(con)
  if (is.null(baseline)) .wb_graph_require(usage$database_bytes <= as.numeric(budgets$storage_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph staging database budget exceeded.")
  else .wb_graph_require(max(0, usage$database_bytes - baseline$database_bytes) <=
    as.numeric(budgets$published_bytes), "GRAPH_RESOURCE_EXCEEDED",
    "Graph publication database-growth budget exceeded.")
  .wb_graph_require(usage$journal_bytes <= as.numeric(budgets$wal_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph SQLite WAL/journal/SHM budget exceeded.")
  .wb_graph_require(usage$temporary_bytes <= as.numeric(budgets$token_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph SQLite temporary spill budget exceeded.")
  if (is.null(baseline)) .wb_graph_require(usage$database_bytes + usage$temporary_bytes <=
    as.numeric(budgets$token_bytes), "GRAPH_RESOURCE_EXCEEDED", "Combined graph scratch and spill budget exceeded.")
  invisible(usage)
}

.wb_graph_i64 <- function(value) {
  .wb_graph_require(.wb_graph_int64(value) && !startsWith(value, "-"),
    "GRAPH_COUNT_INVALID", "Expected exact nonnegative decimal int64.")
  bit64::as.integer64(value)
}

.wb_graph_add_count <- function(count, increment) {
  next_count <- suppressWarnings(.wb_graph_i64(count) + bit64::as.integer64(increment))
  .wb_graph_require(!is.na(next_count), "GRAPH_COUNT_OVERFLOW", "Count overflow.")
  as.character(next_count)
}

.wb_graph_materialization_admit <- function(value, bytes) {
  # Count canonical tokens without allocating a whole serialized graph or
  # expanded attribute/mapping rows. Abort before visiting the remaining tree.
  .wb_graph_require(is.numeric(bytes) && length(bytes) == 1L &&
    is.finite(bytes) && bytes > 0, "GRAPH_RESOURCE_POLICY_INVALID", "Materialization budget.")
  used <- 0
  add <- function(n) {
    used <<- used + n
    .wb_graph_require(used <= bytes, "GRAPH_RESOURCE_EXCEEDED",
      "Whole-object materialization budget exceeded; use bounded graph parts.")
  }
  walk <- function(x) {
    if (is.null(x)) {add(4); return(invisible(NULL))}
    if (is.list(x)) {
      add(2 + max(0, length(x) - 1))
      object <- !is.null(names(x))
      for (i in seq_along(x)) {
        if (object) {
          .wb_graph_require(nchar(names(x)[[i]], type = "bytes") <= bytes,
            "GRAPH_RESOURCE_EXCEEDED", "Oversized field token.")
          add(nchar(.wb_operation_pack_canonical_json(names(x)[[i]]), type = "bytes") + 1)
        }
        walk(x[[i]])
      }
    } else {
      if (is.character(x)) .wb_graph_require(all(nchar(x, type = "bytes") <= bytes),
        "GRAPH_RESOURCE_EXCEEDED", "Oversized scalar token.")
      add(nchar(.wb_operation_pack_canonical_json(x), type = "bytes"))
    }
    invisible(NULL)
  }
  walk(value)
  invisible(used)
}

.wb_graph_create_schema <- function(con, retained = TRUE) {
  .wb_graph_backend_assert(con)
  DBI::dbExecute(con, paste0("CREATE TABLE IF NOT EXISTS artifact_graph_meta (",
    "artifact_id TEXT PRIMARY KEY,profile TEXT NOT NULL,direction_mode TEXT NOT NULL,",
    "content_identity_json TEXT,binding_identity_json TEXT,descriptor_json TEXT,",
    "descriptor_identity_json TEXT,canonical_bytes TEXT,",
    if (retained) "FOREIGN KEY(artifact_id) REFERENCES artifacts(artifact_id) DEFERRABLE INITIALLY DEFERRED" else
      "CHECK(profile='graph_sqlite_v1')", ");"))
  DBI::dbExecute(con, paste0("CREATE TABLE IF NOT EXISTS artifact_graph_rows (",
    "artifact_id TEXT NOT NULL,component TEXT NOT NULL CHECK(component IN (",
    paste0("'", .wb_graph_components(), "'", collapse = ","), ")),",
    "row_ordinal INTEGER NOT NULL CHECK(typeof(row_ordinal)='integer' AND row_ordinal>=0),",
    "record_json TEXT NOT NULL CHECK(json_valid(record_json)),PRIMARY KEY(artifact_id,component,row_ordinal),",
    "FOREIGN KEY(artifact_id) REFERENCES artifact_graph_meta(artifact_id) DEFERRABLE INITIALLY DEFERRED);"))
  unique_fields <- list(nodes = "node_id", edges = "edge_id", incidences = "incidence_id",
    bindings = "binding_id")
  for (component in names(unique_fields)) DBI::dbExecute(con, paste0(
    "CREATE UNIQUE INDEX IF NOT EXISTS graph_", component, "_id ON artifact_graph_rows",
    "(artifact_id,json_extract(record_json,'$.", unique_fields[[component]],
    "')) WHERE component='", component, "';"))
  DBI::dbExecute(con, paste0("CREATE UNIQUE INDEX IF NOT EXISTS graph_edge_incidence ",
    "ON artifact_graph_rows(artifact_id,json_extract(record_json,'$.edge_id'),",
    "json_extract(record_json,'$.ordinal')) WHERE component='incidences';"))
  DBI::dbExecute(con, paste0("CREATE UNIQUE INDEX IF NOT EXISTS graph_field_id ",
    "ON artifact_graph_rows(artifact_id,json_extract(record_json,'$.scope'),",
    "json_extract(record_json,'$.field_ordinal')) WHERE component='attribute_fields';"))
  DBI::dbExecute(con, paste0("CREATE UNIQUE INDEX IF NOT EXISTS graph_field_name ",
    "ON artifact_graph_rows(artifact_id,json_extract(record_json,'$.scope'),",
    "json_extract(record_json,'$.name')) WHERE component='attribute_fields';"))
  DBI::dbExecute(con, paste0("CREATE UNIQUE INDEX IF NOT EXISTS graph_value_key ",
    "ON artifact_graph_rows(artifact_id,json_extract(record_json,'$.scope'),",
    "json_extract(record_json,'$.field_ordinal'),json_extract(record_json,'$.entity_ordinal')) ",
    "WHERE component='attribute_values';"))
  for (field in c("node_id", "axis_id")) DBI::dbExecute(con, paste0(
    "CREATE UNIQUE INDEX IF NOT EXISTS graph_mapping_", field,
    " ON artifact_graph_rows(artifact_id,json_extract(record_json,'$.binding_id'),",
    "json_extract(record_json,'$.", field, "')) WHERE component='binding_mappings';"))
  invisible(TRUE)
}

.wb_graph_backend_assert <- function(con) {
  available <- tryCatch(DBI::dbGetQuery(con, "SELECT octet_length('x') n;")$n[[1]] == 1,
    error = function(error) FALSE)
  .wb_graph_require(isTRUE(available), "GRAPH_BACKEND_VERSION_UNSUPPORTED",
    "Graph bounded reads require SQLite octet_length support (3.43 or later).")
  invisible(TRUE)
}

.wb_graph_configure <- function(con, budgets) {
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")
  DBI::dbExecute(con, "PRAGMA temp_store=FILE;")
  DBI::dbExecute(con, paste0("PRAGMA cache_size=-", budgets$sqlite_cache_kib, ";"))
  invisible(TRUE)
}

.wb_graph_stage_new <- function(direction_mode, budgets = list()) {
  .wb_graph_transient_usage()
  .wb_graph_require(.wb_graph_string(direction_mode) && direction_mode %in%
    c("directed", "undirected", "mixed"), "GRAPH_DIRECTION_INVALID", "Invalid header.")
  state <- new.env(parent = emptyenv())
  state$budgets <- .wb_graph_budgets(budgets)
  state$path <- tempfile("scwb_graph_stage_", fileext = ".sqlite")
  state$closed <- FALSE
  succeeded <- FALSE
  on.exit(if (!succeeded) .wb_graph_stage_discard(state), add = TRUE)
  state$con <- DBI::dbConnect(RSQLite::SQLite(), state$path, bigint = "character")
  attr(state$con, "wb_graph_owned_stage") <- TRUE
  # Register after SQLite creates its external pointer. R finalizes newer
  # registrations first: close our owned connection before its pointer is
  # collected, including abandoned session values and process exit.
  reg.finalizer(state, function(x) .wb_graph_stage_discard(x), onexit = TRUE)
  .wb_graph_storage_fault("connected", state)
  .wb_graph_configure(state$con, state$budgets)
  .wb_graph_create_schema(state$con, retained = FALSE)
  DBI::dbExecute(state$con, paste0("INSERT INTO artifact_graph_meta",
    "(artifact_id,profile,direction_mode) VALUES('staged','graph_sqlite_v1',?);"),
    params = list(direction_mode))
  state$counts <- stats::setNames(rep("0", length(.wb_graph_components())),
    .wb_graph_components())
  state$component <- 1L
  state$finished <- FALSE
  .wb_graph_disk_admit(state$con, state$budgets)
  succeeded <- TRUE
  state
}

.wb_graph_storage_fault <- function(event, state) {
  hook <- getOption("scworkbench.graph_storage_test_hook")
  if (is.function(hook)) hook(event, state)
  invisible(TRUE)
}

.wb_graph_stage_discard <- function(state) {
  if (!isTRUE(state$closed)) {
    if (!is.null(state$con) && DBI::dbIsValid(state$con)) DBI::dbDisconnect(state$con)
    for (path in c(state$path, paste0(state$path, c("-wal", "-shm", "-journal"))))
      if (file.exists(path)) unlink(path)
    state$closed <- TRUE
  }
  invisible(TRUE)
}

.wb_graph_page <- function(con, artifact_id, component, after, page, bytes,
                           predicate = "", params = list()) {
  # Measure encoded bytes inside SQLite before any payload crosses into R.
  # The first window is row-bounded; only the byte-admitted prefix is decoded.
  query <- paste0("WITH candidate AS (SELECT row_ordinal,",
    "octet_length(record_json) n FROM artifact_graph_rows ",
    "WHERE artifact_id=? AND component=? ", predicate,
    " AND row_ordinal>=CAST(? AS INTEGER) ORDER BY row_ordinal LIMIT ?),",
    "bounded AS (SELECT *,SUM(n) OVER (ORDER BY row_ordinal) used FROM candidate) ",
    "SELECT g.row_ordinal,g.record_json FROM bounded b JOIN artifact_graph_rows g ",
    "ON g.artifact_id=? AND g.component=? AND g.row_ordinal=b.row_ordinal ",
    "WHERE b.used<=? ORDER BY g.row_ordinal;")
  values <- c(list(artifact_id, component), params, list(after, page, artifact_id, component, bytes))
  rows <- DBI::dbGetQuery(con, query, params = values)
  if (!nrow(rows)) {
    exists <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows ",
      "WHERE artifact_id=? AND component=? ", predicate,
      " AND row_ordinal>=CAST(? AS INTEGER) LIMIT 1;"),
      params = c(list(artifact_id, component), params, list(after)))
    .wb_graph_require(!nrow(exists), "GRAPH_RESOURCE_EXCEEDED",
      "Single graph record exceeds the admitted decoded-partition budget.")
  }
  rows
}

.wb_graph_scan <- function(con, artifact_id, component, callback, page = 512L,
                           predicate = "", params = list(), bytes = 1048576) {
  # RSQLite has one live result per connection. Keyset pages are independently
  # closed before callbacks, permitting bounded nested field/value scans.
  after <- "0"
  repeat {
    rows <- .wb_graph_page(con, artifact_id, component, after, page, bytes,
      predicate, params)
    if (!nrow(rows)) break
    callback(rows)
    after <- .wb_graph_add_count(as.character(rows$row_ordinal[[nrow(rows)]]), 1L)
  }
  invisible(TRUE)
}

.wb_graph_parse <- function(json) .wb_operation_pack_parse_canonical_json(json)

.wb_graph_append <- function(state, component, rows, first_ordinal = NULL) {
  .wb_graph_require(!state$closed && !state$finished, "GRAPH_WRITER_RETIRED", "Writer retired.")
  index <- match(component, .wb_graph_components())
  .wb_graph_require(!is.na(index) && index >= state$component,
    "GRAPH_PART_ORDER_INVALID", "Components cannot be repeated or reordered.")
  rows <- .wb_graph_records(rows)
  .wb_graph_require(as.numeric(object.size(rows)) <= as.numeric(state$budgets$memory_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Decoded graph part exceeds working-memory admission.")
  .wb_graph_require(length(rows) <= state$budgets$partition_rows,
    "GRAPH_RESOURCE_EXCEEDED", "Partition row budget exceeded.")
  start <- state$counts[[component]]
  .wb_graph_require(is.null(first_ordinal) || identical(first_ordinal, start),
    "GRAPH_PART_ORDER_INVALID", "Partition is stale, repeated or missing.")
  if (!length(rows)) {state$component <- index; return(invisible(TRUE))}
  encoded <- vapply(rows, .wb_operation_pack_canonical_json, character(1))
  .wb_graph_require(sum(nchar(encoded, type = "bytes")) <= state$budgets$partition_bytes,
    "GRAPH_RESOURCE_EXCEEDED", "Decoded partition byte budget exceeded.")
  ordinals <- as.character(.wb_graph_i64(start) + bit64::as.integer64(seq_along(rows) - 1L))
  tryCatch(DBI::dbWithTransaction(state$con, {
    DBI::dbAppendTable(state$con, "artifact_graph_rows", data.frame(artifact_id = "staged",
      component = component, row_ordinal = bit64::as.integer64(ordinals), record_json = encoded))
    .wb_graph_disk_admit(state$con, state$budgets)
  }), error = function(error) {
    if (inherits(error, "wb_graph_error")) stop(error)
    .wb_graph_error("GRAPH_ROWS_INVALID", conditionMessage(error))
  })
  state$counts[[component]] <- .wb_graph_add_count(start, length(rows))
  state$component <- index
  .wb_graph_disk_admit(state$con, state$budgets)
  invisible(TRUE)
}

.wb_graph_row_validate <- function(component, record) {
  fields <- switch(component, nodes = "node_id", edges = c("edge_id", "kind", "direction"),
    incidences = c("incidence_id", "edge_id", "node_id", "role", "ordinal"),
    attribute_fields = c("scope", "field_ordinal", "name", "type", "nullable"),
    attribute_values = c("scope", "field_ordinal", "entity_ordinal", "value"),
    bindings = c("binding_ordinal", "binding_id", "axis_kind", "source_ref", "source_snapshot_identity",
      "axis_content_identity", "axis_order_identity"),
    binding_mappings = c("binding_id", "mapping_ordinal", "node_id", "axis_id"))
  .wb_graph_closed(record, fields, component)
  for (name in intersect(fields, c("node_id", "edge_id", "incidence_id", "binding_id", "axis_id", "name")))
    .wb_graph_require(.wb_graph_string(record[[name]]), "GRAPH_ID_INVALID", name)
  for (name in intersect(fields, "ordinal")) {
    value <- record[[name]]
    .wb_graph_require(is.numeric(value) && length(value) == 1L && is.finite(value) &&
      value >= 0 && value <= 999999999999999 && value == floor(value),
      "GRAPH_ORDINAL_INVALID", name)
  }
  for (name in intersect(fields, c("field_ordinal", "entity_ordinal", "binding_ordinal", "mapping_ordinal")))
    .wb_graph_i64(record[[name]])
  if (component == "edges") .wb_graph_require(.wb_graph_string(record$kind) &&
    .wb_graph_string(record$direction) && record$kind %in% c("ordinary", "hyper") &&
    record$direction %in% c("directed", "undirected"), "GRAPH_DIRECTION_INVALID", "Invalid edge.")
  if (component == "incidences") .wb_graph_require(.wb_graph_string(record$role) &&
    record$role %in% c("tail", "head", "member"),
    "GRAPH_ROLE_INVALID", "Invalid incidence role.")
  if (component %in% c("attribute_fields", "attribute_values"))
    .wb_graph_require(.wb_graph_string(record$scope) &&
      record$scope %in% c("graph", "node", "edge", "incidence"),
      "GRAPH_ATTRIBUTE_INVALID", "Invalid attribute scope.")
  if (component == "attribute_fields") .wb_graph_require(.wb_graph_string(record$type) && record$type %in%
    c("bool", "utf8", "int64_decimal_string", "float64_le_hex") &&
    is.logical(record$nullable) && length(record$nullable) == 1L && !is.na(record$nullable),
    "GRAPH_ATTRIBUTE_INVALID", "Invalid attribute declaration.")
  invisible(TRUE)
}

.wb_graph_validate_sql <- function(con, artifact_id, budgets = .wb_graph_budgets()) {
  .wb_graph_backend_assert(con)
  database <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  database_path <- database$file[database$name == "main"][[1L]]
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows WHERE artifact_id=? ",
    "AND octet_length(record_json)>? LIMIT 1;"), params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(!nrow(oversized), "GRAPH_RESOURCE_EXCEEDED", "Stored graph record exceeds decoded budget.")
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_meta WHERE artifact_id=? AND (",
    "COALESCE(octet_length(content_identity_json),0)+COALESCE(octet_length(binding_identity_json),0)+",
    "COALESCE(octet_length(descriptor_json),0)+COALESCE(octet_length(descriptor_identity_json),0)+",
    "COALESCE(octet_length(profile),0)+COALESCE(octet_length(direction_mode),0)+",
    "COALESCE(octet_length(canonical_bytes),0)+COALESCE(octet_length(artifact_id),0)>?) LIMIT 1;"),
    params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(!nrow(oversized), "GRAPH_RESOURCE_EXCEEDED", "Graph identity header exceeds decoded budget.")
  meta <- DBI::dbGetQuery(con, paste0("SELECT * FROM artifact_graph_meta WHERE artifact_id=? AND ",
    "COALESCE(octet_length(content_identity_json),0)+COALESCE(octet_length(binding_identity_json),0)+",
    "COALESCE(octet_length(descriptor_json),0)+COALESCE(octet_length(descriptor_identity_json),0)+",
    "COALESCE(octet_length(profile),0)+COALESCE(octet_length(direction_mode),0)+",
    "COALESCE(octet_length(canonical_bytes),0)+COALESCE(octet_length(artifact_id),0)<=?;"),
    params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(nrow(meta) == 1L && meta$profile[[1]] == "graph_sqlite_v1",
    "GRAPH_VERSION_UNSUPPORTED", "Graph registry missing or unsupported.")
  .wb_graph_require(meta$direction_mode[[1]] %in% c("directed", "undirected", "mixed"),
    "GRAPH_DIRECTION_INVALID", "Invalid stored direction mode.")
  hidden <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows WHERE artifact_id=? AND (",
    "typeof(row_ordinal)!='integer' OR row_ordinal<0 OR component NOT IN (",
    paste0("'", .wb_graph_components(), "'", collapse = ","),
    ") OR NOT json_valid(record_json)) LIMIT 1;"), params = list(artifact_id))
  .wb_graph_require(!nrow(hidden), "GRAPH_ROWS_INVALID", "Hidden/unknown/invalid stored component rows.")
  unique_keys <- list(nodes = "node_id", edges = "edge_id", incidences = "incidence_id",
    attribute_fields = c("scope", "name"), attribute_values = c("scope", "field_ordinal", "entity_ordinal"),
    bindings = "binding_id", binding_mappings = c("binding_id", "node_id"))
  for (component in names(unique_keys)) {
    group <- paste0("json_extract(record_json,'$.", unique_keys[[component]], "')", collapse = ",")
    duplicate <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows ",
      "WHERE artifact_id=? AND component=? GROUP BY ", group, " HAVING COUNT(*)>1 LIMIT 1;"),
      params = list(artifact_id, component))
    .wb_graph_require(!nrow(duplicate), "GRAPH_ID_DUPLICATE", component)
  }
  duplicate <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows ",
    "WHERE artifact_id=? AND component='binding_mappings' GROUP BY ",
    "json_extract(record_json,'$.binding_id'),json_extract(record_json,'$.axis_id') ",
    "HAVING COUNT(*)>1 LIMIT 1;"), params = list(artifact_id))
  .wb_graph_require(!nrow(duplicate), "GRAPH_BINDINGS_INVALID", "Noninjective axis mapping.")
  for (component in .wb_graph_components()) {
    expected <- "0"
    .wb_graph_scan(con, artifact_id, component, function(rows) {
      .wb_graph_require(identical(as.character(rows$row_ordinal), as.character(
        .wb_graph_i64(expected) + bit64::as.integer64(seq_len(nrow(rows)) - 1L))),
        "GRAPH_PART_ORDER_INVALID", "Missing/gapped stored partition rows.")
      for (json in rows$record_json) .wb_graph_row_validate(component, .wb_graph_parse(json))
      expected <<- .wb_graph_add_count(expected, nrow(rows))
    }, page = budgets$partition_rows, bytes = budgets$partition_bytes)
  }
  # The disk join computes arity/counts, not a per-edge in-memory incidence list.
  edge_sql <- paste0("SELECT e.record_json edge_json,COUNT(i.row_ordinal) n,",
    "MIN(json_extract(i.record_json,'$.ordinal')) lo,MAX(json_extract(i.record_json,'$.ordinal')) hi,",
    "SUM(json_extract(i.record_json,'$.role')='tail') tails,",
    "SUM(json_extract(i.record_json,'$.role')='head') heads,",
    "SUM(json_extract(i.record_json,'$.role')='member') members ",
    "FROM artifact_graph_rows e LEFT JOIN artifact_graph_rows i ON i.artifact_id=e.artifact_id ",
    "AND i.component='incidences' AND json_extract(i.record_json,'$.edge_id')=json_extract(e.record_json,'$.edge_id') ",
    "WHERE e.artifact_id=? AND e.component='edges' GROUP BY e.row_ordinal ORDER BY e.row_ordinal;")
  cursor <- DBI::dbSendQuery(con, edge_sql, params = list(artifact_id))
  tryCatch(repeat {
    .wb_graph_transient_admit(budgets, database_path)
    # Each edge can occupy the entire admitted byte partition. A row-count
    # limit alone would permit partition_rows times that memory, especially
    # with whitespace-padded but valid JSON. Keep this aggregate cursor scalar.
    batch <- DBI::dbFetch(cursor, n = 1L)
    if (!nrow(batch)) break
    .wb_graph_storage_fault("edge_aggregate_batch", list(
      rows = nrow(batch), encoded_bytes = sum(nchar(batch$edge_json, type = "bytes"))))
    for (i in seq_len(nrow(batch))) {
      edge <- .wb_graph_parse(batch$edge_json[[i]])
      n <- bit64::as.integer64(batch$n[[i]])
      directed <- edge$direction == "directed"
      ordinary <- edge$kind == "ordinary"
      .wb_graph_require(meta$direction_mode[[1]] == "mixed" ||
        meta$direction_mode[[1]] == edge$direction, "GRAPH_DIRECTION_INVALID", edge$edge_id)
      .wb_graph_require(n > 0 && as.character(batch$lo[[i]]) == "0" &&
        bit64::as.integer64(batch$hi[[i]]) == n - 1,
        "GRAPH_ORDINAL_INVALID", edge$edge_id)
      valid <- if (ordinary && directed) n == 2 && batch$tails[[i]] == 1 &&
        batch$heads[[i]] == 1 else if (ordinary) n == 2 && batch$members[[i]] == 2 else
        if (directed) batch$tails[[i]] > 0 && batch$heads[[i]] > 0 &&
          batch$members[[i]] == 0 else batch$members[[i]] == n
      .wb_graph_require(valid, "GRAPH_ARITY_INVALID", edge$edge_id)
    }
  }, finally = DBI::dbClearResult(cursor))
  # Existence/order are independently checked against indexed durable rows.
  bad <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows i ",
    "LEFT JOIN artifact_graph_rows n ON n.artifact_id=i.artifact_id AND n.component='nodes' ",
    "AND json_extract(n.record_json,'$.node_id')=json_extract(i.record_json,'$.node_id') ",
    "LEFT JOIN artifact_graph_rows e ON e.artifact_id=i.artifact_id AND e.component='edges' ",
    "AND json_extract(e.record_json,'$.edge_id')=json_extract(i.record_json,'$.edge_id') ",
    "WHERE i.artifact_id=? AND i.component='incidences' AND ",
    "(n.row_ordinal IS NULL OR e.row_ordinal IS NULL) LIMIT 1;"), params = list(artifact_id))
  .wb_graph_require(!nrow(bad), "GRAPH_INCIDENCE_DANGLING", "Dangling incidence.")
  order_cursor <- DBI::dbSendQuery(con, paste0("SELECT e.row_ordinal edge_ordinal,",
    "json_extract(i.record_json,'$.ordinal') ordinal,",
    "json_extract(i.record_json,'$.role') role,json_extract(e.record_json,'$.kind') kind,",
    "json_extract(e.record_json,'$.direction') direction FROM artifact_graph_rows i ",
    "JOIN artifact_graph_rows e ON e.artifact_id=i.artifact_id AND e.component='edges' ",
    "AND json_extract(e.record_json,'$.edge_id')=json_extract(i.record_json,'$.edge_id') ",
    "WHERE i.artifact_id=? AND i.component='incidences' ORDER BY i.row_ordinal;"),
    params = list(artifact_id))
  previous_edge <- bit64::as.integer64(-1)
  previous_ordinal <- -1
  tryCatch(repeat {
    .wb_graph_transient_admit(budgets, database_path)
    batch <- DBI::dbFetch(order_cursor, n = budgets$partition_rows)
    if (!nrow(batch)) break
    for (i in seq_len(nrow(batch))) {
      current_edge <- bit64::as.integer64(batch$edge_ordinal[[i]])
      ordinal <- as.numeric(batch$ordinal[[i]])
      .wb_graph_require((current_edge > previous_edge && ordinal == 0) ||
        (current_edge == previous_edge && ordinal == previous_ordinal + 1),
        "GRAPH_ORDER_INVALID", "Incidences do not follow declared edge/ordinal order.")
      if (batch$kind[[i]] == "ordinary" && batch$direction[[i]] == "directed")
        .wb_graph_require(batch$role[[i]] == if (ordinal == 0) "tail" else "head",
          "GRAPH_ROLE_INVALID", "Directed ordinary edge must be tail then head.")
      previous_edge <- current_edge; previous_ordinal <- ordinal
    }
  }, finally = DBI::dbClearResult(order_cursor))
  .wb_graph_validate_sql_attributes(con, artifact_id, budgets)
  invisible(TRUE)
}

.wb_graph_count <- function(con, artifact_id, component) {
  DBI::dbGetQuery(con, paste0("SELECT CAST(COUNT(*) AS TEXT) n FROM artifact_graph_rows ",
    "WHERE artifact_id=? AND component=?;"), params = list(artifact_id, component))$n[[1]]
}

.wb_graph_validate_sql_attributes <- function(con, artifact_id, budgets) {
  expected_fields <- stats::setNames(rep("0", 4), c("graph", "node", "edge", "incidence"))
  counts <- c(graph = "1", node = .wb_graph_count(con, artifact_id, "nodes"),
    edge = .wb_graph_count(con, artifact_id, "edges"),
    incidence = .wb_graph_count(con, artifact_id, "incidences"))
  .wb_graph_scan(con, artifact_id, "attribute_fields", function(rows) {
    for (json in rows$record_json) {
      field <- .wb_graph_parse(json)
      .wb_graph_require(identical(field$field_ordinal, expected_fields[[field$scope]]),
        "GRAPH_ATTRIBUTE_INVALID", "Gapped/reordered field declarations.")
      expected_fields[[field$scope]] <<- .wb_graph_add_count(expected_fields[[field$scope]], 1L)
      expected <- "0"
      .wb_graph_scan(con, artifact_id, "attribute_values", function(values) {
        for (value_json in values$record_json) {
          value <- .wb_graph_parse(value_json)
          .wb_graph_require(.wb_graph_i64(value$entity_ordinal) == .wb_graph_i64(expected) &&
            .wb_graph_scalar(value$value, field$type, field$nullable),
            "GRAPH_ATTRIBUTE_INVALID", field$name)
          expected <<- .wb_graph_add_count(expected, 1L)
        }
      }, page = budgets$partition_rows, bytes = budgets$partition_bytes,
      predicate = "AND json_extract(record_json,'$.scope')=? AND json_extract(record_json,'$.field_ordinal')=?",
      params = list(field$scope, field$field_ordinal))
      .wb_graph_require(identical(expected, counts[[field$scope]]),
        "GRAPH_ATTRIBUTE_INVALID", "Attribute dense coverage mismatch.")
    }
  }, page = budgets$partition_rows, bytes = budgets$partition_bytes)
  bad <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows v ",
    "LEFT JOIN artifact_graph_rows f ON f.artifact_id=v.artifact_id ",
    "AND f.component='attribute_fields' AND json_extract(f.record_json,'$.scope')=json_extract(v.record_json,'$.scope') ",
    "AND json_extract(f.record_json,'$.field_ordinal')=json_extract(v.record_json,'$.field_ordinal') ",
    "WHERE v.artifact_id=? AND v.component='attribute_values' AND f.row_ordinal IS NULL LIMIT 1;"),
    params = list(artifact_id))
  .wb_graph_require(!nrow(bad), "GRAPH_ATTRIBUTE_INVALID", "Undeclared attribute values.")
  invisible(TRUE)
}

.wb_graph_sql_content_hash <- function(con, artifact_id, budgets = .wb_graph_budgets()) {
  .wb_graph_validate_sql(con, artifact_id, budgets)
  scratch_path <- NULL
  if (isTRUE(attr(con, "wb_graph_owned_stage"))) {
    database <- DBI::dbGetQuery(con, "PRAGMA database_list;")
    scratch_path <- database$file[database$name == "main"][[1L]]
  }
  file <- tempfile("scwb_graph_tokens_")
  on.exit(if (file.exists(file)) unlink(file), add = TRUE)
  sink <- file(file, "wb")
  written <- bit64::as.integer64(0)
  observed_spill <- bit64::as.integer64(0)
  emit <- function(token) {
    bytes <- charToRaw(enc2utf8(token))
    written <<- written + bit64::as.integer64(length(bytes))
    .wb_graph_require(!is.na(written) && written <= .wb_graph_i64(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Canonical-token spill budget exceeded.")
    writeBin(bytes, sink)
    if (written - observed_spill >= min(1048576, as.numeric(budgets$token_bytes))) {
      flush(sink); .wb_graph_spill_admit(budgets, scratch_path)
      observed_spill <<- written
    }
  }
  array <- function(component, transform = .wb_graph_parse, predicate = "", params = list()) {
    emit("["); first <- TRUE
    .wb_graph_scan(con, artifact_id, component, function(rows) {
      for (json in rows$record_json) {
        if (!first) emit(",")
        emit(.wb_operation_pack_canonical_json(transform(json)))
        first <<- FALSE
      }
    }, page = budgets$partition_rows, bytes = budgets$partition_bytes,
      predicate = predicate, params = params)
    emit("]")
  }
  tryCatch({
    emit('{"attributes":{')
    first_scope <- TRUE
    for (scope in c("edge", "graph", "incidence", "node")) {
      if (!first_scope) emit(",")
      emit(paste0('"', scope, '":[')); first_field <- TRUE
      .wb_graph_scan(con, artifact_id, "attribute_fields", function(rows) {
        for (json in rows$record_json) {
          field <- .wb_graph_parse(json)
          if (!first_field) emit(",")
          emit(paste0('{"name":', .wb_operation_pack_canonical_json(field$name),
            ',"nullable":', .wb_operation_pack_canonical_json(field$nullable),
            ',"type":', .wb_operation_pack_canonical_json(field$type), ',"values":'))
          array("attribute_values", function(json) .wb_graph_parse(json)$value,
            "AND json_extract(record_json,'$.scope')=? AND json_extract(record_json,'$.field_ordinal')=?",
            list(scope, field$field_ordinal))
          emit("}"); first_field <<- FALSE
        }
      }, page = budgets$partition_rows, bytes = budgets$partition_bytes,
        predicate = "AND json_extract(record_json,'$.scope')=?", params = list(scope))
      emit("]"); first_scope <- FALSE
    }
    mode <- DBI::dbGetQuery(con, "SELECT direction_mode FROM artifact_graph_meta WHERE artifact_id=?;",
      params = list(artifact_id))$direction_mode[[1]]
    emit(paste0('},"direction_mode":', .wb_operation_pack_canonical_json(mode), ',"edges":'))
    array("edges"); emit(',"incidences":'); array("incidences")
    emit(',"nodes":'); array("nodes")
    emit(',"schema":"scworkbench.graph.content.v1"}')
    flush(sink); .wb_graph_spill_admit(budgets, scratch_path)
  }, finally = close(sink))
  input <- file(file, "rb")
  sha <- tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
  list(identity = list(scheme = "scworkbench.graph.content.canonical-json.v1", sha256 = sha),
    canonical_bytes = as.character(written))
}

.wb_graph_stage_small <- function(graph, budgets = list()) {
  admitted <- .wb_graph_budgets(budgets)
  .wb_graph_materialization_admit(list(content = graph$content,
    bindings = graph$associations), admitted$collect_bytes)
  wb_graph_validate(graph)
  state <- .wb_graph_stage_new(graph$content$direction_mode, budgets)
  succeeded <- FALSE
  on.exit(if (!succeeded) .wb_graph_stage_discard(state), add = TRUE)
  append <- function(component, producer) {
    buffer <- list(); bytes <- 0
    flush <- function() {
      if (length(buffer)) .wb_graph_append(state, component, buffer)
      buffer <<- list(); bytes <<- 0
    }
    put <- function(record) {
      n <- nchar(.wb_operation_pack_canonical_json(record), type = "bytes")
      .wb_graph_require(n <= state$budgets$partition_bytes,
        "GRAPH_RESOURCE_EXCEEDED", "Single output record exceeds partition budget.")
      if (length(buffer) >= state$budgets$partition_rows ||
          bytes + n > state$budgets$partition_bytes) flush()
      buffer[[length(buffer) + 1L]] <<- record; bytes <<- bytes + n
    }
    producer(put); flush()
  }
  for (component in c("nodes", "edges", "incidences"))
    append(component, function(put) for (record in graph$content[[component]]) put(record))
  for (component in c("attribute_fields", "attribute_values")) append(component,
    function(put) for (scope in c("graph", "node", "edge", "incidence")) {
    declarations <- graph$content$attributes[[scope]]
    for (i in seq_along(declarations)) {
      field <- declarations[[i]]
      if (component == "attribute_fields") put(list(scope = scope, field_ordinal = as.character(i - 1L),
        name = field$name, type = field$type, nullable = field$nullable)) else
        for (j in seq_along(field$values)) put(list(scope = scope,
          field_ordinal = as.character(i - 1L), entity_ordinal = as.character(j - 1L), value = field$values[[j]]))
    }
  })
  # Associations enter the same streamed tables; authentication is independent.
  append("bindings", function(put) for (i in seq_along(graph$associations)) {
    binding <- graph$associations[[i]]
    put(c(list(binding_ordinal = as.character(i - 1L)), binding[setdiff(names(binding), "mapping")]))
  })
  append("binding_mappings", function(put) for (binding in graph$associations)
    for (j in seq_along(binding$mapping)) put(c(list(binding_id = binding$binding_id,
      mapping_ordinal = as.character(j - 1L)), binding$mapping[[j]])))
  state$content <- .wb_graph_sql_content_hash(state$con, "staged", state$budgets)
  succeeded <- TRUE
  state
}
