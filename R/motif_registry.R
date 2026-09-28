# Matrix genome + motif registry contract surfaces

.wb_ensure_matrix_contract_columns <- function(con) {
  .wb_assert(!is.null(con), "con is required")
  .wb_assert(.wb_db_has_table(con, "matrices"), "matrices table not found")
  if (.wb_schema_component_is_current(
    con, "matrices", list(matrices = c("organism", "genome_build", "genome_provider"))
  )) return(invisible(TRUE))

  add_col <- function(name, type) {
    if (.wb_db_has_column(con, "matrices", name)) return(invisible(NULL))
    DBI::dbExecute(con, paste0("ALTER TABLE matrices ADD COLUMN ", name, " ", type, ";"))
  }

  add_col("organism", "TEXT")
  add_col("genome_build", "TEXT")
  add_col("genome_provider", "TEXT")
  invisible(TRUE)
}

.wb_ensure_motif_registry_tables <- function(con) {
  .wb_assert(!is.null(con), "con is required")
  if (.wb_schema_component_is_current(
    con, c("motif_libraries", "motifs", "motif_match_sets", "motif_match_membership")
  )) return(invisible(TRUE))

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS motif_libraries (
      motif_library   TEXT PRIMARY KEY,
      source_type     TEXT NOT NULL,
      organism        TEXT,
      genome_build    TEXT,
      collection      TEXT,
      source_id       TEXT,
      source_version  TEXT,
      description     TEXT,
      created_at      TEXT NOT NULL,
      created_by      TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS motifs (
      motif_key       TEXT PRIMARY KEY,
      motif_library   TEXT NOT NULL,
      motif_id        TEXT,
      motif_name      TEXT,
      source_type     TEXT,
      matrix_class    TEXT,
      payload_json    TEXT,
      metadata_json   TEXT,
      created_at      TEXT NOT NULL,
      created_by      TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS motif_match_sets (
      motif_match_set   TEXT PRIMARY KEY,
      matrix_id         TEXT NOT NULL,
      motif_library     TEXT NOT NULL,
      organism          TEXT,
      genome_build      TEXT,
      genome_provider   TEXT,
      match_engine      TEXT NOT NULL,
      match_params_json TEXT,
      n_features        INTEGER,
      n_motifs          INTEGER,
      description       TEXT,
      created_at        TEXT NOT NULL,
      created_by        TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS motif_match_membership (
      motif_match_set   TEXT NOT NULL,
      motif_key         TEXT NOT NULL,
      feature_id        TEXT NOT NULL
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_libraries_source ON motif_libraries(source_type);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_libraries_org ON motif_libraries(organism, genome_build);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motifs_library ON motifs(motif_library);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motifs_id ON motifs(motif_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_match_sets_matrix ON motif_match_sets(matrix_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_match_sets_library ON motif_match_sets(motif_library);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_match_membership_set ON motif_match_membership(motif_match_set);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_match_membership_motif ON motif_match_membership(motif_key);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_motif_match_membership_feature ON motif_match_membership(feature_id);")
  invisible(TRUE)
}

#' Set Genome Metadata For A Matrix
#'
#' Canonical engine write path for declaring the organism/build contract of a
#' matrix. Peak matrices should carry this metadata explicitly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param organism Organism label, for example `"human"` or `"mouse"`.
#' @param genome_build Genome build label, for example `"hg38"` or `"mm10"`.
#' @param genome_provider Optional provider/ref label, for example
#'   `"BSgenome.Hsapiens.UCSC.hg38"`.
#'
#' @return Invisibly returns a small summary list.
#' @export
wb_matrix_set_genome <- function(bundle,
                                 matrix_id,
                                 organism,
                                 genome_build,
                                 genome_provider = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Matrix genome-contract mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "a wb_bundle_from_*() or wb_ingest_apply() declared ingestion transaction")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(organism) && length(organism) == 1 && nzchar(organism), "organism invalid")
  .wb_assert(is.character(genome_build) && length(genome_build) == 1 && nzchar(genome_build), "genome_build invalid")

  con <- bundle$con
  .wb_ensure_matrix_contract_columns(con)

  hit <- DBI::dbGetQuery(con, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(hit) == 1L, paste0("Unknown matrix_id: ", matrix_id))

  DBI::dbExecute(
    con,
    "UPDATE matrices
       SET organism = ?,
           genome_build = ?,
           genome_provider = ?
     WHERE matrix_id = ?;",
    params = list(
      as.character(organism)[1],
      as.character(genome_build)[1],
      if (is.null(genome_provider) || !nzchar(as.character(genome_provider)[1])) NA_character_ else as.character(genome_provider)[1],
      as.character(matrix_id)[1]
    )
  )

  invisible(list(
    matrix_id = as.character(matrix_id)[1],
    organism = as.character(organism)[1],
    genome_build = as.character(genome_build)[1],
    genome_provider = if (is.null(genome_provider)) NULL else as.character(genome_provider)[1]
  ))
}

#' List Motif Libraries
#'
#' Canonical registry getter for motif-library definitions.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param organism Optional organism filter.
#' @param genome_build Optional genome-build filter.
#' @param source_type Optional source-type filter, for example `"jaspar"` or
#'   `"custom"`.
#'
#' @return A data frame of motif-library rows.
#' @export
wb_motif_libraries <- function(bundle,
                               organism = NULL,
                               genome_build = NULL,
                               source_type = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)

  q <- "SELECT motif_library, source_type, organism, genome_build, collection, source_id, source_version, description, created_at, created_by FROM motif_libraries"
  where <- character(0)
  params <- list()

  if (!is.null(organism)) {
    where <- c(where, "organism = ?")
    params <- c(params, list(as.character(organism)[1]))
  }
  if (!is.null(genome_build)) {
    where <- c(where, "genome_build = ?")
    params <- c(params, list(as.character(genome_build)[1]))
  }
  if (!is.null(source_type)) {
    where <- c(where, "source_type = ?")
    params <- c(params, list(as.character(source_type)[1]))
  }
  if (length(where)) q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))
  q <- paste0(q, " ORDER BY motif_library;")

  out <- if (length(params)) DBI::dbGetQuery(con, q, params = params) else DBI::dbGetQuery(con, q)
  chr_cols <- intersect(c("motif_library", "source_type", "organism", "genome_build", "collection",
                          "source_id", "source_version", "description", "created_at", "created_by"),
                        colnames(out))
  for (nm in chr_cols) out[[nm]] <- as.character(out[[nm]])
  out
}

#' Register A Motif Library
#'
#' Writes one motif-library definition row. Motif definitions themselves are
#' stored separately in the `motifs` registry.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_library Canonical engine key for the library.
#' @param source_type Source type, for example `"jaspar"` or `"custom"`.
#' @param organism Optional organism label.
#' @param genome_build Optional genome-build label.
#' @param collection Optional collection label, for example `"CORE"`.
#' @param source_id Optional source identifier.
#' @param source_version Optional source version.
#' @param description Optional description.
#' @param created_by Optional author tag.
#'
#' @return Invisibly returns a small summary list.
#' @export
wb_motif_library_register <- function(bundle,
                                      motif_library,
                                      source_type,
                                      organism = NULL,
                                      genome_build = NULL,
                                      collection = NULL,
                                      source_id = NULL,
                                      source_version = NULL,
                                      description = NULL,
                                      created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Motif registry mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "a declared motif ingestion transaction during bundle assembly")
  .wb_assert(is.character(motif_library) && length(motif_library) == 1 && nzchar(motif_library), "motif_library invalid")
  .wb_assert(is.character(source_type) && length(source_type) == 1 && nzchar(source_type), "source_type invalid")

  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  DBI::dbExecute(
    con,
    "INSERT INTO motif_libraries(
       motif_library, source_type, organism, genome_build, collection,
       source_id, source_version, description, created_at, created_by
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(motif_library) DO UPDATE SET
       source_type = excluded.source_type,
       organism = excluded.organism,
       genome_build = excluded.genome_build,
       collection = excluded.collection,
       source_id = excluded.source_id,
       source_version = excluded.source_version,
       description = excluded.description,
       created_by = excluded.created_by;",
    params = list(
      as.character(motif_library)[1],
      as.character(source_type)[1],
      if (is.null(organism)) NA_character_ else as.character(organism)[1],
      if (is.null(genome_build)) NA_character_ else as.character(genome_build)[1],
      if (is.null(collection)) NA_character_ else as.character(collection)[1],
      if (is.null(source_id)) NA_character_ else as.character(source_id)[1],
      if (is.null(source_version)) NA_character_ else as.character(source_version)[1],
      if (is.null(description)) NA_character_ else as.character(description)[1],
      now,
      if (is.null(created_by)) NA_character_ else as.character(created_by)[1]
    )
  )

  invisible(list(
    motif_library = as.character(motif_library)[1],
    source_type = as.character(source_type)[1]
  ))
}

