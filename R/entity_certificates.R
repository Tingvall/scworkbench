.wb_certificate_schema <- function() "scworkbench.provenance.entity_certificate.v1"

.wb_certificate_state <- function(status, reason = NULL, ...) {
  out <- c(list(status = as.character(status)[1]), list(...))
  if (!is.null(reason)) out$reason <- as.character(reason)[1]
  out
}

.wb_certificate_json <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (!nzchar(txt)) return(.wb_certificate_state("unavailable", "not_recorded"))
  tryCatch(
    .wb_certificate_state("available", value = jsonlite::fromJSON(txt, simplifyVector = FALSE)),
    error = function(e) .wb_certificate_state("corrupt", "malformed_json")
  )
}

.wb_certificate_scalar <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]]) || !nzchar(as.character(x[[1]]))) NULL else as.character(x[[1]])
}

.wb_certificate_relative_path <- function(path) {
  path <- .wb_certificate_scalar(path)
  if (is.null(path)) return(.wb_certificate_state("not_applicable"))
  if (.wb_path_is_absolute(path) || any(strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1]] == "..")) {
    return(.wb_certificate_state("corrupt", "path_is_not_bundle_relative"))
  }
  .wb_certificate_state("available", path = gsub("\\\\", "/", path))
}

.wb_certificate_rows <- function(x) {
  if (!is.data.frame(x) || !nrow(x)) return(list())
  x <- x[do.call(order, c(lapply(x, function(z) as.character(z)), list(na.last = TRUE))), , drop = FALSE]
  rownames(x) <- NULL
  lapply(seq_len(nrow(x)), function(i) {
    z <- as.list(x[i, , drop = FALSE])
    lapply(z, function(v) if (!length(v) || is.na(v[[1]])) NULL else unname(v[[1]]))
  })
}

.wb_certificate_query <- function(con, table, sql, params = list()) {
  if (!.wb_table_exists(con, table)) return(data.frame(stringsAsFactors = FALSE))
  if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
}

.wb_certificate_node_id <- function(kind, id) {
  graph_kind <- if (identical(kind, "model")) "model_ref" else kind
  paste0(graph_kind, ":", id)
}

.wb_certificate_public_kind <- function(kind) ifelse(kind == "model_ref", "model", kind)

.wb_certificate_relationship_item <- function(row, endpoint) {
  node_id <- as.character(row[[endpoint]])
  bits <- strsplit(node_id, ":", fixed = TRUE)[[1]]
  list(
    kind = .wb_certificate_public_kind(bits[[1]]),
    id = paste(bits[-1L], collapse = ":"),
    node_id = sub("^model_ref:", "model:", node_id),
    relationship_type = as.character(row$edge_type),
    binding = .wb_certificate_scalar(row$binding) %||% .wb_certificate_scalar(row$label),
    run_id = .wb_certificate_scalar(row$run_id),
    snapshot_id = .wb_certificate_scalar(row$snapshot_id)
  )
}

.wb_certificate_reachable <- function(edges, start, upstream) {
  if (!nrow(edges)) return(character())
  seen <- start; frontier <- start
  while (length(frontier)) {
    next_ids <- if (isTRUE(upstream)) edges$from[edges$to %in% frontier] else edges$to[edges$from %in% frontier]
    next_ids <- sort(unique(as.character(next_ids[!is.na(next_ids) & nzchar(next_ids)])))
    next_ids <- setdiff(next_ids, seen)
    if (!length(next_ids)) break
    seen <- c(seen, next_ids); frontier <- next_ids
  }
  setdiff(seen, start)
}

.wb_certificate_relationships <- function(graph, node_id) {
  edges <- graph$edges
  incoming <- if (nrow(edges)) edges[as.character(edges$to) == node_id, , drop = FALSE] else edges
  outgoing <- if (nrow(edges)) edges[as.character(edges$from) == node_id, , drop = FALSE] else edges
  upstream <- .wb_certificate_reachable(edges, node_id, TRUE)
  downstream <- .wb_certificate_reachable(edges, node_id, FALSE)
  node_item <- function(id) {
    bits <- strsplit(id, ":", fixed = TRUE)[[1]]
    list(kind = .wb_certificate_public_kind(bits[[1]]), id = paste(bits[-1L], collapse = ":"), node_id = sub("^model_ref:", "model:", id))
  }
  list(
    immediate_inputs = .wb_certificate_state("available", items = lapply(seq_len(nrow(incoming)), function(i) .wb_certificate_relationship_item(incoming[i, , drop = FALSE], "from"))),
    immediate_outputs = .wb_certificate_state("available", items = lapply(seq_len(nrow(outgoing)), function(i) .wb_certificate_relationship_item(outgoing[i, , drop = FALSE], "to"))),
    upstream = .wb_certificate_state("available", count = length(upstream), items = lapply(sort(upstream), node_item)),
    downstream = .wb_certificate_state("available", count = length(downstream), items = lapply(sort(downstream), node_item))
  )
}

