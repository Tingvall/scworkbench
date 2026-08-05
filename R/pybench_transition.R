# Authoritative R-side isolation, mutation audit, and publication for PyBench v2.

.wb_pybench_rows_sha256 <- function(rows) {
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  columns <- sort(names(rows), method = "radix")
  rows <- rows[, columns, drop = FALSE]
  if (nrow(rows) > 1L) {
    rows <- rows[do.call(order, c(unname(rows), list(na.last = FALSE, method = "radix"))), , drop = FALSE]
  }
  token <- function(value) {
    value <- enc2utf8(as.character(value))
    paste0(nchar(value, type = "bytes"), ":", value)
  }
  stream <- c("scworkbench-sqlite-rows-v2\n", paste0("C", length(columns), "\n"))
  if (length(columns)) stream <- c(stream, vapply(columns, token, character(1)))
  stream <- c(stream, paste0("R", nrow(rows), "\n"))
  if (nrow(rows) && length(columns)) {
    stream <- c(stream, unlist(lapply(seq_len(nrow(rows)), function(i) {
      vapply(rows[i, , drop = TRUE], token, character(1))
    }), use.names = FALSE))
  }
  digest::digest(paste0(stream, collapse = ""), algo = "sha256", serialize = FALSE)
}

.wb_pybench_db_snapshot <- function(con) {
  schema <- DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;")
  tables <- as.character(schema$name[schema$type == "table"])
  rows <- stats::setNames(lapply(tables, function(table) {
    info <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
    cols <- as.character(info$name)
    order <- if (length(cols)) paste(vapply(cols, function(x) paste0("src.", as.character(DBI::dbQuoteIdentifier(con, x))), character(1)), collapse = ",") else "src.rowid"
    from <- paste0(DBI::dbQuoteIdentifier(con, table), " AS src")
    value <- DBI::dbGetQuery(con, paste0("SELECT src.* FROM ", from, " ORDER BY ", order, ";"))
    type_expr <- vapply(cols, function(column) {
      quoted <- as.character(DBI::dbQuoteIdentifier(con, column))
      paste0("typeof(", quoted, ") AS ", quoted)
    }, character(1))
    canonical_expr <- vapply(cols, function(column) {
      quoted <- as.character(DBI::dbQuoteIdentifier(con, column))
      paste0(
        "CASE typeof(", quoted, ") ",
        "WHEN 'null' THEN 'null:' ",
        "WHEN 'integer' THEN 'integer:' || printf('%lld',", quoted, ") ",
        "WHEN 'real' THEN NULL ",
        "WHEN 'text' THEN 'text:' || hex(CAST(", quoted, " AS BLOB)) ",
        "WHEN 'blob' THEN 'blob:' || hex(", quoted, ") END AS ", quoted
      )
    }, character(1))
    canonical <- if (length(canonical_expr)) {
      DBI::dbGetQuery(con, paste0("SELECT ", paste(canonical_expr, collapse = ","), " FROM ",
                                  from, " ORDER BY ", order, ";"))
    } else data.frame()
    types <- if (length(type_expr)) {
      DBI::dbGetQuery(con, paste0("SELECT ", paste(type_expr, collapse = ","), " FROM ",
                                  from, " ORDER BY ", order, ";"))
    } else data.frame()
    for (column in cols) {
      real <- identical(nrow(types), nrow(value)) & as.character(types[[column]]) == "real"
      if (!any(real)) next
      canonical[[column]][real] <- vapply(as.numeric(value[[column]][real]), function(number) {
        bytes <- writeBin(as.double(number), raw(), size = 8L, endian = "big")
        paste0("real:", paste(sprintf("%02X", as.integer(bytes)), collapse = ""))
      }, character(1))
    }
    list(row_count = nrow(value), content_sha256 = .wb_prov_sha256_object(value),
         rows = value, canonical_rows = canonical)
  }), tables)
  list(schema = schema, schema_sha256 = .wb_prov_sha256_object(schema), tables = rows)
}