#' List Motifs
#'
#' Canonical registry getter for motif definitions.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_library Optional motif-library filter.
#' @param motif_keys Optional explicit motif-key filter.
#'
#' @return A data frame of motif-definition rows.
#' @export
wb_motifs <- function(bundle,
                      motif_library = NULL,
                      motif_keys = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)

  q <- "SELECT motif_key, motif_library, motif_id, motif_name, source_type, matrix_class, payload_json, metadata_json, created_at, created_by FROM motifs"
  where <- character(0)
  params <- list()

  if (!is.null(motif_library)) {
    where <- c(where, "motif_library = ?")
    params <- c(params, list(as.character(motif_library)[1]))
  }
  if (!is.null(motif_keys)) {
    keys <- unique(as.character(motif_keys))
    where <- c(where, paste0("motif_key IN ", .wb_sql_in_placeholders(length(keys))))
    params <- c(params, as.list(keys))
  }
  if (length(where)) q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))
  q <- paste0(q, " ORDER BY motif_library, motif_key;")

  out <- if (length(params)) DBI::dbGetQuery(con, q, params = params) else DBI::dbGetQuery(con, q)
  chr_cols <- intersect(c("motif_key", "motif_library", "motif_id", "motif_name", "source_type",
                          "matrix_class", "payload_json", "metadata_json", "created_at", "created_by"),
                        colnames(out))
  for (nm in chr_cols) out[[nm]] <- as.character(out[[nm]])
  out
}

