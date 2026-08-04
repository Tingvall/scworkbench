# Matrix transform ops.

.wb_matrix_id_path_safe <- function(x) {
  x <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(x %||% "")[1])
  if (!nzchar(x)) x <- "matrix"
  x
}

# BPCells packed compression is intended for integer-like count matrices. A
# normalized matrix is continuous, so persist it as an explicit uncompressed
# double matrix rather than relying on packed floating-point conversion.
.wb_matrix_write_continuous <- function(mat, out_dir) {
  .wb_require_pkg("BPCells", "continuous matrix transform write")
  typed <- BPCells::convert_matrix_type(mat, "double")
  BPCells::write_matrix_dir(typed, out_dir, compress = FALSE)
  .wb_bp_open_matrix_dir(out_dir)
}

.wb_matrix_assert_transform_signal <- function(persisted, source_library_size, context) {
  source_library_size <- as.numeric(source_library_size)
  source_nonzero <- is.finite(source_library_size) & source_library_size > 0
  if (!any(source_nonzero)) return(invisible(TRUE))

  output_signal <- as.numeric(Matrix::colSums(persisted))
  .wb_assert(length(output_signal) == length(source_library_size),
             paste0(context, ": persisted output cell count does not match source library sizes."))
  .wb_assert(any(is.finite(output_signal) & output_signal > 0),
             paste0(context, ": source matrix contains nonzero signal but persisted normalized output is all zero; output was not registered."))
  .wb_assert(all(is.finite(output_signal[source_nonzero]) & output_signal[source_nonzero] > 0),
             paste0(context, ": one or more nonzero source cells lost all signal during normalized matrix write; output was not registered."))
  invisible(TRUE)
}

.wb_matrix_single_fragment_cell_ids <- function(bundle, matrix_id, mat, bundle_cell_ids) {
  fragments <- wb_matrix_fragments(bundle, matrix_id)
  .wb_assert(
    nrow(fragments) == 1L,
    paste0("matrix_log_normalize: single-fragment matrix '", matrix_id,
           "' requires exactly one registered matrix fragment to resolve cell order.")
  )
  fragment_cell_ids <- as.character(jsonlite::fromJSON(fragments$cell_ids_json[1]))
  .wb_assert(
    length(fragment_cell_ids) == ncol(mat),
    paste0("matrix_log_normalize: fragment cell count does not match matrix columns for '", matrix_id, "'.")
  )
  .wb_assert(
    identical(fragment_cell_ids, as.character(bundle_cell_ids)),
    paste0("matrix_log_normalize: registered fragment cell order does not match the logical bundle cell universe for '", matrix_id, "'.")
  )

  # Payload dimnames are optional convenience metadata. For example, a 10x
  # payload may retain raw barcodes while the bundle uses sample-prefixed
  # canonical IDs. Never use payload dimnames to resolve cell identity here.
  fragment_cell_ids
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
    checked <- .wb_path_status(bundle$dir, p, must_exist=FALSE, purpose="matrix removal")
    if (isTRUE(checked$ok) && (dir.exists(checked$absolute) || file.exists(checked$absolute))) unlink(checked$absolute, recursive = TRUE, force = TRUE)
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
                                            source_library_size,
                                            source = "matrix_log_normalize") {
  con <- bundle$con
  safe_id <- .wb_matrix_id_path_safe(matrix_id)
  rel_path <- file.path("mat", paste0("mat_frag_", safe_id, "_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  abs_path <- .wb_bundle_path_require(bundle, rel_path, expected_type="directory", must_exist=FALSE,
                                      purpose="transformed matrix output")
  if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)

  .wb_require_pkg("BPCells", "matrix transform write")
  persisted <- tryCatch({
    .wb_matrix_write_continuous(mat, abs_path)
  }, error = function(e) {
    if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
    stop(e)
  })
  tryCatch(
    .wb_matrix_assert_transform_signal(persisted, source_library_size, "matrix_log_normalize"),
    error = function(e) {
      if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
      stop(e)
    }
  )

  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  tryCatch(DBI::dbWithTransaction(con, {
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
  }), error = function(e) {
    if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
    stop(e)
  })

  rel_path
}

