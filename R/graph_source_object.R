# Supplemental bounded durable authority for retained cell-axis sources. It
# preserves, but does not pretend to stream-recompute, legacy R-object identity.
.wb_graph_object_schema <- function(con) {
  for (table in c("artifact_labels", "artifact_pseudotime")) {
    if (!.wb_db_has_column(con, table, "payload_ordinal")) DBI::dbExecute(con,
      paste0("ALTER TABLE ", table, " ADD COLUMN payload_ordinal INTEGER ",
        "CHECK(payload_ordinal IS NULL OR (typeof(payload_ordinal)='integer' AND payload_ordinal>=0));"))
    DBI::dbExecute(con, paste0("CREATE UNIQUE INDEX IF NOT EXISTS ", table,
      "_payload_order ON ", table, "(artifact_id,payload_ordinal);"))
  }
  DBI::dbExecute(con, paste0("CREATE TABLE IF NOT EXISTS artifact_object_payload_meta (",
    "artifact_id TEXT PRIMARY KEY REFERENCES artifacts(artifact_id) DEFERRABLE INITIALLY DEFERRED,",
    "kind TEXT NOT NULL CHECK(kind IN ('cell_vector','cell_vector_family')),",
    "value_type TEXT NOT NULL,meta_present INTEGER NOT NULL CHECK(meta_present IN (0,1)),",
    "content_identity_json TEXT NOT NULL CHECK(length(CAST(content_identity_json AS BLOB))<=1024),",
    "closure_identity_json TEXT);"))
  DBI::dbExecute(con, paste0("CREATE TABLE IF NOT EXISTS artifact_object_metadata_chunks (",
    "artifact_id TEXT NOT NULL REFERENCES artifact_object_payload_meta(artifact_id) DEFERRABLE INITIALLY DEFERRED,",
    "chunk_ordinal INTEGER NOT NULL CHECK(typeof(chunk_ordinal)='integer' AND chunk_ordinal>=0),",
    "chunk BLOB NOT NULL CHECK(typeof(chunk)='blob' AND length(chunk)>0 AND length(chunk)<=65536),",
    "PRIMARY KEY(artifact_id,chunk_ordinal));"))
  if (!.wb_db_has_column(con, "prov_run_outputs", "retained_payload_identity_json"))
    DBI::dbExecute(con, "ALTER TABLE prov_run_outputs ADD COLUMN retained_payload_identity_json TEXT;")
  invisible(TRUE)
}