#' Register A Motif Definition
#'
#' Writes one motif definition row into the motif registry. `payload_json` is the
#' canonical place for the serialized motif definition until a dedicated motif
#' primitive/loader surface is introduced.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_library Existing motif-library key.
#' @param motif_key Canonical engine key for the motif.
#' @param motif_name Optional human-readable motif name.
#' @param motif_id Optional external catalog id, for example a JASPAR id.
#' @param source_type Optional source type override.
#' @param matrix_class Optional motif matrix class label, for example `"PWMatrix"`.
#' @param payload_json Optional serialized motif payload JSON.
#' @param metadata Optional list or JSON string of extra metadata.
#' @param created_by Optional author tag.
#'
#' @return Invisibly returns a small summary list.
#' @export
wb_motif_register <- function(bundle,
                              motif_library,
                              motif_key,
                              motif_name = NULL,
                              motif_id = NULL,
                              source_type = NULL,
                              matrix_class = NULL,
                              payload_json = NULL,
                              metadata = NULL,
                              created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Motif registry mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "a declared motif ingestion transaction during bundle assembly")
  .wb_assert(is.character(motif_library) && length(motif_library) == 1 && nzchar(motif_library), "motif_library invalid")
  .wb_assert(is.character(motif_key) && length(motif_key) == 1 && nzchar(motif_key), "motif_key invalid")

  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)
  hit <- DBI::dbGetQuery(con, "SELECT motif_library FROM motif_libraries WHERE motif_library = ?;", params = list(motif_library))
  .wb_assert(nrow(hit) == 1L, paste0("Unknown motif_library: ", motif_library))

  meta_json <- if (is.null(metadata)) {
    NULL
  } else if (is.character(metadata) && length(metadata) == 1) {
    as.character(metadata)[1]
  } else {
    jsonlite::toJSON(metadata, auto_unbox = TRUE, null = "null")
  }
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  DBI::dbExecute(
    con,
    "INSERT INTO motifs(
       motif_key, motif_library, motif_id, motif_name, source_type,
       matrix_class, payload_json, metadata_json, created_at, created_by
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(motif_key) DO UPDATE SET
       motif_library = excluded.motif_library,
       motif_id = excluded.motif_id,
       motif_name = excluded.motif_name,
       source_type = excluded.source_type,
       matrix_class = excluded.matrix_class,
       payload_json = excluded.payload_json,
       metadata_json = excluded.metadata_json,
       created_by = excluded.created_by;",
    params = list(
      as.character(motif_key)[1],
      as.character(motif_library)[1],
      if (is.null(motif_id)) NA_character_ else as.character(motif_id)[1],
      if (is.null(motif_name)) NA_character_ else as.character(motif_name)[1],
      if (is.null(source_type)) NA_character_ else as.character(source_type)[1],
      if (is.null(matrix_class)) NA_character_ else as.character(matrix_class)[1],
      if (is.null(payload_json)) NA_character_ else as.character(payload_json)[1],
      if (is.null(meta_json)) NA_character_ else as.character(meta_json)[1],
      now,
      if (is.null(created_by)) NA_character_ else as.character(created_by)[1]
    )
  )

  invisible(list(
    motif_library = as.character(motif_library)[1],
    motif_key = as.character(motif_key)[1]
  ))
}

