#' Publish a scworkbench app bundle from a Seurat object
#'
#' This is the "Average Joe" entry point:
#'   wb_publish_app_bundle(seurat)
#'
#' A published bundle is matrix_id-native:
#' - Seurat assays are only used during export.
#' - The SQLite schema stores features keyed by matrix_id (NOT assay).
#' - matrices table has no assay column.
#'
#' Output bundle layout:
#'   <out_dir>/
#'     manifest.json
#'     db/app.sqlite
#'     mat/<matrix_id>/   (BPCells matrix dir)
#'
#' @param seurat A Seurat object.
#' @param out_dir Output directory for the bundle. If NULL, a default is chosen.
#' @param dataset_col Optional meta.data column to define dataset_id (defaults to orig.ident if present).
#' @param bundle_id Optional bundle_id used for default out_dir naming.
#' @param bundle_name Optional human-readable name for manifest.
#' @param overwrite If TRUE, overwrite out_dir if it exists.
#' @param export_assays Seurat assays to export. If NULL, chooses sane defaults (RNA + one ATAC-like if present).
#' @param matrix_layer Seurat layer/slot to export (default "counts").
#' @param matrix_specs Optional list of specs; if NULL, derived from export_assays.
#'   Each spec is a list with fields:
#'     matrix_id, seurat_assay, layer, feature_type, description
#' @param feature_type_map Optional named character vector mapping seurat_assay -> feature_type ("gene"/"peak").
#' @param write_spaces If TRUE, exports Seurat reductions as spaces (2D to space_2d, else to space_coords).
#' @param write_matrices If TRUE, exports matrices via BPCells and registers fragments.
#'
#' @return The manifest list (invisibly).
#' @export
wb_publish_app_bundle <- function(
    seurat,
    out_dir = NULL,
    dataset_col = NULL,
    bundle_id = NULL,
    bundle_name = NULL,
    overwrite = FALSE,
    export_assays = NULL,
    matrix_layer = "counts",
    matrix_specs = NULL,
    feature_type_map = NULL,
    write_spaces = TRUE,
    write_matrices = TRUE
) {
  .wb_assert(inherits(seurat, "Seurat"), "seurat must be a Seurat object")

  # ---- defaults ----
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  if (is.null(bundle_id) || !nzchar(bundle_id)) bundle_id <- paste0("scworkbench_", stamp)
  if (is.null(bundle_name) || !nzchar(bundle_name)) bundle_name <- bundle_id

  if (is.null(out_dir) || !nzchar(out_dir)) {
    base_out <- Sys.getenv("SCWORKBENCH_OUT_DIR", unset = "")
    if (!nzchar(base_out)) base_out <- file.path(getwd(), "scworkbench_bundles")
    out_dir <- file.path(base_out, bundle_id)
  }

  # dataset_col
  meta <- seurat@meta.data
  if (is.null(dataset_col) || !nzchar(dataset_col)) {
    dataset_col <- if ("orig.ident" %in% colnames(meta)) "orig.ident" else NULL
  }

  # export_assays
  if (is.null(export_assays)) export_assays <- .wb_default_export_assays(seurat)

  # matrix_specs
  if (is.null(matrix_specs)) {
    matrix_specs <- .wb_default_matrix_specs(
      seurat = seurat,
      layer = matrix_layer,
      export_assays = export_assays,
      feature_type_map = feature_type_map
    )
  }
  .wb_assert(is.list(matrix_specs), "matrix_specs must be a list")
  if (length(matrix_specs) == 0 && isTRUE(write_matrices)) {
    warning("No matrix_specs resolved; write_matrices=TRUE but nothing to export.")
  }

  # ---- prepare dirs ----
  if (dir.exists(out_dir)) {
    if (!isTRUE(overwrite)) stop("out_dir exists: ", out_dir, " (set overwrite=TRUE)", call. = FALSE)
    unlink(out_dir, recursive = TRUE, force = TRUE)
  }
  dir.create(file.path(out_dir, "db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "mat"), recursive = TRUE, showWarnings = FALSE)

  # ---- ids ----
  cell_id <- colnames(seurat)
  .wb_assert(length(cell_id) > 0, "Seurat has no cells (colnames(seurat) empty)")

  if (!is.null(dataset_col) && dataset_col %in% colnames(meta)) {
    dataset_id <- as.character(meta[[dataset_col]])
    dataset_id_source <- paste0("meta.data.", dataset_col)
  } else {
    dataset_id <- rep("dataset_1", length(cell_id))
    dataset_id_source <- "fallback: dataset_1"
  }
  .wb_assert(length(dataset_id) == length(cell_id), "dataset_id length mismatch")

  # ---- open sqlite ----
  db_path <- file.path(out_dir, "db", "app.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # ---- schema (ASSAY-FREE) ----
  .wb_ensure_schema_app_bundle(con)

  # ---- datasets ----
  ds_tab <- as.data.frame(table(dataset_id), stringsAsFactors = FALSE)
  colnames(ds_tab) <- c("dataset_id", "n_cells")
  ds_tab$n_cells <- as.integer(ds_tab$n_cells)
  DBI::dbExecute(con, "DELETE FROM datasets;")
  DBI::dbWriteTable(con, "datasets", ds_tab, append = TRUE)

  # ---- cells + metadata ----
  cells_df <- data.frame(
    cell_id = cell_id,
    dataset_id = dataset_id,
    stringsAsFactors = FALSE
  )

  meta2 <- meta
  for (nm in colnames(meta2)) {
    x <- meta2[[nm]]
    if (is.factor(x)) x <- as.character(x)
    if (is.logical(x)) x <- as.integer(x)
    meta2[[nm]] <- x
  }
  meta2$cell_id <- rownames(meta2)
  meta2 <- meta2[match(cell_id, meta2$cell_id), , drop = FALSE]
  .wb_assert(!anyNA(match(cell_id, rownames(meta2))), "meta.data rows not aligned to Seurat colnames (unexpected)")
  meta2$cell_id <- NULL

  cells_df <- cbind(cells_df, meta2)

  # Add metadata columns dynamically (idempotent)
  existing_cols <- DBI::dbGetQuery(con, "PRAGMA table_info(cells);")$name
  for (nm in setdiff(colnames(cells_df), c("cell_id", "dataset_id"))) {
    if (nm %in% existing_cols) next
    x <- cells_df[[nm]]
    col_type <- if (is.numeric(x)) "REAL" else "TEXT"
    if (is.integer(x)) col_type <- "INTEGER"
    DBI::dbExecute(con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
  }

  DBI::dbExecute(con, "DELETE FROM cells;")
  DBI::dbWriteTable(con, "cells", cells_df, append = TRUE)

  # ---- core cell set membership ----
  DBI::dbExecute(con, "DELETE FROM cell_set_membership;")
  core_df <- data.frame(
    cell_set    = "core",
    cell_id     = cell_id,
    source      = "publish",
    created_at  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    created_by  = NA_character_,
    description = "Published atlas core cells",
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "cell_set_membership", core_df, append = TRUE)
  DBI::dbExecute(con, "DELETE FROM cell_set_styles WHERE cell_set = 'core';")
  DBI::dbExecute(
    con,
    "INSERT INTO cell_set_styles
   (cell_set, label, shape, size, alpha, stroke, outline, fill_mode, created_at, created_by, description)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    params = list(
      "core", "core",
      16L, 0.25, 0.35, 0.0,
      NA_character_, "fill",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      "publish",
      "Default style for core"
    )
  )


  # ---- spaces (reductions) ----
  if (isTRUE(write_spaces)) {
    reductions <- names(seurat@reductions)

    DBI::dbExecute(con, "DELETE FROM spaces;")
    DBI::dbExecute(con, "DELETE FROM space_coords;")
    DBI::dbExecute(con, "DELETE FROM space_2d;")

    write_space_long <- function(space_id, emb) {
      dims <- ncol(emb)
      chunk <- 20000L
      idx <- seq_len(nrow(emb))
      for (s in seq(1, length(idx), by = chunk)) {
        ii <- idx[s:min(s + chunk - 1, length(idx))]
        sub <- emb[ii, , drop = FALSE]
        df_long <- do.call(rbind, lapply(seq_len(dims), function(d) {
          data.frame(
            space_id = space_id,
            cell_id  = rownames(sub),
            dim      = d,
            value    = as.numeric(sub[, d]),
            stringsAsFactors = FALSE
          )
        }))
        DBI::dbWriteTable(con, "space_coords", df_long, append = TRUE)
      }
    }

    write_space_2d <- function(space_id, emb, cell_id_order) {
      emb <- emb[match(cell_id_order, rownames(emb)), , drop = FALSE]
      df <- data.frame(
        space_id = space_id,
        cell_id  = cell_id_order,
        x        = as.numeric(emb[, 1]),
        y        = as.numeric(emb[, 2]),
        stringsAsFactors = FALSE
      )
      DBI::dbWriteTable(con, "space_2d", df, append = TRUE)
    }

    for (r in reductions) {
      emb <- seurat@reductions[[r]]@cell.embeddings
      dims <- ncol(emb)

      if (dims == 2) {
        DBI::dbWriteTable(con, "spaces", data.frame(
          space_id = r,
          source = "Seurat reduction",
          dims = 2L,
          storage = "wide:space_2d",
          description = r,
          stringsAsFactors = FALSE
        ), append = TRUE)
        write_space_2d(r, emb, cell_id)
      } else {
        DBI::dbWriteTable(con, "spaces", data.frame(
          space_id = r,
          source = "Seurat reduction",
          dims = as.integer(dims),
          storage = "long:space_coords",
          description = r,
          stringsAsFactors = FALSE
        ), append = TRUE)
        write_space_long(r, emb)
      }
    }
  }
  .wb_create_artifacts_schema(con)

  # ---- matrices + features + fragments (ASSAY-FREE DB; assay only inside spec) ----
  DBI::dbExecute(con, "DELETE FROM matrices;")
  DBI::dbExecute(con, "DELETE FROM matrix_fragments;")
  DBI::dbExecute(con, "DELETE FROM features;")

  if (length(matrix_specs) > 0) {
    .wb_register_features_for_specs_matrix_id(con, seurat, matrix_specs)
  }

  if (isTRUE(write_matrices) && length(matrix_specs) > 0) {
    for (sp in matrix_specs) {
      .wb_write_and_register_matrix_from_spec(con, seurat, out_dir, sp, cell_ids = cell_id)
    }
  }

  # ---- manifest ----
  mat_tbl <- try(DBI::dbReadTable(con, "matrices"), silent = TRUE)
  if (inherits(mat_tbl, "try-error")) mat_tbl <- data.frame()

  feats_tbl <- try(DBI::dbReadTable(con, "features"), silent = TRUE)
  if (inherits(feats_tbl, "try-error")) feats_tbl <- data.frame()

  n_spaces <- 0L
  if (isTRUE(write_spaces)) {
    sp_tbl <- try(DBI::dbReadTable(con, "spaces"), silent = TRUE)
    if (!inherits(sp_tbl, "try-error")) n_spaces <- nrow(sp_tbl)
  }

  manifest <- list(
    scworkbench_manifest_version = "2.0.0",
    bundle_id = bundle_id,
    bundle_name = bundle_name,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    counts = list(
      n_cells = length(cell_id),
      n_datasets = length(unique(dataset_id)),
      n_spaces = as.integer(n_spaces),
      n_features = nrow(feats_tbl),
      n_matrices = nrow(mat_tbl)
    ),
    storage = list(
      sqlite = list(path = "db/app.sqlite"),
      matrices = if (nrow(mat_tbl) > 0) split(mat_tbl, mat_tbl$matrix_id) else list()
    ),
    id_policy = list(
      cell_id_source = "colnames(seurat)",
      dataset_id_source = dataset_id_source,
      feature_id_source = "rownames(seurat@assays[[spec$seurat_assay]]) per matrix_spec (publisher-only seurat_assay)",
      matrix_specs = matrix_specs
    ),
    spaces = if (isTRUE(write_spaces)) as.list(try(DBI::dbReadTable(con, "spaces"), silent = TRUE)) else list()
  )

  jsonlite::write_json(
    manifest,
    file.path(out_dir, "manifest.json"),
    pretty = TRUE,
    auto_unbox = TRUE
  )

  cat("=== scworkbench: bundle written ===\n")
  cat("Bundle:", out_dir, "\n")
  cat(" - SQLite:", db_path, "\n")
  cat(" - Manifest:", file.path(out_dir, "manifest.json"), "\n")
  if (isTRUE(write_matrices)) cat(" - Matrices:", file.path(out_dir, "mat"), "\n")

  invisible(manifest)
}

# ==============================================================================
# Internals
# ==============================================================================

`%||%` <- function(a, b) {
  if (!is.null(a) && length(a) > 0) a else b
}

.wb_default_export_assays <- function(seurat) {
  assays <- names(seurat@assays)
  chosen <- character(0)

  if ("RNA" %in% assays) chosen <- c(chosen, "RNA")

  atac_candidates <- c("ATAC", "peaks", "Chromatin", "chromatin", "Peak", "Peaks")
  atac_hit <- intersect(atac_candidates, assays)
  if (length(atac_hit) > 0) chosen <- c(chosen, atac_hit[1])

  if (length(chosen) == 0) chosen <- setdiff(assays, c("SCT"))
  unique(chosen)
}

.wb_guess_feature_type <- function(feature_ids) {
  sample_ids <- feature_ids[seq_len(min(2000, length(feature_ids)))]
  peakish <- mean(grepl("^[^:]+:[0-9]+-[0-9]+$", sample_ids))
  if (is.finite(peakish) && peakish > 0.5) return("peak")
  "gene"
}

wb_matrix_spec <- function(matrix_id,
                           seurat_assay,
                           layer = "counts",
                           feature_type = c("gene", "peak", "feature"),
                           description = NULL) {
  feature_type <- match.arg(feature_type)
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id required")
  .wb_assert(is.character(seurat_assay) && length(seurat_assay) == 1 && nzchar(seurat_assay), "seurat_assay required")

  list(
    matrix_id = matrix_id,
    seurat_assay = seurat_assay,  # publisher-only
    layer = layer,
    feature_type = feature_type,
    description = description %||% paste0(
      "Matrix from Seurat assay '", seurat_assay, "' layer '", layer, "' (", feature_type, ")"
    )
  )
}

.wb_default_matrix_specs <- function(seurat, layer = "counts",
                                     export_assays = NULL,
                                     feature_type_map = NULL) {
  assays <- names(seurat@assays)
  if (!is.null(export_assays)) assays <- intersect(assays, export_assays)

  specs <- list()
  for (a in assays) {
    feats <- rownames(seurat@assays[[a]])
    if (length(feats) == 0) next

    ft <- if (!is.null(feature_type_map) && a %in% names(feature_type_map)) {
      as.character(feature_type_map[[a]])
    } else {
      .wb_guess_feature_type(feats)
    }

    specs[[length(specs) + 1]] <- wb_matrix_spec(
      matrix_id = paste0(a, "_", layer),
      seurat_assay = a,
      layer = layer,
      feature_type = ft,
      description = paste0("Exported from Seurat assay '", a, "' (feature_type=", ft, ")")
    )
  }
  specs
}

.wb_parse_peak_ids <- function(peak_ids) {
  parsed <- do.call(rbind, lapply(peak_ids, function(pid) {
    m <- regexec("^([^:]+):([0-9]+)-([0-9]+)$", pid)
    r <- regmatches(pid, m)[[1]]
    if (length(r) == 4) c(chr = r[2], start = r[3], end = r[4]) else c(chr = NA, start = NA, end = NA)
  }))

  data.frame(
    chr = parsed[, "chr"],
    start = suppressWarnings(as.integer(parsed[, "start"])),
    end = suppressWarnings(as.integer(parsed[, "end"])),
    stringsAsFactors = FALSE
  )
}

.wb_ensure_schema_app_bundle <- function(con) {
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "PRAGMA synchronous=NORMAL;")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS datasets (
      dataset_id TEXT PRIMARY KEY,
      n_cells INTEGER
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cells (
      cell_id TEXT PRIMARY KEY,
      dataset_id TEXT
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_cells_dataset ON cells(dataset_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_membership (
      cell_set    TEXT NOT NULL,
      cell_id     TEXT NOT NULL,
      source      TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT,
      PRIMARY KEY (cell_set, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_set  ON cell_set_membership(cell_set);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_cell ON cell_set_membership(cell_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS spaces (
      space_id TEXT PRIMARY KEY,
      source TEXT,
      dims INTEGER,
      storage TEXT,
      description TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_coords (
      space_id TEXT,
      cell_id TEXT,
      dim INTEGER,
      value REAL,
      PRIMARY KEY (space_id, cell_id, dim)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_coords_space ON space_coords(space_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_coords_cell  ON space_coords(cell_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_2d (
      space_id TEXT,
      cell_id TEXT,
      x REAL,
      y REAL,
      PRIMARY KEY (space_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_2d_space ON space_2d(space_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_2d_cell  ON space_2d(cell_id);")

  # ---- ASSAY-FREE FEATURES: keyed by matrix_id ----
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS features (
      matrix_id    TEXT NOT NULL,
      feature_id   TEXT NOT NULL,
      feature_type TEXT,
      chr          TEXT,
      start        INTEGER,
      end          INTEGER,
      PRIMARY KEY (matrix_id, feature_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_features_matrix ON features(matrix_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_features_feature ON features(feature_id);")

  # ---- ASSAY-FREE MATRICES ----
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrices (
      matrix_id    TEXT PRIMARY KEY,
      layer        TEXT,
      feature_type TEXT,
      n_features   INTEGER,
      n_cells      INTEGER,
      storage      TEXT,
      path         TEXT,
      description  TEXT,
      organism     TEXT,
      genome_build TEXT,
      genome_provider TEXT
    );
  ")

  # optional (harmless)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_cells (
      matrix_id TEXT,
      cell_id   TEXT,
      PRIMARY KEY (matrix_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_matrix_cells_cell   ON matrix_cells(cell_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_matrix_cells_matrix ON matrix_cells(matrix_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_styles (
      cell_set    TEXT PRIMARY KEY,
      label       TEXT,
      shape       INTEGER,
      size        REAL,
      alpha       REAL,
      stroke      REAL,
      outline     TEXT,
      fill_mode   TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT
    );
  ")

  # ---- fragments ----
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_fragments (
      fragment_id      TEXT PRIMARY KEY,
      matrix_id        TEXT NOT NULL,
      storage          TEXT NOT NULL,
      path             TEXT NOT NULL,
      n_features       INTEGER,
      n_cells          INTEGER,
      feature_ids_json TEXT NOT NULL,
      cell_ids_json    TEXT NOT NULL,
      source           TEXT,
      created_at       TEXT NOT NULL,
      description      TEXT
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mf_matrix_id ON matrix_fragments(matrix_id);")

  .wb_create_cell_set_styles_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_styles (
      cell_set    TEXT PRIMARY KEY,
      label       TEXT,
      shape       INTEGER,
      size        REAL,
      alpha       REAL,
      stroke      REAL,
      outline     TEXT,
      fill_mode   TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT
    );
  ")
  invisible(TRUE)
}


  invisible(TRUE)
}

.wb_register_features_for_specs_matrix_id <- function(con, seurat, matrix_specs) {
  for (sp in matrix_specs) {
    mid <- sp$matrix_id
    a   <- sp$seurat_assay
    ft  <- sp$feature_type %||% "feature"

    feature_ids <- rownames(seurat@assays[[a]])
    if (length(feature_ids) == 0) next

    if (identical(ft, "peak")) {
      peak_df <- .wb_parse_peak_ids(feature_ids)
      feats_df <- data.frame(
        matrix_id    = mid,
        feature_id   = feature_ids,
        feature_type = "peak",
        chr          = peak_df$chr,
        start        = peak_df$start,
        end          = peak_df$end,
        stringsAsFactors = FALSE
      )
    } else {
      feats_df <- data.frame(
        matrix_id    = mid,
        feature_id   = feature_ids,
        feature_type = ft,
        chr          = NA_character_,
        start        = NA_integer_,
        end          = NA_integer_,
        stringsAsFactors = FALSE
      )
    }

    DBI::dbExecute(con, "DELETE FROM features WHERE matrix_id = ?;", params = list(mid))
    DBI::dbWriteTable(con, "features", feats_df, append = TRUE)
  }

  invisible(TRUE)
}

.get_assay_counts <- function(seurat, assay, layer_or_slot = "counts") {
  a <- seurat@assays[[assay]]
  .wb_assert(!is.null(a), paste0("Unknown assay: ", assay))

  if (inherits(a, "Assay5")) {
    m <- SeuratObject::LayerData(a, layer = layer_or_slot)
  } else if (methods::is(a, "Assay") && layer_or_slot %in% methods::slotNames(a)) {
    m <- methods::slot(a, layer_or_slot)
  } else if (requireNamespace("Seurat", quietly = TRUE)) {
    fmls <- names(formals(Seurat::GetAssayData))
    if ("layer" %in% fmls) {
      m <- Seurat::GetAssayData(seurat, assay = assay, layer = layer_or_slot)
    } else {
      m <- Seurat::GetAssayData(seurat, assay = assay, slot = layer_or_slot)
    }
  } else {
    stop(
      "Could not resolve assay data for assay '", assay,
      "' layer/slot '", layer_or_slot,
      "'. Install Seurat or use a SeuratObject-supported assay layout.",
      call. = FALSE
    )
  }
  if (!inherits(m, "Matrix")) m <- Matrix::Matrix(m, sparse = TRUE)
  m
}

.align_matrix_to_ids <- function(m, feature_ids, cell_ids) {
  .wb_assert(!is.null(rownames(m)) && !is.null(colnames(m)),
             "Matrix must have rownames (features) and colnames (cells) to align")
  fi <- match(feature_ids, rownames(m))
  ci <- match(cell_ids, colnames(m))
  .wb_assert(!anyNA(fi), "Some features missing in assay matrix (unexpected)")
  .wb_assert(!anyNA(ci), "Some cells missing in assay matrix (unexpected)")
  m[fi, ci, drop = FALSE]
}

.write_bpcells_dir <- function(mat, out_dir, overwrite = TRUE) {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    stop("BPCells not installed. Install it or set write_matrices=FALSE.", call. = FALSE)
  }
  if (dir.exists(out_dir) || file.exists(out_dir)) {
    if (!isTRUE(overwrite)) stop("BPCells matrix path exists: ", out_dir, call. = FALSE)
    unlink(out_dir, recursive = TRUE, force = TRUE)
  }
  # BPCells expects output dir not to exist
  BPCells::write_matrix_dir(mat, out_dir)
  invisible(TRUE)
}

.wb_new_fragment_id <- function(matrix_id) {
  paste0(
    "mf_", matrix_id, "_",
    format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
    paste0(sample(c(0:9, letters), 8, TRUE), collapse = "")
  )
}

wb_register_matrix_fragment <- function(con, matrix_id, path_rel,
                                        feature_ids, cell_ids,
                                        source = NULL,
                                        created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                        description = NULL) {
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(path_rel) && length(path_rel) == 1 && nzchar(path_rel), "path_rel invalid")
  .wb_assert(is.character(feature_ids) && length(feature_ids) > 0, "feature_ids empty")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids empty")

  frag_id <- .wb_new_fragment_id(matrix_id)

  df <- data.frame(
    fragment_id      = frag_id,
    matrix_id        = matrix_id,
    storage          = "bpcells",
    path             = path_rel,
    n_features       = as.integer(length(feature_ids)),
    n_cells          = as.integer(length(cell_ids)),
    feature_ids_json = jsonlite::toJSON(as.list(feature_ids), auto_unbox = TRUE),
    cell_ids_json    = jsonlite::toJSON(as.list(cell_ids), auto_unbox = TRUE),
    source           = source %||% NA_character_,
    created_at       = created_at,
    description      = description %||% NA_character_,
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, "matrix_fragments", df, append = TRUE)
  frag_id
}

.wb_write_and_register_matrix_from_spec <- function(con, seurat, out_dir, spec, cell_ids) {
  mid <- spec$matrix_id
  a   <- spec$seurat_assay
  lyr <- spec$layer %||% "counts"
  ft  <- spec$feature_type %||% "feature"

  .wb_assert(nzchar(mid), "spec$matrix_id required")
  .wb_assert(nzchar(a), "spec$seurat_assay required")

  feature_ids <- rownames(seurat@assays[[a]])
  if (length(feature_ids) == 0) stop("No features in Seurat assay: ", a, call. = FALSE)

  m <- .get_assay_counts(seurat, assay = a, layer_or_slot = lyr)
  m <- .align_matrix_to_ids(m, feature_ids = feature_ids, cell_ids = cell_ids)

  rel_path <- file.path("mat", mid)
  abs_path <- file.path(out_dir, rel_path)
  .write_bpcells_dir(m, abs_path, overwrite = TRUE)

  # registry row (NO assay)
  DBI::dbExecute(con, "DELETE FROM matrices WHERE matrix_id = ?;", params = list(mid))
  DBI::dbWriteTable(
    con, "matrices",
    data.frame(
      matrix_id    = mid,
      layer        = lyr,
      feature_type = ft,
      n_features   = as.integer(nrow(m)),
      n_cells      = as.integer(ncol(m)),
      storage      = "bpcells",
      path         = rel_path,
      description  = spec$description %||% NA_character_,
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )

  wb_register_matrix_fragment(
    con         = con,
    matrix_id   = mid,
    path_rel    = rel_path,
    feature_ids = feature_ids,
    cell_ids    = cell_ids,
    source      = "publish",
    created_at  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    description = spec$description %||% NA_character_
  )

  invisible(TRUE)
}
