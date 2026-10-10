# Central owner for the durable bundle schema and its ordered migrations.
# Component schema helpers remain compatibility shims for callers inside the
# package, but only this file orchestrates schema creation and upgrades.

.wb_bundle_schema_version <- function() 11L

.wb_bundle_schema_migrations <- function() {
  list(
    list(version = 1L, id = "001_consolidate_durable_schema", apply = .wb_schema_migration_001),
    list(version = 2L, id = "002_referential_integrity", apply = .wb_schema_migration_002),
    list(version = 3L, id = "003_lifecycle_backfill", apply = .wb_schema_migration_003),
    list(version = 4L, id = "004_complete_space_foreign_keys", apply = .wb_schema_migration_004),
    list(version = 5L, id = "005_metadata_field_registry", apply = .wb_schema_migration_005),
    list(version = 6L, id = "006_provenance_identity_schemes", apply = .wb_schema_migration_006),
    list(version = 7L, id = "007_analysis_capsules", apply = .wb_schema_migration_007),
    list(version = 8L, id = "008_metadata_field_content_identity", apply = .wb_schema_migration_008),
    list(version = 9L, id = "009_typed_cell_set_consumption", apply = .wb_schema_migration_009),
    list(version = 10L, id = "010_nullable_cell_vector_family", apply = .wb_schema_migration_010),
    list(version = 11L, id = "011_graph_sqlite_v1", apply = .wb_schema_migration_011)
  )
}

.wb_schema_migration_011 <- function(con, bundle_dir = NULL) {
  .wb_graph_create_schema(con, retained = TRUE)
  .wb_graph_object_schema(con)
  invisible(TRUE)
}

.wb_sqlite_configure_connection <- function(con, writable = TRUE, configure_journal = TRUE) {
  .wb_assert(DBI::dbIsValid(con), "SQLite connection is not valid.")
  attr(con, "scworkbench_read_only") <- !isTRUE(writable)
  if (!isTRUE(writable)) return(invisible(TRUE))
  transacting <- isTRUE(tryCatch(RSQLite::sqliteIsTransacting(con), error = function(e) FALSE))
  if (transacting) {
    enabled <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "PRAGMA foreign_keys;")[[1L]][1L]))
    .wb_assert(identical(enabled, 1L),
               "Writable SQLite transaction has foreign-key enforcement disabled; mutation is forbidden.")
    return(invisible(TRUE))
  }
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")
  enabled <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "PRAGMA foreign_keys;")[[1L]][1L]))
  .wb_assert(identical(enabled, 1L),
             "Writable SQLite connection refused PRAGMA foreign_keys=ON; no mutation is permitted.")
  if (isTRUE(configure_journal)) DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "PRAGMA synchronous=NORMAL;")
  invisible(TRUE)
}

.wb_schema_ledger_exists <- function(con) {
  nrow(DBI::dbGetQuery(
    con,
    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='bundle_schema_migrations' LIMIT 1;"
  )) == 1L
}

.wb_schema_component_is_current <- function(con, tables, columns = list()) {
  if (!.wb_schema_ledger_exists(con) || !identical(.wb_schema_status(con)$status, "current")) return(FALSE)
  missing <- setdiff(as.character(tables), DBI::dbListTables(con))
  .wb_assert(!length(missing), paste0(
    "BUNDLE_SCHEMA_CORRUPT: current migration ledger is missing table(s): ",
    paste(missing, collapse = ", "), ". Restore a backup; lazy repair is forbidden."
  ))
  for (table in names(columns)) {
    absent <- setdiff(columns[[table]], DBI::dbListFields(con, table))
    .wb_assert(!length(absent), paste0(
      "BUNDLE_SCHEMA_CORRUPT: current migration ledger is missing ", table,
      " column(s): ", paste(absent, collapse = ", "), ". Restore a backup; lazy repair is forbidden."
    ))
  }
  TRUE
}

.wb_assert_observational_schema <- function(bundle, tables, action = "bundle inspection") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  status <- .wb_schema_status(bundle$con)
  if (!identical(status$status, "current")) {
    code <- if (identical(status$status, "upgrade_required")) {
      "BUNDLE_SCHEMA_UPGRADE_REQUIRED"
    } else {
      "BUNDLE_SCHEMA_CORRUPT"
    }
    stop(
      code, ": ", action, " requires the current bundle schema. ", status$message,
      " Open the bundle writable with the current scworkbench and run wb_migrate_bundle().",
      call. = FALSE
    )
  }
  .wb_schema_component_is_current(bundle$con, tables)
  invisible(TRUE)
}

