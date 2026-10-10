# Ordered node-edge-incidence graph contract. No bundle-axis inference.
.wb_graph_error <- function(code, message) {
  stop(structure(list(message = paste0(code, ": ", message), call = NULL,
    code = code), class = c("wb_graph_error", "error", "condition")))
}

.wb_graph_require <- function(ok, code, message) {
  if (!isTRUE(ok)) .wb_graph_error(code, message)
  invisible(TRUE)
}

.wb_graph_closed <- function(x, fields, where) {
  .wb_graph_require(is.list(x) && !is.null(names(x)) &&
    !anyDuplicated(names(x)) && setequal(names(x), fields),
    "GRAPH_FIELDS_INVALID", paste0(where, " must contain exactly: ",
      paste(fields, collapse = ", ")))
}

.wb_graph_string <- function(x, maximum = 256, empty = FALSE) {
  is.character(x) && length(x) == 1L && !is.na(x) &&
    (empty || nzchar(x)) && !is.na(iconv(x, from = "UTF-8", to = "UTF-8")) &&
    nchar(x, type = "bytes") <= maximum
}

.wb_graph_records <- function(x) {
  if (is.data.frame(x)) {
    .wb_graph_require(!anyDuplicated(names(x)) &&
      !any(vapply(x, is.factor, logical(1))), "GRAPH_FIELDS_INVALID",
      "Data-frame fields must be unique and explicitly typed, not factors.")
    return(lapply(seq_len(nrow(x)), function(i)
      lapply(x, function(column) column[[i]])))
  }
  .wb_graph_require(is.list(x) && is.null(names(x)), "GRAPH_ARRAY_INVALID",
    "Records must be an ordered array or a data frame.")
  x
}

.wb_graph_int64 <- function(x) {
  if (!.wb_graph_string(x, 20) ||
      !grepl("^(0|[1-9][0-9]*|-[1-9][0-9]*)$", x)) return(FALSE)
  negative <- startsWith(x, "-")
  digits <- if (negative) substring(x, 2) else x
  bound <- if (negative) "9223372036854775808" else "9223372036854775807"
  nchar(digits) < nchar(bound) ||
    (nchar(digits) == nchar(bound) && digits <= bound)
}

.wb_graph_f64 <- function(x) {
  if (!.wb_graph_string(x, 16) || !grepl("^[0-9a-f]{16}$", x)) return(FALSE)
  bits <- as.raw(strtoi(substring(x, seq(1, 15, 2), seq(2, 16, 2)), 16L))
  is.finite(readBin(bits, "double", n = 1L, size = 8L, endian = "little"))
}

.wb_graph_scalar <- function(x, type, nullable) {
  if (is.null(x)) return(isTRUE(nullable))
  switch(type, bool = is.logical(x) && length(x) == 1L && !is.na(x),
    utf8 = .wb_graph_string(x, 65536, empty = TRUE),
    int64_decimal_string = .wb_graph_int64(x),
    float64_le_hex = .wb_graph_f64(x), FALSE)
}

