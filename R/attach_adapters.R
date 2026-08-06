# Attach adapter layer (non-breaking wrappers)

.wb_att_or <- function(x, y) if (is.null(x)) y else x

.wb_att_dup_values <- function(x) {
  x <- as.character(x %||% character(0))
  x <- x[nzchar(x)]
  if (!length(x)) return(character(0))
  u <- unique(x)
  u[duplicated(match(x, u))]
}

.wb_att_first_col_ids <- function(df, what) {
  .wb_assert(is.data.frame(df), paste0(what, " must be a data.frame."))
  .wb_assert(ncol(df) >= 1, paste0(what, " must have at least one column (first col = cell_id)."))
  ids <- as.character(df[[1]])
  ids <- ids[nzchar(ids)]
  .wb_assert(length(ids) == nrow(df), paste0(what, " first column contains empty/invalid cell_ids."))
  ids
}

.wb_att_detect_space_shape <- function(obj) {
  if (is.matrix(obj)) return("wide_hd_matrix")
  if (!is.data.frame(obj)) return("unknown")
  if (ncol(obj) < 3) return("unknown")

  nm <- tolower(colnames(obj))
  has_xy <- all(c("x", "y") %in% nm)
  has_dv <- all(c("dim", "value") %in% nm)
  if (has_xy) return("wide_2d")
  if (has_dv) return("long")

  if (ncol(obj) == 3) {
    v2 <- obj[[2]]
    v3 <- obj[[3]]
    intish <- is.integer(v2) || (is.numeric(v2) && all(abs(v2 - round(v2)) < 1e-8, na.rm = TRUE))
    num3 <- is.numeric(v3) || is.integer(v3)
    if (isTRUE(intish) && isTRUE(num3)) return("long")
    return("wide_2d")
  }

  "wide_hd_df"
}

.wb_attach_report_artifact <- function(bundle,
                                       apply_mode,
                                       validation,
                                       normalization,
                                       result,
                                       created_by = NULL,
                                       source = "attach") {
  .wb_require_pkg("jsonlite", "attach report artifact")
  if (!exists(".wb_promote_obs_table", mode = "function")) return(NA_character_)

  vv <- validation %||% list()
  nn <- normalization %||% list()
  rr <- result %||% list()

  rep_tbl <- data.frame(
    apply_mode = as.character(apply_mode %||% "")[1],
    n_target = as.integer(vv$n_target %||% NA_integer_),
    n_existing = as.integer(vv$n_existing %||% NA_integer_),
    n_missing = as.integer(vv$n_missing %||% NA_integer_),
    n_errors = as.integer(length(vv$errors %||% character(0))),
    n_warnings = as.integer(length(vv$warnings %||% character(0))),
    errors_json = jsonlite::toJSON(as.character(vv$errors %||% character(0)), auto_unbox = TRUE, null = "null"),
    warnings_json = jsonlite::toJSON(as.character(vv$warnings %||% character(0)), auto_unbox = TRUE, null = "null"),
    validation_json = jsonlite::toJSON(.wb_json_sanitize(vv), auto_unbox = TRUE, null = "null"),
    normalization_json = jsonlite::toJSON(.wb_json_sanitize(nn), auto_unbox = TRUE, null = "null"),
    result_json = jsonlite::toJSON(.wb_json_sanitize(rr), auto_unbox = TRUE, null = "null"),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE
  )

  prim <- wb_prim_obs_table(
    table = rep_tbl,
    table_type = "attach_report",
    entity_kind = "attach",
    meta = list(source = source)
  )

  run <- wb_new_run(
    op_name = "attach_apply",
    inputs = list(
      cell_set = "all",
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list(source = source)
    ),
    params = list(apply_mode = as.character(apply_mode %||% "")[1]),
    outputs = list(attach_report = prim),
    notes = "Attach report artifact"
  )

  .wb_promote_obs_table(
    bundle = bundle,
    run = run,
    out_name = "attach_report",
    prim = prim,
    name = "attach_report",
    description = "Attach validation/normalization/apply report",
    created_by = created_by,
    parent_artifacts = list()
  )
}