.wb_schema_status <- function(con) {
  current <- .wb_bundle_schema_version()
  if (!.wb_schema_ledger_exists(con)) {
    return(list(current = current, observed = 0L, status = "upgrade_required",
                message = paste0("Bundle schema ledger is absent; writable migration to version ", current, " is required.")))
  }
  rows <- DBI::dbGetQuery(
    con,
    "SELECT version, migration_id FROM bundle_schema_migrations ORDER BY version;"
  )
  observed <- if (nrow(rows)) max(as.integer(rows$version)) else 0L
  expected <- .wb_bundle_schema_migrations()
  expected_ids <- vapply(expected, `[[`, character(1), "id")
  expected_versions <- vapply(expected, `[[`, integer(1), "version")
  valid_prefix <- nrow(rows) <= length(expected) && identical(
    as.integer(rows$version), head(expected_versions, nrow(rows))
  ) && identical(as.character(rows$migration_id), head(expected_ids, nrow(rows)))
  if (observed > current) {
    return(list(current = current, observed = observed, status = "newer_schema",
                message = paste0("Bundle schema version ", observed, " is newer than this scworkbench supports (", current, ").")))
  }
  if (!isTRUE(valid_prefix)) {
    return(list(current = current, observed = observed, status = "invalid_ledger",
                message = "Bundle schema migration ledger is not a valid ordered migration prefix."))
  }
  if (observed < current) {
    return(list(current = current, observed = observed, status = "upgrade_required",
                message = paste0("Bundle schema version ", observed, " requires writable migration to version ", current, ".")))
  }
  definitions <- .wb_schema_foreign_key_definitions()
  invalid_constraints <- lapply(names(definitions), function(table) {
    .wb_schema_table_foreign_key_status(con, table)
  })
  names(invalid_constraints) <- names(definitions)
  invalid_constraints <- invalid_constraints[!vapply(invalid_constraints, `[[`, logical(1), "ok")]
  if (length(invalid_constraints)) {
    detail <- vapply(names(invalid_constraints), function(table) {
      paste0(table, " [", invalid_constraints[[table]]$message, "]")
    }, character(1))
    return(list(
      current = current, observed = observed, status = "invalid_schema",
      message = paste0(
        "Bundle migration ledger is current but its exact foreign-key signature is invalid: ",
        paste(detail, collapse = "; "), ". Restore a verified schema backup; lazy repair is forbidden."
      )
    ))
  }
  family_columns <- DBI::dbGetQuery(con, "PRAGMA table_info(artifact_pseudotime);")
  value_column <- family_columns[family_columns$name == "pseudotime", , drop = FALSE]
  if (nrow(value_column) != 1L || as.integer(value_column$notnull[[1L]]) != 0L) {
    return(list(current = current, observed = observed, status = "invalid_schema",
                message = "Bundle migration ledger is current but cell-vector-family values are not nullable."))
  }
  list(current = current, observed = observed, status = "current",
       message = paste0("Bundle schema is current at version ", current, "."))
}

.wb_schema_create_ledger <- function(con) {
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS bundle_schema_migrations (",
    "version INTEGER PRIMARY KEY,",
    "migration_id TEXT NOT NULL UNIQUE,",
    "applied_at TEXT NOT NULL,",
    "scworkbench_version TEXT NOT NULL",
    ");"
  ))
  invisible(TRUE)
}

.wb_schema_migration_hook <- function(event, version = NA_integer_, migration_id = NA_character_, con = NULL) {
  hook <- getOption("scworkbench.schema_migration_test_hook")
  if (is.function(hook)) hook(event = event, version = version, migration_id = migration_id, con = con)
  invisible(TRUE)
}

.wb_schema_migration_001 <- function(con, bundle_dir = NULL) {
  .wb_ensure_schema_app_bundle(con)
  .wb_ensure_metadata_fields_table(con)
  .wb_ensure_metadata_field_identities_table(con)
  .wb_ensure_analysis_capsule_tables(con)
  .wb_create_artifacts_schema(con)
  .wb_migrate_provenance_tables_locked(con)
  .wb_ensure_feature_set_tables(con)
  .wb_ensure_cell_vectors_tables(con)
  .wb_ensure_cell_set_recipes_table(con)
  .wb_ensure_motif_registry_tables(con)
  .wb_ensure_space_models_table(con)
  .wb_ensure_registry_mutation_events_table(con)
  .wb_ensure_prov_registry_mutations_table(con)
  invisible(TRUE)
}

.wb_schema_migration_006 <- function(con, bundle_dir = NULL) {
  .wb_migrate_provenance_identity_schemes_locked(con)
  invisible(TRUE)
}

.wb_schema_migration_009 <- function(con, bundle_dir = NULL) {
  .wb_migrate_provenance_tables_locked(con)
  invisible(TRUE)
}

