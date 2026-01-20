# scworkbench: publish_app_bundle() with "Average Joe" defaults + power-user overrides
# - Average Joe: publish_app_bundle(seurat)
# - Power users: override args OR set options(scworkbench.*)
#
# Requires: DBI, RSQLite, jsonlite, Seurat, Matrix, BPCells (optional if write_matrices=TRUE)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && nzchar(as.character(a[1]))) a else b

wb_resolve <- function(arg, opt_name, fallback) {
  if (!is.null(arg)) return(arg)
  opt <- getOption(opt_name, NULL)
  if (!is.null(opt)) return(opt)
  fallback
}

wb_guess_feature_type <- function(feature_ids) {
  # Heuristic: peaks typically look like chr:start-end
  sample_ids <- feature_ids[seq_len(min(2000, length(feature_ids)))]
  peakish <- mean(grepl("^[^:]+:[0-9]+-[0-9]+$", sample_ids))
  if (is.finite(peakish) && peakish > 0.5) return("peak")
  return("gene")
}

wb_default_export_assays <- function(seurat) {
  assays <- names(seurat@assays)
  chosen <- character(0)

  # 1) RNA (raw)
  if ("RNA" %in% assays) chosen <- c(chosen, "RNA")

  # 2) ATAC-ish: pick the first matching common name
  atac_candidates <- c("peaks", "ATAC", "Chromatin", "chromatin", "Peak", "Peaks")
  atac_hit <- intersect(atac_candidates, assays)
  if (length(atac_hit) > 0) chosen <- c(chosen, atac_hit[1])

  # If nothing matched, fall back to: all assays except SCT
  if (length(chosen) == 0) {
    chosen <- setdiff(assays, c("SCT"))
  }

  unique(chosen)
}


wb_matrix_spec <- function(matrix_id, assay, slot = "counts",
                           feature_type = c("gene", "peak", "feature"),
                           description = NULL) {
  feature_type <- match.arg(feature_type)
  list(
    matrix_id = matrix_id,
    assay = assay,
    slot = slot,
    feature_type = feature_type,
    description = description %||% paste0("Matrix from assay '", assay, "' slot '", slot, "' (", feature_type, ")")
  )
}

wb_default_matrix_specs <- function(seurat, slot = "counts", export_assays = NULL, feature_type_map = NULL) {
  assays <- names(seurat@assays)
  if (!is.null(export_assays)) assays <- intersect(assays, export_assays)

  specs <- list()
  for (assay in assays) {
    feats <- rownames(seurat@assays[[assay]])
    if (length(feats) == 0) next

    ft <- NULL
    if (!is.null(feature_type_map) && assay %in% names(feature_type_map)) {
      ft <- as.character(feature_type_map[[assay]])
    } else {
      ft <- wb_guess_feature_type(feats)
    }

    specs[[length(specs) + 1]] <- wb_matrix_spec(
      matrix_id = paste0(assay, "_", slot),
      assay = assay,
      slot = slot,
      feature_type = ft,
      description = paste0("Exported matrix from assay '", assay, "' (feature_type=", ft, ")")
    )
  }
  specs
}