.wb_certificate_lifecycle <- function(con, kind, id) {
  db_kind <- if (identical(kind, "model")) "model_ref" else kind
  kinds <- if (identical(kind, "model")) c("model_ref", "model") else db_kind
  marks <- paste(rep("?", length(kinds)), collapse = ",")
  row <- .wb_certificate_query(con, "entity_lifecycle",
    paste0("SELECT * FROM entity_lifecycle WHERE entity_kind IN (", marks, ") AND entity_id = ? ORDER BY entity_kind;"), c(as.list(kinds), list(id)))
  supers <- .wb_certificate_query(con, "entity_supersessions",
    paste0("SELECT * FROM entity_supersessions WHERE (successor_kind IN (", marks, ") AND successor_id = ?) OR (predecessor_kind IN (", marks, ") AND predecessor_id = ?) ORDER BY created_at, successor_kind, successor_id, predecessor_kind, predecessor_id;"),
    c(as.list(kinds), list(id), as.list(kinds), list(id)))
  tomb <- .wb_certificate_query(con, "entity_tombstones",
    paste0("SELECT * FROM entity_tombstones WHERE entity_kind IN (", marks, ") AND entity_id = ? ORDER BY entity_kind;"), c(as.list(kinds), list(id)))
  list(
    state = if (nrow(row)) as.character(row$lifecycle_state[[1]]) else if (identical(kind, "run") || identical(kind, "external_source")) "persisted" else "current",
    record = if (nrow(row)) .wb_certificate_state("available", value = .wb_certificate_rows(row)[[1]]) else .wb_certificate_state("unavailable", "not_recorded"),
    supersessions = .wb_certificate_state("available", items = .wb_certificate_rows(supers)),
    tombstone = if (nrow(tomb)) .wb_certificate_state("available", value = .wb_certificate_rows(tomb)[[1]]) else .wb_certificate_state("not_applicable")
  )
}

