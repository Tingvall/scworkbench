# Model reference path handling.
#
# Contract: model files stored inside a bundle are addressed by a path relative
# to bundle$dir. Absolute legacy rows are inventory-only until a caller uses the
# explicit, provenance-producing import route below.

.wb_bundle_root <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle.")
  normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
}

.wb_model_ref_bundle_relative_path <- function(bundle, model_path) {
  model_path <- as.character(model_path %||% "")[1]
  if (!nzchar(model_path)) return(model_path)
  if (!.wb_path_is_absolute(model_path)) {
    status <- .wb_path_status(bundle$dir, model_path, must_exist = FALSE,
                              purpose = "model reference")
    .wb_assert(isTRUE(status$ok), paste0(status$code, ": invalid model reference path."))
    return(status$relative)
  }
  bundle_dir <- .wb_bundle_root(bundle)
  abs <- normalizePath(model_path, winslash = "/", mustWork = FALSE)
  if (.wb_path_inside(abs, bundle_dir)) {
    rel <- substring(abs, nchar(bundle_dir) + 2L)
    status <- .wb_path_status(bundle_dir, rel, must_exist = FALSE, purpose = "model reference")
    .wb_assert(isTRUE(status$ok), paste0(status$code, ": invalid model reference path."))
    return(status$relative)
  }
  model_path
}

.wb_resolve_model_ref_path <- function(bundle, model_path) {
  raw <- as.character(model_path %||% "")[1]
  .wb_assert(nzchar(raw), "model_ref path is empty.")

  if (.wb_path_is_absolute(raw)) {
    # PyBench v1 compatibility: an engine-created staging overlay may receive
    # an absolute runtime result before promotion canonicalizes it. It is never
    # durable, and is accepted only when it resolves inside that exact staging
    # root. Committed bundles do not receive this exception.
    if (nzchar(as.character(bundle$staging_source_dir %||% "")[1])) {
      resolved <- normalizePath(raw, winslash="/", mustWork=FALSE)
      root <- .wb_bundle_root(bundle)
      if (.wb_path_inside(resolved, root) && (file.exists(resolved) || dir.exists(resolved))) {
        return(normalizePath(resolved, winslash="/", mustWork=TRUE))
      }
    }
    stop("LEGACY_EXTERNAL_MODEL_REFERENCE: absolute model paths are nonportable and are never loaded implicitly. Use wb_repair_model_ref_paths(..., import_external = TRUE) from a trusted writable source.", call. = FALSE)
  }
  .wb_bundle_path_require(bundle, raw, expected_type = "either", must_exist = TRUE,
                          purpose = "model_ref payload")
}

#' (Advanced) Repair relocatable model_ref artifact paths
#'
#' Rewrites `artifact_model_ref`, `artifact_umap_model`, and `space_models`
#' model paths to bundle-relative paths. It never searches arbitrary filesystem
#' locations or guesses a replacement by basename.
#'
#' @param bundle scworkbench bundle.
#' @param dry_run If `TRUE`, report planned changes without updating SQLite.
#' @param import_external Explicitly authorize reading an absolute legacy model
#'   source, copy it into bundle-owned model storage, replace the registry path with a
#'   contained relative path, and record a declared ingestion transaction.
#'   The default never probes an external path.
#' @return Data frame with one row per registered model path and planned action.
#' @export
wb_repair_model_ref_paths <- function(bundle, dry_run = TRUE, import_external = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle.")
  if (!isTRUE(dry_run)) {
    return(.wb_with_mutation_context(bundle, route = "ingestion", code = {
      .wb_repair_model_ref_paths_locked(bundle, dry_run = FALSE,
                                        import_external = import_external)
    }))
  }
  .wb_repair_model_ref_paths_locked(bundle, dry_run = TRUE,
                                    import_external = import_external)
}

