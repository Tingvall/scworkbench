# Graph-backed semantic planning helpers.

.wb_semantic_record_map <- function(catalog) {
  records <- catalog$records %||% list()
  ids <- vapply(records, function(x) as.character(x$record_id %||% ""), character(1))
  stats::setNames(records, ids)
}

.wb_semantic_artifact_record_id <- function(bundle, artifact_id) {
  aid <- as.character(artifact_id %||% "")[1]
  .wb_assert(nzchar(aid), "artifact_id must be non-empty")

  art <- wb_art_list(bundle)
  row <- art[as.character(art$artifact_id %||% "") == aid, , drop = FALSE]
  .wb_assert(nrow(row) == 1L, paste0("Artifact not found: ", aid))
  artifact_type <- as.character(row$type[1] %||% "")[1]

  table_type <- NULL
  entity_kind <- NULL
  if (artifact_type %in% c("obs_table", "feature_table")) {
    ti <- try(wb_art_table_info(bundle, aid), silent = TRUE)
    if (!inherits(ti, "try-error") && is.data.frame(ti) && nrow(ti) == 1L) {
      table_type <- as.character(ti$table_type[1] %||% "")[1]
      entity_kind <- as.character(ti$entity_kind[1] %||% "")[1]
    }
  }

  specific <- if (!is.null(table_type) && nzchar(table_type)) paste0("artifact_type:", artifact_type, ":", table_type) else ""
  generic <- paste0("artifact_type:", artifact_type)

  list(
    artifact_id = aid,
    artifact_type = artifact_type,
    table_type = table_type,
    entity_kind = entity_kind,
    specific_record_id = specific,
    generic_record_id = generic,
    registry_row = row
  )
}

.wb_semantic_graph_edges_df <- function(graph) {
  edges <- graph$edges %||% list()
  if (!length(edges)) {
    return(data.frame(from = character(0), to = character(0), edge_type = character(0), label = character(0), stringsAsFactors = FALSE))
  }
  out <- do.call(rbind, lapply(edges, function(e) {
    data.frame(
      from = as.character(e$from %||% ""),
      to = as.character(e$to %||% ""),
      edge_type = as.character(e$edge_type %||% ""),
      label = as.character(e$label %||% ""),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

.wb_semantic_plan_record_table <- function(record_ids, record_map, relation = "") {
  record_ids <- unique(as.character(record_ids))
  record_ids <- record_ids[nzchar(record_ids) & record_ids %in% names(record_map)]
  if (!length(record_ids)) {
    return(data.frame(
      record_id = character(0),
      record_type = character(0),
      name = character(0),
      title = character(0),
      description = character(0),
      relation = character(0),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, lapply(record_ids, function(id) {
    rec <- record_map[[id]]
    data.frame(
      record_id = as.character(rec$record_id %||% id),
      record_type = as.character(rec$record_type %||% ""),
      name = as.character(rec$name %||% ""),
      title = as.character(rec$title %||% ""),
      description = as.character(rec$description %||% ""),
      relation = as.character(relation %||% ""),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

#' Plan Next Actions For A Promoted Artifact
#'
#' Uses the semantic compatibility graph to answer: given this artifact, what
#' can an agent do next? The helper inspects the artifact type/table type,
#' follows artifact-to-primitive, primitive-to-wrangler, wrangler-to-plot, and
#' primitive-to-op edges, and returns candidate actions with caveats.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Promoted artifact id.
#' @param include_recipes Include recipe records connected to the artifact,
#'   primitive, compatible ops, plots, or wranglers.
#' @return A named list with artifact identity, candidate actions, graph edges,
#'   and caveats.
#' @export
wb_semantic_plan_artifact_next_steps <- function(bundle, artifact_id, include_recipes = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be an open scworkbench_bundle")
  info <- .wb_semantic_artifact_record_id(bundle, artifact_id)
  catalog <- wb_semantic_catalog(bundle = bundle)
  graph <- catalog$graph
  record_map <- .wb_semantic_record_map(catalog)
  edges <- .wb_semantic_graph_edges_df(graph)

  start_ids <- unique(c(info$specific_record_id, info$generic_record_id))
  start_ids <- start_ids[nzchar(start_ids) & start_ids %in% names(record_map)]

  primitive_ids <- unique(edges$to[edges$from %in% start_ids & edges$edge_type == "loads_as"])
  primitive_ids <- primitive_ids[primitive_ids %in% names(record_map)]

  wrangler_ids <- unique(edges$to[edges$from %in% c(start_ids, primitive_ids) & edges$edge_type == "wrangled_by"])
  if ("wrangler:table:client_load_table" %in% names(record_map)) {
    wrangler_ids <- unique(c("wrangler:table:client_load_table", wrangler_ids))
  }
  plot_ids <- unique(edges$to[edges$from %in% wrangler_ids & edges$edge_type == "feeds_plot"])
  downstream_op_ids <- unique(edges$to[edges$from %in% primitive_ids & edges$edge_type == "consumed_by"])

  related_ids <- unique(c(start_ids, primitive_ids, wrangler_ids, plot_ids, downstream_op_ids))
  recipe_ids <- character(0)
  if (isTRUE(include_recipes)) {
    recipe_edges <- edges[edges$edge_type %in% c("uses", "recipe_produces", "used_by_recipe", "produced_by_recipe"), , drop = FALSE]
    recipe_ids <- unique(c(
      recipe_edges$from[grepl("^recipe:", recipe_edges$from) & recipe_edges$to %in% related_ids],
      recipe_edges$to[grepl("^recipe:", recipe_edges$to) & recipe_edges$from %in% related_ids]
    ))
    recipe_ids <- recipe_ids[recipe_ids %in% names(record_map)]
  }

  action_edges <- edges[
    edges$from %in% related_ids | edges$to %in% related_ids | edges$from %in% recipe_ids,
    ,
    drop = FALSE
  ]

  identity <- try(wb_art_identity_card(bundle, artifact_id = info$artifact_id), silent = TRUE)
  if (inherits(identity, "try-error")) identity <- NULL

  list(
    schema_version = "scworkbench.semantic_artifact_plan.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    artifact = list(
      artifact_id = info$artifact_id,
      artifact_type = info$artifact_type,
      table_type = info$table_type,
      entity_kind = info$entity_kind,
      semantic_record_ids = start_ids,
      name = as.character(info$registry_row$name[1] %||% ""),
      source_op = as.character(info$registry_row$source_op[1] %||% ""),
      created_at = as.character(info$registry_row$created_at[1] %||% "")
    ),
    primitive = .wb_semantic_plan_record_table(primitive_ids, record_map, relation = "loads_as"),
    plots = .wb_semantic_plan_record_table(plot_ids, record_map, relation = "via_compatible_wrangler"),
    wranglers = .wb_semantic_plan_record_table(wrangler_ids, record_map, relation = "wrangled_by"),
    downstream_ops = .wb_semantic_plan_record_table(downstream_op_ids, record_map, relation = "primitive_consumed_by"),
    recipes = .wb_semantic_plan_record_table(recipe_ids, record_map, relation = "mentions_artifact_or_compatible_action"),
    graph_edges = action_edges,
    identity_card = identity,
    caveats = c(
      "Graph compatibility means technically possible, not biologically appropriate.",
      "Use artifact provenance, source op, and parameter semantics before making biological claims.",
      "For table artifacts, table_type-specific semantics are preferred over generic primitive kind."
    )
  )
}
