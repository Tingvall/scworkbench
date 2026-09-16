# Replay selected session registry mutations through canonical registry APIs.

.wb_ensure_registry_mutation_events_table <- function(con) {
  if (.wb_schema_component_is_current(con, "registry_mutation_events")) return(invisible(TRUE))
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS registry_mutation_events (event_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, registry_type TEXT NOT NULL, action TEXT NOT NULL, registry_key_json TEXT NOT NULL, payload_json TEXT, created_at TEXT NOT NULL);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_registry_mutation_events_run ON registry_mutation_events(run_id);")
  invisible(TRUE)
}

.wb_ensure_prov_registry_mutations_table <- function(con) {
  if (.wb_schema_component_is_current(
    con, "prov_registry_mutations",
    list(prov_registry_mutations = c("content_hash", "content_identity_scheme"))
  )) return(invisible(TRUE))
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS prov_registry_mutations (commit_id TEXT NOT NULL, event_id TEXT NOT NULL, run_id TEXT NOT NULL, registry_type TEXT NOT NULL, action TEXT NOT NULL, registry_key_json TEXT NOT NULL, payload_json TEXT, content_hash TEXT, content_identity_scheme TEXT, PRIMARY KEY(commit_id, event_id));")
  if (!.wb_db_has_column(con, "prov_registry_mutations", "content_hash")) {
    DBI::dbExecute(con, "ALTER TABLE prov_registry_mutations ADD COLUMN content_hash TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_registry_mutations", "content_identity_scheme")) {
    DBI::dbExecute(con, "ALTER TABLE prov_registry_mutations ADD COLUMN content_identity_scheme TEXT;")
  }
  invisible(TRUE)
}

.wb_journal_registry_mutation <- function(bundle, registry_type, action, key, payload = NULL) {
  ctx <- .wb_registry_mutation_context(bundle)
  if (is.null(bundle$staging_source_dir) || is.null(ctx)) {
    return(invisible(FALSE))
  }
  .wb_ensure_registry_mutation_events_table(bundle$con)
  payload_json <- if (is.null(payload)) NA_character_ else jsonlite::toJSON(
    payload, dataframe = "rows", auto_unbox = TRUE, null = "null"
  )
  DBI::dbExecute(
    bundle$con,
    "INSERT INTO registry_mutation_events(event_id, run_id, registry_type, action, registry_key_json, payload_json, created_at) VALUES(?, ?, ?, ?, ?, ?, ?);",
    params = list(
      .wb_allocate_db_identifier(
        bundle$con, "registry_mutation_events", "event_id",
        "registry_event_", n = 12L, purpose = "registry mutation event"
      ),
      as.character(ctx$run_id)[1],
      as.character(registry_type)[1],
      as.character(action)[1],
      jsonlite::toJSON(key, auto_unbox = TRUE, null = "null"),
      payload_json,
      format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
    )
  )
  invisible(TRUE)
}

.wb_registry_event_entity <- function(registry_type, key) {
  if (registry_type %in% c("cell_set", "cell_set_recipe")) {
    id <- as.character(key$cell_set %||% "")[1]
    if (nzchar(id)) return(.wb_entity_normalize("cell_set", id))
  }
  if (identical(registry_type, "feature_set")) {
    feature_set <- as.character(key$feature_set %||% "")[1]
    matrix_id <- as.character(key$matrix_id %||% "")[1]
    if (nzchar(feature_set) && nzchar(matrix_id)) {
      return(list(kind = "feature_set", id = .wb_feature_set_entity_id(feature_set, matrix_id)))
    }
  }
  NULL
}

