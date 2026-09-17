# Generic authenticated read-only registry snapshots for operation-pack ABI v2.

.wb_operation_pack_v2_registry_read_error <- function(code, message, phase = "resolution", ...) {
  .wb_operation_pack_v2_error(code, message, phase, ...)
}

.wb_operation_pack_v2_registry_selector <- function(params, declaration) {
  read_value <- function(field) {
    parameter <- as.character(declaration[[field]] %||% "")[1]
    if (!nzchar(parameter)) return(character())
    value <- as.character(unlist(params[[parameter]] %||% character(), use.names = FALSE))
    value <- value[!is.na(value) & nzchar(value)]
    if (anyDuplicated(value)) .wb_operation_pack_v2_registry_read_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Feature-set registry selector '", parameter, "' contains duplicates."))
    sort(value, method = "radix")
  }
  namespaces <- sort(unique(c(read_value("namespace_parameter"),
    read_value("namespaces_parameter"))), method = "radix")
  feature_sets <- read_value("feature_sets_parameter")
  list(
    namespaces = unname(as.list(namespaces)),
    feature_sets = unname(as.list(feature_sets)),
    no_selector_policy = as.character(declaration$no_selector_policy)[1],
    empty_match_policy = as.character(declaration$empty_match_policy)[1]
  )
}

.wb_operation_pack_v2_registry_scalar <- function(value, integer = FALSE) {
  if (!length(value) || is.na(value[[1]])) return(NULL)
  if (isTRUE(integer)) return(as.integer(value[[1]]))
  as.character(value[[1]])
}

.wb_operation_pack_v2_feature_set_registry_snapshot_validate <- function(snapshot) {
  exact_names <- function(value, expected, label) {
    if (!is.list(value) || is.null(names(value)) || !setequal(names(value), expected) ||
        anyDuplicated(names(value))) .wb_operation_pack_v2_registry_read_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Malformed feature-set registry ", label, "."))
  }
  exact_names(snapshot, c("schema", "matrix_id", "feature_universe", "selection", "sets"), "snapshot")
  if (!identical(as.character(snapshot$schema)[1],
      "scworkbench.feature_set_registry.snapshot.v1")) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry snapshot schema is invalid.")
  }
  matrix_id <- as.character(snapshot$matrix_id)[1]
  universe <- as.character(unlist(snapshot$feature_universe, use.names = FALSE))
  if (!nzchar(matrix_id) || anyNA(universe) || any(!nzchar(universe)) || anyDuplicated(universe)) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry matrix binding or feature universe is invalid.")
  }
  exact_names(snapshot$selection,
    c("namespaces", "feature_sets", "no_selector_policy", "empty_match_policy"),
    "selection")
  namespaces <- as.character(unlist(snapshot$selection$namespaces, use.names = FALSE))
  selected_sets <- as.character(unlist(snapshot$selection$feature_sets, use.names = FALSE))
  if (anyNA(c(namespaces, selected_sets)) || any(!nzchar(c(namespaces, selected_sets))) ||
      anyDuplicated(namespaces) || anyDuplicated(selected_sets) ||
      !identical(namespaces, sort(namespaces, method = "radix")) ||
      !identical(selected_sets, sort(selected_sets, method = "radix")) ||
      !identical(as.character(snapshot$selection$no_selector_policy)[1], "all_namespaces") ||
      !as.character(snapshot$selection$empty_match_policy)[1] %in% c("allow", "error")) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry selector normalization is invalid.")
  }
  sets <- snapshot$sets %||% list()
  if (!is.list(sets) || !is.null(names(sets))) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry sets must be an array.")
  }
  set_fields <- c("feature_set", "matrix_id", "n_features", "set_id", "namespace",
    "organism", "source_id", "source_version", "origin", "recipe_json",
    "is_readonly", "created_at", "updated_at", "created_by", "description",
    "memberships")
  keys <- character(length(sets))
  set_names <- character(length(sets))
  for (i in seq_along(sets)) {
    item <- sets[[i]]
    exact_names(item, set_fields, paste0("set at index ", i))
    feature_set <- as.character(item$feature_set)[1]
    set_names[[i]] <- feature_set
    item_matrix <- as.character(item$matrix_id)[1]
    namespace <- as.character(item$namespace %||% "")[1]
    scalar_string <- function(value, nullable = TRUE) {
      (is.null(value) && isTRUE(nullable)) ||
        (is.character(value) && length(value) == 1L && !is.na(value))
    }
    scalar_integer <- function(value) {
      is.numeric(value) && length(value) == 1L && !is.na(value) &&
        is.finite(value) && identical(as.numeric(value), as.numeric(as.integer(value)))
    }
    if (!is.character(item$feature_set) || length(item$feature_set) != 1L ||
        !is.character(item$matrix_id) || length(item$matrix_id) != 1L ||
        !nzchar(feature_set) || !identical(item_matrix, matrix_id) ||
        !scalar_integer(item$n_features) ||
        !scalar_integer(item$is_readonly) ||
        !as.integer(item$is_readonly) %in% c(0L, 1L) ||
        !all(vapply(item[c("set_id", "namespace", "organism", "source_id",
          "source_version", "origin", "recipe_json", "created_at",
          "updated_at", "created_by", "description")], scalar_string,
          logical(1)))) {
      .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Feature-set registry set metadata or matrix binding is invalid.")
    }
    keys[[i]] <- paste(namespace, feature_set, sep = "\r")
    memberships <- item$memberships %||% list()
    if (!is.list(memberships) || !is.null(names(memberships))) {
      .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Feature-set registry membership is invalid for '", feature_set, "'."))
    }
    ids <- character(length(memberships)); ranks <- integer(length(memberships))
    for (j in seq_along(memberships)) {
      member <- memberships[[j]]
      exact_names(member, c("feature_id", "rank"), "membership")
      if (!is.character(member$feature_id) || length(member$feature_id) != 1L ||
          !is.numeric(member$rank) || length(member$rank) != 1L ||
          is.na(member$rank) || !is.finite(member$rank) ||
          !identical(as.numeric(member$rank), as.numeric(as.integer(member$rank)))) {
        .wb_operation_pack_v2_registry_read_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          paste0("Feature-set registry membership is invalid for '",
            feature_set, "'."))
      }
      ids[[j]] <- as.character(member$feature_id)[1]
      ranks[[j]] <- as.integer(member$rank)[1]
    }
    if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids) ||
        length(setdiff(ids, universe)) || !identical(ranks, seq_along(ranks)) ||
        !identical(as.integer(item$n_features)[1], length(ids))) {
      .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Feature-set registry membership is invalid for '", feature_set, "'."))
    }
  }
  if (anyDuplicated(set_names) || anyDuplicated(keys) ||
      !identical(keys, sort(keys, method = "radix"))) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry rows are duplicated or noncanonical.")
  }
  if (!length(sets) && identical(snapshot$selection$empty_match_policy, "error")) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "No feature sets match the authenticated registry selectors.")
  }
  snapshot
}

