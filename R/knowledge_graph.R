# Knowledge graph exports for agent/runtime planning.

.wb_kg_schema_version <- function() "scworkbench.kg.v1"

.wb_kg_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

.wb_kg_json <- function(x) {
  .wb_require_pkg("jsonlite", "knowledge graph JSON encoding")
  as.character(jsonlite::toJSON(.wb_json_sanitize(x %||% list()), auto_unbox = TRUE, null = "null"))
}

.wb_kg_text <- function(...) {
  vals <- unlist(list(...), recursive = TRUE, use.names = FALSE)
  vals <- as.character(vals[!is.na(vals)])
  vals <- vals[nzchar(vals)]
  paste(unique(vals), collapse = "\n")
}

.wb_kg_slug <- function(x) {
  x <- as.character(x %||% "")[1]
  x <- gsub("[^A-Za-z0-9_:.@/-]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}

.wb_kg_node_df <- function() {
  data.frame(
    id = character(0),
    label = character(0),
    node_type = character(0),
    source = character(0),
    source_version = character(0),
    text = character(0),
    payload_json = character(0),
    stringsAsFactors = FALSE
  )
}

.wb_kg_edge_df <- function() {
  data.frame(
    id = character(0),
    source_id = character(0),
    target_id = character(0),
    edge_type = character(0),
    source = character(0),
    confidence = numeric(0),
    payload_json = character(0),
    stringsAsFactors = FALSE
  )
}

.wb_kg_node <- function(id, label, node_type, source,
                        source_version = .wb_kg_schema_version(),
                        text = "", payload = list()) {
  data.frame(
    id = as.character(id)[1],
    label = as.character(label %||% id)[1],
    node_type = as.character(node_type)[1],
    source = as.character(source)[1],
    source_version = as.character(source_version %||% .wb_kg_schema_version())[1],
    text = as.character(text %||% "")[1],
    payload_json = .wb_kg_json(payload),
    stringsAsFactors = FALSE
  )
}

.wb_kg_edge_id <- function(source_id, target_id, edge_type, source = "scworkbench",
                           semantic_label = "") {
  .wb_identifier_sha256(c(source_id, target_id, edge_type, source, semantic_label), "edge")
}

.wb_kg_edge <- function(source_id, target_id, edge_type, source,
                        confidence = 1, payload = list(), semantic_label = "") {
  data.frame(
    id = .wb_kg_edge_id(source_id, target_id, edge_type, source, semantic_label),
    source_id = as.character(source_id)[1],
    target_id = as.character(target_id)[1],
    edge_type = as.character(edge_type)[1],
    source = as.character(source)[1],
    confidence = as.numeric(confidence %||% 1)[1],
    payload_json = .wb_kg_json(payload),
    stringsAsFactors = FALSE
  )
}

.wb_kg_bind <- function(items, empty) {
  items <- items[!vapply(items, is.null, logical(1))]
  if (!length(items)) return(empty)
  out <- do.call(rbind, items)
  rownames(out) <- NULL
  out
}

.wb_kg_sort_nodes <- function(nodes) {
  if (!nrow(nodes)) return(nodes)
  nodes <- nodes[!duplicated(nodes$id), , drop = FALSE]
  nodes <- nodes[order(nodes$node_type, nodes$id), , drop = FALSE]
  rownames(nodes) <- NULL
  nodes
}

.wb_kg_sort_edges <- function(edges) {
  if (!nrow(edges)) return(edges)
  edges <- edges[!duplicated(edges$id), , drop = FALSE]
  edges <- edges[order(edges$edge_type, edges$source_id, edges$target_id, edges$id), , drop = FALSE]
  rownames(edges) <- NULL
  edges
}

.wb_kg_payload_evidence <- function(payload_json) {
  payload <- try(jsonlite::fromJSON(as.character(payload_json %||% "{}")[1], simplifyVector = FALSE), silent = TRUE)
  if (inherits(payload, "try-error") || is.null(payload) || !is.list(payload)) payload <- list()
  snapshots <- .wb_prov_snapshot_ids(payload$snapshot_id %||% NULL, payload$snapshot_ids %||% NULL)
  payload$snapshot_id <- NULL
  payload$snapshot_ids <- NULL
  list(
    payload = payload,
    canonical = .wb_kg_json(payload),
    snapshot_ids = snapshots
  )
}

.wb_kg_canonicalize_rows <- function(rows, kind = c("node", "edge")) {
  kind <- match.arg(kind)
  if (!nrow(rows)) return(rows)
  ids <- sort(unique(as.character(rows$id)))
  out <- vector("list", length(ids))
  stable <- setdiff(names(rows), c("payload_json"))
  for (i in seq_along(ids)) {
    id <- ids[[i]]
    group <- rows[as.character(rows$id) == id, , drop = FALSE]
    row <- group[1L, , drop = FALSE]
    for (field in stable) {
      values <- .wb_prov_evidence_values(group[[field]])
      if (length(values) > 1L) {
        .wb_prov_composition_abort(
          if (identical(kind, "node")) "PROVENANCE_KG_NODE_CONFLICT" else "PROVENANCE_KG_EDGE_CONFLICT",
          paste0("Conflicting canonical provenance KG ", kind, " evidence for '",
                 id, "' field '", field, "'."),
          list(entity_id = id, field = field, values = values)
        )
      }
      if (length(values) == 1L) row[[field]] <- values[[1L]]
    }
    evidence <- lapply(group$payload_json, .wb_kg_payload_evidence)
    payloads <- unique(vapply(evidence, `[[`, character(1), "canonical"))
    if (length(payloads) > 1L) {
      .wb_prov_composition_abort(
        if (identical(kind, "node")) "PROVENANCE_KG_NODE_CONFLICT" else "PROVENANCE_KG_EDGE_CONFLICT",
        paste0("Conflicting canonical provenance KG ", kind, " payload evidence for '", id, "'."),
        list(entity_id = id, field = "payload_json", values = payloads)
      )
    }
    payload <- evidence[[1L]]$payload
    snapshots <- sort(unique(unlist(lapply(evidence, `[[`, "snapshot_ids"), use.names = FALSE)))
    if (length(snapshots)) payload$snapshot_ids <- as.list(snapshots)
    row$payload_json <- .wb_kg_json(payload)
    out[[i]] <- row
  }
  ans <- do.call(rbind, out)
  rownames(ans) <- NULL
  ans
}

.wb_kg_normalize_graph <- function(nodes, edges, strict_provenance = FALSE) {
  if (isTRUE(strict_provenance)) {
    nodes <- .wb_kg_canonicalize_rows(nodes, "node")
    edges <- .wb_kg_canonicalize_rows(edges, "edge")
  }
  list(
    schema_version = .wb_kg_schema_version(),
    generated_at = .wb_kg_now(),
    nodes = .wb_kg_sort_nodes(nodes),
    edges = .wb_kg_sort_edges(edges)
  )
}

.wb_kg_node_type <- function(record_type) {
  type <- as.character(record_type %||% "")[1]
  map <- c(
    op = "Op",
    recipe = "Recipe",
    primitive = "Primitive",
    artifact_type = "ArtifactType",
    parameter = "Parameter",
    getter = "Getter",
    wrangler = "Wrangler",
    plot = "Plot"
  )
  if (type %in% names(map)) return(unname(map[[type]]))
  if (!nzchar(type)) return("Unknown")
  paste0(toupper(substr(type, 1L, 1L)), substr(type, 2L, nchar(type)))
}

.wb_kg_static_edge_canonical <- function(e) {
  type <- as.character(e$edge_type %||% "")[1]
  from <- as.character(e$from %||% "")[1]
  to <- as.character(e$to %||% "")[1]
  reverse <- FALSE
  edge_type <- switch(
    type,
    consumes = "REQUIRES",
    consumed_by = {
      reverse <- TRUE
      "REQUIRES"
    },
    produces = "PRODUCES",
    recipe_produces = "PRODUCES",
    produced_by_recipe = {
      reverse <- TRUE
      "PRODUCES"
    },
    has_parameter = "HAS_PARAMETER",
    has_parameter_semantics = "HAS_PARAMETER",
    uses = "USES",
    used_by_recipe = {
      reverse <- TRUE
      "USES"
    },
    promotes_as = "PROMOTED_AS",
    loads_as = "INSTANCE_OF",
    wrangled_by = "CAN_WRANGLE",
    feeds_plot = "CAN_PLOT",
    compatible_with = "COMPATIBLE_WITH",
    toupper(type)
  )
  if (isTRUE(reverse)) {
    tmp <- from
    from <- to
    to <- tmp
  }
  list(from = from, to = to, edge_type = edge_type)
}

.wb_kg_static_nodes <- function(catalog) {
  records <- catalog$records %||% list()
  if (!length(records)) return(.wb_kg_node_df())
  nodes <- lapply(records, function(rec) {
    id <- as.character(rec$record_id %||% "")[1]
    .wb_kg_node(
      id = id,
      label = rec$title %||% rec$name %||% id,
      node_type = .wb_kg_node_type(rec$record_type),
      source = "semantic_catalog",
      source_version = as.character(catalog$schema_version %||% ""),
      text = .wb_kg_text(rec$title, rec$description, rec$search_text, rec$tags),
      payload = rec
    )
  })
  .wb_kg_sort_nodes(.wb_kg_bind(nodes, .wb_kg_node_df()))
}

.wb_kg_static_edges <- function(graph) {
  edges <- graph$edges %||% list()
  if (!length(edges)) return(.wb_kg_edge_df())
  out <- lapply(edges, function(e) {
    ce <- .wb_kg_static_edge_canonical(e)
    .wb_kg_edge(
      source_id = ce$from,
      target_id = ce$to,
      edge_type = ce$edge_type,
      source = "semantic_compatibility_graph",
      confidence = 1,
      payload = e
    )
  })
  .wb_kg_sort_edges(.wb_kg_bind(out, .wb_kg_edge_df()))
}

#' Export Static scworkbench Knowledge Graph
#'
#' Builds the engine-owned static knowledge graph from semantic catalogs and
#' the compatibility graph. The graph is deterministic in node/edge identity and
#' sorted output order. Static edge directions are normalized by edge type:
#' `REQUIRES` is consumer to required input, `PRODUCES` is producer to output,
#' `USES` is user to used dependency, `CAN_WRANGLE` is source primitive/artifact
#' type to wrangler, and `CAN_PLOT` is wrangler to plot.
#'
#' @return A list with `schema_version`, `generated_at`, `nodes`, and `edges`.
#' @export
wb_kg_static_graph <- function() {
  catalog <- wb_semantic_catalog()
  .wb_kg_normalize_graph(
    nodes = .wb_kg_static_nodes(catalog),
    edges = .wb_kg_static_edges(catalog$graph)
  )
}

.wb_kg_bundle_id <- function(bundle) {
  as.character(bundle$manifest$bundle_id %||% basename(normalizePath(bundle$dir, winslash = "/", mustWork = FALSE)))[1]
}

.wb_kg_bundle_node_id <- function(bundle) paste0("bundle:", .wb_kg_slug(.wb_kg_bundle_id(bundle)))

.wb_kg_safe_df <- function(expr) {
  out <- try(expr, silent = TRUE)
  if (inherits(out, "try-error") || is.null(out)) return(data.frame(stringsAsFactors = FALSE))
  as.data.frame(out, stringsAsFactors = FALSE)
}

.wb_kg_bundle_nodes_edges <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  bid <- .wb_kg_bundle_node_id(bundle)
  nodes <- list(.wb_kg_node(
    id = bid,
    label = .wb_kg_bundle_id(bundle),
    node_type = "Bundle",
    source = "bundle_manifest",
    text = .wb_kg_text(bundle$manifest$bundle_name, .wb_kg_bundle_id(bundle)),
    payload = list(bundle_id = .wb_kg_bundle_id(bundle))
  ))
  edges <- list()

  mats <- .wb_kg_safe_df(wb_matrices(bundle))
  if (nrow(mats)) {
    for (i in seq_len(nrow(mats))) {
      mid <- as.character(mats$matrix_id[i])
      nid <- paste0("matrix:", .wb_kg_slug(mid))
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(nid, mid, "Matrix", "bundle_registry", text = .wb_kg_text(mid, mats$feature_type[i], mats$layer[i]), payload = as.list(mats[i, , drop = FALSE]))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(bid, nid, "HAS_MATRIX", "bundle_registry")
    }
  }

  spaces <- .wb_kg_safe_df(wb_spaces(bundle))
  if (nrow(spaces)) {
    for (i in seq_len(nrow(spaces))) {
      sid <- as.character(spaces$space_id[i])
      nid <- paste0("space:", .wb_kg_slug(sid))
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(nid, sid, "Space", "bundle_registry", text = .wb_kg_text(sid, spaces$description[i], spaces$storage[i]), payload = as.list(spaces[i, , drop = FALSE]))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(bid, nid, "HAS_SPACE", "bundle_registry")
    }
  }

  cell_sets <- try(wb_cell_sets(bundle), silent = TRUE)
  if (!inherits(cell_sets, "try-error") && length(cell_sets)) {
    for (cs in as.character(cell_sets)) {
      if (!nzchar(cs)) next
      nid <- paste0("cell_set:", .wb_kg_slug(cs))
      n_cells <- try(length(wb_resolve_cell_set(bundle, cs)), silent = TRUE)
      if (inherits(n_cells, "try-error")) n_cells <- NA_integer_
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(nid, cs, "CellSet", "bundle_registry", text = cs, payload = list(cell_set = cs, n_cells = n_cells))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(bid, nid, "HAS_CELL_SET", "bundle_registry")
    }
  }

  fsets <- .wb_kg_safe_df(wb_feature_sets(bundle))
  if (nrow(fsets)) {
    ns_vals <- unique(as.character(fsets$namespace %||% character(0)))
    ns_vals <- ns_vals[!is.na(ns_vals) & nzchar(ns_vals)]
    for (ns in ns_vals) {
      nid <- paste0("feature_namespace:", .wb_kg_slug(ns))
      sub <- fsets[as.character(fsets$namespace) == ns, , drop = FALSE]
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(nid, ns, "FeatureSetNamespace", "bundle_registry", text = ns, payload = list(namespace = ns, n_feature_sets = nrow(sub), matrices = unique(as.character(sub$matrix_id))))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(bid, nid, "HAS_FEATURE_NAMESPACE", "bundle_registry")
      for (mid in unique(as.character(sub$matrix_id))) {
        if (nzchar(mid)) edges[[length(edges) + 1L]] <- .wb_kg_edge(nid, paste0("matrix:", .wb_kg_slug(mid)), "USES", "bundle_registry")
      }
    }
  }

  arts <- .wb_kg_safe_df(wb_art_list(bundle))
  if (nrow(arts)) {
    atypes <- unique(as.character(arts$type %||% character(0)))
    atypes <- atypes[!is.na(atypes) & nzchar(atypes)]
    for (atype in atypes) {
      atid <- paste0("artifact_type:", .wb_kg_slug(atype))
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(
        atid,
        atype,
        "ArtifactType",
        "artifact_registry_ref",
        text = atype,
        payload = list(artifact_type = atype)
      )
    }
    for (i in seq_len(nrow(arts))) {
      aid <- as.character(arts$artifact_id[i])
      nid <- paste0("artifact:", .wb_kg_slug(aid))
      atype <- as.character(arts$type[i] %||% "")
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(nid, aid, "Artifact", "artifact_registry", text = .wb_kg_text(aid, arts$name[i], atype, arts$source_op[i]), payload = as.list(arts[i, , drop = FALSE]))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(nid, paste0("artifact_type:", .wb_kg_slug(atype)), "INSTANCE_OF", "artifact_registry", confidence = if (nzchar(atype)) 1 else 0.5)
      edges[[length(edges) + 1L]] <- .wb_kg_edge(nid, bid, "BELONGS_TO_BUNDLE", "artifact_registry")
    }
  }

  list(nodes = .wb_kg_bind(nodes, .wb_kg_node_df()), edges = .wb_kg_bind(edges, .wb_kg_edge_df()))
}

#' Export Bundle Instance Knowledge Graph
#'
#' Builds bundle-specific instance nodes for matrices, spaces, cell sets,
#' feature-set namespaces, and artifacts.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @return A list with `schema_version`, `generated_at`, `nodes`, and `edges`.
#' @export
wb_kg_bundle_graph <- function(bundle) {
  be <- .wb_kg_bundle_nodes_edges(bundle)
  .wb_kg_normalize_graph(be$nodes, be$edges)
}

.wb_kg_provenance_nodes_edges <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  bid <- .wb_kg_bundle_node_id(bundle)
  nodes <- list(.wb_kg_node(
    id = bid,
    label = .wb_kg_bundle_id(bundle),
    node_type = "Bundle",
    source = "bundle_manifest_ref",
    text = .wb_kg_text(bundle$manifest$bundle_name, .wb_kg_bundle_id(bundle)),
    payload = list(bundle_id = .wb_kg_bundle_id(bundle))
  ))
  edges <- list()

  heads <- .wb_kg_safe_df(wb_prov_list_heads(bundle))
  if (nrow(heads)) {
    for (i in seq_len(nrow(heads))) {
      sid <- as.character(heads$snapshot_id[i])
      snid <- paste0("session:", .wb_kg_slug(sid))
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(snid, sid, "Session", "provenance_store", text = .wb_kg_text(sid, heads$name_prefix[i], heads$description[i]), payload = as.list(heads[i, , drop = FALSE]))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(snid, bid, "BELONGS_TO_BUNDLE", "provenance_store")
    }
  }

  con <- bundle$con
  if (.wb_table_exists(con, "prov_runs")) {
    runs <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash, contract_hash, ",.wb_prov_run_identity_select(con)," FROM prov_runs ORDER BY snapshot_id, run_id;"))
    if (nrow(runs)) {
      ops <- unique(as.character(runs$op_name %||% character(0)))
      ops <- ops[!is.na(ops) & nzchar(ops)]
      for (op in ops) {
        nodes[[length(nodes) + 1L]] <- .wb_kg_node(
          paste0("op:", .wb_kg_slug(op)),
          op,
          "Op",
          "provenance_store_ref",
          text = op,
          payload = list(op_name = op)
        )
      }
      for (i in seq_len(nrow(runs))) {
        rid <- as.character(runs$run_id[i])
        op <- as.character(runs$op_name[i] %||% "")
        rnid <- paste0("run:", .wb_kg_slug(rid))
        nodes[[length(nodes) + 1L]] <- .wb_kg_node(rnid, op %||% rid, "Run", "provenance_store", text = .wb_kg_text(rid, op, runs$notes[i]), payload = as.list(runs[i, , drop = FALSE]))
        edges[[length(edges) + 1L]] <- .wb_kg_edge(rnid, paste0("op:", .wb_kg_slug(op)), "INSTANCE_OF", "provenance_store", confidence = if (nzchar(op)) 1 else 0.5)
        edges[[length(edges) + 1L]] <- .wb_kg_edge(rnid, paste0("session:", .wb_kg_slug(runs$snapshot_id[i])), "BELONGS_TO_SESSION", "provenance_store")
      }
    }
  }

  if (.wb_table_exists(con, "prov_run_edges")) {
    ee <- DBI::dbGetQuery(con, "SELECT snapshot_id, parent_run_id, child_run_id, edge_type, edge_label FROM prov_run_edges ORDER BY snapshot_id, parent_run_id, child_run_id, edge_type;")
    if (nrow(ee)) {
      for (i in seq_len(nrow(ee))) {
        edges[[length(edges) + 1L]] <- .wb_kg_edge(
          paste0("run:", .wb_kg_slug(ee$parent_run_id[i])),
          paste0("run:", .wb_kg_slug(ee$child_run_id[i])),
          "USED_INPUT",
          "provenance_store",
          payload = as.list(ee[i, , drop = FALSE]),
          semantic_label = paste(as.character(ee$edge_type[i]),
                                 as.character(ee$edge_label[i] %||% ""), sep = ":")
        )
      }
    }
  }

  if (.wb_table_exists(con, "prov_source_inputs")) {
    src <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, source_id, source_json, checksum_status FROM prov_source_inputs ORDER BY snapshot_id, run_id, source_id;")
    if (nrow(src)) for (i in seq_len(nrow(src))) {
      declaration <- .wb_validation_json(src$source_json[i]) %||% list()
      scope <- as.character(declaration$scope %||% declaration$source_scope %||% "legacy_external")[1]
      prefix <- if (identical(scope,"in_memory")) "in_memory_source:" else "external_source:"
      node_type <- if (identical(scope,"in_memory")) "InMemorySource" else "ExternalSource"
      snid <- paste0(prefix, .wb_kg_slug(src$source_id[i]))
      source_payload <- as.list(src[i, setdiff(names(src), c("snapshot_id", "run_id")), drop = FALSE])
      nodes[[length(nodes) + 1L]] <- .wb_kg_node(snid, as.character(src$source_id[i]), node_type, "declared_ingestion_input", payload=c(source_payload, list(scope=scope, snapshot_id=src$snapshot_id[i])))
      edges[[length(edges) + 1L]] <- .wb_kg_edge(snid, paste0("run:", .wb_kg_slug(src$run_id[i])), "SUPPLIED_TO", "declared_ingestion_input", payload=as.list(src[i, , drop=FALSE]))
    }
  }

  if (.wb_table_exists(con, "prov_run_outputs")) {
    outs <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id, run_id, output_name, primitive_kind, output_hash, artifact_id, ", .wb_prov_output_identity_select(con), " FROM prov_run_outputs ORDER BY snapshot_id, run_id, output_name;"))
    if (nrow(outs)) {
      arts <- .wb_kg_safe_df(wb_art_list(bundle, include_history = TRUE))
      art_ids <- unique(as.character(outs$artifact_id %||% character(0)))
      art_ids <- art_ids[!is.na(art_ids) & nzchar(art_ids)]
      for (aid_raw in art_ids) {
        art_row <- arts[as.character(arts$artifact_id %||% character(0)) == aid_raw, , drop = FALSE]
        payload <- if (nrow(art_row)) as.list(art_row[1, , drop = FALSE]) else list(artifact_id = aid_raw)
        label <- if (nrow(art_row) && "name" %in% names(art_row) && nzchar(as.character(art_row$name[1]))) as.character(art_row$name[1]) else aid_raw
        nodes[[length(nodes) + 1L]] <- .wb_kg_node(
          paste0("artifact:", .wb_kg_slug(aid_raw)),
          label,
          "Artifact",
          "provenance_store_ref",
          text = .wb_kg_text(aid_raw, label),
          payload = payload
        )
      }
      primitives <- unique(as.character(outs$primitive_kind %||% character(0)))
      primitives <- primitives[!is.na(primitives) & nzchar(primitives)]
      for (pk in primitives) {
        nodes[[length(nodes) + 1L]] <- .wb_kg_node(
          paste0("primitive:", .wb_kg_slug(pk)),
          pk,
          "Primitive",
          "provenance_store_ref",
          text = pk,
          payload = list(primitive_kind = pk)
        )
      }
      for (i in seq_len(nrow(outs))) {
        rid <- paste0("run:", .wb_kg_slug(outs$run_id[i]))
        if (!is.na(outs$artifact_id[i]) && nzchar(as.character(outs$artifact_id[i]))) {
          aid <- paste0("artifact:", .wb_kg_slug(outs$artifact_id[i]))
          edges[[length(edges) + 1L]] <- .wb_kg_edge(rid, aid, "PRODUCED_ARTIFACT", "provenance_store", payload = as.list(outs[i, , drop = FALSE]), semantic_label = as.character(outs$output_name[i]))
        }
        pk <- as.character(outs$primitive_kind[i] %||% "")
        if (nzchar(pk)) {
          edges[[length(edges) + 1L]] <- .wb_kg_edge(rid, paste0("primitive:", .wb_kg_slug(pk)), "PRODUCES", "provenance_store", payload = as.list(outs[i, , drop = FALSE]), semantic_label = as.character(outs$output_name[i]))
        }
      }
    }
  }

  lifecycle <- wb_entity_lifecycle(bundle, include_history = TRUE)
  if (nrow(lifecycle)) for (i in seq_len(nrow(lifecycle))) {
    kind <- as.character(lifecycle$entity_kind[i]); entity_id <- as.character(lifecycle$entity_id[i])
    nid <- paste0("entity:", .wb_kg_slug(paste(kind, entity_id, sep = ":")))
    nodes[[length(nodes) + 1L]] <- .wb_kg_node(
      nid, entity_id, paste0("Durable", tools::toTitleCase(gsub("_", " ", kind))),
      "entity_lifecycle", text = .wb_kg_text(kind, entity_id, lifecycle$lifecycle_state[i]),
      payload = as.list(lifecycle[i, , drop = FALSE])
    )
  }
  supersessions <- wb_entity_supersessions(bundle)
  if (is.data.frame(supersessions) && nrow(supersessions)) for (i in seq_len(nrow(supersessions))) {
    from <- paste0("entity:", .wb_kg_slug(paste(supersessions$successor_kind[i], supersessions$successor_id[i], sep = ":")))
    to <- paste0("entity:", .wb_kg_slug(paste(supersessions$predecessor_kind[i], supersessions$predecessor_id[i], sep = ":")))
    edges[[length(edges) + 1L]] <- .wb_kg_edge(from, to, "SUPERSEDES", "entity_lifecycle", payload = as.list(supersessions[i, , drop = FALSE]))
  }

  if (.wb_table_exists(con,"analysis_capsules")) {
    caps <- wb_capsules(bundle)
    if (nrow(caps)) for (i in seq_len(nrow(caps))) {
      cap <- wb_capsule(bundle,caps$capsule_id[i]); cid <- paste0("capsule:",cap$capsule_id)
      payload <- list(capsule_id=cap$capsule_id,name=cap$name,purpose=cap$purpose,assurance_level=cap$assurance_level,replay_status=cap$replay_status,script_sha256=cap$script_sha256,family_hint=cap$family_hint,catalog_review=cap$catalog_review,relationships=cap$relationships)
      nodes[[length(nodes)+1L]] <- .wb_kg_node(cid,cap$name,"AnalysisCapsule","analysis_capsule",text=.wb_kg_text(cap$name,cap$purpose,"externally executed terminal evidence"),payload=payload)
      for (j in seq_len(nrow(cap$inputs))) {
        iid <- paste0(cap$inputs$entity_kind[j],":",.wb_kg_slug(cap$inputs$entity_id[j]))
        existing_ids <- vapply(nodes,function(x)as.character(x$id[[1L]]),character(1))
        if(!iid%in%existing_ids) nodes[[length(nodes)+1L]] <- .wb_kg_node(iid,cap$inputs$entity_id[j],paste0("Durable",tools::toTitleCase(gsub("_"," ",cap$inputs$entity_kind[j]))),"analysis_capsule_input",payload=as.list(cap$inputs[j,setdiff(names(cap$inputs),"observed_identity_json"),drop=FALSE]))
        edges[[length(edges)+1L]] <- .wb_kg_edge(iid,cid,"CONSUMES","analysis_capsule",semantic_label=cap$inputs$input_name[j],payload=list(binding=cap$inputs$input_name[j]))
      }
      for (j in seq_len(nrow(cap$outputs))) {
        oid <- paste0("capsule_output:",cap$outputs$output_id[j])
        nodes[[length(nodes)+1L]] <- .wb_kg_node(oid,cap$outputs$output_name[j],"AnalysisCapsuleOutput","analysis_capsule",payload=as.list(cap$outputs[j,,drop=FALSE]))
        edges[[length(edges)+1L]] <- .wb_kg_edge(cid,oid,"PRODUCES","analysis_capsule",semantic_label=cap$outputs$output_name[j],payload=list(binding=cap$outputs$output_name[j]))
      }
      if (is.data.frame(cap$relationships) && nrow(cap$relationships)) for(j in seq_len(nrow(cap$relationships))) if(!is.na(cap$relationships$related_capsule_id[j])&&nzchar(cap$relationships$related_capsule_id[j])) edges[[length(edges)+1L]] <- .wb_kg_edge(cid,paste0("capsule:",cap$relationships$related_capsule_id[j]),toupper(cap$relationships$relationship_type[j]),"analysis_capsule",payload=list(assurance="operator_declared_not_engine_proven"))
    }
  }

  list(nodes = .wb_kg_bind(nodes, .wb_kg_node_df()), edges = .wb_kg_bind(edges, .wb_kg_edge_df()))
}

