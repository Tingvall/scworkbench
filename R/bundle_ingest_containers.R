# Canonical ingestion from dominant single-cell containers into bundle state.

.wb_ingest_version <- function() "v1"

.wb_ingest_source_object <- function(input, class_label) {
  source_path <- NULL
  obj <- input
  if (is.character(input) && length(input) == 1L) {
    source_path <- normalizePath(input, winslash = "/", mustWork = TRUE)
    obj <- readRDS(source_path)
  }
  list(object = obj, source_path = source_path, class_label = class_label)
}

.wb_ingest_clean_id <- function(x, fallback = "object") {
  x <- as.character(x %||% fallback)[1]
  x <- gsub("[^A-Za-z0-9_.-]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  if (!nzchar(x)) fallback else x
}

.wb_ingest_promote_staged_bundle <- function(stage_dir, final_dir, source_type, overwrite = FALSE) {
  .wb_with_bundle_writer_lock(final_dir, operation = paste0(source_type, " staged ingestion publication"), code = {
    .wb_ingest_promote_staged_bundle_locked(stage_dir, final_dir, source_type, overwrite = overwrite)
  })
}

.wb_ingest_promote_staged_bundle_locked <- function(stage_dir, final_dir, source_type, overwrite = FALSE) {
  stage_manifest_path <- .wb_bundle_path_require(stage_dir,"manifest.json",expected_type="file",purpose="staged ingestion manifest")
  stage_manifest <- jsonlite::read_json(stage_manifest_path, simplifyVector = TRUE)
  if (dir.exists(final_dir)) {
    .wb_assert(isTRUE(overwrite), paste0("bundle_dir exists: ", final_dir, " (set overwrite=TRUE)"))
    unlink(final_dir, recursive = TRUE, force = TRUE)
  }
  if (!isTRUE(file.rename(stage_dir, final_dir))) {
    stop("Failed to promote staged ", source_type, " bundle to final bundle_dir: ", final_dir, call. = FALSE)
  }

  bundle <- wb_open_bundle(final_dir)
  final_id <- basename(normalizePath(final_dir, winslash = "/", mustWork = FALSE))
  id_policy <- bundle$manifest$id_policy %||% list()
  id_policy$staging_provenance <- list(
    source_type = as.character(source_type),
    staging_bundle_id = as.character(stage_manifest$bundle_id %||% NA_character_)[1],
    staging_bundle_name = as.character(stage_manifest$bundle_name %||% NA_character_)[1],
    staging_dir_basename = basename(stage_dir)
  )
  bundle$manifest$bundle_id <- final_id
  bundle$manifest$bundle_name <- final_id
  bundle$manifest$id_policy <- id_policy
  bundle$manifest$creation$bundle_id <- final_id
  bundle$manifest$creation$bundle_name <- final_id
  bundle$manifest$creation$id_policy <- id_policy
  .wb_with_mutation_context(
    bundle = bundle, route = "ingestion",
    code = wb_refresh_manifest(bundle)
  )
  bundle
}

.wb_ingest_as_metadata_df <- function(x, row_ids, id_col = "cell_id") {
  if (is.null(x)) {
    out <- data.frame(stringsAsFactors = FALSE)
  } else {
    out <- as.data.frame(x, stringsAsFactors = FALSE, optional = TRUE)
  }
  if (nrow(out) == 0L && length(row_ids) > 0L) {
    out <- data.frame(.row = seq_along(row_ids), stringsAsFactors = FALSE)
    out$.row <- NULL
  }
  if (nrow(out) != length(row_ids)) {
    stop("metadata row count does not match object cells/features.", call. = FALSE)
  }
  for (j in seq_len(ncol(out))) {
    val <- out[[j]]
    if (is.factor(val)) val <- as.character(val)
    if (is.logical(val)) val <- as.integer(val)
    if (is.list(val) && !is.data.frame(val)) {
      val <- vapply(val, function(z) jsonlite::toJSON(.wb_json_sanitize(z), auto_unbox = TRUE, null = "null"), character(1))
    }
    if (!is.atomic(val)) val <- as.character(val)
    out[[j]] <- val
  }
  key <- data.frame(as.character(row_ids), stringsAsFactors = FALSE, check.names = FALSE)
  names(key) <- id_col
  cbind(key, out, stringsAsFactors = FALSE)
}

.wb_ingest_dataset_id <- function(metadata, dataset_col, n) {
  if (!is.null(dataset_col) && dataset_col %in% names(metadata)) {
    return(as.character(metadata[[dataset_col]]))
  }
  if ("orig.ident" %in% names(metadata)) return(as.character(metadata[["orig.ident"]]))
  rep("dataset_1", n)
}

.wb_ingest_cell_id_repair <- function(cell_ids,
                                      duplicate_cell_id_policy = c("error", "make_unique"),
                                      original_id_col = "original_cell_id") {
  duplicate_cell_id_policy <- match.arg(duplicate_cell_id_policy)
  raw <- as.character(cell_ids %||% character(0))
  .wb_assert(length(raw) > 0L, "cell_ids empty after cleaning")
  empty <- is.na(raw) | !nzchar(raw)
  if (any(empty)) {
    raw[empty] <- paste0("cell_", which(empty))
  }
  dup_mask <- duplicated(raw) | duplicated(raw, fromLast = TRUE)
  n_duplicate_rows <- sum(dup_mask)
  duplicate_ids <- unique(raw[dup_mask])
  duplicate_ids <- duplicate_ids[nzchar(duplicate_ids)]

  final <- raw
  if (length(duplicate_ids)) {
    if (identical(duplicate_cell_id_policy, "error")) {
      stop(
        "Duplicate cell IDs detected during container ingestion (duplicate rows=",
        n_duplicate_rows,
        ", duplicate IDs=",
        length(duplicate_ids),
        "). Re-run with duplicate_cell_id_policy='make_unique' to make deterministic unique IDs while preserving original IDs in metadata.",
        call. = FALSE
      )
    }
    final <- make.unique(raw, sep = ".")
  }

  .wb_assert(!anyDuplicated(final), "cell ID repair failed to produce unique cell_ids.")
  list(
    cell_ids = final,
    original_cell_ids = raw,
    policy = duplicate_cell_id_policy,
    duplicate_rows = as.integer(n_duplicate_rows),
    duplicate_ids = as.character(duplicate_ids),
    original_id_col = as.character(original_id_col %||% "original_cell_id")[1]
  )
}

.wb_ingest_feature_id_repair <- function(feature_ids,
                                         duplicate_feature_id_policy = c("error", "make_unique"),
                                         original_id_col = "original_feature_id") {
  duplicate_feature_id_policy <- match.arg(duplicate_feature_id_policy)
  raw <- as.character(feature_ids %||% character(0))
  .wb_assert(length(raw) > 0L, "feature_ids empty after cleaning")
  empty <- is.na(raw) | !nzchar(raw)
  if (any(empty)) {
    raw[empty] <- paste0("feature_", which(empty))
  }
  dup_mask <- duplicated(raw) | duplicated(raw, fromLast = TRUE)
  n_duplicate_rows <- sum(dup_mask)
  duplicate_ids <- unique(raw[dup_mask])
  duplicate_ids <- duplicate_ids[nzchar(duplicate_ids)]

  final <- raw
  if (length(duplicate_ids)) {
    if (identical(duplicate_feature_id_policy, "error")) {
      stop(
        "Duplicate feature IDs detected during container ingestion (duplicate rows=",
        n_duplicate_rows,
        ", duplicate IDs=",
        length(duplicate_ids),
        "). Re-run with duplicate_feature_id_policy='make_unique' to make deterministic unique IDs while preserving original IDs in feature metadata.",
        call. = FALSE
      )
    }
    final <- make.unique(raw, sep = ".")
  }

  .wb_assert(!anyDuplicated(final), "feature ID repair failed to produce unique feature_ids.")
  list(
    feature_ids = final,
    original_feature_ids = raw,
    policy = duplicate_feature_id_policy,
    duplicate_rows = as.integer(n_duplicate_rows),
    duplicate_ids = as.character(duplicate_ids),
    original_id_col = as.character(original_id_col %||% "original_feature_id")[1]
  )
}

.wb_ingest_categorical_cols <- function(metadata, categorical_cols = NULL, max_levels = 50L) {
  cand <- setdiff(names(metadata), c("cell_id", "dataset_id"))
  if (!is.null(categorical_cols)) return(intersect(as.character(categorical_cols), cand))
  keep <- vapply(cand, function(nm) {
    x <- metadata[[nm]]
    if (is.numeric(x) && !is.integer(x)) return(FALSE)
    ux <- unique(as.character(x[!is.na(x)]))
    length(ux) >= 1L && length(ux) <= max_levels
  }, logical(1))
  cand[keep]
}

.wb_ingest_label_cell_sets <- function(bundle,
                                       metadata,
                                       categorical_cols = NULL,
                                       prefix = "label",
                                       source = "container_ingest",
                                       created_by = NULL,
                                       max_levels = 50L) {
  cols <- .wb_ingest_categorical_cols(metadata, categorical_cols = categorical_cols, max_levels = max_levels)
  made <- character(0)
  if (!length(cols)) return(made)
  for (col in cols) {
    x <- as.character(metadata[[col]])
    vals <- sort(unique(x[!is.na(x) & nzchar(x)]))
    if (!length(vals) || length(vals) > max_levels) next
    for (val in vals) {
      set_id <- paste0(prefix, "_", .wb_ingest_clean_id(col, "label"), "__", .wb_ingest_clean_id(val, "value"))
      cells <- as.character(metadata$cell_id[x == val & !is.na(x)])
      wb_cell_set_replace(
        bundle = bundle,
        cell_set = set_id,
        cell_ids = cells,
        source = source,
        created_by = created_by,
        description = paste0("Imported categorical label ", col, "=", val),
        strict = TRUE
      )
      made <- c(made, paste0("set:", set_id))
    }
  }
  unique(made)
}

.wb_container_ingest_report_artifact <- function(bundle,
                                                source_type,
                                                source_path = NULL,
                                                assays_imported = character(0),
                                                spaces_imported = character(0),
                                                categorical_sets = character(0),
                                                rowdata_artifact_id = NA_character_,
                                                unsupported = list(),
                                                cell_id_policy = NULL,
                                                feature_id_policy = NULL,
                                                status = "completed",
                                                phase = "completed",
                                                created_by = NULL,
                                                matrix_ids = character(0),
                                                source_identity = NULL) {
  .wb_require_pkg("jsonlite", "container ingestion report")
  if (!exists(".wb_promote_obs_table", mode = "function")) return(NA_character_)
  cell_id_policy <- cell_id_policy %||% list(
    duplicate_cell_id_policy = NA_character_,
    duplicate_cell_id_rows = NA_integer_,
    duplicate_cell_id_unique_values = NA_integer_,
    original_cell_id_column = NA_character_
  )
  feature_id_policy <- feature_id_policy %||% list(
    duplicate_feature_id_policy = NA_character_,
    duplicate_feature_id_rows = NA_integer_,
    duplicate_feature_id_unique_values = NA_integer_,
    original_feature_id_column = NA_character_
  )
  tbl <- data.frame(
    importer = "scworkbench_container_ingest",
    importer_version = .wb_ingest_version(),
    ingestion_status = as.character(status %||% "completed")[1],
    phase_reached = as.character(phase %||% "completed")[1],
    source_type = source_type,
    source_path = source_path %||% NA_character_,
    assays_imported_json = jsonlite::toJSON(as.character(assays_imported), auto_unbox = TRUE, null = "null"),
    spaces_imported_json = jsonlite::toJSON(as.character(spaces_imported), auto_unbox = TRUE, null = "null"),
    categorical_sets_json = jsonlite::toJSON(as.character(categorical_sets), auto_unbox = TRUE, null = "null"),
    rowdata_artifact_id = rowdata_artifact_id %||% NA_character_,
    duplicate_cell_id_policy = as.character(cell_id_policy$duplicate_cell_id_policy %||% NA_character_)[1],
    duplicate_cell_id_rows = as.integer(cell_id_policy$duplicate_cell_id_rows %||% NA_integer_)[1],
    duplicate_cell_id_unique_values = as.integer(cell_id_policy$duplicate_cell_id_unique_values %||% NA_integer_)[1],
    original_cell_id_column = as.character(cell_id_policy$original_cell_id_column %||% NA_character_)[1],
    duplicate_feature_id_policy = as.character(feature_id_policy$duplicate_feature_id_policy %||% NA_character_)[1],
    duplicate_feature_id_rows = as.integer(feature_id_policy$duplicate_feature_id_rows %||% NA_integer_)[1],
    duplicate_feature_id_unique_values = as.integer(feature_id_policy$duplicate_feature_id_unique_values %||% NA_integer_)[1],
    original_feature_id_column = as.character(feature_id_policy$original_feature_id_column %||% NA_character_)[1],
    unsupported_json = jsonlite::toJSON(.wb_json_sanitize(unsupported), auto_unbox = TRUE, null = "null"),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE
  )
  prim <- wb_prim_obs_table(
    table = tbl,
    table_type = "container_ingest_report",
    entity_kind = "ingest",
    meta = list(source_type = source_type, importer_version = .wb_ingest_version())
  )
  space_outputs <- if (length(spaces_imported)) {
    stats::setNames(
      lapply(as.character(spaces_imported), wb_prim_space),
      paste0("space_", as.character(spaces_imported))
    )
  } else list()
  run <- wb_new_run(
    op_name = paste0("bundle_ingest_", tolower(gsub("[^A-Za-z0-9]+", "_", source_type))),
    inputs = list(
      cell_set = "all", parents = character(0),
      provenance_refs = if (!is.na(as.character(rowdata_artifact_id %||% NA_character_)[1]) && nzchar(as.character(rowdata_artifact_id %||% "")[1])) list(wb_ref_artifact(rowdata_artifact_id, "feature_metadata")) else list(),
      user_inputs = list(source_path = source_path)
    ),
    params = list(importer_version = .wb_ingest_version(), cell_id_policy = cell_id_policy, feature_id_policy = feature_id_policy, status = status, phase = phase),
    outputs = c(list(ingest_report = prim), space_outputs),
    notes = "Container ingestion report"
  )
  artifact_id <- .wb_promote_obs_table(
    bundle = bundle,
    run = run,
    out_name = "ingest_report",
    prim = prim,
    name = "container_ingest_report",
    description = "Container ingestion metadata and v1 unsupported field summary",
    created_by = created_by,
    parent_artifacts = if (!is.na(as.character(rowdata_artifact_id %||% NA_character_)[1]) && nzchar(as.character(rowdata_artifact_id %||% "")[1])) list(wb_ref_artifact(rowdata_artifact_id, "feature_metadata")) else list()
  )
  .wb_prov_record_ingestion(
    bundle = bundle, run = run, artifact_id = artifact_id,
    matrix_ids = matrix_ids, created_by = created_by, source_identity = source_identity
  )
  wb_refresh_manifest(bundle)
  artifact_id
}

.wb_ingest_failure_marker <- function(bundle_dir,
                                      source_type,
                                      source_path = NULL,
                                      phase = NULL,
                                      error = NULL,
                                      details = list()) {
  .wb_with_bundle_writer_lock(bundle_dir, operation = paste0(source_type, " ingestion failure publication"), code = {
    .wb_ingest_failure_marker_locked(bundle_dir, source_type, source_path, phase, error, details)
  })
}

.wb_ingest_failure_marker_locked <- function(bundle_dir,
                                             source_type,
                                             source_path = NULL,
                                             phase = NULL,
                                             error = NULL,
                                             details = list()) {
  .wb_require_pkg("jsonlite", "container ingestion failure marker")
  if (dir.exists(bundle_dir)) unlink(bundle_dir, recursive = TRUE, force = TRUE)
  dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
  marker <- list(
    ingestion_status = "failed",
    importer = "scworkbench_container_ingest",
    importer_version = .wb_ingest_version(),
    source_type = source_type,
    source_path = source_path %||% NA_character_,
    phase_reached = phase %||% NA_character_,
    error = error %||% NA_character_,
    details = details %||% list(),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  writeLines(
    jsonlite::toJSON(.wb_json_sanitize(marker), auto_unbox = TRUE, pretty = TRUE, null = "null"),
    con = file.path(bundle_dir, "INGEST_FAILED.json"),
    useBytes = TRUE
  )
  invisible(file.path(bundle_dir, "INGEST_FAILED.json"))
}

.wb_ingest_feature_metadata_artifact <- function(bundle, feature_metadata, source_type, matrix_id, created_by = NULL) {
  if (is.null(feature_metadata) || !nrow(feature_metadata) || !exists(".wb_promote_feature_table", mode = "function")) {
    return(NA_character_)
  }
  tbl <- as.data.frame(feature_metadata, stringsAsFactors = FALSE, check.names = FALSE)
  if (!("feature_id" %in% names(tbl))) names(tbl)[1] <- "feature_id"
  tbl$feature_id <- as.character(tbl$feature_id)
  prim <- wb_prim_feature_table(
    table = tbl,
    table_type = "container_feature_metadata",
    meta = list(source_type = source_type, matrix_id = matrix_id, importer_version = .wb_ingest_version())
  )
  run <- wb_new_run(
    op_name = "bundle_ingest_feature_metadata",
    inputs = list(cell_set = "all", parents = character(0), user_inputs = list(source_type = source_type)),
    params = list(matrix_id = matrix_id),
    outputs = list(feature_metadata = prim),
    notes = "Container feature metadata import"
  )
  artifact_id <- .wb_promote_feature_table(
    bundle = bundle,
    run = run,
    out_name = "feature_metadata",
    prim = prim,
    name = paste0(matrix_id, "_feature_metadata"),
    description = paste0("Feature metadata imported from ", source_type),
    created_by = created_by,
    parent_artifacts = list()
  )
  .wb_prov_record_ingestion_substep(bundle, run, artifact_id, created_by = created_by)
  wb_refresh_manifest(bundle)
  artifact_id
}

.wb_ingest_10x_read_tsv <- function(path, col_names) {
  .wb_assert(file.exists(path), paste0("10x file not found: ", path))
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, open = "rt") else file(path, open = "rt")
  on.exit(close(con), add = TRUE)
  out <- utils::read.delim(
    con,
    header = FALSE,
    sep = "\t",
    stringsAsFactors = FALSE,
    quote = "",
    comment.char = "",
    check.names = FALSE
  )
  if (ncol(out) < length(col_names)) {
    for (i in seq_len(length(col_names) - ncol(out))) out[[ncol(out) + 1L]] <- NA_character_
  }
  names(out)[seq_along(col_names)] <- col_names
  out
}

.wb_ingest_10x_mtx_metadata <- function(path) {
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, open = "rt") else file(path, open = "rt")
  on.exit(close(con), add = TRUE)
  lines <- character(0)
  dims <- c(n_rows = NA_integer_, n_cols = NA_integer_, n_nonzero = NA_integer_)
  repeat {
    x <- readLines(con, n = 1L, warn = FALSE)
    if (!length(x)) break
    if (!startsWith(x, "%")) {
      parts <- strsplit(trimws(x), "\\s+")[[1]]
      if (length(parts) >= 3L) dims <- stats::setNames(as.integer(parts[1:3]), names(dims))
      break
    }
    lines <- c(lines, x)
    if (length(lines) > 1000L) break
  }
  meta_line <- grep("^%metadata_json:", lines, value = TRUE)
  if (!length(meta_line)) return(list(comments = lines, metadata_json = NULL, dims = dims))
  js <- sub("^%metadata_json:\\s*", "", meta_line[[1]])
  parsed <- tryCatch(jsonlite::fromJSON(js, simplifyVector = TRUE), error = function(e) NULL)
  list(comments = lines, metadata_json = parsed, dims = dims)
}