.wb_operation_pack_v2_feature_set_registry_snapshot <- function(bundle, declaration,
                                                                  inputs, params) {
  matrix_input <- as.character(declaration$matrix_input)[1]
  matrix_value <- inputs[[matrix_input]]
  matrix_id <- as.character(matrix_value$matrix_id %||% "")[1]
  if (!nzchar(matrix_id)) .wb_operation_pack_v2_registry_read_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Feature-set registry read requires a resolved matrix identifier.")
  universe <- tryCatch(as.character(wb_feature_ids(bundle, matrix_id)),
    error = function(error) .wb_operation_pack_v2_registry_read_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Feature-set registry matrix binding is invalid: ",
        conditionMessage(error))))
  if (!length(universe) || anyNA(universe) || any(!nzchar(universe)) || anyDuplicated(universe)) {
    .wb_operation_pack_v2_registry_read_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Feature-set registry read requires one canonical ordered feature universe.")
  }
  selection <- .wb_operation_pack_v2_registry_selector(params, declaration)
  namespaces <- as.character(unlist(selection$namespaces, use.names = FALSE))
  selected_sets <- as.character(unlist(selection$feature_sets, use.names = FALSE))
  info <- wb_feature_sets(bundle, matrix_id = matrix_id)
  if (length(namespaces)) info <- info[as.character(info$namespace) %in% namespaces, , drop = FALSE]
  if (length(selected_sets)) info <- info[as.character(info$feature_set) %in% selected_sets, , drop = FALSE]
  if (nrow(info)) {
    namespace_order <- as.character(info$namespace)
    namespace_order[is.na(namespace_order)] <- ""
    info <- info[order(namespace_order,
      as.character(info$feature_set), method = "radix"), , drop = FALSE]
  }
  set_rows <- vector("list", nrow(info))
  for (i in seq_len(nrow(info))) {
    feature_set <- as.character(info$feature_set[[i]])
    memberships <- DBI::dbGetQuery(bundle$con, paste(
      "SELECT feature_id, rank FROM feature_set_membership",
      "WHERE matrix_id = ? AND feature_set = ? ORDER BY rank ASC;"),
      params = list(matrix_id, feature_set))
    memberships$feature_id <- as.character(memberships$feature_id)
    memberships$rank <- as.integer(memberships$rank)
    member_rows <- lapply(seq_len(nrow(memberships)), function(j) list(
      feature_id = memberships$feature_id[[j]], rank = memberships$rank[[j]]))
    row <- info[i, , drop = FALSE]
    set_rows[[i]] <- list(
      feature_set = feature_set,
      matrix_id = matrix_id,
      n_features = as.integer(row$n_features[[1]]),
      set_id = .wb_operation_pack_v2_registry_scalar(row$set_id),
      namespace = .wb_operation_pack_v2_registry_scalar(row$namespace),
      organism = .wb_operation_pack_v2_registry_scalar(row$organism),
      source_id = .wb_operation_pack_v2_registry_scalar(row$source_id),
      source_version = .wb_operation_pack_v2_registry_scalar(row$source_version),
      origin = .wb_operation_pack_v2_registry_scalar(row$origin),
      recipe_json = .wb_operation_pack_v2_registry_scalar(row$recipe_json),
      is_readonly = .wb_operation_pack_v2_registry_scalar(row$is_readonly, integer = TRUE),
      created_at = .wb_operation_pack_v2_registry_scalar(row$created_at),
      updated_at = .wb_operation_pack_v2_registry_scalar(row$updated_at),
      created_by = .wb_operation_pack_v2_registry_scalar(row$created_by),
      description = .wb_operation_pack_v2_registry_scalar(row$description),
      memberships = unname(member_rows)
    )
  }
  snapshot <- list(
    schema = "scworkbench.feature_set_registry.snapshot.v1",
    matrix_id = matrix_id,
    feature_universe = unname(as.list(universe)),
    selection = selection,
    sets = unname(set_rows)
  )
  .wb_operation_pack_v2_feature_set_registry_snapshot_validate(snapshot)
}