.wb_certificate_producer <- function(con, kind, id) {
  producer_history <- NULL
  if (identical(kind, "run")) return(.wb_certificate_state("not_applicable"))
  if (identical(kind, "external_source")) {
    rows <- .wb_certificate_query(con, "prov_run_entity_bindings",
      "SELECT snapshot_id, run_id, binding_name, relationship_type FROM prov_run_entity_bindings WHERE entity_kind = 'external_source' AND entity_id = ? AND relationship_type = 'CONSUMES' ORDER BY snapshot_id, run_id, binding_name;", list(id))
    return(if (nrow(rows)) .wb_certificate_state("not_applicable", reason = "external_sources_are_consumed_not_produced", consuming_runs = .wb_certificate_rows(rows)) else .wb_certificate_state("unavailable", "no_consuming_ingestion_run"))
  }
  if (identical(kind, "metadata_field")) {
    history <- .wb_certificate_query(con, "metadata_field_identities", paste(
      "SELECT i.identity_id,i.identity_version,i.content_sha256 AS content_hash,",
      "i.content_identity_scheme,i.registry_sha256,i.n_cells,i.snapshot_id,i.run_id,",
      "b.binding_name AS output_name,'metadata_field' AS primitive_kind",
      "FROM metadata_field_identities i LEFT JOIN prov_run_entity_bindings b",
      "ON b.snapshot_id=i.snapshot_id AND b.run_id=i.run_id",
      "AND b.entity_kind='metadata_field' AND b.entity_id=i.field_id",
      "AND b.relationship_type IN ('PRODUCES','MATERIALIZES')",
      "AND b.content_hash=i.content_sha256 AND b.content_identity_scheme=i.content_identity_scheme",
      "WHERE i.field_id=? ORDER BY i.identity_version;"
    ), list(id))
    current <- .wb_certificate_query(con, "metadata_field_identities", paste(
      "SELECT i.identity_id,i.identity_version,i.content_sha256 AS content_hash,",
      "i.content_identity_scheme,i.registry_sha256,i.n_cells,i.snapshot_id,i.run_id,",
      "b.binding_name AS output_name,'metadata_field' AS primitive_kind",
      "FROM metadata_field_identities i JOIN prov_run_entity_bindings b",
      "ON b.snapshot_id=i.snapshot_id AND b.run_id=i.run_id",
      "AND b.entity_kind='metadata_field' AND b.entity_id=i.field_id",
      "AND b.relationship_type IN ('PRODUCES','MATERIALIZES')",
      "AND b.content_hash=i.content_sha256 AND b.content_identity_scheme=i.content_identity_scheme",
      "WHERE i.field_id=? AND i.is_current=1;"
    ), list(id))
    if (!nrow(current)) return(.wb_certificate_state("unavailable", "no_current_metadata_identity_producer"))
    if (nrow(current) != 1L) return(.wb_certificate_state("corrupt", "current_metadata_producer_is_not_unique", candidates = .wb_certificate_rows(current)))
    rows <- current
    producer_history <- .wb_certificate_rows(history)
  } else if (identical(kind, "artifact")) {
    rows <- .wb_certificate_query(con, "prov_run_outputs",
      paste0("SELECT snapshot_id, run_id, output_name, primitive_kind, output_hash, ", .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con), " FROM prov_run_outputs WHERE artifact_id = ? ORDER BY snapshot_id, run_id, output_name;"), list(id))
  } else {
    db_kind <- if (identical(kind, "model")) "model_ref" else kind
    rows <- .wb_certificate_query(con, "prov_run_entity_bindings",
      "SELECT snapshot_id, run_id, binding_name AS output_name, entity_kind AS primitive_kind, content_hash, content_identity_scheme FROM prov_run_entity_bindings WHERE entity_kind = ? AND entity_id = ? AND relationship_type IN ('PRODUCES','MATERIALIZES') ORDER BY snapshot_id, run_id, binding_name;", list(db_kind, id))
  }
  if (!nrow(rows)) return(.wb_certificate_state("unavailable", "no_canonical_producer_binding"))
  if (nrow(rows) != 1L) return(.wb_certificate_state("corrupt", "producer_binding_is_not_unique", candidates = .wb_certificate_rows(rows)))
  rid <- as.character(rows$run_id[[1]]); sid <- as.character(rows$snapshot_id[[1]])
  if (!identical(kind, "artifact")) {
    output <- .wb_certificate_query(con, "prov_run_outputs",
      paste0("SELECT ", .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con), " FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? AND output_name = ?;"),
      list(sid, rid, as.character(rows$output_name[[1]])))
    if (nrow(output) == 1L) for (nm in names(output)) rows[[nm]] <- output[[nm]][[1L]]
  }
  run <- .wb_certificate_query(con, "prov_runs", "SELECT op_name, op_version, contract_json, contract_hash, contract_hash_scheme FROM prov_runs WHERE snapshot_id = ? AND run_id = ?;", list(sid, rid))
  .wb_certificate_state("available", run_id = rid, snapshot_id = sid,
    output = .wb_certificate_rows(rows)[[1]],
    history = producer_history,
    operation = if (nrow(run)) list(name = .wb_certificate_scalar(run$op_name), version = .wb_certificate_scalar(run$op_version), contract = .wb_certificate_json(run$contract_json), contract_hash = .wb_certificate_scalar(run$contract_hash), contract_hash_scheme = .wb_certificate_scalar(run$contract_hash_scheme)) else .wb_certificate_state("corrupt", "producer_run_missing"),
    run = if (nrow(run)) .wb_certificate_run(con, rid) else .wb_certificate_state("corrupt", "producer_run_missing"))
}

