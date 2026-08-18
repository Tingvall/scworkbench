# Durable entity lifecycle and immutable-history support.

.wb_entity_lifecycle_schema <- function() "scworkbench.entity_lifecycle.v1"

.wb_entity_kinds <- function() {
  c("matrix", "space", "model", "model_ref", "artifact", "cell_set", "feature_set", "metadata_field", "external_source", "in_memory_source", "registry")
}

.wb_entity_normalize <- function(entity_kind, entity_id) {
  kind <- as.character(entity_kind %||% "")[1]
  id <- as.character(entity_id %||% "")[1]
  .wb_assert(!is.na(kind) && kind %in% .wb_entity_kinds(), paste0(
    "entity_kind must be one of: ", paste(.wb_entity_kinds(), collapse = ", ")
  ))
  .wb_assert(!is.na(id) && nzchar(id), "entity_id must be a non-empty string")
  if (identical(kind, "cell_set") && !identical(id, "core") && !startsWith(id, "set:")) id <- paste0("set:", id)
  list(kind = kind, id = id)
}

.wb_feature_set_entity_id <- function(feature_set, matrix_id) {
  paste0(as.character(matrix_id)[1], "::", as.character(feature_set)[1])
}

.wb_model_ref_identity_parse <- function(entity_id) {
  id <- as.character(entity_id %||% "")[1]
  # Appending a sentinel preserves the intentional empty input-space field in
  # identities such as "uwot|output|"; base strsplit drops trailing empties.
  bits <- strsplit(paste0(id, "#"), "|", fixed = TRUE)[[1L]]
  bits[[length(bits)]] <- sub("#$", "", bits[[length(bits)]])
  if (length(bits) != 3L || any(is.na(bits)) || !nzchar(bits[[1L]]) || !nzchar(bits[[2L]])) {
    return(list(ok = FALSE, id = id, engine = NA_character_, model_space_id = NA_character_,
                in_space_id = NA_character_))
  }
  in_space_id <- bits[[3L]]
  # Older/pre-registered model primitives could serialize an unavailable
  # optional input space through paste() as the literal sentinel "NA" while
  # artifact_model_ref correctly stored SQL NULL. Treat only that exact legacy
  # sentinel as an absent optional identity field.
  if (identical(in_space_id, "NA")) in_space_id <- ""
  list(ok = TRUE, id = id, engine = bits[[1L]], model_space_id = bits[[2L]],
       in_space_id = in_space_id)
}