.wb_registry_entity_content_hash <- function(bundle, entity_kind, entity_id) {
  con <- bundle$con
  payload <- if (identical(entity_kind, "cell_set")) {
    data.frame(
      cell_id = as.character(DBI::dbGetQuery(
        con,
        "SELECT cell_id FROM cell_set_membership WHERE cell_set = ? ORDER BY cell_id;",
        params = list(entity_id)
      )$cell_id),
      stringsAsFactors = FALSE
    )
  } else if (identical(entity_kind, "feature_set")) {
    parts <- strsplit(entity_id, "::", fixed = TRUE)[[1]]
    .wb_assert(length(parts) >= 2L, "Invalid feature-set lifecycle identifier.")
    matrix_id <- parts[[1]]
    feature_set <- paste(parts[-1], collapse = "::")
    list(
      metadata = DBI::dbGetQuery(
        con,
        "SELECT * FROM feature_sets WHERE matrix_id = ? AND feature_set = ?;",
        params = list(matrix_id, feature_set)
      ),
      members = DBI::dbGetQuery(
        con,
        "SELECT feature_id, rank FROM feature_set_membership WHERE matrix_id = ? AND feature_set = ? ORDER BY rank, feature_id;",
        params = list(matrix_id, feature_set)
      )
    )
  } else {
    return(NA_character_)
  }
  .wb_prov_sha256_object(list(
    schema = "scworkbench.registry_entity_identity.v1",
    entity_kind = entity_kind,
    entity_id = entity_id,
    payload = payload
  ))
}