.wb_certificate_run <- function(con, id) {
  rows <- .wb_certificate_query(con, "prov_runs", paste0("SELECT *, ", .wb_prov_run_identity_select(con), " FROM prov_runs WHERE run_id = ? ORDER BY snapshot_id;"), list(id))
  if (!nrow(rows)) return(NULL)
  # A globally unique run may occur in several snapshots only with identical evidence.
  row <- rows[1, , drop = FALSE]
  outputs <- .wb_certificate_query(con, "prov_run_outputs", paste0("SELECT snapshot_id, output_name, primitive_kind, artifact_id, output_hash, ", .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con), " FROM prov_run_outputs WHERE run_id = ? ORDER BY snapshot_id, output_name;"), list(id))
  edges <- .wb_certificate_query(con, "prov_run_edges", "SELECT snapshot_id, parent_run_id, child_run_id, edge_type, edge_label FROM prov_run_edges WHERE parent_run_id = ? OR child_run_id = ? ORDER BY snapshot_id, parent_run_id, child_run_id, edge_type, edge_label;", list(id, id))
  receipts <- .wb_certificate_query(con, "prov_replay_equivalence_results", "SELECT * FROM prov_replay_equivalence_results WHERE original_run_id = ? OR replay_run_id = ? ORDER BY original_run_id, original_output_name, replay_run_id;", list(id, id))
  list(
    operation = list(name = .wb_certificate_scalar(row$op_name), version = .wb_certificate_scalar(row$op_version), contract = .wb_certificate_json(row$contract_json), contract_hash = .wb_certificate_scalar(row$contract_hash), contract_hash_scheme = .wb_certificate_scalar(row$contract_hash_scheme)),
    parameters = .wb_certificate_json(row$params_json),
    symbolic_inputs = .wb_certificate_json(row$symbolic_inputs_json),
    resolved_execution_inputs = .wb_certificate_json(row$execution_inputs_json),
    recorded_inputs = .wb_certificate_json(row$inputs_json),
    runtime_attestation = .wb_certificate_json(row$runtime_fingerprint_json),
    identity = list(run_hash = .wb_certificate_scalar(row$run_hash), run_hash_scheme = .wb_certificate_scalar(row$run_hash_scheme)),
    snapshots = sort(unique(as.character(rows$snapshot_id))),
    outputs = .wb_certificate_state("available", items = .wb_certificate_rows(outputs)),
    parent_runs = sort(unique(as.character(edges$parent_run_id[edges$child_run_id == id]))),
    child_runs = sort(unique(as.character(edges$child_run_id[edges$parent_run_id == id]))),
    replay_equivalence = if (nrow(receipts)) .wb_certificate_state("available", items = .wb_certificate_rows(receipts)) else .wb_certificate_state("unavailable", "no_replay_receipt")
  )
}