.wb_motif_registry_exported_singleton <- function(package) {
  object <- tryCatch(getExportedValue(package, package), error = identity)
  .wb_assert(!inherits(object, "error"), paste0(
    "Could not load exported singleton object from package: ", package))
  object
}

#' Import JASPAR Motifs Into The Registry
#'
#' Convenience importer for populating a motif library from an installed JASPAR
#' data package.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_library Canonical engine key for the library.
#' @param jaspar_pkg Installed JASPAR data package name.
#' @param species JASPAR species filter.
#' @param collection JASPAR collection filter.
#' @param motif_ids Optional exact JASPAR motif ids to retain.
#' @param motif_names Optional motif names to retain.
#' @param organism Optional organism label for the library row.
#' @param genome_build Optional genome-build label for the library row.
#' @param description Optional description.
#' @param created_by Optional author tag.
#'
#' @return Invisibly returns a small summary list.
#' @export
wb_motif_library_import_jaspar <- function(bundle,
                                           motif_library,
                                           jaspar_pkg = "JASPAR2020",
                                           species,
                                           collection = "CORE",
                                           motif_ids = NULL,
                                           motif_names = NULL,
                                           organism = NULL,
                                           genome_build = NULL,
                                           description = NULL,
                                           created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(motif_library) && length(motif_library) == 1 && nzchar(motif_library), "motif_library invalid")
  .wb_assert(is.character(jaspar_pkg) && length(jaspar_pkg) == 1 && nzchar(jaspar_pkg), "jaspar_pkg invalid")
  .wb_assert(!missing(species) && length(species) >= 1 && nzchar(as.character(species)[1]), "species is required")
  .wb_with_mutation_context(bundle = bundle, route = "ingestion", code = {
  .wb_require_pkg("TFBSTools", "JASPAR motif import")
  .wb_require_pkg(as.character(jaspar_pkg)[1], "JASPAR motif import")

  jaspar_obj <- .wb_motif_registry_exported_singleton(jaspar_pkg)
  opts <- list(species = as.character(species)[1], collection = as.character(collection)[1])
  motifs <- TFBSTools::getMatrixSet(jaspar_obj, opts)
  .wb_assert(length(motifs) > 0L,
             paste0("No motifs returned from ", jaspar_pkg, " for species='", species, "' collection='", collection, "'."))

  ids <- vapply(motifs, TFBSTools::ID, character(1))
  names0 <- vapply(motifs, TFBSTools::name, character(1))
  keep <- rep(TRUE, length(motifs))
  if (!is.null(motif_ids)) keep <- keep & ids %in% unique(as.character(motif_ids))
  if (!is.null(motif_names)) keep <- keep & names0 %in% unique(as.character(motif_names))
  motifs <- motifs[keep]
  .wb_assert(length(motifs) > 0L, "No motifs remained after motif_ids/motif_names filtering.")

  DBI::dbWithTransaction(bundle$con, {
  wb_motif_library_register(
    bundle = bundle,
    motif_library = motif_library,
    source_type = "jaspar",
    organism = organism,
    genome_build = genome_build,
    collection = collection,
    source_id = jaspar_pkg,
    source_version = gsub("^JASPAR", "", as.character(jaspar_pkg)[1]),
    description = description,
    created_by = created_by
  )

  for (i in seq_along(motifs)) {
    m <- motifs[[i]]
    key <- paste(TFBSTools::ID(m), TFBSTools::name(m), sep = "_")
    wb_motif_register(
      bundle = bundle,
      motif_library = motif_library,
      motif_key = key,
      motif_name = TFBSTools::name(m),
      motif_id = TFBSTools::ID(m),
      source_type = "jaspar",
      matrix_class = class(m)[1],
      payload_json = .wb_motif_payload_to_json(m),
      metadata = list(tags = as.list(m@tags)),
      created_by = created_by
    )
  }

  result <- list(
    motif_library = as.character(motif_library)[1],
    n_motifs = length(motifs),
    jaspar_pkg = as.character(jaspar_pkg)[1],
    collection = as.character(collection)[1]
  )
  .wb_record_declared_ingestion(
    bundle = bundle, transaction_name = "motif_library_import_jaspar",
    source = jaspar_pkg, created_by = created_by,
    additional_outputs = list(registry_manifest = wb_prim_obs_table(
      data.frame(motif_library = result$motif_library, n_motifs = result$n_motifs,
        stringsAsFactors = FALSE),
      table_type = "motif_library_import_manifest", entity_kind = "motif_library"
    )), transaction_open = TRUE
  )
  invisible(result)
  })
  })
}

