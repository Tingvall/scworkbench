test_metadata_identifier_bulk_write_contract <- function() {
  root <- tempfile("scwb_metadata_identifier_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  ids <- paste0("cell_", seq_len(12L))

  md <- data.frame(
    join = rev(ids), v01 = seq_along(ids), v02 = rep(c("A", "B"), 6L),
    v03 = seq_along(ids) + 0.5, v04 = rep(c(TRUE, FALSE), 6L),
    v05 = factor(rep(c("x", "y"), 6L)), v06 = rep(NA_character_, 12L),
    v07 = letters[seq_len(12L)], v08 = LETTERS[seq_len(12L)],
    v09 = seq_along(ids), v10 = seq_along(ids) + 100L,
    v11 = rep("safe", 12L), v12 = rep("reserved", 12L),
    v13 = rep("reserved2", 12L), v14 = rep("empty", 12L),
    v15 = rep("case1", 12L), v16 = rep("case2", 12L),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  names(md) <- c(
    "join key", "space name", "tab\tname", "quote\"name", "apostrophe'name",
    "punct.!?-", "slash/name%", "雪 λ", "select", "x\"; DROP TABLE datasets; --",
    "duplicate", "duplicate", "cell_id", "dataset_id", "", "CaseFold", "casefold"
  )
  wb_define_cells(b, ids, metadata = md, set_name = "core", source = "identifier-contract")

  fields <- wb_metadata_fields(b)
  stopifnot(nrow(fields) == ncol(md) - 1L + 2L)
  stopifnot(all(c(
    "field_id", "source_name", "display_name", "storage_name", "source_position",
    "storage_type", "source_type", "coercion_type", "collision_status",
    "resolution", "import_id", "import_source", "evidence_json"
  ) %in% names(fields)))
  exact_names <- c("space name", "tab\tname", "quote\"name", "apostrophe'name", "punct.!?-", "slash/name%", "雪 λ", "select", "x\"; DROP TABLE datasets; --")
  exact <- fields[fields$source_name %in% exact_names, , drop = FALSE]
  stopifnot(all(exact$source_name == exact$storage_name), all(exact$collision_status == "none"))
  collided <- fields[fields$source_name %in% c("duplicate", "cell_id", "dataset_id", "", "CaseFold", "casefold") & fields$is_core == 0L, , drop = FALSE]
  stopifnot(nrow(collided) == 7L, all(collided$resolution == "stable_storage_rename"))
  stopifnot(all(grepl("^meta:", collided$field_id)), !anyDuplicated(tolower(fields$storage_name)))
  stopifnot(all(c("cells", "datasets", "metadata_fields") %in% DBI::dbListTables(b$con)))

  ambiguous <- try(wb_meta(b, cols = c("cell_id", "duplicate")), silent = TRUE)
  stopifnot(inherits(ambiguous, "try-error"), grepl("stable identities", as.character(ambiguous), fixed = TRUE))
  duplicate_ids <- fields$field_id[fields$source_name == "duplicate"]
  aligned <- wb_meta(b, cells = ids[c(7L, 2L, 11L)], cols = c("cell_id", "space name", duplicate_ids))
  stopifnot(identical(as.character(aligned$cell_id), ids[c(7L, 2L, 11L)]))
  stopifnot(identical(as.integer(aligned[[2L]]), c(6L, 11L, 2L)))
  stopifnot(identical(as.integer(aligned[[3L]]), c(106L, 111L, 102L)))
  stopifnot(identical(as.character(aligned[[4L]]), rep("safe", 3L)))

  cat_sel <- wb_sel_meta(b, "tab\tname", values = "A")
  num_sel <- wb_sel_meta(b, "space name", min = 3L, max = 5L)
  stopifnot(length(cat_sel) == 6L, identical(as.character(num_sel), ids[8:10]))

  update <- data.frame(join = ids[c(2L, 9L)], value = c(200L, 900L), check.names = FALSE)
  names(update)[2L] <- "space name"
  wb_attach_metadata(b, update, cell_ids = ids[c(2L, 9L)], source = "partial-update")
  updated <- wb_meta(b, cells = ids, cols = c("cell_id", "space name"))[[2L]]
  stopifnot(updated[[2L]] == 200L, updated[[9L]] == 900L)

  before <- updated
  incompatible <- data.frame(join = ids[1:2], value = c("lossy", "write"), check.names = FALSE)
  names(incompatible)[2L] <- "space name"
  err <- try(wb_attach_metadata(b, incompatible, cell_ids = ids[1:2]), silent = TRUE)
  stopifnot(inherits(err, "try-error"), identical(before, wb_meta(b, cols = c("cell_id", "space name"))[[2L]]))
  dup_cells <- try(scworkbench:::.wb_write_cell_metadata(b$con, data.frame(id = c(ids[[1L]], ids[[1L]]), z = 1:2)), silent = TRUE)
  unknown <- try(scworkbench:::.wb_write_cell_metadata(b$con, data.frame(id = "not-a-cell", z = 1L)), silent = TRUE)
  stopifnot(inherits(dup_cells, "try-error"), inherits(unknown, "try-error"))
  ingest_dup <- wb_ingest_validate(
    b, set_name = "duplicate-check",
    metadata = data.frame(id = c("new1", "new1"), z = 1:2), strict = FALSE
  )
  stopifnot(!isTRUE(ingest_dup$valid), any(grepl("duplicate", ingest_dup$errors, fixed = TRUE)))
  zero <- scworkbench:::.wb_write_cell_metadata(b$con, data.frame(id = character(), z = integer()))
  stopifnot(identical(zero$n_rows, 0L))

  fields_before <- DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY rowid;")
  columns_before <- DBI::dbListFields(b$con, "cells")
  old_hook <- getOption("scworkbench.metadata_writer_test_hook")
  on.exit(options(scworkbench.metadata_writer_test_hook = old_hook), add = TRUE)
  options(scworkbench.metadata_writer_test_hook = function(event, ...) {
    if (identical(event, "after_values")) stop("injected metadata writer failure", call. = FALSE)
  })
  injected <- try(scworkbench:::.wb_write_cell_metadata(
    b$con, data.frame(id = ids[1:3], `rollback field` = 1:3, check.names = FALSE), source = "fault"
  ), silent = TRUE)
  options(scworkbench.metadata_writer_test_hook = old_hook)
  stopifnot(inherits(injected, "try-error"))
  stopifnot(identical(columns_before, DBI::dbListFields(b$con, "cells")))
  stopifnot(identical(fields_before, DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY rowid;")))
  stopifnot(!("rollback field" %in% DBI::dbListFields(b$con, "cells")))

  nul_runtime <- try(rawToChar(as.raw(c(97L, 0L, 98L))), silent = TRUE)
  stopifnot(inherits(nul_runtime, "try-error"))
  TRUE
}

test_metadata_bulk_writer_scale_contract <- function() {
  root <- tempfile("scwb_metadata_scale_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  n_cells <- 5000L
  n_fields <- 24L
  ids <- sprintf("cell_%05d", seq_len(n_cells))
  wb_define_cells(b, ids)
  md <- data.frame(cell_id = rev(ids), stringsAsFactors = FALSE, check.names = FALSE)
  for (j in seq_len(n_fields)) md[[paste0("bulk field ", j)]] <- as.integer(seq_len(n_cells) + j)
  started <- proc.time()[["elapsed"]]
  report <- scworkbench:::.wb_write_cell_metadata(b$con, md, target_cell_ids = ids, source = "scale-contract")
  elapsed <- proc.time()[["elapsed"]] - started
  stopifnot(identical(report$statement_complexity, "O(metadata_fields)"))
  stopifnot(identical(report$complexity, "O(metadata_rows * metadata_fields * log(bundle_cells))"))
  stopifnot(identical(report$staging_index_strategy, "TEMP TABLE cell_id TEXT PRIMARY KEY"))
  plan <- unlist(lapply(report$query_plan, function(x) as.character(x$detail)), use.names = FALSE)
  stopifnot(any(grepl("USING INDEX|USING COVERING INDEX", plan)),
            !any(grepl("SCAN s$", plan)))
  stopifnot(report$statement_count <= 4L * n_fields + 4L)
  stopifnot(report$statement_count < n_cells * n_fields)
  probe <- wb_meta(b, cells = ids[c(1L, n_cells)], cols = c("cell_id", "bulk field 1", paste0("bulk field ", n_fields)))
  stopifnot(identical(as.character(probe$cell_id), ids[c(1L, n_cells)]))
  stopifnot(identical(as.integer(probe[[2L]]), c(n_cells + 1L, 2L)))
  attr(report, "fixture") <- c(n_cells = n_cells, n_fields = n_fields)
  attr(report, "elapsed_seconds") <- elapsed
  TRUE
}

test_metadata_bulk_writer_large_universe_contract <- function() {
  root <- tempfile("scwb_metadata_large_universe_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  n_cells <- 120895L
  ids <- sprintf("cell_%06d", seq_len(n_cells))
  wb_define_cells(b, ids)
  set.seed(270605L)
  permuted <- sample(ids)
  ordinal <- match(permuted, ids)
  md <- data.frame(
    cell_id = permuted,
    stage = c("egg", "larva", "pupa", "adult")[1L + ordinal %% 4L],
    replicate = sprintf("rep_%02d", 1L + ordinal %% 12L),
    role = c("worker", "queen", "drone")[1L + ordinal %% 3L],
    library = sprintf("lib_%02d", 1L + ordinal %% 9L),
    batch = as.integer(1L + ordinal %% 5L),
    qc_pass = ordinal %% 7L != 0L,
    umi_total = as.integer(ordinal * 3L),
    detected = as.integer(100L + ordinal %% 12000L),
    score = as.numeric(ordinal) / n_cells,
    note = ifelse(ordinal %% 2L == 0L, "even", NA_character_),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  gc(reset = TRUE)
  started <- proc.time()[["elapsed"]]
  report <- scworkbench:::.wb_write_cell_metadata(
    b$con, md, target_cell_ids = ids, source = "large-universe-contract"
  )
  elapsed <- proc.time()[["elapsed"]] - started
  gc_evidence <- gc()
  memory_mb <- max(gc_evidence[, "max used"] * c(56, 8) / (1024^2))
  stopifnot(report$n_rows == n_cells, nrow(report$fields) == 10L,
            report$statement_count <= 4L * 10L + 4L,
            identical(report$statement_complexity, "O(metadata_fields)"),
            identical(report$staging_index_strategy, "TEMP TABLE cell_id TEXT PRIMARY KEY"))
  plan <- unlist(lapply(report$query_plan, function(x) as.character(x$detail)), use.names = FALSE)
  stopifnot(any(grepl("USING INDEX|USING COVERING INDEX", plan)), !any(grepl("SCAN s$", plan)))
  probe_idx <- unique(c(1L, 2L, n_cells %/% 2L, n_cells - 1L, n_cells))
  probe <- wb_meta(b, cells = ids[probe_idx], cols = c("cell_id", "stage", "batch", "qc_pass", "umi_total", "score"))
  stopifnot(identical(as.character(probe$cell_id), ids[probe_idx]),
            identical(as.character(probe$stage), c("egg", "larva", "pupa", "adult")[1L + probe_idx %% 4L]),
            identical(as.integer(probe$batch), as.integer(1L + probe_idx %% 5L)),
            identical(as.integer(probe$umi_total), as.integer(probe_idx * 3L)),
            isTRUE(all.equal(as.numeric(probe$score), as.numeric(probe_idx) / n_cells)))
  before_fields <- DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY rowid;")
  old_hook <- getOption("scworkbench.metadata_writer_test_hook")
  on.exit(options(scworkbench.metadata_writer_test_hook = old_hook), add = TRUE)
  options(scworkbench.metadata_writer_test_hook = function(event, ...) {
    if (identical(event, "after_staging")) stop("forced large-stage rollback", call. = FALSE)
  })
  failed <- try(scworkbench:::.wb_write_cell_metadata(
    b$con, data.frame(cell_id = permuted, rollback_large = ordinal),
    target_cell_ids = ids, source = "forced-large-rollback"
  ), silent = TRUE)
  options(scworkbench.metadata_writer_test_hook = old_hook)
  stopifnot(inherits(failed, "try-error"),
            identical(before_fields, DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY rowid;")),
            !("rollback_large" %in% DBI::dbListFields(b$con, "cells")))
  partial_ids <- ids[c(3L, n_cells %/% 2L, n_cells - 2L)]
  partial <- data.frame(cell_id = rev(partial_ids), stage = c("new_last", "new_mid", "new_first"))
  partial_report <- scworkbench:::.wb_write_cell_metadata(b$con, partial, target_cell_ids = partial_ids, source = "partial-large")
  stopifnot(partial_report$n_rows == 3L,
            identical(as.character(wb_meta(b, cells = partial_ids, cols = c("cell_id", "stage"))$stage),
                      c("new_first", "new_mid", "new_last")))
  message(sprintf("large metadata evidence: rows=%d fields=%d statements=%d elapsed=%.3fs peak_gc=%.1fMiB",
                  n_cells, 10L, report$statement_count, elapsed, memory_mb))
  TRUE
}

test_metadata_field_deep_validation_contract <- function() {
  roots <- character()
  on.exit(unlink(roots, recursive = TRUE, force = TRUE), add = TRUE)
  make_case <- function() {
    root <- tempfile("scwb_metadata_validation_")
    roots <<- c(roots, root)
    b <- wb_init_bundle(root, overwrite = TRUE)
    wb_define_cells(b, c("c1", "c2"), metadata = data.frame(id = c("c1", "c2"), field = 1:2))
    wb_refresh_manifest(b); wb_finalize_recipient_bundle(b); wb_close_bundle(b)
    stopifnot(isTRUE(wb_bundle_validation_report(root, level = "content")$ok))
    root
  }
  corrupt <- function(root, sql) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "db", "app.sqlite"))
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con, sql)
  }
  missing_root <- make_case()
  corrupt(missing_root, "DELETE FROM metadata_fields WHERE field_id='meta:000001';")
  missing <- wb_bundle_validation_report(missing_root, level = "content")
  stopifnot(!isTRUE(missing$ok), "METADATA_FIELD_MAPPING_MISSING" %in% missing$diagnostics$code)

  dangling_root <- make_case()
  corrupt(dangling_root, "UPDATE metadata_fields SET storage_name='absent_column' WHERE field_id='meta:000001';")
  dangling <- wb_bundle_validation_report(dangling_root, level = "content")
  stopifnot(!isTRUE(dangling$ok), "METADATA_FIELD_MAPPING_DANGLING" %in% dangling$diagnostics$code)

  non_resolvable_root <- make_case()
  corrupt(non_resolvable_root, "UPDATE metadata_fields SET field_id='' WHERE field_id='meta:000001';")
  non_resolvable <- wb_bundle_validation_report(non_resolvable_root, level = "content")
  stopifnot(!isTRUE(non_resolvable$ok), "METADATA_FIELD_NON_RESOLVABLE" %in% non_resolvable$diagnostics$code)

  core_root <- make_case()
  corrupt(core_root, "UPDATE metadata_fields SET is_core=0 WHERE field_id='core:dataset_id';")
  core <- wb_bundle_validation_report(core_root, level = "content")
  stopifnot(!isTRUE(core$ok), "METADATA_FIELD_CORE_CONFLICT" %in% core$diagnostics$code)
  TRUE
}
