#' Initialize an Empty scworkbench Bundle
#'
#' Create a new bundle directory with canonical SQLite schema, matrix storage
#' root, and manifest. This is the source-agnostic entry point for staged bundle
#' assembly.
#'
#' @param out_dir Output directory for the bundle.
#' @param bundle_id Optional bundle identifier. Defaults to the directory name.
#' @param bundle_name Optional human-readable bundle name. Defaults to
#'   `bundle_id`.
#' @param overwrite If `TRUE`, remove an existing `out_dir` first.
#'
#' @return An open `scworkbench_bundle`.
#' @export
wb_init_bundle <- function(out_dir,
                           bundle_id = NULL,
                           bundle_name = NULL,
                           overwrite = FALSE) {
  .wb_assert(is.character(out_dir) && length(out_dir) == 1L && nzchar(out_dir),
             "out_dir must be a non-empty string")

  writer_lock <- .wb_bundle_writer_lock_acquire(out_dir, operation = "bundle initialization")
  assembly_registered <- FALSE
  on.exit({
    if (!isTRUE(assembly_registered)) .wb_bundle_writer_lock_release(writer_lock)
  }, add = TRUE)

  if (dir.exists(out_dir)) {
    if (!isTRUE(overwrite)) {
      stop("out_dir exists: ", out_dir, " (set overwrite=TRUE)", call. = FALSE)
    }
    unlink(out_dir, recursive = TRUE, force = TRUE)
  }

  if (is.null(bundle_id) || !nzchar(bundle_id)) bundle_id <- basename(normalizePath(out_dir, winslash = "/", mustWork = FALSE))
  if (is.null(bundle_name) || !nzchar(bundle_name)) bundle_name <- bundle_id

  dir.create(file.path(out_dir, "db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "mat"), recursive = TRUE, showWarnings = FALSE)

  db_path <- file.path(out_dir, "db", "app.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(if (!is.null(con)) try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  .wb_ensure_schema_bundle(con)
  .wb_create_artifacts_schema(con)

  manifest <- .wb_bundle_build_manifest(
    bundle_dir = out_dir,
    con = con,
    bundle_id = bundle_id,
    bundle_name = bundle_name,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    id_policy = list(
      assembly_mode = "staged",
      source_adapter = "none"
    )
  )
  .wb_bundle_write_manifest(out_dir, manifest)

  try(DBI::dbDisconnect(con), silent = TRUE)
  con <- NULL
  bundle <- wb_open_bundle(out_dir)
  .wb_register_assembly_bundle(bundle, writer_lock = writer_lock)
  assembly_registered <- TRUE
  # Writable open may install supported registry schemas. Publish their exact
  # committed state before returning the active assembly handle.
  .wb_refresh_manifest_committed(bundle)
  bundle
}

#' Define the Canonical Bundle Cell Universe
#'
#' Thin canonical wrapper over cell ingest for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_ids Character vector of canonical cell ids.
#' @param metadata Optional metadata data frame.
#' @param dataset_id Dataset id to assign to the new cells. May be length 1 or
#'   the same length as `cell_ids`.
#' @param set_name Membership set to create for the new cells. Defaults to
#'   `"core"`.
#' @param overwrite Passed through to [wb_ingest_cells()].
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#'
#' @return Result from [wb_ingest_cells()].
#' @export
wb_define_cells <- function(bundle,
                            cell_ids,
                            metadata = NULL,
                            dataset_id = "dataset_1",
                            set_name = "core",
                            overwrite = FALSE,
                            source = "assembly",
                            created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(
    bundle = bundle, action = "Canonical cell-universe definition",
    allowed = c("assembly", "ingestion"),
    replacement = "wb_init_bundle() and wb_define_cells() on the returned active assembly handle, or a wb_bundle_from_*() ingestion constructor"
  )
  .wb_assert(is.character(set_name) && length(set_name) == 1L && nzchar(set_name),
             "set_name must be a non-empty string")

  raw_ids <- as.character(cell_ids)
  raw_ids <- raw_ids[nzchar(raw_ids)]
  .wb_assert(!anyDuplicated(raw_ids), "wb_define_cells(): cell_ids must be unique; repair or reject duplicated IDs before defining the canonical bundle universe.")
  ids <- raw_ids
  .wb_assert(length(ids) > 0, "cell_ids empty after cleaning")

  ds <- as.character(dataset_id %||% "dataset_1")
  if (length(ds) == 1L) ds <- rep(ds, length(ids))
  .wb_assert(length(ds) == length(ids), "dataset_id must be length 1 or the same length as cell_ids")

  n_existing <- DBI::dbGetQuery(bundle$con, "SELECT COUNT(*) AS n FROM cells;")$n[[1]]
  if (isTRUE(n_existing > 0)) {
    if (!isTRUE(overwrite)) {
      stop("Bundle already has cells; wb_define_cells() is for canonical universe initialization.", call. = FALSE)
    }
    stop("overwrite=TRUE not implemented yet for wb_define_cells() canonical initialization.", call. = FALSE)
  }

  md <- NULL
  if (!is.null(metadata)) {
    .wb_assert(is.data.frame(metadata), "metadata must be a data.frame")
    md <- as.data.frame(metadata, stringsAsFactors = FALSE, check.names = FALSE)
    if (!("cell_id" %in% colnames(md))) {
      .wb_assert(ncol(md) >= 1L, "metadata must have at least one column")
      md$cell_id <- as.character(md[[1]])
    } else {
      md$cell_id <- as.character(md$cell_id)
    }
    md <- md[match(ids, md$cell_id), , drop = FALSE]
    .wb_assert(!anyNA(match(ids, md$cell_id)), "metadata rows not aligned to cell_ids")
    for (nm in setdiff(colnames(md), "cell_id")) {
      x <- md[[nm]]
      if (is.factor(x)) x <- as.character(x)
      if (is.logical(x)) x <- as.integer(x)
      md[[nm]] <- x
    }
  }

  cells_df <- data.frame(
    cell_id = ids,
    dataset_id = ds,
    stringsAsFactors = FALSE
  )
  if (!is.null(md)) {
    md$cell_id <- NULL
    md$dataset_id <- NULL
    cells_df <- cbind(cells_df, md, stringsAsFactors = FALSE)
  }

  existing_cols <- DBI::dbListFields(bundle$con, "cells")
  new_cols <- setdiff(colnames(cells_df), existing_cols)
  for (nm in new_cols) {
    x <- cells_df[[nm]]
    col_type <- if (is.numeric(x)) "REAL" else "TEXT"
    if (is.integer(x)) col_type <- "INTEGER"
    DBI::dbExecute(bundle$con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
  }

  .wb_ensure_cell_set_membership_table(bundle$con)
  cell_set_name <- if (identical(set_name, "core")) "core" else paste0("set:", set_name)
  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  membership_df <- data.frame(
    cell_set = cell_set_name,
    cell_id = ids,
    source = source,
    created_at = created_at,
    created_by = created_by %||% NA_character_,
    description = paste0("Defined cells for ", cell_set_name),
    stringsAsFactors = FALSE
  )
  ds_tab <- as.data.frame(table(ds), stringsAsFactors = FALSE)
  if (nrow(ds_tab)) {
    colnames(ds_tab) <- c("dataset_id", "n_cells")
    ds_tab$dataset_id <- as.character(ds_tab$dataset_id)
    ds_tab$n_cells <- as.integer(ds_tab$n_cells)
  }

  DBI::dbWithTransaction(bundle$con, {
    DBI::dbWriteTable(bundle$con, "cells", cells_df, append = TRUE)
    DBI::dbWriteTable(bundle$con, "cell_set_membership", membership_df, append = TRUE)
    if (nrow(ds_tab)) {
      DBI::dbExecute(bundle$con, "DELETE FROM datasets;")
      DBI::dbWriteTable(bundle$con, "datasets", ds_tab, append = TRUE)
    }
  })

  if (identical(set_name, "core")) {
    .wb_bundle_ensure_default_cell_set_style(bundle$con, "core", created_by = created_by %||% source)
  }

  .wb_record_declared_ingestion(
    bundle = bundle, transaction_name = "assembly_define_cells",
    source = source, created_by = created_by
  )
  wb_refresh_manifest(bundle)
  invisible(list(
    set_name = set_name,
    n_defined = length(ids),
    n_metadata_cols = ncol(cells_df) - 2L
  ))
}

#' Attach One Matrix During Staged Assembly
#'
#' Thin wrapper over [wb_attach_apply()] for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param mat Matrix-like object with `rownames = feature_id` and
#'   `colnames = cell_id`.
#' @param layer Matrix layer label.
#' @param feature_type Feature type label.
#' @param description Optional description.
#' @param cell_ids Optional cell subset to restrict attach.
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#' @param emit_report_artifact Whether to persist an attach report artifact.
#'
#' @return Result from [wb_attach_apply()].
#' @export
wb_attach_matrix <- function(bundle,
                             matrix_id,
                             mat,
                             layer = "counts",
                             feature_type = "feature",
                             description = NULL,
                             cell_ids = NULL,
                             source = "assembly",
                             created_by = NULL,
                             emit_report_artifact = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id),
             "matrix_id must be a non-empty string")

  mats <- setNames(list(list(
    mat = mat,
    layer = layer,
    feature_type = feature_type,
    description = description
  )), matrix_id)

  res <- wb_attach_apply(
    bundle = bundle,
    cell_ids = cell_ids,
    matrices = mats,
    source = source,
    created_by = created_by,
    emit_report_artifact = emit_report_artifact
  )
  invisible(res)
}

#' Attach One Space During Staged Assembly
#'
#' Thin wrapper over [wb_attach_apply()] for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param space_id Space identifier.
#' @param coords Space coordinates payload.
#' @param cell_ids Optional cell subset to restrict attach.
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#' @param emit_report_artifact Whether to persist an attach report artifact.
#'
#' @return Result from [wb_attach_apply()].
#' @export
wb_attach_space <- function(bundle,
                            space_id,
                            coords,
                            cell_ids = NULL,
                            source = "assembly",
                            created_by = NULL,
                            emit_report_artifact = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(space_id) && length(space_id) == 1L && nzchar(space_id),
             "space_id must be a non-empty string")

  spaces <- setNames(list(coords), space_id)
  res <- wb_attach_apply(
    bundle = bundle,
    cell_ids = cell_ids,
    spaces = spaces,
    source = source,
    created_by = created_by,
    emit_report_artifact = emit_report_artifact
  )
  invisible(res)
}

#' Attach Metadata During Staged Assembly
#'
#' Thin wrapper over [wb_attach_apply()] for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param metadata Metadata data frame (first column is treated as `cell_id`).
#' @param cell_ids Optional explicit cell subset.
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#' @param emit_report_artifact Whether to persist an attach report artifact.
#'
#' @return Result from [wb_attach_apply()].
#' @export
wb_attach_metadata <- function(bundle,
                               metadata,
                               cell_ids = NULL,
                               source = "assembly",
                               created_by = NULL,
                               emit_report_artifact = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  res <- wb_attach_apply(
    bundle = bundle,
    cell_ids = cell_ids,
    metadata = metadata,
    source = source,
    created_by = created_by,
    emit_report_artifact = emit_report_artifact
  )
  invisible(res)
}

#' Refresh Bundle Manifest From Authoritative Storage
#'
#' Rebuild the manifest from bundle metadata and registries.
#'
#' @param bundle Open `scworkbench_bundle`.
#'
#' @return The refreshed manifest list.
#' @export
wb_refresh_manifest <- function(bundle) {
  .wb_assert_bundle_writable(bundle, "manifest refresh")
  writer_lock <- .wb_bundle_writer_lock_acquire(bundle, operation = "manifest refresh")
  on.exit(.wb_bundle_writer_lock_release(writer_lock), add = TRUE)
  .wb_assert_mutation_context(
    bundle = bundle, action = "Bundle manifest mutation",
    allowed = c("assembly", "session_execution", "promotion", "ingestion"),
    replacement = "a declared ingestion transaction or registered session promotion"
  )
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_refresh_manifest_committed(bundle)
}

# Internal tail step for a canonical mutation route that has already committed
# its SQLite transaction and still owns the bundle-writer lock.
.wb_refresh_manifest_committed <- function(bundle) {
  con <- bundle$con
  man_old <- try(bundle$manifest, silent = TRUE)
  if (inherits(man_old, "try-error") || !is.list(man_old)) man_old <- list()

  # Creation identity is immutable once a bundle is published.  The duplicated
  # top-level fields remain for compatibility, but refreshes always take their
  # values from the explicit creation record when it exists.
  creation <- man_old$creation %||% list(
    bundle_id = man_old$bundle_id %||% basename(bundle$dir),
    bundle_name = man_old$bundle_name %||% man_old$bundle_id %||% basename(bundle$dir),
    created_at = man_old$created_at %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    id_policy = man_old$id_policy %||% list()
  )

  manifest <- .wb_bundle_build_manifest(
    bundle_dir = bundle$dir,
    con = con,
    bundle_id = as.character(creation$bundle_id %||% basename(bundle$dir))[1],
    bundle_name = as.character(creation$bundle_name %||% creation$bundle_id %||% basename(bundle$dir))[1],
    created_at = as.character(creation$created_at %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))[1],
    id_policy = creation$id_policy %||% list()
  )
  .wb_bundle_write_manifest(bundle$dir, manifest)
  invisible(manifest)
}