.wb_repair_model_ref_paths_locked <- function(bundle, dry_run = TRUE,
                                               import_external = FALSE) {
  con <- bundle$con
  .wb_assert(!is.null(con), "wb_repair_model_ref_paths(): bundle$con is NULL.")
  wb_migrate_artifacts(bundle)

  rows <- list()
  if (.wb_table_exists(con,"artifact_model_ref")) {
    artifact_rows <- DBI::dbGetQuery(con,"SELECT artifact_id AS entity_id, artifact_id, model_path FROM artifact_model_ref ORDER BY artifact_id;")
    artifact_rows$registry_table <- rep("artifact_model_ref", nrow(artifact_rows))
    rows[[length(rows)+1L]] <- artifact_rows
  }
  if (.wb_table_exists(con,"artifact_umap_model")) {
    umap_rows <- DBI::dbGetQuery(con,"SELECT artifact_id AS entity_id, artifact_id, model_path FROM artifact_umap_model ORDER BY artifact_id;")
    umap_rows$registry_table <- rep("artifact_umap_model", nrow(umap_rows))
    rows[[length(rows)+1L]] <- umap_rows
  }
  if (.wb_table_exists(con,"space_models")) {
    space_rows <- DBI::dbGetQuery(con,"SELECT space_id AS entity_id, model_path FROM space_models ORDER BY space_id;")
    space_rows$artifact_id <- rep(NA_character_, nrow(space_rows))
    space_rows$registry_table <- rep("space_models", nrow(space_rows))
    rows[[length(rows)+1L]] <- space_rows
  }
  rows <- if(length(rows)) do.call(rbind,lapply(rows,function(x) x[,c("registry_table","entity_id","artifact_id","model_path")])) else data.frame()
  if (!nrow(rows)) {
    return(data.frame(
      artifact_id = character(0),
      registry_table = character(0),
      entity_id = character(0),
      old_model_path = character(0),
      new_model_path = character(0),
      action = character(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- lapply(seq_len(nrow(rows)), function(i) {
    registry_table <- as.character(rows$registry_table[[i]])
    entity_id <- as.character(rows$entity_id[[i]])
    artifact_id <- as.character(rows$artifact_id[[i]] %||% NA_character_)
    old <- as.character(rows$model_path[[i]] %||% "")
    new <- old
    action <- "unchanged"

    if (!nzchar(old)) {
      action <- "empty_path"
    } else if (.wb_path_is_absolute(old)) {
      bundle_dir <- .wb_bundle_root(bundle)
      old_norm <- normalizePath(old, winslash = "/", mustWork = FALSE)
      prefix <- paste0(bundle_dir, "/")
      if (startsWith(old_norm, prefix)) {
        new <- substring(old_norm, nchar(prefix) + 1L)
        checked <- .wb_path_status(bundle_dir, new, must_exist = TRUE,
                                   purpose = "legacy model reference")
        action <- if (isTRUE(checked$ok)) "repair_absolute_inside_bundle" else checked$code
      } else {
        if (isTRUE(import_external)) {
          safe_id <- gsub("[^A-Za-z0-9._-]", "_", entity_id)
          suffix <- tools::file_ext(basename(old))
          model_root <- if(identical(registry_table,"space_models")) file.path("models","imported") else "artifact_models"
          new <- file.path(model_root, paste0(safe_id, if(nzchar(suffix)) paste0(".", suffix) else ""))
          action <- "import_legacy_external"
        } else {
          action <- "legacy_external_nonportable"
        }
      }
    } else {
      checked <- .wb_path_status(.wb_bundle_root(bundle), old, must_exist = TRUE,
                                 purpose = "model reference")
      action <- if (isTRUE(checked$ok)) "relative_ok" else checked$code
    }

    data.frame(
      artifact_id = artifact_id,
      registry_table = registry_table,
      entity_id = entity_id,
      old_model_path = old,
      new_model_path = new,
      action = action,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, out)

  changed <- out[
    out$action %in% c("repair_absolute_inside_bundle", "import_legacy_external") &
      nzchar(out$new_model_path) &
      out$new_model_path != out$old_model_path,
    ,
    drop = FALSE
  ]
  if (!isTRUE(dry_run) && nrow(changed)) {
    created_targets <- character()
    publication_complete <- FALSE
    on.exit({
      if (!isTRUE(publication_complete) && length(created_targets)) {
        for (target in rev(created_targets)) {
          if (file.exists(target) || dir.exists(target)) unlink(target, recursive=TRUE, force=TRUE)
        }
      }
    }, add=TRUE)
    DBI::dbWithTransaction(con, {
      for (i in seq_len(nrow(changed))) {
        old <- changed$old_model_path[[i]]
        new <- changed$new_model_path[[i]]
        if (identical(changed$action[[i]], "import_legacy_external")) {
          .wb_assert(isTRUE(import_external), "External model import requires import_external=TRUE.")
          .wb_assert(file.exists(old) || dir.exists(old), paste0("Legacy external model source is missing: ", old))
          target <- .wb_bundle_path_require(bundle, new, must_exist = FALSE,
                                            purpose = "imported model destination")
          .wb_assert(!file.exists(target) && !dir.exists(target), paste0("Imported model destination already exists: ", new))
          dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
          copied <- isTRUE(file.copy(old, target, recursive = dir.exists(old), copy.mode = TRUE))
          .wb_assert(copied, paste0("Failed to copy legacy external model into bundle: ", old))
          created_targets <- c(created_targets, target)
          imported_status <- if (dir.exists(target)) {
            .wb_path_tree_status(bundle$dir,new,purpose="imported legacy model tree")
          } else .wb_path_status(bundle$dir,new,expected_type="file",must_exist=TRUE,purpose="imported legacy model")
          .wb_assert(isTRUE(imported_status$ok),paste0(imported_status$code,": imported legacy model is not bundle-contained."))
        }
        DBI::dbExecute(
          con,
          switch(changed$registry_table[[i]],
            artifact_model_ref="UPDATE artifact_model_ref SET model_path = ? WHERE artifact_id = ?;",
            artifact_umap_model="UPDATE artifact_umap_model SET model_path = ? WHERE artifact_id = ?;",
            space_models="UPDATE space_models SET model_path = ? WHERE space_id = ?;"
          ),
          params = list(new, changed$entity_id[[i]])
        )
        if (identical(changed$action[[i]], "import_legacy_external")) {
          row <- switch(changed$registry_table[[i]],
            artifact_model_ref=DBI::dbGetQuery(con,"SELECT engine,model_space_id,in_space_id,model_type FROM artifact_model_ref WHERE artifact_id=?;",params=list(changed$entity_id[[i]])),
            artifact_umap_model=transform(DBI::dbGetQuery(con,"SELECT space_id AS model_space_id FROM artifact_umap_model WHERE artifact_id=?;",params=list(changed$entity_id[[i]])),engine="uwot",in_space_id="",model_type="uwot_umap"),
            space_models=(function(x) {
              x$engine <- ifelse(grepl("uwot",x$model_type,ignore.case=TRUE),"uwot",x$model_type)
              x
            })(DBI::dbGetQuery(con,"SELECT space_id AS model_space_id,source_space_id AS in_space_id,model_type FROM space_models WHERE space_id=?;",params=list(changed$entity_id[[i]])))
          )
          imported_artifact_id <- as.character(changed$artifact_id[[i]])[1]
          if (is.na(imported_artifact_id)) imported_artifact_id <- ""
          prim <- wb_prim_model_ref(model_space_id=as.character(row$model_space_id[1]), in_space_id=as.character(row$in_space_id[1] %||% ""), engine=as.character(row$engine[1]), artifact_id=imported_artifact_id)
          prim$model_path <- new
          .wb_record_declared_ingestion(bundle, transaction_name="import_legacy_model_ref", source="legacy_external_model", additional_outputs=list(imported_model=prim), transaction_open=TRUE, source_identity=list(source_type="legacy_external_model", inputs=list(list(path=old, role="model_payload", format=as.character(row$model_type[1] %||% row$engine[1]), checksum=.wb_prov_path_identity(old)$content_sha256, checksum_algorithm="sha256", bundled=FALSE))))
        }
      }
      wb_refresh_manifest(bundle)
    })
    publication_complete <- TRUE
  }

  out
}