.wb_motif_payload_to_json <- function(motif) {
  payload <- list(
    ID = TFBSTools::ID(motif),
    name = TFBSTools::name(motif),
    matrixClass = motif@matrixClass,
    strand = as.character(motif@strand),
    bg = as.list(motif@bg),
    tags = as.list(motif@tags),
    rownames = rownames(motif@profileMatrix),
    profileMatrix = unname(split(motif@profileMatrix, row(motif@profileMatrix)))
  )
  jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
}

.wb_motif_from_payload_json <- function(payload_json) {
  .wb_require_pkg("TFBSTools", "motif registry load")
  payload <- jsonlite::fromJSON(as.character(payload_json)[1], simplifyVector = TRUE)
  prof_raw <- payload$profileMatrix
  prof <- if (is.matrix(prof_raw)) {
    apply(prof_raw, c(1, 2), as.numeric)
  } else {
    do.call(rbind, lapply(prof_raw, as.numeric))
  }
  rn <- as.character(payload$rownames %||% c("A", "C", "G", "T"))
  .wb_assert(length(rn) == nrow(prof),
             "Motif payload rownames length does not match profileMatrix row count.")
  rownames(prof) <- rn
  TFBSTools::PFMatrix(
    ID = as.character(payload$ID %||% "Unknown")[1],
    name = as.character(payload$name %||% "Unknown")[1],
    matrixClass = as.character(payload$matrixClass %||% "Unknown")[1],
    strand = as.character(payload$strand %||% "+")[1],
    bg = unlist(payload$bg),
    tags = payload$tags %||% list(),
    profileMatrix = prof
  )
}

.wb_motifs_load_tfbstools <- function(bundle,
                                      motif_library,
                                      motif_keys = NULL) {
  tbl <- wb_motifs(bundle, motif_library = motif_library, motif_keys = motif_keys)
  .wb_assert(nrow(tbl) > 0L, paste0("No motifs found for motif_library '", motif_library, "'."))
  .wb_assert(all(!is.na(tbl$payload_json) & nzchar(tbl$payload_json)),
             paste0("One or more motifs in '", motif_library, "' are missing payload_json."))

  out <- lapply(tbl$payload_json, .wb_motif_from_payload_json)
  names(out) <- as.character(tbl$motif_key)
  do.call(TFBSTools::PFMatrixList, out)
}

#' List Motif Match Sets
#'
#' Canonical registry getter for motif-to-peak match sets.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Optional matrix filter.
#' @param motif_library Optional motif-library filter.
#' @param motif_match_set Optional exact motif-match-set key filter.
#'
#' @return A data frame of motif-match-set rows.
#' @export
wb_motif_match_sets <- function(bundle,
                                matrix_id = NULL,
                                motif_library = NULL,
                                motif_match_set = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)

  q <- paste(
    "SELECT motif_match_set, matrix_id, motif_library, organism, genome_build,",
    "genome_provider, match_engine, match_params_json, n_features, n_motifs,",
    "description, created_at, created_by FROM motif_match_sets"
  )
  where <- character(0)
  params <- list()

  if (!is.null(matrix_id)) {
    where <- c(where, "matrix_id = ?")
    params <- c(params, list(as.character(matrix_id)[1]))
  }
  if (!is.null(motif_library)) {
    where <- c(where, "motif_library = ?")
    params <- c(params, list(as.character(motif_library)[1]))
  }
  if (!is.null(motif_match_set)) {
    where <- c(where, "motif_match_set = ?")
    params <- c(params, list(as.character(motif_match_set)[1]))
  }
  if (length(where)) q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))
  q <- paste0(q, " ORDER BY motif_match_set;")

  out <- if (length(params)) DBI::dbGetQuery(con, q, params = params) else DBI::dbGetQuery(con, q)
  chr_cols <- intersect(c("motif_match_set", "matrix_id", "motif_library", "organism",
                          "genome_build", "genome_provider", "match_engine",
                          "match_params_json", "description", "created_at", "created_by"),
                        colnames(out))
  for (nm in chr_cols) out[[nm]] <- as.character(out[[nm]])
  out
}

