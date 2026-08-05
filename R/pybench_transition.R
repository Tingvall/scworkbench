# Authoritative R-side isolation, mutation audit, and publication for PyBench v2.

.wb_pybench_rows_sha256 <- function(rows) {
  rows <- as.data.frame(rows, stringsAsFactors = FALSE)
  if (length(names(rows))) rows <- rows[, sort(names(rows)), drop = FALSE]
  canonical <- jsonlite::toJSON(rows, dataframe = "rows", auto_unbox = TRUE,
                                digits = NA, na = "null", null = "null", pretty = FALSE)
  digest::digest(as.character(canonical), algo = "sha256", serialize = FALSE)
}

.wb_pybench_db_snapshot <- function(con) {
  schema <- DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;")
  tables <- as.character(schema$name[schema$type == "table"])
  rows <- stats::setNames(lapply(tables, function(table) {
    info <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
    cols <- as.character(info$name)
    order <- if (length(cols)) paste(vapply(cols, function(x) as.character(DBI::dbQuoteIdentifier(con, x)), character(1)), collapse = ",") else "rowid"
    value <- DBI::dbGetQuery(con, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), " ORDER BY ", order, ";"))
    list(row_count = nrow(value), content_sha256 = .wb_prov_sha256_object(value), rows = value)
  }), tables)
  list(schema = schema, schema_sha256 = .wb_prov_sha256_object(schema), tables = rows)
}

.wb_pybench_payload_snapshot <- function(root, ignore_manifest = TRUE) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  rels <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE, include.dirs = TRUE)
  rels <- gsub("\\\\", "/", rels)
  rels <- rels[!grepl("(^|/)\\.scworkbench-writer\\.lock($|/)", rels)]
  if (isTRUE(ignore_manifest)) rels <- setdiff(rels, "manifest.json")
  db_rel <- ""
  manifest <- try(jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE), silent = TRUE)
  if (!inherits(manifest, "try-error")) db_rel <- as.character(manifest$storage$sqlite$path %||% "")[1]
  rels <- setdiff(rels, c(db_rel, paste0(db_rel, c("-wal", "-shm", "-journal"))))
  out <- list()
  for (rel in sort(rels)) {
    path <- file.path(root, rel)
    link <- Sys.readlink(path)
    if (nzchar(link)) {
      # Hash linked content, not the host path stored in the link target.
      if (dir.exists(path)) next
      out[[rel]] <- list(type = "file", content_sha256 = .wb_prov_sha256_file(path))
    } else if (dir.exists(path)) {
      out[[rel]] <- list(type = "dir", content_sha256 = .wb_prov_sha256_object(character()))
    } else if (file.exists(path)) {
      out[[rel]] <- list(type = "file", content_sha256 = .wb_prov_sha256_file(path))
    }
  }
  out
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

.wb_pybench_scope_rows <- function(snapshot, descriptor) {
  table <- as.character(descriptor$table)[1]
  tab <- snapshot$tables[[table]]
  .wb_assert(!is.null(tab), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: allowed table is absent: ", table))
  rows <- tab$rows
  column <- as.character(descriptor$key_scope$column)[1]
  .wb_assert(column %in% names(rows), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: key column is absent: ", table, ".", column))
  values <- as.character(descriptor$key_scope$values)
  rows[as.character(rows[[column]]) %in% values, , drop = FALSE]
}

.wb_pybench_payload_matches <- function(rel, allowed) {
  prefix <- sub("/+$", "", as.character(allowed$path)[1])
  identical(rel, prefix) || startsWith(rel, paste0(prefix, "/")) ||
    (identical(dirname(rel), dirname(prefix)) && startsWith(basename(rel), basename(prefix)))
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
    covered_pre <- covered_post <- logical(0)
    for (allowed in candidates) {
      pre_rows <- .wb_pybench_scope_rows(pre_db, allowed)
      post_rows <- .wb_pybench_scope_rows(post_db, allowed)
      full_pre <- pre_db$tables[[table]]$rows
      full_post <- post_db$tables[[table]]$rows
      column <- as.character(allowed$key_scope$column)[1]
      values <- as.character(allowed$key_scope$values)
      outside_pre <- full_pre[!as.character(full_pre[[column]]) %in% values, , drop = FALSE]
      outside_post <- full_post[!as.character(full_post[[column]]) %in% values, , drop = FALSE]
      .wb_assert(identical(outside_pre, outside_post), paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: sibling rows changed in ", table))
      if (!identical(pre_rows, post_rows)) {
        d <- allowed
        d$row_count <- as.integer(nrow(post_rows))
        d$content_sha256 <- .wb_pybench_rows_sha256(post_rows)
        descriptors[[length(descriptors) + 1L]] <- d
      }
    }
  }

  paths <- union(names(pre_payload), names(post_payload))
  changed_paths <- paths[vapply(paths, function(x) !identical(pre_payload[[x]] %||% NULL, post_payload[[x]] %||% NULL), logical(1))]
  for (rel in changed_paths) {
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
  .wb_assert(identical(sort(vapply(reported, .wb_pybench_manifest_key, character(1))),
                       sort(vapply(observed, .wb_pybench_manifest_key, character(1)))),
             "PYBENCH_RECEIPT_MISMATCH: receipt write manifest differs from authoritative R audit")
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
    ok <- file.copy(src, dst, recursive = TRUE, copy.mode = TRUE, copy.date = TRUE)
    .wb_assert(isTRUE(ok), paste0("PYBENCH_TRANSITION_FAILED: failed to publish audited payload: ", rel))
  }
  invisible(TRUE)
}

.wb_pybench_execute_isolated <- function(module, request, bundle, python_bin, env, request_path, receipt_path) {
  mode <- as.character(request$execution_capability$mode)[1]
  .wb_assert(!is.null(bundle) && inherits(bundle, "scworkbench_bundle"), "PyBench v2 execution requires an engine bundle handle")
  if (identical(mode, "read_only")) {
    pre_db <- .wb_pybench_db_snapshot(bundle$con)
    pre_payload <- .wb_pybench_payload_snapshot(bundle$dir)
    result <- .wb_pybench_run_module(module, request, bundle = NULL, python_bin = python_bin, env = env,
                                     request_path = request_path, receipt_path = receipt_path, isolated = FALSE)
    post_db <- .wb_pybench_db_snapshot(bundle$con)
    post_payload <- .wb_pybench_payload_snapshot(bundle$dir)
    .wb_assert(identical(pre_db$schema_sha256, post_db$schema_sha256) && identical(pre_db$tables, post_db$tables) && identical(pre_payload, post_payload),
               "PYBENCH_SOURCE_WRITE_ATTEMPT: read-only subprocess changed bundle state")
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
  pre_payload <- .wb_pybench_payload_snapshot(bundle$dir)
  cloned <- .wb_pybench_clone_bundle(bundle)
  on.exit({
    try(wb_close_bundle(cloned$bundle), silent = TRUE)
    unlink(cloned$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  request$bundle_dir <- normalizePath(cloned$root, winslash = "/", mustWork = TRUE)
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