.wb_ingest_10x_read_mtx <- function(path) {
  .wb_assert(file.exists(path), paste0("10x matrix file not found: ", path))
  con <- if (grepl("\\.gz$", path, ignore.case = TRUE)) gzfile(path, open = "rt") else file(path, open = "rt")
  on.exit(close(con), add = TRUE)
  mat <- Matrix::readMM(con)
  if (!inherits(mat, "dgCMatrix")) mat <- methods::as(methods::as(mat, "CsparseMatrix"), "dgCMatrix")
  mat
}

.wb_ingest_10x_triplet_dirs <- function(input) {
  input <- normalizePath(input, winslash = "/", mustWork = TRUE)
  all_files <- list.files(input, recursive = TRUE, full.names = TRUE)
  base <- basename(all_files)

  find_one <- function(pattern) {
    all_files[grepl(pattern, base, ignore.case = TRUE)]
  }

  barcodes <- find_one("(^|_)barcodes\\.tsv(\\.gz)?$")
  features <- find_one("(^|_)(features|genes)\\.tsv(\\.gz)?$")
  matrices <- find_one("(^|_)matrix\\.mtx(\\.gz)?$")

  if (!length(barcodes) || !length(features) || !length(matrices)) {
    stop("No complete 10x Matrix Market triplets found under input directory: ", input, call. = FALSE)
  }

  prefix_for <- function(path, suffix_pattern) {
    x <- basename(path)
    x <- sub(suffix_pattern, "", x, ignore.case = TRUE)
    if (!nzchar(x)) basename(dirname(path)) else x
  }
  btab <- data.frame(prefix = vapply(barcodes, prefix_for, character(1), suffix_pattern = "(_)?barcodes\\.tsv(\\.gz)?$"), barcodes_path = barcodes, stringsAsFactors = FALSE)
  ftab <- data.frame(prefix = vapply(features, prefix_for, character(1), suffix_pattern = "(_)?(features|genes)\\.tsv(\\.gz)?$"), features_path = features, stringsAsFactors = FALSE)
  mtab <- data.frame(prefix = vapply(matrices, prefix_for, character(1), suffix_pattern = "(_)?matrix\\.mtx(\\.gz)?$"), matrix_path = matrices, stringsAsFactors = FALSE)
  tab <- merge(merge(btab, ftab, by = "prefix"), mtab, by = "prefix")
  if (!nrow(tab)) stop("No complete 10x Matrix Market triplets could be matched by file prefix.", call. = FALSE)
  tab$sample_id <- vapply(tab$prefix, .wb_ingest_clean_id, character(1), fallback = "sample")

  parts <- strsplit(as.character(tab$sample_id), "_", fixed = TRUE)
  tab$gsm <- vapply(parts, function(x) if (length(x) && grepl("^GSM[0-9]+$", x[[1]])) x[[1]] else NA_character_, character(1))
  tab$replicate <- vapply(parts, function(x) {
    hit <- grep("^R[0-9]+$", x, value = TRUE)
    if (length(hit)) sub("^R", "", hit[[1]]) else NA_character_
  }, character(1))
  known_stage <- c("Pupa", "Nurse", "Forager")
  tab$stage <- vapply(parts, function(x) {
    hit <- x[tolower(x) %in% tolower(known_stage)]
    if (length(hit)) known_stage[match(tolower(hit[[1]]), tolower(known_stage))] else NA_character_
  }, character(1))

  tab[, c("sample_id", "matrix_path", "barcodes_path", "features_path", setdiff(names(tab), c("sample_id", "matrix_path", "barcodes_path", "features_path", "prefix"))), drop = FALSE]
}

