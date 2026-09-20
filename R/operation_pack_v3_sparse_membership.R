# Generic ABI-v3 typed-space and sparse-membership contracts.

.wb_operation_pack_v3_space_matrix <- function(value) {
  if (is.matrix(value)) return(value)
  if (is.data.frame(value)) return(.wb_as_coord_matrix(value))
  .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Typed-space source is not a supported logical space view.",
    "resolution")
}

.wb_operation_pack_v3_selector_values <- function(bundle, value, parameter,
                                                     default_all = FALSE) {
  universe <- as.character(wb_cells(bundle, cell_set = "all"))
  if (is.null(value)) {
    if (!isTRUE(default_all)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Cell selector parameter '", parameter, "' is required."),
      "resolution")
    return(universe)
  }
  raw <- if (is.list(value) && !is.null(value$cell_set)) value$cell_set else
    value
  if (is.list(raw) && is.null(raw$cell_set)) raw <- as.character(unlist(raw,
    use.names = FALSE))
  if (is.character(raw) && length(raw) > 1L && anyDuplicated(raw))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Cell selector parameter '", parameter,
        "' contains duplicate identifiers."), "resolution")
  known <- tryCatch(as.character(wb_cell_sets(bundle)), error = function(e)
    character())
  symbolic <- is.character(raw) && length(raw) == 1L &&
    (startsWith(raw, "set:") || raw %in% c("core", "all", known))
  if (is.character(raw) && !symbolic && length(setdiff(raw, universe)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Cell selector parameter '", parameter,
        "' contains cells outside the declared bundle universe."),
      "resolution")
  selected <- tryCatch(.wb_resolve_group_cells(bundle, raw, universe),
    error = function(error) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Cell selector parameter '", parameter, "' is invalid: ",
        conditionMessage(error)), "resolution"))
  selected <- as.character(selected)
  if (!length(selected) || anyNA(selected) || any(!nzchar(selected)) ||
      anyDuplicated(selected) || length(setdiff(selected, universe)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Cell selector parameter '", parameter,
        "' did not resolve to a nonempty unique bundle-cell axis."),
      "resolution")
  selected
}

.wb_operation_pack_v3_bind_cell_selectors <- function(bundle, operation,
                                                        params) {
  declarations <- operation$cell_selector_axes %||% list()
  if (!length(declarations)) return(params)
  resolved <- list()
  for (declaration in declarations) {
    parameter <- as.character(declaration$parameter)[1]
    resolved[[parameter]] <- .wb_operation_pack_v3_selector_values(bundle,
      params[[parameter]], parameter,
      default_all = isTRUE(declaration$default_all_cells))
  }
  include_parameter <- unique(vapply(declarations, function(x)
    as.character(x$include_query_parameter %||% "")[1], character(1)))
  include_parameter <- include_parameter[nzchar(include_parameter)]
  candidate <- Filter(function(x) identical(as.character(x$role)[1],
    "candidate"), declarations)
  query <- Filter(function(x) identical(as.character(x$role)[1],
    "query"), declarations)
  if (length(candidate) == 1L && length(query) == 1L &&
      length(include_parameter) == 1L &&
      !isTRUE(params[[include_parameter]])) {
    candidate_parameter <- as.character(candidate[[1]]$parameter)[1]
    query_parameter <- as.character(query[[1]]$parameter)[1]
    resolved[[candidate_parameter]] <- resolved[[candidate_parameter]][
      !resolved[[candidate_parameter]] %in% resolved[[query_parameter]]]
    if (!length(resolved[[candidate_parameter]]))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Candidate axis is empty after applying include_query = false.",
        "resolution")
  }
  for (name in names(resolved)) params[[name]] <- unname(as.list(
    resolved[[name]]))
  params
}

.wb_operation_pack_v3_space_content <- function(values, cells) {
  values <- .wb_operation_pack_v3_space_matrix(values)
  .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.space_slice.content.v1", list(
      schema = "scworkbench.operation_pack.space_slice.content.v1",
      dimensions = unname(as.list(as.integer(dim(values)))),
      cell_id = unname(as.list(as.character(cells))),
      values = lapply(seq_len(nrow(values)), function(i)
        unname(as.list(as.numeric(values[i, ]))))))
}

