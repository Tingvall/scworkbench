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
  wb_open_bundle(out_dir)
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
  .wb_assert(is.character(set_name) && length(set_name) == 1L && nzchar(set_name),
             "set_name must be a non-empty string")

  ids <- unique(as.character(cell_ids))
  ids <- ids[nzchar(ids)]
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

  DBI::dbWriteTable(bundle$con, "cells", cells_df, append = TRUE)

  .wb_ensure_cell_set_membership_table(bundle$con)
  cell_set_name <- if (identical(set_name, "core")) "core" else paste0("set:", set_name)
  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  DBI::dbWriteTable(
    bundle$con,
    "cell_set_membership",
    data.frame(
      cell_set = cell_set_name,
      cell_id = ids,
      source = source,
      created_at = created_at,
      created_by = created_by %||% NA_character_,
      description = paste0("Defined cells for ", cell_set_name),
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )

  if (length(ids)) {
    tmp_name <- paste0("tmp_dataset_assign_", as.integer(Sys.time()), "_", paste(sample(c(letters, 0:9), 6, replace = TRUE), collapse = ""))
    DBI::dbWriteTable(
      bundle$con,
      tmp_name,
      data.frame(
        cell_id = ids,
        dataset_id = ds,
        stringsAsFactors = FALSE
      ),
      temporary = TRUE,
      overwrite = TRUE
    )
    DBI::dbExecute(
      bundle$con,
      sprintf(
        "UPDATE cells
            SET dataset_id = (SELECT t.dataset_id FROM %s t WHERE t.cell_id = cells.cell_id)
          WHERE cell_id IN (SELECT cell_id FROM %s);",
        tmp_name,
        tmp_name
      )
    )
    DBI::dbExecute(bundle$con, sprintf("DROP TABLE IF EXISTS %s;", tmp_name))

    ds_tab <- as.data.frame(table(DBI::dbGetQuery(bundle$con, "SELECT dataset_id FROM cells;")$dataset_id), stringsAsFactors = FALSE)
    if (nrow(ds_tab)) {
      colnames(ds_tab) <- c("dataset_id", "n_cells")
      ds_tab$n_cells <- as.integer(ds_tab$n_cells)
      DBI::dbExecute(bundle$con, "DELETE FROM datasets;")
      DBI::dbWriteTable(bundle$con, "datasets", ds_tab, append = TRUE)
    }
  }

  if (identical(set_name, "core")) {
    .wb_bundle_ensure_default_cell_set_style(bundle$con, "core", created_by = created_by %||% source)
  }

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
  wb_refresh_manifest(bundle)
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
  wb_refresh_manifest(bundle)
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
  wb_refresh_manifest(bundle)
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
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  man_old <- try(bundle$manifest, silent = TRUE)
  if (inherits(man_old, "try-error") || !is.list(man_old)) man_old <- list()

  manifest <- .wb_bundle_build_manifest(
    bundle_dir = bundle$dir,
    con = con,
    bundle_id = as.character(man_old$bundle_id %||% basename(bundle$dir))[1],
    bundle_name = as.character(man_old$bundle_name %||% man_old$bundle_id %||% basename(bundle$dir))[1],
    created_at = as.character(man_old$created_at %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))[1],
    id_policy = man_old$id_policy %||% list()
  )
  .wb_bundle_write_manifest(bundle$dir, manifest)
  invisible(manifest)
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

  list(
    scworkbench_manifest_version = "2.0.0",
    bundle_id = as.character(bundle_id)[1],
    bundle_name = as.character(bundle_name)[1],
    created_at = as.character(created_at)[1],
    counts = list(
      n_cells = as.integer(n_cells %||% 0L),
      n_datasets = as.integer(n_datasets %||% 0L),
      n_spaces = as.integer(n_spaces %||% 0L),
      n_features = as.integer(n_features %||% 0L),
      n_matrices = as.integer(if (nrow(mat_tbl)) nrow(mat_tbl) else 0L)
    ),
    storage = list(
      sqlite = list(path = "db/app.sqlite"),
      matrices = if (nrow(mat_tbl) > 0L) split(mat_tbl, mat_tbl$matrix_id) else list()
    ),
    id_policy = id_policy %||% list(),
    spaces = if (nrow(sp_tbl) > 0L) as.list(sp_tbl) else list()
  )
}

.wb_bundle_write_manifest <- function(bundle_dir, manifest) {
  jsonlite::write_json(
    manifest,
    file.path(bundle_dir, "manifest.json"),
    pretty = TRUE,
    auto_unbox = TRUE,
    null = "null"
  )
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
