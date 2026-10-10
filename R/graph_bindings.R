.wb_graph_identity_assert <- function(value, scheme) {
  .wb_graph_closed(value, c("scheme", "sha256"), "identity")
  .wb_graph_require(identical(value$scheme, scheme) && is.character(value$sha256) &&
    length(value$sha256) == 1L && !is.na(value$sha256) &&
    grepl("^[0-9a-f]{64}$", value$sha256), "GRAPH_IDENTITY_INVALID", scheme)
  invisible(TRUE)
}

.wb_graph_binding_header_validate <- function(binding) {
  .wb_graph_closed(binding, c("binding_id", "axis_kind", "source_ref",
    "source_snapshot_identity", "axis_content_identity", "axis_order_identity"), "binding")
  .wb_graph_require(.wb_graph_string(binding$binding_id) &&
    .wb_graph_string(binding$axis_kind) && binding$axis_kind %in% c("cell", "feature"),
    "GRAPH_BINDINGS_INVALID", "Invalid binding ID/axis kind.")
  .wb_graph_closed(binding$source_ref, c("kind", "source_id"), "source reference")
  .wb_graph_require(.wb_graph_string(binding$source_ref$source_id) &&
    .wb_graph_string(binding$source_ref$kind) && binding$source_ref$kind %in%
      c("matrix", "retained_cell_axis") &&
    (binding$axis_kind == "cell" || binding$source_ref$kind == "matrix"),
    "GRAPH_BINDINGS_INVALID", "Invalid source reference.")
  .wb_graph_identity_assert(binding$source_snapshot_identity,
    "scworkbench.provenance.snapshot_head.v1")
  .wb_graph_identity_assert(binding$axis_content_identity,
    "scworkbench.graph.source-axis-content.canonical-json.v1")
  .wb_graph_identity_assert(binding$axis_order_identity,
    paste0("scworkbench.", binding$axis_kind, "_order.v1"))
  invisible(TRUE)
}

.wb_graph_bindings_validate <- function(bindings, node_ids) {
  bindings <- .wb_graph_records(bindings)
  binding_ids <- character(length(bindings))
  for (i in seq_along(bindings)) {
    binding <- bindings[[i]]
    .wb_graph_closed(binding, c("binding_id", "axis_kind", "source_ref",
      "source_snapshot_identity", "axis_content_identity", "axis_order_identity", "mapping"),
      "binding with mapping")
    .wb_graph_binding_header_validate(binding[setdiff(names(binding), "mapping")])
    binding_ids[[i]] <- binding$binding_id
    mapping <- .wb_graph_records(binding$mapping)
    nodes <- axes <- character(length(mapping))
    for (j in seq_along(mapping)) {
      .wb_graph_closed(mapping[[j]], c("node_id", "axis_id"), "mapping")
      .wb_graph_require(.wb_graph_string(mapping[[j]]$node_id) &&
        .wb_graph_string(mapping[[j]]$axis_id), "GRAPH_BINDINGS_INVALID", "Invalid mapping IDs.")
      nodes[[j]] <- mapping[[j]]$node_id; axes[[j]] <- mapping[[j]]$axis_id
    }
    positions <- match(nodes, node_ids)
    .wb_graph_require(!anyNA(positions) && !anyDuplicated(nodes) && !anyDuplicated(axes) &&
      identical(order(positions), seq_along(positions)), "GRAPH_BINDINGS_INVALID",
      "Mappings must be injective within a binding and follow graph node order.")
  }
  .wb_graph_require(!anyDuplicated(binding_ids), "GRAPH_BINDINGS_INVALID", "Duplicate binding IDs.")
  invisible(TRUE)
}

#' Compute a Graph's Logical Identities
#' @param graph Graph primitive. Hash equality does not confer source authority.
#' @return Content, binding and path-free retained-descriptor identities and preimage.
#' @export
wb_graph_identity <- function(graph) {
  wb_graph_validate(graph)
  content <- .wb_graph_content_identity(graph$content)
  binding <- .wb_graph_identity("scworkbench.graph.axis-bindings.canonical-json.v1",
    list(schema = "scworkbench.graph.axis-bindings.v1", graph_content_identity = content,
      bindings = graph$associations))
  descriptor <- list(schema = "scworkbench.graph.retained-descriptor.v1",
    content_identity = content, binding_identity = binding,
    binding_count = length(graph$associations))
  list(content_identity = content, binding_identity = binding, descriptor = descriptor,
    descriptor_identity = .wb_graph_identity(
      "scworkbench.graph.retained-descriptor.canonical-json.v1", descriptor))
}