# Canonical storage-aware resolver for a lifecycle model_ref identity.  It is
# deliberately read-only: validation and lifecycle migration use exactly the
# same registry/path/provenance rules, while only their callers decide whether
# to report a diagnostic or transition legacy lifecycle state.
.wb_model_ref_physical_presence <- function(bundle, entity_id, allow_pending = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  identity <- .wb_model_ref_identity_parse(entity_id)
  fail <- function(code, message, storage = "unresolved", artifact_id = NA_character_,
                   model_path = NA_character_, materialization_path = NA_character_) {
    list(present = FALSE, code = code, message = message, storage = storage,
         identity = identity, artifact_id = artifact_id, model_path = model_path,
         materialization_path = materialization_path, absolute_model_path = NA_character_)
  }
  if (!isTRUE(identity$ok)) {
    return(fail("MODEL_REF_IDENTITY_MALFORMED",
                "model_ref lifecycle identity must be engine|model_space_id|in_space_id"))
  }

  value <- function(x) {
    out <- as.character(x %||% "")[1L]
    if (is.na(out)) "" else out
  }

  check_path <- function(path, purpose) {
    .wb_path_status(bundle$dir, value(path), expected_type = "either",
                    must_exist = TRUE, purpose = purpose)
  }

  # A reference is space-model-backed when one row matches its destination,
  # engine/model type, and (when declared) input space. This includes uwot and
  # legacy/custom fitted space-model engines; other engines continue to the
  # artifact-backed resolver below.
  space_rows <- if (.wb_table_exists(con, "space_models")) DBI::dbGetQuery(
    con, "SELECT * FROM space_models WHERE space_id = ?;",
    params = list(identity$model_space_id)
  ) else data.frame()
  if (nrow(space_rows)) {
    model_types <- as.character(space_rows$model_type)
    compatible <- model_types == identity$engine |
      startsWith(model_types, paste0(identity$engine, "_"))
    if (nzchar(identity$in_space_id)) {
      compatible <- compatible & as.character(space_rows$source_space_id) == identity$in_space_id
    }
    matched_space <- space_rows[compatible, , drop = FALSE]
    if (nrow(matched_space)) {
      status <- check_path(matched_space$model_path[[1L]], "space-model lifecycle payload")
      if (!isTRUE(status$ok)) {
        return(fail("MODEL_REF_SPACE_MODEL_PAYLOAD_INVALID",
                    paste0(status$code, ": space-model payload is missing or not contained"),
                    storage = "space_models", model_path = matched_space$model_path[[1L]]))
      }
      return(list(present = TRUE, code = "OK", message = "space_models payload present",
                  storage = "space_models", identity = identity, artifact_id = NA_character_,
                  model_path = as.character(matched_space$model_path[[1L]]),
                  materialization_path = NA_character_,
                  absolute_model_path = as.character(status$absolute)))
    }
    if (identical(identity$engine, "uwot")) {
      return(fail("MODEL_REF_SPACE_MODEL_IDENTITY_MISMATCH",
                  "space_models row does not match the model engine/input-space identity",
                  storage = "space_models"))
    }
  } else if (identical(identity$engine, "uwot")) {
    return(fail("MODEL_REF_SPACE_MODEL_MISSING",
                "uwot model_ref has no matching space_models row", storage = "space_models"))
  }

  required <- c("artifact_model_ref", "artifacts", "prov_run_entity_bindings",
                "prov_run_outputs", "prov_materializations", "prov_commits")
  missing_tables <- required[!vapply(required, function(table) .wb_table_exists(con, table), logical(1))]
  if (length(missing_tables)) {
    return(fail("MODEL_REF_ARTIFACT_REGISTRY_MISSING",
                paste0("artifact-backed model_ref requires tables: ", paste(missing_tables, collapse = ", ")),
                storage = "artifact_model_ref"))
  }

  candidates <- DBI::dbGetQuery(con, "
    SELECT amr.*, a.type AS owner_type
    FROM artifact_model_ref amr
    LEFT JOIN artifacts a ON a.artifact_id = amr.artifact_id
    WHERE amr.engine = ? AND amr.model_space_id = ?
      AND COALESCE(amr.in_space_id, '') = ?
    ORDER BY amr.artifact_id;
  ", params = list(identity$engine, identity$model_space_id, identity$in_space_id))
  if (!nrow(candidates)) {
    bound_owners <- DBI::dbGetQuery(con, "
      SELECT DISTINCT o.artifact_id
      FROM prov_run_entity_bindings b
      JOIN prov_run_outputs o
        ON o.snapshot_id=b.snapshot_id AND o.run_id=b.run_id
       AND o.output_name=b.binding_name
      JOIN artifacts a ON a.artifact_id=o.artifact_id AND a.type='model_ref'
      LEFT JOIN artifact_model_ref amr ON amr.artifact_id=o.artifact_id
      WHERE b.entity_kind='model_ref' AND b.entity_id=? AND b.direction='output'
        AND amr.artifact_id IS NULL;
    ", params = list(identity$id))
    if (nrow(bound_owners)) {
      return(fail("MODEL_REF_ARTIFACT_PAYLOAD_MISSING",
                  "owning model_ref artifact has no artifact_model_ref payload row",
                  storage = "artifact_model_ref",
                  artifact_id = as.character(bound_owners$artifact_id[[1L]])))
    }
    return(fail("MODEL_REF_ARTIFACT_IDENTITY_MISMATCH",
                "no artifact_model_ref row matches engine, model space, and input space",
                storage = "artifact_model_ref"))
  }

  failures <- list()
  for (i in seq_len(nrow(candidates))) {
    artifact_id <- as.character(candidates$artifact_id[[i]])
    model_path <- as.character(candidates$model_path[[i]])
    if (!identical(value(candidates$owner_type[[i]]), "model_ref")) {
      failures[[length(failures) + 1L]] <- fail(
        "MODEL_REF_ARTIFACT_OWNER_INVALID",
        "artifact_model_ref row lacks an owning artifacts row of type model_ref",
        storage = "artifact_model_ref", artifact_id = artifact_id, model_path = model_path
      )
      next
    }
    model_status <- check_path(model_path, "artifact-backed model lifecycle payload")
    if (!isTRUE(model_status$ok)) {
      failures[[length(failures) + 1L]] <- fail(
        "MODEL_REF_ARTIFACT_PAYLOAD_INVALID",
        paste0(model_status$code, ": artifact-backed model payload is missing or not contained"),
        storage = "artifact_model_ref", artifact_id = artifact_id, model_path = model_path
      )
      next
    }

    links <- DBI::dbGetQuery(con, "
      SELECT b.snapshot_id, b.commit_id, b.run_id, b.binding_name, b.path,
             b.content_hash AS binding_hash, b.content_identity_scheme AS binding_scheme,
             o.artifact_id, o.primitive_kind, o.materialization_path,
             o.content_sha256 AS output_hash, o.content_identity_scheme AS output_scheme,
             pm.path AS persisted_materialization_path,
             pm.primitive_kind AS persisted_primitive_kind,
             c.state AS commit_state
      FROM prov_run_entity_bindings b
      JOIN prov_run_outputs o
        ON o.snapshot_id = b.snapshot_id AND o.run_id = b.run_id
       AND o.output_name = b.binding_name
      LEFT JOIN prov_materializations pm
        ON pm.commit_id = b.commit_id AND pm.run_id = b.run_id
       AND pm.output_name = b.binding_name
      LEFT JOIN prov_commits c ON c.commit_id = b.commit_id
      WHERE b.entity_kind = 'model_ref' AND b.entity_id = ?
        AND b.direction = 'output' AND b.relationship_type = 'MATERIALIZES'
        AND o.artifact_id = ?
      ORDER BY b.snapshot_id, b.run_id;
    ", params = list(identity$id, artifact_id))
    if (!nrow(links)) {
      failures[[length(failures) + 1L]] <- fail(
        "MODEL_REF_PROVENANCE_BINDING_MISSING",
        "artifact-backed model has no matching output binding and artifact materialization",
        storage = "artifact_model_ref", artifact_id = artifact_id, model_path = model_path
      )
      next
    }

    for (j in seq_len(nrow(links))) {
      if (isTRUE(allow_pending) && identical(as.character(links$commit_state[[j]]), "pending")) {
        return(list(present = TRUE, code = "PENDING", message = "pending model publication",
                    storage = "pending", identity = identity, artifact_id = artifact_id,
                    model_path = model_path, materialization_path = value(links$path[[j]]),
                    absolute_model_path = as.character(model_status$absolute)))
      }
      materialization_path <- value(links$persisted_materialization_path[[j]])
      paths_agree <- nzchar(materialization_path) &&
        identical(materialization_path, value(links$path[[j]])) &&
        identical(materialization_path, value(links$materialization_path[[j]]))
      kinds_agree <- identical(as.character(links$primitive_kind[[j]]), "model_ref") &&
        identical(value(links$persisted_primitive_kind[[j]]), "model_ref")
      hashes_agree <- {
        bh <- value(links$binding_hash[[j]])
        oh <- value(links$output_hash[[j]])
        !nzchar(bh) || !nzchar(oh) || identical(tolower(bh), tolower(oh))
      }
      lifecycle_agrees <- TRUE
      if (.wb_table_exists(con, "entity_lifecycle")) {
        life <- DBI::dbGetQuery(
          con, "SELECT identity_hash FROM entity_lifecycle WHERE entity_kind='model_ref' AND entity_id=?;",
          params = list(identity$id)
        )
        if (nrow(life)) {
          lh <- value(life$identity_hash[[1L]])
          bh <- value(links$binding_hash[[j]])
          lifecycle_agrees <- !nzchar(lh) || !nzchar(bh) || identical(tolower(lh), tolower(bh))
        }
      }
      materialization_status <- if (nzchar(materialization_path)) {
        check_path(materialization_path, "model_ref provenance materialization")
      } else list(ok = FALSE)
      if (identical(as.character(links$commit_state[[j]]), "complete") && paths_agree &&
          kinds_agree && hashes_agree && lifecycle_agrees && isTRUE(materialization_status$ok)) {
        return(list(present = TRUE, code = "OK", message = "artifact-backed model payload present",
                    storage = "artifact_model_ref", identity = identity,
                    artifact_id = artifact_id, model_path = model_path,
                    materialization_path = materialization_path,
                    absolute_model_path = as.character(model_status$absolute)))
      }
    }
    failures[[length(failures) + 1L]] <- fail(
      "MODEL_REF_PROVENANCE_MATERIALIZATION_INVALID",
      "model_ref binding, committed output, and provenance materialization are inconsistent",
      storage = "artifact_model_ref", artifact_id = artifact_id, model_path = model_path,
      materialization_path = value(links$persisted_materialization_path[[1L]])
    )
  }
  failures[[1L]]
}

.wb_entity_lifecycle_tables <- function(con) {
  if (.wb_schema_component_is_current(
    con, c("entity_lifecycle", "entity_supersessions", "entity_tombstones"),
    list(entity_lifecycle = "identity_scheme", entity_tombstones = "identity_scheme")
  )) return(invisible(TRUE))
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS entity_lifecycle (
      entity_kind TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      lifecycle_state TEXT NOT NULL,
      identity_hash TEXT,
      identity_scheme TEXT,
      provenance_bound INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      reason TEXT,
      actor TEXT,
      PRIMARY KEY(entity_kind, entity_id),
      CHECK(lifecycle_state IN ('current','superseded','rejected','retracted','ephemeral'))
    );
  ")
  if (!.wb_db_has_column(con, "entity_lifecycle", "identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE entity_lifecycle ADD COLUMN identity_scheme TEXT;")
  }
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_entity_lifecycle_state ON entity_lifecycle(lifecycle_state, entity_kind);")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS entity_supersessions (
      successor_kind TEXT NOT NULL,
      successor_id TEXT NOT NULL,
      predecessor_kind TEXT NOT NULL,
      predecessor_id TEXT NOT NULL,
      relationship_type TEXT NOT NULL DEFAULT 'SUPERSEDES',
      created_at TEXT NOT NULL,
      created_by TEXT,
      reason TEXT,
      PRIMARY KEY(successor_kind, successor_id, predecessor_kind, predecessor_id),
      CHECK(relationship_type = 'SUPERSEDES')
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS entity_tombstones (
      entity_kind TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      tombstone_state TEXT NOT NULL,
      retracted_at TEXT NOT NULL,
      retracted_by TEXT,
      reason TEXT NOT NULL,
      identity_hash TEXT,
      identity_scheme TEXT,
      PRIMARY KEY(entity_kind, entity_id),
      CHECK(tombstone_state IN ('retracted','rejected'))
    );
  ")
  if (!.wb_db_has_column(con, "entity_tombstones", "identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE entity_tombstones ADD COLUMN identity_scheme TEXT;")
  }
  invisible(TRUE)
}

.wb_entity_lifecycle_upsert <- function(con, kind, id, state = "current",
                                        identity_hash = NA_character_, identity_scheme = NA_character_, bound = FALSE,
                                        reason = NA_character_, actor = NA_character_) {
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  DBI::dbExecute(con, "
    INSERT INTO entity_lifecycle(entity_kind, entity_id, lifecycle_state, identity_hash, identity_scheme,
      provenance_bound, created_at, updated_at, reason, actor)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(entity_kind, entity_id) DO UPDATE SET
      identity_hash = COALESCE(entity_lifecycle.identity_hash, excluded.identity_hash),
      identity_scheme = COALESCE(entity_lifecycle.identity_scheme, excluded.identity_scheme),
      provenance_bound = MAX(entity_lifecycle.provenance_bound, excluded.provenance_bound),
      updated_at = CASE WHEN excluded.provenance_bound > entity_lifecycle.provenance_bound
                        THEN excluded.updated_at ELSE entity_lifecycle.updated_at END;
  ", params = list(kind, id, state, identity_hash, identity_scheme, as.integer(isTRUE(bound)), now, now, reason, actor))
  invisible(TRUE)
}

.wb_entity_binding_targets <- function(entity_kind, entity_id, con = NULL) {
  z <- .wb_entity_normalize(entity_kind, entity_id)
  out <- list(z)
  if (identical(z$kind, "model_ref")) {
    identity <- .wb_model_ref_identity_parse(z$id)
    registered <- if (!is.null(con) && .wb_table_exists(con, "space_models") && isTRUE(identity$ok)) {
      DBI::dbGetQuery(
        con, "SELECT model_type, source_space_id FROM space_models WHERE space_id = ?;",
        params = list(identity$model_space_id)
      )
    } else data.frame()
    has_registered_model <- nrow(registered) == 1L &&
      (identical(as.character(registered$model_type[[1L]]), identity$engine) ||
       startsWith(as.character(registered$model_type[[1L]]), paste0(identity$engine, "_"))) &&
      (!nzchar(identity$in_space_id) ||
       identical(as.character(registered$source_space_id[[1L]]), identity$in_space_id))
    if (isTRUE(has_registered_model)) {
      out[[length(out) + 1L]] <- list(kind = "model", id = identity$model_space_id)
    }
  }
  out
}

.wb_entity_nonmissing_hash <- function(identity_hash) {
  value <- as.character(identity_hash %||% NA_character_)[1]
  if (is.na(value) || !nzchar(value)) NA_character_ else value
}

.wb_entity_bind_one <- function(con, kind, id, identity_hash = NA_character_,
                                identity_scheme = NA_character_,
                                actor = NA_character_) {
  .wb_entity_lifecycle_tables(con)
  hash <- .wb_entity_nonmissing_hash(identity_hash)
  row <- DBI::dbGetQuery(
    con,
    "SELECT * FROM entity_lifecycle WHERE entity_kind = ? AND entity_id = ?;",
    params = list(kind, id)
  )
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  if (!nrow(row)) {
    DBI::dbExecute(
      con,
      "INSERT INTO entity_lifecycle(entity_kind, entity_id, lifecycle_state, identity_hash, identity_scheme, provenance_bound, created_at, updated_at, reason, actor) VALUES(?, ?, 'current', ?, ?, 1, ?, ?, NULL, ?);",
      params = list(kind, id, hash, identity_scheme, now, now, actor)
    )
    return(invisible(TRUE))
  }

  state <- as.character(row$lifecycle_state[1])
  if (state %in% c("superseded", "rejected", "retracted")) {
    stop(
      "Cannot bind historical ", kind, " '", id, "' in state '", state,
      "'. Historical identifiers cannot be revived; create and promote a new identity.",
      call. = FALSE
    )
  }
  old_hash <- .wb_entity_nonmissing_hash(row$identity_hash[1])
  if (!is.na(old_hash) && !is.na(hash) && !identical(old_hash, hash)) {
    stop(
      "Conflicting immutable identity hash for ", kind, " '", id,
      "': existing=", old_hash, ", binding=", hash, ".",
      call. = FALSE
    )
  }
  old_scheme <- as.character(row$identity_scheme[1] %||% NA_character_)[1]
  new_scheme <- as.character(identity_scheme %||% NA_character_)[1]
  if (!is.na(old_scheme) && nzchar(old_scheme) && !is.na(new_scheme) && nzchar(new_scheme) && !identical(old_scheme, new_scheme)) {
    stop("Conflicting immutable identity schemes for ", kind, " '", id, "': existing=", old_scheme, ", binding=", new_scheme, ".", call. = FALSE)
  }
  DBI::dbExecute(
    con,
    "UPDATE entity_lifecycle SET lifecycle_state = 'current', identity_hash = COALESCE(identity_hash, ?), identity_scheme = COALESCE(identity_scheme, ?), provenance_bound = 1, updated_at = ?, reason = CASE WHEN lifecycle_state = 'ephemeral' THEN 'Selected ephemeral identity promoted to a durable current claim.' ELSE reason END, actor = COALESCE(?, actor) WHERE entity_kind = ? AND entity_id = ?;",
    params = list(hash, identity_scheme, now, actor, kind, id)
  )
  invisible(TRUE)
}

# The canonical provenance-binding transition. Callers must invoke this inside
# the transaction that persists the corresponding provenance binding.
.wb_entity_bind_provenance <- function(con, entity_kind, entity_id,
                                       identity_hash = NA_character_,
                                       identity_scheme = NA_character_,
                                       actor = NA_character_) {
  targets <- .wb_entity_binding_targets(entity_kind, entity_id, con = con)
  for (target in targets) {
    .wb_entity_bind_one(
      con, target$kind, target$id,
      identity_hash = identity_hash, identity_scheme = identity_scheme, actor = actor
    )
  }
  invisible(TRUE)
}

.wb_entity_backfill_binding <- function(con, entity_kind, entity_id,
                                        identity_hash = NA_character_,
                                        identity_scheme = NA_character_) {
  hash <- .wb_entity_nonmissing_hash(identity_hash)
  targets <- .wb_entity_binding_targets(entity_kind, entity_id, con = con)
  for (target in targets) {
    row <- DBI::dbGetQuery(
      con,
      "SELECT identity_hash, identity_scheme FROM entity_lifecycle WHERE entity_kind = ? AND entity_id = ?;",
      params = list(target$kind, target$id)
    )
    if (!nrow(row)) {
      .wb_entity_lifecycle_upsert(
        con, target$kind, target$id, state = "current",
        identity_hash = hash, identity_scheme = identity_scheme, bound = TRUE
      )
      next
    }
    old_hash <- .wb_entity_nonmissing_hash(row$identity_hash[1])
    if (!is.na(old_hash) && !is.na(hash) && !identical(old_hash, hash)) {
      stop(
        "Conflicting immutable identity hashes in persisted provenance for ",
        target$kind, " '", target$id, "'.",
        call. = FALSE
      )
    }
    old_scheme <- as.character(row$identity_scheme[1] %||% NA_character_)[1]
    new_scheme <- as.character(identity_scheme %||% NA_character_)[1]
    if (!is.na(old_scheme) && nzchar(old_scheme) && !is.na(new_scheme) && nzchar(new_scheme) && !identical(old_scheme, new_scheme)) {
      stop(
        "Conflicting immutable identity schemes in persisted provenance for ",
        target$kind, " '", target$id, "'.",
        call. = FALSE
      )
    }
    DBI::dbExecute(
      con,
      "UPDATE entity_lifecycle SET identity_hash = COALESCE(identity_hash, ?), identity_scheme = COALESCE(identity_scheme, ?), provenance_bound = 1 WHERE entity_kind = ? AND entity_id = ?;",
      params = list(hash, identity_scheme, target$kind, target$id)
    )
  }
  invisible(TRUE)
}

.wb_entity_registry_bindings <- function(con) {
  out <- data.frame(entity_kind = character(), entity_id = character(), stringsAsFactors = FALSE)
  if (!.wb_table_exists(con, "prov_registry_mutations")) return(out)
  x <- DBI::dbGetQuery(con, "SELECT registry_type, registry_key_json FROM prov_registry_mutations;")
  if (!nrow(x)) return(out)
  rows <- lapply(seq_len(nrow(x)), function(i) {
    key <- tryCatch(jsonlite::fromJSON(as.character(x$registry_key_json[i]), simplifyVector = TRUE), error = function(e) NULL)
    typ <- as.character(x$registry_type[i])
    if (typ %in% c("cell_set", "cell_set_recipe") && nzchar(as.character(key$cell_set %||% "")[1])) {
      return(data.frame(entity_kind = "cell_set", entity_id = as.character(key$cell_set)[1], stringsAsFactors = FALSE))
    }
    if (identical(typ, "feature_set") && nzchar(as.character(key$feature_set %||% "")[1]) && nzchar(as.character(key$matrix_id %||% "")[1])) {
      return(data.frame(entity_kind = "feature_set", entity_id = .wb_feature_set_entity_id(key$feature_set, key$matrix_id), stringsAsFactors = FALSE))
    }
    NULL
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(out)
  unique(do.call(rbind, rows))
}

.wb_entity_direct_bindings <- function(bundle) {
  con <- bundle$con
  out <- data.frame(entity_kind = character(), entity_id = character(), stringsAsFactors = FALSE)
  if (.wb_table_exists(con, "prov_run_entity_bindings")) {
    direct <- DBI::dbGetQuery(con, "SELECT DISTINCT direction, entity_kind, entity_id FROM prov_run_entity_bindings;")
    if (nrow(direct)) {
      external_model_input <- vapply(seq_len(nrow(direct)),function(i) {
        if (!identical(as.character(direct$direction[i]),"input") || !identical(as.character(direct$entity_kind[i]),"model_ref")) return(FALSE)
        !isTRUE(.wb_model_ref_physical_presence(
          bundle, as.character(direct$entity_id[i]), allow_pending = TRUE
        )$present)
      },logical(1))
      out <- direct[!external_model_input,c("entity_kind","entity_id"),drop=FALSE]
    }
  }
  if (.wb_table_exists(con, "prov_run_outputs")) {
    a <- DBI::dbGetQuery(con, "SELECT DISTINCT artifact_id AS entity_id FROM prov_run_outputs WHERE artifact_id IS NOT NULL AND artifact_id <> '';")
    if (nrow(a)) out <- rbind(out, transform(a, entity_kind = "artifact")[, c("entity_kind", "entity_id")])
  }
  unique(rbind(out, .wb_entity_registry_bindings(con)))
}

.wb_entity_is_provenance_bound <- function(bundle, entity_kind, entity_id) {
  z <- .wb_entity_normalize(entity_kind, entity_id)
  con <- bundle$con
  bindings <- .wb_entity_direct_bindings(bundle)
  lifecycle_bound <- function(kind, id) {
    if (!.wb_table_exists(con, "entity_lifecycle")) return(FALSE)
    x <- DBI::dbGetQuery(con, "SELECT provenance_bound FROM entity_lifecycle WHERE entity_kind = ? AND entity_id = ?;",
      params = list(kind, id))
    nrow(x) == 1L && as.integer(x$provenance_bound[1]) == 1L
  }
  if (identical(z$kind, "model")) {
    model_ids <- as.character(bindings$entity_id[bindings$entity_kind == "model_ref"])
    return(lifecycle_bound(z$kind, z$id) || any(vapply(strsplit(model_ids, "|", fixed = TRUE), function(x) length(x) >= 2L && identical(x[[2]], z$id), logical(1))))
  }
  lifecycle_bound(z$kind, z$id) || any(as.character(bindings$entity_kind) == z$kind & as.character(bindings$entity_id) == z$id)
}

.wb_entity_assert_replaceable <- function(bundle, entity_kind, entity_id, action = "replace") {
  z <- .wb_entity_normalize(entity_kind, entity_id)
  if (.wb_entity_is_provenance_bound(bundle, z$kind, z$id)) {
    stop(
      "Cannot ", action, " provenance-bound ", z$kind, " '", z$id,
      "'. Create a new identifier, then record it with wb_entity_supersede(). Historical identities are immutable.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

.wb_entity_physical_inventory <- function(bundle) {
  con <- bundle$con
  rows <- list()
  add <- function(kind, ids) {
    ids <- unique(as.character(ids)); ids <- ids[!is.na(ids) & nzchar(ids)]
    if (length(ids)) rows[[length(rows) + 1L]] <<- data.frame(entity_kind = kind, entity_id = ids, stringsAsFactors = FALSE)
  }
  if (.wb_table_exists(con, "matrices")) add("matrix", DBI::dbGetQuery(con, "SELECT matrix_id FROM matrices;")$matrix_id)
  if (.wb_table_exists(con, "spaces")) add("space", DBI::dbGetQuery(con, "SELECT space_id FROM spaces;")$space_id)
  if (.wb_table_exists(con, "space_models")) add("model", DBI::dbGetQuery(con, "SELECT space_id FROM space_models;")$space_id)
  if (.wb_table_exists(con, "artifacts")) add("artifact", DBI::dbGetQuery(con, "SELECT artifact_id FROM artifacts;")$artifact_id)
  if (.wb_table_exists(con, "cell_set_membership")) add("cell_set", DBI::dbGetQuery(con, "SELECT DISTINCT cell_set FROM cell_set_membership;")$cell_set)
  if (.wb_table_exists(con, "feature_sets")) {
    x <- DBI::dbGetQuery(con, "SELECT feature_set, matrix_id FROM feature_sets;")
    if (nrow(x)) add("feature_set", mapply(.wb_feature_set_entity_id, x$feature_set, x$matrix_id, USE.NAMES = FALSE))
  }
  if (.wb_table_exists(con, "metadata_fields")) {
    add("metadata_field", DBI::dbGetQuery(
      con, "SELECT field_id FROM metadata_fields WHERE is_core=0;"
    )$field_id)
  }
  if (.wb_table_exists(con, "prov_source_inputs")) {
    sources <- DBI::dbGetQuery(con, "SELECT DISTINCT source_id, source_json FROM prov_source_inputs;")
    if (nrow(sources)) {
      in_memory <- vapply(sources$source_json, function(txt) identical(as.character((.wb_validation_json(txt) %||% list())$scope %||% ""), "in_memory"), logical(1))
      add("external_source", sources$source_id[!in_memory])
      add("in_memory_source", sources$source_id[in_memory])
    }
  }
  if (!length(rows)) return(data.frame(entity_kind = character(), entity_id = character(), stringsAsFactors = FALSE))
  unique(do.call(rbind, rows))
}

.wb_entity_inventory <- function(bundle) {
  physical <- .wb_entity_physical_inventory(bundle)
  bindings <- .wb_entity_direct_bindings(bundle)
  unique(rbind(physical, bindings))
}

.wb_entity_lifecycle_migrate <- function(bundle) {
  if (isTRUE(bundle$read_only)) return(invisible(FALSE))
  .wb_with_bundle_writer_lock(bundle, operation = "entity lifecycle migration", code = {
    .wb_entity_lifecycle_migrate_locked(bundle)
  })
}

.wb_entity_lifecycle_migrate_locked <- function(bundle) {
  con <- bundle$con
  .wb_entity_lifecycle_tables(con)
  inv <- .wb_entity_inventory(bundle)
  if (!nrow(inv)) return(invisible(TRUE))
  bindings <- .wb_entity_direct_bindings(bundle)
  for (i in seq_len(nrow(inv))) {
    kind <- as.character(inv$entity_kind[i]); id <- as.character(inv$entity_id[i])
    bound <- if (identical(kind, "model")) .wb_entity_is_provenance_bound(bundle, kind, id) else
      any(bindings$entity_kind == kind & bindings$entity_id == id)
    .wb_entity_lifecycle_upsert(con, kind, id, bound = bound)
  }
  if (.wb_table_exists(con, "prov_run_entity_bindings")) {
    persisted <- DBI::dbGetQuery(
      con,
      paste0(
        "SELECT direction, entity_kind, entity_id, content_hash, ",
        if (.wb_db_has_column(con, "prov_run_entity_bindings", "content_identity_scheme")) "content_identity_scheme" else "NULL AS content_identity_scheme",
        " FROM prov_run_entity_bindings ORDER BY entity_kind, entity_id;"
      )
    )
    if (nrow(persisted)) for (i in seq_len(nrow(persisted))) {
      if (identical(as.character(persisted$direction[i]),"input") && identical(as.character(persisted$entity_kind[i]),"model_ref")) {
        registered <- .wb_model_ref_physical_presence(
          bundle, as.character(persisted$entity_id[i]), allow_pending = TRUE
        )
        if (!isTRUE(registered$present)) next
      }
      .wb_entity_backfill_binding(
        con,
        as.character(persisted$entity_kind[i]),
        as.character(persisted$entity_id[i]),
        persisted$content_hash[i], persisted$content_identity_scheme[i]
      )
    }
  }
  if (.wb_table_exists(con, "prov_registry_mutations") &&
      .wb_db_has_column(con, "prov_registry_mutations", "content_hash")) {
    persisted_registry <- DBI::dbGetQuery(
      con,
      paste0(
        "SELECT registry_type, registry_key_json, content_hash, ",
        if (.wb_db_has_column(con, "prov_registry_mutations", "content_identity_scheme")) "content_identity_scheme" else "NULL AS content_identity_scheme",
        " FROM prov_registry_mutations ORDER BY registry_type, registry_key_json;"
      )
    )
    if (nrow(persisted_registry)) for (i in seq_len(nrow(persisted_registry))) {
      key <- tryCatch(
        jsonlite::fromJSON(as.character(persisted_registry$registry_key_json[i]), simplifyVector = FALSE),
        error = function(e) NULL
      )
      entity <- if (is.null(key)) NULL else .wb_registry_event_entity(
        as.character(persisted_registry$registry_type[i]), key
      )
      if (!is.null(entity)) {
        .wb_entity_backfill_binding(
          con, entity$kind, entity$id, persisted_registry$content_hash[i],
          persisted_registry$content_identity_scheme[i]
        )
      }
    }
  }
  # A legacy provenance claim whose payload registry row has disappeared is
  # migrated as retracted, not silently recreated as current.
  physical <- .wb_entity_physical_inventory(bundle)
  binding_physically_present <- function(kind, id) {
    if (kind == "model_ref") {
      return(isTRUE(.wb_model_ref_physical_presence(bundle, id, allow_pending = TRUE)$present))
    }
    any(physical$entity_kind == kind & physical$entity_id == id)
  }
  missing <- bindings[!vapply(seq_len(nrow(bindings)), function(i) {
    binding_physically_present(as.character(bindings$entity_kind[i]), as.character(bindings$entity_id[i]))
  }, logical(1)), , drop = FALSE]
  if (nrow(missing)) for (i in seq_len(nrow(missing))) {
    kind <- as.character(missing$entity_kind[i]); id <- as.character(missing$entity_id[i])
    .wb_entity_lifecycle_upsert(con, kind, id, state = "retracted", bound = TRUE,
      reason = "Migrated legacy provenance binding with missing durable registry payload.")
    now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
    DBI::dbExecute(con, "UPDATE entity_lifecycle SET lifecycle_state = 'retracted', provenance_bound = 1, updated_at = ?, reason = ? WHERE entity_kind = ? AND entity_id = ? AND lifecycle_state = 'current';",
      params = list(now, "Migrated legacy provenance binding with missing durable registry payload.", kind, id))
    DBI::dbExecute(con, "INSERT OR IGNORE INTO entity_tombstones(entity_kind, entity_id, tombstone_state, retracted_at, reason) VALUES(?, ?, 'retracted', ?, ?);",
      params = list(kind, id, now, "Migrated legacy provenance binding with missing durable registry payload."))
  }
  invisible(TRUE)
}

#' List Durable Entity Lifecycle State
#'
#' Returns current and historical lifecycle state for matrices, spaces, models,
#' artifacts, cell sets, feature sets, and other provenance-bound registry rows.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind Optional entity-kind filter.
#' @param entity_id Optional entity-id filter.
#' @param lifecycle_state Optional state filter.
#' @param include_history If `FALSE`, return only `current` entities.
#' @return A data frame with one row per durable entity identity.
#' @export
wb_entity_lifecycle <- function(bundle, entity_kind = NULL, entity_id = NULL,
                                lifecycle_state = NULL, include_history = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  if (!isTRUE(bundle$read_only)) .wb_entity_lifecycle_migrate(bundle)
  if (!.wb_table_exists(bundle$con, "entity_lifecycle")) {
    return(data.frame(entity_kind = character(), entity_id = character(), lifecycle_state = character(),
      identity_hash = character(), provenance_bound = integer(), created_at = character(), updated_at = character(),
      reason = character(), actor = character(), stringsAsFactors = FALSE))
  }
  x <- DBI::dbGetQuery(bundle$con, "SELECT * FROM entity_lifecycle ORDER BY entity_kind, entity_id;")
  if (!is.null(entity_kind)) x <- x[x$entity_kind %in% as.character(entity_kind), , drop = FALSE]
  if (!is.null(entity_id)) x <- x[x$entity_id %in% as.character(entity_id), , drop = FALSE]
  if (!isTRUE(include_history)) x <- x[x$lifecycle_state == "current", , drop = FALSE]
  if (!is.null(lifecycle_state)) x <- x[x$lifecycle_state %in% as.character(lifecycle_state), , drop = FALSE]
  rownames(x) <- NULL
  x
}

#' List Explicit Entity Supersession Relationships
#' @param bundle Open `scworkbench_bundle`.
#' @return A data frame of `SUPERSEDES` relationships.
#' @export
wb_entity_supersessions <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  if (!isTRUE(bundle$read_only)) .wb_entity_lifecycle_migrate(bundle)
  if (!.wb_table_exists(bundle$con, "entity_supersessions")) return(data.frame())
  DBI::dbGetQuery(bundle$con, "SELECT * FROM entity_supersessions ORDER BY created_at, successor_kind, successor_id;")
}

.wb_entity_set_state <- function(bundle, entity_kind, entity_id, state, reason, actor = NULL) {
  .wb_assert_bundle_writable(bundle, "entity lifecycle mutation")
  .wb_with_bundle_writer_lock(bundle, operation = paste0("entity lifecycle transition: ", state), code = {
    .wb_entity_set_state_locked(bundle, entity_kind, entity_id, state, reason, actor)
  })
}

.wb_entity_set_state_locked <- function(bundle, entity_kind, entity_id, state, reason, actor = NULL) {
  .wb_entity_lifecycle_migrate(bundle)
  z <- .wb_entity_normalize(entity_kind, entity_id)
  .wb_assert(state %in% c("retracted", "rejected", "ephemeral"), "invalid lifecycle transition")
  .wb_assert(is.character(reason) && length(reason) == 1L && nzchar(reason), "reason must be a non-empty string")
  row <- DBI::dbGetQuery(bundle$con, "SELECT * FROM entity_lifecycle WHERE entity_kind = ? AND entity_id = ?;", params = list(z$kind, z$id))
  .wb_assert(nrow(row) == 1L, paste0("Unknown durable entity: ", z$kind, "/", z$id))
  if (identical(state, "ephemeral")) {
    .wb_assert(!.wb_entity_is_provenance_bound(bundle, z$kind, z$id), "A provenance-bound entity cannot be marked ephemeral.")
  }
  .wb_assert(row$lifecycle_state[1] %in% c("current", "ephemeral"), paste0(
    "Entity is already historical (", row$lifecycle_state[1], ") and cannot transition again."
  ))
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  write_state <- function() {
    DBI::dbExecute(bundle$con, "UPDATE entity_lifecycle SET lifecycle_state = ?, updated_at = ?, reason = ?, actor = ? WHERE entity_kind = ? AND entity_id = ?;",
      params = list(state, now, reason, actor %||% NA_character_, z$kind, z$id))
    if (state %in% c("retracted", "rejected")) {
      DBI::dbExecute(bundle$con, "INSERT INTO entity_tombstones(entity_kind, entity_id, tombstone_state, retracted_at, retracted_by, reason, identity_hash, identity_scheme) VALUES(?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(entity_kind, entity_id) DO NOTHING;",
        params = list(z$kind, z$id, state, now, actor %||% NA_character_, reason, row$identity_hash[1] %||% NA_character_, row$identity_scheme[1] %||% NA_character_))
    }
  }
  if (isTRUE(getOption("scworkbench.registry_replay_transaction_open"))) write_state() else DBI::dbWithTransaction(bundle$con, write_state())
  invisible(wb_entity_lifecycle(bundle, z$kind, z$id))
}

#' Retract A Durable Entity Without Deleting Evidence
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind Durable entity kind.
#' @param entity_id Durable entity identifier.
#' @param reason Required retraction reason.
#' @param retracted_by Optional actor.
#' @return Invisibly returns the lifecycle row.
#' @export
wb_entity_retract <- function(bundle, entity_kind, entity_id, reason, retracted_by = NULL) {
  .wb_entity_set_state(bundle, entity_kind, entity_id, "retracted", reason, retracted_by)
}

#' Reject A Durable Candidate Without Deleting Evidence
#' @inheritParams wb_entity_retract
#' @export
wb_entity_reject <- function(bundle, entity_kind, entity_id, reason, retracted_by = NULL) {
  .wb_entity_set_state(bundle, entity_kind, entity_id, "rejected", reason, retracted_by)
}

#' Mark An Unbound Entity As Ephemeral
#' @inheritParams wb_entity_retract
#' @export
wb_entity_mark_ephemeral <- function(bundle, entity_kind, entity_id, reason, retracted_by = NULL) {
  .wb_entity_set_state(bundle, entity_kind, entity_id, "ephemeral", reason, retracted_by)
}

#' Record An Explicit Supersession
#'
#' Both identities remain stored. The predecessor becomes historical and the
#' successor becomes the current claim.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind Entity kind shared by predecessor and successor.
#' @param entity_id New successor identifier.
#' @param supersedes_id Existing predecessor identifier.
#' @param reason Required rationale.
#' @param created_by Optional actor.
#' @return Invisibly returns the inserted relationship.
#' @export
wb_entity_supersede <- function(bundle, entity_kind, entity_id, supersedes_id,
                                reason, created_by = NULL) {
  .wb_assert_bundle_writable(bundle, "entity supersession")
  .wb_with_bundle_writer_lock(bundle, operation = "entity supersession", code = {
    .wb_entity_supersede_locked(bundle, entity_kind, entity_id, supersedes_id, reason, created_by)
  })
}

.wb_entity_supersede_locked <- function(bundle, entity_kind, entity_id, supersedes_id,
                                        reason, created_by = NULL) {
  .wb_entity_lifecycle_migrate(bundle)
  successor <- .wb_entity_normalize(entity_kind, entity_id)
  predecessor <- .wb_entity_normalize(entity_kind, supersedes_id)
  .wb_assert(!identical(successor$id, predecessor$id), "Successor and predecessor identifiers must differ.")
  .wb_assert(is.character(reason) && length(reason) == 1L && nzchar(reason), "reason must be a non-empty string")
  x <- wb_entity_lifecycle(bundle, entity_kind = successor$kind, entity_id = c(successor$id, predecessor$id))
  .wb_assert(all(c(successor$id, predecessor$id) %in% x$entity_id), "Both successor and predecessor must already exist.")
  old <- x[x$entity_id == predecessor$id, , drop = FALSE]
  new <- x[x$entity_id == successor$id, , drop = FALSE]
  .wb_assert(old$lifecycle_state[1] == "current", "Predecessor must be current.")
  .wb_assert(
    identical(as.character(new$lifecycle_state[1]), "current") &&
      identical(as.integer(new$provenance_bound[1]), 1L),
    "Successor must be a current, provenance-bound identity. Promote an unbound or ephemeral candidate first."
  )
  if (.wb_table_exists(bundle$con, "entity_supersessions")) {
    edges <- DBI::dbGetQuery(
      bundle$con,
      "SELECT successor_kind, successor_id, predecessor_kind, predecessor_id FROM entity_supersessions WHERE successor_kind = ? AND predecessor_kind = ?;",
      params = list(successor$kind, successor$kind)
    )
    reaches <- function(from, target) {
      seen <- character(0)
      queue <- as.character(from)
      while (length(queue)) {
        current <- queue[[1]]
        queue <- queue[-1]
        if (identical(current, target)) return(TRUE)
        if (current %in% seen) next
        seen <- c(seen, current)
        queue <- c(queue, as.character(edges$predecessor_id[edges$successor_id == current]))
      }
      FALSE
    }
    .wb_assert(
      !reaches(predecessor$id, successor$id),
      "Supersession would create a cycle."
    )
  }
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  DBI::dbWithTransaction(bundle$con, {
    DBI::dbExecute(bundle$con, "UPDATE entity_lifecycle SET lifecycle_state = 'superseded', updated_at = ?, reason = ?, actor = ? WHERE entity_kind = ? AND entity_id = ?;",
      params = list(now, reason, created_by %||% NA_character_, predecessor$kind, predecessor$id))
    DBI::dbExecute(bundle$con, "UPDATE entity_lifecycle SET lifecycle_state = 'current', updated_at = ?, reason = NULL, actor = ? WHERE entity_kind = ? AND entity_id = ?;",
      params = list(now, created_by %||% NA_character_, successor$kind, successor$id))
    DBI::dbExecute(bundle$con, "INSERT INTO entity_supersessions(successor_kind, successor_id, predecessor_kind, predecessor_id, relationship_type, created_at, created_by, reason) VALUES(?, ?, ?, ?, 'SUPERSEDES', ?, ?, ?);",
      params = list(successor$kind, successor$id, predecessor$kind, predecessor$id, now, created_by %||% NA_character_, reason))
  })
  invisible(wb_entity_supersessions(bundle))
}

.wb_entity_has_references <- function(bundle, kind, id) {
  if (.wb_entity_is_provenance_bound(bundle, kind, id)) return(TRUE)
  if (identical(kind, "artifact")) {
    edges <- .wb_art_dependency_edges(bundle)
    if (nrow(edges) && any(edges$parent_artifact_id == id | edges$child_artifact_id == id)) return(TRUE)
  }
  if (.wb_table_exists(bundle$con, "entity_supersessions")) {
    n <- DBI::dbGetQuery(bundle$con, "SELECT COUNT(*) AS n FROM entity_supersessions WHERE (successor_kind = ? AND successor_id = ?) OR (predecessor_kind = ? AND predecessor_id = ?);",
      params = list(kind, id, kind, id))$n[1]
    if (as.integer(n) > 0L) return(TRUE)
  }
  FALSE
}

#' Unsafely Purge A Verified Ephemeral Entity
#'
#' This is the only physical entity-deletion route. It requires exact,
#' unmistakable confirmation and refuses provenance-bound or referenced state.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind Entity kind.
#' @param entity_id Entity identifier.
#' @param confirmation Exact string `PURGE UNREFERENCED EPHEMERAL ENTITY`.
#' @return Invisibly returns `TRUE`.
#' @export
wb_unsafe_purge_ephemeral_entity <- function(bundle, entity_kind, entity_id, confirmation) {
  .wb_assert_bundle_writable(bundle, "unsafe ephemeral purge")
  .wb_with_bundle_writer_lock(bundle, operation = "unsafe ephemeral entity purge", code = {
    .wb_unsafe_purge_ephemeral_entity_locked(bundle, entity_kind, entity_id, confirmation)
  })
}

.wb_unsafe_purge_ephemeral_entity_locked <- function(bundle, entity_kind, entity_id, confirmation) {
  .wb_assert(identical(as.character(confirmation)[1], "PURGE UNREFERENCED EPHEMERAL ENTITY"),
    "Unsafe purge requires confirmation='PURGE UNREFERENCED EPHEMERAL ENTITY'.")
  .wb_entity_lifecycle_migrate(bundle)
  z <- .wb_entity_normalize(entity_kind, entity_id)
  row <- wb_entity_lifecycle(bundle, z$kind, z$id)
  .wb_assert(nrow(row) == 1L && identical(row$lifecycle_state[1], "ephemeral"), "Only explicitly marked ephemeral entities can be purged.")
  .wb_assert(!.wb_entity_has_references(bundle, z$kind, z$id), "Ephemeral entity is referenced and cannot be purged.")
  con <- bundle$con
  retired_space_path <- ""
  if (identical(z$kind, "space") && .wb_table_exists(con, "space_payloads")) {
    payload <- DBI::dbGetQuery(con, "SELECT path FROM space_payloads WHERE space_id = ?;",
                               params = list(z$id))
    if (nrow(payload)) retired_space_path <- as.character(payload$path[[1L]])
  }
  DBI::dbWithTransaction(con, {
    if (identical(z$kind, "artifact")) {
      a <- DBI::dbGetQuery(con, "SELECT type FROM artifacts WHERE artifact_id = ?;", params = list(z$id))
      if (nrow(a)) .wb_art_delete_payload(con, z$id, as.character(a$type[1]), bundle = bundle)
    } else if (identical(z$kind, "cell_set")) {
      DBI::dbExecute(con, "DELETE FROM cell_set_membership WHERE cell_set = ?;", params = list(z$id))
    } else if (identical(z$kind, "feature_set")) {
      parts <- strsplit(z$id, "::", fixed = TRUE)[[1]]
      .wb_assert(length(parts) >= 2L, "Invalid feature-set lifecycle identifier.")
      matrix_id <- parts[[1]]; feature_set <- paste(parts[-1], collapse = "::")
      DBI::dbExecute(con, "DELETE FROM feature_set_membership WHERE matrix_id = ? AND feature_set = ?;", params = list(matrix_id, feature_set))
      DBI::dbExecute(con, "DELETE FROM feature_sets WHERE matrix_id = ? AND feature_set = ?;", params = list(matrix_id, feature_set))
    } else if (identical(z$kind, "space")) {
      DBI::dbExecute(con, "DELETE FROM space_payloads WHERE space_id = ?;", params = list(z$id))
      DBI::dbExecute(con, "DELETE FROM spaces WHERE space_id = ?;", params = list(z$id))
    } else if (identical(z$kind, "model")) {
      DBI::dbExecute(con, "DELETE FROM space_models WHERE space_id = ?;", params = list(z$id))
    } else if (identical(z$kind, "matrix")) {
      stop("Matrix payload purge is intentionally unsupported; remove an entire disposable development bundle instead.", call. = FALSE)
    } else {
      stop("Physical purge is not implemented for entity kind: ", z$kind, call. = FALSE)
    }
    DBI::dbExecute(con, "DELETE FROM entity_lifecycle WHERE entity_kind = ? AND entity_id = ?;", params = list(z$kind, z$id))
  })
  if (nzchar(retired_space_path)) {
    status <- .wb_path_status(bundle$dir, retired_space_path, expected_type = "file",
                              must_exist = FALSE, purpose = "purged dense-space payload")
    if (isTRUE(status$ok) && file.exists(status$absolute)) unlink(status$absolute, force = TRUE)
  }
  invisible(TRUE)
}
