# Matrix transform ops.

.wb_matrix_id_path_safe <- function(x) {
  x <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(x %||% "")[1])
  if (!nzchar(x)) x <- "matrix"
  x
}

.wb_matrix_remove_existing <- function(bundle, matrix_id) {
  con <- bundle$con
  rows <- DBI::dbGetQuery(
    con,
    "SELECT matrix_id, path FROM matrices WHERE matrix_id = ?;",
    params = list(as.character(matrix_id))
  )
  frags <- tryCatch(wb_matrix_fragments(bundle, matrix_id), error = function(e) data.frame())
  paths <- unique(c(as.character(rows$path %||% character(0)), as.character(frags$path %||% character(0))))
  paths <- paths[!is.na(paths) & nzchar(paths)]

  DBI::dbWithTransaction(con, {
    if (.wb_table_exists(con, "matrix_fragments")) {
      DBI::dbExecute(con, "DELETE FROM matrix_fragments WHERE matrix_id = ?;", params = list(as.character(matrix_id)))
    }
    if (.wb_table_exists(con, "matrix_fragment_cells")) {
      fids <- as.character(frags$fragment_id %||% character(0))
      fids <- fids[!is.na(fids) & nzchar(fids)]
      if (length(fids)) {
        q <- paste(rep("?", length(fids)), collapse = ",")
        DBI::dbExecute(con, paste0("DELETE FROM matrix_fragment_cells WHERE fragment_id IN (", q, ");"), params = as.list(fids))
      }
    }
    if (.wb_table_exists(con, "matrix_fragment_features")) {
      fids <- as.character(frags$fragment_id %||% character(0))
      fids <- fids[!is.na(fids) & nzchar(fids)]
      if (length(fids)) {
        q <- paste(rep("?", length(fids)), collapse = ",")
        DBI::dbExecute(con, paste0("DELETE FROM matrix_fragment_features WHERE fragment_id IN (", q, ");"), params = as.list(fids))
      }
    }
    if (.wb_table_exists(con, "features")) {
      DBI::dbExecute(con, "DELETE FROM features WHERE matrix_id = ?;", params = list(as.character(matrix_id)))
    }
    DBI::dbExecute(con, "DELETE FROM matrices WHERE matrix_id = ?;", params = list(as.character(matrix_id)))
  })

  for (p in paths) {
    abs <- file.path(bundle$dir, p)
    if (dir.exists(abs) || file.exists(abs)) unlink(abs, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

.wb_matrix_register_transformed <- function(bundle,
                                            matrix_id,
                                            source_matrix_id,
                                            mat,
                                            feature_ids,
                                            cell_ids,
                                            layer,
                                            feature_type,
                                            description,
                                            source = "matrix_log_normalize") {
  con <- bundle$con
  safe_id <- .wb_matrix_id_path_safe(matrix_id)
  rel_path <- file.path("mat", paste0("mat_frag_", safe_id, "_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  abs_path <- file.path(bundle$dir, rel_path)
  if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)

  .wb_require_pkg("BPCells", "matrix transform write")
  BPCells::write_matrix_dir(mat, abs_path)

  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  DBI::dbWithTransaction(con, {
    DBI::dbWriteTable(
      con,
      "matrices",
      data.frame(
        matrix_id = as.character(matrix_id),
        layer = as.character(layer),
        feature_type = as.character(feature_type),
        n_features = as.integer(length(feature_ids)),
        n_cells = as.integer(length(cell_ids)),
        storage = "bpcells",
        path = rel_path,
        description = as.character(description %||% paste0("Derived from ", source_matrix_id)),
        stringsAsFactors = FALSE
      ),
      append = TRUE
    )

    wb_register_matrix_fragment(
      con = con,
      matrix_id = as.character(matrix_id),
      path_rel = rel_path,
      feature_ids = as.character(feature_ids),
      cell_ids = as.character(cell_ids),
      source = source,
      created_at = now,
      description = as.character(description %||% paste0("Derived from ", source_matrix_id))
    )

    src_feats <- DBI::dbGetQuery(
      con,
      "SELECT feature_id, feature_type, chr, start, end
       FROM features
       WHERE matrix_id = ?
       ORDER BY rowid;",
      params = list(as.character(source_matrix_id))
    )
    if (nrow(src_feats)) {
      src_feats <- src_feats[match(as.character(feature_ids), as.character(src_feats$feature_id)), , drop = FALSE]
      feats_df <- data.frame(
        matrix_id = as.character(matrix_id),
        feature_id = as.character(feature_ids),
        feature_type = as.character(src_feats$feature_type %||% feature_type),
        chr = as.character(src_feats$chr %||% NA_character_),
        start = suppressWarnings(as.integer(src_feats$start %||% NA_integer_)),
        end = suppressWarnings(as.integer(src_feats$end %||% NA_integer_)),
        stringsAsFactors = FALSE
      )
    } else {
      feats_df <- data.frame(
        matrix_id = as.character(matrix_id),
        feature_id = as.character(feature_ids),
        feature_type = as.character(feature_type),
        chr = NA_character_,
        start = NA_integer_,
        end = NA_integer_,
        stringsAsFactors = FALSE
      )
    }
    DBI::dbWriteTable(con, "features", feats_df, append = TRUE)
  })

  rel_path
}

#' Log-Normalize A Count Matrix
#'
#' Creates a reusable `log1p(counts / library_size * scale_factor)` matrix in
#' the bundle. Version 1 writes a full feature-by-cell BPCells matrix and
#' registers it under `output_matrix_id`.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Source count matrix id.
#' @param output_matrix_id New matrix id. Defaults to
#'   `paste0(matrix_id, "_log1p_cp", scale_factor)`.
#' @param scale_factor Per-cell target count scale, conventionally `10000`.
#' @param overwrite Replace an existing output matrix if present.
#'
#' @return Standard op result with `outputs$matrix` and `outputs$summary`.
#' @export
wb_op_matrix_log_normalize <- function(bundle,
                                       matrix_id,
                                       output_matrix_id = NULL,
                                       scale_factor = 10000,
                                       overwrite = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id invalid")
  scale_factor <- suppressWarnings(as.numeric(scale_factor)[1])
  .wb_assert(is.finite(scale_factor) && scale_factor > 0, "scale_factor must be positive")
  if (is.null(output_matrix_id) || !nzchar(as.character(output_matrix_id)[1])) {
    output_matrix_id <- paste0(matrix_id, "_log1p_cp", format(scale_factor, scientific = FALSE, trim = TRUE))
  }
  output_matrix_id <- as.character(output_matrix_id)[1]
  .wb_assert(nzchar(output_matrix_id), "output_matrix_id invalid")
  .wb_assert(!identical(output_matrix_id, matrix_id), "output_matrix_id must differ from source matrix_id")

  con <- bundle$con
  source_row <- wb_matrix_info(bundle, matrix_id = matrix_id)
  .wb_assert(nrow(source_row) == 1L, paste0("Source matrix not found: ", matrix_id))

  existing <- wb_matrix_info(bundle, matrix_id = output_matrix_id)
  if (nrow(existing) > 0L) {
    .wb_assert(isTRUE(overwrite), paste0("Output matrix exists: ", output_matrix_id, " (set overwrite=TRUE)"))
    .wb_matrix_remove_existing(bundle, output_matrix_id)
  }

  m <- wb_matrix(bundle, matrix_id)
  feature_ids <- wb_feature_ids(bundle, matrix_id = matrix_id)
  cell_ids <- wb_cells(bundle, cell_set = "all")
  .wb_assert(length(feature_ids) > 0L, "source matrix has no features")
  .wb_assert(length(cell_ids) > 0L, "bundle has no cells")

  lib_size <- as.numeric(Matrix::colSums(m))
  names(lib_size) <- colnames(m)
  lib_size <- lib_size[match(cell_ids, names(lib_size))]
  .wb_assert(length(lib_size) == length(cell_ids), "library size/cell alignment failed")
  zero_library_cells <- cell_ids[!is.finite(lib_size) | lib_size <= 0]
  denom <- lib_size
  denom[!is.finite(denom) | denom <= 0] <- Inf

  # BPCells keeps these operations lazy and streams them during write_matrix_dir.
  scale_by_cell <- scale_factor / denom
  norm <- log1p(BPCells::multiply_cols(m, scale_by_cell))
  rownames(norm) <- feature_ids
  colnames(norm) <- cell_ids

  layer <- paste0("log1p_cp", format(scale_factor, scientific = FALSE, trim = TRUE))
  feature_type <- as.character(source_row$feature_type[1] %||% "feature")
  description <- paste0(
    "Log-normalized matrix: log1p(", matrix_id,
    " / per-cell library size * ", format(scale_factor, scientific = FALSE, trim = TRUE),
    "). Source matrix: ", matrix_id, "."
  )
  rel_path <- .wb_matrix_register_transformed(
    bundle = bundle,
    matrix_id = output_matrix_id,
    source_matrix_id = matrix_id,
    mat = norm,
    feature_ids = feature_ids,
    cell_ids = cell_ids,
    layer = layer,
    feature_type = feature_type,
    description = description,
    source = "matrix_log_normalize"
  )

  summary <- data.frame(
    output_matrix_id = output_matrix_id,
    source_matrix_id = matrix_id,
    transform = "log1p_cp",
    formula = paste0("log1p(counts / library_size * ", format(scale_factor, scientific = FALSE, trim = TRUE), ")"),
    scale_factor = as.numeric(scale_factor),
    n_features = as.integer(length(feature_ids)),
    n_cells = as.integer(length(cell_ids)),
    n_zero_library_cells = as.integer(length(zero_library_cells)),
    min_library_size = suppressWarnings(min(lib_size, na.rm = TRUE)),
    median_library_size = suppressWarnings(stats::median(lib_size, na.rm = TRUE)),
    max_library_size = suppressWarnings(max(lib_size, na.rm = TRUE)),
    path = rel_path,
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      matrix = wb_prim_matrix(output_matrix_id),
      summary = wb_prim_obs_table(
        summary,
        table_type = "matrix_log_normalize_summary",
        entity_kind = "matrix",
        meta = list(
          source_matrix_id = matrix_id,
          output_matrix_id = output_matrix_id,
          transform = "log1p_cp",
          scale_factor = scale_factor
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      output_matrix_id = output_matrix_id,
      transform = "log1p_cp",
      scale_factor = as.numeric(scale_factor),
      overwrite = isTRUE(overwrite),
      n_features = as.integer(length(feature_ids)),
      n_cells = as.integer(length(cell_ids)),
      n_zero_library_cells = as.integer(length(zero_library_cells))
    )
  )
}