.wb_graph_validate_sql_bindings <- function(con, artifact_id, budgets) {
  .wb_graph_scan(con, artifact_id, "bindings", function(rows) {
    for (json in rows$record_json) {
      header <- .wb_graph_parse(json)
      .wb_graph_binding_header_validate(header)
      previous_node <- bit64::as.integer64(-1)
      # Existence/order use the authoritative graph rows, not a full node list.
      query <- paste0("SELECT m.record_json,n.row_ordinal node_ordinal FROM artifact_graph_rows m ",
        "LEFT JOIN artifact_graph_rows n ON n.artifact_id=m.artifact_id AND n.component='nodes' ",
        "AND json_extract(n.record_json,'$.node_id')=json_extract(m.record_json,'$.node_id') ",
        "WHERE m.artifact_id=? AND m.component='binding_mappings' ",
        "AND json_extract(m.record_json,'$.binding_id')=? ORDER BY m.row_ordinal;")
      cursor <- DBI::dbSendQuery(con, query, params = list(artifact_id, header$binding_id))
      tryCatch(repeat {
        batch <- DBI::dbFetch(cursor, n = budgets$partition_rows)
        if (!nrow(batch)) break
        for (i in seq_len(nrow(batch))) {
          .wb_graph_row_validate("binding_mappings", .wb_graph_parse(batch$record_json[[i]]))
          node <- bit64::as.integer64(batch$node_ordinal[[i]])
          .wb_graph_require(!is.na(node) && node > previous_node,
            "GRAPH_BINDINGS_INVALID", "Foreign or reordered mapped graph node.")
          previous_node <- node
        }
      }, finally = DBI::dbClearResult(cursor))
    }
  }, page = budgets$partition_rows)
  bad <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM artifact_graph_rows m ",
    "LEFT JOIN artifact_graph_rows b ON b.artifact_id=m.artifact_id AND b.component='bindings' ",
    "AND json_extract(b.record_json,'$.binding_id')=json_extract(m.record_json,'$.binding_id') ",
    "WHERE m.artifact_id=? AND m.component='binding_mappings' AND b.row_ordinal IS NULL LIMIT 1;"),
    params = list(artifact_id))
  .wb_graph_require(!nrow(bad), "GRAPH_BINDINGS_INVALID", "Mapping without a binding.")
  invisible(TRUE)
}

.wb_graph_token_hash <- function(emitter, budgets) {
  token_file <- tempfile("scwb_graph_identity_")
  on.exit(if (file.exists(token_file)) unlink(token_file), add = TRUE)
  sink <- file(token_file, "wb"); count <- bit64::as.integer64(0)
  emit <- function(value) {
    bytes <- charToRaw(enc2utf8(value))
    count <<- count + bit64::as.integer64(length(bytes))
    .wb_graph_require(!is.na(count) && count <= .wb_graph_i64(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Identity token spill budget exceeded.")
    writeBin(bytes, sink)
  }
  tryCatch(emitter(emit), finally = close(sink))
  input <- file(token_file, "rb")
  tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
}

.wb_graph_sql_identities <- function(con, artifact_id, budgets = .wb_graph_budgets()) {
  content <- .wb_graph_sql_content_hash(con, artifact_id, budgets)
  .wb_graph_validate_sql_bindings(con, artifact_id, budgets)
  binding_count <- .wb_graph_count(con, artifact_id, "bindings")
  .wb_graph_require(.wb_graph_i64(binding_count) <= bit64::as.integer64("999999999999999"),
    "GRAPH_COUNT_INVALID", "Binding-count representation exceeds canonical JSON v1 domain.")
  digest <- .wb_graph_token_hash(function(emit) {
    emit('{"bindings":['); first <- TRUE
    .wb_graph_scan(con, artifact_id, "bindings", function(rows) {
      for (json in rows$record_json) {
        binding <- .wb_graph_parse(json)
        if (!first) emit(",")
        emit("{"); field_first <- TRUE
        for (name in sort(c(names(binding), "mapping"), method = "radix")) {
          if (!field_first) emit(",")
          emit(paste0(.wb_operation_pack_canonical_json(name), ":"))
          if (name == "mapping") {
            emit("["); mapping_first <- TRUE
            .wb_graph_scan(con, artifact_id, "binding_mappings", function(pairs) {
              for (pair_json in pairs$record_json) {
                pair <- .wb_graph_parse(pair_json)
                if (!mapping_first) emit(",")
                emit(.wb_operation_pack_canonical_json(pair[c("node_id", "axis_id")]))
                mapping_first <<- FALSE
              }
            }, page = budgets$partition_rows,
              predicate = "AND json_extract(record_json,'$.binding_id')=?",
              params = list(binding$binding_id))
            emit("]")
          } else emit(.wb_operation_pack_canonical_json(binding[[name]]))
          field_first <- FALSE
        }
        emit("}"); first <<- FALSE
      }
    }, page = budgets$partition_rows)
    emit(paste0('],"graph_content_identity":',
      .wb_operation_pack_canonical_json(content$identity),
      ',"schema":"scworkbench.graph.axis-bindings.v1"}'))
  }, budgets)
  binding <- list(scheme = "scworkbench.graph.axis-bindings.canonical-json.v1", sha256 = digest)
  descriptor <- list(schema = "scworkbench.graph.retained-descriptor.v1",
    content_identity = content$identity, binding_identity = binding,
    binding_count = as.numeric(binding_count))
  list(content_identity = content$identity, binding_identity = binding,
    descriptor = descriptor, descriptor_identity = .wb_graph_identity(
      "scworkbench.graph.retained-descriptor.canonical-json.v1", descriptor),
    canonical_bytes = content$canonical_bytes)
}
