# Model reference path handling.
#
# Contract: model_ref files stored inside a bundle are addressed by a path
# relative to bundle$dir. Loaders may resolve old absolute rows only when the
# target is either still readable as-is or safely recoverable from this bundle's
# artifact_models/ directory.

.wb_path_is_absolute <- function(path) {
  path <- as.character(path %||% "")[1]
  if (!nzchar(path)) return(FALSE)
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

.wb_bundle_root <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle.")
  normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
}

.wb_model_ref_bundle_relative_path <- function(bundle, model_path) {
  model_path <- as.character(model_path %||% "")[1]
  if (!nzchar(model_path)) return(model_path)
  if (!.wb_path_is_absolute(model_path)) return(gsub("\\\\", "/", model_path))

  bundle_dir <- .wb_bundle_root(bundle)
  abs <- normalizePath(model_path, winslash = "/", mustWork = FALSE)
  prefix <- paste0(bundle_dir, "/")
  if (identical(abs, bundle_dir)) return("")
  if (startsWith(abs, prefix)) {
    return(substring(abs, nchar(prefix) + 1L))
  }
  model_path
}

.wb_resolve_model_ref_path <- function(bundle, model_path) {
  raw <- as.character(model_path %||% "")[1]
  .wb_assert(nzchar(raw), "model_ref path is empty.")

  attempts <- character(0)
  add_attempt <- function(path) {
    path <- as.character(path %||% "")[1]
    if (nzchar(path) && !(path %in% attempts)) attempts <<- c(attempts, path)
    path
  }

  if (.wb_path_is_absolute(raw)) {
    p <- add_attempt(raw)
    if (file.exists(p)) {
      return(normalizePath(p, winslash = "/", mustWork = TRUE))
    }
    candidate <- file.path(.wb_bundle_root(bundle), "artifact_models", basename(raw))
    p <- add_attempt(candidate)
    if (file.exists(p)) {
      return(normalizePath(p, winslash = "/", mustWork = TRUE))
    }
  } else {
    candidate <- file.path(.wb_bundle_root(bundle), raw)
    p <- add_attempt(candidate)
    if (file.exists(p)) {
      return(normalizePath(p, winslash = "/", mustWork = TRUE))
    }
  }

  stop(
    paste0(
      "model_ref file could not be resolved. Stored path: ", raw,
      ". Attempted: ", paste(attempts, collapse = " ; ")
    ),
    call. = FALSE
  )
}

#' Repair relocatable model_ref artifact paths
#'
#' Rewrites `artifact_model_ref.model_path` rows to bundle-relative paths when
#' the corresponding model file exists inside this bundle. This does not search
#' arbitrary filesystem locations: stale absolute paths are repaired only by
#' matching their basename under `bundle/artifact_models/`.
#'
#' @param bundle scworkbench bundle.
#' @param dry_run If `TRUE`, report planned changes without updating SQLite.
#' @return Data frame with one row per model_ref path row and planned action.
#' @export
wb_repair_model_ref_paths <- function(bundle, dry_run = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle.")
  con <- bundle$con
  .wb_assert(!is.null(con), "wb_repair_model_ref_paths(): bundle$con is NULL.")
  wb_migrate_artifacts(bundle)

  rows <- DBI::dbGetQuery(
    con,
    "SELECT artifact_id, model_path FROM artifact_model_ref ORDER BY artifact_id;"
  )
  if (!nrow(rows)) {
    return(data.frame(
      artifact_id = character(0),
      old_model_path = character(0),
      new_model_path = character(0),
      action = character(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- lapply(seq_len(nrow(rows)), function(i) {
    artifact_id <- as.character(rows$artifact_id[[i]])
    old <- as.character(rows$model_path[[i]] %||% "")
    new <- old
    action <- "unchanged"

    if (!nzchar(old)) {
      action <- "empty_path"
    } else if (.wb_path_is_absolute(old)) {
      bundle_dir <- .wb_bundle_root(bundle)
      old_norm <- normalizePath(old, winslash = "/", mustWork = FALSE)
      prefix <- paste0(bundle_dir, "/")
      if (file.exists(old) && startsWith(old_norm, prefix)) {
        new <- substring(old_norm, nchar(prefix) + 1L)
        action <- if (!identical(new, old)) "repair_absolute_inside_bundle" else "unchanged"
      } else {
        candidate <- file.path(bundle_dir, "artifact_models", basename(old))
        if (file.exists(candidate)) {
          new <- file.path("artifact_models", basename(old))
          action <- "repair_stale_absolute_basename"
        } else if (file.exists(old)) {
          action <- "absolute_external_exists"
        } else {
          action <- "missing"
        }
      }
    } else {
      candidate <- file.path(.wb_bundle_root(bundle), old)
      action <- if (file.exists(candidate)) "relative_ok" else "relative_missing"
    }

    data.frame(
      artifact_id = artifact_id,
      old_model_path = old,
      new_model_path = new,
      action = action,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, out)

  changed <- out[
    out$action %in% c("repair_absolute_inside_bundle", "repair_stale_absolute_basename") &
      nzchar(out$new_model_path) &
      out$new_model_path != out$old_model_path,
    ,
    drop = FALSE
  ]
  if (!isTRUE(dry_run) && nrow(changed)) {
    for (i in seq_len(nrow(changed))) {
      DBI::dbExecute(
        con,
        "UPDATE artifact_model_ref SET model_path = ? WHERE artifact_id = ?;",
        params = list(changed$new_model_path[[i]], changed$artifact_id[[i]])
      )
    }
  }

  out
}
