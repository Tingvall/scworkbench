# Core-owned lifecycle for ABI v2 registry requests.

.wb_operation_pack_registry_fault <- function(event, ...) {
  hook <- getOption("scworkbench.operation_pack_registry_test_hook", NULL)
  if (is.function(hook)) hook(event = event, ...)
  invisible(TRUE)
}

.wb_operation_pack_cell_set_name <- function(value) {
  .wb_operation_pack_assert(
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(value),
    "PYBENCH_OUTPUT_INVALID",
    "Requested cell-set name must be one non-empty string.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  value <- as.character(value)[1]
  if (!startsWith(value, "set:")) value <- paste0("set:", value)
  .wb_operation_pack_assert(
    !is.na(value) && grepl("^set:[A-Za-z0-9][A-Za-z0-9_.-]*$", value),
    "PYBENCH_OUTPUT_INVALID",
    paste0("Invalid requested cell-set name: '", value, "'."),
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  value
}

.wb_operation_pack_nullable_scalar <- function(value, label) {
  if (is.null(value)) return(NULL)
  .wb_operation_pack_assert(
    is.character(value) && length(value) == 1L && !is.na(value),
    "PYBENCH_OUTPUT_INVALID",
    paste0("Cell-set-family source ", label, " must be one string or null."),
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  as.character(value)[1]
}

.wb_operation_pack_cell_set_source <- function(source) {
  required <- c("label", "created_by", "input_artifact_id", "input_run_id",
    "input_snapshot_id")
  .wb_operation_pack_assert(
    is.list(source) && !is.null(names(source)) &&
      setequal(names(source), required) && !anyDuplicated(names(source)),
    "PYBENCH_OUTPUT_INVALID",
    paste0("Cell-set-family source must contain exactly: ",
      paste(required, collapse = ", "), "."),
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  label <- .wb_operation_pack_nullable_scalar(source$label, "label")
  .wb_operation_pack_assert(
    !is.null(label) && nzchar(label), "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family source label must be non-empty.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  out <- list(
    label = label,
    created_by = .wb_operation_pack_nullable_scalar(source$created_by,
      "created_by"),
    input_artifact_id = .wb_operation_pack_nullable_scalar(
      source$input_artifact_id, "input_artifact_id"),
    input_run_id = .wb_operation_pack_nullable_scalar(source$input_run_id,
      "input_run_id"),
    input_snapshot_id = .wb_operation_pack_nullable_scalar(
      source$input_snapshot_id, "input_snapshot_id")
  )
  run_present <- !is.null(out$input_run_id) && nzchar(out$input_run_id)
  snapshot_present <- !is.null(out$input_snapshot_id) &&
    nzchar(out$input_snapshot_id)
  .wb_operation_pack_assert(
    identical(run_present, snapshot_present), "PYBENCH_OUTPUT_INVALID",
    paste0("Cell-set-family source provenance is ambiguous: input_run_id and ",
      "input_snapshot_id must be supplied together."),
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  out
}

.wb_operation_pack_cell_set_family_normalize <- function(bundle, value) {
  .wb_operation_pack_assert(
    inherits(bundle, "scworkbench_bundle"), "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family admission requires a core bundle authority.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  .wb_operation_pack_assert(
    is.list(value) && is.character(value$kind) &&
      length(value$kind) == 1L &&
      identical(value$kind, "cell_set_family_admission") &&
      !is.null(names(value)) &&
      setequal(names(value), c("kind", "sets", "mode", "source")) &&
      !anyDuplicated(names(value)),
    "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family admission payload has an invalid outer shape.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  mode <- value$mode
  .wb_operation_pack_assert(
    is.character(mode) && length(mode) == 1L && !is.na(mode) &&
      mode %in% c("add", "replace"),
    "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family mode must be exactly 'add' or 'replace'.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  sets <- value$sets
  .wb_operation_pack_assert(
    is.list(sets) && (is.null(names(sets)) || !length(sets)),
    "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family sets must be a JSON array.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  universe <- as.character(wb_cells(bundle, cell_set = "all"))
  normalized <- lapply(sets, function(item) {
    required <- c("name", "cells", "description", "selection_rule")
    .wb_operation_pack_assert(
      is.list(item) && !is.null(names(item)) &&
        setequal(names(item), required) && !anyDuplicated(names(item)),
      "PYBENCH_OUTPUT_INVALID",
      paste0("Each cell-set-family member must contain exactly: ",
        paste(required, collapse = ", "), "."),
      phase = "audit", class = "wb_operation_pack_v2_error"
    )
    cells_valid <- is.character(item$cells) ||
      (is.list(item$cells) && all(vapply(item$cells, function(x) {
        is.character(x) && length(x) == 1L && !is.na(x)
      }, logical(1))))
    .wb_operation_pack_assert(
      cells_valid, "PYBENCH_OUTPUT_INVALID",
      "Each admitted cell-set membership must be a string array.",
      phase = "audit", class = "wb_operation_pack_v2_error"
    )
    cells <- if (is.character(item$cells)) {
      as.character(item$cells)
    } else {
      as.character(unlist(item$cells %||% character(), use.names = FALSE))
    }
    .wb_operation_pack_assert(
      length(cells) > 0L && !anyNA(cells) && all(nzchar(cells)) &&
        !anyDuplicated(cells),
      "PYBENCH_OUTPUT_INVALID",
      "Each admitted cell set requires unique, non-empty members.",
      phase = "audit", class = "wb_operation_pack_v2_error"
    )
    foreign <- setdiff(cells, universe)
    .wb_operation_pack_assert(
      !length(foreign), "PYBENCH_OUTPUT_INVALID",
      paste0("Cell-set-family contains cells outside the bundle universe: ",
        paste(utils::head(foreign, 10L), collapse = ", "), "."),
      phase = "audit", class = "wb_operation_pack_v2_error"
    )
    description <- item$description
    selection_rule <- item$selection_rule
    .wb_operation_pack_assert(
      is.character(description) && length(description) == 1L &&
        !is.na(description) &&
        is.character(selection_rule) && length(selection_rule) == 1L &&
        !is.na(selection_rule) && nzchar(selection_rule),
      "PYBENCH_OUTPUT_INVALID",
      "Cell-set-family description must be a string and selection_rule must be non-empty.",
      phase = "audit", class = "wb_operation_pack_v2_error"
    )
    list(
      name = .wb_operation_pack_cell_set_name(item$name),
      cells = universe[universe %in% cells],
      description = description,
      selection_rule = selection_rule
    )
  })
  set_names <- vapply(normalized, `[[`, character(1), "name")
  .wb_operation_pack_assert(
    !anyDuplicated(set_names), "PYBENCH_OUTPUT_INVALID",
    "Cell-set-family request repeats a normalized set name.",
    phase = "audit", class = "wb_operation_pack_v2_error"
  )
  if (length(normalized)) {
    normalized <- normalized[order(set_names, method = "radix")]
  }
  out <- list(
    kind = "cell_set_family_admission",
    sets = unname(normalized),
    mode = mode,
    source = .wb_operation_pack_cell_set_source(value$source)
  )
  attr(out, "family_identity") <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.cell_set.family_admission.v1",
    "normalized family payload", out
  )
  attr(out, "member_identities") <- lapply(out$sets, function(item) list(
    name = item$name,
    membership_identity = .wb_operation_pack_v2_identity_scoped(
      "scworkbench.cell_set.membership.v1", "ordered exact membership",
      item$cells
    )
  ))
  attr(out, "source_identity") <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.cell_set.family_source.v1", "normalized source metadata",
    out$source
  )
  out
}

.wb_operation_pack_single_admission_family <- function(bundle, value) {
  cells <- as.character(value$cells %||% character())
  .wb_operation_pack_cell_set_family_normalize(bundle, list(
    kind = "cell_set_family_admission",
    sets = list(list(
      name = .wb_operation_pack_cell_set_name(value$name), cells = cells,
      description = "ABI v2 single-set admission",
      selection_rule = "cell_id in authenticated admission membership"
    )),
    mode = "add",
    source = list(
      label = "operation_pack_v2_cell_set_admission",
      created_by = NULL, input_artifact_id = NULL,
      input_run_id = NULL, input_snapshot_id = NULL
    )
  ))
}

.wb_operation_pack_v2_registry_request_value <- function(result, item) {
  name <- as.character(item$name)[1]
  python <- identical(as.character(
    result$receipt$runtime_attestation$backend %||% "R")[1], "Python")
  root <- if (python) "registry_requests" else "outputs"
  path <- file.path(result$path, root, name,
    if (python) "payload.json" else "payload.rds")
  .wb_operation_pack_assert(file.exists(path), "PYBENCH_REOPEN_VALIDATION_FAILED",
    paste0("Registry-request payload is absent: ", name),
    phase = "reopen", class = "wb_operation_pack_v2_error")
  if (python) jsonlite::read_json(path, simplifyVector = FALSE) else readRDS(path)
}

.wb_operation_pack_v2_stage_registry_requests <- function(bundle, result) {
  records <- result$receipt$registry_requests %||% list()
  if (!length(records)) return(list())
  prepared <- lapply(records, function(item) {
    value <- .wb_operation_pack_v2_registry_request_value(result, item)
    kind <- as.character(item$descriptor$kind)[1]
    family <- if (identical(kind, "cell_set_admission")) {
      .wb_operation_pack_single_admission_family(bundle, value)
    } else if (identical(kind, "cell_set_family_admission")) {
      .wb_operation_pack_cell_set_family_normalize(bundle, value)
    } else {
      .wb_operation_pack_v2_error("PYBENCH_OUTPUT_INVALID",
        paste0("Unsupported registry-request kind: ", kind), "audit")
    }
    family_identity <- attr(family, "family_identity")
    if (identical(kind, "cell_set_family_admission")) {
      expected_dimensions <- as.integer(c(
        length(family$sets),
        sum(vapply(family$sets, function(set) length(set$cells), integer(1)))
      ))
      .wb_operation_pack_assert(
        identical(family_identity$sha256,
          as.character(item$descriptor$family_identity$sha256 %||% "")[1]) &&
        identical(as.integer(unlist(item$descriptor$dimensions,
          use.names = FALSE)), expected_dimensions) &&
        identical(.wb_operation_pack_canonical_json(
          item$descriptor$member_identities),
          .wb_operation_pack_canonical_json(
            attr(family, "member_identities"))) &&
        identical(.wb_operation_pack_canonical_json(
          item$descriptor$source_identity),
          .wb_operation_pack_canonical_json(
            attr(family, "source_identity"))),
        "PYBENCH_RECEIPT_MISMATCH",
        paste0("Cell-set-family descriptor differs from its normalized payload: ",
          item$name), phase = "receipt",
        class = "wb_operation_pack_v2_error"
      )
    }
    list(
      transition_id = as.character(result$transition_id)[1],
      output_name = as.character(item$name)[1],
      request_kind = kind,
      request_identity = result$request$request_identity,
      receipt_identity = result$receipt$receipt_identity,
      observed_descriptor_identity = item$descriptor$observed_descriptor_identity,
      family_identity = family_identity,
      family = family
    )
  })
  names(prepared) <- vapply(prepared, `[[`, character(1), "output_name")
  .wb_operation_pack_assert(!anyDuplicated(names(prepared)),
    "PYBENCH_RECEIPT_MISMATCH", "Registry-request names are duplicated.",
    phase = "receipt", class = "wb_operation_pack_v2_error")

  DBI::dbWithTransaction(bundle$con, {
    for (item in prepared) {
      .wb_journal_registry_mutation(
        bundle, "operation_pack_cell_set_family", "admit",
        key = list(
          transition_id = item$transition_id,
          output_name = item$output_name
        ),
        payload = item
      )
    }
  })
  prepared
}

.wb_operation_pack_registry_event_payload <- function(row) {
  value <- jsonlite::fromJSON(as.character(row$payload_json[[1]]),
    simplifyVector = FALSE)
  .wb_operation_pack_assert(is.list(value) && is.list(value$family),
    "PYBENCH_RECEIPT_MISMATCH", "Registry admission event is malformed.",
    phase = "promotion", class = "wb_operation_pack_v2_error")
  value
}

.wb_operation_pack_registry_preflight <- function(bundle, events) {
  selected <- events[as.character(events$registry_type) ==
    "operation_pack_cell_set_family", , drop = FALSE]
  if (!nrow(selected)) return(invisible(list()))
  seen <- character()
  out <- vector("list", nrow(selected))
  for (i in seq_len(nrow(selected))) {
    payload <- .wb_operation_pack_registry_event_payload(selected[i, , drop = FALSE])
    family <- .wb_operation_pack_cell_set_family_normalize(bundle,
      payload$family)
    identity <- attr(family, "family_identity")
    .wb_operation_pack_assert(
      identical(identity$sha256,
        as.character(payload$family_identity$sha256 %||% "")[1]),
      "PYBENCH_RECEIPT_MISMATCH",
      "Staged cell-set-family identity is invalid.", phase = "promotion",
      class = "wb_operation_pack_v2_error"
    )
    names_now <- vapply(family$sets, `[[`, character(1), "name")
    conflict <- intersect(seen, names_now)
    .wb_operation_pack_assert(
      !length(conflict), "PYBENCH_OUTPUT_INVALID",
      paste0("Promotion closure contains multiple admissions for cell set: ",
        paste(conflict, collapse = ", "), "."),
      phase = "promotion", class = "wb_operation_pack_v2_error"
    )
    seen <- c(seen, names_now)
    for (set in family$sets) {
      current <- wb_cells(bundle, cell_set = set$name)
      next_members <- if (identical(family$mode, "add")) {
        universe <- wb_cells(bundle, cell_set = "all")
        universe[universe %in% unique(c(current, set$cells))]
      } else set$cells
      if (length(current) && .wb_entity_is_provenance_bound(
          bundle, "cell_set", set$name)) {
        .wb_operation_pack_assert(
          identical(as.character(current), as.character(next_members)),
          "PYBENCH_OUTPUT_INVALID",
          paste0("Admission would change provenance-bound cell set '",
            set$name, "'."), phase = "promotion",
          class = "wb_operation_pack_v2_error"
        )
      }
    }
    out[[i]] <- list(row = selected[i, , drop = FALSE], payload = payload,
      family = family)
  }
  invisible(out)
}

.wb_operation_pack_registry_apply_event <- function(bundle, row, payload) {
  family <- .wb_operation_pack_cell_set_family_normalize(bundle,
    payload$family)
  source <- family$source
  for (i in seq_along(family$sets)) {
    set <- family$sets[[i]]
    if (identical(family$mode, "replace")) {
      wb_cell_set_replace(
        bundle, cell_set = set$name, cell_ids = set$cells,
        source = source$label,
        created_by = source$created_by %||% NA_character_,
        description = set$description, strict = TRUE
      )
    } else {
      wb_cell_set_add(
        bundle, cell_set = set$name, cell_ids = set$cells,
        source = source$label,
        created_by = source$created_by %||% NA_character_,
        description = set$description
      )
    }
    content_hash <- .wb_registry_entity_content_hash(bundle, "cell_set",
      set$name)
    .wb_entity_bind_provenance(
      bundle$con, "cell_set", set$name, content_hash,
      unname(.wb_content_identity_schemes()[["registry"]])
    )
    .wb_operation_pack_registry_fault(
      "between_family_member_writes",
      event_id = as.character(row$event_id[[1]]), member_index = i,
      member_count = length(family$sets), cell_set = set$name
    )
  }
  attr(family, "family_identity")$sha256
}

.wb_operation_pack_v2_prepare_transition_payloads <- function(
    staging_bundle, bundle, workspace, runs, topo) {
  if (is.null(staging_bundle)) return(invisible(workspace))
  for (rid in topo) {
    if (.wb_run_is_committed(bundle, rid)) next
    transition <- runs[[rid]]$operation_pack_transition %||% NULL
    if (is.null(transition)) next
    transition_id <- .wb_operation_pack_v2_safe_component(
      transition$transition_id, "transition_id")
    source <- file.path(.wb_operation_pack_v2_store(staging_bundle),
      transition_id)
    record <- .wb_operation_pack_v2_record_validate(source,
      load_payloads = TRUE)
    .wb_operation_pack_assert(
      isTRUE(record$ok) && identical(record$state$state, "reopened") &&
        identical(as.character(record$receipt$run_id)[1],
          as.character(rid)[1]) &&
        identical(as.character(record$receipt_identity$sha256)[1],
          as.character(transition$receipt_identity$sha256)[1]),
      "PYBENCH_REOPEN_VALIDATION_FAILED",
      paste0("Staged ABI v2 transition is absent or unauthenticated: ",
        transition_id), phase = "promotion",
      class = "wb_operation_pack_v2_error"
    )
    if (identical(as.character(record$request$schema %||% "")[1],
        "scworkbench.operation_pack.transition_request.v3"))
      .wb_operation_pack_v3_retained_provenance_assert_current(bundle,
        record$request, source)
    rel <- file.path("operation_pack_v2", transition_id)
    .wb_prepare_staged_payload(staging_bundle, workspace, rel)
  }
  invisible(workspace)
}

.wb_operation_pack_v2_write_registry_bindings <- function(
    bundle, snapshot_id, commit_id, run_id) {
  if (is.null(commit_id) || length(commit_id) == 0L ||
      is.na(commit_id[[1L]]) || !nzchar(as.character(commit_id[[1L]]))) {
    return(invisible(TRUE))
  }
  if (!.wb_table_exists(bundle$con, "prov_registry_mutations")) {
    return(invisible(TRUE))
  }
  rows <- DBI::dbGetQuery(
    bundle$con,
    paste0("SELECT * FROM prov_registry_mutations ",
      "WHERE commit_id = ? AND run_id = ? AND registry_type = ? ",
      "ORDER BY event_id;"),
    params = list(commit_id, run_id, "operation_pack_cell_set_family")
  )
  if (!nrow(rows)) return(invisible(TRUE))
  for (i in seq_len(nrow(rows))) {
    payload <- jsonlite::fromJSON(as.character(rows$payload_json[[i]]),
      simplifyVector = FALSE)
    family <- payload$family
    for (j in seq_along(family$sets %||% list())) {
      set <- family$sets[[j]]
      content_hash <- .wb_registry_entity_content_hash(bundle, "cell_set",
        as.character(set$name)[1])
      .wb_prov_insert_entity_binding(
        bundle$con, snapshot_id, commit_id, run_id, "output",
        paste0("registry:", payload$output_name, ":", j),
        "cell_set", as.character(set$name)[1], "MATERIALIZES",
        content_hash = content_hash,
        content_identity_scheme = unname(
          .wb_content_identity_schemes()[["registry"]]),
        source = "operation_pack_v2_registry_request",
        resolution_json = jsonlite::toJSON(list(
          transition_id = payload$transition_id,
          output_name = payload$output_name,
          family_identity = payload$family_identity,
          selection_rule = set$selection_rule
        ), auto_unbox = TRUE, null = "null")
      )
    }
  }
  invisible(TRUE)
}

#' Inspect Applied ABI v2 Registry Requests
#'
#' Reads core-owned promotion receipts without loading the producing operation
#' pack. One row is returned for each atomically admitted family request,
#' including valid empty families.
#'
#' @param bundle Open scworkbench bundle, including a read-only recipient.
#' @param transition_id Optional ABI v2 transition identifier.
#' @return A data frame of committed registry-admission receipts.
#' @export
wb_operation_pack_registry_receipts <- function(bundle, transition_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
    "bundle must be scworkbench_bundle")
  empty <- function() data.frame(
    transition_id = character(), run_id = character(),
    output_name = character(), request_kind = character(),
    mode = character(), n_sets = integer(), family_sha256 = character(),
    receipt_sha256 = character(), commit_id = character(),
    stringsAsFactors = FALSE
  )
  if (!.wb_table_exists(bundle$con, "prov_registry_mutations")) {
    return(empty())
  }
  rows <- DBI::dbGetQuery(
    bundle$con,
    paste0("SELECT prm.*, pc.state AS commit_state ",
      "FROM prov_registry_mutations prm ",
      "JOIN prov_commits pc ON pc.commit_id = prm.commit_id ",
      "WHERE prm.registry_type = ? AND pc.state = 'complete' ",
      "ORDER BY prm.commit_id, prm.event_id;"),
    params = list("operation_pack_cell_set_family")
  )
  if (!nrow(rows)) return(empty())
  parsed <- lapply(seq_len(nrow(rows)), function(i) {
    value <- jsonlite::fromJSON(as.character(rows$payload_json[[i]]),
      simplifyVector = FALSE)
    data.frame(
      transition_id = as.character(value$transition_id)[1],
      run_id = as.character(rows$run_id[[i]]),
      output_name = as.character(value$output_name)[1],
      request_kind = as.character(value$request_kind)[1],
      mode = as.character(value$family$mode)[1],
      n_sets = as.integer(length(value$family$sets %||% list())),
      family_sha256 = as.character(value$family_identity$sha256)[1],
      receipt_sha256 = as.character(value$receipt_identity$sha256)[1],
      commit_id = as.character(rows$commit_id[[i]]),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, parsed)
  if (!is.null(transition_id)) {
    out <- out[as.character(out$transition_id) ==
      as.character(transition_id)[1], , drop = FALSE]
  }
  rownames(out) <- NULL
  out
}

.wb_operation_pack_v2_assert_registry_receipts <- function(bundle) {
  if (!.wb_table_exists(bundle$con, "prov_registry_mutations")) {
    return(invisible(TRUE))
  }
  rows <- DBI::dbGetQuery(
    bundle$con,
    paste0("SELECT prm.* FROM prov_registry_mutations prm ",
      "JOIN prov_commits pc ON pc.commit_id = prm.commit_id ",
      "WHERE prm.registry_type = ? AND pc.state = 'complete' ",
      "ORDER BY prm.commit_id, prm.event_id;"),
    params = list("operation_pack_cell_set_family")
  )
  for (i in seq_len(nrow(rows))) {
    payload <- .wb_operation_pack_registry_event_payload(
      rows[i, , drop = FALSE])
    family <- .wb_operation_pack_cell_set_family_normalize(bundle,
      payload$family)
    .wb_operation_pack_assert(
      identical(attr(family, "family_identity")$sha256,
        as.character(payload$family_identity$sha256)[1]),
      "PYBENCH_REOPEN_VALIDATION_FAILED",
      "Committed registry receipt has an invalid family identity.",
      phase = "recipient", class = "wb_operation_pack_v2_error"
    )
    transition <- file.path(.wb_operation_pack_v2_store(bundle),
      .wb_operation_pack_v2_safe_component(payload$transition_id,
        "transition_id"))
    record <- .wb_operation_pack_v2_record_validate(transition,
      load_payloads = TRUE)
    request_names <- vapply(record$receipt$registry_requests %||% list(),
      `[[`, character(1), "name")
    index <- match(as.character(payload$output_name)[1], request_names)
    .wb_operation_pack_assert(
      isTRUE(record$ok) && !is.na(index) &&
        identical(as.character(record$receipt_identity$sha256)[1],
          as.character(payload$receipt_identity$sha256)[1]),
      "PYBENCH_REOPEN_VALIDATION_FAILED",
      "Committed registry receipt is not bound to its transition receipt.",
      phase = "recipient", class = "wb_operation_pack_v2_error"
    )
    for (set in family$sets) {
      observed <- as.character(wb_cells(bundle, cell_set = set$name))
      valid_membership <- if (identical(family$mode, "replace")) {
        identical(observed, as.character(set$cells))
      } else {
        all(as.character(set$cells) %in% observed)
      }
      .wb_operation_pack_assert(
        isTRUE(valid_membership),
        "PYBENCH_REOPEN_VALIDATION_FAILED",
        paste0("Committed cell-set-family membership changed: ", set$name),
        phase = "recipient", class = "wb_operation_pack_v2_error"
      )
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_registry_replay_rows <- function(bundle, run_ids) {
  empty <- data.frame(
    run_id = character(), output_name = character(),
    request_kind = character(), family_sha256 = character(),
    family_json = character(), stringsAsFactors = FALSE
  )
  if (!length(run_ids) ||
      !.wb_table_exists(bundle$con, "prov_registry_mutations")) {
    return(empty)
  }
  placeholders <- paste(rep("?", length(run_ids)), collapse = ",")
  rows <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT prm.run_id, prm.payload_json FROM prov_registry_mutations prm ",
    "JOIN prov_commits pc ON pc.commit_id = prm.commit_id ",
    "WHERE prm.registry_type = ? AND pc.state = 'complete' ",
    "AND prm.run_id IN (", placeholders, ") ORDER BY prm.run_id, prm.event_id;"),
    params = c(list("operation_pack_cell_set_family"), as.list(run_ids)))
  if (!nrow(rows)) return(empty)
  out <- lapply(seq_len(nrow(rows)), function(i) {
    payload <- jsonlite::fromJSON(as.character(rows$payload_json[[i]]),
      simplifyVector = FALSE)
    family <- payload$family
    data.frame(
      run_id = as.character(rows$run_id[[i]]),
      output_name = as.character(payload$output_name)[1],
      request_kind = as.character(payload$request_kind)[1],
      family_sha256 = as.character(payload$family_identity$sha256)[1],
      family_json = .wb_operation_pack_canonical_json(family),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

.wb_operation_pack_v2_assert_registry_replay <- function(expected, observed) {
  observed <- observed %||% list()
  .wb_assert(nrow(expected) == length(observed),
    "Strict replay registry-request count differs from the committed run.")
  if (!nrow(expected)) return(invisible(TRUE))
  observed_names <- vapply(observed, `[[`, character(1), "output_name")
  .wb_assert(!anyDuplicated(observed_names) &&
      setequal(as.character(expected$output_name), observed_names),
    "Strict replay registry-request names differ from the committed run.")
  expected <- expected[order(expected$output_name, method = "radix"), ,
    drop = FALSE]
  observed <- observed[match(expected$output_name, observed_names)]
  for (i in seq_len(nrow(expected))) {
    family <- observed[[i]]$family
    for (attribute in c("family_identity", "member_identities",
        "source_identity")) {
      attr(family, attribute) <- NULL
    }
    .wb_assert(
      identical(as.character(observed[[i]]$request_kind)[1],
        as.character(expected$request_kind[[i]])) &&
      identical(as.character(observed[[i]]$family_identity$sha256)[1],
        as.character(expected$family_sha256[[i]])) &&
      identical(.wb_operation_pack_canonical_json(family),
        as.character(expected$family_json[[i]])),
      paste0("Strict replay registry-request identity differs for output '",
        expected$output_name[[i]], "'.")
    )
  }
  invisible(TRUE)
}