.wb_ingest_10x_sample_table <- function(input, sample_table = NULL) {
  if (!is.null(sample_table)) {
    tab <- as.data.frame(sample_table, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    .wb_assert(is.character(input) && length(input) == 1L && dir.exists(input), "input must be a 10x triplet directory when sample_table is NULL")
    tab <- .wb_ingest_10x_triplet_dirs(input)
  }
  required <- c("sample_id", "matrix_path", "barcodes_path", "features_path")
  missing <- setdiff(required, names(tab))
  .wb_assert(!length(missing), paste0("sample_table missing required columns: ", paste(missing, collapse = ", ")))
  for (nm in required) tab[[nm]] <- as.character(tab[[nm]])
  tab$sample_id <- vapply(tab$sample_id, .wb_ingest_clean_id, character(1), fallback = "sample")
  .wb_assert(!anyDuplicated(tab$sample_id), "sample_table sample_id values must be unique after cleaning.")
  for (nm in c("matrix_path", "barcodes_path", "features_path")) {
    tab[[nm]] <- normalizePath(tab[[nm]], winslash = "/", mustWork = TRUE)
  }
  tab
}

.wb_ingest_10x_cell_ids <- function(sample_id, barcodes, duplicate_cell_id_policy = c("prefix", "make_unique", "error")) {
  duplicate_cell_id_policy <- match.arg(duplicate_cell_id_policy)
  raw <- as.character(barcodes)
  .wb_assert(length(raw) > 0L, "10x barcode list is empty")
  .wb_assert(!anyNA(raw) && all(nzchar(raw)), "10x barcode list contains empty/NA values")
  if (identical(duplicate_cell_id_policy, "prefix")) {
    final <- paste0(as.character(sample_id)[1], ":", raw)
  } else {
    final <- raw
  }
  final
}

.wb_update_matrix_registry_counts <- function(bundle, matrix_id, n_features, n_cells, path = NULL) {
  DBI::dbExecute(
    bundle$con,
    "UPDATE matrices
       SET n_features = ?,
           n_cells = ?,
           path = COALESCE(path, ?)
     WHERE matrix_id = ?;",
    params = list(as.integer(n_features), as.integer(n_cells), path %||% NA_character_, matrix_id)
  )
  invisible(TRUE)
}

.wb_ingest_10x_link_or_copy <- function(from, to) {
  if (file.exists(to)) unlink(to, force = TRUE)
  if (grepl("\\.gz$", to, ignore.case = TRUE) && !grepl("\\.gz$", from, ignore.case = TRUE)) {
    in_con <- file(from, open = "rb")
    on.exit(close(in_con), add = TRUE)
    out_con <- gzfile(to, open = "wb")
    on.exit(close(out_con), add = TRUE)
    repeat {
      x <- readBin(in_con, what = "raw", n = 1024L * 1024L)
      if (!length(x)) break
      writeBin(x, out_con)
    }
    return(invisible(to))
  }
  ok <- tryCatch(file.symlink(from, to), warning = function(w) FALSE, error = function(e) FALSE)
  if (!isTRUE(ok) || !file.exists(to)) {
    ok <- file.copy(from, to, overwrite = TRUE)
  }
  .wb_assert(isTRUE(ok) && file.exists(to), paste0("Failed to stage 10x file: ", from))
  invisible(to)
}

.wb_ingest_10x_write_bpcells_fragment <- function(sample,
                                                  out_dir,
                                                  matrix_id,
                                                  sample_id,
                                                  feature_ids,
                                                  cell_ids) {
  .wb_require_pkg("BPCells", "10x Matrix Market ingestion")
  staging <- tempfile(pattern = paste0("10x_", sample_id, "_"), tmpdir = tempdir())
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(staging, recursive = TRUE, force = TRUE), add = TRUE)
  .wb_ingest_10x_link_or_copy(sample$matrix_path, file.path(staging, "matrix.mtx.gz"))
  .wb_ingest_10x_link_or_copy(sample$features_path, file.path(staging, "features.tsv.gz"))
  .wb_ingest_10x_link_or_copy(sample$barcodes_path, file.path(staging, "barcodes.tsv.gz"))
  if (dir.exists(out_dir)) unlink(out_dir, recursive = TRUE, force = TRUE)
  imported <- paste0(out_dir, ".imported")
  on.exit(if (dir.exists(imported)) unlink(imported, recursive = TRUE, force = TRUE), add = TRUE)
  BPCells::import_matrix_market_10x(staging, outdir = imported, row_major = FALSE)
  mat <- .wb_bp_open_matrix_dir(imported)
  .wb_assert(identical(as.integer(dim(mat)), c(length(feature_ids), length(cell_ids))),
             paste0("Imported 10x fragment dimensions disagree with canonical identities for sample_id=", sample_id))
  rownames(mat) <- as.character(feature_ids)
  colnames(mat) <- as.character(cell_ids)
  BPCells::write_matrix_dir(mat, out_dir)
  unlink(imported, recursive = TRUE, force = TRUE)
  invisible(out_dir)
}

