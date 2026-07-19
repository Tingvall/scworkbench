# Replay selected session registry mutations through canonical registry APIs.

.wb_replay_registry_mutations <- function(staging_bundle, bundle, topo, commit_id) {
  if (is.null(staging_bundle) || !.wb_table_exists(staging_bundle$con, "registry_mutation_events")) return(invisible(data.frame()))
  ids <- unique(as.character(topo))
  if (!length(ids)) return(invisible(data.frame()))
  q <- paste(rep("?", length(ids)), collapse = ",")
  events <- DBI::dbGetQuery(staging_bundle$con, paste0("SELECT * FROM registry_mutation_events WHERE run_id IN (", q, ") ORDER BY created_at, event_id;"), params = as.list(ids))
  if (!nrow(events)) return(invisible(events))
  old <- getOption("scworkbench.registry_replay_transaction_open")
  options(scworkbench.registry_replay_transaction_open = TRUE)
  on.exit(options(scworkbench.registry_replay_transaction_open = old), add = TRUE)
  for (i in seq_len(nrow(events))) {
    hook <- getOption("scworkbench.registry_replay_hook", NULL)
    if (is.function(hook)) hook(events[i, , drop = FALSE])
    key <- jsonlite::fromJSON(as.character(events$registry_key_json[i]), simplifyVector = FALSE)
    action <- as.character(events$action[i])
    .wb_assert(identical(as.character(events$registry_type[i]), "feature_set"), "Unsupported registry mutation event")
    if (identical(action, "replace")) {
      payload <- jsonlite::fromJSON(as.character(events$payload_json[i]), simplifyVector = FALSE)
      meta <- as.data.frame(payload$metadata, stringsAsFactors = FALSE)
      .wb_assert(nrow(meta) == 1L, "Feature-set replace event metadata is invalid")
      wb_feature_set_replace(bundle, feature_set = key$feature_set, matrix_id = key$matrix_id,
        feature_ids = as.character(unlist(payload$feature_ids, use.names = FALSE)), strict = TRUE,
        created_by = as.character(meta$created_by[1] %||% NA_character_), description = as.character(meta$description[1] %||% NA_character_),
        set_id = as.character(meta$set_id[1] %||% NA_character_), namespace = as.character(meta$namespace[1] %||% NA_character_),
        organism = as.character(meta$organism[1] %||% NA_character_), source_id = as.character(meta$source_id[1] %||% NA_character_),
        source_version = as.character(meta$source_version[1] %||% NA_character_), origin = as.character(meta$origin[1] %||% NA_character_),
        recipe = as.character(meta$recipe_json[1] %||% NA_character_), is_readonly = as.integer(meta$is_readonly[1] %||% 0L))
    } else if (identical(action, "delete")) {
      wb_feature_set_delete(bundle, feature_set = key$feature_set, matrix_id = key$matrix_id %||% NULL)
    } else stop("Unsupported registry mutation action: ", action, call. = FALSE)
  }
  .wb_ensure_feature_set_tables(bundle$con)
  DBI::dbExecute(bundle$con, "CREATE TABLE IF NOT EXISTS prov_registry_mutations (commit_id TEXT NOT NULL, event_id TEXT NOT NULL, run_id TEXT NOT NULL, registry_type TEXT NOT NULL, action TEXT NOT NULL, registry_key_json TEXT NOT NULL, payload_json TEXT, PRIMARY KEY(commit_id, event_id));")
  DBI::dbAppendTable(bundle$con, "prov_registry_mutations", transform(events, commit_id = commit_id)[, c("commit_id", "event_id", "run_id", "registry_type", "action", "registry_key_json", "payload_json")])
  invisible(events)
}
