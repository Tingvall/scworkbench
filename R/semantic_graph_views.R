# Human-facing graph exports for the semantic compatibility graph.

.wb_semantic_graph_nodes_table <- function(catalog) {
  nodes <- catalog$graph$nodes %||% list()
  if (!length(nodes)) {
    return(data.frame(
      record_id = character(0),
      record_type = character(0),
      name = character(0),
      title = character(0),
      description = character(0),
      stringsAsFactors = FALSE
    ))
  }

  records <- catalog$records %||% list()
  desc <- stats::setNames(
    vapply(records, function(x) as.character(x$description %||% ""), character(1)),
    vapply(records, function(x) as.character(x$record_id %||% ""), character(1))
  )

  out <- do.call(rbind, lapply(nodes, function(x) {
    id <- as.character(x$record_id %||% "")[1]
    data.frame(
      record_id = id,
      record_type = as.character(x$record_type %||% "")[1],
      name = as.character(x$name %||% "")[1],
      title = as.character(x$title %||% "")[1],
      description = as.character(desc[[id]] %||% "")[1],
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

.wb_semantic_graph_edges_table <- function(graph) {
  edges <- graph$edges %||% list()
  if (!length(edges)) {
    return(data.frame(
      from = character(0),
      to = character(0),
      edge_type = character(0),
      label = character(0),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, lapply(edges, function(e) {
    data.frame(
      from = as.character(e$from %||% "")[1],
      to = as.character(e$to %||% "")[1],
      edge_type = as.character(e$edge_type %||% "")[1],
      label = as.character(e$label %||% "")[1],
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

.wb_semantic_graph_filter_tables <- function(nodes, edges, record_types = NULL,
                                             edge_types = NULL, node_regex = NULL,
                                             include_neighbors = FALSE) {
  selected_ids <- nodes$record_id

  if (!is.null(record_types)) {
    record_types <- as.character(record_types)
    selected_ids <- intersect(selected_ids, nodes$record_id[nodes$record_type %in% record_types])
  }

  if (!is.null(node_regex) && nzchar(as.character(node_regex)[1])) {
    pat <- as.character(node_regex)[1]
    text <- paste(nodes$record_id, nodes$record_type, nodes$name, nodes$title, nodes$description, sep = "\n")
    matched <- nodes$record_id[grepl(pat, text, ignore.case = TRUE)]
    matched <- intersect(matched, selected_ids)
    if (isTRUE(include_neighbors)) {
      neigh <- unique(c(
        edges$from[edges$to %in% matched],
        edges$to[edges$from %in% matched]
      ))
      matched <- unique(c(matched, neigh))
      matched <- intersect(matched, selected_ids)
    }
    selected_ids <- matched
  }

  out_edges <- edges[edges$from %in% selected_ids & edges$to %in% selected_ids, , drop = FALSE]
  if (!is.null(edge_types)) {
    edge_types <- as.character(edge_types)
    out_edges <- out_edges[out_edges$edge_type %in% edge_types, , drop = FALSE]
    selected_ids <- unique(c(out_edges$from, out_edges$to, selected_ids))
  }

  out_nodes <- nodes[nodes$record_id %in% selected_ids, , drop = FALSE]
  out_nodes <- out_nodes[order(out_nodes$record_type, out_nodes$record_id), , drop = FALSE]
  out_edges <- out_edges[order(out_edges$edge_type, out_edges$from, out_edges$to), , drop = FALSE]
  rownames(out_nodes) <- NULL
  rownames(out_edges) <- NULL
  list(nodes = out_nodes, edges = out_edges)
}

#' Export Semantic Compatibility Graph Tables
#'
#' Converts the semantic compatibility graph into node and edge tables that can
#' be inspected directly or imported into graph tools.
#'
#' @param bundle Optional open bundle, passed through to semantic catalog export.
#' @param record_types Optional record types to retain, such as `"op"`,
#'   `"primitive"`, `"artifact_type"`, `"wrangler"`, `"plot"`, `"getter"`,
#'   `"parameter"`, or `"recipe"`.
#' @param edge_types Optional edge types to retain, such as `"produces"`,
#'   `"consumed_by"`, `"loads_as"`, `"wrangled_by"`, `"feeds_plot"`, or
#'   `"uses"`.
#' @param node_regex Optional case-insensitive regular expression matched
#'   against node id, type, name, title, and description.
#' @param include_neighbors If `TRUE`, include graph neighbors of nodes matched
#'   by `node_regex`.
#' @return A list with `nodes` and `edges` data frames.
#' @export
wb_semantic_graph_tables <- function(bundle = NULL,
                                     record_types = NULL,
                                     edge_types = NULL,
                                     node_regex = NULL,
                                     include_neighbors = FALSE) {
  catalog <- wb_semantic_catalog(bundle = bundle)
  nodes <- .wb_semantic_graph_nodes_table(catalog)
  edges <- .wb_semantic_graph_edges_table(catalog$graph)
  .wb_semantic_graph_filter_tables(
    nodes = nodes,
    edges = edges,
    record_types = record_types,
    edge_types = edge_types,
    node_regex = node_regex,
    include_neighbors = include_neighbors
  )
}

.wb_dot_escape <- function(x) {
  x <- as.character(x %||% "")[1]
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x
}

.wb_semantic_graph_node_fill <- function(record_type) {
  fill <- c(
    op = "#b7d9f2",
    primitive = "#bde8bf",
    artifact_type = "#f3d27a",
    wrangler = "#f2b779",
    plot = "#d8b6e8",
    getter = "#d8d8d8",
    parameter = "#f3b6c6",
    recipe = "#efe6a0"
  )
  unname(fill[[as.character(record_type %||% "")[1]]] %||% "#eeeeee")
}

.wb_semantic_graph_edge_style <- function(edge_type) {
  type <- as.character(edge_type %||% "")[1]
  if (type %in% c("used_by_recipe", "produced_by_recipe")) return("style=dotted,color=\"#777777\"")
  if (type %in% c("has_parameter_semantics")) return("style=dashed,color=\"#b24c6a\"")
  if (type %in% c("feeds_plot", "wrangled_by")) return("color=\"#8a5ca8\"")
  if (type %in% c("loads_as")) return("color=\"#7a5a00\"")
  if (type %in% c("produces", "consumed_by")) return("color=\"#2f6f8f\"")
  "color=\"#555555\""
}

.wb_svg_escape <- function(x) {
  x <- as.character(x %||% "")[1]
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x
}

.wb_svg_short_label <- function(x, n = 42L) {
  x <- as.character(x %||% "")[1]
  if (nchar(x) <= n) return(x)
  paste0(substr(x, 1L, n - 1L), "...")
}

.wb_semantic_graph_svg <- function(tables, title = NULL) {
  nodes <- tables$nodes
  edges <- tables$edges
  type_order <- c("recipe", "getter", "op", "parameter", "artifact_type", "primitive", "wrangler", "plot")
  present_types <- unique(as.character(nodes$record_type))
  types <- c(intersect(type_order, present_types), setdiff(sort(present_types), type_order))

  col_w <- 330
  row_h <- 72
  margin_x <- 40
  margin_y <- 80
  node_w <- 260
  node_h <- 46

  pos <- data.frame(record_id = character(0), x = numeric(0), y = numeric(0), stringsAsFactors = FALSE)
  for (j in seq_along(types)) {
    ids <- nodes$record_id[nodes$record_type == types[[j]]]
    ids <- sort(ids)
    if (!length(ids)) next
    pos <- rbind(pos, data.frame(
      record_id = ids,
      x = margin_x + (j - 1L) * col_w,
      y = margin_y + (seq_along(ids) - 1L) * row_h,
      stringsAsFactors = FALSE
    ))
  }
  rownames(pos) <- NULL
  pmap <- split(pos, pos$record_id)

  max_rows <- max(1L, max(tabulate(match(nodes$record_type, types)), 1L))
  width <- margin_x * 2 + max(1L, length(types)) * col_w
  height <- margin_y + max_rows * row_h + 80

  lines <- c(
    paste0("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"", width, "\" height=\"", height, "\" viewBox=\"0 0 ", width, " ", height, "\">"),
    "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>",
    "<defs><marker id=\"arrow\" markerWidth=\"10\" markerHeight=\"10\" refX=\"9\" refY=\"3\" orient=\"auto\" markerUnits=\"strokeWidth\"><path d=\"M0,0 L0,6 L9,3 z\" fill=\"#555\"/></marker></defs>",
    paste0("<text x=\"", margin_x, "\" y=\"34\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"22\" font-weight=\"700\">", .wb_svg_escape(title %||% "scworkbench Semantic Graph"), "</text>")
  )

  for (j in seq_along(types)) {
    x <- margin_x + (j - 1L) * col_w
    lines <- c(lines, paste0(
      "<text x=\"", x, "\" y=\"60\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"12\" font-weight=\"700\" fill=\"#555\">",
      .wb_svg_escape(types[[j]]), "</text>"
    ))
  }

  for (i in seq_len(nrow(edges))) {
    e <- edges[i, , drop = FALSE]
    if (!(e$from %in% names(pmap)) || !(e$to %in% names(pmap))) next
    a <- pmap[[e$from]]
    b <- pmap[[e$to]]
    x1 <- a$x + node_w
    y1 <- a$y + node_h / 2
    x2 <- b$x
    y2 <- b$y + node_h / 2
    if (x2 < x1) {
      x1 <- a$x
      x2 <- b$x + node_w
    }
    lines <- c(lines, paste0(
      "<line x1=\"", x1, "\" y1=\"", y1, "\" x2=\"", x2, "\" y2=\"", y2,
      "\" stroke=\"#555\" stroke-opacity=\"0.22\" stroke-width=\"1.2\" marker-end=\"url(#arrow)\"><title>",
      .wb_svg_escape(paste(e$from, e$edge_type, e$to)), "</title></line>"
    ))
  }

  for (i in seq_len(nrow(nodes))) {
    rec <- nodes[i, , drop = FALSE]
    p <- pmap[[rec$record_id]]
    fill <- .wb_semantic_graph_node_fill(rec$record_type)
    title_label <- .wb_svg_short_label(if (nzchar(rec$title)) rec$title else rec$name)
    id_label <- .wb_svg_short_label(rec$record_id, n = 48L)
    lines <- c(lines, paste0(
      "<g><title>", .wb_svg_escape(paste(rec$record_id, rec$description, sep = "\n")), "</title>",
      "<rect x=\"", p$x, "\" y=\"", p$y, "\" width=\"", node_w, "\" height=\"", node_h,
      "\" rx=\"8\" fill=\"", fill, "\" stroke=\"#555\" stroke-opacity=\"0.55\"/>",
      "<text x=\"", p$x + 10, "\" y=\"", p$y + 18, "\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"11\" font-weight=\"700\">",
      .wb_svg_escape(title_label), "</text>",
      "<text x=\"", p$x + 10, "\" y=\"", p$y + 34, "\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"9\" fill=\"#333\">",
      .wb_svg_escape(id_label), "</text></g>"
    ))
  }

  paste(c(lines, "</svg>"), collapse = "\n")
}

#' Export Semantic Compatibility Graph As Graphviz DOT
#'
#' Produces a Graphviz DOT document for visual inspection of semantic catalog
#' relationships. Render with `dot -Tpng file.dot -o file.png` or import into a
#' compatible graph viewer.
#'
#' @inheritParams wb_semantic_graph_tables
#' @param title Optional graph label.
#' @return A single DOT string.
#' @export
wb_semantic_graph_dot <- function(bundle = NULL,
                                  record_types = NULL,
                                  edge_types = NULL,
                                  node_regex = NULL,
                                  include_neighbors = FALSE,
                                  title = NULL) {
  tbl <- wb_semantic_graph_tables(
    bundle = bundle,
    record_types = record_types,
    edge_types = edge_types,
    node_regex = node_regex,
    include_neighbors = include_neighbors
  )
  nodes <- tbl$nodes
  edges <- tbl$edges

  node_keys <- stats::setNames(paste0("n", seq_len(nrow(nodes))), nodes$record_id)
  lines <- c(
    "digraph scworkbench_semantic_graph {",
    "  graph [rankdir=LR, overlap=false, splines=true, bgcolor=\"white\"];",
    "  node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fontsize=10, color=\"#555555\"];",
    "  edge [fontname=\"Helvetica\", fontsize=8, arrowsize=0.7];"
  )
  if (!is.null(title) && nzchar(as.character(title)[1])) {
    lines <- c(lines, paste0("  label=\"", .wb_dot_escape(title), "\";"), "  labelloc=\"t\";", "  fontsize=18;")
  }

  for (i in seq_len(nrow(nodes))) {
    rec <- nodes[i, , drop = FALSE]
    label <- paste(as.character(rec$title %||% rec$name), as.character(rec$record_id), sep = "\n")
    lines <- c(lines, paste0(
      "  ", node_keys[[rec$record_id]], " [label=\"", .wb_dot_escape(label),
      "\", fillcolor=\"", .wb_semantic_graph_node_fill(rec$record_type), "\"];"
    ))
  }
  for (i in seq_len(nrow(edges))) {
    e <- edges[i, , drop = FALSE]
    if (!(e$from %in% names(node_keys)) || !(e$to %in% names(node_keys))) next
    lines <- c(lines, paste0(
      "  ", node_keys[[e$from]], " -> ", node_keys[[e$to]],
      " [label=\"", .wb_dot_escape(e$edge_type), "\", ",
      .wb_semantic_graph_edge_style(e$edge_type), "];"
    ))
  }
  lines <- c(lines, "}")
  paste(lines, collapse = "\n")
}

#' Write Semantic Compatibility Graph Views
#'
#' Writes CSV node/edge tables plus a small set of Graphviz DOT and SVG views
#' for the semantic compatibility graph.
#'
#' @param out_dir Output directory.
#' @param bundle Optional open bundle, passed through to semantic catalog export.
#' @return Invisibly returns a manifest data frame of written files.
#' @export
wb_write_semantic_graph_views <- function(out_dir = "docs/semantic_graphs", bundle = NULL) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  full <- wb_semantic_graph_tables(bundle = bundle)
  nodes_path <- file.path(out_dir, "semantic_graph_nodes.csv")
  edges_path <- file.path(out_dir, "semantic_graph_edges.csv")
  utils::write.csv(full$nodes, nodes_path, row.names = FALSE)
  utils::write.csv(full$edges, edges_path, row.names = FALSE)

  views <- list(
    list(name = "full", title = "Full Semantic Compatibility Graph"),
    list(name = "ops_primitives", title = "Ops, Primitives, And Operation I/O", record_types = c("op", "primitive"), edge_types = c("consumed_by", "produces")),
    list(name = "artifact_plotting", title = "Artifacts To Primitives To Wranglers To Plots", record_types = c("artifact_type", "primitive", "wrangler", "plot"), edge_types = c("loads_as", "wrangled_by", "feeds_plot")),
    list(name = "recipes", title = "Recipes And The Engine Surfaces They Use", record_types = c("recipe", "op", "getter", "plot", "wrangler", "artifact_type", "parameter"), edge_types = c("uses", "used_by_recipe", "recipe_produces", "produced_by_recipe")),
    list(name = "parameters", title = "Ops And Shared Parameter Semantics", record_types = c("op", "parameter"), edge_types = c("has_parameter_semantics")),
    list(name = "trajectory_dynamics", title = "Trajectory Dynamics Neighborhood", node_regex = "trajectory|pseudotime|gene.?set|signal", include_neighbors = TRUE)
  )

  manifest <- data.frame(
    file = c(nodes_path, edges_path),
    view = c("nodes", "edges"),
    kind = c("csv", "csv"),
    stringsAsFactors = FALSE
  )

  for (view in views) {
    args <- view
    name <- args$name
    title <- args$title
    args$name <- NULL
    args$title <- NULL
    graph_args <- c(list(bundle = bundle), args)
    tables <- do.call(wb_semantic_graph_tables, graph_args)
    dot <- do.call(wb_semantic_graph_dot, c(graph_args, list(title = title)))
    path <- file.path(out_dir, paste0("semantic_graph_", name, ".dot"))
    writeLines(dot, con = path, useBytes = TRUE)
    manifest <- rbind(manifest, data.frame(file = path, view = name, kind = "dot", stringsAsFactors = FALSE))
    svg <- .wb_semantic_graph_svg(tables, title = title)
    svg_path <- file.path(out_dir, paste0("semantic_graph_", name, ".svg"))
    writeLines(svg, con = svg_path, useBytes = TRUE)
    manifest <- rbind(manifest, data.frame(file = svg_path, view = name, kind = "svg", stringsAsFactors = FALSE))
  }

  manifest_path <- file.path(out_dir, "semantic_graph_manifest.csv")
  utils::write.csv(manifest, manifest_path, row.names = FALSE)
  manifest <- rbind(manifest, data.frame(file = manifest_path, view = "manifest", kind = "csv", stringsAsFactors = FALSE))
  rownames(manifest) <- NULL
  invisible(manifest)
}