#' (Advanced) Validate attach payload (dry-run)
#'
#' @param bundle scworkbench bundle
#' @param cell_ids Optional explicit cell IDs. If NULL, inferred from payloads.
#' @param metadata Optional metadata data.frame (first col = cell_id)
#' @param spaces Optional named list of space payloads
#' @param matrices Optional named list of matrix payloads
#' @param strict If TRUE, stop on errors
#' @return list(valid, errors, warnings, inferred_cell_ids, n_target, n_existing, n_missing, details)
#' @export
wb_attach_validate <- function(bundle,
                               cell_ids = NULL,
                               metadata = NULL,
                               spaces = list(),
                               matrices = list(),
                               strict = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  errors <- character(0)
  warns <- character(0)
  infer <- character(0)
  detail_spaces <- list()
  detail_mats <- list()
  detail_meta <- list()

  if (!is.null(cell_ids)) {
    raw_ids <- as.character(cell_ids)
    dup_ids <- unique(.wb_att_dup_values(raw_ids))
    if (length(dup_ids)) errors <- c(errors, paste0("cell_ids contains duplicate IDs (n=", length(dup_ids), ")."))
    ids <- unique(raw_ids)
    ids <- ids[nzchar(ids)]
    if (!length(ids)) errors <- c(errors, "cell_ids provided but empty after cleaning.")
    infer <- c(infer, ids)
  }

  if (!is.null(metadata)) {
    if (!is.data.frame(metadata)) {
      errors <- c(errors, "metadata must be a data.frame.")
    } else {
      md_ids <- .wb_att_first_col_ids(metadata, "metadata")
      infer <- c(infer, md_ids)
      dup_md <- unique(.wb_att_dup_values(md_ids))
      detail_meta <- list(
        n_rows = nrow(metadata),
        n_cols = ncol(metadata),
        n_cells = length(unique(md_ids)),
        duplicate_cell_ids = dup_md
      )
      if (length(dup_md)) errors <- c(errors, paste0("metadata contains duplicate cell_ids (n=", length(dup_md), ")."))
    }
  }

  if (length(spaces %||% list())) {
    for (sid in names(spaces)) {
      obj <- spaces[[sid]]
      shp <- .wb_att_detect_space_shape(obj)
      if (identical(shp, "unknown")) {
        errors <- c(errors, paste0("space '", sid, "' has unsupported shape."))
        detail_spaces[[sid]] <- list(shape = "unknown", n_rows = NA_integer_, n_cells = 0L, status = "error")
        next
      }
      if (is.data.frame(obj)) {
        s_ids <- .wb_att_first_col_ids(obj, paste0("space '", sid, "'"))
        infer <- c(infer, s_ids)
        dup_sid <- unique(.wb_att_dup_values(s_ids))
        if (length(dup_sid)) warns <- c(warns, paste0("space '", sid, "' contains duplicate cell_ids (n=", length(dup_sid), ")."))
        detail_spaces[[sid]] <- list(
          shape = shp, n_rows = nrow(obj), n_cells = length(unique(s_ids)),
          duplicate_cell_ids = dup_sid, status = "ok"
        )
      } else if (is.matrix(obj)) {
        rn <- rownames(obj) %||% character(0)
        rn <- as.character(rn[nzchar(rn)])
        if (!length(rn)) {
          errors <- c(errors, paste0("space '", sid, "' matrix must have rownames=cell_id."))
          detail_spaces[[sid]] <- list(shape = shp, n_rows = nrow(obj), n_cells = 0L, status = "error")
        } else {
          infer <- c(infer, rn)
          dup_sid <- unique(.wb_att_dup_values(rn))
          if (length(dup_sid)) warns <- c(warns, paste0("space '", sid, "' matrix rownames contain duplicates (n=", length(dup_sid), ")."))
          detail_spaces[[sid]] <- list(
            shape = shp, n_rows = nrow(obj), n_cells = length(unique(rn)), n_dims = ncol(obj),
            duplicate_cell_ids = dup_sid, status = "ok"
          )
        }
      }
    }
  }

  if (length(matrices %||% list())) {
    for (mid in names(matrices)) {
      x <- matrices[[mid]]
      mat <- if (is.list(x) && !is.null(x$mat)) x$mat else x
      cn <- colnames(mat) %||% character(0)
      rn <- rownames(mat) %||% character(0)
      if (!length(cn)) errors <- c(errors, paste0("matrix '", mid, "' missing colnames (cell_ids)."))
      if (!length(rn)) errors <- c(errors, paste0("matrix '", mid, "' missing rownames (feature_ids)."))
      dup_mid <- unique(.wb_att_dup_values(cn))
      if (length(dup_mid)) warns <- c(warns, paste0("matrix '", mid, "' has duplicate cell_ids in colnames (n=", length(dup_mid), ")."))
      if (length(unique(rn)) != length(rn)) warns <- c(warns, paste0("matrix '", mid, "' has duplicate feature_ids in rownames."))
      infer <- c(infer, as.character(cn[nzchar(cn)]))
      detail_mats[[mid]] <- list(
        n_features = length(rn), n_cells = length(cn), duplicate_cell_ids = dup_mid,
        status = if (length(cn) && length(rn)) "ok" else "error"
      )
    }
  }

  infer <- unique(as.character(infer))
  infer <- infer[nzchar(infer)]
  if (!length(infer)) errors <- c(errors, "Could not infer any cell_ids from payload.")

  existing <- character(0)
  missing <- character(0)
  if (length(infer)) {
    ex <- as.character(DBI::dbGetQuery(bundle$con, "SELECT cell_id FROM cells;")$cell_id)
    existing <- intersect(infer, ex)
    missing <- setdiff(infer, ex)
    if (!length(existing)) {
      errors <- c(errors, "None of inferred/provided cell_ids exist in this bundle.")
    } else if (length(missing)) {
      warns <- c(warns, paste0("Some cell_ids are missing in bundle and will be ignored (n=", length(missing), ")."))
    }
  }

  out <- list(
    valid = length(errors) == 0,
    errors = unique(errors),
    warnings = unique(warns),
    inferred_cell_ids = infer,
    n_target = length(infer),
    n_existing = length(existing),
    n_missing = length(missing),
    details = list(
      metadata = detail_meta,
      spaces = detail_spaces,
      matrices = detail_mats,
      missing_cells_head = head(missing, 20)
    )
  )

  if (isTRUE(strict) && !isTRUE(out$valid)) {
    stop(paste(c("Attach validation failed:", paste0(" - ", out$errors)), collapse = "\n"), call. = FALSE)
  }
  out
}