.wb_replay_registry_mutations <- function(staging_bundle, bundle, topo, commit_id) {
  if (is.null(staging_bundle) || !.wb_table_exists(staging_bundle$con, "registry_mutation_events")) return(invisible(data.frame()))
  ids <- unique(as.character(topo))
  if (!length(ids)) return(invisible(data.frame()))
  q <- paste(rep("?", length(ids)), collapse = ",")
  events <- DBI::dbGetQuery(
    staging_bundle$con,
    paste0("SELECT * FROM registry_mutation_events WHERE run_id IN (", q, ") ORDER BY rowid;"),
    params = as.list(ids)
  )
  if (!nrow(events)) return(invisible(events))
  .wb_operation_pack_registry_preflight(bundle, events)
  old <- getOption("scworkbench.registry_replay_transaction_open")
  old_replay <- getOption("scworkbench.provenance_registry_replay")
  options(scworkbench.registry_replay_transaction_open = TRUE)
  options(scworkbench.provenance_registry_replay = TRUE)
  on.exit({
    options(scworkbench.registry_replay_transaction_open = old)
    options(scworkbench.provenance_registry_replay = old_replay)
  }, add = TRUE)
  .wb_with_mutation_context(
    bundle = bundle, route = "promotion", staging_bundle = staging_bundle, code = {
  event_hashes <- rep(NA_character_, nrow(events))
  for (i in seq_len(nrow(events))) {
    hook <- getOption("scworkbench.registry_replay_hook", NULL)
    if (is.function(hook)) hook(events[i, , drop = FALSE])
    key <- jsonlite::fromJSON(as.character(events$registry_key_json[i]), simplifyVector = FALSE)
    action <- as.character(events$action[i])
    registry_type <- as.character(events$registry_type[i])
    payload_obj <- if (!is.na(events$payload_json[i]) && nzchar(as.character(events$payload_json[i]))) {
      jsonlite::fromJSON(as.character(events$payload_json[i]), simplifyVector = FALSE)
    } else NULL
    entity <- .wb_registry_event_entity(registry_type, key)
    retracting <- identical(registry_type, "feature_set") && identical(action, "delete") ||
      identical(registry_type, "cell_set") && identical(action, "remove") && is.null(payload_obj$cell_ids)
    if (!is.null(entity) && isTRUE(retracting)) {
      event_hashes[i] <- .wb_registry_entity_content_hash(bundle, entity$kind, entity$id)
      .wb_entity_bind_provenance(
        bundle$con, entity$kind, entity$id, event_hashes[i],
        unname(.wb_content_identity_schemes()[["registry"]])
      )
    }
    if (identical(registry_type, "feature_set") && identical(action, "replace")) {
      payload <- payload_obj
      meta <- as.data.frame(payload$metadata, stringsAsFactors = FALSE)
      .wb_assert(nrow(meta) == 1L, "Feature-set replace event metadata is invalid")
      wb_feature_set_replace(bundle, feature_set = key$feature_set, matrix_id = key$matrix_id,
        feature_ids = as.character(unlist(payload$feature_ids, use.names = FALSE)), strict = TRUE,
        created_by = as.character(meta$created_by[1] %||% NA_character_), description = as.character(meta$description[1] %||% NA_character_),
        set_id = as.character(meta$set_id[1] %||% NA_character_), namespace = as.character(meta$namespace[1] %||% NA_character_),
        organism = as.character(meta$organism[1] %||% NA_character_), source_id = as.character(meta$source_id[1] %||% NA_character_),
        source_version = as.character(meta$source_version[1] %||% NA_character_), origin = as.character(meta$origin[1] %||% NA_character_),
        recipe = as.character(meta$recipe_json[1] %||% NA_character_), is_readonly = as.integer(meta$is_readonly[1] %||% 0L))
    } else if (identical(registry_type, "feature_set") && identical(action, "delete")) {
      wb_feature_set_delete(bundle, feature_set = key$feature_set, matrix_id = key$matrix_id %||% NULL)
    } else if (identical(registry_type, "cell_set")) {
      payload <- payload_obj
      metadata <- payload$metadata %||% list()
      if (identical(action, "replace")) {
        wb_cell_set_replace(
          bundle,
          cell_set = key$cell_set,
          cell_ids = as.character(unlist(payload$cell_ids %||% character(0), use.names = FALSE)),
          source = as.character(metadata$source %||% "session_promotion")[1],
          created_by = as.character(metadata$created_by %||% NA_character_)[1],
          description = as.character(metadata$description %||% NA_character_)[1],
          strict = TRUE
        )
      } else if (identical(action, "add")) {
        ids_add <- as.character(unlist(payload$cell_ids %||% character(0), use.names = FALSE))
        if (length(ids_add)) {
          wb_cell_set_add(
            bundle,
            cell_set = key$cell_set,
            cell_ids = ids_add,
            source = as.character(metadata$source %||% "session_promotion")[1],
            created_by = as.character(metadata$created_by %||% NA_character_)[1],
            description = as.character(metadata$description %||% NA_character_)[1]
          )
        }
      } else if (identical(action, "remove")) {
        ids_remove <- payload$cell_ids %||% NULL
        if (!is.null(ids_remove)) ids_remove <- as.character(unlist(ids_remove, use.names = FALSE))
        wb_cell_set_remove(bundle, cell_set = key$cell_set, cell_ids = ids_remove)
      } else {
        stop("Unsupported cell-set registry mutation action: ", action, call. = FALSE)
      }
    } else if (identical(registry_type,
        "operation_pack_cell_set_family") && identical(action, "admit")) {
      event_hashes[i] <- .wb_operation_pack_registry_apply_event(
        bundle, events[i, , drop = FALSE], payload_obj)
    } else if (identical(registry_type, "cell_set_recipe") && identical(action, "upsert")) {
      payload <- payload_obj
      .wb_cell_set_recipe_row_upsert(
        bundle = bundle,
        cell_set = key$cell_set,
        recipe_json = as.character(payload$recipe_json %||% "")[1],
        created_at = as.character(payload$created_at %||% .wb_now_sqlite())[1],
        created_by = as.character(payload$created_by %||% NA_character_)[1],
        source = as.character(payload$source %||% NA_character_)[1],
        description = as.character(payload$description %||% NA_character_)[1],
        role = as.character(payload$role %||% NA_character_)[1],
        status = as.character(payload$status %||% NA_character_)[1]
      )
    } else {
      stop("Unsupported registry mutation event: ", registry_type, "/", action, call. = FALSE)
    }
    if (!is.null(entity) && !isTRUE(retracting)) {
      event_hashes[i] <- .wb_registry_entity_content_hash(bundle, entity$kind, entity$id)
      .wb_entity_bind_provenance(
        bundle$con, entity$kind, entity$id, event_hashes[i],
        unname(.wb_content_identity_schemes()[["registry"]])
      )
    }
  }
  })
  .wb_ensure_registry_mutation_events_table(bundle$con)
  .wb_ensure_prov_registry_mutations_table(bundle$con)
  if (any(as.character(events$registry_type) ==
      "operation_pack_cell_set_family")) {
    .wb_operation_pack_registry_fault(
      "before_registry_receipt_finalization", commit_id = commit_id)
  }
  events$content_hash <- event_hashes
  events$content_identity_scheme <- ifelse(
    is.na(event_hashes), NA_character_,
    unname(.wb_content_identity_schemes()[["registry"]])
  )
  .wb_db_append_chunked(
    bundle$con,
    "prov_registry_mutations",
    transform(events, commit_id = commit_id)[, c("commit_id", "event_id", "run_id", "registry_type", "action", "registry_key_json", "payload_json", "content_hash", "content_identity_scheme")]
  )
  invisible(events)
}
