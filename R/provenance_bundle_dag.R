# Bundle-level persisted provenance DAG composition.

.wb_prov_bundle_empty_nodes <- function() {
  data.frame(
    id = character(0),
    node_type = character(0),
    label = character(0),
    title = character(0),
    artifact_id = character(0),
    run_id = character(0),
    snapshot_id = character(0),
    artifact_type = character(0),
    primitive_kind = character(0),
    op_name = character(0),
    created_at = character(0),
    status = character(0),
    lineage_status = character(0),
    canonical = logical(0),
    superseded = logical(0),
    stringsAsFactors = FALSE
  )
}

.wb_prov_bundle_empty_edges <- function() {
  data.frame(
    from = character(0),
    to = character(0),
    edge_type = character(0),
    label = character(0),
    run_id = character(0),
    snapshot_id = character(0),
    artifact_id = character(0),
    stringsAsFactors = FALSE
  )
}

.wb_prov_bundle_node <- function(id,
                                 node_type,
                                 label = NA_character_,
                                 title = NA_character_,
                                 artifact_id = NA_character_,
                                 run_id = NA_character_,
                                 snapshot_id = NA_character_,
                                 artifact_type = NA_character_,
                                 primitive_kind = NA_character_,
                                 op_name = NA_character_,
                                 created_at = NA_character_,
                                 status = NA_character_,
                                 lineage_status = NA_character_,
                                 canonical = NA,
                                 superseded = NA) {
  data.frame(
    id = as.character(id)[1],
    node_type = as.character(node_type)[1],
    label = as.character(label %||% NA_character_)[1],
    title = as.character(title %||% NA_character_)[1],
    artifact_id = as.character(artifact_id %||% NA_character_)[1],
    run_id = as.character(run_id %||% NA_character_)[1],
    snapshot_id = as.character(snapshot_id %||% NA_character_)[1],
    artifact_type = as.character(artifact_type %||% NA_character_)[1],
    primitive_kind = as.character(primitive_kind %||% NA_character_)[1],
    op_name = as.character(op_name %||% NA_character_)[1],
    created_at = as.character(created_at %||% NA_character_)[1],
    status = as.character(status %||% NA_character_)[1],
    lineage_status = as.character(lineage_status %||% NA_character_)[1],
    canonical = as.logical(canonical)[1],
    superseded = as.logical(superseded)[1],
    stringsAsFactors = FALSE
  )
}

.wb_prov_bundle_edge <- function(from,
                                 to,
                                 edge_type,
                                 label = NA_character_,
                                 run_id = NA_character_,
                                 snapshot_id = NA_character_,
                                 artifact_id = NA_character_) {
  data.frame(
    from = as.character(from)[1],
    to = as.character(to)[1],
    edge_type = as.character(edge_type)[1],
    label = as.character(label %||% NA_character_)[1],
    run_id = as.character(run_id %||% NA_character_)[1],
    snapshot_id = as.character(snapshot_id %||% NA_character_)[1],
    artifact_id = as.character(artifact_id %||% NA_character_)[1],
    stringsAsFactors = FALSE
  )
}

.wb_prov_bundle_bind <- function(rows, empty) {
  if (!length(rows)) return(empty())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  unique(out)
}

.wb_prov_json_read <- function(txt) {
  txt <- as.character(txt %||% "")[1]
  if (!nzchar(txt)) return(list())
  out <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
  if (inherits(out, "try-error") || is.null(out)) list() else out
}

.wb_prov_refs_from_object <- function(x, path = "root") {
  refs <- .wb_dag_collect_refs(x, path = path)
  if (!is.data.frame(refs) || !nrow(refs)) {
    return(data.frame(
      path = character(0),
      ref_type = character(0),
      run_id = character(0),
      artifact_id = character(0),
      output = character(0),
      stringsAsFactors = FALSE
    ))
  }
  refs
}