.wb_schema_migration_010 <- function(con, bundle_dir = NULL) {
  columns <- DBI::dbGetQuery(con, "PRAGMA table_info(artifact_pseudotime);")
  .wb_assert(identical(as.character(columns$name),
    c("artifact_id", "cell_id", "lineage_id", "pseudotime")),
    "Nullable-family migration requires the exact historical artifact_pseudotime columns.")
  if (as.integer(columns$notnull[columns$name == "pseudotime"][[1L]]) == 0L)
    return(invisible(TRUE))
  .wb_assert(isTRUE(.wb_schema_table_foreign_key_status(con, "artifact_pseudotime")$ok),
    "Nullable-family migration requires the historical artifact_pseudotime foreign keys.")
  DBI::dbExecute(con, "PRAGMA defer_foreign_keys=ON;")
  DBI::dbExecute(con, "
    CREATE TABLE __wb_nullable_artifact_pseudotime (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      lineage_id TEXT NOT NULL,
      pseudotime REAL,
      PRIMARY KEY (artifact_id, cell_id, lineage_id),
      FOREIGN KEY (artifact_id) REFERENCES artifacts (artifact_id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY (cell_id) REFERENCES cells (cell_id) DEFERRABLE INITIALLY DEFERRED
    );")
  DBI::dbExecute(con, "
    INSERT INTO __wb_nullable_artifact_pseudotime(artifact_id,cell_id,lineage_id,pseudotime)
    SELECT artifact_id,cell_id,lineage_id,pseudotime FROM artifact_pseudotime;")
  .wb_assert(identical(
    as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM __wb_nullable_artifact_pseudotime;")$n[[1L]]),
    as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM artifact_pseudotime;")$n[[1L]])),
    "Nullable-family migration did not preserve every historical payload row.")
  DBI::dbExecute(con, "DROP TABLE artifact_pseudotime;")
  DBI::dbExecute(con, "ALTER TABLE __wb_nullable_artifact_pseudotime RENAME TO artifact_pseudotime;")
  DBI::dbExecute(con, "CREATE INDEX idx_pt_artifact ON artifact_pseudotime(artifact_id);")
  invisible(TRUE)
}

.wb_schema_rebuild_with_foreign_keys <- function(con, table, constraints, force = FALSE) {
  .wb_assert(.wb_table_exists(con, table), paste0("Schema migration expected table: ", table))
  if (!isTRUE(force) && isTRUE(.wb_schema_table_foreign_key_status(con, table)$ok)) return(invisible(FALSE))

  schema <- DBI::dbGetQuery(
    con, "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?;", params = list(table)
  )$sql[[1L]]
  .wb_assert(is.character(schema) && length(schema) == 1L && nzchar(schema),
             paste0("Cannot recover canonical CREATE statement for ", table, "."))
  indexes <- DBI::dbGetQuery(
    con,
    "SELECT sql FROM sqlite_schema WHERE type='index' AND tbl_name=? AND sql IS NOT NULL ORDER BY name;",
    params = list(table)
  )$sql
  temporary <- paste0("__wb_schema_new_", table)
  DBI::dbExecute(con, paste0("DROP TABLE IF EXISTS ", DBI::dbQuoteIdentifier(con, temporary), ";"))
  create <- sub(
    "^CREATE[[:space:]]+TABLE[[:space:]]+[^[:space:]\\(]+",
    paste("CREATE TABLE", temporary), schema, ignore.case = TRUE, perl = TRUE
  )
  # Migrations may replace an incomplete or incorrect declaration. Strip the
  # centrally owned table-level clauses before installing the canonical set;
  # otherwise a same-count wrong relationship can survive beside the repair.
  create <- gsub(
    ",?[[:space:]]*FOREIGN[[:space:]]+KEY[[:space:]]*\\([^)]*\\)[[:space:]]+REFERENCES[[:space:]]+[^,([:space:]]+[[:space:]]*\\([^)]*\\)[[:space:]]*(?:ON[[:space:]]+(?:UPDATE|DELETE)[[:space:]]+[A-Z[:space:]]+)?[[:space:]]*(?:ON[[:space:]]+(?:UPDATE|DELETE)[[:space:]]+[A-Z[:space:]]+)?[[:space:]]*(?:MATCH[[:space:]]+[A-Z]+)?[[:space:]]*(?:(?:NOT[[:space:]]+)?DEFERRABLE(?:[[:space:]]+INITIALLY[[:space:]]+(?:DEFERRED|IMMEDIATE))?)?",
    "", create, ignore.case = TRUE, perl = TRUE
  )
  create <- sub("[)][[:space:]]*$", paste0(",\n  ", paste(constraints, collapse = ",\n  "), "\n)"), create, perl = TRUE)
  .wb_assert(!identical(create, schema), paste0("Could not prepare constrained schema for ", table, "."))
  DBI::dbExecute(con, create)
  tryCatch(
    DBI::dbExecute(
      con,
      paste0("INSERT INTO ", DBI::dbQuoteIdentifier(con, temporary),
             " SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), ";")
    ),
    error = function(e) stop(
      "Referential-integrity migration rejected existing rows in ", table,
      ": ", conditionMessage(e), call. = FALSE
    )
  )
  DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, table), ";"))
  DBI::dbExecute(
    con,
    paste0("ALTER TABLE ", DBI::dbQuoteIdentifier(con, temporary),
           " RENAME TO ", DBI::dbQuoteIdentifier(con, table), ";")
  )
  for (sql in indexes) DBI::dbExecute(con, sql)
  invisible(TRUE)
}

.wb_schema_fk <- function(columns, parent, parent_columns = columns) {
  paste0(
    "FOREIGN KEY (", paste(columns, collapse = ", "), ") REFERENCES ", parent,
    " (", paste(parent_columns, collapse = ", "), ") DEFERRABLE INITIALLY DEFERRED"
  )
}

.wb_schema_fk_spec <- function(columns, parent, parent_columns = columns,
                               on_update = "NO ACTION", on_delete = "NO ACTION",
                               match = "NONE", deferred = "DEFERRABLE INITIALLY DEFERRED") {
  list(
    columns = as.character(columns), parent = as.character(parent)[1L],
    parent_columns = as.character(parent_columns), on_update = toupper(on_update),
    on_delete = toupper(on_delete), match = toupper(match), deferred = toupper(deferred)
  )
}

.wb_schema_foreign_key_contract <- function() {
  fk <- .wb_schema_fk_spec
  list(
    space_payloads = list(fk("space_id", "spaces")),
    features = list(fk("matrix_id", "matrices")),
    matrix_cells = list(fk("matrix_id", "matrices"), fk("cell_id", "cells")),
    cell_set_membership = list(fk("cell_id", "cells")),
    matrix_fragments = list(fk("matrix_id", "matrices")),
    matrix_fragment_cells = list(fk("fragment_id", "matrix_fragments"), fk("cell_id", "cells")),
    matrix_fragment_features = list(fk("fragment_id", "matrix_fragments")),
    cell_vector_values = list(fk("vector_id", "cell_vectors"), fk("cell_id", "cells")),
    feature_sets = list(fk("matrix_id", "matrices")),
    feature_set_membership = list(
      fk(c("feature_set", "matrix_id"), "feature_sets", c("feature_set", "matrix_id")),
      fk(c("matrix_id", "feature_id"), "features", c("matrix_id", "feature_id"))
    ),
    entity_supersessions = list(
      fk(c("successor_kind", "successor_id"), "entity_lifecycle", c("entity_kind", "entity_id")),
      fk(c("predecessor_kind", "predecessor_id"), "entity_lifecycle", c("entity_kind", "entity_id"))
    ),
    entity_tombstones = list(fk(c("entity_kind", "entity_id"), "entity_lifecycle", c("entity_kind", "entity_id"))),
    motifs = list(fk("motif_library", "motif_libraries")),
    motif_match_sets = list(fk("matrix_id", "matrices"), fk("motif_library", "motif_libraries")),
    motif_match_membership = list(fk("motif_match_set", "motif_match_sets"), fk("motif_key", "motifs")),
    space_models = list(fk("space_id", "spaces", "space_id"), fk("source_space_id", "spaces", "space_id")),
    artifacts = list(fk("provenance_snapshot_id", "prov_heads", "snapshot_id")),
    artifact_graph_meta = list(fk("artifact_id", "artifacts")),
    artifact_graph_rows = list(fk("artifact_id", "artifact_graph_meta")),
    artifact_object_payload_meta = list(fk("artifact_id", "artifacts")),
    artifact_object_metadata_chunks = list(fk("artifact_id", "artifact_object_payload_meta")),
    artifact_labels = list(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_pseudotime = list(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_relation_rows = list(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_curves_2d = list(fk("artifact_id", "artifacts")),
    artifact_space_path_meta = list(fk("artifact_id", "artifacts")),
    artifact_space_path_rows = list(fk("artifact_id", "artifacts"), fk("space_id", "spaces", "space_id")),
    artifact_umap_model = list(fk("artifact_id", "artifacts"), fk("space_id", "spaces", "space_id")),
    artifact_model_ref = list(fk("artifact_id", "artifacts")),
    artifact_tables = list(fk("artifact_id", "artifacts")),
    artifact_table_rows = list(fk("artifact_id", "artifacts")),
    prov_heads = list(fk("commit_id", "prov_commits", "commit_id")),
    prov_runs = list(fk("snapshot_id", "prov_heads", "snapshot_id")),
    prov_run_edges = list(
      fk(c("snapshot_id", "parent_run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk(c("snapshot_id", "child_run_id"), "prov_runs", c("snapshot_id", "run_id"))
    ),
    prov_run_outputs = list(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("artifact_id", "artifacts", "artifact_id")
    ),
    prov_run_entity_bindings = list(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("commit_id", "prov_commits", "commit_id")
    ),
    prov_source_identities = list(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("matrix_id", "matrices", "matrix_id")
    ),
    prov_source_inputs = list(fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id"))),
    prov_replay_equivalence_results = list(
      fk("replay_snapshot_id", "prov_heads", "snapshot_id"),
      fk("replay_artifact_id", "artifacts", "artifact_id")
    ),
    prov_materializations = list(fk("commit_id", "prov_commits", "commit_id")),
    prov_registry_mutations = list(fk("commit_id", "prov_commits", "commit_id")),
    analysis_capsule_inputs = list(fk("capsule_id", "analysis_capsules")),
    analysis_capsule_outputs = list(fk("capsule_id", "analysis_capsules")),
    analysis_capsule_relationships = list(
      fk("capsule_id", "analysis_capsules"),
      fk("related_capsule_id", "analysis_capsules", "capsule_id")
    ),
    metadata_field_identities = list(
      fk("field_id", "metadata_fields", "field_id"),
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id"))
    )
  )
}

.wb_schema_fk_signature <- function(spec) {
  paste(
    paste(spec$columns, collapse = ","), spec$parent,
    paste(spec$parent_columns, collapse = ","), spec$on_update,
    spec$on_delete, spec$match, sep = " -> "
  )
}

.wb_schema_actual_foreign_key_signatures <- function(con, table) {
  actual <- DBI::dbGetQuery(con, paste0(
    "PRAGMA foreign_key_list(", DBI::dbQuoteIdentifier(con, table), ");"
  ))
  if (!nrow(actual)) return(character())
  groups <- split(actual, actual$id)
  unname(sort(vapply(groups, function(rows) {
    rows <- rows[order(as.integer(rows$seq)), , drop = FALSE]
    .wb_schema_fk_signature(list(
      columns = as.character(rows$from), parent = as.character(rows$table[1L]),
      parent_columns = as.character(rows$to), on_update = toupper(as.character(rows$on_update[1L])),
      on_delete = toupper(as.character(rows$on_delete[1L])), match = toupper(as.character(rows$match[1L]))
    ))
  }, character(1))))
}

.wb_schema_table_foreign_key_status <- function(con, table) {
  expected_specs <- .wb_schema_foreign_key_contract()[[table]]
  if (is.null(expected_specs) || !.wb_table_exists(con, table)) {
    return(list(ok = FALSE, message = "required table is absent"))
  }
  expected <- unname(sort(vapply(expected_specs, .wb_schema_fk_signature, character(1))))
  actual <- .wb_schema_actual_foreign_key_signatures(con, table)
  signature_ok <- identical(actual, expected)
  schema <- DBI::dbGetQuery(
    con, "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?;", params = list(table)
  )$sql
  deferred_count <- if (length(schema) && !is.na(schema[[1L]])) {
    hits <- gregexpr("DEFERRABLE[[:space:]]+INITIALLY[[:space:]]+DEFERRED", schema[[1L]], ignore.case = TRUE, perl = TRUE)[[1L]]
    if (identical(hits[[1L]], -1L)) 0L else length(hits)
  } else 0L
  deferred_ok <- identical(as.integer(deferred_count), as.integer(length(expected_specs))) &&
    !grepl("NOT[[:space:]]+DEFERRABLE|INITIALLY[[:space:]]+IMMEDIATE", schema[[1L]], ignore.case = TRUE, perl = TRUE)
  if (signature_ok && deferred_ok) return(list(ok = TRUE, message = "exact signature matches"))
  missing <- setdiff(expected, actual)
  extra <- setdiff(actual, expected)
  detail <- c(
    if (length(missing)) paste0("missing=", paste(missing, collapse = " | ")),
    if (length(extra)) paste0("unexpected=", paste(extra, collapse = " | ")),
    if (!deferred_ok) paste0("deferred declarations=", deferred_count, "/", length(expected_specs))
  )
  list(ok = FALSE, message = paste(detail, collapse = "; "))
}

.wb_schema_foreign_key_definitions <- function() {
  lapply(.wb_schema_foreign_key_contract(), function(specs) {
    vapply(specs, function(spec) {
      .wb_schema_fk(spec$columns, spec$parent, spec$parent_columns)
    }, character(1))
  })
}

.wb_schema_identifier_relationships <- function() {
  rows <- list()
  add <- function(table, columns, target, classification, enforcement) {
    rows[[length(rows) + 1L]] <<- data.frame(
      table = table, columns = paste(columns, collapse = ", "), target = target,
      classification = classification, enforcement = enforcement,
      stringsAsFactors = FALSE
    )
  }
  contract <- .wb_schema_foreign_key_contract()
  for (table in names(contract)) for (spec in contract[[table]]) add(
    table, spec$columns,
    paste0(spec$parent, "(", paste(spec$parent_columns, collapse = ", "), ")"),
    "sqlite_foreign_key", "Exact central FK signature; DEFERRABLE INITIALLY DEFERRED"
  )

  # Relationships whose normalized child shape cannot express the parent's
  # full identity, or whose parent is polymorphic/JSON-encoded, are checked by
  # the exhaustive deep validator instead of an ordinary SQLite FK.
  app <- list(
    list("cells", "dataset_id", "datasets(dataset_id)", "DANGLING_DATASET_REFERENCE"),
    list("matrix_fragments", "feature_ids_json", "features(matrix_id, feature_id) via matrix_id", "MATRIX_FRAGMENT_FEATURE_ORDER_MISMATCH / payload identity checks"),
    list("matrix_fragments", "cell_ids_json", "cells(cell_id)", "MATRIX_FRAGMENT_CELL_COVERAGE_GAP / payload identity checks"),
    list("matrix_fragment_features", "feature_id", "features(matrix_id, feature_id) via matrix_fragments.matrix_id", "MATRIX_FRAGMENT_FEATURE_REGISTRY_MISMATCH"),
    list("motif_match_membership", "feature_id", "features(matrix_id, feature_id) via motif_match_sets.matrix_id", "MOTIF_MATCH_DANGLING_MATRIX_FEATURE"),
    list("prov_heads", "head_run_ids_json", "prov_runs(snapshot_id, run_id)", "PROVENANCE_DANGLING_HEAD_RUN"),
    list("prov_materializations", "run_id", "prov_runs(run_id), snapshot-independent legacy key", "MATERIALIZATION_DANGLING_RUN"),
    list("prov_registry_mutations", "run_id", "prov_runs(run_id), snapshot-independent materialization key", "registry/provenance deep validation"),
    list("prov_replay_equivalence_results", "original_run_id, replay_run_id", "prov_runs(run_id), cross-snapshot replay identities", "replay-equivalence deep validation"),
    list("prov_run_entity_bindings", "entity_kind, entity_id", "polymorphic durable registry", "PROVENANCE_DANGLING_ENTITY_BINDING"),
    list("analysis_capsule_inputs", "entity_id", "polymorphic accepted durable registry", "CAPSULE_INPUT_BINDINGS_INVALID / capsule deep validation"),
    list("entity_lifecycle", "entity_kind, entity_id", "polymorphic durable registry", "lifecycle/deep-validation state binding"),
    list("registry_mutation_events", "run_id", "session staging run", "promotion transaction validates selected run topology")
  )
  for (x in app) add(x[[1L]], x[[2L]], x[[3L]], "application_validated", x[[4L]])

  # These values are deliberately namespaced labels, payload-local identities,
  # human actors, or external/source identifiers. They are not durable registry
  # child relationships and must remain representable without invented rows.
  symbolic <- list(
    list("artifacts", "input_space_id", "symbolic operation input space"),
    list("artifacts", "input_matrix_id", "symbolic operation input matrix"),
    list("artifacts", "cell_set", "symbolic selector/cell-set namespace"),
    list("artifact_model_ref", "model_space_id", "engine-owned model identity; may be external"),
    list("artifact_model_ref", "in_space_id", "optional engine input-space label; may be external"),
    list("artifact_curves_2d", "lineage_id", "artifact-local lineage identity"),
    list("artifact_pseudotime", "lineage_id", "artifact-local lineage identity"),
    list("artifact_relation_rows", "relation_key", "artifact-local relation identity"),
    list("artifact_space_path_rows", "path_id", "artifact-local path identity"),
    list("cell_set_membership", "cell_set", "cell-set namespace; registry is membership-defined"),
    list("cell_set_recipes", "cell_set", "cell-set namespace; recipe may precede materialization"),
    list("cell_set_styles", "cell_set", "cell-set namespace; style may precede materialization"),
    list("feature_sets", "set_id", "stable external/catalog set identity"),
    list("feature_sets", "source_id", "external feature-set source identity"),
    list("motif_libraries", "source_id", "external motif-library source identity"),
    list("motifs", "motif_id", "source-library motif identity"),
    list("metadata_fields", "import_id", "ingestion or attachment transaction identity"),
    list("metadata_field_identities", "import_id", "metadata publication transaction identity"),
    list("space_models", "cell_set", "symbolic fitted-cell selector"),
    list("prov_source_inputs", "source_id", "external source identity"),
    list("registry_mutation_events", "event_id", "session-local event identity"),
    list("prov_registry_mutations", "event_id", "promoted registry-event identity"),
    list("prov_replay_equivalence_results", "result_id", "replay result identity")
  )
  for (x in symbolic) add(x[[1L]], x[[2L]], "external or local namespace", "symbolic_or_external", x[[3L]])

  out <- do.call(rbind, rows)
  out[order(out$table, out$columns, out$classification), , drop = FALSE]
}

.wb_schema_migration_002 <- function(con, bundle_dir = NULL) {
  definitions <- .wb_schema_foreign_key_definitions()
  DBI::dbExecute(con, "PRAGMA defer_foreign_keys=ON;")
  # Rebuild referenced provenance parents before artifacts begin referring to
  # them. SQLite tracks a dropped referenced parent as a deferred violation
  # even when an equivalent table is recreated under the same name.
  # The four fresh graph-profile tables first exist in migration 011, whose
  # canonical declarations already include the exact central constraints.
  later_tables <- c("artifact_graph_meta", "artifact_graph_rows",
    "artifact_object_payload_meta", "artifact_object_metadata_chunks")
  table_order <- c("prov_heads", "prov_runs", setdiff(names(definitions),
    c("prov_heads", "prov_runs", later_tables)))
  for (table in table_order) {
    tryCatch(
      .wb_schema_rebuild_with_foreign_keys(con, table, definitions[[table]]),
      error = function(e) stop("Foreign-key migration failed while rebuilding ", table, ": ", conditionMessage(e), call. = FALSE)
    )
  }
  violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
  if (nrow(violations)) {
    first <- violations[1L, , drop = FALSE]
    stop(
      "Schema migration found dangling durable references in table ", first$table[[1L]],
      " at rowid ", first$rowid[[1L]], ". Repair the source bundle or restore from the migration backup.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

.wb_schema_migration_003 <- function(con, bundle_dir = NULL) {
  bundle <- structure(
    list(dir = bundle_dir %||% .wb_bundle_dir_from_connection(con), con = con, read_only = FALSE),
    class = "scworkbench_bundle"
  )
  .wb_entity_lifecycle_migrate_locked(bundle)
  invisible(TRUE)
}

.wb_schema_migration_004 <- function(con, bundle_dir = NULL) {
  definitions <- .wb_schema_foreign_key_definitions()
  DBI::dbExecute(con, "PRAGMA defer_foreign_keys=ON;")
  for (table in c("space_models", "artifact_umap_model", "artifact_space_path_rows")) {
    tryCatch(
      .wb_schema_rebuild_with_foreign_keys(con, table, definitions[[table]]),
      error = function(e) stop(
        "Complete-space foreign-key migration failed while rebuilding ", table,
        ": ", conditionMessage(e), call. = FALSE
      )
    )
  }
  violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
  if (nrow(violations)) stop(
    "Complete-space foreign-key migration found dangling durable references in table ",
    violations$table[[1L]], " at rowid ", violations$rowid[[1L]], ".",
    call. = FALSE
  )
  invisible(TRUE)
}

.wb_schema_migration_005 <- function(con, bundle_dir = NULL) {
  .wb_metadata_backfill_registry(con)
  invisible(TRUE)
}

.wb_schema_migration_007 <- function(con, bundle_dir = NULL) {
  .wb_ensure_analysis_capsule_tables(con)
  invisible(TRUE)
}

.wb_schema_migration_008 <- function(con, bundle_dir = NULL) {
  .wb_ensure_metadata_field_identities_table(con)
  invisible(TRUE)
}

.wb_schema_backup_database <- function(con, bundle_dir, from_version, to_version) {
  root <- file.path(
    dirname(bundle_dir), paste0(".", basename(bundle_dir), ".schema-backups")
  )
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  token <- .wb_allocate_identifier(
    paste0(format(Sys.time(), "%Y%m%dT%H%M%OS6"), "-", Sys.getpid(), "-"),
    12L, purpose = "schema migration backup"
  )
  path <- file.path(root, paste0("app.sqlite.v", from_version, "-to-v", to_version, ".", token, ".bak"))
  destination <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(try(DBI::dbDisconnect(destination), silent = TRUE), add = TRUE)
  .wb_sqlite_configure_connection(destination, writable = TRUE)
  RSQLite::sqliteCopyDatabase(con, destination)
  check <- DBI::dbGetQuery(destination, "PRAGMA quick_check;")[[1L]]
  .wb_assert(identical(tolower(as.character(check)), "ok"), "Migration backup failed SQLite quick_check.")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_schema_migrate_connection <- function(con, bundle_dir = NULL, backup = TRUE) {
  .wb_sqlite_configure_connection(con, writable = TRUE)
  initial <- .wb_schema_status(con)
  if (initial$status %in% c("newer_schema", "invalid_ledger", "invalid_schema")) stop(initial$message, call. = FALSE)
  if (identical(initial$status, "current")) return(invisible(list(changed = FALSE, backup = NULL, status = initial)))
  backup_path <- if (isTRUE(backup) && !is.null(bundle_dir)) {
    .wb_schema_backup_database(con, bundle_dir, initial$observed, .wb_bundle_schema_version())
  } else NULL

  migrations <- .wb_bundle_schema_migrations()
  pending <- migrations[vapply(migrations, function(x) x$version > initial$observed, logical(1))]
  DBI::dbBegin(con)
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con) && RSQLite::sqliteIsTransacting(con)) try(DBI::dbRollback(con), silent = TRUE), add = TRUE)
  tryCatch({
    .wb_schema_create_ledger(con)
    for (migration in pending) {
      .wb_schema_migration_hook("before", migration$version, migration$id, con)
      migration$apply(con, bundle_dir = bundle_dir)
      .wb_schema_migration_hook("after_apply", migration$version, migration$id, con)
      DBI::dbExecute(
        con,
        "INSERT INTO bundle_schema_migrations(version,migration_id,applied_at,scworkbench_version) VALUES(?,?,?,?);",
        params = list(
          migration$version, migration$id, format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z"),
          tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "development")
        )
      )
      .wb_schema_migration_hook("after_ledger", migration$version, migration$id, con)
    }
    final <- .wb_schema_status(con)
    .wb_assert(identical(final$status, "current"), final$message)
    violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
    .wb_assert(!nrow(violations), "Schema migration cannot commit with foreign-key violations.")
    DBI::dbCommit(con)
    committed <- TRUE
  }, error = function(e) {
    if (RSQLite::sqliteIsTransacting(con)) DBI::dbRollback(con)
    stop(
      "Bundle schema migration rolled back completely", if (!is.null(backup_path)) paste0("; recovery backup: ", backup_path) else "",
      ". Cause: ", conditionMessage(e), call. = FALSE
    )
  })
  invisible(list(changed = TRUE, backup = backup_path, status = .wb_schema_status(con)))
}

#' Inspect Bundle Schema Migration Status
#'
#' Inspect the migration ledger without changing the bundle.
#'
#' @param bundle_or_dir Open bundle or bundle directory.
#' @return A named schema-status record.
#' @export
wb_bundle_schema_status <- function(bundle_or_dir) {
  if (inherits(bundle_or_dir, "scworkbench_bundle")) return(.wb_schema_status(bundle_or_dir$con))
  path <- normalizePath(bundle_or_dir, winslash = "/", mustWork = TRUE)
  lock <- wb_bundle_writer_lock_info(path)
  .wb_assert(!isTRUE(lock$locked), paste0(
    "Bundle schema status requires stable recipient state; ", .wb_writer_lock_diagnostic(lock)
  ))
  manifest_path <- .wb_bundle_path_require(path,"manifest.json",expected_type="file",purpose="bundle manifest")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  db <- .wb_bundle_path_require(path,as.character(manifest$storage$sqlite$path)[1L],expected_type="file",purpose="manifest SQLite database")
  .wb_assert(!file.exists(paste0(db, "-wal")) && !file.exists(paste0(db, "-shm")),
             "Bundle schema status requires finalized SQLite state without WAL sidecars.")
  con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db, winslash = "/", mustWork = TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  .wb_sqlite_configure_connection(con, writable = FALSE)
  .wb_schema_status(con)
}

#' Migrate A Bundle To The Current Durable Schema
#'
#' Apply every pending ordered migration under the exclusive bundle-writer
#' lock and one SQLite transaction. Before upgrading an existing database, an
#' online SQLite backup is retained in a sibling hidden backup directory. A
#' failed migration rolls back the database completely; the backup can be
#' copied back while the bundle is closed if external recovery is required.
#'
#' @param bundle Open writable bundle.
#' @return Invisibly returns migration status and backup path.
#' @export
wb_migrate_bundle <- function(bundle) {
  .wb_assert_bundle_writable(bundle, "bundle schema migration")
  .wb_with_bundle_writer_lock(bundle, operation = "bundle schema migration", code = {
    .wb_schema_migrate_connection(bundle$con, bundle_dir = bundle$dir, backup = TRUE)
  })
}