.wb_certificate_details <- function(bundle, con, kind, id, producer) {
  if (identical(kind, "external_source")) {
    row <- .wb_certificate_query(con, "prov_source_inputs", "SELECT * FROM prov_source_inputs WHERE source_id = ? ORDER BY snapshot_id, run_id;", list(id))
    if (!nrow(row)) return(NULL)
    parsed <- .wb_certificate_json(row$source_json[[1]])
    val <- parsed$value %||% list()
    raw_path <- .wb_certificate_scalar(val$path)
    uri <- .wb_certificate_scalar(val$uri)
    uri_identity <- if (is.null(uri)) .wb_certificate_state("not_applicable") else if (grepl("^file:", uri, ignore.case = TRUE)) .wb_certificate_state("redacted", "host_file_uri") else .wb_certificate_state("available", value = uri)
    return(list(source = list(uri = uri_identity, path_identity = if (is.null(raw_path)) .wb_certificate_state("not_applicable") else list(status = "available", basename = basename(raw_path)), accession = .wb_certificate_scalar(val$accession), role = .wb_certificate_scalar(val$role %||% val$file_kind), format = .wb_certificate_scalar(val$format)), checksum = list(status = as.character(row$checksum_status[[1]]), algorithm = .wb_certificate_scalar(val$checksum_algorithm %||% if (!is.null(val$sha256)) "sha256" else NULL), value = .wb_certificate_scalar(val$sha256 %||% val$checksum)), consuming_ingestion_runs = sort(unique(as.character(row$run_id)))))
  }
  if (identical(kind, "metadata_field")) {
    row <- .wb_certificate_query(
      con, "metadata_fields", "SELECT * FROM metadata_fields WHERE field_id = ?;", list(id)
    )
    if (!nrow(row)) return(NULL)
    identities <- .wb_certificate_query(con, "metadata_field_identities",
      "SELECT * FROM metadata_field_identities WHERE field_id=? ORDER BY identity_version;", list(id))
    return(list(
      registry = .wb_certificate_rows(row)[[1L]],
      storage = list(table = "cells", column = as.character(row$storage_name[[1L]])),
      identities = if (nrow(identities)) .wb_certificate_state("available", current = .wb_certificate_rows(identities[identities$is_current == 1L, , drop = FALSE]), history = .wb_certificate_rows(identities)) else .wb_certificate_state("unavailable", "identity_not_recorded"),
      assurance = list(
        values = "externally_supplied",
        upstream_derivation = "not_engine_observed"
      )
    ))
  }
  if (identical(kind, "matrix")) {
    row <- .wb_certificate_query(con, "matrices", "SELECT * FROM matrices WHERE matrix_id = ?;", list(id)); if (!nrow(row)) return(NULL)
    frags <- .wb_certificate_query(con, "matrix_fragments", "SELECT fragment_id, storage, path, n_features, n_cells, source, created_at FROM matrix_fragments WHERE matrix_id = ? ORDER BY fragment_id;", list(id))
    return(list(dimensions = list(features = as.integer(row$n_features[[1]]), cells = as.integer(row$n_cells[[1]])), namespaces = list(feature_type = .wb_certificate_scalar(row$feature_type), organism = .wb_certificate_scalar(row$organism), genome_build = .wb_certificate_scalar(row$genome_build), genome_provider = .wb_certificate_scalar(row$genome_provider)), storage = list(backend = .wb_certificate_scalar(row$storage), path = .wb_certificate_relative_path(row$path)), fragments = .wb_certificate_state(if (nrow(frags)) "available" else "not_applicable", items = .wb_certificate_rows(frags))))
  }
  if (identical(kind, "space")) {
    row <- .wb_certificate_query(con, "spaces", "SELECT * FROM spaces WHERE space_id = ?;", list(id)); if (!nrow(row)) return(NULL)
    payload <- .wb_certificate_query(con, "space_payloads", "SELECT * FROM space_payloads WHERE space_id = ?;", list(id))
    sm <- .wb_certificate_query(con, "space_models", "SELECT * FROM space_models WHERE space_id = ?;", list(id))
    binds <- .wb_certificate_query(con, "prov_run_entity_bindings", "SELECT direction, binding_name, entity_kind, entity_id, relationship_type FROM prov_run_entity_bindings WHERE run_id = ? ORDER BY direction, binding_name, entity_kind, entity_id;", list(producer$run_id %||% ""))
    source_ids <- sort(unique(as.character(binds$entity_id[binds$entity_kind == "space" & binds$relationship_type == "CONSUMES"])))
    return(list(dimensions = list(cells = if (nrow(payload)) as.integer(payload$n_cells[[1]]) else NULL, dimensions = if (nrow(payload)) as.integer(payload$n_dims[[1]]) else as.integer(row$dims[[1]])), ordered_cell_identity = if (nrow(payload)) .wb_certificate_state("available", sha256 = .wb_certificate_scalar(payload$cell_ids_sha256)) else .wb_certificate_state("unavailable", "not_recorded"), source_space_id = if (length(source_ids)) .wb_certificate_state("available", value = source_ids[[1]]) else .wb_certificate_state("not_applicable"), output_space_id = .wb_certificate_state("available", value = id), storage = if (nrow(payload)) list(status = "available", backend = .wb_certificate_scalar(row$storage), path = .wb_certificate_relative_path(payload$path), schema_version = .wb_certificate_scalar(payload$schema_version), dtype = .wb_certificate_scalar(payload$dtype), endianness = .wb_certificate_scalar(payload$endianness), chunk_rows = as.integer(payload$chunk_rows[[1]]), chunk_dims = as.integer(payload$chunk_dims[[1]]), content_sha256 = .wb_certificate_scalar(payload$content_sha256), content_identity_scheme = .wb_certificate_scalar(payload$content_identity_scheme)) else list(status = "available", backend = .wb_certificate_scalar(row$storage), path = .wb_certificate_state("not_applicable")), associated_model = if (nrow(sm)) .wb_certificate_state("available", model_id = id, model_type = .wb_certificate_scalar(sm$model_type)) else .wb_certificate_state("not_applicable")))
  }
  if (identical(kind, "model")) {
    bits <- strsplit(id, "|", fixed = TRUE)[[1]]
    aid <- if (length(bits) >= 1L) bits[[1]] else id
    row <- .wb_certificate_query(con, "artifact_model_ref", "SELECT * FROM artifact_model_ref WHERE artifact_id = ?;", list(aid))
    model_space_id <- if (length(bits) >= 2L) bits[[2L]] else id
    if (!nrow(row)) row <- .wb_certificate_query(con, "space_models", "SELECT space_id AS artifact_id, model_type AS engine, space_id AS model_space_id, source_space_id AS in_space_id, model_type, model_path FROM space_models WHERE space_id = ?;", list(model_space_id))
    if (!nrow(row)) return(NULL)
    path <- .wb_certificate_relative_path(row$model_path)
    identity <- .wb_certificate_state("unavailable", "payload_not_readable")
    if (identical(path$status, "available")) {
      abs <- tryCatch(.wb_bundle_path_require(bundle, path$path, expected_type = "either", must_exist = TRUE, purpose = "certificate model payload"), error = function(e) "")
      if (nzchar(abs)) identity <- .wb_certificate_state("available", value = .wb_prov_path_identity(abs))
    }
    return(list(engine = .wb_certificate_scalar(row$engine), model_type = .wb_certificate_scalar(row$model_type), source_space_id = .wb_certificate_scalar(row$in_space_id), associated_spaces = sort(unique(c(.wb_certificate_scalar(row$in_space_id), .wb_certificate_scalar(row$model_space_id)))), storage = list(path = path, contained_payload_tree_identity = identity)))
  }
  if (identical(kind, "artifact")) {
    row <- .wb_certificate_query(con, "artifacts", "SELECT artifact_id, type, name, description, created_at, created_by, source_op, cell_set, provenance_snapshot_id, lineage_status FROM artifacts WHERE artifact_id = ?;", list(id)); if (!nrow(row)) return(NULL)
    model <- .wb_certificate_query(con, "artifact_model_ref", "SELECT engine, model_space_id, in_space_id, model_type, model_path FROM artifact_model_ref WHERE artifact_id = ?;", list(id))
    binds <- .wb_certificate_query(con, "prov_run_entity_bindings", "SELECT entity_id, relationship_type FROM prov_run_entity_bindings WHERE run_id = ? AND entity_kind = 'space' ORDER BY relationship_type, entity_id;", list(producer$run_id %||% ""))
    source_spaces <- sort(unique(as.character(binds$entity_id[binds$relationship_type == "CONSUMES"])))
    output_spaces <- sort(unique(as.character(binds$entity_id[binds$relationship_type %in% c("PRODUCES", "MATERIALIZES")])))
    return(list(primitive_kind = .wb_certificate_scalar(producer$output$primitive_kind), artifact_type = .wb_certificate_scalar(row$type), cell_set = .wb_certificate_scalar(row$cell_set), lineage_status = .wb_certificate_scalar(row$lineage_status), storage = if (nrow(model)) list(backend = "artifact_model_ref", path = .wb_certificate_relative_path(model$model_path)) else .wb_certificate_state("registry_backed", "use_typed_artifact_getter"), source_space_id = if (length(source_spaces)) .wb_certificate_state("available", value = source_spaces[[1L]]) else .wb_certificate_state("not_applicable"), output_space_id = if (length(output_spaces)) .wb_certificate_state("available", value = output_spaces[[1L]]) else .wb_certificate_state("not_applicable")))
  }
  if (identical(kind, "run")) return(.wb_certificate_run(con, id))
  NULL
}

