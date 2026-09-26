#' (Advanced) Attach primitives to existing cells (matrices/spaces/metadata)
#'
#' Canonical rule: FIRST COLUMN = cell_id, regardless of name.
#' No "cell_id" column semantics anywhere.
#'
#' Prefer supported `wb_bundle_from_*()` constructors for ordinary ingestion.
#' This writer is for controlled staged bundle assembly.
#'
#' @param bundle scworkbench_bundle
#' @param matrices Named list. Each entry name is the `matrix_id`. Each entry can be:
#'   - a Matrix-like object (sparse ok) with colnames=cell_id and rownames=feature_id
#'   - OR a list(mat=..., layer=..., feature_type=..., description=...)
#' @param spaces Named list (space_id -> data.frame). Each object must be a data.frame:
#'   - 2D: first col=cell_id, plus x,y
#'   - long: first col=cell_id, plus dim,value
#' @param metadata Optional data.frame: first col=cell_id, rest are metadata cols
#' @param metadata_field_refs Optional position-aligned list of
#'   [wb_ref_metadata_field()] references. Non-NULL entries explicitly update
#'   existing fields; NULL entries treat payload column names as source names.
#' @param cell_ids Optional character vector: restrict attach to these cells (must exist in bundle)
#' @param source Stored in registries
#' @param created_by Optional (currently unused here; kept for forward compatibility)
#' @return report list
#' @export
wb_attach_to_cells <- function(
    bundle,
    matrices = NULL,
    spaces = NULL,
    metadata = NULL,
    cell_ids = NULL,
    source = "attach",
    created_by = NULL,
    metadata_field_refs = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  .wb_assert_mutation_context(
    bundle = bundle, action = "Low-level attachment writer wb_attach_to_cells()",
    allowed = c("assembly", "ingestion"),
    replacement = "wb_attach_apply() as a declared provenance-producing ingestion transaction"
  )
  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")

  # Ensure required tables exist
  #.wb_ensure_matrix_fragments_table(con)

  as_chr <- function(x) as.character(x)

  # FIRST COLUMN ONLY = cell_id (name irrelevant)
  .take_first_col_as_cell_id <- function(df, what = "attachment") {
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
    .wb_assert(ncol(df) >= 1, paste0(what, " must have at least 1 column (first col = cell_id)."))

    ids <- as_chr(df[[1]])
    .wb_assert(length(ids) == nrow(df), paste0(what, ": first column length mismatch."))
    .wb_assert(!anyNA(ids), paste0(what, ": first column contains NA cell ids."))

    ids <- ids[nzchar(ids)]
    .wb_assert(length(ids) == nrow(df), paste0(what, ": first column contains empty cell ids."))

    payload <- df[, -1, drop = FALSE]
    list(cell_ids = ids, data = payload)
  }

  # ---- infer target cell_ids if NULL ----
  if (is.null(cell_ids)) {
    cands <- character(0)

    # matrices: from colnames
    if (!is.null(matrices) && length(matrices)) {
      for (nm in names(matrices)) {
        x <- matrices[[nm]]
        mat <- if (is.list(x) && !is.null(x$mat)) x$mat else x
        if (!is.null(colnames(mat))) cands <- c(cands, as_chr(colnames(mat)))
      }
    }

    # spaces + metadata: from first column
    if (!is.null(spaces) && length(spaces)) {
      for (sid in names(spaces)) {
        obj <- spaces[[sid]]
        .wb_assert(is.data.frame(obj), paste0("Space '", sid, "' must be a data.frame (first col = cell_id)."))
        cands <- c(cands, as_chr(obj[[1]]))
      }
    }

    if (!is.null(metadata)) {
      .wb_assert(is.data.frame(metadata), "metadata must be a data.frame (first col = cell_id).")
      cands <- c(cands, as_chr(metadata[[1]]))
    }

    cell_ids <- unique(cands[nzchar(cands)])
    .wb_assert(length(cell_ids) > 0, "Could not infer cell_ids from attachments.")
  } else {
    cell_ids <- unique(as_chr(cell_ids))
    cell_ids <- cell_ids[nzchar(cell_ids)]
    .wb_assert(length(cell_ids) > 0, "cell_ids provided but empty after cleaning")
  }

  # ---- restrict to cells that actually exist in bundle ----
  existing <- as_chr(DBI::dbGetQuery(con,
    "SELECT cell_id FROM cells ORDER BY rowid;")$cell_id)
  keep <- intersect(cell_ids, existing)
  .wb_assert(length(keep) > 0, "None of the provided/inferred cell_ids exist in this bundle.")
  missing <- setdiff(cell_ids, existing)

  report <- list(
    n_target_cells = length(cell_ids),
    n_existing_cells = length(keep),
    n_missing_cells = length(missing),
    missing_cells_head = head(missing, 20),
    matrices = list(),
    spaces = list(),
    metadata = NULL
  )

  # ============================================================
  # 1) METADATA ATTACH (SQLite cells table)
  # ============================================================
  if (!is.null(metadata)) {
    metadata_report <- .wb_write_cell_metadata(
      con, metadata, target_cell_ids = keep, source = source, created_by = created_by,
      field_refs = metadata_field_refs
    )
    report$metadata <- metadata_report
  }

  # ============================================================
  # 2) SPACES ATTACH (canonical file-backed payloads)
  # ============================================================
  if (!is.null(spaces) && length(spaces)) {
    for (space_id in names(spaces)) {
      obj <- spaces[[space_id]]
      .wb_assert(is.data.frame(obj), paste0("Space '", space_id, "' must be a data.frame (first col = cell_id)."))

      sp_res <- .take_first_col_as_cell_id(obj, what = paste0("space '", space_id, "'"))
      df <- sp_res$data
      df$cell_id <- sp_res$cell_ids

      df$cell_id <- as_chr(df$cell_id)
      df <- df[df$cell_id %in% keep, , drop = FALSE]

      if (nrow(df) == 0) {
        report$spaces[[space_id]] <- list(type = "empty", n = 0)
        next
      }

      if (all(c("x", "y") %in% colnames(df))) {
        mat <- cbind(x = as.numeric(df$x), y = as.numeric(df$y))
        rownames(mat) <- df$cell_id
        report$spaces[[space_id]] <- list(type = "2d", n = nrow(df))
      } else if (all(c("dim", "value") %in% colnames(df))) {
        dims_n <- suppressWarnings(as.integer(max(df$dim, na.rm = TRUE)))
        cells_u <- unique(df$cell_id)
        mat <- matrix(NA_real_, nrow = length(cells_u), ncol = dims_n,
                      dimnames = list(cells_u, paste0("dim", seq_len(dims_n))))
        mat[cbind(match(df$cell_id, cells_u), as.integer(df$dim))] <- as.numeric(df$value)
        .wb_assert(!anyNA(mat), paste0("Space '", space_id, "' long payload is incomplete."))
        report$spaces[[space_id]] <- list(type = "long", n = nrow(df))
      } else {
        stop(
          "Space '", space_id, "' must have either columns (x,y) for 2D, or (dim,value) for long. ",
          "Reminder: first column is cell_id and is not part of the payload columns.",
          call. = FALSE
        )
      }
      .wb_space_payload_merge_write(bundle, space_id, mat, source = source,
                                    description = space_id, overwrite_cells = TRUE)
    }
  }

  # ============================================================
  # 3) MATRICES ATTACH (BPCells fragments + registry)
  # ============================================================
  if (!is.null(matrices) && length(matrices)) {
    .wb_require_pkg("BPCells", "matrix attach")
    .wb_require_pkg("Matrix", "matrix attach")

    for (matrix_id in names(matrices)) {
      x <- matrices[[matrix_id]]
      mat <- if (is.list(x) && !is.null(x$mat)) x$mat else x

      layer <- if (is.list(x) && !is.null(x$layer)) x$layer else "counts"
      feature_type <- if (is.list(x) && !is.null(x$feature_type)) x$feature_type else "feature"
      description <- if (is.list(x) && !is.null(x$description)) x$description else NULL

      if (!inherits(mat, "Matrix")) mat <- Matrix::Matrix(mat, sparse = TRUE)

      .wb_assert(!is.null(rownames(mat)), paste0("Matrix ", matrix_id, " missing rownames (feature_ids)"))
      .wb_assert(!is.null(colnames(mat)), paste0("Matrix ", matrix_id, " missing colnames (cell_ids)"))

      feature_ids <- as_chr(rownames(mat))
      col_cells <- as_chr(colnames(mat))

      keep_cols <- intersect(existing, intersect(col_cells, keep))
      .wb_assert(length(keep_cols) > 0, paste0("Matrix ", matrix_id, " has no columns matching bundle cells."))

      mat2 <- mat[, match(keep_cols, col_cells), drop = FALSE]
      colnames(mat2) <- keep_cols

      # ensure matrices row exists (create if missing)
      have <- DBI::dbGetQuery(
        con,
        "SELECT matrix_id FROM matrices WHERE matrix_id = ?;",
        params = list(matrix_id)
      )

      if (nrow(have) == 0) {
        DBI::dbWriteTable(
          con, "matrices",
          data.frame(
            matrix_id = matrix_id,
            layer = layer,
            feature_type = feature_type,
            n_features = NA_integer_,
            n_cells = NA_integer_,
            storage = "bpcells",
            path = NA_character_,
            description = description %||% paste0("Created by attach (", source, ")"),
            stringsAsFactors = FALSE
          ),
          append = TRUE
        )
      }

      # write BPCells fragment
      frag_dirname <- paste0("mat_frag_", .wb_matrix_id_path_safe(matrix_id), "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
      rel_path <- file.path("mat", frag_dirname)
      abs_path <- .wb_bundle_path_require(bundle, rel_path, expected_type="directory", must_exist=FALSE,
                                          purpose="attached matrix output")

      if (dir.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
      BPCells::write_matrix_dir(mat2, abs_path)

      # register fragment (your existing registry is the authority)
      frag_id <- wb_register_matrix_fragment(
        con = con,
        matrix_id = matrix_id,
        path_rel = rel_path,
        feature_ids = feature_ids,
        cell_ids = keep_cols,
        source = source,
        created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )

      # Keep the logical matrix registry usable when a matrix is first created
      # via attach. For staged assembly, many bundles will introduce each
      # modality exactly once through this path.
      DBI::dbExecute(
        con,
        "UPDATE matrices
           SET n_features = COALESCE(n_features, ?),
               n_cells = COALESCE(n_cells, ?),
               path = COALESCE(path, ?)
         WHERE matrix_id = ?;",
        params = list(
          as.integer(length(feature_ids)),
          as.integer(length(keep_cols)),
          rel_path,
          matrix_id
        )
      )

      feats_df <- if (identical(feature_type, "peak")) {
        peak_df <- .wb_parse_peak_ids(feature_ids)
        data.frame(
          matrix_id = matrix_id,
          feature_id = feature_ids,
          feature_type = "peak",
          chr = peak_df$chr,
          start = peak_df$start,
          end = peak_df$end,
          stringsAsFactors = FALSE
        )
      } else {
        data.frame(
          matrix_id = matrix_id,
          feature_id = feature_ids,
          feature_type = feature_type,
          chr = NA_character_,
          start = NA_integer_,
          end = NA_integer_,
          stringsAsFactors = FALSE
        )
      }

      existing_feats <- DBI::dbGetQuery(
        con,
        "SELECT matrix_id, feature_id, feature_type, chr, start, end
           FROM features
          WHERE matrix_id = ?;",
        params = list(matrix_id)
      )
      if (nrow(existing_feats)) {
        feats_df <- rbind(existing_feats, feats_df)
        feats_df <- feats_df[!duplicated(feats_df$feature_id, fromLast = TRUE), , drop = FALSE]
      }
      DBI::dbExecute(con, "DELETE FROM features WHERE matrix_id = ?;", params = list(matrix_id))
      DBI::dbWriteTable(con, "features", feats_df, append = TRUE)

      # Recipient validation and matrix coverage use the normalized logical
      # matrix membership, not only the fragment's ordered cell list.
      for (cell_id in keep_cols) DBI::dbExecute(con,
        "INSERT OR IGNORE INTO matrix_cells(matrix_id, cell_id) VALUES (?, ?);",
        params = list(matrix_id, cell_id))
      DBI::dbExecute(con,
        "UPDATE matrices SET n_cells=(SELECT COUNT(*) FROM matrix_cells WHERE matrix_id=?) WHERE matrix_id=?;",
        params = list(matrix_id, matrix_id))

      report$matrices[[matrix_id]] <- list(
        fragment_id = frag_id,
        n_features = length(feature_ids),
        n_cells = length(keep_cols),
        path = rel_path
      )
    }
  }

  report
}
