# Shared getter decoding for retained artifacts and receipt-audited private
# operation outputs. Decoding does not issue provenance or graph authority.
.wb_artifact_cell_payload_decode <- function(con, art, artifact_id, type) {
  .wb_assert(type %in% c("cell_vector", "cell_vector_family"),
    "Cell payload decoder requires a cell primitive kind.")
  legacy_object_identity_required <- FALSE
  prim <- switch(type,
    # ---- cell_vector stored as artifact_labels (cell_id, label) ----
    "cell_vector" = {
      payload_descriptor <- .wb_artifact_object_descriptor(
        art$provenance_json[[1L]], "cell_vector", artifact_id
      )
      has_value_type <- .wb_db_has_column(con, "artifact_labels", "value_type")
      has_value_num  <- .wb_db_has_column(con, "artifact_labels", "value_num")
      q <- if (has_value_type || has_value_num) {
        paste0(
          "SELECT al.cell_id, al.label, ",
          if (has_value_type) "al.value_type" else "NULL AS value_type", ", ",
          if (has_value_num) "al.value_num" else "NULL AS value_num", "
           FROM artifact_labels AS al
           LEFT JOIN cells AS c ON c.cell_id = al.cell_id
           WHERE al.artifact_id = ?
           ORDER BY c.rowid, al.cell_id;"
        )
      } else {
        "SELECT al.cell_id, al.label, NULL AS value_type, NULL AS value_num
         FROM artifact_labels AS al
         LEFT JOIN cells AS c ON c.cell_id = al.cell_id
         WHERE al.artifact_id = ?
         ORDER BY c.rowid, al.cell_id;"
      }
      df <- DBI::dbGetQuery(con, q, params = list(artifact_id))
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_labels for ", artifact_id))
      df <- .wb_artifact_restore_object_row_order(
        df, payload_descriptor, "cell_vector", artifact_id
      )
      durable_meta <- if (.wb_graph_object_has_attestation(con, artifact_id, "cell_vector")) {
        .wb_graph_object_restore(con, artifact_id, df, payload_descriptor, "cell_vector")
      } else {
        legacy_object_identity_required <- TRUE
        .wb_object_primitive_meta_from_descriptor(payload_descriptor)
      }

      vt <- unique(as.character(stats::na.omit(df$value_type %||% character(0))))
      .wb_assert(length(vt) <= 1L,
                 paste0("wb_art_load(): conflicting cell-vector value types for ", artifact_id))
      inferred_type <- if (length(vt)) vt[[1L]] else "categorical"
      if (identical(inferred_type, "continuous") && "value_num" %in% names(df)) {
        v <- suppressWarnings(as.numeric(df$value_num))
        bad <- is.na(v) & !is.na(df$label) & nzchar(as.character(df$label))
        if (any(bad)) v[bad] <- suppressWarnings(as.numeric(df$label[bad]))
      } else {
        v <- as.character(df$label)
      }
      names(v) <- as.character(df$cell_id)
      out <- wb_prim_cell_vector(v, value_type = inferred_type)
      if (!is.null(payload_descriptor) && isTRUE(payload_descriptor$meta_present)) {
        out$meta <- durable_meta
      }
      out
    },

    # ---- cell_vector_family stored as artifact_pseudotime (cell_id, lineage_id, pseudotime) ----
    "cell_vector_family" = {
      payload_descriptor <- .wb_artifact_object_descriptor(
        art$provenance_json[[1L]], "cell_vector_family", artifact_id
      )
      df <- DBI::dbGetQuery(
        con,
        "SELECT cell_id, lineage_id, pseudotime
         FROM artifact_pseudotime
         WHERE artifact_id = ?
         ORDER BY lineage_id, cell_id;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_pseudotime for ", artifact_id))
      df <- .wb_artifact_restore_object_row_order(
        df, payload_descriptor, "cell_vector_family", artifact_id
      )
      durable_meta <- if (.wb_graph_object_has_attestation(con, artifact_id, "cell_vector_family")) {
        .wb_graph_object_restore(con, artifact_id, df, payload_descriptor, "cell_vector_family")
      } else {
        legacy_object_identity_required <- TRUE
        .wb_object_primitive_meta_from_descriptor(payload_descriptor)
      }

      wb_prim_cell_vector_family(
        key = df$lineage_id,
        cell_id = df$cell_id,
        value = df$pseudotime,
        value_type = if (is.null(payload_descriptor)) "continuous" else
          as.character(payload_descriptor$value_type %||% "continuous"),
        meta = if (is.null(payload_descriptor)) list() else
          durable_meta %||% list()
      )
    }
  )
  list(primitive=prim, legacy_identity_required=legacy_object_identity_required)
}

# R/artifacts_load.R
# Load a promoted artifact back into a wb_primitive (kind-safe),
# using the *existing* migrate schema (no payload_json column needed).

# ---- Main loader ----
#' Load a Promoted Artifact as a Primitive
#'
#' Reconstructs a typed primitive from the bundle-owned artifact registry and
#' payload tables. Consumers should use this function rather than reading
#' artifact payload tables directly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Promoted artifact identifier.
#' @param expected_kind Optional expected primitive kind. When supplied, loading
#'   fails if the stored artifact has another kind.
#'
#' @param allow_untrusted_deserialization Explicitly allow R deserialization of
#'   a contained model payload that is not provenance-bound. This never permits
#'   an external, traversing, or symlink-escaping path.
#' @return A `wb_primitive` reconstructed from the promoted payload.
#' @export
wb_art_load <- function(bundle, artifact_id, expected_kind = NULL,
                        allow_untrusted_deserialization = FALSE) {
  con <- bundle$con
  .wb_assert(!is.null(con), "wb_art_load(): bundle$con is NULL (no DB connection).")
  artifact_id <- as.character(artifact_id)
  .wb_assert(nzchar(artifact_id), "wb_art_load(): artifact_id must be a non-empty string.")

  art <- DBI::dbGetQuery(
    con,
    "SELECT artifact_id, type, name, source_op, input_space_id, input_matrix_id,
            cell_set, provenance_json
     FROM artifacts
     WHERE artifact_id = ?;",
    params = list(artifact_id)
  )
  if (nrow(art) != 1L) {
    # A session overlay is a point-in-time SQLite copy. Resolve only against
    # its explicitly recorded source bundle when a promoted artifact was
    # created after the overlay began; never search arbitrary paths.
    source_dir <- as.character(bundle$staging_source_dir %||% "")[1]
    if (nzchar(source_dir) && dir.exists(source_dir) &&
        !identical(normalizePath(source_dir, winslash = "/", mustWork = TRUE),
                   normalizePath(bundle$dir, winslash = "/", mustWork = TRUE))) {
      source_bundle <- wb_open_bundle(source_dir, validate = FALSE)
      on.exit(wb_close_bundle(source_bundle), add = TRUE)
      return(wb_art_load(source_bundle, artifact_id = artifact_id, expected_kind = expected_kind,
                         allow_untrusted_deserialization = allow_untrusted_deserialization))
    }
  }
  .wb_assert(nrow(art) == 1, paste0("wb_art_load(): artifact not found: ", artifact_id))

  type <- as.character(art$type[[1]])
  legacy_object_identity_required <- FALSE

  # Reconstruct primitive by type
  prim <- switch(
    type,

    "graph" = .wb_graph_load_reference(bundle, artifact_id),

    "cell_vector" =,
    "cell_vector_family" = {
      decoded <- .wb_artifact_cell_payload_decode(con,art,artifact_id,type)
      legacy_object_identity_required <- decoded$legacy_identity_required
      decoded$primitive
    },

    # ---- relation_family stored as artifact_relation_rows ----
    "relation_family" = {
      payload_descriptor <- .wb_artifact_object_descriptor(
        art$provenance_json[[1L]], "relation_family", artifact_id
      )
      df <- DBI::dbGetQuery(
        con,
        "SELECT relation_key, cell_id, weight, value, distance
         FROM artifact_relation_rows
         WHERE artifact_id = ?
         ORDER BY relation_key, cell_id;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_relation_rows for ", artifact_id))
      df <- .wb_artifact_restore_object_row_order(
        df, payload_descriptor, "relation_family", artifact_id
      )

      # Preserve optional columns semantically: all-NA columns become NULL.
      all_na <- function(x) all(is.na(x))
      present <- if (is.null(payload_descriptor)) {
        c(weight = !all_na(df$weight), value = !all_na(df$value), distance = !all_na(df$distance))
      } else {
        fields <- as.character(unlist(payload_descriptor$fields_present %||% list(), use.names = FALSE))
        stats::setNames(c("weight", "value", "distance") %in% fields,
                        c("weight", "value", "distance"))
      }
      wb_prim_relation_family(
        key = df$relation_key,
        cell_id = df$cell_id,
        weight = if (present[["weight"]]) df$weight else NULL,
        value = if (present[["value"]]) df$value else NULL,
        distance = if (present[["distance"]]) df$distance else NULL,
        meta = if (is.null(payload_descriptor)) list() else
          .wb_object_primitive_meta_from_descriptor(payload_descriptor) %||% list()
      )
    },

    # ---- path_2d_family stored as artifact_curves_2d (lineage_id, point, x, y) ----
    "path_2d_family" = {
      payload_descriptor <- .wb_artifact_object_descriptor(
        art$provenance_json[[1L]], "path_2d_family", artifact_id
      )
      df <- DBI::dbGetQuery(
        con,
        "SELECT lineage_id, point, x, y
         FROM artifact_curves_2d
         WHERE artifact_id = ?
         ORDER BY lineage_id, point;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_curves_2d for ", artifact_id))
      df <- .wb_artifact_restore_object_row_order(
        df, payload_descriptor, "path_2d_family", artifact_id
      )

      wb_prim_path_2d_family(
        key = df$lineage_id,
        point = df$point,
        x = df$x,
        y = df$y,
        meta = if (is.null(payload_descriptor)) list() else
          .wb_object_primitive_meta_from_descriptor(payload_descriptor) %||% list()
      )
    },

    # ---- space_path_family stored as artifact_space_path_rows/meta ----
    "space_path_family" = {
      payload_descriptor <- .wb_artifact_object_descriptor(
        art$provenance_json[[1L]], "space_path_family", artifact_id
      )
      df <- DBI::dbGetQuery(
        con,
        "SELECT space_id, path_id, point, dim, value
         FROM artifact_space_path_rows
         WHERE artifact_id = ?
         ORDER BY path_id, point, dim;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_space_path_rows for ", artifact_id))
      df <- .wb_artifact_restore_object_row_order(
        df, payload_descriptor, "space_path_family", artifact_id
      )

      meta_info <- DBI::dbGetQuery(
        con,
        "SELECT meta_json
         FROM artifact_space_path_meta
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      meta <- list()
      if (nrow(meta_info) == 1L) {
        mj <- as.character(meta_info$meta_json[[1]] %||% "")
        if (nzchar(mj) && !identical(mj, "null")) {
          meta <- tryCatch(jsonlite::fromJSON(mj, simplifyVector = FALSE), error = function(e) list())
        }
      }
      if (!is.null(payload_descriptor) && isTRUE(payload_descriptor$meta_present)) {
        durable_meta <- .wb_object_primitive_meta_from_descriptor(payload_descriptor)
        durable_json <- jsonlite::toJSON(.wb_json_sanitize(durable_meta), auto_unbox = TRUE, null = "null")
        stored_json <- jsonlite::toJSON(.wb_json_sanitize(meta), auto_unbox = TRUE, null = "null")
        .wb_assert(
          identical(as.character(durable_json), as.character(stored_json)),
          paste0("wb_art_load(): durable space_path_family metadata does not match payload metadata for ", artifact_id)
        )
        meta <- durable_meta
      }

      wb_prim_space_path_family(
        space_id = df$space_id,
        path_id = df$path_id,
        point = df$point,
        dim = df$dim,
        value = df$value,
        meta = meta
      )
    },

    # ---- space_2d: durable reference to the canonical file-backed payload ----
    "space_2d" = {
      space_id <- as.character(art$input_space_id[[1]])
      .wb_assert(nzchar(space_id), "wb_art_load(): space_2d artifact missing input_space_id.")

      p <- wb_prim_space_2d(space_id)
      p$df <- .wb_space_2d_safe(bundle, space_id)
      p
    },

    # ---- umap_model / model_ref stored as artifact_umap_model ----
    "umap_model" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT space_id, model_path
         FROM artifact_umap_model
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) == 1, paste0("wb_art_load(): no row in artifact_umap_model for ", artifact_id))
      p <- wb_prim_model_ref(
        model_space_id = as.character(df$space_id[[1]]),
        in_space_id = if (is.null(art$input_space_id[[1]])) "" else as.character(art$input_space_id[[1]]),
        engine = "uwot",
        artifact_id = artifact_id
      )
      p$model_path <- as.character(df$model_path[[1]])
      p
    },

    # ---- generic model_ref artifacts (engine-tagged, e.g. slingshot/uwot) ----
    "model_ref" = {
      optional_model_column <- function(column) if (
          .wb_db_has_column(con, "artifact_model_ref", column)) column else
            paste0("NULL AS ", column)
      df <- DBI::dbGetQuery(
        con,
        paste0("SELECT engine, model_space_id, in_space_id, model_type, ",
          "model_path, ", optional_model_column("linkage_json"), ", ",
          optional_model_column("model_primary_path"), ", ",
          optional_model_column("model_tree_manifest_json"), ", ",
          optional_model_column("payload_manifest_identity_json"), " ",
          "FROM artifact_model_ref WHERE artifact_id = ?;"),
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) == 1, paste0("wb_art_load(): no row in artifact_model_ref for ", artifact_id))

      engine <- as.character(df$engine[[1]] %||% "uwot")
      stored_model_path <- as.character(df$model_path[[1]] %||% "")
      model_path <- tryCatch(
        .wb_resolve_model_ref_path(bundle, stored_model_path),
        error = function(e) {
          stop(
            paste0(
              "wb_art_load(): model file missing for engine='", engine, "': ",
              stored_model_path, ". ", conditionMessage(e)
            ),
            call. = FALSE
          )
        }
      )
      p <- wb_prim_model_ref(
        model_space_id = as.character(df$model_space_id[[1]]),
        in_space_id = as.character(df$in_space_id[[1]] %||% ""),
        engine = engine,
        artifact_id = artifact_id
      )
      p$model_type <- as.character(df$model_type[[1]] %||% engine)
      p$model_path <- model_path
      verified_primary_path <- NULL
      verified_primary_entry <- NULL
      linkage_json <- as.character(df$linkage_json[[1]] %||% "")[1]
      if (!is.na(linkage_json) && nzchar(linkage_json)) {
        linkage <- jsonlite::fromJSON(linkage_json, simplifyVector = FALSE)
        if (all(c("source_space_id", "fitted_cell_order_identity") %in%
            names(linkage)) && (all(c("source_space_content_identity",
              "source_snapshot_id") %in% names(linkage)) || identical(
                as.character(linkage$schema %||% "")[1],
                "scworkbench.operation_pack.model_source_linkage.v3")))
          p$model_source_linkage <- linkage else
          p$model_linkage <- linkage
      }
      tree_json <- as.character(df$model_tree_manifest_json[[1]] %||% "")[1]
      if (!is.na(tree_json) && nzchar(tree_json)) {
        tree <- tryCatch(jsonlite::fromJSON(tree_json,
          simplifyVector = FALSE), error = function(e) NULL)
        .wb_operation_pack_v3_assert_model_tree_manifest(tree, engine,
          p$model_type, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
          phase = "resolution")
        primary <- as.character(df$model_primary_path[[1]] %||% "")[1]
        .wb_assert(identical(primary, tree$primary_path),
          "wb_art_load(): durable model primary path differs from its tree manifest.")
        observed <- .wb_operation_pack_v3_model_tree_manifest(model_path,
          engine, p$model_type, primary,
          code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution")
        payload <- .wb_operation_pack_v3_model_payload_identity(observed)
        payload_json <- as.character(
          df$payload_manifest_identity_json[[1]] %||% "")[1]
        declared_payload <- if (!is.na(payload_json) && nzchar(payload_json))
          jsonlite::fromJSON(payload_json, simplifyVector = FALSE) else NULL
        .wb_assert(identical(observed, tree) &&
            !is.null(declared_payload) && identical(payload, declared_payload),
          "wb_art_load(): durable contained model tree failed authenticated reconstruction.")
        p$model_tree_root <- model_path
        p$model_primary_path <- primary
        p$model_tree_manifest <- tree
        p$model_payload_manifest_identity <- payload
        verified_primary_path <- file.path(model_path, primary)
        verified_primary_entry <- tree$entries[[match(primary, vapply(
          tree$entries, `[[`, character(1), "path"))]]
      }
      lifecycle <- if (.wb_table_exists(con, "entity_lifecycle")) {
        wb_entity_lifecycle(bundle, "artifact", artifact_id)
      } else data.frame()
      provenance_bound <- nrow(lifecycle) && identical(as.integer(lifecycle$provenance_bound[1] %||% 0L), 1L)
      trust <- .wb_model_deserialization_status(bundle, stored_model_path,
                                                provenance_bound = provenance_bound)
      p$deserialization_trust <- trust$trust

      # Load in-memory object for engines with project/continue ops that require the model object.
      if (engine %in% c("slingshot", "monocle3")) {
        .wb_assert(
          isTRUE(trust$deserialization_allowed) || isTRUE(allow_untrusted_deserialization),
          "MODEL_DESERIALIZATION_TRUST_REQUIRED: loading serialized model state requires trusted provenance/runtime or allow_untrusted_deserialization=TRUE."
        )
        if (is.null(verified_primary_path)) {
          .wb_assert(!dir.exists(model_path),
            "wb_art_load(): legacy model payload is a directory without an authenticated primary file.")
          p$model_obj <- readRDS(model_path)
        } else {
          status <- .wb_path_status(model_path, p$model_primary_path,
            expected_type = "file", must_exist = TRUE,
            purpose = "authenticated contained model primary file")
          .wb_assert(isTRUE(status$ok) &&
              !nzchar(Sys.readlink(verified_primary_path)),
            "wb_art_load(): authenticated model primary file is missing, linked, or escaped.")
          bytes <- readBin(verified_primary_path, "raw",
            n = as.integer(verified_primary_entry$size))
          .wb_assert(identical(as.integer(length(bytes)),
              as.integer(verified_primary_entry$size)) &&
              identical(digest::digest(bytes, algo = "sha256",
                serialize = FALSE), verified_primary_entry$sha256),
            "wb_art_load(): authenticated model primary file changed before deserialization.")
          # readRDS() auto-decompresses a file connection, but not a raw
          # connection. Keep deserialization bound to the verified byte copy.
          if (length(bytes) >= 2L && !identical(bytes[1:2],
              charToRaw("X\n")) && !identical(bytes[1:2],
              charToRaw("A\n")) && !identical(bytes[1:2],
              charToRaw("B\n")))
            bytes <- memDecompress(bytes, type = "unknown")
          stream <- rawConnection(bytes)
          p$model_obj <- tryCatch(readRDS(stream),
            finally = close(stream))
        }
      }
      p
    },

    "feature_table" = {
      info <- DBI::dbGetQuery(
        con,
        "SELECT table_type, entity_kind, meta_json
         FROM artifact_tables
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(info) == 1, paste0("wb_art_load(): no row in artifact_tables for ", artifact_id))

      rows <- DBI::dbGetQuery(
        con,
        "SELECT row_json
         FROM artifact_table_rows
         WHERE artifact_id = ?
         ORDER BY row_idx ASC;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(rows) >= 0, paste0("wb_art_load(): failed reading table rows for ", artifact_id))

      meta <- if (!is.null(info$meta_json[[1]]) && nzchar(as.character(info$meta_json[[1]]))) {
        jsonlite::fromJSON(as.character(info$meta_json[[1]]), simplifyVector = TRUE)
      } else {
        list()
      }

      decoded <- .wb_table_decode_meta(meta, .wb_table_artifact_is_typed(con, artifact_id))
      tbl <- if (is.null(decoded$storage)) .wb_art_table_rows_to_df(rows) else
        .wb_art_table_rows_to_df(rows, decoded$storage)
      meta <- decoded$meta
      prim <- wb_prim_feature_table(
        table = tbl,
        table_type = as.character(info$table_type[[1]] %||% "generic"),
        meta = meta
      )
      if (is.null(decoded$storage)) prim$table_storage <- NULL else
        prim$table_storage$columns <- decoded$storage
      prim
    },

    "obs_table" = {
      info <- DBI::dbGetQuery(
        con,
        "SELECT table_type, entity_kind, meta_json
         FROM artifact_tables
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(info) == 1, paste0("wb_art_load(): no row in artifact_tables for ", artifact_id))

      rows <- DBI::dbGetQuery(
        con,
        "SELECT row_json
         FROM artifact_table_rows
         WHERE artifact_id = ?
         ORDER BY row_idx ASC;",
        params = list(artifact_id)
      )
      meta <- if (!is.null(info$meta_json[[1]]) && nzchar(as.character(info$meta_json[[1]]))) {
        jsonlite::fromJSON(as.character(info$meta_json[[1]]), simplifyVector = TRUE)
      } else {
        list()
      }

      decoded <- .wb_table_decode_meta(meta, .wb_table_artifact_is_typed(con, artifact_id))
      tbl <- if (is.null(decoded$storage)) .wb_art_table_rows_to_df(rows) else
        .wb_art_table_rows_to_df(rows, decoded$storage)
      meta <- decoded$meta
      prim <- wb_prim_obs_table(
        table = tbl,
        table_type = as.character(info$table_type[[1]] %||% "generic"),
        entity_kind = as.character(info$entity_kind[[1]] %||% "generic"),
        meta = meta
      )
      if (is.null(decoded$storage)) prim$table_storage <- NULL else
        prim$table_storage$columns <- decoded$storage
      prim
    },

    stop("wb_art_load(): Unsupported artifact type: ", type, call. = FALSE)
  )

  if (legacy_object_identity_required)
    .wb_graph_legacy_object_identity_assert(con, artifact_id, prim)
  prim <- .wb_trajectory_hydrate_primitive_meta(bundle, artifact_id, prim)

  if (identical(type, "relation_family") &&
      !is.null(payload_descriptor$content_identity)) {
    observed <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.relation_family.content.v1", unclass(prim))
    .wb_assert(identical(observed, payload_descriptor$content_identity),
      paste0("wb_art_load(): durable relation content differs from its ",
        "payload descriptor for ", artifact_id))
  }

  # Kind-safety
  if (!is.null(expected_kind)) {
    .wb_assert_kind(prim, expected_kind, where = paste0(" (artifact_id=", artifact_id, ")"))
  }

  prim
}

# This getter is used only inside the authenticated transition audit callback;
# its returned primitive carries no retained-source authority. Public loading
# still requires the producer certificate before hydration.
.wb_artifact_authenticated_cell_output <- function(bundle,artifact_id,expected_kind,run_id,observed) {
  art <- DBI::dbGetQuery(bundle$con,
    "SELECT type,provenance_json FROM artifacts WHERE artifact_id=?;",
    params=list(artifact_id))
  .wb_assert(nrow(art)==1L && identical(as.character(art$type[[1L]]),expected_kind),
    "PYBENCH_RECEIPT_MISMATCH: private cell output registry differs from its grant")
  provenance <- .wb_art_parse_provenance_json(art$provenance_json[[1L]])
  .wb_assert(isTRUE(provenance$pybench_pending) &&
    identical(as.character(provenance$run_id),as.character(run_id)),
    "PYBENCH_RECEIPT_MISMATCH: private cell output is not owned by the allocated pending run")
  table <- if(expected_kind=="cell_vector") "artifact_labels" else "artifact_pseudotime"
  descriptors <- Filter(function(x) identical(as.character(x$mutation_class),"sqlite_rows") &&
    identical(as.character(x$table),table) &&
    identical(as.character(x$output_id),as.character(artifact_id)) &&
    identical(as.character(x$output_kind),expected_kind),observed)
  .wb_assert(length(descriptors)==1L,
    "PYBENCH_RECEIPT_MISMATCH: private cell output lacks one audited payload closure")
  descriptor <- descriptors[[1L]]
  .wb_assert(identical(as.character(descriptor$key_scope$column),"artifact_id") &&
    identical(as.character(descriptor$key_scope$values),as.character(artifact_id)),
    "PYBENCH_RECEIPT_MISMATCH: private output scope differs from its allocation")
  verify <- function() {
    actual <- .wb_pybench_table_snapshot(bundle$con,table,descriptor$key_scope)
    .wb_assert(identical(as.integer(actual$row_count),as.integer(descriptor$row_count)) &&
      identical(.wb_pybench_rows_sha256(actual$canonical_rows),as.character(descriptor$content_sha256)),
      "PYBENCH_RECEIPT_MISMATCH: private output bytes differ from the authoritative receipt audit")
    invisible(TRUE)
  }
  verify()
  decoded <- .wb_artifact_cell_payload_decode(bundle$con,art,artifact_id,expected_kind)
  verify()
  # ABI1 writers produce the existing ordinary row carrier, not current graph
  # attestation. Partial or unexpected current proof cannot select a fallback.
  .wb_assert(isTRUE(decoded$legacy_identity_required),
    "PYBENCH_RECEIPT_MISMATCH: private cell output is not the issued ordinary carrier")
  .wb_assert_kind(decoded$primitive,expected_kind)
  .wb_trajectory_hydrate_primitive_meta(bundle,artifact_id,decoded$primitive)
}