#' Export Bundle Provenance Knowledge Graph
#'
#' Builds run/session/artifact provenance graph nodes and edges from persisted
#' provenance snapshots.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @return A list with `schema_version`, `generated_at`, `nodes`, and `edges`.
#' @export
wb_kg_provenance_graph <- function(bundle) {
  pe <- .wb_kg_provenance_nodes_edges(bundle)
  .wb_kg_normalize_graph(pe$nodes, pe$edges, strict_provenance = TRUE)
}

.wb_kg_combined_graph <- function(bundle = NULL) {
  static <- wb_kg_static_graph()
  nodes <- static$nodes
  edges <- static$edges
  if (!is.null(bundle)) {
    bg <- wb_kg_bundle_graph(bundle)
    pg <- wb_kg_provenance_graph(bundle)
    nodes <- rbind(nodes, bg$nodes, pg$nodes)
    edges <- rbind(edges, bg$edges, pg$edges)
  }
  .wb_kg_normalize_graph(nodes, edges)
}

.wb_kg_catalog_hashes <- function() {
  list(
    scheme = unname(.wb_identity_schemes()[["identifier"]]),
    semantic_catalog = .wb_identifier_sha256(.wb_kg_json(wb_semantic_catalog()), "semantic_catalog"),
    semantic_compatibility_graph = .wb_identifier_sha256(.wb_kg_json(wb_semantic_compatibility_graph()), "semantic_compatibility_graph"),
    parameter_semantics = .wb_identifier_sha256(.wb_kg_json(wb_parameter_semantics_catalog()), "parameter_semantics"),
    recipe_semantics = .wb_identifier_sha256(.wb_kg_json(wb_recipe_semantics_catalog()), "recipe_semantics")
  )
}