#' (Advanced) Normalize attach payload to canonical forms
#'
#' @inheritParams wb_attach_validate
#' @return list(cell_ids, metadata, spaces, matrices, report)
#' @export
wb_attach_normalize <- function(bundle,
                                cell_ids = NULL,
                                metadata = NULL,
                                spaces = list(),
                                matrices = list()) {
  chk <- wb_attach_validate(
    bundle = bundle,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices,
    strict = TRUE
  )

  ids <- unique(as.character(.wb_att_or(cell_ids, chk$inferred_cell_ids)))
  ids <- ids[nzchar(ids)]

  norm_notes <- character(0)
  md_norm <- metadata
  if (!is.null(md_norm)) {
    md_norm <- as.data.frame(md_norm, stringsAsFactors = FALSE, check.names = FALSE)
    if (!identical(colnames(md_norm)[1], "cell_id")) {
      norm_notes <- c(norm_notes, paste0("metadata first column renamed from '", colnames(md_norm)[1], "' to 'cell_id'."))
      colnames(md_norm)[1] <- "cell_id"
    }
    md_norm <- md_norm[md_norm$cell_id %in% ids, , drop = FALSE]
    md_norm <- md_norm[!duplicated(md_norm$cell_id), , drop = FALSE]
  }

  spaces_norm <- list()
  space_notes <- list()
  if (length(spaces %||% list())) {
    for (sid in names(spaces)) {
      obj <- spaces[[sid]]
      shp <- .wb_att_detect_space_shape(obj)
      if (is.matrix(obj)) {
        m <- obj
        keep <- intersect(ids, rownames(m))
        spaces_norm[[sid]] <- m[keep, , drop = FALSE]
        space_notes[[sid]] <- c(space_notes[[sid]] %||% character(0), "matrix rows filtered to target cell_ids.")
        next
      }
      df <- as.data.frame(obj, stringsAsFactors = FALSE, check.names = FALSE)
      colnames(df)[1] <- "cell_id"
      df <- df[df$cell_id %in% ids, , drop = FALSE]
      if (!nrow(df)) {
        spaces_norm[[sid]] <- df
        next
      }

      if (identical(shp, "wide_2d")) {
        if (!all(c("x", "y") %in% tolower(colnames(df)))) {
          space_notes[[sid]] <- c(space_notes[[sid]] %||% character(0), "columns 2:3 remapped to x/y.")
          names(df)[2:3] <- c("x", "y")
        }
        spaces_norm[[sid]] <- df[, c("cell_id", "x", "y"), drop = FALSE]
      } else if (identical(shp, "long")) {
        if (!all(c("dim", "value") %in% tolower(colnames(df)))) {
          space_notes[[sid]] <- c(space_notes[[sid]] %||% character(0), "columns 2:3 remapped to dim/value.")
          names(df)[2:3] <- c("dim", "value")
        }
        df$dim <- suppressWarnings(as.integer(df$dim))
        df$value <- suppressWarnings(as.numeric(df$value))
        spaces_norm[[sid]] <- df[, c("cell_id", "dim", "value"), drop = FALSE]
      } else if (identical(shp, "wide_hd_df")) {
        m <- suppressWarnings(apply(df[, -1, drop = FALSE], 2, as.numeric))
        m <- as.matrix(m)
        spaces_norm[[sid]] <- data.frame(
          cell_id = rep(as.character(df$cell_id), each = ncol(m)),
          dim = rep(seq_len(ncol(m)), times = nrow(m)),
          value = as.vector(t(m)),
          stringsAsFactors = FALSE
        )
        space_notes[[sid]] <- c(
          space_notes[[sid]] %||% character(0),
          "wide high-D data.frame converted to canonical long coordinates."
        )
      } else {
        spaces_norm[[sid]] <- obj
      }
    }
  }

  mats_norm <- matrices

  list(
    cell_ids = ids,
    metadata = md_norm,
    spaces = spaces_norm,
    matrices = mats_norm,
    report = list(
      n_cells = length(ids),
      notes = unique(norm_notes),
      space_notes = space_notes
    )
  )
}