.wb_operation_pack_v2_registry_read_records <- function(bundle, operation, inputs,
                                                          params, input_records,
                                                          stage_root) {
  declarations <- operation$registry_reads %||% list()
  if (!length(declarations)) return(list(records = list(), values = list()))
  input_map <- stats::setNames(input_records,
    vapply(input_records, `[[`, character(1), "name"))
  records <- vector("list", length(declarations)); values <- vector("list", length(declarations))
  names(values) <- vapply(declarations, `[[`, character(1), "name")
  for (i in seq_along(declarations)) {
    declaration <- declarations[[i]]
    name <- as.character(declaration$name)[1]
    snapshot <- .wb_operation_pack_v2_feature_set_registry_snapshot(
      bundle, declaration, inputs, params)
    value_dir <- file.path(stage_root, "registry_reads", name)
    dir.create(value_dir, recursive = TRUE, showWarnings = FALSE)
    payload <- file.path(value_dir, "payload.json")
    .wb_operation_pack_v2_atomic_json(snapshot, payload)
    matrix_record <- input_map[[as.character(declaration$matrix_input)[1]]]
    selection_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.feature_set_registry.selection.v1",
      "normalized selector binding", snapshot$selection)
    content_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.feature_set_registry.snapshot.v1",
      "canonical matrix-bound registry snapshot", snapshot)
    source_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.feature_set_registry.source.v1",
      "ordered registry source state", list(matrix_id = snapshot$matrix_id,
        feature_universe = snapshot$feature_universe, sets = snapshot$sets))
    ancestry_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.provenance.ancestry.v1",
      "registry snapshot ancestry", list(
        matrix_input = declaration$matrix_input,
        matrix_content_identity = matrix_record$descriptor$content_identity,
        selection_identity = selection_identity))
    payload_manifest <- list(path = paste0("registry_reads/", name, "/payload.json"),
      size = as.numeric(file.info(payload)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(payload))
    descriptor <- list(
      category = "authenticated_core_registry_snapshot",
      kind = "feature_set_registry",
      reader = "read_feature_set_registry",
      matrix_input = as.character(declaration$matrix_input)[1],
      selector_binding = list(
        namespace_parameter = declaration$namespace_parameter %||% NULL,
        namespaces_parameter = declaration$namespaces_parameter %||% NULL,
        feature_sets_parameter = declaration$feature_sets_parameter %||% NULL,
        no_selector_policy = declaration$no_selector_policy,
        empty_match_policy = declaration$empty_match_policy
      ),
      matrix_id = snapshot$matrix_id,
      dimensions = unname(as.list(as.integer(c(length(snapshot$sets),
        sum(vapply(snapshot$sets, function(x) length(x$memberships), integer(1))))))),
      matrix_content_identity = matrix_record$descriptor$content_identity,
      feature_order_identity = matrix_record$descriptor$feature_order_identity,
      selection_identity = selection_identity,
      content_identity = content_identity,
      source_identity = source_identity,
      ancestry_identity = ancestry_identity,
      payload_manifest_identity = .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.payload_manifest.v2",
        "registry read payload manifest", payload_manifest)
    )
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.registry_read_descriptor.v2",
      "descriptor excluding descriptor_identity", descriptor)
    records[[i]] <- list(name = name, descriptor = descriptor)
    values[[name]] <- snapshot
  }
  order_index <- order(vapply(records, `[[`, character(1), "name"), method = "radix")
  list(records = records[order_index], values = values[vapply(records[order_index], `[[`, character(1), "name")])
}