.wb_pybench_payload_snapshot <- function(root, ignore_manifest = TRUE) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  db_rel <- ""
  manifest <- try(jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE), silent = TRUE)
  if (!inherits(manifest, "try-error")) db_rel <- as.character(manifest$storage$sqlite$path %||% "")[1]
  ignored <- c(".scworkbench-pybench-stage.json", db_rel, paste0(db_rel, c("-wal", "-shm", "-journal")))
  if (isTRUE(ignore_manifest)) ignored <- c(ignored, "manifest.json")
  out <- list()
  walk <- function(dir, prefix = "") {
    kids <- list.files(dir, recursive = FALSE, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    for (path in sort(kids)) {
      rel <- gsub("\\\\", "/", if (nzchar(prefix)) file.path(prefix, basename(path)) else basename(path))
      if (rel %in% ignored || grepl("(^|/)\\.scworkbench-writer\\.lock($|/)", rel)) next
      link <- Sys.readlink(path)
      if (nzchar(link)) {
        # Do not traverse a directory link: a hostile target may escape or
        # recurse back into the transition tree.
        out[[rel]] <<- list(type = "symlink", content_sha256 = .wb_prov_sha256_object("symlink"))
      } else if (dir.exists(path)) {
        out[[rel]] <<- list(type = "dir", content_sha256 = .wb_prov_sha256_object(character()))
        walk(path, rel)
      } else if (file.exists(path)) {
        out[[rel]] <<- list(type = "file", content_sha256 = .wb_prov_sha256_file(path))
      }
    }
  }
  walk(root)
  out[sort(names(out))]
}

.wb_pybench_source_snapshot <- function(stage_bundle) {
  source <- as.character(stage_bundle$staging_source_dir %||% "")[1]
  if (!nzchar(source) || !dir.exists(source)) return(NULL)
  manifest <- jsonlite::read_json(file.path(source, "manifest.json"), simplifyVector = TRUE)
  db_rel <- as.character(manifest$storage$sqlite$path)[1]
  db_files <- c(db_rel, paste0(db_rel, c("-wal", "-shm")))
  db <- list()
  for (rel in db_files) if (file.exists(file.path(source, rel))) {
    db[[rel]] <- .wb_prov_sha256_file(file.path(source, rel))
  }
  list(db = db, payload = .wb_pybench_payload_snapshot(source, ignore_manifest = TRUE))
}

.wb_pybench_clone_bundle <- function(bundle) {
  root <- tempfile("pybench_transition_")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  status <- system2("cp", c("-aL", "--reflink=auto", shQuote(paste0(normalizePath(bundle$dir, winslash = "/", mustWork = TRUE), "/.")), shQuote(root)))
  .wb_assert(identical(as.integer(status), 0L), "PYBENCH_TRANSITION_FAILED: could not create isolated staging transition")
  manifest <- jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE)
  db_rel <- as.character(manifest$storage$sqlite$path)[1]
  for (suffix in c("", "-wal", "-shm", "-journal")) unlink(file.path(root, paste0(db_rel, suffix)), force = TRUE)
  .wb_session_sqlite_backup(bundle$con, file.path(root, db_rel))
  transition <- wb_open_bundle(root, validate = FALSE)
  transition$staging_source_dir <- bundle$staging_source_dir
  transition$pybench_session_binding <- bundle$pybench_session_binding
  list(root = root, bundle = transition)
}

.wb_pybench_write_stage_marker <- function(root, request) {
  cap <- request$execution_capability
  marker <- list(
    schema = "scworkbench.pybench.stage.v2",
    protocol_version = .wb_pyproto_version(),
    capability_id = cap$capability_id,
    session_id = cap$session_id,
    run_id = cap$run_id,
    source_attestation = cap$source_attestation,
    staging_identity = cap$staging_identity
  )
  path <- file.path(root, ".scworkbench-pybench-stage.json")
  jsonlite::write_json(marker, path, auto_unbox = TRUE, pretty = FALSE, null = "null")
  invisible(path)
}