wb_parse_peak_ids <- function(peak_ids) {
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

wb_register_features_for_specs <- function(con, seurat, matrix_specs) {
  assays_needed <- unique(vapply(matrix_specs, `[[`, character(1), "assay"))

  for (assay in assays_needed) {
    feature_ids <- rownames(seurat@assays[[assay]])
    if (length(feature_ids) == 0) next

    # Find declared feature_type for this assay (first spec match)
    ft <- NULL
    for (sp in matrix_specs) if (identical(sp$assay, assay)) { ft <- sp$feature_type; break }
    ft <- ft %||% wb_guess_feature_type(feature_ids)

    if (identical(ft, "peak")) {
      peak_df <- wb_parse_peak_ids(feature_ids)
      feats_df <- data.frame(
        assay = assay,
        feature_id = feature_ids,
        feature_type = "peak",
        chr = peak_df$chr,
        start = peak_df$start,
        end = peak_df$end,
        stringsAsFactors = FALSE
      )
    } else {
      feats_df <- data.frame(
        assay = assay,
        feature_id = feature_ids,
        feature_type = ft,
        chr = NA_character_,
        start = NA_integer_,
        end = NA_integer_,
        stringsAsFactors = FALSE
      )
    }

    DBI::dbExecute(con, "DELETE FROM features WHERE assay = ?;", params = list(assay))
    DBI::dbWriteTable(con, "features", feats_df, append = TRUE)
  }
}

.get_assay_counts <- function(seurat, assay, layer_or_slot = "counts") {
  # SeuratObject v5: GetAssayData(layer=) preferred
  fmls <- names(formals(Seurat::GetAssayData))

  if ("layer" %in% fmls) {
    m <- Seurat::GetAssayData(seurat, assay = assay, layer = layer_or_slot)
  } else {
    m <- Seurat::GetAssayData(seurat, assay = assay, slot  = layer_or_slot)
  }

  if (!inherits(m, "Matrix")) m <- Matrix::Matrix(m, sparse = TRUE)
  m
}


.align_matrix_to_ids <- function(m, feature_ids, cell_ids) {
  if (is.null(rownames(m)) || is.null(colnames(m))) {
    stop("Matrix must have rownames (features) and colnames (cells) to align safely.")
  }
  m2 <- m[match(feature_ids, rownames(m)), match(cell_ids, colnames(m)), drop = FALSE]
  if (anyNA(match(feature_ids, rownames(m)))) stop("Some features missing in assay matrix (unexpected).")
  if (anyNA(match(cell_ids, colnames(m)))) stop("Some cells missing in assay matrix (unexpected).")
  m2
}

.write_bpcells_dir <- function(mat, out_dir, overwrite = TRUE) {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    stop("BPCells not installed. Install it or set write_matrices=FALSE.")
  }

  # BPCells expects out_dir NOT to exist.
  if (dir.exists(out_dir) || file.exists(out_dir)) {
    if (!isTRUE(overwrite)) stop("BPCells matrix path already exists: ", out_dir)

    unlink(out_dir, recursive = TRUE, force = TRUE)

    # sanity check: if it still exists, fail loudly (permissions, NFS oddities, etc.)
    if (dir.exists(out_dir) || file.exists(out_dir)) {
      stop("Failed to remove existing BPCells path: ", out_dir,
           "\nCheck permissions or whether another process is using it.")
    }
  }

  # DO NOT dir.create(out_dir) — BPCells will create it.

  # Prefer write_matrix_dir if present
  if (exists("write_matrix_dir", where = asNamespace("BPCells"), mode = "function")) {
    f <- get("write_matrix_dir", envir = asNamespace("BPCells"))

    # Pass overwrite only if the function supports it
    if ("overwrite" %in% names(formals(f))) {
      BPCells::write_matrix_dir(mat, out_dir, overwrite = isTRUE(overwrite))
    } else {
      BPCells::write_matrix_dir(mat, out_dir)
    }
    return(invisible(TRUE))
  }

  # Fallback: some versions use write_matrix()
  if (exists("write_matrix", where = asNamespace("BPCells"), mode = "function")) {
    f <- get("write_matrix", envir = asNamespace("BPCells"))
    if ("overwrite" %in% names(formals(f))) {
      BPCells::write_matrix(mat, out_dir, overwrite = isTRUE(overwrite))
    } else {
      BPCells::write_matrix(mat, out_dir)
    }
    return(invisible(TRUE))
  }

  stop(
    "Could not find a supported BPCells writer. Expected BPCells::write_matrix_dir() or BPCells::write_matrix().\n",
    "BPCells exports: ", paste(ls(getNamespace("BPCells")), collapse = ", ")
  )
}