.wb_prov_run_artifact_refs <- function(row) {
  objs <- list()
  sym_txt <- as.character(row$symbolic_inputs_json %||% "")[1]
  inp_txt <- as.character(row$inputs_json %||% "")[1]
  if (nzchar(sym_txt) && !identical(sym_txt, "null")) {
    objs$symbolic_inputs <- .wb_prov_json_read(sym_txt)
  }
  if (nzchar(inp_txt) && !identical(inp_txt, "null")) {
    inp <- .wb_prov_json_read(inp_txt)
    objs$inputs <- inp
    if (is.list(inp$user_inputs)) objs$user_inputs <- inp$user_inputs
    if (is.list(inp$provenance_refs)) objs$provenance_refs <- inp$provenance_refs
  }
  if (!length(objs)) return(.wb_prov_refs_from_object(list()))

  rows <- list()
  k <- 0L
  for (nm in names(objs)) {
    rr <- .wb_prov_refs_from_object(objs[[nm]], path = nm)
    if (!nrow(rr)) next
    k <- k + 1L
    rows[[k]] <- rr
  }
  if (!length(rows)) return(.wb_prov_refs_from_object(list()))
  out <- unique(do.call(rbind, rows))
  out <- out[out$ref_type == "artifact" & nzchar(as.character(out$artifact_id %||% "")), , drop = FALSE]
  rownames(out) <- NULL
  out
}

.wb_prov_bundle_registry_mutations <- function(bundle, artifact_ids) {
  con <- bundle$con
  artifact_ids <- unique(as.character(artifact_ids %||% character(0)))
  artifact_ids <- artifact_ids[nzchar(artifact_ids)]
  if (!length(artifact_ids)) {
    return(list(nodes = .wb_prov_bundle_empty_nodes(), edges = .wb_prov_bundle_empty_edges()))
  }
  if (!.wb_table_exists(con, "artifact_tables") || !.wb_table_exists(con, "artifact_table_rows")) {
    return(list(nodes = .wb_prov_bundle_empty_nodes(), edges = .wb_prov_bundle_empty_edges()))
  }

  cl <- .wb_sql_in_clause(artifact_ids)
  info <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT artifact_id, table_type FROM artifact_tables WHERE table_type = 'winner_cell_set_manifest' ",
      "AND artifact_id ", cl$sql, ";"
    ),
    params = cl$params
  )
  if (!nrow(info)) {
    return(list(nodes = .wb_prov_bundle_empty_nodes(), edges = .wb_prov_bundle_empty_edges()))
  }

  nodes <- list()
  edges <- list()
  ni <- 0L
  ei <- 0L
  for (aid in unique(as.character(info$artifact_id))) {
    rows <- DBI::dbGetQuery(
      con,
      "SELECT row_json FROM artifact_table_rows WHERE artifact_id = ? ORDER BY row_idx;",
      params = list(aid)
    )
    if (!nrow(rows)) next
    for (txt in as.character(rows$row_json)) {
      obj <- .wb_prov_json_read(txt)
      cs <- as.character(obj$cell_set %||% "")[1]
      if (!nzchar(cs)) next
      node_id <- paste0("cell_set:", cs)
      ni <- ni + 1L
      nodes[[ni]] <- .wb_prov_bundle_node(
        id = node_id,
        node_type = "cell_set",
        label = cs,
        title = paste0("Cell set ", cs),
        status = "registered"
      )
      ei <- ei + 1L
      edges[[ei]] <- .wb_prov_bundle_edge(
        from = paste0("artifact:", aid),
        to = node_id,
        edge_type = "MUTATES_REGISTRY",
        label = "registers cell set",
        artifact_id = aid
      )
    }
  }

  list(
    nodes = .wb_prov_bundle_bind(nodes, .wb_prov_bundle_empty_nodes),
    edges = .wb_prov_bundle_bind(edges, .wb_prov_bundle_empty_edges)
  )
}