.wb_pybench_scope_rows <- function(snapshot, descriptor, canonical = FALSE) {
  table <- as.character(descriptor$table)[1]
  tab <- snapshot$tables[[table]]
  .wb_assert(!is.null(tab), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: allowed table is absent: ", table))
  rows <- tab$rows
  column <- as.character(descriptor$key_scope$column)[1]
  .wb_assert(column %in% names(rows), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: key column is absent: ", table, ".", column))
  values <- as.character(descriptor$key_scope$values)
  selected <- as.character(rows[[column]]) %in% values
  out <- if (isTRUE(canonical)) tab$canonical_rows[selected, , drop = FALSE] else rows[selected, , drop = FALSE]
  rownames(out) <- NULL
  out
}

.wb_pybench_payload_matches <- function(rel, allowed) {
  prefix <- sub("/+$", "", as.character(allowed$path)[1])
  stem <- basename(prefix)
  sibling <- basename(rel)
  extension_form <- identical(dirname(rel), dirname(prefix)) &&
    startsWith(sibling, paste0(stem, ".")) &&
    grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", substring(sibling, nchar(stem) + 2L))
  identical(rel, prefix) || startsWith(rel, paste0(prefix, "/")) || extension_form
}

.wb_pybench_audit_mutations <- function(pre_db, post_db, pre_payload, post_payload, request) {
  .wb_assert(identical(pre_db$schema_sha256, post_db$schema_sha256),
             "PYBENCH_OUT_OF_SCOPE_MUTATION: SQLite schema changed")
  allow <- request$execution_capability$write_allowlist %||% list()
  sqlite_allow <- Filter(function(x) identical(as.character(x$mutation_class), "sqlite_rows"), allow)
  payload_allow <- Filter(function(x) identical(as.character(x$mutation_class), "payload_tree"), allow)
  descriptors <- list()

  changed_tables <- union(names(pre_db$tables), names(post_db$tables))
  changed_tables <- changed_tables[vapply(changed_tables, function(x) {
    !identical(pre_db$tables[[x]]$content_sha256 %||% "", post_db$tables[[x]]$content_sha256 %||% "")
  }, logical(1))]
  for (table in changed_tables) {
    candidates <- Filter(function(x) identical(as.character(x$table), table), sqlite_allow)
    .wb_assert(length(candidates) > 0L, paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: undeclared SQLite table mutation: ", table))
    key_columns <- unique(vapply(candidates, function(x) as.character(x$key_scope$column)[1], character(1)))
    .wb_assert(length(key_columns) == 1L,
               paste0("PYBENCH_CAPABILITY_MISMATCH: table allowances use incompatible key columns: ", table))
    column <- key_columns[[1]]
    values <- unique(unlist(lapply(candidates, function(x) as.character(x$key_scope$values)), use.names = FALSE))
    full_pre <- pre_db$tables[[table]]$rows
    full_post <- post_db$tables[[table]]$rows
    .wb_assert(column %in% names(full_pre) && column %in% names(full_post),
               paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: key column is absent: ", table, ".", column))
    outside_pre <- full_pre[!as.character(full_pre[[column]]) %in% values, , drop = FALSE]
    outside_post <- full_post[!as.character(full_post[[column]]) %in% values, , drop = FALSE]
    rownames(outside_pre) <- NULL; rownames(outside_post) <- NULL
    .wb_assert(identical(outside_pre, outside_post), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: sibling rows changed in ", table))
    for (allowed in candidates) {
      pre_rows <- .wb_pybench_scope_rows(pre_db, allowed)
      post_rows <- .wb_pybench_scope_rows(post_db, allowed)
      if (!identical(pre_rows, post_rows)) {
        d <- allowed
        d$row_count <- as.integer(nrow(post_rows))
        d$content_sha256 <- .wb_pybench_rows_sha256(.wb_pybench_scope_rows(post_db, allowed, canonical = TRUE))
        descriptors[[length(descriptors) + 1L]] <- d
      }
    }
  }

  paths <- union(names(pre_payload), names(post_payload))
  changed_paths <- paths[vapply(paths, function(x) !identical(pre_payload[[x]] %||% NULL, post_payload[[x]] %||% NULL), logical(1))]
  for (rel in changed_paths) {
    .wb_assert(!identical(as.character((post_payload[[rel]] %||% list())$type %||% ""), "symlink"),
               paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: symlink payload mutation is forbidden: ", rel))
    candidates <- Filter(function(x) .wb_pybench_payload_matches(rel, x), payload_allow)
    .wb_assert(length(candidates) == 1L, paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: undeclared or ambiguous payload mutation: ", rel))
    allowed <- candidates[[1]]
    d <- allowed
    d$path <- rel
    d$row_count <- 0L
    d$content_sha256 <- as.character((post_payload[[rel]] %||% list(content_sha256 = .wb_prov_sha256_object(NULL)))$content_sha256)[1]
    descriptors[[length(descriptors) + 1L]] <- d
  }
  descriptors
}

.wb_pybench_manifest_key <- function(x) paste(.wb_pyproto_descriptor_key(x), as.integer(x$row_count), as.character(x$content_sha256), sep = "\r")

.wb_pybench_verify_receipt_audit <- function(receipt, observed) {
  reported <- receipt$write_manifest %||% list()
  reported_keys <- sort(vapply(reported, .wb_pybench_manifest_key, character(1)))
  observed_keys <- sort(vapply(observed, .wb_pybench_manifest_key, character(1)))
  if (!identical(reported_keys, observed_keys)) {
    missing <- setdiff(observed_keys, reported_keys)
    extra <- setdiff(reported_keys, observed_keys)
    summarize <- function(x) {
      if (!length(x)) return("none")
      paste(vapply(strsplit(head(x, 3L), "\r", fixed = TRUE), function(parts) {
        paste0(paste(head(parts, max(1L, length(parts) - 1L)), collapse = "/"),
               "#", substr(tail(parts, 1L), 1L, 12L))
      }, character(1)), collapse = ", ")
    }
    stop("PYBENCH_RECEIPT_MISMATCH: receipt write manifest differs from authoritative R audit; ",
         "missing_observed=", summarize(missing), "; extra_reported=", summarize(extra), call. = FALSE)
  }
  invisible(TRUE)
}

.wb_pybench_publish_transition <- function(source, destination, pre_payload, post_payload) {
  RSQLite::sqliteCopyDatabase(source$con, destination$con)
  paths <- union(names(pre_payload), names(post_payload))
  changed <- paths[vapply(paths, function(x) !identical(pre_payload[[x]] %||% NULL, post_payload[[x]] %||% NULL), logical(1))]
  for (rel in changed) {
    src <- file.path(source$dir, rel)
    dst <- file.path(destination$dir, rel)
    status <- .wb_path_status(destination$dir, rel, expected_type = "either", must_exist = FALSE, purpose = "PyBench audited publication")
    .wb_assert(isTRUE(status$ok), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: unsafe publication path: ", rel))
    if (!file.exists(src) && !dir.exists(src)) { unlink(dst, recursive = TRUE, force = TRUE); next }
    if (file.exists(dst) || dir.exists(dst)) unlink(dst, recursive = TRUE, force = TRUE)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    ok <- if (dir.exists(src)) {
      file.copy(src, dirname(dst), recursive = TRUE, copy.mode = TRUE, copy.date = TRUE)
    } else {
      file.copy(src, dst, recursive = FALSE, copy.mode = TRUE, copy.date = TRUE)
    }
    .wb_assert(isTRUE(ok), paste0("PYBENCH_TRANSITION_FAILED: failed to publish audited payload: ", rel))
  }
  invisible(TRUE)
}

.wb_pybench_execute_isolated <- function(module, request, bundle, python_bin, env, request_path, receipt_path) {
  mode <- as.character(request$execution_capability$mode)[1]
  .wb_assert(!is.null(bundle) && inherits(bundle, "scworkbench_bundle"), "PyBench v2 execution requires an engine bundle handle")
  if (identical(mode, "read_only")) {
    source_db <- .wb_pybench_db_snapshot(bundle$con)
    source_payload <- .wb_pybench_payload_snapshot(bundle$dir)
    cloned <- .wb_pybench_clone_bundle(bundle)
    on.exit({
      try(wb_close_bundle(cloned$bundle), silent = TRUE)
      unlink(cloned$root, recursive = TRUE, force = TRUE)
    }, add = TRUE)
    pre_db <- .wb_pybench_db_snapshot(cloned$bundle$con)
    pre_payload <- .wb_pybench_payload_snapshot(cloned$root)
    request$bundle_dir <- normalizePath(cloned$root, winslash = "/", mustWork = TRUE)
    result <- .wb_pybench_run_module(module, request, bundle = NULL, python_bin = python_bin, env = env,
                                     request_path = request_path, receipt_path = receipt_path, isolated = FALSE)
    post_db <- .wb_pybench_db_snapshot(cloned$bundle$con)
    post_payload <- .wb_pybench_payload_snapshot(cloned$root)
    .wb_assert(identical(pre_db$schema_sha256, post_db$schema_sha256) && identical(pre_db$tables, post_db$tables) && identical(pre_payload, post_payload),
               "PYBENCH_SOURCE_WRITE_ATTEMPT: read-only subprocess changed bundle state")
    .wb_assert(identical(source_db, .wb_pybench_db_snapshot(bundle$con)) &&
                 identical(source_payload, .wb_pybench_payload_snapshot(bundle$dir)),
               "PYBENCH_SOURCE_WRITE_ATTEMPT: committed source changed during read-only execution")
    .wb_assert(length(result$receipt$write_manifest %||% list()) == 0L, "PYBENCH_RECEIPT_MISMATCH: read-only receipt reported writes")
    return(result)
  }
  .wb_assert(nzchar(as.character(bundle$staging_source_dir %||% "")[1]),
             "PYBENCH_SOURCE_WRITE_ATTEMPT: staging_write cannot target a committed bundle")
  binding <- bundle$pybench_session_binding %||% list()
  cap <- request$execution_capability
  .wb_assert(identical(as.character(cap$session_id), as.character(binding$session_id)) &&
               identical(as.character(cap$staging_identity$root_sha256), as.character(binding$root_sha256)) &&
               identical(as.character(cap$staging_identity$checkpoint_generation), as.character(binding$checkpoint_generation)),
             "PYBENCH_STALE_STAGING_IDENTITY: request is not bound to the current session stage generation")
  source_before <- .wb_pybench_source_snapshot(bundle)
  pre_db <- .wb_pybench_db_snapshot(bundle$con)
  cloned <- .wb_pybench_clone_bundle(bundle)
  on.exit({
    try(wb_close_bundle(cloned$bundle), silent = TRUE)
    unlink(cloned$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  pre_payload <- .wb_pybench_payload_snapshot(cloned$root)
  request$bundle_dir <- normalizePath(cloned$root, winslash = "/", mustWork = TRUE)
  .wb_pybench_write_stage_marker(cloned$root, request)
  result <- .wb_pybench_run_module(module, request, bundle = cloned$bundle, python_bin = python_bin, env = env,
                                   request_path = request_path, receipt_path = receipt_path, isolated = FALSE)
  .wb_pyproto_validate_receipt(result$receipt, request)
  post_db <- .wb_pybench_db_snapshot(cloned$bundle$con)
  post_payload <- .wb_pybench_payload_snapshot(cloned$root)
  observed <- .wb_pybench_audit_mutations(pre_db, post_db, pre_payload, post_payload, request)
  .wb_pybench_verify_receipt_audit(result$receipt, observed)
  .wb_assert(identical(source_before, .wb_pybench_source_snapshot(bundle)),
             "PYBENCH_SOURCE_WRITE_ATTEMPT: committed source changed during subprocess execution")
  hook <- getOption("scworkbench.pybench_transition_fault_hook", NULL)
  if (is.function(hook)) hook("after_receipt_before_publication")
  .wb_pybench_publish_transition(cloned$bundle, bundle, pre_payload, post_payload)
  result$request <- request
  result$observed_write_manifest <- observed
  result
}