.wb_graph_object_metadata_hash <- function(con, artifact_id, budgets) {
  file <- tempfile("scwb_object_meta_")
  sink <- file(file, "wb")
  on.exit(if (file.exists(file)) unlink(file), add = TRUE)
  next_row <- "0"; bytes <- bit64::as.integer64(0)
  tryCatch({repeat {
    size <- DBI::dbGetQuery(con, paste0("SELECT length(chunk) n,typeof(chunk) type ",
      "FROM artifact_object_metadata_chunks WHERE artifact_id=? AND chunk_ordinal>=CAST(? AS INTEGER) ",
      "ORDER BY chunk_ordinal LIMIT 1;"), params = list(artifact_id, next_row))
    if (!nrow(size)) break
    .wb_graph_require(size$type[[1]] == "blob" && size$n[[1]] > 0 &&
      size$n[[1]] <= min(65536, budgets$partition_bytes),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Source chunk exceeds admission before decoding.")
    rows <- DBI::dbGetQuery(con, paste0("SELECT chunk_ordinal,chunk FROM artifact_object_metadata_chunks ",
      "WHERE artifact_id=? AND chunk_ordinal>=CAST(? AS INTEGER) ",
      "AND typeof(chunk)='blob' AND length(chunk)>0 AND length(chunk)<=? ",
      "ORDER BY chunk_ordinal LIMIT 1;"),
      params = list(artifact_id, next_row, min(65536, budgets$partition_bytes)))
    .wb_graph_require(nrow(rows) == 1L, "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Source chunk changed during admitted fetch.")
    if (!nrow(rows)) break
    .wb_graph_require(identical(as.character(rows$chunk_ordinal[[1]]), next_row) &&
      is.raw(rows$chunk[[1]]) && length(rows$chunk[[1]]) > 0 &&
      length(rows$chunk[[1]]) <= 65536 && length(rows$chunk[[1]]) <= budgets$partition_bytes,
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Metadata chunk closure or byte bound invalid.")
    bytes <- suppressWarnings(bytes + bit64::as.integer64(length(rows$chunk[[1]])))
    .wb_graph_require(!is.na(bytes) && bytes <= .wb_graph_i64(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Source metadata spill budget exceeded.")
    writeBin(rows$chunk[[1]], sink)
    flush(sink)
    .wb_graph_spill_admit(budgets)
    next_row <- .wb_graph_add_count(next_row, 1L)
  }
    flush(sink)
    .wb_graph_spill_admit(budgets)
  }, finally = close(sink))
  hidden <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_object_metadata_chunks WHERE artifact_id=? ",
    "AND (typeof(chunk_ordinal)!='integer' OR chunk_ordinal<0) LIMIT 1;"), params = list(artifact_id))
  .wb_graph_require(!nrow(hidden), "GRAPH_SOURCE_PAYLOAD_INVALID", "Hidden metadata chunk.")
  input <- file(file, "rb")
  sha <- tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
  list(sha256 = sha, bytes = as.character(bytes))
}

.wb_graph_object_closure <- function(con, artifact_id, budgets = .wb_graph_budgets()) {
  budgets <- .wb_graph_effective_budgets(con, budgets)
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_object_payload_meta WHERE artifact_id=? ",
    "AND (COALESCE(octet_length(kind),0)+COALESCE(octet_length(value_type),0)+",
    "COALESCE(octet_length(content_identity_json),0)+COALESCE(octet_length(closure_identity_json),0))>?;"),
    params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(!nrow(oversized), "GRAPH_RESOURCE_EXCEEDED", "Source header exceeds decoded admission.")
  header <- DBI::dbGetQuery(con, paste0("SELECT * FROM artifact_object_payload_meta WHERE artifact_id=? ",
    "AND (COALESCE(octet_length(kind),0)+COALESCE(octet_length(value_type),0)+",
    "COALESCE(octet_length(content_identity_json),0)+COALESCE(octet_length(closure_identity_json),0))<=?;"),
    params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(nrow(header) == 1L && header$kind[[1]] %in%
    c("cell_vector", "cell_vector_family"), "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Retained source lacks fresh bounded payload authority.")
  kind <- header$kind[[1]]
  table <- if (kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
  numeric_column <- if (kind == "cell_vector") "value_num" else "pseudotime"
  invalid_numeric <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM ", table,
    " WHERE artifact_id=? AND typeof(", numeric_column, ") NOT IN ('null','integer','real') LIMIT 1;"),
    params = list(artifact_id))
  .wb_graph_require(!nrow(invalid_numeric), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Retained scientific numeric payload has an unsupported SQLite type.")
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM ", table,
    " WHERE artifact_id=? AND (COALESCE(octet_length(cell_id),0)+",
    if (kind == "cell_vector") "COALESCE(octet_length(label),0)+COALESCE(octet_length(value_type),0)" else "COALESCE(octet_length(lineage_id),0)",
    "+512)>? LIMIT 1;"), params = list(artifact_id, budgets$partition_bytes))
  .wb_graph_require(!nrow(oversized), "GRAPH_RESOURCE_EXCEEDED", "Source record exceeds decoded byte admission.")
  invalid <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM ", table,
    " WHERE artifact_id=? AND (payload_ordinal IS NULL OR typeof(payload_ordinal)!='integer' ",
    "OR payload_ordinal<0) LIMIT 1;"), params = list(artifact_id))
  .wb_graph_require(!nrow(invalid), "GRAPH_SOURCE_PAYLOAD_INVALID", "Missing or hidden source ordinal.")
  content <- .wb_graph_parse(header$content_identity_json[[1]])
  .wb_graph_identity_assert(content, "scworkbench.content.object.canonical-json.v1")
  metadata <- .wb_graph_object_metadata_hash(con, artifact_id, budgets)
  .wb_graph_require(header$meta_present[[1]] %in% 0:1 &&
    (header$meta_present[[1]] == 1 || metadata$bytes == "0"),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Absent metadata has retained bytes.")
  value_type <- header$value_type[[1]]
  digest <- .wb_graph_token_hash(function(emit) {
    emit(paste0('{"content_identity":', .wb_operation_pack_canonical_json(content),
      ',"kind":', .wb_operation_pack_canonical_json(kind), ',"metadata":',
      .wb_operation_pack_canonical_json(list(present = header$meta_present[[1]] == 1,
        encoding = "R.serializeJSON.v1", sha256 = metadata$sha256)), ',"rows":['))
    next_row <- "0"; first <- TRUE
    # Preserve one ordered cursor and the exact canonical row preimage.
    # Precharge source/type/output carriers before bounded batches; the cursor
    # also enforces that byte bound if the source changes after admission.
    # Verification is recomputed at every authority boundary without a cache.
    byte_expression <- paste0("COALESCE(octet_length(cell_id),0)+",
      if (kind == "cell_vector") "COALESCE(octet_length(label),0)+COALESCE(octet_length(value_type),0)" else
        "COALESCE(octet_length(lineage_id),0)")
    admission <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n,COALESCE(MAX(",
      byte_expression, "),0) bytes FROM ", table, " WHERE artifact_id=?;"), params = list(artifact_id))
    maximum_bytes <- as.numeric(admission$bytes[[1L]])
    batch_rows <- min(64L, budgets$partition_rows)
    while (batch_rows > 1L) {
      carrier_bytes <- 4096 + batch_rows * 1536
      encoded_bytes <- 2 + batch_rows * (6 * maximum_bytes + 256)
      reservation_bytes <- carrier_bytes + 8 * encoded_bytes
      if (reservation_bytes <= 8 * budgets$partition_bytes &&
          6 * maximum_bytes + 256 <= budgets$partition_bytes) break
      batch_rows <- batch_rows - 1L
    }
    batch_enabled <- batch_rows > 1L
    .wb_graph_storage_fault("source_object_batch_admission", list(con = con, budgets = budgets,
      rows = batch_rows, enabled = batch_enabled, maximum_source_bytes = maximum_bytes,
      reservation_bytes = if (batch_enabled) reservation_bytes else 0,
      decoded_reservation_bytes = 8 * budgets$partition_bytes))
    cursor <- DBI::dbSendQuery(con, paste0("SELECT payload_ordinal,cell_id,",
        if (kind == "cell_vector") "label,value_type,value_num" else "lineage_id,pseudotime",
        " FROM ", table, " WHERE artifact_id=? ",
        "AND typeof(", numeric_column, ") IN ('null','integer','real') AND ",
        "COALESCE(octet_length(cell_id),0)+",
        if (kind == "cell_vector") "COALESCE(octet_length(label),0)+COALESCE(octet_length(value_type),0)" else "COALESCE(octet_length(lineage_id),0)",
        "+512<=? AND ", byte_expression, "<=? ORDER BY payload_ordinal;"),
        params = list(artifact_id, budgets$partition_bytes, maximum_bytes))
    tryCatch(repeat {
      .wb_graph_storage_fault("source_object_batch_fetch", list(con = con, budgets = budgets,
        rows = batch_rows, enabled = batch_enabled,
        reservation_bytes = if (batch_enabled) reservation_bytes else 0,
        decoded_reservation_bytes = 8 * budgets$partition_bytes))
      rows <- DBI::dbFetch(cursor, n = batch_rows)
      if (!nrow(rows)) break
      if (batch_enabled) {
        expected_ordinals <- as.character(bit64::as.integer64(next_row) +
          bit64::as.integer64(seq.int(0L, nrow(rows) - 1L)))
        .wb_graph_require(identical(as.character(rows$payload_ordinal), expected_ordinals),
          "GRAPH_SOURCE_PAYLOAD_INVALID", "Source payload order is not dense.")
        string_fields <- if (kind == "cell_vector") c("cell_id", "label", "value_type") else c("cell_id", "lineage_id")
        .wb_graph_require(all(vapply(rows[string_fields], is.character, logical(1))),
          "GRAPH_SOURCE_PAYLOAD_INVALID", "Source string carriers have unsupported storage types.")
        if (kind == "cell_vector") .wb_graph_require(all(rows$value_type == value_type),
          "GRAPH_SOURCE_PAYLOAD_INVALID", "Source scientific value types disagree.")
        .wb_graph_require(!anyNA(rows[string_fields]), "GRAPH_RESOURCE_EXCEEDED", "Oversized scalar token.")
        for (field in string_fields) .wb_operation_pack_assert(!anyNA(iconv(rows[[field]],
          from = "", to = "UTF-8", sub = NA_character_)), "OPERATION_PACK_CANONICAL_STRING_INVALID",
          "Canonical identity strings must be valid UTF-8.", class = "wb_operation_pack_identity_error")
        values <- vapply(wb_graph_encode_finite_f64(rows[[numeric_column]]),
          function(value) if (is.null(value)) NA_character_ else value, character(1))
        framed <- if (kind == "cell_vector") data.frame(cell_id = rows$cell_id,
          label = rows$label, ordinal = expected_ordinals, value_num = values,
          value_type = rows$value_type, stringsAsFactors = FALSE) else
          data.frame(cell_id = rows$cell_id, key = rows$lineage_id,
            ordinal = expected_ordinals, value = values, stringsAsFactors = FALSE)
        json <- as.character(jsonlite::toJSON(framed, dataframe = "rows",
          auto_unbox = TRUE, null = "null", na = "null"))
        .wb_graph_require(nchar(json, type = "bytes") <= encoded_bytes,
          "GRAPH_RESOURCE_EXCEEDED", "Source closure batch exceeded pre-admitted encoded size.")
        if (!first) emit(",")
        emit(substr(json, 2L, nchar(json) - 1L))
        first <- FALSE; next_row <- .wb_graph_add_count(next_row, nrow(rows))
        next
      }
      .wb_graph_require(identical(as.character(rows$payload_ordinal[[1]]), next_row),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Source payload order is not dense.")
      row <- if (kind == "cell_vector") list(ordinal = next_row,
        cell_id = rows$cell_id[[1]], label = rows$label[[1]],
        value_type = rows$value_type[[1]],
        value_num = wb_graph_encode_finite_f64(rows$value_num[[1]])[[1]]) else
        list(ordinal = next_row, cell_id = rows$cell_id[[1]], key = rows$lineage_id[[1]],
          value = wb_graph_encode_finite_f64(rows$pseudotime[[1]])[[1]])
      if (kind == "cell_vector") .wb_graph_require(identical(row$value_type, value_type),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Source scientific value types disagree.")
      .wb_graph_materialization_admit(row, budgets$partition_bytes)
      if (!first) emit(",")
      emit(.wb_operation_pack_canonical_json(row))
      first <- FALSE; next_row <- .wb_graph_add_count(next_row, 1L)
    }, finally = DBI::dbClearResult(cursor))
    .wb_graph_require(identical(as.character(admission$n[[1L]]), next_row),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Source changed across admitted closure observation.")
    emit(paste0('],"schema":"scworkbench.artifact.ordered-object-payload.v1","value_type":',
      .wb_operation_pack_canonical_json(value_type), "}"))
  }, budgets)
  list(scheme = "scworkbench.artifact.ordered-object-payload.canonical-json.v1", sha256 = digest)
}

.wb_graph_object_retain <- function(bundle, artifact_id, prim) {
  con <- bundle$con
  identity <- list(scheme = "scworkbench.content.object.canonical-json.v1",
    sha256 = .wb_prov_sha256_object(unclass(prim)))
  present <- "meta" %in% names(unclass(prim))
  DBI::dbExecute(con, paste0("INSERT INTO artifact_object_payload_meta ",
    "(artifact_id,kind,value_type,meta_present,content_identity_json) VALUES(?,?,?,?,?);"),
    params = list(artifact_id, prim$kind, prim$value_type, as.integer(present),
      .wb_operation_pack_canonical_json(identity)))
  if (present) {
    bytes <- charToRaw(enc2utf8(jsonlite::serializeJSON(prim$meta, digits = NA)))
    ordinal <- "0"
    for (start in seq.int(1L, length(bytes), by = 65536L)) {
      chunk <- bytes[seq.int(start, min(length(bytes), start + 65535L))]
      DBI::dbExecute(con, "INSERT INTO artifact_object_metadata_chunks VALUES(?,?,?);",
        params = list(artifact_id, bit64::as.integer64(ordinal), list(chunk)))
      ordinal <- .wb_graph_add_count(ordinal, 1L)
    }
  }
  closure <- .wb_graph_object_closure(con, artifact_id)
  DBI::dbExecute(con, "UPDATE artifact_object_payload_meta SET closure_identity_json=? WHERE artifact_id=?;",
    params = list(.wb_operation_pack_canonical_json(closure), artifact_id))
  invisible(closure)
}

.wb_graph_object_verify <- function(con, artifact_id, budgets = .wb_graph_budgets(),
                                    require_certificate = TRUE) {
  budgets <- .wb_graph_effective_budgets(con, budgets)
  actual <- .wb_graph_object_closure(con, artifact_id, budgets)
  header <- DBI::dbGetQuery(con,
    paste0("SELECT closure_identity_json,content_identity_json FROM artifact_object_payload_meta ",
      "WHERE artifact_id=? AND COALESCE(octet_length(closure_identity_json),0)+",
      "COALESCE(octet_length(content_identity_json),0)<=?;"),
    params = list(artifact_id, budgets$partition_bytes))
  same <- function(text) identical(.wb_graph_parse(text), actual)
  .wb_graph_require(nrow(header) == 1L && same(header$closure_identity_json[[1]]),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Actual source closure disagrees with its retained payload.")
  original <- .wb_graph_parse(header$content_identity_json[[1]])
  .wb_graph_certificate_scan(con, artifact_id, function(certificate) {
    text <- certificate$retained_payload_identity_json[[1]]
    if (is.na(text) && !require_certificate && isTRUE(RSQLite::sqliteIsTransacting(con))) return(invisible(NULL))
    .wb_graph_require(!is.na(text) && same(text) &&
      identical(certificate$content_identity_scheme[[1]], original$scheme) &&
      identical(certificate$content_sha256[[1]], original$sha256), "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Actual source closure disagrees with independently retained output evidence.")
  }, budgets, required = require_certificate)
  actual
}

.wb_graph_certificate_scan <- function(con, artifact_id, callback,
    budgets = .wb_graph_budgets(), required = TRUE, include_verification = FALSE) {
  fields <- c("content_identity_scheme", "content_sha256", "retained_payload_identity_json")
  if (include_verification) fields <- c(fields, "verification_level", "verification_status")
  byte_expression <- paste0("COALESCE(octet_length(", fields, "),0)", collapse = "+")
  hidden <- DBI::dbGetQuery(con,
    "SELECT 1 FROM prov_run_outputs WHERE artifact_id=? AND rowid<=0 LIMIT 1;",
    params = list(artifact_id))
  .wb_graph_require(!nrow(hidden), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Hidden nonpositive provenance output rowid.")
  after <- bit64::as.integer64(-1); count <- "0"
  repeat {
    size <- DBI::dbGetQuery(con, paste0("SELECT rowid,", byte_expression, " n FROM prov_run_outputs ",
      "WHERE artifact_id=? AND rowid>? ORDER BY rowid LIMIT 1;"),
      params = list(artifact_id, after))
    if (!nrow(size)) break
    .wb_graph_require(size$n[[1]] <= budgets$partition_bytes, "GRAPH_RESOURCE_EXCEEDED",
      "Retained output certificate exceeds byte admission before decoding.")
    certificate <- DBI::dbGetQuery(con, paste0("SELECT ", paste(fields, collapse = ","), " ",
      "FROM prov_run_outputs WHERE rowid=? AND ",
      byte_expression, "<=?;"),
      params = list(size$rowid[[1]], budgets$partition_bytes))
    .wb_graph_require(nrow(certificate) == 1L, "GRAPH_RESOURCE_EXCEEDED",
      "Retained certificate changed during admitted fetch.")
    callback(certificate)
    after <- bit64::as.integer64(size$rowid[[1]]); count <- .wb_graph_add_count(count, 1L)
  }
  .wb_graph_require(!required || count != "0", "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Retained payload lacks independently issued provenance output evidence.")
  invisible(count)
}

# This is a materializing loader convenience, not the scalable grant path. It
# reads the same actual bytes used by bounded verification, never a shadow meta.
.wb_graph_object_has_attestation <- function(con, artifact_id, kind) {
  table <- if (kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
  queries <- c(
    "SELECT 1 FROM artifact_object_payload_meta WHERE artifact_id=? LIMIT 1;",
    "SELECT 1 FROM artifact_object_metadata_chunks WHERE artifact_id=? LIMIT 1;",
    "SELECT 1 FROM prov_run_outputs WHERE artifact_id=? AND retained_payload_identity_json IS NOT NULL LIMIT 1;",
    paste0("SELECT 1 FROM ", table,
      " WHERE artifact_id=? AND payload_ordinal IS NOT NULL LIMIT 1;"))
  any(vapply(queries, function(query)
    nrow(DBI::dbGetQuery(con, query, params = list(artifact_id))) != 0L, logical(1)))
}

.wb_graph_legacy_object_identity_assert <- function(con, artifact_id, prim) {
  observed <- .wb_prov_sha256_object(unclass(prim))
  scheme <- unname(.wb_content_identity_schemes()[["object"]])
  .wb_graph_certificate_scan(con, artifact_id, function(certificate) {
    if (is.na(certificate$content_identity_scheme[[1L]]) &&
        is.na(certificate$content_sha256[[1L]]) &&
        identical(certificate$verification_level[[1L]], "structural") &&
        identical(certificate$verification_status[[1L]], "legacy_structural_only"))
      return(invisible(NULL))
    .wb_graph_require(identical(certificate$content_identity_scheme[[1L]], scheme) &&
      identical(certificate$content_sha256[[1L]], observed),
      "ARTIFACT_CONTENT_IDENTITY_MISMATCH",
      "Ordinary legacy object content differs from independently retained output evidence.")
  }, required = TRUE, include_verification = TRUE)
  invisible(TRUE)
}

.wb_graph_object_restore <- function(con, artifact_id, df, descriptor, kind) {
  .wb_graph_object_verify(con, artifact_id,
    require_certificate = !isTRUE(RSQLite::sqliteIsTransacting(con)))
  table <- if (kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
  keys <- DBI::dbGetQuery(con, paste0("SELECT cell_id",
    if (kind == "cell_vector_family") ",lineage_id" else "",
    " FROM ", table, " WHERE artifact_id=? ORDER BY payload_ordinal;"),
    params = list(artifact_id))
  tokens <- function(rows) .wb_object_row_key_tokens(if (kind == "cell_vector")
    data.frame(cell_id = rows$cell_id) else
    data.frame(key = rows$lineage_id, cell_id = rows$cell_id))
  .wb_graph_require(identical(tokens(df), tokens(keys)), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Scientific payload ordinals disagree with the durable row-order descriptor.")
  header <- DBI::dbGetQuery(con,
    "SELECT meta_present,value_type FROM artifact_object_payload_meta WHERE artifact_id=?;",
    params = list(artifact_id))
  .wb_graph_require(!is.null(descriptor) &&
    identical(isTRUE(descriptor$meta_present), header$meta_present[[1]] == 1L) &&
    identical(descriptor$value_type, header$value_type[[1]]),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Source descriptor type/metadata presence disagrees.")
  chunks <- DBI::dbGetQuery(con,
    "SELECT chunk FROM artifact_object_metadata_chunks WHERE artifact_id=? ORDER BY chunk_ordinal;",
    params = list(artifact_id))
  bytes <- do.call(c, chunks$chunk)
  text <- if (length(bytes)) rawToChar(bytes) else ""
  .wb_graph_require(identical(text, if (isTRUE(descriptor$meta_present))
    descriptor$meta_r_json else ""), "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Actual metadata bytes disagree with the legacy durable descriptor.")
  if (isTRUE(descriptor$meta_present)) jsonlite::unserializeJSON(text) else NULL
}