.wb_operation_pack_v3_typed_space_grant <- function(declaration, input,
    input_record, params, transition_source_state_identity, stage_root) {
  name <- as.character(declaration$name)[1]
  parameter <- as.character(declaration$selection$parameter)[1]
  cells <- as.character(unlist(params[[parameter]], use.names = FALSE))
  available <- as.character(input$cell_id %||% rownames(input$values))
  if (!length(cells) || anyNA(cells) || any(!nzchar(cells)) ||
      anyDuplicated(cells) || length(setdiff(cells, available)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Typed-space axis '", name,
        "' is empty, duplicate, stale, or outside the source space."),
      "resolution")
  axis <- .wb_operation_pack_v3_axis_manifest("cells", cells, name,
    stage_root)
  chunk_parameter <- as.character(declaration$chunk_size_parameter)[1]
  requested <- as.integer(params[[chunk_parameter]])[1]
  if (is.na(requested) || requested < 1L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-space chunk size must be positive.", "resolution")
  dimensions <- as.integer(ncol(as.matrix(input$values)))
  source <- list(
    input_name = as.character(declaration$input)[1],
    space_id = as.character(input$space_id %||% "")[1],
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    input_content_identity = input_record$content_identity,
    selected_content_identity = .wb_operation_pack_v3_space_content(
      input$values[match(cells, as.character(input$cell_id)), , drop = FALSE],
      cells),
    transition_source_state_identity = transition_source_state_identity)
  source$source_reference_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_space_source_reference.v1",
    "source reference excluding source_reference_identity", source)
  grant <- list(
    schema = "scworkbench.operation_pack.typed_space_grant.v1",
    name = name, input_name = as.character(declaration$input)[1],
    reader = "read_typed_space", kind = "space",
    role = as.character(declaration$role)[1],
    selector_parameter = parameter, source_reference = source,
    cells_axis = axis$descriptor, dimension_count = dimensions,
    requested_chunk_size = requested,
    call_discipline = "ordered_partition_exactly_once",
    max_rows = as.integer(min(requested, length(cells))),
    max_columns = dimensions, max_elements = as.double(min(requested,
      length(cells))) * as.double(dimensions))
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_space_grant.v1",
    "grant excluding grant_identity", grant)
  attr(grant, "operation_pack_v3_cells") <- cells
  grant
}

.wb_operation_pack_v3_typed_space_result <- function(grant, ordinal, value) {
  cells <- as.character(value$cell_id)
  out <- list(
    schema = "scworkbench.operation_pack.typed_space_result.v1",
    source_reference_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$source_reference$source_reference_identity),
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), ordinal = as.integer(ordinal),
    cell_count = as.integer(length(cells)),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    dimensions = unname(as.list(as.integer(dim(value$values)))),
    semantic_content_identity = .wb_operation_pack_v3_space_content(
      value$values, cells))
  out$space_result_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_space_result.v1",
    "space result excluding space_result_identity", out)
  out
}

.wb_operation_pack_v3_add_typed_space_readers <- function(adapter, request) {
  state <- adapter$state
  grants <- request$typed_space_grants %||% list()
  state$typed_space_calls <- stats::setNames(vector("list", length(grants)),
    vapply(grants, `[[`, character(1), "name"))
  sources <- attr(request, "operation_pack_v3_typed_space_values") %||% list()
  readers <- stats::setNames(lapply(grants, function(grant) {
    name <- as.character(grant$name)[1]
    force(name); force(grant)
    function(cells) {
      if (isTRUE(state$used)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH", "Capability has already been consumed.",
        "execution")
      cells <- as.character(cells)
      allowed <- as.character(sources[[name]]$cells)
      prior <- state$typed_space_calls[[name]] %||% list()
      consumed <- sum(vapply(prior, function(x) x$result$cell_count,
        integer(1)))
      expected <- if (length(cells)) allowed[seq.int(consumed + 1L,
        consumed + length(cells))] else character()
      if (!length(cells) || anyNA(cells) || anyDuplicated(cells) ||
          !identical(cells, expected) ||
          length(cells) > as.integer(grant$requested_chunk_size))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Typed-space reads must partition the authenticated axis in order.",
          "execution")
      input <- sources[[name]]$input
      index <- match(cells, as.character(input$cell_id))
      if (anyNA(index)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Typed-space source changed after authentication.", "execution")
      values <- as.matrix(input$values[index, , drop = FALSE])
      rownames(values) <- cells
      value <- structure(list(kind = "space", space_id = input$space_id,
        values = values, dimensions = as.integer(dim(values)),
        cell_id = cells, storage_profile = "space_dense_v1",
        meta = input$meta %||% list()), class = "wb_primitive")
      result <- .wb_operation_pack_v3_typed_space_result(grant,
        length(prior) + 1L, value)
      state$typed_space_calls[[name]][[length(prior) + 1L]] <- list(
        result = result, cells = cells)
      state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
        category = "typed_space", name = name,
        space_result_identity = result$space_result_identity)
      .wb_operation_pack_v2_deep_copy(value)
    }
  }), vapply(grants, `[[`, character(1), "name"))
  adapter$readers <- c(adapter$readers, readers)
  adapter
}