.wb_operation_pack_v2_registry_reads_assert_current <- function(bundle, operation,
                                                                 inputs, params,
                                                                 records) {
  declarations <- operation$registry_reads %||% list()
  if (!length(declarations)) return(invisible(TRUE))
  record_map <- stats::setNames(records, vapply(records, `[[`, character(1), "name"))
  for (declaration in declarations) {
    name <- as.character(declaration$name)[1]
    snapshot <- .wb_operation_pack_v2_feature_set_registry_snapshot(
      bundle, declaration, inputs, params)
    observed_content <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.feature_set_registry.snapshot.v1",
      "canonical matrix-bound registry snapshot", snapshot)
    observed_source <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.feature_set_registry.source.v1",
      "ordered registry source state", list(matrix_id = snapshot$matrix_id,
        feature_universe = snapshot$feature_universe, sets = snapshot$sets))
    expected <- record_map[[name]]$descriptor
    if (!identical(observed_content, expected$content_identity) ||
        !identical(observed_source, expected$source_identity)) {
      .wb_operation_pack_v2_registry_read_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Feature-set registry source changed after preflight for '", name, "'."),
        phase = "dispatch", registry_read = name)
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_registry_read_observations <- function(request, reader_calls) {
  records <- request$registry_reads %||% list()
  if (!length(records)) return(list())
  out <- vector("list", length(records))
  for (i in seq_along(records)) {
    record <- records[[i]]; name <- as.character(record$name)[1]
    calls <- Filter(function(x) identical(x$category %||% "input", "registry_read") &&
      identical(as.character(x$name)[1], name), reader_calls)
    if (length(calls) != 1L) .wb_operation_pack_v2_registry_read_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      paste0("Registry reader '", name, "' must be consumed exactly once; observed ",
        length(calls), "."), phase = "execution", registry_read = name)
    descriptor <- record$descriptor
    observed <- list(
      category = descriptor$category,
      kind = descriptor$kind,
      reader = descriptor$reader,
      descriptor_identity = descriptor$descriptor_identity,
      content_identity = descriptor$content_identity,
      source_identity = descriptor$source_identity,
      ancestry_identity = descriptor$ancestry_identity,
      payload_manifest_identity = descriptor$payload_manifest_identity,
      use_count = 1L
    )
    observed$observed_descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_registry_read.v2",
      "descriptor excluding observed_descriptor_identity", observed)
    out[[i]] <- list(name = name, descriptor = observed)
  }
  out
}

#' Inspect Durable ABI v2 Registry Reads
#'
#' Read authenticated core-registry snapshots from a finalized transition.
#' This getter uses only the core-owned transition record; the originating
#' operation pack does not need to be installed or active.
#'
#' @param bundle Open scworkbench bundle, including a read-only recipient.
#' @param transition_id Durable ABI v2 transition identifier.
#' @return Named list of registry-read records. Each record contains the
#'   validated typed `snapshot`, request `descriptor`, and observed receipt
#'   `observation`.
#' @export
wb_operation_pack_transition_registry_reads <- function(bundle, transition_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
    "bundle must be scworkbench_bundle")
  transition_id <- .wb_operation_pack_v2_safe_component(
    transition_id, "transition_id")
  path <- file.path(.wb_operation_pack_v2_store(bundle), transition_id)
  result <- .wb_operation_pack_v2_record_validate(path, load_payloads = TRUE)
  .wb_operation_pack_assert(
    isTRUE(result$ok) && identical(result$state$state, "reopened"),
    "PYBENCH_REOPEN_VALIDATION_FAILED",
    paste0("Transition is absent or invalid: ", result$code %||% "not_reopened"),
    class = "wb_operation_pack_v2_error")
  requests <- result$request$registry_reads %||% list()
  observations <- result$receipt$registry_reads %||% list()
  if (!length(requests)) return(list())
  out <- vector("list", length(requests))
  names(out) <- vapply(requests, `[[`, character(1), "name")
  for (i in seq_along(requests)) {
    name <- names(out)[[i]]
    payload <- file.path(path, "registry_reads", name, "payload.json")
    snapshot <- .wb_operation_pack_parse_canonical_json(readChar(
      payload, nchars = file.info(payload)$size, useBytes = TRUE))
    snapshot <- .wb_operation_pack_v2_feature_set_registry_snapshot_validate(
      snapshot)
    out[[i]] <- list(
      snapshot = structure(snapshot,
        class = c("wb_operation_pack_feature_set_registry", "list")),
      descriptor = requests[[i]]$descriptor,
      observation = observations[[i]]$descriptor
    )
  }
  out
}
