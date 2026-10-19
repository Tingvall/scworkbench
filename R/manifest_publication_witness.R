# An invocation may avoid repeating a successful manifest publication, but this
# never substitutes for payload authentication, recovery or explicit validation.
.wb_manifest_publication_epoch <- function(bundle) {
  con <- bundle$con
  if (!DBI::dbIsValid(con) || isTRUE(RSQLite::sqliteIsTransacting(con))) return(NULL)
  key <- .wb_writer_lock_key(bundle)
  if (!.wb_writer_lock_held(bundle)) return(NULL)
  entry <- get(key, envir = .wb_writer_lock_state$held, inherits = FALSE)
  owner <- .wb_writer_lock_read_metadata(entry$lock_path)
  if (is.null(owner) || !identical(as.character(owner$owner_token),
      as.character(entry$token))) return(NULL)
  exact <- function(x) {
    .wb_assert(is.numeric(x) && !is.object(x) && length(x) == 1L &&
      !is.na(x) && is.finite(x) && x >= 0 && x <= 2^53 - 1 && x == floor(x),
      "Publication witness SQL counter is unavailable or inexact.")
    x
  }
  databases <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  # TEMP may not yet appear in database_list. Its real definitions must always
  # participate; schema_version alone can be reset by callers and DDL rollback.
  names <- unique(c("main", "temp", as.character(databases$name)))
  schemas <- setNames(lapply(names, function(name) {
    quoted <- as.character(DBI::dbQuoteIdentifier(con, name))
    list(version = exact(DBI::dbGetQuery(con,
      paste0("PRAGMA ", quoted, ".schema_version;"))[[1L]]),
      data = exact(DBI::dbGetQuery(con,
        paste0("PRAGMA ", quoted, ".data_version;"))[[1L]]),
      sql = DBI::dbGetQuery(con, paste0("SELECT type,name,tbl_name,sql FROM ",
        quoted, ".sqlite_schema ORDER BY type,name,tbl_name,sql;")))
  }), names)
  observed <- list(connection = con@ref, writer_key = key, writer_token = entry$token,
    changes = exact(DBI::dbGetQuery(con, "SELECT total_changes();")[[1L]]),
    data = exact(DBI::dbGetQuery(con, "PRAGMA main.data_version;")[[1L]]),
    databases = databases, schemas = schemas)
  # Inspecting temp.sqlite_schema can register empty TEMP; scoped sorter
  # restoration can detach it. Describe the ACTUAL state after our own reads,
  # without discarding TEMP evidence or concealing another association change.
  final_databases <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  non_temp <- function(rows) {
    rows <- rows[rows$name != "temp", , drop = FALSE]
    rownames(rows) <- NULL
    rows
  }
  if (!identical(non_temp(databases), non_temp(final_databases)) ||
      anyDuplicated(final_databases$name) ||
      !all(final_databases$name %in% names(schemas))) return(NULL)
  observed$databases <- final_databases
  observed
}

.wb_manifest_publication_sha256 <- function(bundle) {
  status <- .wb_path_status(bundle$dir, "manifest.json", expected_type = "file",
    must_exist = TRUE, purpose = "published manifest witness")
  .wb_assert(isTRUE(status$ok), "Published manifest witness path is unavailable or unsafe.")
  digest::digest(file = status$absolute, algo = "sha256", serialize = FALSE)
}

.wb_manifest_publication_reusable <- function(bundle) {
  con <- bundle$con
  witness <- con@ref$wb_manifest_publication_witness
  valid <- tryCatch({
    before <- .wb_manifest_publication_epoch(bundle)
    if (is.null(witness) || is.null(before) || !identical(before, witness$epoch)) FALSE else {
      sha <- .wb_manifest_publication_sha256(bundle)
      after <- .wb_manifest_publication_epoch(bundle)
      !is.null(after) && identical(before, after) && identical(sha, witness$sha256)
    }
  }, error = function(error) FALSE)
  if (!isTRUE(valid)) con@ref$wb_manifest_publication_witness <- NULL
  isTRUE(valid)
}