#' (Advanced) Apply attach using validated/normalized payload
#'
#' @inheritParams wb_attach_validate
#' @param source Provenance source tag
#' @param created_by Optional author tag
#' @param validate_only If TRUE, return normalized payload and do not write.
#' @param apply_mode Apply mode: atomic (recommended) or best_effort.
#' @param emit_report_artifact If TRUE, persist an obs_table attach report artifact.
#' @param metadata_field_refs Optional position-aligned explicit metadata field
#'   references for compatible updates.
#' @return Result from `wb_attach_to_cells()` (or normalized payload for validate_only=TRUE)
#' @export
wb_attach_apply <- function(bundle,
                            cell_ids = NULL,
                            metadata = NULL,
                            spaces = list(),
                            matrices = list(),
                            source = "attach",
                            created_by = NULL,
                            validate_only = FALSE,
                            apply_mode = c("atomic", "best_effort"),
                            emit_report_artifact = FALSE,
                            metadata_field_refs = NULL) {
  apply_mode <- match.arg(apply_mode)
  chk <- wb_attach_validate(
    bundle = bundle,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices,
    strict = FALSE
  )
  if (!isTRUE(chk$valid)) {
    stop(paste(c("Attach validation failed:", paste0(" - ", chk$errors)), collapse = "\n"), call. = FALSE)
  }

  norm <- wb_attach_normalize(
    bundle = bundle,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices
  )

  if (isTRUE(validate_only)) {
    return(invisible(list(validated = TRUE, validation = chk, normalized = norm)))
  }

  .wb_with_mutation_context(bundle = bundle, route = "ingestion", code = {
  run_attach <- function() {
    wb_attach_to_cells(
      bundle = bundle,
      matrices = norm$matrices,
      spaces = norm$spaces,
      metadata = norm$metadata,
      metadata_field_refs = metadata_field_refs,
      cell_ids = norm$cell_ids,
      source = source,
      created_by = created_by
    )
  }

  res <- NULL
  artifact_id <- NA_character_
  if (identical(apply_mode, "best_effort")) {
    res <- run_attach()
    if (isTRUE(emit_report_artifact)) {
      artifact_id <- .wb_attach_report_artifact(
        bundle = bundle,
        apply_mode = apply_mode,
        validation = chk,
        normalization = norm$report %||% list(),
        result = res %||% list(),
        created_by = created_by,
        source = source
      )
    }
    .wb_record_declared_ingestion(
      bundle = bundle, transaction_name = "attach_apply",
      matrix_ids = names(norm$matrices %||% list()),
      space_ids = names(norm$spaces %||% list()),
      source = source, created_by = created_by
    )
  } else {
    con <- bundle$con
    mat_root <- file.path(bundle$dir, "mat")
    dirs_before <- if (dir.exists(mat_root)) list.files(mat_root, full.names = TRUE) else character(0)
    out <- try(
      DBI::dbWithTransaction(con, {
        r0 <- run_attach()
        a0 <- NA_character_
        if (isTRUE(emit_report_artifact)) {
          a0 <- .wb_attach_report_artifact(
            bundle = bundle,
            apply_mode = apply_mode,
            validation = chk,
            normalization = norm$report %||% list(),
            result = r0 %||% list(),
            created_by = created_by,
            source = source
          )
        }
        .wb_record_declared_ingestion(
          bundle = bundle, transaction_name = "attach_apply",
          matrix_ids = names(norm$matrices %||% list()),
          space_ids = names(norm$spaces %||% list()),
          source = source, created_by = created_by,
          transaction_open = TRUE
        )
        list(result = r0, artifact_id = a0)
      }),
      silent = TRUE
    )
    if (inherits(out, "try-error")) {
      dirs_after <- if (dir.exists(mat_root)) list.files(mat_root, full.names = TRUE) else character(0)
      new_dirs <- setdiff(dirs_after, dirs_before)
      if (length(new_dirs)) {
        for (d in new_dirs) if (dir.exists(d)) unlink(d, recursive = TRUE, force = TRUE)
      }
      stop(paste0("Atomic attach failed and was rolled back. ", as.character(out)), call. = FALSE)
    }
    artifact_id <- as.character(out$artifact_id %||% NA_character_)[1]
    res <- out$result
  }

  attr(res, "attach_report") <- list(
    validation = chk,
    normalization = norm$report %||% list(),
    apply_mode = apply_mode,
    artifact_id = as.character(artifact_id %||% NA_character_)[1]
  )
  attr(res, "attach_report_artifact_id") <- as.character(artifact_id %||% NA_character_)[1]
  wb_refresh_manifest(bundle)
  res
  })
}