.wb_matrix_register_transformed_fragments <- function(bundle,
                                                      matrix_id,
                                                      source_matrix_id,
                                                      fragments,
                                                      feature_ids,
                                                      layer,
                                                      feature_type,
                                                      description,
                                                      scale_factor) {
  con <- bundle$con
  .wb_require_pkg("BPCells", "matrix transform write")
  .wb_assert(is.data.frame(fragments) && nrow(fragments) > 0L, "fragments must be non-empty")
  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  safe_id <- .wb_matrix_id_path_safe(matrix_id)
  first_rel_path <- NA_character_
  all_cell_ids <- character(0)
  lib_sizes <- numeric(0)
  created_paths <- character(0)

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
  fragment_rows <- vector("list", nrow(fragments))

  tryCatch({
    for (i in seq_len(nrow(fragments))) {
      frow <- fragments[i, , drop = FALSE]
      frag_features <- as.character(jsonlite::fromJSON(frow$feature_ids_json[1]))
      frag_cells <- as.character(jsonlite::fromJSON(frow$cell_ids_json[1]))
      .wb_assert(identical(frag_features, as.character(feature_ids)),
                 paste0("matrix_log_normalize: fragment feature order differs for fragment ", frow$fragment_id[1], "."))
      .wb_assert(length(frag_cells) == as.integer(frow$n_cells[1]),
                 paste0("matrix_log_normalize: fragment cell metadata mismatch for fragment ", frow$fragment_id[1], "."))

      src_path <- .wb_bundle_path_require(bundle, frow$path[1], expected_type = "directory",
                                          purpose = paste0("matrix fragment ", frow$fragment_id[1]))
      src_mat <- .wb_bp_open_matrix_dir(src_path)
      .wb_assert(identical(as.integer(dim(src_mat)), as.integer(c(length(feature_ids), length(frag_cells)))),
                 paste0("matrix_log_normalize: source fragment dimensions mismatch for fragment ", frow$fragment_id[1], "."))

      lib_size <- as.numeric(Matrix::colSums(src_mat))
      names(lib_size) <- frag_cells
      denom <- lib_size
      denom[!is.finite(denom) | denom <= 0] <- Inf
      norm <- log1p(BPCells::multiply_cols(src_mat, scale_factor / denom))
      rownames(norm) <- feature_ids
      colnames(norm) <- frag_cells

      rel_path <- file.path(
        "mat",
        paste0(
          "mat_frag_", safe_id, "_",
          sprintf("%03d", i), "_",
          format(Sys.time(), "%Y%m%d_%H%M%S")
        )
      )
      abs_path <- .wb_bundle_path_require(bundle, rel_path, expected_type = "directory",
                                          must_exist = FALSE, purpose = "normalized matrix output")
      if (dir.exists(abs_path) || file.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
      created_paths <- c(created_paths, abs_path)
      persisted <- .wb_matrix_write_continuous(norm, abs_path)
      .wb_matrix_assert_transform_signal(
        persisted,
        lib_size,
        paste0("matrix_log_normalize fragment ", frow$fragment_id[1])
      )
      fragment_rows[[i]] <- list(
        path = rel_path,
        cell_ids = frag_cells,
        description = paste0("Log-normalized fragment from ", frow$fragment_id[1])
      )
      if (is.na(first_rel_path)) first_rel_path <- rel_path
      all_cell_ids <- c(all_cell_ids, frag_cells)
      lib_sizes <- c(lib_sizes, lib_size)
    }

    DBI::dbWithTransaction(con, {
      DBI::dbWriteTable(
        con,
        "matrices",
        data.frame(
          matrix_id = as.character(matrix_id),
          layer = as.character(layer),
          feature_type = as.character(feature_type),
          n_features = as.integer(length(feature_ids)),
          n_cells = as.integer(length(all_cell_ids)),
          storage = "bpcells",
          path = first_rel_path,
          description = as.character(description %||% paste0("Derived from ", source_matrix_id)),
          stringsAsFactors = FALSE
        ),
        append = TRUE
      )
      DBI::dbWriteTable(con, "features", feats_df, append = TRUE)
      for (fragment_row in fragment_rows) {
        wb_register_matrix_fragment(
          con = con,
          matrix_id = as.character(matrix_id),
          path_rel = fragment_row$path,
          feature_ids = as.character(feature_ids),
          cell_ids = fragment_row$cell_ids,
          source = "matrix_log_normalize",
          created_at = now,
          description = fragment_row$description
        )
      }
    })
  }, error = function(e) {
    try(.wb_matrix_remove_existing(bundle, matrix_id), silent = TRUE)
    for (path in created_paths) {
      if (dir.exists(path) || file.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
    }
    stop(e)
  })

  list(
    path = first_rel_path,
    cell_ids = all_cell_ids,
    lib_size = lib_sizes,
    n_fragments = as.integer(nrow(fragments))
  )
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
  .wb_assert_operation_execution(bundle, "matrix_log_normalize")
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
    .wb_entity_assert_replaceable(bundle, "matrix", output_matrix_id, action = "overwrite")
    .wb_matrix_remove_existing(bundle, output_matrix_id)
  }

  feature_ids <- wb_feature_ids(bundle, matrix_id = matrix_id)
  cell_ids <- wb_cells(bundle, cell_set = "all")
  .wb_assert(length(feature_ids) > 0L, "source matrix has no features")
  .wb_assert(length(cell_ids) > 0L, "bundle has no cells")

  layer <- paste0("log1p_cp", format(scale_factor, scientific = FALSE, trim = TRUE))
  feature_type <- as.character(source_row$feature_type[1] %||% "feature")
  description <- paste0(
    "Log-normalized matrix: log1p(", matrix_id,
    " / per-cell library size * ", format(scale_factor, scientific = FALSE, trim = TRUE),
    "). Source matrix: ", matrix_id, "."
  )

  frags <- tryCatch(wb_matrix_fragments(bundle, matrix_id), error = function(e) data.frame())
  if (nrow(frags) > 1L) {
    reg <- .wb_matrix_register_transformed_fragments(
      bundle = bundle,
      matrix_id = output_matrix_id,
      source_matrix_id = matrix_id,
      fragments = frags,
      feature_ids = feature_ids,
      layer = layer,
      feature_type = feature_type,
      description = description,
      scale_factor = scale_factor
    )
    rel_path <- reg$path
    lib_size <- reg$lib_size
    cell_ids <- reg$cell_ids
    n_fragments <- reg$n_fragments
  } else {
    m <- wb_matrix(bundle, matrix_id)
    cell_ids <- .wb_matrix_single_fragment_cell_ids(
      bundle = bundle,
      matrix_id = matrix_id,
      mat = m,
      bundle_cell_ids = cell_ids
    )
    lib_size <- as.numeric(Matrix::colSums(m))
    names(lib_size) <- cell_ids
    .wb_assert(length(lib_size) == length(cell_ids), "library size/cell alignment failed")
    denom <- lib_size
    denom[!is.finite(denom) | denom <= 0] <- Inf

    # BPCells keeps these operations lazy and streams them during write_matrix_dir.
    norm <- log1p(BPCells::multiply_cols(m, scale_factor / denom))
    rownames(norm) <- feature_ids
    colnames(norm) <- cell_ids

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
      source_library_size = lib_size,
      source = "matrix_log_normalize"
    )
    n_fragments <- as.integer(max(nrow(frags), 1L))
  }
  .wb_assert(setequal(as.character(cell_ids), as.character(wb_cells(bundle, cell_set = "all"))),
             "matrix_log_normalize: transformed matrix cells do not match bundle cell universe.")
  zero_library_cells <- cell_ids[!is.finite(lib_size) | lib_size <= 0]

  summary <- data.frame(
    output_matrix_id = output_matrix_id,
    source_matrix_id = matrix_id,
    transform = "log1p_cp",
    formula = paste0("log1p(counts / library_size * ", format(scale_factor, scientific = FALSE, trim = TRUE), ")"),
    scale_factor = as.numeric(scale_factor),
    n_features = as.integer(length(feature_ids)),
    n_cells = as.integer(length(cell_ids)),
    n_fragments = as.integer(n_fragments),
    n_zero_library_cells = as.integer(length(zero_library_cells)),
    min_library_size = suppressWarnings(min(lib_size, na.rm = TRUE)),
    median_library_size = suppressWarnings(stats::median(lib_size, na.rm = TRUE)),
    max_library_size = suppressWarnings(max(lib_size, na.rm = TRUE)),
    path = rel_path,
    storage_representation = "bpcells_uncompressed_double",
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