.wb_prov_bundle_subgraph <- function(graph,
                                     start_ids,
                                     direction = c("both", "upstream", "downstream"),
                                     max_depth = NULL) {
  direction <- match.arg(direction)
  nodes <- graph$nodes
  edges <- graph$edges
  start_ids <- unique(as.character(start_ids %||% character(0)))
  start_ids <- start_ids[nzchar(start_ids) & start_ids %in% as.character(nodes$id)]
  if (!length(start_ids)) {
    return(list(nodes = nodes[0, , drop = FALSE], edges = edges[0, , drop = FALSE]))
  }
  if (!nrow(edges)) {
    keep <- as.character(nodes$id) %in% start_ids
    return(list(nodes = nodes[keep, , drop = FALSE], edges = edges[0, , drop = FALSE]))
  }

  max_depth <- if (is.null(max_depth)) Inf else suppressWarnings(as.integer(max_depth)[1])
  if (!is.finite(max_depth) || max_depth < 0L) max_depth <- Inf

  visited <- character(0)
  queue <- start_ids
  depth <- rep.int(0L, length(queue))
  while (length(queue)) {
    cur <- queue[[1]]
    d <- depth[[1]]
    queue <- queue[-1]
    depth <- depth[-1]
    if (cur %in% visited) next
    visited <- c(visited, cur)
    if (d >= max_depth) next

    nxt <- character(0)
    if (direction %in% c("downstream", "both")) {
      nxt <- c(nxt, as.character(edges$to[as.character(edges$from) == cur]))
    }
    if (direction %in% c("upstream", "both")) {
      nxt <- c(nxt, as.character(edges$from[as.character(edges$to) == cur]))
    }
    nxt <- unique(nxt[nzchar(nxt) & !(nxt %in% visited)])
    if (length(nxt)) {
      queue <- c(queue, nxt)
      depth <- c(depth, rep.int(d + 1L, length(nxt)))
    }
  }

  keep_nodes <- as.character(nodes$id) %in% visited
  keep_edges <- as.character(edges$from) %in% visited & as.character(edges$to) %in% visited
  list(
    nodes = nodes[keep_nodes, , drop = FALSE],
    edges = edges[keep_edges, , drop = FALSE]
  )
}