#' Replace Motif Match Membership For A Match Set
#'
#' Canonical engine write path for a motif-to-peak match materialization.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_match_set Canonical engine key for this match set.
#' @param matrix_id Matrix identifier the matches are defined over.
#' @param motif_library Motif-library key used for matching.
#' @param matches Data frame with required columns `motif_key` and `feature_id`.
#' @param organism Optional organism label.
#' @param genome_build Optional genome-build label.
#' @param genome_provider Optional genome provider/ref label.
#' @param match_engine Match engine label, for example `"motifmatchr"`.
#' @param match_params Optional list or JSON string of matching parameters.
#' @param description Optional description.
#' @param created_by Optional author tag.
#'
#' @return Invisibly returns a small summary list.
#' @export
wb_motif_match_replace <- function(bundle,
                                   motif_match_set,
                                   matrix_id,
                                   motif_library,
                                   matches,
                                   organism = NULL,
                                   genome_build = NULL,
                                   genome_provider = NULL,
                                   match_engine = "motifmatchr",
                                   match_params = NULL,
                                   description = NULL,
                                   created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Motif-match registry mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "a declared motif ingestion transaction during bundle assembly")
  .wb_assert(is.character(motif_match_set) && length(motif_match_set) == 1 && nzchar(motif_match_set), "motif_match_set invalid")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(motif_library) && length(motif_library) == 1 && nzchar(motif_library), "motif_library invalid")
  .wb_assert(is.data.frame(matches), "matches must be a data.frame")
  .wb_assert(all(c("motif_key", "feature_id") %in% colnames(matches)),
             "matches must include motif_key and feature_id columns")
  .wb_assert(is.character(match_engine) && length(match_engine) == 1 && nzchar(match_engine), "match_engine invalid")

  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)

  lib_hit <- DBI::dbGetQuery(con, "SELECT motif_library FROM motif_libraries WHERE motif_library = ?;", params = list(motif_library))
  .wb_assert(nrow(lib_hit) == 1L, paste0("Unknown motif_library: ", motif_library))
  mat_hit <- DBI::dbGetQuery(con, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(mat_hit) == 1L, paste0("Unknown matrix_id: ", matrix_id))

  matches <- unique(matches[, c("motif_key", "feature_id"), drop = FALSE])
  matches$motif_key <- as.character(matches$motif_key)
  matches$feature_id <- as.character(matches$feature_id)
  .wb_assert(all(nzchar(matches$motif_key)) && all(nzchar(matches$feature_id)),
             "matches must contain non-empty motif_key and feature_id values")

  if (nrow(matches) > 0L) {
    motif_tbl <- wb_motifs(bundle, motif_library = motif_library, motif_keys = unique(matches$motif_key))
    .wb_assert(nrow(motif_tbl) == length(unique(matches$motif_key)),
               "matches includes motif_key values not present in motif_library")
    feat_tbl <- wb_features(bundle, matrix_id = matrix_id)
    .wb_assert(all(matches$feature_id %in% as.character(feat_tbl$feature_id)),
               "matches includes feature_id values not present in matrix_id")
  }

  params_json <- if (is.null(match_params)) {
    NULL
  } else if (is.character(match_params) && length(match_params) == 1L) {
    as.character(match_params)[1]
  } else {
    jsonlite::toJSON(match_params, auto_unbox = TRUE, null = "null")
  }
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  n_features <- length(unique(matches$feature_id))
  n_motifs <- length(unique(matches$motif_key))

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(
      con,
      "INSERT INTO motif_match_sets(
         motif_match_set, matrix_id, motif_library, organism, genome_build,
         genome_provider, match_engine, match_params_json, n_features, n_motifs,
         description, created_at, created_by
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(motif_match_set) DO UPDATE SET
         matrix_id = excluded.matrix_id,
         motif_library = excluded.motif_library,
         organism = excluded.organism,
         genome_build = excluded.genome_build,
         genome_provider = excluded.genome_provider,
         match_engine = excluded.match_engine,
         match_params_json = excluded.match_params_json,
         n_features = excluded.n_features,
         n_motifs = excluded.n_motifs,
         description = excluded.description,
         created_by = excluded.created_by;",
      params = list(
        as.character(motif_match_set)[1],
        as.character(matrix_id)[1],
        as.character(motif_library)[1],
        if (is.null(organism)) NA_character_ else as.character(organism)[1],
        if (is.null(genome_build)) NA_character_ else as.character(genome_build)[1],
        if (is.null(genome_provider)) NA_character_ else as.character(genome_provider)[1],
        as.character(match_engine)[1],
        if (is.null(params_json)) NA_character_ else as.character(params_json)[1],
        as.integer(n_features),
        as.integer(n_motifs),
        if (is.null(description)) NA_character_ else as.character(description)[1],
        now,
        if (is.null(created_by)) NA_character_ else as.character(created_by)[1]
      )
    )
    DBI::dbExecute(
      con,
      "DELETE FROM motif_match_membership WHERE motif_match_set = ?;",
      params = list(as.character(motif_match_set)[1])
    )
    if (nrow(matches) > 0L) {
      DBI::dbAppendTable(
        con,
        "motif_match_membership",
        data.frame(
          motif_match_set = rep(as.character(motif_match_set)[1], nrow(matches)),
          motif_key = matches$motif_key,
          feature_id = matches$feature_id,
          stringsAsFactors = FALSE
        )
      )
    }
  })

  invisible(list(
    motif_match_set = as.character(motif_match_set)[1],
    matrix_id = as.character(matrix_id)[1],
    motif_library = as.character(motif_library)[1],
    n_features = as.integer(n_features),
    n_motifs = as.integer(n_motifs)
  ))
}

