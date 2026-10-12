# Isolated prototype only; no installed or public source route changes.
.wb_graph_object_closure_batched <- function(con, artifact_id, budgets = .wb_graph_budgets()) {
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
    # Compile one ordered cursor rather than a query for every source row.
    # Global byte/type checks above AND the cursor's predicates enforce
    # pre-decoding admission. Fetch still holds exactly one admitted row;
    # source verification is not cached across authority boundaries.
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