.wb_ingest_matrix <- function(bundle, matrix_id, mat, layer, source, created_by, emit_report_artifact = FALSE) {
  if (!inherits(mat, "Matrix") && !is.matrix(mat)) mat <- Matrix::Matrix(mat, sparse = TRUE)
  if (is.null(rownames(mat))) rownames(mat) <- paste0("feature_", seq_len(nrow(mat)))
  if (is.null(colnames(mat))) colnames(mat) <- wb_cells(bundle, "core")
  feature_type <- .wb_guess_feature_type(rownames(mat))
  wb_attach_matrix(
    bundle = bundle,
    matrix_id = matrix_id,
    mat = mat,
    layer = layer,
    feature_type = feature_type,
    description = paste0(source, " ", layer, " matrix"),
    source = source,
    created_by = created_by,
    emit_report_artifact = emit_report_artifact
  )
  invisible(matrix_id)
}

#' Initialize a Bundle from 10x Matrix Market Triplets
#'
#' Imports one or more Cell Ranger-style Matrix Market triplets
#' (`matrix.mtx[.gz]`, `barcodes.tsv[.gz]`, `features.tsv[.gz]`) into a
#' scworkbench bundle. Multiple libraries are stored as BPCells fragments under
#' one logical matrix.
#'
#' @param input Directory containing one 10x triplet, a directory of triplets,
#'   or a sample table-compatible source descriptor.
#' @param bundle_dir Destination bundle directory. Ingestion builds in a
#'   sibling staging directory and promotes only after validation succeeds.
#' @param sample_table Optional data frame describing multiple libraries. It
#'   must provide sample_id, matrix_path, barcodes_path, and features_path;
#'   other columns are copied to cell metadata.
#' @param matrix_id Logical count-matrix identifier for the combined libraries.
#' @param overwrite Whether an existing destination bundle may be replaced after
#'   a successful staged build.
#' @param created_by Optional actor label recorded in the ingest report and
#'   provenance.
#' @param duplicate_cell_id_policy Policy for collisions across libraries.
#'   prefix constructs deterministic sample_id:barcode cell IDs, make_unique
#'   repairs collisions, and error rejects them.
#' @param duplicate_feature_id_policy Policy for duplicate feature IDs.
#'   error rejects them; make_unique repairs them deterministically.
#' @param original_feature_id_col Feature metadata column that preserves feature
#'   IDs before any repair.
#' @param emit_report_artifact Whether to promote the ingestion QC/provenance
#'   report artifact.
#' @param source_identity Optional immutable structured record describing the
#'   supplied source. It is not inferred from `input`.
#'
#' @return An open scworkbench_bundle at bundle_dir.
#'
#' @export
wb_bundle_from_10x_mtx <- function(input,
                                   bundle_dir,
                                   sample_table = NULL,
                                   matrix_id = "RNA_counts",
                                   overwrite = FALSE,
                                   created_by = "container_ingest",
                                   duplicate_cell_id_policy = c("prefix", "make_unique", "error"),
                                   duplicate_feature_id_policy = c("error", "make_unique"),
                                   original_feature_id_col = "original_feature_id",
                                   emit_report_artifact = TRUE,
                                   source_identity = NULL) {
  .wb_require_pkg("Matrix", "10x Matrix Market ingestion")
  .wb_require_pkg("BPCells", "10x Matrix Market ingestion")
  duplicate_cell_id_policy <- match.arg(duplicate_cell_id_policy)
  duplicate_feature_id_policy <- match.arg(duplicate_feature_id_policy)
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id must be a non-empty string")
  .wb_assert(is.character(bundle_dir) && length(bundle_dir) == 1L && nzchar(bundle_dir), "bundle_dir must be a non-empty string")

  final_dir <- normalizePath(bundle_dir, winslash = "/", mustWork = FALSE)
  if (dir.exists(final_dir) && !isTRUE(overwrite)) {
    stop("bundle_dir exists: ", bundle_dir, " (set overwrite=TRUE)", call. = FALSE)
  }
  parent_dir <- dirname(final_dir)
  dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  stage_dir <- tempfile(pattern = paste0(".", basename(final_dir), "_staging_"), tmpdir = parent_dir)
  source_path <- if (is.character(input) && length(input) == 1L && file.exists(input)) normalizePath(input, winslash = "/", mustWork = FALSE) else NA_character_
  phase <- "initialized"
  bundle <- NULL

  out <- tryCatch({
    phase <- "sample_table"
    samples <- .wb_ingest_10x_sample_table(input, sample_table = sample_table)
    sample_meta_cols <- setdiff(names(samples), c("matrix_path", "barcodes_path", "features_path"))

    phase <- "read_barcodes_features"
    per <- vector("list", nrow(samples))
    names(per) <- samples$sample_id
    all_cells <- character(0)
    all_barcodes <- character(0)
    all_feature_raw <- NULL
    all_feature_final <- NULL
    feature_meta <- NULL
    total_nnz <- 0
    mtx_metadata <- list()

    for (i in seq_len(nrow(samples))) {
      s <- samples[i, , drop = FALSE]
      barcodes <- .wb_ingest_10x_read_tsv(s$barcodes_path, c("barcode"))$barcode
      features <- .wb_ingest_10x_read_tsv(s$features_path, c("feature_id", "feature_name", "feature_type"))
      feature_repair <- .wb_ingest_feature_id_repair(
        features$feature_id,
        duplicate_feature_id_policy = duplicate_feature_id_policy,
        original_id_col = original_feature_id_col
      )
      final_features <- feature_repair$feature_ids
      if (is.null(all_feature_final)) {
        all_feature_final <- final_features
        all_feature_raw <- feature_repair$original_feature_ids
        feature_meta <- data.frame(
          feature_id = final_features,
          stringsAsFactors = FALSE
        )
        feature_meta[[original_feature_id_col]] <- feature_repair$original_feature_ids
        feature_meta$feature_name <- as.character(features$feature_name %||% NA_character_)
        feature_meta$feature_type <- as.character(features$feature_type %||% "Gene Expression")
        feature_meta <- feature_meta[, c("feature_id", original_feature_id_col, setdiff(names(feature_meta), c("feature_id", original_feature_id_col))), drop = FALSE]
      } else if (!identical(all_feature_final, final_features)) {
        stop("10x libraries do not share the same final feature_id order; union/reindex attach is not implemented for multi-library 10x ingestion.", call. = FALSE)
      }
      cell_ids <- .wb_ingest_10x_cell_ids(s$sample_id, barcodes, duplicate_cell_id_policy = duplicate_cell_id_policy)
      per[[i]] <- list(
        sample = s,
        barcodes = barcodes,
        cell_ids = cell_ids,
        features = features,
        feature_repair = feature_repair,
        final_features = final_features,
        mtx_meta = .wb_ingest_10x_mtx_metadata(s$matrix_path)
      )
      all_cells <- c(all_cells, cell_ids)
      all_barcodes <- c(all_barcodes, barcodes)
      mtx_metadata[[s$sample_id]] <- per[[i]]$mtx_meta$metadata_json %||% list()
    }

    dup_final_mask <- duplicated(all_cells) | duplicated(all_cells, fromLast = TRUE)
    if (any(dup_final_mask)) {
      if (identical(duplicate_cell_id_policy, "error")) {
        stop("Duplicate final cell IDs detected during 10x ingestion after selected policy.", call. = FALSE)
      }
      if (identical(duplicate_cell_id_policy, "make_unique")) {
        all_cells <- make.unique(all_cells, sep = ".")
        cursor <- 0L
        for (i in seq_along(per)) {
          n <- length(per[[i]]$cell_ids)
          per[[i]]$cell_ids <- all_cells[seq.int(cursor + 1L, cursor + n)]
          cursor <- cursor + n
        }
      } else {
        stop("Duplicate final cell IDs detected despite prefix policy.", call. = FALSE)
      }
    }
    .wb_assert(!anyDuplicated(all_cells), "10x cell ID policy failed to produce unique final cell_ids.")

    phase <- "init_bundle"
    message("10x_mtx: initializing staged bundle")
    bundle <- wb_init_bundle(stage_dir, overwrite = TRUE)
    on.exit(if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)

    phase <- "define_cells"
    message("10x_mtx: defining ", length(all_cells), " cells")
    cell_md <- vector("list", length(per))
    for (i in seq_along(per)) {
      s <- per[[i]]$sample
      n <- length(per[[i]]$cell_ids)
      md <- data.frame(
        cell_id = per[[i]]$cell_ids,
        barcode = per[[i]]$barcodes,
        sample_id = rep(as.character(s$sample_id), n),
        stringsAsFactors = FALSE
      )
      for (nm in setdiff(names(s), c("matrix_path", "barcodes_path", "features_path", "sample_id"))) {
        md[[nm]] <- rep(as.character(s[[nm]]), n)
      }
      cell_md[[i]] <- md
    }
    cell_md <- do.call(rbind, cell_md)
    wb_define_cells(
      bundle,
      cell_ids = cell_md$cell_id,
      metadata = cell_md,
      dataset_id = cell_md$sample_id,
      set_name = "core",
      source = "10x_mtx",
      created_by = created_by
    )
    message("10x_mtx: cell definition complete")

    phase <- "attach_matrices"
    message("10x_mtx: initializing matrix registry for ", matrix_id)
    first_rel_path <- NA_character_
    created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    DBI::dbWriteTable(
      bundle$con,
      "matrices",
      data.frame(
        matrix_id = matrix_id,
        layer = "counts",
        feature_type = "gene",
        n_features = as.integer(length(all_feature_final)),
        n_cells = as.integer(length(all_cells)),
        storage = "bpcells",
        path = NA_character_,
        description = "Imported 10x Matrix Market count matrix",
        stringsAsFactors = FALSE
      ),
      append = TRUE
    )
    message("10x_mtx: feature registry complete")
    DBI::dbWriteTable(
      bundle$con,
      "features",
      data.frame(
        matrix_id = matrix_id,
        feature_id = all_feature_final,
        feature_type = "gene",
        chr = NA_character_,
        start = NA_integer_,
        end = NA_integer_,
        stringsAsFactors = FALSE
      ),
      append = TRUE
    )
    for (i in seq_along(per)) {
      sample_id <- per[[i]]$sample$sample_id
      message("10x_mtx: importing library ", i, "/", length(per), " (", sample_id, ")")
      dims <- per[[i]]$mtx_meta$dims
      .wb_assert(as.integer(dims[["n_rows"]]) == length(per[[i]]$final_features), paste0("10x matrix row count does not match features for sample_id=", sample_id))
      .wb_assert(as.integer(dims[["n_cols"]]) == length(per[[i]]$cell_ids), paste0("10x matrix column count does not match barcodes for sample_id=", sample_id))
      total_nnz <- total_nnz + as.integer(dims[["n_nonzero"]])
      frag_dirname <- paste0("mat_frag_", matrix_id, "_", .wb_ingest_clean_id(sample_id, "sample"), "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
      rel_path <- file.path("mat", frag_dirname)
      abs_path <- .wb_bundle_path_require(bundle,rel_path,expected_type="directory",must_exist=FALSE,
                                          purpose="10x matrix fragment output")
      .wb_ingest_10x_write_bpcells_fragment(
        sample = per[[i]]$sample,
        out_dir = abs_path,
        matrix_id = matrix_id,
        sample_id = sample_id,
        feature_ids = per[[i]]$final_features,
        cell_ids = per[[i]]$cell_ids
      )
      message("10x_mtx: registered library ", i, "/", length(per), " (", sample_id, ")")
      frag_mat <- .wb_bp_open_matrix_dir(abs_path)
      .wb_assert(identical(as.integer(dim(frag_mat)), as.integer(c(length(per[[i]]$final_features), length(per[[i]]$cell_ids)))),
                 paste0("BPCells 10x fragment dimensions mismatch for sample_id=", sample_id))
      wb_register_matrix_fragment(
        con = bundle$con,
        matrix_id = matrix_id,
        path_rel = rel_path,
        feature_ids = per[[i]]$final_features,
        cell_ids = per[[i]]$cell_ids,
        source = "10x_mtx",
        created_at = created_at,
        description = paste0("10x Matrix Market fragment ", sample_id)
      )
      if (is.na(first_rel_path)) {
        first_rel_path <- rel_path
      }
    }
    .wb_update_matrix_registry_counts(
      bundle,
      matrix_id = matrix_id,
      n_features = length(all_feature_final),
      n_cells = length(all_cells),
      path = first_rel_path
    )

    phase <- "feature_metadata"
    rowdata_artifact <- .wb_ingest_feature_metadata_artifact(bundle, feature_meta, "10x_mtx", matrix_id, created_by = created_by)

    phase <- "report"
    if (isTRUE(emit_report_artifact)) {
      dup_raw_cell_mask <- duplicated(all_barcodes) | duplicated(all_barcodes, fromLast = TRUE)
      feature_repair <- per[[1]]$feature_repair
      .wb_container_ingest_report_artifact(
        bundle,
        source_type = "10x_mtx",
        source_path = source_path,
        assays_imported = matrix_id,
        spaces_imported = character(0),
        categorical_sets = character(0),
        rowdata_artifact_id = rowdata_artifact,
        unsupported = list(
          n_libraries = nrow(samples),
          sample_ids = as.character(samples$sample_id),
          source_paths = samples[, c("sample_id", "matrix_path", "barcodes_path", "features_path"), drop = FALSE],
          matrix_id = matrix_id,
          total_cells = length(all_cells),
          total_features = length(all_feature_final),
          total_nonzero_entries = total_nnz,
          sample_metadata_columns = sample_meta_cols,
          barcodes_prefixed = identical(duplicate_cell_id_policy, "prefix"),
          matrix_market_metadata = mtx_metadata
        ),
        cell_id_policy = list(
          duplicate_cell_id_policy = duplicate_cell_id_policy,
          duplicate_cell_id_rows = as.integer(sum(dup_raw_cell_mask)),
          duplicate_cell_id_unique_values = length(unique(all_barcodes[dup_raw_cell_mask])),
          original_cell_id_column = "barcode"
        ),
        feature_id_policy = list(
          duplicate_feature_id_policy = feature_repair$policy,
          duplicate_feature_id_rows = feature_repair$duplicate_rows,
          duplicate_feature_id_unique_values = length(feature_repair$duplicate_ids),
          original_feature_id_column = original_feature_id_col
        ),
        status = "completed",
        phase = phase,
        created_by = created_by,
        matrix_ids = matrix_id,
        source_identity = source_identity
      )
    }

    phase <- "finalize_staging"
    wb_refresh_manifest(bundle)
    wb_close_bundle(bundle)
    bundle <- NULL
    .wb_ingest_promote_staged_bundle(stage_dir, final_dir, source_type = "10x_mtx", overwrite = overwrite)
  }, error = function(e) {
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    if (dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE, force = TRUE)
    if (isTRUE(overwrite) || !dir.exists(final_dir)) {
      .wb_ingest_failure_marker(
        final_dir,
        source_type = "10x_mtx",
        source_path = source_path,
        phase = phase,
        error = conditionMessage(e),
        details = list(
          duplicate_cell_id_policy = duplicate_cell_id_policy,
          duplicate_feature_id_policy = duplicate_feature_id_policy,
          matrix_id = matrix_id
        )
      )
    }
    stop(
      "10x Matrix Market ingestion failed at phase '",
      phase,
      "'. Final bundle was not promoted; see INGEST_FAILED.json when present. Error: ",
      conditionMessage(e),
      call. = FALSE
    )
  })
  out
}

#' Initialize a Bundle from a Seurat Object
#'
#' Importer v1 maps assays/layers, cell metadata, reductions, identities, and
#' categorical metadata labels into existing scworkbench bundle primitives. It
#' does not reconstruct upstream preprocessing provenance or arbitrary tool
#' histories.
#'
#' @param input A Seurat object or path to an RDS containing one.
#' @param bundle_dir Destination bundle directory.
#' @param assays Assay names to import; defaults to all assays.
#' @param layers Layer/slot name, or named assay-to-layer mapping.
#' @param matrix_specs Optional compatibility publication specifications from
#'   [wb_matrix_spec()]. When supplied, their matrix IDs, assays, layers,
#'   feature types, and descriptions are authoritative.
#' @param reductions Reduced-dimension names to import; defaults to all.
#' @param metadata_cols Optional metadata columns to retain.
#' @param categorical_cols Metadata columns to materialize as cell sets.
#' @param create_cell_sets Whether categorical metadata creates cell sets.
#' @param dataset_col Optional metadata column used as dataset identity.
#' @param overwrite Whether an existing bundle directory may be replaced.
#' @param created_by Optional provenance actor.
#' @param emit_report_artifact Whether to promote an ingest report artifact.
#' @param source_identity Optional immutable source declaration. In-memory and
#'   RDS inputs receive a canonical declaration when omitted.
#' @return An open scworkbench bundle.
#' @export
wb_bundle_from_seurat <- function(input,
                                  bundle_dir,
                                  assays = NULL,
                                  layers = "counts",
                                  matrix_specs = NULL,
                                  reductions = NULL,
                                  metadata_cols = NULL,
                                  categorical_cols = NULL,
                                  create_cell_sets = TRUE,
                                  dataset_col = NULL,
                                  overwrite = FALSE,
                                  created_by = NULL,
                                  emit_report_artifact = TRUE,
                                  source_identity = NULL) {
  .wb_require_pkg("SeuratObject", "Seurat ingestion")
  .wb_require_pkg("Matrix", "Seurat ingestion")
  src <- .wb_ingest_source_object(input, "Seurat")
  seurat <- src$object
  .wb_assert(inherits(seurat, "Seurat"), "input must be a Seurat object or an .rds containing one")
  if (is.null(source_identity)) {
    source_input <- if (!is.null(src$source_path) && nzchar(src$source_path)) {
      list(
        path = src$source_path,
        role = "source_object",
        format = "rds",
        checksum = .wb_prov_sha256_file(src$source_path),
        checksum_algorithm = "sha256"
      )
    } else {
      list(
        uri = "scworkbench-ingestion://bundle_from_seurat/in-memory-seurat",
        role = "source_object",
        format = "Seurat"
      )
    }
    source_identity <- list(source_type = "Seurat", inputs = list(source_input))
  }

  bundle <- wb_init_bundle(bundle_dir, overwrite = overwrite)
  completed <- FALSE
  on.exit({
    if (isTRUE(completed)) {
      try(wb_refresh_manifest(bundle), silent = TRUE)
    } else {
      try(wb_close_bundle(bundle), silent = TRUE)
    }
  }, add = TRUE)

  md <- as.data.frame(seurat@meta.data, stringsAsFactors = FALSE, check.names = FALSE)
  md <- .wb_ingest_as_metadata_df(md, row_ids = colnames(seurat), id_col = "cell_id")
  if (!is.null(metadata_cols)) md <- md[, unique(c("cell_id", intersect(c(metadata_cols, dataset_col), names(md)))), drop = FALSE]
  ds <- .wb_ingest_dataset_id(md, dataset_col = dataset_col, n = ncol(seurat))
  wb_define_cells(bundle, colnames(seurat), metadata = md, dataset_id = ds, set_name = "core", source = "seurat", created_by = created_by)

  imported <- character(0)
  if (!is.null(matrix_specs)) {
    .wb_assert(is.list(matrix_specs), "matrix_specs must be a list")
    for (spec in matrix_specs) {
      .wb_assert(is.list(spec), "each matrix_specs entry must be a list")
      wb_attach_matrix_from_seurat(
        bundle = bundle,
        seurat = seurat,
        matrix_id = as.character(spec$matrix_id %||% "")[1],
        assay = as.character(spec$seurat_assay %||% "")[1],
        layer = as.character(spec$layer %||% layers %||% "counts")[1],
        feature_type = as.character(spec$feature_type %||% "feature")[1],
        description = spec$description %||% NULL,
        source = "seurat",
        created_by = created_by
      )
      imported <- c(imported, as.character(spec$matrix_id)[1])
    }
  } else {
    assays <- assays %||% names(seurat@assays)
    for (assay in assays) {
      lyr <- if (length(layers) == 1L) layers else layers[[assay]] %||% layers[[1]]
      mat <- .get_assay_counts(seurat, assay = assay, layer_or_slot = lyr)
      mat <- .align_matrix_to_ids(mat, rownames(mat), colnames(seurat))
      matrix_id <- .wb_ingest_clean_id(if (length(assays) == 1L) assay else paste(assay, lyr, sep = "_"), "matrix")
      .wb_ingest_matrix(bundle, matrix_id, mat, layer = lyr, source = "seurat", created_by = created_by)
      imported <- c(imported, matrix_id)
    }
  }

  if (is.null(reductions)) reductions <- names(seurat@reductions)
  spaces <- if (length(reductions)) {
    wb_attach_spaces_from_seurat(
      bundle, seurat, reductions = reductions, overwrite = FALSE, source = "seurat"
    )
  } else list()
  space_ids <- names(spaces)

  if ("seurat_clusters" %in% names(md)) categorical_cols <- unique(c(categorical_cols, "seurat_clusters"))
  cat_sets <- if (isTRUE(create_cell_sets)) {
    .wb_ingest_label_cell_sets(bundle, md, categorical_cols = categorical_cols, prefix = "seurat", source = "seurat", created_by = created_by)
  } else character(0)

  if (isTRUE(emit_report_artifact)) {
    .wb_container_ingest_report_artifact(
      bundle,
      source_type = "Seurat",
      source_path = src$source_path,
      assays_imported = imported,
      spaces_imported = space_ids,
      categorical_sets = cat_sets,
      unsupported = list(misc = "not imported", graphs = "not imported", commands = "not imported"),
      created_by = created_by,
      matrix_ids = imported,
      source_identity = source_identity
    )
  }
  completed <- TRUE
  bundle
}

#' Initialize a Bundle from a SingleCellExperiment Object
#'
#' @param input A `SingleCellExperiment` object or path to an RDS containing one.
#' @param bundle_dir Destination bundle directory.
#' @param assays Assay names to import; defaults to all assays.
#' @param reduced_dims Reduced-dimension names to import; defaults to all.
#' @param metadata_cols Optional cell metadata columns to retain.
#' @param categorical_cols Metadata columns to materialize as cell sets.
#' @param create_cell_sets Whether categorical metadata creates cell sets.
#' @param dataset_col Optional metadata column used as dataset identity.
#' @param duplicate_cell_id_policy Whether duplicate cell IDs error or are made
#'   unique while preserving original IDs.
#' @param original_cell_id_col Metadata column for original cell IDs.
#' @param duplicate_feature_id_policy Whether duplicate feature IDs error or are
#'   made unique while preserving original IDs.
#' @param original_feature_id_col Feature metadata column for original IDs.
#' @param overwrite Whether an existing bundle directory may be replaced.
#' @param created_by Optional provenance actor.
#' @param emit_report_artifact Whether to promote an ingest report artifact.
#' @return An open scworkbench bundle.
#' @export
wb_bundle_from_sce <- function(input,
                               bundle_dir,
                               assays = NULL,
                               reduced_dims = NULL,
                               metadata_cols = NULL,
                               categorical_cols = NULL,
                               create_cell_sets = TRUE,
                               dataset_col = NULL,
                               duplicate_cell_id_policy = c("error", "make_unique"),
                               original_cell_id_col = "original_cell_id",
                               duplicate_feature_id_policy = c("error", "make_unique"),
                               original_feature_id_col = "original_feature_id",
                               overwrite = FALSE,
                               created_by = NULL,
                               emit_report_artifact = TRUE) {
  .wb_require_pkg("SingleCellExperiment", "SingleCellExperiment ingestion")
  .wb_require_pkg("SummarizedExperiment", "SingleCellExperiment ingestion")
  .wb_require_pkg("Matrix", "SingleCellExperiment ingestion")
  duplicate_cell_id_policy <- match.arg(duplicate_cell_id_policy)
  duplicate_feature_id_policy <- match.arg(duplicate_feature_id_policy)
  src <- .wb_ingest_source_object(input, "SingleCellExperiment")
  sce <- src$object
  .wb_assert(methods::is(sce, "SingleCellExperiment"), "input must be a SingleCellExperiment object or an .rds containing one")

  cell_ids <- colnames(sce)
  if (is.null(cell_ids)) cell_ids <- paste0("cell_", seq_len(ncol(sce)))
  id_repair <- .wb_ingest_cell_id_repair(
    cell_ids,
    duplicate_cell_id_policy = duplicate_cell_id_policy,
    original_id_col = original_cell_id_col
  )
  raw_cell_ids <- id_repair$original_cell_ids
  cell_ids <- id_repair$cell_ids
  colnames(sce) <- cell_ids

  feature_ids <- rownames(sce)
  if (is.null(feature_ids)) feature_ids <- paste0("feature_", seq_len(nrow(sce)))
  feature_repair <- .wb_ingest_feature_id_repair(
    feature_ids,
    duplicate_feature_id_policy = duplicate_feature_id_policy,
    original_id_col = original_feature_id_col
  )
  raw_feature_ids <- feature_repair$original_feature_ids
  feature_ids <- feature_repair$feature_ids
  rownames(sce) <- feature_ids

  bundle <- wb_init_bundle(bundle_dir, overwrite = overwrite)
  completed <- FALSE
  on.exit({
    if (isTRUE(completed)) {
      try(wb_refresh_manifest(bundle), silent = TRUE)
    } else {
      try(wb_close_bundle(bundle), silent = TRUE)
    }
  }, add = TRUE)

  md <- .wb_ingest_as_metadata_df(SummarizedExperiment::colData(sce), row_ids = cell_ids, id_col = "cell_id")
  original_cell_id_col <- as.character(original_cell_id_col %||% "original_cell_id")[1]
  if (!nzchar(original_cell_id_col)) original_cell_id_col <- "original_cell_id"
  if (original_cell_id_col %in% names(md)) {
    original_cell_id_col <- make.unique(c(names(md), original_cell_id_col), sep = ".")[[length(names(md)) + 1L]]
  }
  md[[original_cell_id_col]] <- raw_cell_ids
  original_position <- ncol(md)
  md <- md[, c(1L, original_position, setdiff(seq_len(ncol(md)), c(1L, original_position))), drop = FALSE]
  if (!is.null(metadata_cols)) {
    md <- md[, unique(c("cell_id", original_cell_id_col, intersect(c(metadata_cols, dataset_col), names(md)))), drop = FALSE]
  }
  ds <- .wb_ingest_dataset_id(md, dataset_col = dataset_col, n = length(cell_ids))
  .wb_assert(length(ds) == 1L || length(ds) == length(cell_ids),
             "dataset_id must be length 1 or the same length as final unique cell_ids after duplicate-cell-ID handling.")
  wb_define_cells(bundle, cell_ids, metadata = md, dataset_id = ds, set_name = "core", source = "single_cell_experiment", created_by = created_by)

  assay_names <- SummarizedExperiment::assayNames(sce)
  assays <- assays %||% assay_names
  imported <- character(0)
  rowdata_artifact <- NA_character_
  for (assay in assays) {
    mat <- SummarizedExperiment::assay(sce, assay)
    rownames(mat) <- feature_ids
    colnames(mat) <- cell_ids
    matrix_id <- .wb_ingest_clean_id(assay, "matrix")
    .wb_ingest_matrix(bundle, matrix_id, mat, layer = assay, source = "single_cell_experiment", created_by = created_by)
    imported <- c(imported, matrix_id)
    if (is.na(rowdata_artifact)) {
      rd <- .wb_ingest_as_metadata_df(SummarizedExperiment::rowData(sce), row_ids = feature_ids, id_col = "feature_id")
      original_feature_id_col <- as.character(original_feature_id_col %||% "original_feature_id")[1]
      if (!nzchar(original_feature_id_col)) original_feature_id_col <- "original_feature_id"
      if (original_feature_id_col %in% names(rd)) {
        original_feature_id_col <- make.unique(c(names(rd), original_feature_id_col), sep = ".")[[length(names(rd)) + 1L]]
      }
      rd[[original_feature_id_col]] <- raw_feature_ids
      rd <- rd[, c("feature_id", original_feature_id_col, setdiff(names(rd), c("feature_id", original_feature_id_col))), drop = FALSE]
      rowdata_artifact <- .wb_ingest_feature_metadata_artifact(bundle, rd, "SingleCellExperiment", matrix_id, created_by = created_by)
    }
  }

  rd_names <- SingleCellExperiment::reducedDimNames(sce)
  reduced_dims <- reduced_dims %||% rd_names
  space_ids <- character(0)
  for (rd in reduced_dims) {
    coords <- SingleCellExperiment::reducedDim(sce, rd)
    if (is.null(coords) || ncol(coords) < 2L) next
    coords <- as.matrix(coords)
    rownames(coords) <- cell_ids
    space_id <- .wb_ingest_clean_id(rd, "space")
    wb_add_space(bundle, space_id = space_id, coords = coords, description = paste0("Imported SCE reducedDim ", rd), source = "single_cell_experiment")
    space_ids <- c(space_ids, space_id)
  }

  cat_sets <- if (isTRUE(create_cell_sets)) {
    .wb_ingest_label_cell_sets(bundle, md, categorical_cols = categorical_cols, prefix = "sce", source = "single_cell_experiment", created_by = created_by)
  } else character(0)

  alt_exps <- tryCatch(SingleCellExperiment::altExpNames(sce), error = function(e) character(0))
  if (isTRUE(emit_report_artifact)) {
    .wb_container_ingest_report_artifact(
      bundle,
      source_type = "SingleCellExperiment",
      source_path = src$source_path,
      assays_imported = imported,
      spaces_imported = space_ids,
      categorical_sets = cat_sets,
      rowdata_artifact_id = rowdata_artifact,
      unsupported = list(
        altExp_names = as.character(alt_exps),
        altExp_import = "presence recorded; altExp matrices are not imported by default in importer v1",
        metadata_misc = "int_metadata/metadata are not imported except through report summaries",
        duplicate_cell_id_policy = id_repair$policy,
        duplicate_cell_id_rows = id_repair$duplicate_rows,
        duplicate_cell_id_unique_values = length(id_repair$duplicate_ids),
        original_cell_id_column = original_cell_id_col,
        duplicate_feature_id_policy = feature_repair$policy,
        duplicate_feature_id_rows = feature_repair$duplicate_rows,
        duplicate_feature_id_unique_values = length(feature_repair$duplicate_ids),
        original_feature_id_column = original_feature_id_col
      ),
      cell_id_policy = list(
        duplicate_cell_id_policy = id_repair$policy,
        duplicate_cell_id_rows = id_repair$duplicate_rows,
        duplicate_cell_id_unique_values = length(id_repair$duplicate_ids),
        original_cell_id_column = original_cell_id_col
      ),
      feature_id_policy = list(
        duplicate_feature_id_policy = feature_repair$policy,
        duplicate_feature_id_rows = feature_repair$duplicate_rows,
        duplicate_feature_id_unique_values = length(feature_repair$duplicate_ids),
        original_feature_id_column = original_feature_id_col
      ),
      created_by = created_by,
      matrix_ids = imported
    )
  }
  completed <- TRUE
  bundle
}

#' Initialize a Bundle from an AnnData h5ad File
#'
#' Uses `zellkonverter::readH5AD()` and then maps the converted
#' SingleCellExperiment through [wb_bundle_from_sce()].
#'
#' @inheritParams wb_bundle_from_sce
#' @param input Path to an `.h5ad` file.
#' @return An open scworkbench bundle.
#' @export
wb_bundle_from_h5ad <- function(input,
                                bundle_dir,
                                assays = NULL,
                                reduced_dims = NULL,
                                metadata_cols = NULL,
                                categorical_cols = NULL,
                                create_cell_sets = TRUE,
                                dataset_col = NULL,
                                duplicate_cell_id_policy = c("make_unique", "error"),
                                original_cell_id_col = "ann_data_obs_name",
                                duplicate_feature_id_policy = c("make_unique", "error"),
                                original_feature_id_col = "ann_data_var_name",
                                overwrite = FALSE,
                                created_by = NULL,
                                emit_report_artifact = TRUE) {
  .wb_require_pkg("zellkonverter", "AnnData h5ad ingestion")
  .wb_assert(is.character(input) && length(input) == 1L && file.exists(input), "input must be an existing .h5ad path")
  duplicate_cell_id_policy <- match.arg(duplicate_cell_id_policy)
  duplicate_feature_id_policy <- match.arg(duplicate_feature_id_policy)
  input_path <- normalizePath(input, winslash = "/", mustWork = TRUE)
  .wb_assert(is.character(bundle_dir) && length(bundle_dir) == 1L && nzchar(bundle_dir), "bundle_dir must be a non-empty string")
  final_dir <- normalizePath(bundle_dir, winslash = "/", mustWork = FALSE)
  if (dir.exists(final_dir) && !isTRUE(overwrite)) {
    stop("bundle_dir exists: ", bundle_dir, " (set overwrite=TRUE)", call. = FALSE)
  }
  parent_dir <- dirname(final_dir)
  dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  stage_dir <- tempfile(pattern = paste0(".", basename(final_dir), "_staging_"), tmpdir = parent_dir)
  phase <- "initialized"
  groups <- character(0)
  bundle <- NULL
  out <- tryCatch({
    phase <- "h5ad_top_level_scan"
    if (requireNamespace("rhdf5", quietly = TRUE)) {
      groups <- tryCatch(as.character(rhdf5::h5ls(input_path, recursive = FALSE)$name), error = function(e) character(0))
    }
    phase <- "h5ad_read"
    sce <- zellkonverter::readH5AD(input_path)
    phase <- "identifier_policy"
    h5ad_id_repair <- .wb_ingest_cell_id_repair(
      colnames(sce) %||% paste0("cell_", seq_len(ncol(sce))),
      duplicate_cell_id_policy = duplicate_cell_id_policy,
      original_id_col = original_cell_id_col
    )
    h5ad_feature_repair <- .wb_ingest_feature_id_repair(
      rownames(sce) %||% paste0("feature_", seq_len(nrow(sce))),
      duplicate_feature_id_policy = duplicate_feature_id_policy,
      original_id_col = original_feature_id_col
    )
    phase <- "sce_ingest"
    bundle <- wb_bundle_from_sce(
      sce,
      bundle_dir = stage_dir,
      assays = assays,
      reduced_dims = reduced_dims,
      metadata_cols = metadata_cols,
      categorical_cols = categorical_cols,
      create_cell_sets = create_cell_sets,
      dataset_col = dataset_col,
      duplicate_cell_id_policy = duplicate_cell_id_policy,
      original_cell_id_col = original_cell_id_col,
      duplicate_feature_id_policy = duplicate_feature_id_policy,
      original_feature_id_col = original_feature_id_col,
      overwrite = TRUE,
      created_by = created_by,
      emit_report_artifact = emit_report_artifact
    )
    phase <- "h5ad_report"
    if (isTRUE(emit_report_artifact)) {
      .wb_container_ingest_report_artifact(
        bundle,
        source_type = "AnnData/h5ad",
        source_path = input_path,
        assays_imported = wb_matrices(bundle)$matrix_id,
        spaces_imported = wb_spaces(bundle)$space_id,
        categorical_sets = setdiff(wb_cell_sets(bundle), "core"),
        unsupported = list(
          h5ad_top_level_groups = groups,
          raw = if ("raw" %in% groups) "presence recorded; raw is not separately imported in h5ad importer v1" else "not detected",
          layers = if ("layers" %in% groups) "presence recorded; layers are not separately imported unless converted by zellkonverter into assays" else "not detected",
          obsp = if ("obsp" %in% groups) "presence recorded; graph/neighborhood structures are not imported in v1" else "not detected",
          uns = if ("uns" %in% groups) "presence recorded; arbitrary AnnData uns payloads are not imported in v1" else "not detected",
          duplicate_cell_id_policy = duplicate_cell_id_policy,
          original_cell_id_column = original_cell_id_col,
          duplicate_feature_id_policy = duplicate_feature_id_policy,
          original_feature_id_column = original_feature_id_col
        ),
        cell_id_policy = list(
          duplicate_cell_id_policy = h5ad_id_repair$policy,
          duplicate_cell_id_rows = h5ad_id_repair$duplicate_rows,
          duplicate_cell_id_unique_values = length(h5ad_id_repair$duplicate_ids),
          original_cell_id_column = original_cell_id_col
        ),
        feature_id_policy = list(
          duplicate_feature_id_policy = h5ad_feature_repair$policy,
          duplicate_feature_id_rows = h5ad_feature_repair$duplicate_rows,
          duplicate_feature_id_unique_values = length(h5ad_feature_repair$duplicate_ids),
          original_feature_id_column = original_feature_id_col
        ),
        status = "completed",
        phase = phase,
        created_by = created_by,
        matrix_ids = wb_matrices(bundle)$matrix_id
      )
    }
    phase <- "finalize_staging"
    wb_refresh_manifest(bundle)
    wb_close_bundle(bundle)
    bundle <- NULL
    .wb_ingest_promote_staged_bundle(stage_dir, final_dir, source_type = "h5ad", overwrite = overwrite)
  }, error = function(e) {
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    if (dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE, force = TRUE)
    if (isTRUE(overwrite) || !dir.exists(final_dir)) {
      .wb_ingest_failure_marker(
        final_dir,
        source_type = "AnnData/h5ad",
        source_path = input_path,
        phase = phase,
        error = conditionMessage(e),
        details = list(
          duplicate_cell_id_policy = duplicate_cell_id_policy,
          duplicate_feature_id_policy = duplicate_feature_id_policy,
          staging_dir = stage_dir
        )
      )
    }
    stop(
      "h5ad ingestion failed at phase '",
      phase,
      "'. Final bundle was not promoted; see INGEST_FAILED.json when present. Error: ",
      conditionMessage(e),
      call. = FALSE
    )
  })
  out
}