.wb_operation_pack_v3_typed_space_usage <- function(adapter, request) {
  lapply(request$typed_space_grants %||% list(), function(grant) {
    records <- adapter$state$typed_space_calls[[grant$name]] %||% list()
    selected <- unlist(lapply(records, `[[`, "cells"), use.names = FALSE)
    allowed <- attr(grant, "operation_pack_v3_cells") %||% character()
    if (!identical(selected, allowed)) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH",
      "Typed-space execution did not cover its ordered axis exactly once.",
      "receipt")
    calls <- lapply(records, function(record) {
      call <- record$result
      call$schema <- "scworkbench.operation_pack.observed_typed_space_call.v1"
      call$source_reference_identity <- NULL
      call$call_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_typed_space_call.v1",
        "call excluding call_identity", call)
      call
    })
    usage <- list(
      schema = "scworkbench.operation_pack.typed_space_usage.v1",
      request_identity = .wb_operation_pack_v3_unscoped_identity(
        request$request_identity),
      capability_identity = .wb_operation_pack_v3_unscoped_identity(
        request$execution_capability$capability_identity),
      operation_definition_identity = .wb_operation_pack_v3_unscoped_identity(
        request$operation_authentication$operation_definition_identity),
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity), calls = calls,
      call_count = as.integer(length(calls)),
      concatenated_cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(selected))),
      coverage_status = "exact")
    usage$usage_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.typed_space_usage.v1",
      "usage excluding usage_identity", usage)
    usage
  })
}

.wb_operation_pack_v3_sparse_grant <- function(policy, output, params,
                                                typed_space_grants) {
  query_name <- as.character(policy$query_space_read)[1]
  candidate_name <- as.character(policy$candidate_space_read)[1]
  grants <- stats::setNames(typed_space_grants,
    vapply(typed_space_grants, `[[`, character(1), "name"))
  query <- grants[[query_name]]; candidate <- grants[[candidate_name]]
  if (is.null(query) || is.null(candidate)) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    "Sparse-membership policy names an absent typed-space grant.", "staging")
  k <- as.integer(params[[as.character(policy$k_parameter)[1]]])[1]
  value <- list(
    schema = "scworkbench.operation_pack.sparse_membership_grant.v1",
    output = as.character(output$name)[1],
    representation = as.character(policy$representation)[1],
    partner_output = as.character(policy$partner_output)[1],
    query_axis_identity = query$cells_axis$order_identity,
    candidate_axis_identity = candidate$cells_axis$order_identity,
    query_count = as.integer(query$cells_axis$count),
    candidate_count = as.integer(candidate$cells_axis$count),
    maximum_per_query = k, row_order = "query_then_rank_v1",
    unique_pairs = TRUE, finite_nonnegative_values = TRUE)
  value$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sparse_membership_grant.v1",
    "grant excluding grant_identity", value)
  attr(value, "operation_pack_v3_query_cells") <- attr(query,
    "operation_pack_v3_cells")
  attr(value, "operation_pack_v3_candidate_cells") <- attr(candidate,
    "operation_pack_v3_cells")
  value
}

.wb_operation_pack_v3_pseudobulk_grant <- function(policy, output, params,
    typed_space_grants, typed_slice_grants) {
  spaces <- stats::setNames(typed_space_grants,
    vapply(typed_space_grants, `[[`, character(1), "name"))
  slices <- stats::setNames(typed_slice_grants,
    vapply(typed_slice_grants, `[[`, character(1), "name"))
  query <- spaces[[as.character(policy$query_space_read)[1]]]
  matrix <- slices[[as.character(policy$matrix_slice_read)[1]]]
  if (is.null(query) || is.null(matrix)) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    "Pseudobulk policy names an absent typed grant.", "staging")
  value <- list(
    schema = "scworkbench.operation_pack.pseudobulk_grant.v1",
    output = as.character(output$name)[1],
    membership_output = as.character(policy$membership_output)[1],
    query_axis_identity = query$cells_axis$order_identity,
    feature_axis_identity = matrix$features_axis$order_identity,
    query_cells = unname(as.list(attr(query,
      "operation_pack_v3_cells"))),
    features = unname(as.list(attr(matrix,
      "operation_pack_v3_features"))),
    aggregate = as.character(params[[as.character(
      policy$aggregate_parameter)[1]]])[1],
    zero_neighbor_policy = as.character(policy$zero_neighbor_policy)[1],
    row_order = "query_then_feature_v1")
  value$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.pseudobulk_grant.v1",
    "grant excluding grant_identity", value)
  value
}

