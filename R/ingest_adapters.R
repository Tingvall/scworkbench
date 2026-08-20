# Ingest adapter layer (non-breaking wrappers)

.wb_ing_or <- function(x, y) if (is.null(x)) y else x

.wb_ing_dup_values <- function(x) {
  x <- as.character(x %||% character(0))
  x <- x[nzchar(x)]
  if (!length(x)) return(character(0))
  u <- unique(x)
  u[duplicated(match(x, u))]
}

.wb_ing_first_col_ids <- function(df, what) {
  .wb_assert(is.data.frame(df), paste0(what, " must be a data.frame."))
  .wb_assert(ncol(df) >= 1, paste0(what, " must have at least one column (first col = cell_id)."))
  ids <- as.character(df[[1]])
  ids <- ids[nzchar(ids)]
  .wb_assert(length(ids) == nrow(df), paste0(what, " first column contains empty/invalid cell_ids."))
  ids
}

.wb_ing_detect_space_shape <- function(obj) {
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

.wb_ingest_report_artifact <- function(bundle,
                                       set_name,
                                       apply_mode,
                                       validation,
                                       normalization,
                                       result,
                                       created_by = NULL,
                                       source = "ingest",
                                       matrix_ids = character(0),
                                       space_ids = character(0),
                                       transaction_open = FALSE,
                                       source_identity = NULL) {
  .wb_require_pkg("jsonlite", "ingest report artifact")
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  if (!exists(".wb_promote_obs_table", mode = "function")) return(NA_character_)

  vv <- validation %||% list()
  nn <- normalization %||% list()
  rr <- result %||% list()

  rep_tbl <- data.frame(
    set_name = as.character(set_name %||% "")[1],
    apply_mode = as.character(apply_mode %||% "")[1],
    n_cells = as.integer(vv$n_cells %||% NA_integer_),
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
    table_type = "ingest_report",
    entity_kind = "ingest",
    meta = list(
      source = source,
      set_name = as.character(set_name %||% "")[1]
    )
  )

  run <- wb_new_run(
    op_name = "ingest_apply",
    inputs = list(
      cell_set = paste0("set:", as.character(set_name %||% "")[1]),
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list(set_name = as.character(set_name %||% "")[1], source = source)
    ),
    params = list(apply_mode = as.character(apply_mode %||% "")[1]),
    outputs = list(ingest_report = prim),
    notes = "Ingest report artifact"
  )

  artifact_id <- .wb_promote_obs_table(
    bundle = bundle,
    run = run,
    out_name = "ingest_report",
    prim = prim,
    name = paste0("ingest_report__", as.character(set_name %||% "")[1]),
    description = "Ingest validation/normalization/apply report",
    created_by = created_by,
    parent_artifacts = list()
  )
  .wb_prov_record_ingestion(
    bundle = bundle, run = run, artifact_id = artifact_id,
    matrix_ids = matrix_ids, created_by = created_by,
    transaction_open = transaction_open, source_identity = source_identity,
    authoritative_entity_outputs = FALSE
  )
  .wb_prov_link_source_to_existing_producers(
    bundle, matrix_ids = matrix_ids, space_ids = space_ids,
    source_identity = source_identity
  )
  if (!isTRUE(transaction_open)) .wb_refresh_manifest_committed(bundle)
  artifact_id
}

#' Validate ingest payload (dry-run)
#'
#' Runs shape and consistency checks for ingest payloads without writing.
#'
#' @param bundle scworkbench bundle
#' @param set_name Target set name for ingest
#' @param cell_ids Optional explicit cell IDs. If NULL, inferred from payloads.
#' @param metadata Optional metadata data.frame (first col = cell_id)
#' @param spaces Optional named list of space payloads
#' @param matrices Optional named list of matrix payloads
#' @param strict If TRUE, stop on validation errors. If FALSE, return diagnostics.
#' @return list(valid, errors, warnings, inferred_cell_ids, n_cells, details)
#' @export
wb_ingest_validate <- function(bundle,
                               set_name,
                               cell_ids = NULL,
                               metadata = NULL,
                               spaces = list(),
                               matrices = list(),
                               strict = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(set_name) && length(set_name) == 1 && nzchar(set_name), "set_name invalid")

  errors <- character(0)
  warns <- character(0)
  infer <- character(0)
  detail_spaces <- list()
  detail_mats <- list()
  detail_meta <- list()

  if (!is.null(cell_ids)) {
    raw_ids <- as.character(cell_ids)
    dup_ids <- unique(.wb_ing_dup_values(raw_ids))
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
      md_ids <- .wb_ing_first_col_ids(metadata, "metadata")
      infer <- c(infer, md_ids)
      dup_md <- unique(.wb_ing_dup_values(md_ids))
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
      shp <- .wb_ing_detect_space_shape(obj)
      if (identical(shp, "unknown")) {
        errors <- c(errors, paste0("space '", sid, "' has unsupported shape."))
        detail_spaces[[sid]] <- list(shape = "unknown", n_rows = NA_integer_, n_cells = 0L, status = "error")
        next
      }
      if (is.data.frame(obj)) {
        s_ids <- .wb_ing_first_col_ids(obj, paste0("space '", sid, "'"))
        infer <- c(infer, s_ids)
        dup_sid <- unique(.wb_ing_dup_values(s_ids))
        if (length(dup_sid)) warns <- c(warns, paste0("space '", sid, "' contains duplicate cell_ids (n=", length(dup_sid), ")."))
        detail_spaces[[sid]] <- list(
          shape = shp,
          n_rows = nrow(obj),
          n_cells = length(unique(s_ids)),
          duplicate_cell_ids = dup_sid,
          status = "ok"
        )
      } else if (is.matrix(obj)) {
        rn <- rownames(obj) %||% character(0)
        rn <- as.character(rn[nzchar(rn)])
        if (!length(rn)) {
          errors <- c(errors, paste0("space '", sid, "' matrix must have rownames=cell_id."))
          detail_spaces[[sid]] <- list(shape = shp, n_rows = nrow(obj), n_cells = 0L, status = "error")
        } else {
          infer <- c(infer, rn)
          dup_sid <- unique(.wb_ing_dup_values(rn))
          if (length(dup_sid)) warns <- c(warns, paste0("space '", sid, "' matrix rownames contain duplicates (n=", length(dup_sid), ")."))
          detail_spaces[[sid]] <- list(
            shape = shp,
            n_rows = nrow(obj),
            n_cells = length(unique(rn)),
            n_dims = ncol(obj),
            duplicate_cell_ids = dup_sid,
            status = "ok"
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
      dup_mid <- unique(.wb_ing_dup_values(cn))
      if (length(dup_mid)) warns <- c(warns, paste0("matrix '", mid, "' has duplicate cell_ids in colnames (n=", length(dup_mid), ")."))
      if (length(unique(rn)) != length(rn)) warns <- c(warns, paste0("matrix '", mid, "' has duplicate feature_ids in rownames."))
      infer <- c(infer, as.character(cn[nzchar(cn)]))
      detail_mats[[mid]] <- list(
        n_features = length(rn),
        n_cells = length(cn),
        duplicate_cell_ids = dup_mid,
        status = if (length(cn) && length(rn)) "ok" else "error"
      )
    }
  }

  infer <- unique(as.character(infer))
  infer <- infer[nzchar(infer)]
  if (!length(infer)) errors <- c(errors, "Could not infer any cell_ids from payload.")

  if (length(infer)) {
    con <- bundle$con
    cl <- .wb_sql_in_json(infer)
    existing <- DBI::dbGetQuery(
      con,
      paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"),
      params = cl$params
    )$cell_id
    existing <- as.character(existing)
    if (length(existing)) errors <- c(errors, paste0("Some cell_ids already exist (overwrite not supported). Example: ", existing[[1]]))
  }

  out <- list(
    valid = length(errors) == 0,
    errors = unique(errors),
    warnings = unique(warns),
    inferred_cell_ids = infer,
    n_cells = length(infer),
    details = list(
      metadata = detail_meta,
      spaces = detail_spaces,
      matrices = detail_mats
    )
  )

  if (isTRUE(strict) && !isTRUE(out$valid)) {
    stop(paste(c("Ingest validation failed:", paste0(" - ", out$errors)), collapse = "\n"), call. = FALSE)
  }
  out
}

#' Normalize ingest payload to canonical forms
#'
#' Returns payload normalized to conventions expected by ingest writers.
#'
#' @inheritParams wb_ingest_validate
#' @return list(cell_ids, metadata, spaces, matrices, report)
#' @export
wb_ingest_normalize <- function(bundle,
                                set_name,
                                cell_ids = NULL,
                                metadata = NULL,
                                spaces = list(),
                                matrices = list()) {
  chk <- wb_ingest_validate(
    bundle = bundle,
    set_name = set_name,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices,
    strict = TRUE
  )

  ids <- unique(as.character(.wb_ing_or(cell_ids, chk$inferred_cell_ids)))
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
      shp <- .wb_ing_detect_space_shape(obj)
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
        rownames(m) <- as.character(df$cell_id)
        spaces_norm[[sid]] <- m
        space_notes[[sid]] <- c(space_notes[[sid]] %||% character(0), "wide high-D data.frame converted to numeric matrix.")
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

#' Apply ingest using validated/normalized payload
#'
#' Thin wrapper over `wb_ingest_cells()` that performs adapter checks first.
#'
#' @inheritParams wb_ingest_validate
#' @param source Provenance source tag
#' @param source_identity Optional immutable structured record describing the
#'   supplied source. See `wb_prov_source_identity()` for retrieval.
#' @param created_by Optional author tag
#' @param validate_only If TRUE, return normalized payload and do not write.
#' @param apply_mode `"atomic"` applies all validated data together;
#'   `"best_effort"` allows supported partial attachment behavior.
#' @param emit_report_artifact If TRUE, persist an obs_table ingest report artifact.
#' @return Result from `wb_ingest_cells()` (or normalized payload when validate_only=TRUE)
#' @export
wb_ingest_apply <- function(bundle,
                            set_name,
                            cell_ids = NULL,
                            metadata = NULL,
                            spaces = list(),
                            matrices = list(),
                            source = "ingest",
                            source_identity = NULL,
                            created_by = NULL,
                            validate_only = FALSE,
                            apply_mode = c("atomic", "best_effort"),
                            emit_report_artifact = FALSE) {
  if (!is.null(source_identity)) source_identity <- wb_source_preflight(source_identity, verify_files=TRUE, strict=TRUE)$source_identity
  .wb_assert_bundle_writable(bundle, "ingestion")
  apply_mode <- match.arg(apply_mode)
  .wb_assert(is.null(metadata) || identical(apply_mode, "atomic"),
             "Metadata ingestion requires apply_mode='atomic' so values, identity, and provenance publish together.")
  chk <- wb_ingest_validate(
    bundle = bundle,
    set_name = set_name,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices,
    strict = FALSE
  )
  if (!isTRUE(chk$valid)) {
    stop(paste(c("Ingest validation failed:", paste0(" - ", chk$errors)), collapse = "\n"), call. = FALSE)
  }

  norm <- wb_ingest_normalize(
    bundle = bundle,
    set_name = set_name,
    cell_ids = cell_ids,
    metadata = metadata,
    spaces = spaces,
    matrices = matrices
  )

  if (isTRUE(validate_only)) {
    return(invisible(list(
      validated = TRUE,
      normalized = norm,
      validation = chk
    )))
  }

  .wb_with_mutation_context(bundle = bundle, route = "ingestion", code = {
  run_ingest <- function(transaction_open = FALSE) {
    old_transaction <- getOption("scworkbench.ingest_transaction_open", FALSE)
    options(scworkbench.ingest_transaction_open = isTRUE(transaction_open))
    on.exit(options(scworkbench.ingest_transaction_open = old_transaction), add = TRUE)
    wb_ingest_cells(
      bundle = bundle,
      set_name = set_name,
      cell_ids = norm$cell_ids,
      metadata = norm$metadata,
      spaces = norm$spaces,
      matrices = norm$matrices,
      source = source,
      created_by = created_by
    )
  }

  res <- NULL
  artifact_id <- NA_character_
  if (identical(apply_mode, "best_effort")) {
    res <- run_ingest(FALSE)
    if (isTRUE(emit_report_artifact)) {
      artifact_id <- .wb_ingest_report_artifact(
        bundle = bundle,
        set_name = set_name,
        apply_mode = apply_mode,
        validation = chk,
        normalization = norm$report %||% list(),
        result = res %||% list(),
        created_by = created_by,
        source = source,
        matrix_ids = names(norm$matrices %||% list()),
        space_ids = names(norm$spaces %||% list()), source_identity = source_identity
      )
    }
    if (!isTRUE(emit_report_artifact)) {
      .wb_record_declared_ingestion(
        bundle = bundle, transaction_name = "ingest_apply",
        matrix_ids = names(norm$matrices %||% list()),
        space_ids = names(norm$spaces %||% list()), source = source,
        created_by = created_by, source_identity = source_identity
      )
    }
  } else {
    con <- bundle$con
    payload_collector <- .wb_space_payload_transaction_collector()
    old_payload_collector <- getOption("scworkbench.space_payload_transaction_collector", NULL)
    options(scworkbench.space_payload_transaction_collector = payload_collector)
    on.exit(options(scworkbench.space_payload_transaction_collector = old_payload_collector), add = TRUE)
    mat_root <- file.path(bundle$dir, "mat")
    dirs_before <- if (dir.exists(mat_root)) list.files(mat_root, full.names = TRUE) else character(0)
    err <- NULL
    res <- try(
      DBI::dbWithTransaction(con, {
        r0 <- run_ingest(TRUE)
        a0 <- NA_character_
        if (isTRUE(emit_report_artifact)) {
          a0 <- .wb_ingest_report_artifact(
            bundle = bundle,
            set_name = set_name,
            apply_mode = apply_mode,
            validation = chk,
            normalization = norm$report %||% list(),
            result = r0 %||% list(),
            created_by = created_by,
            source = source,
            matrix_ids = names(norm$matrices %||% list()),
            space_ids = names(norm$spaces %||% list()),
            transaction_open = TRUE, source_identity = source_identity
          )
        }
        if (!isTRUE(emit_report_artifact)) {
          .wb_record_declared_ingestion(
            bundle = bundle, transaction_name = "ingest_apply",
            matrix_ids = names(norm$matrices %||% list()),
            space_ids = names(norm$spaces %||% list()), source = source,
            created_by = created_by, source_identity = source_identity,
            transaction_open = TRUE
          )
        }
        list(result = r0, artifact_id = a0)
      }),
      silent = TRUE
    )
    if (inherits(res, "try-error")) {
      .wb_space_payload_transaction_finish(payload_collector, committed = FALSE)
      err <- as.character(res)
      dirs_after <- if (dir.exists(mat_root)) list.files(mat_root, full.names = TRUE) else character(0)
      new_dirs <- setdiff(dirs_after, dirs_before)
      if (length(new_dirs)) {
        for (d in new_dirs) {
          if (dir.exists(d)) unlink(d, recursive = TRUE, force = TRUE)
        }
      }
      stop(paste0("Atomic ingest failed and was rolled back. ", err), call. = FALSE)
    }
    .wb_space_payload_transaction_finish(payload_collector, committed = TRUE)
    if (is.list(res) && !is.null(res$result)) {
      artifact_id <- as.character(res$artifact_id %||% NA_character_)[1]
      res <- res$result
    }
  }

  attr(res, "ingest_report") <- list(
    validation = chk,
    normalization = norm$report %||% list(),
    apply_mode = apply_mode,
    artifact_id = as.character(artifact_id %||% NA_character_)[1]
  )
  attr(res, "ingest_report_artifact_id") <- as.character(artifact_id %||% NA_character_)[1]
  res
  })
}