.wb_graph_validate_content <- function(content) {
  .wb_graph_closed(content, c("schema", "direction_mode", "nodes", "edges",
    "incidences", "attributes"), "graph content")
  .wb_graph_require(identical(content$schema, "scworkbench.graph.content.v1"),
    "GRAPH_VERSION_UNSUPPORTED", "Unsupported graph content schema.")
  .wb_graph_require(.wb_graph_string(content$direction_mode) &&
    content$direction_mode %in% c("directed", "undirected", "mixed"),
    "GRAPH_DIRECTION_INVALID", "Unsupported graph direction mode.")
  nodes <- .wb_graph_records(content$nodes)
  edges <- .wb_graph_records(content$edges)
  incidences <- .wb_graph_records(content$incidences)
  ids <- function(records, field, fields) {
    values <- vapply(records, function(record) {
      .wb_graph_closed(record, fields, field)
      .wb_graph_require(.wb_graph_string(record[[field]]), "GRAPH_ID_INVALID",
        paste0(field, " must be a nonempty UTF-8 ID, at most 256 bytes."))
      record[[field]]
    }, character(1))
    .wb_graph_require(!anyDuplicated(values), "GRAPH_ID_DUPLICATE", field)
    values
  }
  node_ids <- ids(nodes, "node_id", "node_id")
  edge_ids <- ids(edges, "edge_id", c("edge_id", "kind", "direction"))
  ids(incidences, "incidence_id", c("incidence_id", "edge_id", "node_id",
    "role", "ordinal"))
  for (edge in edges) {
    .wb_graph_require(.wb_graph_string(edge$kind) &&
      edge$kind %in% c("ordinary", "hyper"), "GRAPH_EDGE_KIND_INVALID", edge$edge_id)
    .wb_graph_require(.wb_graph_string(edge$direction) &&
      edge$direction %in% c("directed", "undirected") &&
      (content$direction_mode == "mixed" || content$direction_mode == edge$direction),
      "GRAPH_DIRECTION_INVALID", edge$edge_id)
  }
  edge_positions <- numeric(length(incidences))
  ordinals <- numeric(length(incidences))
  for (i in seq_along(incidences)) {
    item <- incidences[[i]]
    .wb_graph_require(.wb_graph_string(item$node_id) &&
      .wb_graph_string(item$edge_id) && item$node_id %in% node_ids &&
      item$edge_id %in% edge_ids, "GRAPH_INCIDENCE_DANGLING", item$incidence_id)
    position <- match(item$edge_id, edge_ids)
    edge_positions[[i]] <- position
    .wb_graph_require(is.numeric(item$ordinal) && length(item$ordinal) == 1L &&
      !is.na(item$ordinal) && is.finite(item$ordinal) && item$ordinal >= 0 &&
      item$ordinal == floor(item$ordinal) && item$ordinal <= 999999999999999,
      "GRAPH_ORDINAL_INVALID", item$incidence_id)
    ordinals[[i]] <- item$ordinal
    roles <- if (edges[[position]]$direction == "directed") c("tail", "head") else "member"
    .wb_graph_require(.wb_graph_string(item$role) && item$role %in% roles,
      "GRAPH_ROLE_INVALID", item$incidence_id)
  }
  .wb_graph_require(identical(order(edge_positions, ordinals), seq_along(incidences)),
    "GRAPH_ORDER_INVALID", "Incidences must follow edge order and ordinal.")
  for (i in seq_along(edges)) {
    indices <- which(edge_positions == i)
    edge <- edges[[i]]
    .wb_graph_require(length(indices) > 0 &&
      identical(ordinals[indices], as.numeric(seq_along(indices) - 1)),
      "GRAPH_ORDINAL_INVALID", paste0("Missing or gapped incidences: ", edge$edge_id))
    roles <- vapply(incidences[indices], `[[`, character(1), "role")
    directed <- edge$direction == "directed"
    ordinary <- edge$kind == "ordinary"
    valid <- if (ordinary && directed) identical(roles, c("tail", "head")) else
      if (ordinary) length(roles) == 2L else if (directed)
        all(c("tail", "head") %in% roles) else length(roles) >= 1L
    .wb_graph_require(valid, "GRAPH_ARITY_INVALID", edge$edge_id)
  }
  .wb_graph_closed(content$attributes, c("graph", "node", "edge", "incidence"),
    "attributes")
  counts <- c(graph = 1L, node = length(nodes), edge = length(edges),
    incidence = length(incidences))
  for (scope in names(counts)) {
    fields <- .wb_graph_records(content$attributes[[scope]])
    field_names <- character(length(fields))
    for (i in seq_along(fields)) {
      field <- fields[[i]]
      .wb_graph_closed(field, c("name", "type", "nullable", "values"), scope)
      .wb_graph_require(.wb_graph_string(field$name), "GRAPH_ATTRIBUTE_INVALID", scope)
      field_names[[i]] <- field$name
      .wb_graph_require(.wb_graph_string(field$type) && field$type %in%
        c("bool", "utf8", "int64_decimal_string", "float64_le_hex") &&
        is.logical(field$nullable) && length(field$nullable) == 1L &&
        !is.na(field$nullable), "GRAPH_ATTRIBUTE_INVALID", field$name)
      .wb_graph_require(is.list(field$values) && is.null(names(field$values)) &&
        length(field$values) == counts[[scope]] && all(vapply(field$values,
          .wb_graph_scalar, logical(1), type = field$type, nullable = field$nullable)),
        "GRAPH_ATTRIBUTE_INVALID", field$name)
    }
    .wb_graph_require(!anyDuplicated(field_names), "GRAPH_ATTRIBUTE_DUPLICATE", scope)
  }
  invisible(TRUE)
}