.wb_manifest_registry_table_names <- function() {
  c(
    "cells", "datasets", "features", "matrices", "matrix_cells",
    "matrix_fragments", "matrix_fragment_cells", "matrix_fragment_features",
    "spaces", "space_models", "artifacts", "artifact_tables",
    "cell_set_membership", "cell_set_recipes", "cell_set_styles",
    "feature_sets", "feature_set_membership", "cell_vectors",
    "motif_libraries", "motifs", "motif_match_sets", "motif_match_membership",
    "entity_lifecycle", "entity_supersessions", "entity_tombstones",
    "prov_commits", "prov_heads", "prov_materializations",
    "prov_registry_mutations", "prov_replay_equivalence_results",
    "prov_run_edges", "prov_run_entity_bindings", "prov_run_outputs",
    "prov_runs", "prov_source_identities", "prov_source_inputs"
  )
}

.wb_manifest_table_identity <- function(con, table, chunk_size = 5000L) {
  fields <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
  header <- list(
    schema = "scworkbench.manifest.registry-table.v1",
    table = table,
    columns = fields[, intersect(c("name", "type", "notnull", "pk"), names(fields)), drop = FALSE]
  )
  state <- .wb_prov_sha256_object(header)
  query <- DBI::dbSendQuery(
    con,
    paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), " ORDER BY rowid;")
  )
  on.exit(DBI::dbClearResult(query), add = TRUE)
  n <- 0L
  repeat {
    rows <- DBI::dbFetch(query, n = as.integer(chunk_size))
    if (!nrow(rows)) break
    n <- n + nrow(rows)
    payload <- as.character(jsonlite::toJSON(
      .wb_json_sanitize(rows), dataframe = "rows", auto_unbox = TRUE,
      null = "null", na = "null"
    ))
    state <- .wb_prov_sha256_object(list(
      previous = state,
      rows_sha256 = digest::digest(payload, algo = "sha256", serialize = FALSE)
    ))
  }
  list(row_count = as.integer(n), content_sha256 = state)
}