#' Build A Bundle-Level Composed Provenance DAG
#'
#' Composes all persisted provenance snapshots in a bundle into one graph using
#' stable artifact IDs as the bridge between separately promoted sessions. This
#' is the engine-owned graph contract for clients that need a connected view of
#' promoted analyses without reverse-engineering SQLite or provenance JSON.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param snapshot_id Optional snapshot filter.
#' @param run_id Optional run-centered subgraph filter.
#' @param artifact_id Optional artifact-centered subgraph filter.
#' @param direction Subgraph direction when `run_id` or `artifact_id` is set.
#' @param max_depth Optional maximum graph distance for subgraph filters.
#' @param include_snapshots Include provenance snapshot nodes/edges.
#' @param include_registry_mutations Include cell-set registry mutation nodes
#'   and edges where supported.
#' @param include_superseded Reserved for future engine-owned supersession
#'   state. Current node fields `canonical` and `superseded` are `NA`.
#'
#' @return A list with stable `nodes` and `edges` data.frames.
#' @export
wb_prov_bundle_dag <- function(bundle,
                               snapshot_id = NULL,
                               run_id = NULL,
                               artifact_id = NULL,
                               direction = c("both", "upstream", "downstream"),
                               max_depth = NULL,
                               include_snapshots = TRUE,
                               include_registry_mutations = TRUE,
                               include_superseded = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "bundle-level provenance DAG")
  direction <- match.arg(direction)
  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  wb_migrate_artifacts(bundle)

  sid_filter <- as.character(snapshot_id %||% character(0))
  sid_filter <- sid_filter[nzchar(sid_filter)]
  has_sid_filter <- length(sid_filter) > 0L

  heads <- DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, created_at, created_by, name_prefix, description, schema_version, n_runs, n_artifacts
     FROM prov_heads ORDER BY created_at, snapshot_id;"
  )
  if (has_sid_filter && nrow(heads)) {
    heads <- heads[as.character(heads$snapshot_id) %in% sid_filter, , drop = FALSE]
  }

  runs <- DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, run_id, op_name, created_at, notes, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash
     FROM prov_runs ORDER BY created_at, snapshot_id, run_id;"
  )
  if (has_sid_filter && nrow(runs)) {
    runs <- runs[as.character(runs$snapshot_id) %in% sid_filter, , drop = FALSE]
  }

  outputs <- DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, run_id, output_name, primitive_kind, output_hash, artifact_id
     FROM prov_run_outputs ORDER BY snapshot_id, run_id, output_name;"
  )
  if (has_sid_filter && nrow(outputs)) {
    outputs <- outputs[as.character(outputs$snapshot_id) %in% sid_filter, , drop = FALSE]
  }

  run_edges_src <- DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, parent_run_id, child_run_id, edge_type, edge_label
     FROM prov_run_edges ORDER BY snapshot_id, parent_run_id, child_run_id, edge_type;"
  )
  if (has_sid_filter && nrow(run_edges_src)) {
    run_edges_src <- run_edges_src[as.character(run_edges_src$snapshot_id) %in% sid_filter, , drop = FALSE]
  }

  arts <- wb_art_list(bundle)
  if (!is.data.frame(arts)) arts <- data.frame(stringsAsFactors = FALSE)
  if (has_sid_filter && nrow(arts) && "provenance_snapshot_id" %in% names(arts)) {
    keep_sid <- is.na(arts$provenance_snapshot_id) | !nzchar(as.character(arts$provenance_snapshot_id)) |
      as.character(arts$provenance_snapshot_id) %in% sid_filter |
      as.character(arts$artifact_id) %in% as.character(outputs$artifact_id)
    arts <- arts[keep_sid, , drop = FALSE]
  }

  artifact_kind <- stats::setNames(
    as.character(outputs$primitive_kind %||% character(0)),
    as.character(outputs$artifact_id %||% character(0))
  )

  nodes <- list()
  edges <- list()
  ni <- 0L
  ei <- 0L

  if (isTRUE(include_snapshots) && nrow(heads)) {
    for (i in seq_len(nrow(heads))) {
      sid <- as.character(heads$snapshot_id[i])
      ni <- ni + 1L
      nodes[[ni]] <- .wb_prov_bundle_node(
        id = paste0("snapshot:", sid),
        node_type = "snapshot",
        label = sid,
        title = as.character(heads$name_prefix[i] %||% sid)[1],
        snapshot_id = sid,
        created_at = as.character(heads$created_at[i] %||% NA_character_)[1],
        status = "persisted"
      )
    }
  }

  if (nrow(runs)) {
    runs_unique <- runs[!duplicated(as.character(runs$run_id)), , drop = FALSE]
    for (i in seq_len(nrow(runs_unique))) {
      rid <- as.character(runs_unique$run_id[i])
      ni <- ni + 1L
      nodes[[ni]] <- .wb_prov_bundle_node(
        id = paste0("run:", rid),
        node_type = "run",
        label = as.character(runs_unique$op_name[i] %||% rid)[1],
        title = paste0(as.character(runs_unique$op_name[i] %||% "run")[1], " / ", rid),
        run_id = rid,
        snapshot_id = as.character(runs_unique$snapshot_id[i] %||% NA_character_)[1],
        op_name = as.character(runs_unique$op_name[i] %||% NA_character_)[1],
        created_at = as.character(runs_unique$created_at[i] %||% NA_character_)[1],
        status = "persisted"
      )
    }
  }

  if (nrow(arts)) {
    for (i in seq_len(nrow(arts))) {
      aid <- as.character(arts$artifact_id[i] %||% "")[1]
      if (!nzchar(aid)) next
      pk <- unname(artifact_kind[aid])
      if (length(pk) == 0L || is.na(pk)) pk <- NA_character_
      ni <- ni + 1L
      nodes[[ni]] <- .wb_prov_bundle_node(
        id = paste0("artifact:", aid),
        node_type = "artifact",
        label = as.character(arts$name[i] %||% aid)[1],
        title = paste0(as.character(arts$type[i] %||% "artifact")[1], " / ", aid),
        artifact_id = aid,
        snapshot_id = as.character(arts$provenance_snapshot_id[i] %||% NA_character_)[1],
        artifact_type = as.character(arts$type[i] %||% NA_character_)[1],
        primitive_kind = as.character(pk)[1],
        op_name = as.character(arts$source_op[i] %||% NA_character_)[1],
        created_at = as.character(arts$created_at[i] %||% NA_character_)[1],
        status = "promoted",
        lineage_status = as.character(arts$lineage_status[i] %||% NA_character_)[1],
        canonical = NA,
        superseded = NA
      )
    }
  }

  if (isTRUE(include_snapshots) && nrow(runs)) {
    for (i in seq_len(nrow(runs))) {
      sid <- as.character(runs$snapshot_id[i])
      rid <- as.character(runs$run_id[i])
      ei <- ei + 1L
      edges[[ei]] <- .wb_prov_bundle_edge(
        from = paste0("snapshot:", sid),
        to = paste0("run:", rid),
        edge_type = "HAS_SNAPSHOT",
        label = "contains run",
        run_id = rid,
        snapshot_id = sid
      )
    }
  }

  if (nrow(outputs)) {
    outputs2 <- outputs[!is.na(outputs$artifact_id) & nzchar(as.character(outputs$artifact_id)), , drop = FALSE]
    for (i in seq_len(nrow(outputs2))) {
      aid <- as.character(outputs2$artifact_id[i])
      rid <- as.character(outputs2$run_id[i])
      sid <- as.character(outputs2$snapshot_id[i])
      ei <- ei + 1L
      edges[[ei]] <- .wb_prov_bundle_edge(
        from = paste0("run:", rid),
        to = paste0("artifact:", aid),
        edge_type = "PRODUCES",
        label = as.character(outputs2$output_name[i] %||% "output")[1],
        run_id = rid,
        snapshot_id = sid,
        artifact_id = aid
      )
      if (isTRUE(include_snapshots)) {
        ei <- ei + 1L
        edges[[ei]] <- .wb_prov_bundle_edge(
          from = paste0("artifact:", aid),
          to = paste0("snapshot:", sid),
          edge_type = "PROMOTED_IN",
          label = as.character(outputs2$output_name[i] %||% "output")[1],
          run_id = rid,
          snapshot_id = sid,
          artifact_id = aid
        )
      }
    }
  }

  if (nrow(run_edges_src)) {
    for (i in seq_len(nrow(run_edges_src))) {
      parent <- as.character(run_edges_src$parent_run_id[i])
      child <- as.character(run_edges_src$child_run_id[i])
      sid <- as.character(run_edges_src$snapshot_id[i])
      ei <- ei + 1L
      edges[[ei]] <- .wb_prov_bundle_edge(
        from = paste0("run:", parent),
        to = paste0("run:", child),
        edge_type = "DERIVED_FROM",
        label = as.character(run_edges_src$edge_label[i] %||% run_edges_src$edge_type[i])[1],
        run_id = child,
        snapshot_id = sid
      )
    }
  }

  if (nrow(runs)) {
    for (i in seq_len(nrow(runs))) {
      rr <- .wb_prov_run_artifact_refs(runs[i, , drop = FALSE])
      if (!nrow(rr)) next
      rid <- as.character(runs$run_id[i])
      sid <- as.character(runs$snapshot_id[i])
      for (j in seq_len(nrow(rr))) {
        aid <- as.character(rr$artifact_id[j])
        if (!nzchar(aid)) next
        ei <- ei + 1L
        edges[[ei]] <- .wb_prov_bundle_edge(
          from = paste0("artifact:", aid),
          to = paste0("run:", rid),
          edge_type = "CONSUMES",
          label = as.character(rr$output[j] %||% rr$path[j] %||% "artifact input")[1],
          run_id = rid,
          snapshot_id = sid,
          artifact_id = aid
        )
      }
    }
  }

  dep_edges <- .wb_art_dependency_edges(bundle)
  if (has_sid_filter && nrow(dep_edges) && nrow(arts)) {
    keep_aids <- as.character(arts$artifact_id)
    dep_edges <- dep_edges[
      as.character(dep_edges$parent_artifact_id) %in% keep_aids |
        as.character(dep_edges$child_artifact_id) %in% keep_aids,
      ,
      drop = FALSE
    ]
  }
  if (nrow(dep_edges)) {
    for (i in seq_len(nrow(dep_edges))) {
      parent <- as.character(dep_edges$parent_artifact_id[i])
      child <- as.character(dep_edges$child_artifact_id[i])
      ei <- ei + 1L
      edges[[ei]] <- .wb_prov_bundle_edge(
        from = paste0("artifact:", parent),
        to = paste0("artifact:", child),
        edge_type = "DERIVED_FROM",
        label = "parent artifact",
        artifact_id = child
      )
    }
  }

  nodes_df <- .wb_prov_bundle_bind(nodes, .wb_prov_bundle_empty_nodes)
  edges_df <- .wb_prov_bundle_bind(edges, .wb_prov_bundle_empty_edges)

  if (isTRUE(include_registry_mutations)) {
    reg <- .wb_prov_bundle_registry_mutations(
      bundle = bundle,
      artifact_ids = nodes_df$artifact_id[nodes_df$node_type == "artifact"]
    )
    if (nrow(reg$nodes)) nodes_df <- unique(rbind(nodes_df, reg$nodes))
    if (nrow(reg$edges)) edges_df <- unique(rbind(edges_df, reg$edges))
  }

  if (nrow(edges_df)) {
    node_ids <- as.character(nodes_df$id)
    keep <- as.character(edges_df$from) %in% node_ids & as.character(edges_df$to) %in% node_ids
    edges_df <- edges_df[keep, , drop = FALSE]
    edges_df <- unique(edges_df[order(edges_df$from, edges_df$to, edges_df$edge_type), , drop = FALSE])
    rownames(edges_df) <- NULL
  }
  if (nrow(nodes_df)) {
    nodes_df <- unique(nodes_df[order(nodes_df$node_type, nodes_df$id), , drop = FALSE])
    rownames(nodes_df) <- NULL
  }

  graph <- list(
    nodes = nodes_df,
    edges = edges_df,
    schema = "scworkbench.provenance.bundle_dag.v1",
    filters = list(
      snapshot_id = sid_filter,
      run_id = run_id %||% NULL,
      artifact_id = artifact_id %||% NULL,
      direction = direction,
      max_depth = max_depth %||% NULL,
      include_snapshots = isTRUE(include_snapshots),
      include_registry_mutations = isTRUE(include_registry_mutations),
      include_superseded = isTRUE(include_superseded)
    )
  )

  starts <- character(0)
  if (!is.null(run_id)) {
    starts <- c(starts, paste0("run:", unique(as.character(run_id))))
  }
  if (!is.null(artifact_id)) {
    starts <- c(starts, paste0("artifact:", unique(as.character(artifact_id))))
  }
  starts <- starts[nzchar(starts)]
  if (length(starts)) {
    sub <- .wb_prov_bundle_subgraph(graph, start_ids = starts, direction = direction, max_depth = max_depth)
    graph$nodes <- sub$nodes
    graph$edges <- sub$edges
  }

  graph
}

#' Get Composed Provenance Lineage Around One Artifact
#'
#' Convenience wrapper over [wb_prov_bundle_dag()] for artifact-centered
#' upstream, downstream, or bidirectional lineage views.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact ID to center.
#' @param direction `"upstream"`, `"downstream"`, or `"both"`.
#' @param max_depth Optional maximum graph distance.
#' @param ... Additional arguments passed to [wb_prov_bundle_dag()].
#'
#' @return A composed provenance graph list with `nodes` and `edges`.
#' @export
wb_prov_artifact_lineage <- function(bundle,
                                     artifact_id,
                                     direction = c("both", "upstream", "downstream"),
                                     max_depth = NULL,
                                     ...) {
  direction <- match.arg(direction)
  wb_prov_bundle_dag(
    bundle = bundle,
    artifact_id = artifact_id,
    direction = direction,
    max_depth = max_depth,
    ...
  )
}