.wb_certificate_identity <- function(bundle, con, kind, id, producer, details) {
  declared <- if (identical(producer$status, "available")) producer$output else list()
  out <- list(
    content_sha256 = .wb_certificate_scalar(declared$content_sha256 %||% declared$content_hash),
    content_identity_scheme = .wb_certificate_scalar(declared$content_identity_scheme),
    structural_fingerprint = .wb_certificate_scalar(declared$structural_fingerprint),
    structural_fingerprint_scheme = .wb_certificate_scalar(declared$structural_fingerprint_scheme),
    verification_level = .wb_certificate_scalar(declared$verification_level),
    verification_status = .wb_certificate_scalar(declared$verification_status) %||% "unverified",
    observed = .wb_certificate_state("unavailable", "independent_content_verification_not_applicable")
  )
  if (identical(kind, "external_source")) {
    out$verification_level <- "declaration"
    out$verification_status <- as.character(details$checksum$status %||% "unverified")
    return(out)
  }
  if (identical(kind, "run")) return(out)
  declared_sha <- as.character(out$content_sha256 %||% "")[1]
  if (!grepl("^[0-9a-fA-F]{64}$", declared_sha)) {
    out$verification_status <- if (nzchar(declared_sha)) "corrupt" else "unverified"
    out$observed <- .wb_certificate_state("unavailable", if (nzchar(declared_sha)) "malformed_declared_content_sha256" else "content_identity_not_recorded")
    return(out)
  }
  observed <- tryCatch({
    if (identical(kind, "matrix")) {
      .wb_prov_payload_identity(bundle, wb_prim_matrix(id))
    } else if (identical(kind, "metadata_field")) {
      .wb_metadata_field_content_identity(con, id)
    } else if (identical(kind, "space")) {
      payload <- .wb_certificate_query(con, "space_payloads", "SELECT * FROM space_payloads WHERE space_id = ?;", list(id))
      .wb_assert(nrow(payload) == 1L, "space payload registry is unavailable")
      path <- .wb_bundle_path_require(bundle, as.character(payload$path[[1L]]), expected_type = "file", must_exist = TRUE, purpose = "certificate space payload")
      checked <- .wb_space_payload_validate_file(path, expected = payload, verify_hash = TRUE, validate_values = FALSE)
      list(content_sha256 = checked$content_sha256, content_identity_scheme = as.character(payload$content_identity_scheme[[1L]]))
    } else if (identical(kind, "model")) {
      details$storage$contained_payload_tree_identity$value
    } else if (identical(kind, "artifact")) {
      art <- .wb_certificate_query(con, "artifacts", "SELECT type FROM artifacts WHERE artifact_id = ?;", list(id))
      atype <- if (nrow(art)) as.character(art$type[[1L]]) else ""
      if (atype %in% c("feature_table", "obs_table")) {
        list(content_sha256 = .wb_prov_stored_table_content_sha256(con, id), content_identity_scheme = unname(.wb_content_identity_schemes()[["table"]]))
      } else if (identical(atype, "model_ref")) {
        row <- .wb_certificate_query(con, "artifact_model_ref", "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;", list(id))
        path <- .wb_bundle_path_require(bundle, as.character(row$model_path[[1L]]), expected_type = "either", must_exist = TRUE, purpose = "certificate artifact model payload")
        .wb_prov_path_identity(path)
      } else {
        .wb_prov_payload_identity(bundle, wb_art_load(bundle, id))
      }
    } else NULL
  }, error = function(e) structure(list(message = conditionMessage(e)), class = "wb_certificate_verification_error"))
  if (inherits(observed, "wb_certificate_verification_error") || is.null(observed)) {
    out$verification_status <- "failed"
    out$observed <- .wb_certificate_state("corrupt", "payload_verification_failed")
    return(out)
  }
  observed_sha <- as.character(observed$content_sha256 %||% "")[1]
  observed_scheme <- as.character(observed$content_identity_scheme %||% "")[1]
  matches <- identical(tolower(observed_sha), tolower(declared_sha)) &&
    identical(observed_scheme, as.character(out$content_identity_scheme %||% "")[1])
  out$observed <- .wb_certificate_state(if (matches) "verified" else "corrupt",
    content_sha256 = observed_sha, content_identity_scheme = observed_scheme)
  out$verification_status <- if (matches) "content_verified" else "content_identity_mismatch"
  out$verification_level <- if (matches) "content" else "failed"
  out
}

