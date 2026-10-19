# Native matrix fragment-tree.v2 is an R.serializeJSON identity, NOT canonical
# JSON v1. This private verifier reproduces its bytes without materializing axes.
.wb_graph_native_list_start <- function(emit, fields = NULL) {
  attributes <- if (is.null(fields)) "{}" else paste0('{"names":',
    jsonlite::serializeJSON(fields, digits = NA), "}")
  emit(paste0('{"type":"list","attributes":', attributes, ',"value":['))
}

.wb_graph_native_scalar <- function(emit, value) {
  emit(enc2utf8(jsonlite::serializeJSON(value, digits = NA)))
}

.wb_graph_native_text <- function(con, rowid, column, emit, budgets, observer = NULL) {
  # Incremental raw bytes become complete UTF-8 codepoints before serialization.
  # Raw axis-JSON whitespace/escapes remain identity-bearing.
  stopifnot(column %in% c("matrix_id", "storage", "feature_ids_json",
    "cell_ids_json", "source", "description"))
  reader <- .wb_matrix_native_text_reader(con, rowid, column, budgets, observer)
  if (reader$is_null) return(.wb_graph_native_scalar(emit, NA_character_))
  emit('{"type":"character","attributes":{},"value":["')
  prefix <- '{"type":"character","attributes":{},"value":["'
  suffix <- '"]}'
  repeat {
    chunk <- reader$next_chunk()
    if (is.null(chunk)) break
    escaped <- enc2utf8(jsonlite::serializeJSON(chunk, digits = NA))
    .wb_graph_require(startsWith(escaped, prefix) && endsWith(escaped, suffix),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Unsupported native text serialization.")
    emit(substr(escaped, nchar(prefix) + 1L, nchar(escaped) - nchar(suffix)))
  }
  emit(suffix)
}

.wb_graph_native_tree_entries <- function(root, budgets, reserve_bytes = 0) {
  # Charge names, C buffers, R strings/vectors, recursive traversal and native
  # sort copies BEFORE allocation. Existing cache/partition reservations remain.
  .wb_graph_require(typeof(reserve_bytes) %in% c("integer", "double") &&
    is.null(attributes(reserve_bytes)) && !is.object(reserve_bytes) &&
    length(reserve_bytes) == 1L && !is.na(reserve_bytes) &&
    is.finite(reserve_bytes) && reserve_bytes >= 0, "GRAPH_RESOURCE_POLICY_INVALID",
    "Invalid private traversal workspace reservation.")
  allowance <- as.numeric(budgets$memory_bytes) - budgets$sqlite_cache_kib * 1024 -
    8 * budgets$partition_bytes - 65536 - .wb_graph_fd_metadata_reservation(budgets) - reserve_bytes
  .wb_graph_require(allowance > 0, "GRAPH_RESOURCE_EXCEEDED",
    "No working reservation remains for native file-name metadata.")
  used <- 0; entries <- list()
  children <- function(directory) {
    rows <- tryCatch(.Call(C_scwb_graph_source_directory, directory, allowance - used),
      error = function(error) {
        code <- if (startsWith(conditionMessage(error), "GRAPH_RESOURCE_EXCEEDED:"))
          "GRAPH_RESOURCE_EXCEEDED" else "GRAPH_SOURCE_PAYLOAD_INVALID"
        .wb_graph_error(code, conditionMessage(error))
      })
    used <<- used + rows[[2L]]
    lapply(rows[[1L]], function(name) {
      entry <- file.path(directory, name)
      .wb_graph_require(identical(as.character(fs::path(entry)), entry),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Native fs path normalization changes a source file-name.")
      .wb_graph_require(!is.na(iconv(entry, from = "UTF-8", to = "UTF-8")),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Native source file-name is not valid UTF-8.")
      entry
    })
  }
  # Iterative depth-first traversal avoids an unbounded R call stack on deep
  # trees. Name/stack/list/sort reservations are included in each entry charge.
  pending <- rev(children(root))
  while (length(pending)) {
    index <- length(pending)
    entry <- pending[[index]]; pending[[index]] <- NULL
    entries[[length(entries) + 1L]] <- entry
    if (dir.exists(entry) && !nzchar(Sys.readlink(entry)))
      pending <- c(pending, rev(children(entry)))
  }
  # fs uses byte-ordered per-directory preorder; preserve that initial ordering
  # before base R's locale-sensitive, potentially tied native sort.
  sort(as.character(unlist(entries, use.names = FALSE)))
}

.wb_graph_native_tree_hash <- function(bundle, relative, budgets) {
  status <- .wb_path_status(bundle$dir, relative, expected_type = "either",
    must_exist = TRUE, purpose = "native matrix graph source")
  .wb_graph_require(isTRUE(status$ok), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Native matrix source payload is missing or outside its contained root.")
  root <- normalizePath(status$absolute, winslash = "/", mustWork = TRUE)
  if (!dir.exists(root)) return(.wb_prov_sha256_file(root))
  entries <- .wb_graph_native_tree_entries(root, budgets)
  # The issuing stage may contain exact committed leaf links. Reuse the accepted
  # stage trust rule, but retain native R sort (the v3 stage helper uses radix).
  source <- bundle$staging_source_bundle %||% NULL
  for (entry in entries) {
    resolved <- normalizePath(entry, winslash = "/", mustWork = TRUE)
    if (!.wb_path_inside(resolved, root)) {
      suffix <- substring(entry, nchar(root) + 2L)
      expected <- if (inherits(source, "scworkbench_bundle"))
        .wb_path_status(source$dir, file.path(relative, suffix), expected_type = "file",
          must_exist = TRUE, purpose = "native committed matrix leaf") else NULL
      .wb_graph_require(!dir.exists(entry) && nzchar(Sys.readlink(entry)) &&
        !is.null(expected) && isTRUE(expected$ok) && identical(resolved, expected$absolute),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Native matrix source tree contains an unauthorized escaped entry.")
    }
  }
  .wb_graph_token_hash(function(emit) {
    .wb_graph_native_list_start(emit)
    first <- TRUE
    for (entry in entries) if (!dir.exists(entry)) {
      if (!first) emit(",")
      .wb_graph_native_scalar(emit, list(path = substring(entry, nchar(root) + 2L),
        sha256 = .wb_prov_sha256_file(entry)))
      first <- FALSE
    }
    emit("]}")
  }, budgets)
}

.wb_graph_native_numeric_type <- function(con, matrix_id, column) {
  stopifnot(column %in% c("n_cells", "n_features"))
  type <- DBI::dbGetQuery(con, paste0("SELECT ",
    "COALESCE(MAX(typeof(", column, ") NOT IN ('null','integer','real')),0) invalid,",
    "COALESCE(MAX(typeof(", column, ")='real'),0) real,",
    "COALESCE(MAX(typeof(", column, ")='integer' AND (", column,
      ">2147483647 OR ", column, "<-2147483648)),0) wide ",
    "FROM matrix_fragments WHERE matrix_id=?;"), params = list(matrix_id))
  .wb_graph_require(type$invalid[[1L]] == 0L, "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Native matrix dimension has an invalid SQLite type.")
  .wb_graph_require(!(type$real[[1L]] && type$wide[[1L]]), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Mixed wide-integer and REAL dimensions have order-dependent native RSQLite coercion.")
  if (type$real[[1L]]) "numeric" else if (type$wide[[1L]]) "integer64" else "integer"
}

.wb_graph_native_matrix_identity <- function(bundle, matrix_id, budgets = .wb_graph_budgets()) {
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore_budget <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  on.exit(restore_budget(), add = TRUE)
  .wb_graph_require(.wb_graph_string(matrix_id), "GRAPH_SOURCE_PAYLOAD_INVALID", "Invalid matrix source ID.")
  observer <- .wb_matrix_native_byte_observer(con)
  if (!is.null(observer)) on.exit(observer$close(), add = TRUE)
  # A first pass reproduces RSQLite's whole-query numeric column promotion.
  # A late REAL or wide INTEGER must alter every row's native typed preimage.
  types <- stats::setNames(lapply(c("n_features", "n_cells"), function(column)
    .wb_graph_native_numeric_type(con, matrix_id, column)), c("n_features", "n_cells"))
  columns <- c("matrix_id", "storage", "n_features", "n_cells",
    "feature_ids_json", "cell_ids_json", "source", "description")
  invalid <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM matrix_fragments WHERE matrix_id=? AND (",
    "typeof(fragment_id)!='text' OR typeof(path)!='text' OR ",
    "typeof(created_at)!='text' OR octet_length(created_at)>256 OR ",
    "COALESCE(octet_length(fragment_id),0)+COALESCE(octet_length(path),0)+512>?) LIMIT 1;"),
    params = list(matrix_id, budgets$partition_bytes))
  .wb_graph_require(!nrow(invalid), "GRAPH_RESOURCE_EXCEEDED",
    "Matrix fragment selector/path/sort key exceeds admission before decoding.")
  # RSQLite permits one live result per connection. Save only bounded selectors
  # to private scratch, then close the source cursor before chunk queries. This
  # also preserves the original getter's created_at-only order, including ties.
  selectors_path <- tempfile("scwb_graph_identity_matrix_", fileext = ".sqlite")
  selectors <- DBI::dbConnect(RSQLite::SQLite(), selectors_path)
  on.exit({DBI::dbDisconnect(selectors); unlink(selectors_path)}, add = TRUE)
  DBI::dbExecute(selectors, "PRAGMA cache_size=-64;")
  DBI::dbExecute(selectors, "PRAGMA temp_store=FILE;")
  DBI::dbExecute(selectors, "CREATE TABLE selected (ordinal INTEGER PRIMARY KEY, source_rowid INTEGER NOT NULL);")
  cursor <- DBI::dbSendQuery(con,
    "SELECT rowid FROM matrix_fragments WHERE matrix_id=? ORDER BY created_at ASC;",
    params = list(matrix_id))
  ordinal <- bit64::as.integer64(0)
  tryCatch(repeat {
    row <- DBI::dbFetch(cursor, 1L)
    if (!nrow(row)) break
    DBI::dbExecute(selectors, "INSERT INTO selected VALUES(?,?);", params = list(ordinal, row$rowid[[1L]]))
    ordinal <- ordinal + bit64::as.integer64(1)
    .wb_graph_spill_admit(budgets, selectors_path)
  }, finally = DBI::dbClearResult(cursor))
  count <- "0"
  sha <- .wb_graph_token_hash(function(emit) {
    .wb_graph_native_list_start(emit, c("kind", "matrix_id", "fragments"))
    .wb_graph_native_scalar(emit, "matrix"); emit(",")
    .wb_graph_native_scalar(emit, matrix_id); emit(",")
    .wb_graph_native_list_start(emit)
    # Deliberately no tie breaker: this is the getter's created_at ASC order.
    cursor <- DBI::dbSendQuery(selectors, "SELECT source_rowid FROM selected ORDER BY ordinal;")
    tryCatch(repeat {
      selected <- DBI::dbFetch(cursor, 1L)
      if (!nrow(selected)) break
      row <- DBI::dbGetQuery(con, paste0("SELECT rowid native_rowid,fragment_id,path,n_features,n_cells ",
        "FROM matrix_fragments WHERE matrix_id=? AND rowid=? AND ",
        "COALESCE(octet_length(fragment_id),0)+COALESCE(octet_length(path),0)+512<=?;"),
        params = list(matrix_id, selected$source_rowid[[1L]], budgets$partition_bytes))
      .wb_graph_require(nrow(row) == 1L, "GRAPH_SOURCE_PAYLOAD_INVALID", "Admitted matrix fragment changed.")
      if (count != "0") emit(",")
      .wb_graph_native_list_start(emit, c("fragment", "payload_sha256"))
      .wb_graph_native_list_start(emit, columns)
      for (index in seq_along(columns)) {
        column <- columns[[index]]
        if (index != 1L) emit(",")
        if (column %in% names(types)) {
          value <- row[[column]]
          value <- switch(types[[column]], numeric = as.numeric(value),
            integer64 = bit64::as.integer64(value), integer = as.integer(value))
          .wb_graph_native_scalar(emit, value)
        } else .wb_graph_native_text(con, row$native_rowid[[1L]], column, emit, budgets, observer)
      }
      emit("]},")
      .wb_graph_native_scalar(emit, .wb_graph_native_tree_hash(bundle, row$path[[1L]], budgets))
      emit("]}")
      count <<- .wb_graph_add_count(count, 1L)
    }, finally = DBI::dbClearResult(cursor))
    emit("]}]}")
  }, budgets, selectors_path)
  .wb_graph_require(count != "0", "GRAPH_SOURCE_UNAVAILABLE", "Matrix has no retained fragments.")
  if (!is.null(observer)) observer$finish()
  list(scheme = "scworkbench.content.matrix.fragment-tree.v2", sha256 = sha)
}