#' Construct an Ordered Graph Primitive
#'
#' Standalone nodes, ordinary edges and hyperedges with explicit occurrence IDs.
#' Arrays retain supplied order. Attributes are typed ordered field arrays;
#' scientific meaning remains the operation author's responsibility.
#' @param nodes,edges,incidences Ordered record arrays or explicitly typed data frames.
#' @param graph_attributes,node_attributes,edge_attributes,incidence_attributes
#'   Ordered fields with name, type, nullable and an ordered list of values.
#' @param associations Ordered named bindings. Omitted means unbound, not null.
#' @param direction_mode One of directed, undirected or mixed.
#' @return A graph `wb_primitive`.
#' @export
wb_prim_graph <- function(nodes, edges, incidences, graph_attributes = list(),
  node_attributes = list(), edge_attributes = list(), incidence_attributes = list(),
  associations = list(), direction_mode = "mixed") {
  content <- list(schema = "scworkbench.graph.content.v1",
    direction_mode = direction_mode, nodes = .wb_graph_records(nodes),
    edges = .wb_graph_records(edges), incidences = .wb_graph_records(incidences),
    attributes = list(graph = .wb_graph_records(graph_attributes),
      node = .wb_graph_records(node_attributes), edge = .wb_graph_records(edge_attributes),
      incidence = .wb_graph_records(incidence_attributes)))
  .wb_graph_validate_content(content)
  .wb_graph_require(is.list(associations) && is.null(names(associations)),
    "GRAPH_BINDINGS_INVALID", "Associations must be an ordered array, never null.")
  .wb_graph_bindings_validate(associations,
    vapply(content$nodes, `[[`, character(1), "node_id"))
  structure(list(kind = "graph", content = content, associations = associations),
    class = "wb_primitive")
}

#' Validate a Graph Primitive
#' @param graph Graph primitive.
#' @return Invisibly TRUE, or a typed graph error.
#' @export
wb_graph_validate <- function(graph) {
  .wb_assert_kind(graph, "graph")
  .wb_graph_validate_content(graph$content)
  .wb_graph_bindings_validate(graph$associations,
    vapply(graph$content$nodes, `[[`, character(1), "node_id"))
  invisible(TRUE)
}

#' Encode Finite Binary64 Graph Attribute Values
#' @param values Numeric vector. NA is encoded as explicit null; NaN/Inf reject.
#' @return Ordered list of exact little-endian hex strings or null.
#' @export
wb_graph_encode_finite_f64 <- function(values) {
  .wb_graph_require(is.numeric(values), "GRAPH_ATTRIBUTE_INVALID", "Expected numeric values.")
  lapply(values, function(value) {
    if (is.na(value) && !is.nan(value)) return(NULL)
    .wb_graph_require(is.finite(value), "GRAPH_ATTRIBUTE_INVALID", "Non-finite binary64.")
    paste(sprintf("%02x", as.integer(writeBin(as.double(value), raw(), size = 8L,
      endian = "little"))), collapse = "")
  })
}

.wb_graph_identity <- function(scheme, preimage) {
  list(scheme = scheme, sha256 = digest::digest(charToRaw(
    .wb_operation_pack_canonical_json(preimage)), algo = "sha256", serialize = FALSE))
}

.wb_graph_content_identity <- function(content) {
  .wb_graph_validate_content(content)
  .wb_graph_identity("scworkbench.graph.content.canonical-json.v1", content)
}