#' Get a deterministic provenance certificate for a durable entity
#'
#' Certificates are read-only node projections over the canonical composed DAG
#' and durable registries. They contain provenance and identity metadata only;
#' use typed getters to load matrices, coordinates, models, or artifacts.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind One of `external_source`, `metadata_field`, `matrix`,
#'   `space`, `model`, `artifact`, `run`, `capsule`, or `capsule_output`.
#' @param entity_id Durable entity identifier.
#' @return A JSON-serializable `scworkbench.provenance.entity_certificate.v1` list.
#' @export
wb_entity_certificate <- function(bundle, entity_kind, entity_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "entity provenance certificates")
  kind <- match.arg(as.character(entity_kind)[1], c("external_source", "metadata_field", "matrix", "space", "model", "artifact", "run", "capsule", "capsule_output"))
  id <- as.character(entity_id)[1]
  .wb_assert(!is.na(id) && nzchar(id), "entity_id must be a non-empty string")

  # Present the existing connection to all composed-DAG helpers as read-only.
  # This also supports a writer's current WAL-visible state without opening a
  # second connection, checkpointing, migrating, refreshing, or sidecar I/O.
  reader <- structure(list(
    dir = bundle$dir, manifest = bundle$manifest, con = bundle$con, read_only = TRUE
  ), class = "scworkbench_bundle")
  con <- reader$con
  graph <- wb_prov_bundle_dag(reader, include_snapshots = TRUE, include_registry_mutations = TRUE, include_superseded = TRUE)
  node_id <- .wb_certificate_node_id(kind, id)

  if (kind %in% c("capsule", "capsule_output")) {
    .wb_assert(.wb_table_exists(con,"analysis_capsules"),paste0("ENTITY_CERTIFICATE_NOT_FOUND: no durable ",kind," entity '",id,"'."))
    if (identical(kind,"capsule")) {
      cap <- wb_capsule(reader,id); output <- NULL
    } else {
      row <- DBI::dbGetQuery(con,"SELECT * FROM analysis_capsule_outputs WHERE output_id=?;",params=list(id))
      .wb_assert(nrow(row)==1L,paste0("ENTITY_CERTIFICATE_NOT_FOUND: no durable capsule_output entity '",id,"'."))
      cap <- wb_capsule(reader,as.character(row$capsule_id[[1L]])); output <- as.list(row[1L,,drop=FALSE])
    }
    return(list(
      schema=.wb_certificate_schema(),
      subject=list(kind=kind,id=id,node_id=node_id,display_name=if(is.null(output)) cap$name else output$output_name,created_at=cap$registered_at,lifecycle_state="immutable"),
      lifecycle=list(state="immutable",record=.wb_certificate_state("available",value=list(append_only=TRUE)),supersessions=.wb_certificate_state("not_applicable"),tombstone=.wb_certificate_state("not_applicable")),
      producer=if(is.null(output)) .wb_certificate_state("not_applicable",reason="capsules_are_registration_records_not_operation_runs") else .wb_certificate_state("available",capsule_id=cap$capsule_id,execution_mode=cap$execution_mode),
      relationships=.wb_certificate_relationships(graph,node_id),
      identity=if(is.null(output)) list(content_sha256=cap$manifest_sha256,content_identity_scheme="scworkbench.analysis_capsule.manifest-file.sha256.v1",script_sha256=cap$script_sha256) else list(content_sha256=output$content_sha256,content_identity_scheme=output$content_identity_scheme),
      promotion=list(status="not_applicable",reason="capsule registration is not operation promotion"),
      details=list(assurance_level=cap$assurance_level,execution_mode=cap$execution_mode,replay_status=cap$replay_status,script=list(path=.wb_certificate_relative_path(cap$script_path),content_sha256=cap$script_sha256),inputs=cap$inputs,parameters=cap$parameters,runtime_declaration=cap$runtime,output=output,catalog_review=cap$catalog_review,family_hint=cap$family_hint,declared_relationships=cap$relationships,limitations=cap$limitations)
    ))
  }

  exists <- node_id %in% as.character(graph$nodes$id)
  if (!exists && identical(kind, "external_source")) exists <- nrow(.wb_certificate_query(con, "prov_source_inputs", "SELECT source_id FROM prov_source_inputs WHERE source_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "metadata_field")) exists <- nrow(.wb_certificate_query(con, "metadata_fields", "SELECT field_id FROM metadata_fields WHERE field_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "matrix")) exists <- nrow(.wb_certificate_query(con, "matrices", "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "space")) exists <- nrow(.wb_certificate_query(con, "spaces", "SELECT space_id FROM spaces WHERE space_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "artifact")) exists <- nrow(.wb_certificate_query(con, "artifacts", "SELECT artifact_id FROM artifacts WHERE artifact_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "run")) exists <- nrow(.wb_certificate_query(con, "prov_runs", "SELECT run_id FROM prov_runs WHERE run_id = ?;", list(id))) > 0L
  if (!exists && identical(kind, "model")) {
    model_bits <- strsplit(id, "|", fixed = TRUE)[[1]]
    model_space_id <- if (length(model_bits) >= 2L) model_bits[[2L]] else id
    exists <- nrow(.wb_certificate_query(con, "artifact_model_ref", "SELECT artifact_id FROM artifact_model_ref WHERE artifact_id = ?;", list(model_bits[[1L]]))) > 0L || nrow(.wb_certificate_query(con, "space_models", "SELECT space_id FROM space_models WHERE space_id = ?;", list(model_space_id))) > 0L
  }
  if (!exists) stop("ENTITY_CERTIFICATE_NOT_FOUND: no durable ", kind, " entity '", id, "'.", call. = FALSE)

  producer <- .wb_certificate_producer(con, kind, id)
  details <- .wb_certificate_details(reader, con, kind, id, producer)
  if (is.null(details)) stop("ENTITY_CERTIFICATE_KIND_MISMATCH: entity '", id, "' is not registered as ", kind, ".", call. = FALSE)
  lifecycle <- .wb_certificate_lifecycle(con, kind, id)
  node <- graph$nodes[as.character(graph$nodes$id) == node_id, , drop = FALSE]
  created <- if (nrow(node)) .wb_certificate_scalar(node$created_at) else NULL
  display <- if (nrow(node)) .wb_certificate_scalar(node$title %||% node$label) else id
  list(
    schema = .wb_certificate_schema(),
    subject = list(kind = kind, id = id, node_id = paste0(kind, ":", id), display_name = display %||% id, created_at = created, lifecycle_state = lifecycle$state),
    lifecycle = lifecycle,
    producer = producer,
    relationships = .wb_certificate_relationships(graph, node_id),
    identity = .wb_certificate_identity(reader, con, kind, id, producer, details),
    promotion = list(snapshot_id = .wb_certificate_scalar(producer$output$snapshot_id %||% producer$snapshot_id), replay_equivalence_status = .wb_certificate_scalar(producer$output$replay_equivalence_status) %||% "unavailable"),
    details = details
  )
}
