# Durable entity lifecycle and immutable-history support.

.wb_entity_lifecycle_schema <- function() "scworkbench.entity_lifecycle.v1"

.wb_entity_kinds <- function() {
  c("matrix", "space", "model", "model_ref", "artifact", "cell_set", "feature_set", "external_source", "registry")
}

.wb_entity_normalize <- function(entity_kind, entity_id) {
  kind <- as.character(entity_kind %||% "")[1]
  id <- as.character(entity_id %||% "")[1]
  .wb_assert(kind %in% .wb_entity_kinds(), paste0(
    "entity_kind must be one of: ", paste(.wb_entity_kinds(), collapse = ", ")
  ))
  .wb_assert(nzchar(id), "entity_id must be a non-empty string")
  if (identical(kind, "cell_set") && !startsWith(id, "set:")) id <- paste0("set:", id)
  list(kind = kind, id = id)
}

.wb_feature_set_entity_id <- function(feature_set, matrix_id) {
  paste0(as.character(matrix_id)[1], "::", as.character(feature_set)[1])
}

.wb_entity_lifecycle_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS entity_lifecycle (
      entity_kind TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      lifecycle_state TEXT NOT NULL,
      identity_hash TEXT,
      provenance_bound INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      reason TEXT,
      actor TEXT,
      PRIMARY KEY(entity_kind, entity_id),
      CHECK(lifecycle_state IN ('current','superseded','rejected','retracted','ephemeral'))
    );
  ")
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
      PRIMARY KEY(entity_kind, entity_id),
      CHECK(tombstone_state IN ('retracted','rejected'))
    );
  ")
  invisible(TRUE)
}

.wb_entity_lifecycle_upsert <- function(con, kind, id, state = "current",
                                        identity_hash = NA_character_, bound = FALSE,
                                        reason = NA_character_, actor = NA_character_) {
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  DBI::dbExecute(con, "
    INSERT INTO entity_lifecycle(entity_kind, entity_id, lifecycle_state, identity_hash,
      provenance_bound, created_at, updated_at, reason, actor)
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(entity_kind, entity_id) DO UPDATE SET
      identity_hash = COALESCE(entity_lifecycle.identity_hash, excluded.identity_hash),
      provenance_bound = MAX(entity_lifecycle.provenance_bound, excluded.provenance_bound),
      updated_at = CASE WHEN excluded.provenance_bound > entity_lifecycle.provenance_bound
                        THEN excluded.updated_at ELSE entity_lifecycle.updated_at END;
  ", params = list(kind, id, state, identity_hash, as.integer(isTRUE(bound)), now, now, reason, actor))
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

.wb_entity_direct_bindings <- function(con) {
  out <- data.frame(entity_kind = character(), entity_id = character(), stringsAsFactors = FALSE)
  if (.wb_table_exists(con, "prov_run_entity_bindings")) {
    out <- DBI::dbGetQuery(con, "SELECT DISTINCT entity_kind, entity_id FROM prov_run_entity_bindings;")
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
  bindings <- .wb_entity_direct_bindings(con)
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
  if (.wb_table_exists(con, "prov_source_inputs")) add("external_source", DBI::dbGetQuery(con, "SELECT DISTINCT source_id FROM prov_source_inputs;")$source_id)
  if (!length(rows)) return(data.frame(entity_kind = character(), entity_id = character(), stringsAsFactors = FALSE))
  unique(do.call(rbind, rows))
}

.wb_entity_inventory <- function(bundle) {
  physical <- .wb_entity_physical_inventory(bundle)
  bindings <- .wb_entity_direct_bindings(bundle$con)
  unique(rbind(physical, bindings))
}

.wb_entity_lifecycle_migrate <- function(bundle) {
  con <- bundle$con
  .wb_entity_lifecycle_tables(con)
  inv <- .wb_entity_inventory(bundle)
  if (!nrow(inv)) return(invisible(TRUE))
  bindings <- .wb_entity_direct_bindings(con)
  for (i in seq_len(nrow(inv))) {
    kind <- as.character(inv$entity_kind[i]); id <- as.character(inv$entity_id[i])
    bound <- if (identical(kind, "model")) .wb_entity_is_provenance_bound(bundle, kind, id) else
      any(bindings$entity_kind == kind & bindings$entity_id == id)
    .wb_entity_lifecycle_upsert(con, kind, id, bound = bound)
  }
  # A legacy provenance claim whose payload registry row has disappeared is
  # migrated as retracted, not silently recreated as current.
  physical <- .wb_entity_physical_inventory(bundle)
  binding_physically_present <- function(kind, id) {
    if (kind == "model_ref") {
      bits <- strsplit(as.character(id), "|", fixed = TRUE)[[1]]
      return(length(bits) >= 2L && any(physical$entity_kind == "model" & physical$entity_id == bits[[2]]))
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
      DBI::dbExecute(bundle$con, "INSERT INTO entity_tombstones(entity_kind, entity_id, tombstone_state, retracted_at, retracted_by, reason, identity_hash) VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(entity_kind, entity_id) DO NOTHING;",
        params = list(z$kind, z$id, state, now, actor %||% NA_character_, reason, row$identity_hash[1] %||% NA_character_))
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
  .wb_assert(new$lifecycle_state[1] %in% c("current", "ephemeral"), "Successor must not already be historical.")
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
  .wb_assert(identical(as.character(confirmation)[1], "PURGE UNREFERENCED EPHEMERAL ENTITY"),
    "Unsafe purge requires confirmation='PURGE UNREFERENCED EPHEMERAL ENTITY'.")
  .wb_entity_lifecycle_migrate(bundle)
  z <- .wb_entity_normalize(entity_kind, entity_id)
  row <- wb_entity_lifecycle(bundle, z$kind, z$id)
  .wb_assert(nrow(row) == 1L && identical(row$lifecycle_state[1], "ephemeral"), "Only explicitly marked ephemeral entities can be purged.")
  .wb_assert(!.wb_entity_has_references(bundle, z$kind, z$id), "Ephemeral entity is referenced and cannot be purged.")
  con <- bundle$con
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
      DBI::dbExecute(con, "DELETE FROM space_2d WHERE space_id = ?;", params = list(z$id))
      DBI::dbExecute(con, "DELETE FROM space_coords WHERE space_id = ?;", params = list(z$id))
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
  invisible(TRUE)
}