wb_write_and_register_matrix_from_spec <- function(con, seurat, out_dir, spec, cell_ids) {
  assay <- spec$assay
  slot <- spec$slot

  feature_ids <- rownames(seurat@assays[[assay]])
  if (length(feature_ids) == 0) stop("No features in assay: ", assay)

  m <- .get_assay_counts(seurat, assay = assay, layer_or_slot = slot)
  m <- .align_matrix_to_ids(m, feature_ids = feature_ids, cell_ids = cell_ids)

  rel_path <- file.path("mat", spec$matrix_id)
  abs_path <- file.path(out_dir, rel_path)
  .write_bpcells_dir(m, abs_path, overwrite = TRUE)


  DBI::dbExecute(con, "DELETE FROM matrices WHERE matrix_id = ?;", params = list(spec$matrix_id))
  DBI::dbWriteTable(
    con, "matrices",
    data.frame(
      matrix_id = spec$matrix_id,
      assay = assay,
      layer = slot,
      feature_type = spec$feature_type,
      n_features = nrow(m),
      n_cells = ncol(m),
      storage = "bpcells",
      path = rel_path,
      description = spec$description,
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )

  invisible(TRUE)
}

#' Publish a Seurat object into an scworkbench AppBundle
#'
#' Average Joe:
#'   publish_app_bundle(seurat)
#'
#' Power users can override via arguments or options():
#'   options(scworkbench.out_dir = "/path/to/bundles")
#'   options(scworkbench.overwrite = TRUE)
#'   options(scworkbench.dataset_col = "orig.ident")
#'   options(scworkbench.export_assays = c("RNA","ATAC"))
#'   options(scworkbench.matrix_slot = "counts")
#'
#' @param seurat Seurat object
#' @param out_dir Optional bundle directory. If NULL, uses option scworkbench.out_dir or ./scworkbench_bundles/<bundle_id>
#' @param dataset_col Column in meta.data used as dataset id (default: option scworkbench.dataset_col, else "orig.ident" if present, else fallback dataset_1)
#' @param bundle_id Optional bundle id (default generated)
#' @param bundle_name Optional display name
#' @param overwrite If TRUE, overwrite existing bundle directory
#' @param export_assays Optional character vector of assays to export as matrices (NULL => all assays)
#' @param matrix_slot Slot to export from assays (default "counts")
#' @param matrix_specs Optional explicit list of specs (overrides export_assays/matrix_slot/feature_type_map)
#' @param feature_type_map Optional named vector/list mapping assay -> feature_type ("gene"/"peak"/"feature")
#' @param write_spaces If TRUE, export Seurat reductions into spaces tables
#' @param write_matrices If TRUE, export assay matrices via BPCells
#' @export
publish_app_bundle <- function(
    seurat,
    out_dir = NULL,
    dataset_col = NULL,
    bundle_id = NULL,
    bundle_name = NULL,
    overwrite = NULL,
    export_assays = NULL,
    matrix_slot = NULL,
    matrix_specs = NULL,
    feature_type_map = NULL,
    write_spaces = TRUE,
    write_matrices = TRUE
) {
  stopifnot(inherits(seurat, "Seurat"))

  # ---- Resolve defaults (args > options > auto) ----
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  bundle_id <- wb_resolve(bundle_id, "scworkbench.bundle_id", paste0("scworkbench_", stamp))
  bundle_name <- wb_resolve(bundle_name, "scworkbench.bundle_name", bundle_id)

  overwrite <- wb_resolve(overwrite, "scworkbench.overwrite", FALSE)
  matrix_slot <- wb_resolve(matrix_slot, "scworkbench.matrix_slot", "counts")
  export_assays <- wb_resolve(export_assays, "scworkbench.export_assays", NULL)
  if (is.null(export_assays)) {
    export_assays <- wb_default_export_assays(seurat)
  }

  # feature_type_map: allow options too
  if (is.null(feature_type_map)) feature_type_map <- getOption("scworkbench.feature_type_map", NULL)

  # out_dir: if user passes a full bundle dir, use it;
  # else build under base dir (option scworkbench.out_dir or ./scworkbench_bundles)
  if (is.null(out_dir)) {
    base_out <- getOption("scworkbench.out_dir", Sys.getenv("SCWORKBENCH_OUT_DIR", unset = ""))
    if (!nzchar(base_out)) base_out <- file.path(getwd(), "scworkbench_bundles")
    out_dir <- file.path(base_out, bundle_id)
  }

  # dataset_col auto: prefer provided/option; else "orig.ident" if present; else fallback
  if (is.null(dataset_col)) dataset_col <- getOption("scworkbench.dataset_col", NULL)
  if (is.null(dataset_col)) dataset_col <- if ("orig.ident" %in% colnames(seurat@meta.data)) "orig.ident" else NULL

  # ---- Prepare directories ----
  if (dir.exists(out_dir)) {
    if (!isTRUE(overwrite)) stop("out_dir exists: ", out_dir, " (set overwrite=TRUE to replace)")
    unlink(out_dir, recursive = TRUE, force = TRUE)
  }
  dir.create(file.path(out_dir, "db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "mat"), showWarnings = FALSE)

  # ---- IDs ----
  cell_id <- colnames(seurat)
  meta <- seurat@meta.data

  if (!is.null(dataset_col) && dataset_col %in% colnames(meta)) {
    dataset_id <- as.character(meta[[dataset_col]])
    dataset_id_source <- paste0("meta.data.", dataset_col)
  } else {
    dataset_id <- rep("dataset_1", length(cell_id))
    dataset_id_source <- "fallback: dataset_1"
  }

  # ---- open sqlite ----
  db_path <- file.path(out_dir, "db", "app.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "PRAGMA synchronous=NORMAL;")
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")

  # ---- schema ----
  DBI::dbExecute(con, "
    CREATE TABLE datasets (
      dataset_id TEXT PRIMARY KEY,
      n_cells INTEGER
    );
  ")
  DBI::dbExecute(con, "
  CREATE TABLE cells (
    cell_id TEXT PRIMARY KEY,
    dataset_id TEXT,
    cell_set TEXT NOT NULL DEFAULT 'core'
    -- metadata columns added below
  );
")

  DBI::dbExecute(con, "
    CREATE TABLE spaces (
      space_id TEXT PRIMARY KEY,
      source TEXT,
      dims INTEGER,
      storage TEXT,
      description TEXT
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE space_coords (
      space_id TEXT,
      cell_id TEXT,
      dim INTEGER,
      value REAL,
      PRIMARY KEY (space_id, cell_id, dim)
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE space_2d (
      space_id TEXT,
      cell_id TEXT,
      x REAL,
      y REAL,
      PRIMARY KEY (space_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX idx_space_2d_space ON space_2d(space_id);")
  DBI::dbExecute(con, "CREATE INDEX idx_space_2d_cell  ON space_2d(cell_id);")

  # Generic features + matrices registries
  DBI::dbExecute(con, "
    CREATE TABLE features (
      assay TEXT,
      feature_id TEXT,
      feature_type TEXT,
      chr TEXT,
      start INTEGER,
      end INTEGER,
      PRIMARY KEY (assay, feature_id)
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE matrices (
      matrix_id    TEXT PRIMARY KEY,
      assay        TEXT,
      layer        TEXT,
      feature_type TEXT,
      n_features   INTEGER,
      n_cells      INTEGER,
      storage      TEXT,
      path         TEXT,
      description  TEXT
    );
  ")
  DBI::dbExecute(con, "
CREATE TABLE matrix_cells (
  matrix_id TEXT,
  cell_id   TEXT,
  PRIMARY KEY (matrix_id, cell_id)
);
  ")


  # ---- write datasets ----
  ds_tab <- as.data.frame(table(dataset_id), stringsAsFactors = FALSE)
  colnames(ds_tab) <- c("dataset_id", "n_cells")
  ds_tab$n_cells <- as.integer(ds_tab$n_cells)
  DBI::dbWriteTable(con, "datasets", ds_tab, append = TRUE)

  # ---- write cells + metadata ----
  cells_df <- data.frame(
    cell_id   = cell_id,
    dataset_id = dataset_id,
    cell_set  = "core",
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
  meta2$cell_id <- NULL
  cells_df <- cbind(cells_df, meta2)

  for (nm in setdiff(colnames(cells_df), c("cell_id", "dataset_id", "cell_set"))) {
    col_type <- if (is.numeric(cells_df[[nm]])) "REAL" else "TEXT"
    if (is.integer(cells_df[[nm]])) col_type <- "INTEGER"
    DBI::dbExecute(con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
  }
  DBI::dbWriteTable(con, "cells", cells_df, append = TRUE)
  DBI::dbExecute(con, "CREATE INDEX idx_cells_dataset ON cells(dataset_id);")
  DBI::dbExecute(con, "CREATE INDEX idx_cells_cell_set ON cells(cell_set);")
  DBI::dbExecute(con, "CREATE INDEX idx_matrix_cells_cell   ON matrix_cells(cell_id);")
  DBI::dbExecute(con, "CREATE INDEX idx_matrix_cells_matrix ON matrix_cells(matrix_id);")

  # ---- spaces: reductions ----
  if (isTRUE(write_spaces)) {
    reductions <- names(seurat@reductions)

    write_space_long <- function(space_id, emb) {
      dims <- ncol(emb)
      chunk <- 20000
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
          dims = 2,
          storage = "wide:space_2d",
          description = r,
          stringsAsFactors = FALSE
        ), append = TRUE)
        write_space_2d(r, emb, cell_id)
      } else {
        DBI::dbWriteTable(con, "spaces", data.frame(
          space_id = r,
          source = "Seurat reduction",
          dims = dims,
          storage = "long:space_coords",
          description = r,
          stringsAsFactors = FALSE
        ), append = TRUE)
        write_space_long(r, emb)
      }
    }

    DBI::dbExecute(con, "CREATE INDEX idx_space_coords_space ON space_coords(space_id);")
    DBI::dbExecute(con, "CREATE INDEX idx_space_coords_cell ON space_coords(cell_id);")
  }

  # ---- matrices: generic specs + BPCells ----
  resolved_matrix_specs <- matrix_specs
  if (is.null(resolved_matrix_specs)) {
    resolved_matrix_specs <- wb_default_matrix_specs(
      seurat = seurat,
      slot = matrix_slot,
      export_assays = export_assays,
      feature_type_map = feature_type_map
    )
  }

  if (isTRUE(write_matrices)) {
    if (length(resolved_matrix_specs) == 0) {
      warning("No matrix_specs resolved; skipping matrix export.")
    } else {
      wb_register_features_for_specs(con, seurat, resolved_matrix_specs)

      for (spec in resolved_matrix_specs) {
        wb_write_and_register_matrix_from_spec(
          con = con,
          seurat = seurat,
          out_dir = out_dir,
          spec = spec,
          cell_ids = cell_id
        )
      }
    }
  } else {
    # Still register features if specs exist (useful contract even without matrices)
    if (length(resolved_matrix_specs) > 0) {
      wb_register_features_for_specs(con, seurat, resolved_matrix_specs)
    }
  }

  # ---- manifest ----
  mat_tbl <- try(DBI::dbReadTable(con, "matrices"), silent = TRUE)
  if (inherits(mat_tbl, "try-error")) mat_tbl <- data.frame()

  feats_tbl <- try(DBI::dbReadTable(con, "features"), silent = TRUE)
  if (inherits(feats_tbl, "try-error")) feats_tbl <- data.frame()

  manifest <- list(
    scworkbench_manifest_version = "1.1.0",
    bundle_id = bundle_id,
    bundle_name = bundle_name,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    counts = list(
      n_cells = length(cell_id),
      n_datasets = length(unique(dataset_id)),
      n_spaces = if (isTRUE(write_spaces)) nrow(DBI::dbReadTable(con, "spaces")) else 0,
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
      feature_id_source = "rownames(seurat@assays[[assay]]) per exported assay",
      matrix_specs = resolved_matrix_specs
    ),
    spaces = if (isTRUE(write_spaces)) as.list(DBI::dbReadTable(con, "spaces")) else list()
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