.wb_operation_pack_v3_sparse_ledger <- function(value, grant) {
  representation <- as.character(grant$representation)[1]
  if (identical(representation, "obs_table")) {
    table <- value$table
    required <- c("query_cell_id", "neighbor_rank", "cell_id", "distance")
    if (!is.data.frame(table) || !all(required %in% names(table)))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Sparse neighbor table lacks its required edge columns.", "audit")
    query <- as.character(table$query_cell_id)
    rank <- as.integer(table$neighbor_rank)
    cell <- as.character(table$cell_id)
    distance <- as.numeric(table$distance)
  } else {
    query <- as.character(value$key %||% character())
    cell <- as.character(value$cell_id %||% character())
    distance <- as.numeric(value$value %||% numeric())
    rank <- ave(seq_along(query), query, FUN = seq_along)
    rank <- as.integer(rank)
  }
  queries <- attr(grant, "operation_pack_v3_query_cells")
  candidates <- attr(grant, "operation_pack_v3_candidate_cells")
  if (length(query) != length(cell) || length(query) != length(distance) ||
      length(query) != length(rank) || anyNA(query) || anyNA(cell) ||
      anyNA(rank) || any(!is.finite(distance)) || any(distance < 0) ||
      length(setdiff(query, queries)) || length(setdiff(cell, candidates)) ||
      anyDuplicated(paste(query, cell, sep = "\034")))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Sparse membership has invalid, duplicate, or unauthorized edges.",
      "audit")
  expected_query <- rep(queries, times = tabulate(match(query, queries),
    nbins = length(queries)))
  if (!identical(query, expected_query)) .wb_operation_pack_v3_error(
    "PYBENCH_OUTPUT_INVALID",
    "Sparse membership rows are not grouped in authenticated query order.",
    "audit")
  for (q in queries) {
    index <- which(query == q)
    if (length(index) > min(as.integer(grant$maximum_per_query),
        length(candidates)) ||
        (length(index) && !identical(rank[index], seq_along(index))))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Sparse membership exceeds its bound or has invalid ranks.", "audit")
  }
  ledger <- unname(Map(function(q, r, c, d) list(query_cell_id = q,
    neighbor_rank = as.integer(r), cell_id = c, distance = unname(d)),
    query, rank, cell, distance))
  out <- list(schema = "scworkbench.operation_pack.sparse_membership_observation.v1",
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), edge_count = as.integer(length(ledger)),
    edge_ledger = ledger,
    edge_ledger_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.sparse_edge_ledger.v1", ledger),
    status = "validated")
  out$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sparse_membership_observation.v1",
    "observation excluding observation_identity", out)
  out
}

.wb_operation_pack_v3_pseudobulk_observe <- function(value, grant,
                                                       sparse_observation) {
  table <- value$table
  required <- c("feature_id", "query_cell_id", "n_neighbors", "aggregate",
    "value")
  if (!is.data.frame(table) || !all(required %in% names(table)))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Pseudobulk table lacks its required columns.", "audit")
  query <- as.character(unlist(grant$query_cells, use.names = FALSE))
  features <- as.character(unlist(grant$features, use.names = FALSE))
  expected_query <- rep(query, each = length(features))
  expected_features <- rep(features, times = length(query))
  ledger <- sparse_observation$edge_ledger
  counts <- tabulate(match(vapply(ledger, `[[`, character(1),
    "query_cell_id"), query), nbins = length(query))
  zero_neighbor_policy <- as.character(grant$zero_neighbor_policy)[1]
  if (!identical(zero_neighbor_policy, "zero_rows_forbidden_v1"))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Pseudobulk grant has an unknown zero-neighbor policy.", "audit")
  if (any(counts == 0L))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      paste0("Pseudobulk membership leaves authenticated queries without ",
        "neighbors under zero_rows_forbidden_v1."), "audit")
  if (!identical(as.character(table$query_cell_id), expected_query) ||
      !identical(as.character(table$feature_id), expected_features) ||
      !identical(as.integer(table$n_neighbors), rep(as.integer(counts),
        each = length(features))) ||
      any(as.character(table$aggregate) != as.character(grant$aggregate)) ||
      any(!is.finite(as.numeric(table$value))))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Pseudobulk rows differ from the authenticated membership and axes.",
      "audit")
  out <- list(schema = "scworkbench.operation_pack.pseudobulk_observation.v1",
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity),
    edge_ledger_identity = sparse_observation$edge_ledger_identity,
    row_count = as.integer(nrow(table)), aggregate = grant$aggregate,
    status = "validated")
  out$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.pseudobulk_observation.v1",
    "observation excluding observation_identity", out)
  out
}