.wb_kg_manifest <- function(graph, bundle = NULL) {
  version <- tryCatch(
    as.character(utils::packageVersion("scworkbench")),
    error = function(e) {
      desc <- file.path(getwd(), "DESCRIPTION")
      if (file.exists(desc)) {
        dcf <- read.dcf(desc)
        if ("Version" %in% colnames(dcf)) return(as.character(dcf[1, "Version"]))
      }
      "unknown"
    }
  )
  list(
    schema_version = .wb_kg_schema_version(),
    scworkbench_version = version,
    bundle_id = if (is.null(bundle)) NULL else .wb_kg_bundle_id(bundle),
    created_at = .wb_kg_now(),
    node_count = nrow(graph$nodes),
    edge_count = nrow(graph$edges),
    source_catalog_hashes = .wb_kg_catalog_hashes()
  )
}

.wb_kg_write_jsonl <- function(df, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  if (!nrow(df)) return(invisible(path))
  lines <- vapply(seq_len(nrow(df)), function(i) .wb_kg_json(as.list(df[i, , drop = FALSE])), character(1))
  writeLines(lines, con = con, useBytes = TRUE)
  invisible(path)
}

#' Export Knowledge Graph As JSONL
#'
#' Writes `kg_nodes.jsonl`, `kg_edges.jsonl`, and `kg_manifest.json`.
#'
#' @param bundle Optional open bundle. If supplied, bundle and provenance
#'   instance graph layers are included.
#' @param out_dir Output directory.
#' @return Manifest list.
#' @export
wb_kg_export_jsonl <- function(bundle = NULL, out_dir) {
  .wb_assert(is.character(out_dir) && length(out_dir) == 1L && nzchar(out_dir), "out_dir must be non-empty")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  graph <- .wb_kg_combined_graph(bundle = bundle)
  manifest <- .wb_kg_manifest(graph, bundle = bundle)
  .wb_kg_write_jsonl(graph$nodes, file.path(out_dir, "kg_nodes.jsonl"))
  .wb_kg_write_jsonl(graph$edges, file.path(out_dir, "kg_edges.jsonl"))
  jsonlite::write_json(manifest, file.path(out_dir, "kg_manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(manifest)
}

#' Export Knowledge Graph As Neo4j-Friendly CSV
#'
#' Writes `kg_nodes.csv`, `kg_edges.csv`, and `kg_manifest.json`. Column names
#' are the canonical KG contract fields and are intentionally simple enough for
#' a typed scwb-agent import layer to transform into Neo4j admin/import syntax.
#'
#' @param bundle Optional open bundle. If supplied, bundle and provenance
#'   instance graph layers are included.
#' @param out_dir Output directory.
#' @return Manifest list.
#' @export
wb_kg_export_neo4j_csv <- function(bundle = NULL, out_dir) {
  .wb_assert(is.character(out_dir) && length(out_dir) == 1L && nzchar(out_dir), "out_dir must be non-empty")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  graph <- .wb_kg_combined_graph(bundle = bundle)
  manifest <- .wb_kg_manifest(graph, bundle = bundle)
  utils::write.csv(graph$nodes, file.path(out_dir, "kg_nodes.csv"), row.names = FALSE, na = "")
  utils::write.csv(graph$edges, file.path(out_dir, "kg_edges.csv"), row.names = FALSE, na = "")
  jsonlite::write_json(manifest, file.path(out_dir, "kg_manifest.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(manifest)
}

#' Audit Knowledge Graph Catalog Export
#'
#' Validates canonical KG node/edge schemas, duplicate IDs, dangling edges, and
#' allowed high-level node/edge types. If `bundle` is supplied, audits the
#' combined static + bundle + provenance graph; otherwise audits static graph.
#'
#' @param bundle Optional open bundle.
#' @return Audit list with `ok` and issue vectors.
#' @export
wb_kg_catalog_audit <- function(bundle = NULL) {
  graph <- .wb_kg_combined_graph(bundle = bundle)
  nodes <- graph$nodes
  edges <- graph$edges
  node_cols <- c("id", "label", "node_type", "source", "source_version", "text", "payload_json")
  edge_cols <- c("id", "source_id", "target_id", "edge_type", "source", "confidence", "payload_json")
  missing_node_cols <- setdiff(node_cols, names(nodes))
  missing_edge_cols <- setdiff(edge_cols, names(edges))
  duplicate_node_ids <- nodes$id[duplicated(nodes$id)]
  duplicate_edge_ids <- edges$id[duplicated(edges$id)]
  dangling_edges <- if (nrow(edges) && nrow(nodes)) {
    edges$id[!(edges$source_id %in% nodes$id) | !(edges$target_id %in% nodes$id)]
  } else character(0)
  invalid_payload_nodes <- nodes$id[!vapply(nodes$payload_json, jsonlite::validate, logical(1))]
  invalid_payload_edges <- edges$id[!vapply(edges$payload_json, jsonlite::validate, logical(1))]
  list(
    schema_version = "scworkbench.kg_catalog_audit.v1",
    kg_schema_version = .wb_kg_schema_version(),
    ok = length(c(missing_node_cols, missing_edge_cols, duplicate_node_ids, duplicate_edge_ids, dangling_edges, invalid_payload_nodes, invalid_payload_edges)) == 0L,
    node_count = nrow(nodes),
    edge_count = nrow(edges),
    missing_node_cols = missing_node_cols,
    missing_edge_cols = missing_edge_cols,
    duplicate_node_ids = unique(duplicate_node_ids),
    duplicate_edge_ids = unique(duplicate_edge_ids),
    dangling_edges = unique(dangling_edges),
    invalid_payload_nodes = unique(invalid_payload_nodes),
    invalid_payload_edges = unique(invalid_payload_edges)
  )
}