.wb_manifest_registry_snapshot <- function(con) {
  present <- intersect(.wb_manifest_registry_table_names(), DBI::dbListTables(con))
  tables <- setNames(lapply(present, function(table) {
    .wb_manifest_table_identity(con, table)
  }), present)
  list(
    schema = "scworkbench.manifest.registry-state.v1",
    fingerprint = .wb_prov_sha256_object(tables),
    tables = tables
  )
}

.wb_bundle_build_manifest <- function(bundle_dir,
                                      con,
                                      bundle_id,
                                      bundle_name,
                                      created_at,
                                      id_policy = list()) {
  n_cells <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cells;")$n[1]))
  n_datasets <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM datasets;")$n[1]))
  n_spaces <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM spaces;")$n[1]))
  n_features <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM features;")$n[1]))

  mat_tbl <- try(DBI::dbReadTable(con, "matrices"), silent = TRUE)
  if (inherits(mat_tbl, "try-error") || !is.data.frame(mat_tbl)) mat_tbl <- data.frame()
  sp_tbl <- try(DBI::dbReadTable(con, "spaces"), silent = TRUE)
  if (inherits(sp_tbl, "try-error") || !is.data.frame(sp_tbl)) sp_tbl <- data.frame()

  registry_state <- .wb_manifest_registry_snapshot(con)
  list(
    scworkbench_manifest_version = "2.2.0",
    bundle_id = as.character(bundle_id)[1],
    bundle_name = as.character(bundle_name)[1],
    created_at = as.character(created_at)[1],
    creation = list(
      bundle_id = as.character(bundle_id)[1],
      bundle_name = as.character(bundle_name)[1],
      created_at = as.character(created_at)[1],
      id_policy = id_policy %||% list()
    ),
    counts = list(
      n_cells = as.integer(n_cells %||% 0L),
      n_datasets = as.integer(n_datasets %||% 0L),
      n_spaces = as.integer(n_spaces %||% 0L),
      n_features = as.integer(n_features %||% 0L),
      n_matrices = as.integer(if (nrow(mat_tbl)) nrow(mat_tbl) else 0L),
      n_artifacts = as.integer(if (.wb_table_exists(con, "artifacts")) DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM artifacts;")$n[1] else 0L)
    ),
    storage = list(
      sqlite = list(path = "db/app.sqlite"),
      matrices = if (nrow(mat_tbl) > 0L) split(mat_tbl, mat_tbl$matrix_id) else list()
    ),
    id_policy = id_policy %||% list(),
    current_state = registry_state,
    publication = list(
      protocol = "scworkbench.manifest.atomic.v1",
      state_source = "durable_manifest",
      published_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
    ),
    spaces = if (nrow(sp_tbl) > 0L) as.list(sp_tbl) else list(),
    artifacts = if (.wb_table_exists(con, "artifacts")) {
      art_tbl <- DBI::dbGetQuery(con, "SELECT artifact_id, type, name, created_at, source_op FROM artifacts ORDER BY created_at, artifact_id;")
      if (nrow(art_tbl)) as.list(art_tbl) else list()
    } else list()
  )
}

.wb_bundle_write_manifest <- function(bundle_dir, manifest) {
  .wb_assert(.wb_writer_lock_held(bundle_dir),
             "Manifest publication requires the exclusive bundle-writer lock.")
  final <- file.path(bundle_dir, "manifest.json")
  token <- paste0(Sys.getpid(), "-", paste(sample(c(letters, 0:9), 16L, TRUE), collapse = ""))
  staged <- file.path(bundle_dir, paste0(".manifest.json.staging-", token))
  on.exit({
    if (file.exists(staged)) unlink(staged, force = TRUE)
  }, add = TRUE)

  payload <- paste0(as.character(jsonlite::toJSON(
    manifest, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null"
  )), "\n")
  connection <- file(staged, open = "wb")
  write_error <- NULL
  tryCatch({
    writeBin(charToRaw(enc2utf8(payload)), connection)
    flush(connection)
  }, error = function(e) write_error <<- e)
  try(close(connection), silent = TRUE)
  if (!is.null(write_error)) stop(write_error)
  .wb_manifest_test_hook("staged", staged = staged, final = final, manifest = manifest)

  parsed <- tryCatch(
    jsonlite::read_json(staged, simplifyVector = FALSE),
    error = function(e) e
  )
  .wb_assert(!inherits(parsed, "error") && is.list(parsed),
             "Staged bundle manifest failed JSON validation; previous manifest was preserved.")
  .wb_assert(
    identical(as.character(parsed$scworkbench_manifest_version %||% ""),
              as.character(manifest$scworkbench_manifest_version %||% "")),
    "Staged bundle manifest failed schema validation; previous manifest was preserved."
  )
  .wb_manifest_test_hook("validated", staged = staged, final = final, manifest = manifest)
  .wb_manifest_test_hook("before_publish", staged = staged, final = final, manifest = manifest)

  # A same-directory rename is the publication commit point.  Platforms that
  # cannot atomically replace an existing name fail closed and retain the old
  # complete manifest; there is deliberately no remove/backup gap.
  replaced <- try(fs::file_move(staged, final), silent = TRUE)
  .wb_assert(!inherits(replaced, "try-error") && file.exists(final) && !file.exists(staged),
             "Atomic manifest publication failed; previous manifest was preserved and may disagree with committed registries until a guarded refresh succeeds.")
  .wb_manifest_test_hook("published", staged = staged, final = final, manifest = manifest)
  invisible(TRUE)
}

.wb_manifest_test_hook <- function(event, ...) {
  hook <- getOption("scworkbench.manifest_test_hook")
  if (is.function(hook)) hook(event = event, ...)
  invisible(TRUE)
}

.wb_manifest_publish_current_locked <- function(bundle_or_dir, result = NULL) {
  target <- .wb_writer_lock_target(bundle_or_dir)
  manifest_path <- file.path(target, "manifest.json")
  if (!dir.exists(target) || !file.exists(manifest_path)) return(invisible(FALSE))
  candidate <- if (inherits(bundle_or_dir, "scworkbench_bundle")) bundle_or_dir else
    if (inherits(result, "scworkbench_bundle")) result else NULL
  if (!is.null(candidate) && DBI::dbIsValid(candidate$con)) {
    .wb_assert(!isTRUE(RSQLite::sqliteIsTransacting(candidate$con)),
               "Manifest publication cannot precede the committed SQLite transaction.")
    .wb_refresh_manifest_committed(candidate)
    return(invisible(TRUE))
  }

  durable <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  db_rel <- as.character(durable$storage$sqlite$path %||% "")[1]
  db_path <- file.path(target, db_rel)
  if (!nzchar(db_rel) || !file.exists(db_path)) return(invisible(FALSE))
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  creation <- durable$creation %||% list(
    bundle_id = durable$bundle_id, bundle_name = durable$bundle_name,
    created_at = durable$created_at, id_policy = durable$id_policy %||% list()
  )
  refreshed <- .wb_bundle_build_manifest(
    target, con,
    bundle_id = as.character(creation$bundle_id %||% basename(target))[1],
    bundle_name = as.character(creation$bundle_name %||% creation$bundle_id %||% basename(target))[1],
    created_at = as.character(creation$created_at %||% NA_character_)[1],
    id_policy = creation$id_policy %||% list()
  )
  .wb_bundle_write_manifest(target, refreshed)
  invisible(TRUE)
}

.wb_bundle_ensure_default_cell_set_style <- function(con, cell_set = "core", created_by = "assembly") {
  hit <- DBI::dbGetQuery(con, "SELECT cell_set FROM cell_set_styles WHERE cell_set = ?;", params = list(cell_set))
  if (nrow(hit)) return(invisible(TRUE))
  DBI::dbExecute(
    con,
    "INSERT INTO cell_set_styles
       (cell_set, label, shape, size, alpha, stroke, outline, fill_mode, created_at, created_by, description)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    params = list(
      cell_set, cell_set,
      16L, 0.25, 0.35, 0.0,
      NA_character_, "fill",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      as.character(created_by %||% "assembly")[1],
      paste0("Default style for ", cell_set)
    )
  )
  invisible(TRUE)
}

.wb_ensure_schema_bundle <- function(con) {
  .wb_ensure_schema_app_bundle(con)
  invisible(TRUE)
}