#' Load Motif Match Membership
#'
#' Canonical getter for motif-to-peak membership rows.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param motif_match_set Motif-match-set key.
#' @param motif_keys Optional motif-key subset.
#'
#' @return A data frame with `motif_key` and `feature_id` membership rows.
#' @export
wb_motif_match_get <- function(bundle,
                               motif_match_set,
                               motif_keys = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(motif_match_set) && length(motif_match_set) == 1 && nzchar(motif_match_set), "motif_match_set invalid")
  con <- bundle$con
  .wb_ensure_motif_registry_tables(con)

  q <- "SELECT motif_match_set, motif_key, feature_id FROM motif_match_membership WHERE motif_match_set = ?"
  params <- list(as.character(motif_match_set)[1])
  if (!is.null(motif_keys)) {
    keys <- unique(as.character(motif_keys))
    q <- paste0(q, " AND motif_key IN ", .wb_sql_in_placeholders(length(keys)))
    params <- c(params, as.list(keys))
  }
  q <- paste0(q, " ORDER BY motif_key, feature_id;")

  out <- DBI::dbGetQuery(con, q, params = params)
  for (nm in intersect(c("motif_match_set", "motif_key", "feature_id"), colnames(out))) {
    out[[nm]] <- as.character(out[[nm]])
  }
  out
}

.wb_motif_match_matrix <- function(bundle,
                                   motif_match_set,
                                   feature_ids,
                                   motif_keys = NULL) {
  feature_ids <- as.character(feature_ids)
  .wb_assert(length(feature_ids) > 0L, "feature_ids must be non-empty")

  info <- wb_motif_match_sets(bundle, motif_match_set = motif_match_set)
  .wb_assert(nrow(info) == 1L, paste0("Unknown motif_match_set: ", motif_match_set))
  membership <- wb_motif_match_get(bundle, motif_match_set = motif_match_set, motif_keys = motif_keys)

  motif_order <- if (!is.null(motif_keys)) {
    unique(as.character(motif_keys))
  } else if (nrow(membership)) {
    unique(as.character(membership$motif_key))
  } else {
    unique(as.character(wb_motifs(bundle, motif_library = as.character(info$motif_library[1]))$motif_key))
  }
  .wb_assert(length(motif_order) > 0L, paste0("No motifs found for motif_match_set: ", motif_match_set))

  i <- match(as.character(membership$feature_id), feature_ids)
  j <- match(as.character(membership$motif_key), motif_order)
  keep <- !is.na(i) & !is.na(j)

  Matrix::sparseMatrix(
    i = i[keep],
    j = j[keep],
    x = rep(TRUE, sum(keep)),
    dims = c(length(feature_ids), length(motif_order)),
    dimnames = list(feature_ids, motif_order)
  )
}
