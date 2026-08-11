# Public execution boundary for portable target-reproduction scripts.

.wb_target_plan_assert_executable <- function(plan) {
  .wb_assert(inherits(plan, "wb_target_reproduction_plan"),
             "plan must be a wb_target_reproduction_plan")
  .wb_assert(isTRUE(plan$reproducible) && identical(as.character(plan$status), "ok"),
             "plan is not executable: status must be ok and reproducible")
  .wb_assert(is.data.frame(plan$runs) && nrow(plan$runs) > 0L,
             "plan$runs must be a non-empty data frame")
  required_run_fields <- c(
    "run_id", "op_name", "notes", "params_json", "inputs_json",
    "symbolic_inputs_json"
  )
  .wb_assert(all(required_run_fields %in% names(plan$runs)),
             "plan$runs is missing required persisted replay fields")
  run_order <- as.character(plan$run_order %||% character())
  .wb_assert(length(run_order) > 0L && !anyNA(run_order) &&
               all(nzchar(run_order)) && !anyDuplicated(run_order),
             "plan$run_order must contain unique non-empty run IDs")
  .wb_assert(identical(run_order, as.character(plan$runs$run_id)),
             "plan$runs must be in the exact declared topological run order")
  .wb_assert(all(vapply(as.character(plan$runs$op_name), function(op) {
    !inherits(try(.wb_get_op(op), silent = TRUE), "try-error")
  }, logical(1))), "plan contains an unavailable operation")
  .wb_assert(is.list(plan$target) &&
               as.character(plan$target$producing_run_id %||% "")[1] %in% run_order,
             "plan target producer is absent from run_order")

  required_frames <- list(
    boundary_prerequisites = c(
      "run_id", "entity_kind", "entity_id", "binding_name", "content_hash"
    ),
    terminal_outputs = c(
      "run_id", "output_name", "primitive_kind", "content_sha256",
      "content_identity_scheme", "replay_equivalence_policy",
      "replay_equivalence_reference"
    ),
    promotion_outputs = c("run_id", "output_name"),
    durable_outputs = c("run_id", "entity_kind", "entity_id"),
    artifact_sources = c("artifact_id", "run_id", "output_name")
  )
  for (name in names(required_frames)) {
    value <- plan[[name]] %||% data.frame()
    .wb_assert(is.data.frame(value) && all(required_frames[[name]] %in% names(value)),
               paste0("plan$", name, " is missing required fields"))
  }
  .wb_assert(nrow(plan$promotion_outputs) > 0L,
             "plan has no promotable terminal outputs")
  terminal_keys <- paste(
    plan$terminal_outputs$run_id, plan$terminal_outputs$output_name, sep = "\r"
  )
  promotion_keys <- paste(
    plan$promotion_outputs$run_id, plan$promotion_outputs$output_name, sep = "\r"
  )
  .wb_assert(all(promotion_keys %in% terminal_keys),
             "plan promotion outputs must be terminal outputs")
  policies <- as.character(plan$terminal_outputs$replay_equivalence_policy)
  .wb_assert(all(policies %in% .wb_replay_equivalence_policies()) &&
               !any(policies == "not_comparable"),
             "all terminal outputs require a supported replay-equivalence policy")
  invisible(plan)
}

.wb_target_path_has_write_mode <- function(path) {
  info <- file.info(path)
  isTRUE(!is.na(info$mode[1])) && bitwAnd(as.integer(info$mode[1]), 146L) != 0L
}

.wb_target_boundary_identity <- function(bundle, kind, id) {
  if (identical(kind, "matrix")) {
    return(.wb_prov_payload_identity(bundle, wb_prim_matrix(id)))
  }
  if (identical(kind, "space")) {
    return(.wb_prov_payload_identity(bundle, wb_prim_space(id)))
  }
  if (identical(kind, "artifact")) {
    return(.wb_prov_payload_identity(bundle, wb_art_load(bundle, id)))
  }
  if (identical(kind, "model_ref")) {
    parts <- strsplit(id, "|", fixed = TRUE)[[1L]]
    .wb_assert(length(parts) >= 3L,
               paste0("Missing immutable boundary model_ref:", id))
    return(.wb_prov_payload_identity(
      bundle, wb_prim_model_ref(parts[2L], parts[3L], engine = parts[1L])
    ))
  }
  stop("Unsupported immutable boundary kind: ", kind, call. = FALSE)
}

.wb_target_preflight_execution_bundle <- function(plan, execution_bundle_dir) {
  destination <- as.character(execution_bundle_dir %||% "")[1]
  .wb_assert(nzchar(destination) &&
               !identical(destination, "<WRITABLE_INGESTION_READY_CLONE>"),
             "Destination must identify an existing writable ingestion-ready clone.")
  .wb_assert(dir.exists(destination),
             "Destination must be an existing writable ingestion-ready clone.")
  destination <- normalizePath(destination, winslash = "/", mustWork = TRUE)
  source <- as.character(plan$source_bundle_dir %||% "")[1]
  if (nzchar(source)) {
    source <- normalizePath(source, winslash = "/", mustWork = FALSE)
    .wb_assert(!identical(destination, source),
               "Refusing to mutate the inspected source bundle.")
  }

  manifest_path <- file.path(destination, "manifest.json")
  .wb_assert(file.exists(manifest_path),
             "Destination must be an existing writable ingestion-ready clone.")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  db_path <- .wb_bundle_path_require(
    destination, as.character(manifest$storage$sqlite$path %||% "")[1],
    expected_type = "file", purpose = "target reproduction SQLite database"
  )
  .wb_assert(
    file.access(destination, 2L) == 0L && file.access(db_path, 2L) == 0L &&
      .wb_target_path_has_write_mode(destination) &&
      .wb_target_path_has_write_mode(db_path),
    "Destination is a read-only recipient bundle, not a writable execution clone."
  )

  inspection <- wb_open_bundle(destination, read_only = TRUE)
  on.exit(wb_close_bundle(inspection), add = TRUE)

  if (nrow(plan$boundary_prerequisites)) {
    for (i in seq_len(nrow(plan$boundary_prerequisites))) {
      row <- plan$boundary_prerequisites[i, , drop = FALSE]
      kind <- as.character(row$entity_kind[1])
      id <- as.character(row$entity_id[1])
      expected <- as.character(row$content_hash[1] %||% "")[1]
      present <- if (kind == "matrix") {
        id %in% wb_matrices(inspection, include_history = TRUE)$matrix_id
      } else if (kind == "space") {
        id %in% wb_spaces(inspection, include_history = TRUE)$space_id
      } else if (kind == "artifact") {
        id %in% wb_art_list(inspection, include_history = TRUE)$artifact_id
      } else if (kind == "model_ref") {
        parts <- strsplit(id, "|", fixed = TRUE)[[1L]]
        length(parts) >= 2L &&
          parts[2L] %in% wb_spaces(inspection, include_history = TRUE)$space_id
      } else FALSE
      .wb_assert(isTRUE(present),
                 paste0("Missing immutable boundary ", kind, ":", id))
      .wb_assert(grepl("^[0-9a-f]{64}$", expected),
                 paste0("Missing immutable boundary identity ", kind, ":", id))
      observed <- .wb_target_boundary_identity(inspection, kind, id)$content_sha256
      .wb_assert(identical(tolower(expected), tolower(as.character(observed))),
                 paste0("Immutable boundary identity mismatch ", kind, ":", id))
    }
  }

  matrices <- wb_matrices(inspection, include_history = TRUE)$matrix_id
  spaces <- wb_spaces(inspection, include_history = TRUE)$space_id
  if (nrow(plan$durable_outputs)) {
    for (i in seq_len(nrow(plan$durable_outputs))) {
      row <- plan$durable_outputs[i, , drop = FALSE]
      kind <- as.character(row$entity_kind[1])
      id <- as.character(row$entity_id[1])
      collision <- (kind == "matrix" && id %in% matrices) ||
        (kind == "space" && id %in% spaces) ||
        (kind == "model_ref" && {
          parts <- strsplit(id, "|", fixed = TRUE)[[1L]]
          length(parts) >= 2L && parts[2L] %in% spaces
        })
      .wb_assert(!isTRUE(collision),
                 paste0("Durable output collision: ", kind, ":", id))
    }
  }

  if (all(c("prov_runs", "prov_heads") %in% DBI::dbListTables(inspection$con))) {
    analytical <- DBI::dbGetQuery(inspection$con, "
      SELECT DISTINCT r.run_id
        FROM prov_runs AS r
       WHERE NOT EXISTS (
         SELECT 1 FROM prov_heads AS h
          WHERE h.snapshot_id = r.snapshot_id AND h.name_prefix = 'ingestion'
       );
    ")$run_id
    .wb_assert(!length(analytical),
               "Destination is not source-only: analytical provenance runs are already present.")
  }
  destination
}

.wb_target_rewrite_refs <- function(x, replay_map, artifact_replay_map) {
  if (!is.list(x)) return(x)
  type <- as.character(x$ref_type %||% "")[1]
  if (identical(type, "run")) {
    old <- as.character(x$run_id %||% "")[1]
    if (nzchar(old) && !is.null(replay_map[[old]])) x$run_id <- replay_map[[old]]
    return(x)
  }
  if (identical(type, "artifact")) {
    source <- artifact_replay_map[[as.character(x$artifact_id %||% "")[1]]]
    if (!is.null(source) && !is.null(replay_map[[source$run_id]])) {
      return(wb_ref_run(replay_map[[source$run_id]], source$output))
    }
    return(x)
  }
  out <- lapply(
    x, .wb_target_rewrite_refs,
    replay_map = replay_map, artifact_replay_map = artifact_replay_map
  )
  if (!is.null(names(x))) names(out) <- names(x)
  out
}

#' Execute and verify a target reproduction plan
#'
#' This is the sole public mutation boundary used by target-reproduction
#' scripts. It accepts a successful plan and one existing source-only writable
#' clone. Before analytical execution it rejects the inspected source path,
#' filesystem-read-only recipient bundles, missing or changed immutable
#' boundaries, pre-existing analytical runs, ambiguous plans, and durable
#' output collisions. Runs execute in a private session overlay.
#' Terminal replay-equivalence and model-loadability checks complete before
#' promotion, so a failed replay cannot create partial promoted claims.
#'
#' @param plan A successful `wb_target_reproduction_plan`.
#' @param execution_bundle_dir Existing writable ingestion-ready source clone.
#' @return A `wb_target_reproduction_result` list with `schema_version`,
#'   `status`, `execution_bundle_dir`, `original_run_order`, `run_map`,
#'   `promotion`, and durable `verification` rows. The function stops before
#'   promotion on any invalid input, preflight failure, replay error, or failed
#'   equivalence/loadability policy.
#' @export
wb_target_execute_plan <- function(plan, execution_bundle_dir) {
  .wb_target_plan_assert_executable(plan)
  destination <- .wb_target_preflight_execution_bundle(plan, execution_bundle_dir)
  bundle <- wb_open_bundle(destination, read_only = FALSE)
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)

  payload <- .wb_prov_payload_from_runs(
    plan$runs, plan$run_order, mode = "symbolic"
  )
  artifact_replay_map <- list()
  if (nrow(plan$artifact_sources)) {
    for (i in seq_len(nrow(plan$artifact_sources))) {
      artifact_replay_map[[as.character(plan$artifact_sources$artifact_id[i])]] <- list(
        run_id = as.character(plan$artifact_sources$run_id[i]),
        output = as.character(plan$artifact_sources$output_name[i])
      )
    }
  }
  replay_map <- list()
  run_rows <- list()
  session <- wb_session_new()
  completed <- FALSE
  on.exit(if (!isTRUE(completed)) try(wb_session_discard(session), silent = TRUE),
          add = TRUE)
  target_result <- NULL
  for (i in seq_along(plan$run_order)) {
    run_id <- as.character(plan$run_order[i])
    row <- plan$runs[i, , drop = FALSE]
    execution_inputs <- .wb_prov_replay_execution_inputs(
      payload[[run_id]]$inputs, payload[[run_id]]$params,
      run_id = run_id, op_name = as.character(row$op_name[1])
    )
    execution_inputs <- .wb_target_rewrite_refs(
      execution_inputs, replay_map = replay_map,
      artifact_replay_map = artifact_replay_map
    )
    result <- wb_session_run_op(
      session, bundle, as.character(row$op_name[1]),
      inputs = execution_inputs,
      notes = as.character(row$notes[1] %||% "")[1]
    )
    session <- result$session
    replay_map[[run_id]] <- as.character(result$run$run_id)
    run_rows[[i]] <- data.frame(
      order = as.integer(i), original_run_id = run_id,
      replay_run_id = as.character(result$run$run_id),
      op_name = as.character(row$op_name[1]), status = "executed",
      stringsAsFactors = FALSE
    )
    if (identical(run_id, as.character(plan$target$producing_run_id)[1])) {
      target_result <- result
    }
  }
  .wb_assert(!is.null(target_result), "Target run was not replayed.")

  hook <- getOption("scworkbench.target_reproduction_test_hook")
  if (is.function(hook)) {
    replacement <- hook(
      event = "before_terminal_verification", plan = plan, bundle = bundle,
      session = session, target_result = target_result
    )
    if (!is.null(replacement)) target_result <- replacement
  }

  stage_bundle <- wb_session_view(session)
  preverified <- lapply(seq_len(nrow(plan$terminal_outputs)), function(i) {
    row <- plan$terminal_outputs[i, , drop = FALSE]
    output_name <- as.character(row$output_name[1])
    primitive <- target_result$run$outputs[[output_name]]
    .wb_assert(!is.null(primitive),
               paste0("Replayed target omitted terminal output: ", output_name))
    .wb_prov_verify_replay_output(
      bundle = stage_bundle,
      original_run_id = as.character(row$run_id[1]),
      original_output_name = output_name,
      expected_kind = as.character(row$primitive_kind[1]),
      expected_content_sha256 = as.character(row$content_sha256[1] %||% NA_character_),
      expected_content_identity_scheme = as.character(
        row$content_identity_scheme[1] %||% NA_character_
      ),
      replay_equivalence_policy = as.character(row$replay_equivalence_policy[1]),
      expected_reference = as.character(
        row$replay_equivalence_reference[1] %||% NA_character_
      ),
      replayed_prim = primitive,
      replay_run_id = replay_map[[as.character(row$run_id[1])]],
      replay_snapshot_id = "prepromotion",
      replay_artifact_id = NA_character_, persist = FALSE
    )
  })

  selections <- lapply(seq_len(nrow(plan$promotion_outputs)), function(i) {
    row <- plan$promotion_outputs[i, , drop = FALSE]
    wb_ref_run(
      replay_map[[as.character(row$run_id[1])]],
      as.character(row$output_name[1])
    )
  })
  promotion <- wb_session_promote_current(bundle, session, outputs = selections)

  verification <- .wb_with_bundle_writer_lock(
    bundle, operation = "target reproduction verification receipts", code = {
      DBI::dbWithTransaction(bundle$con, {
        do.call(rbind, lapply(
          seq_len(nrow(plan$terminal_outputs)), function(i) {
            row <- plan$terminal_outputs[i, , drop = FALSE]
            output_name <- as.character(row$output_name[1])
            replay_run_id <- replay_map[[as.character(row$run_id[1])]]
            promoted_rows <- promotion$promoted[
              as.character(promotion$promoted$run_id) == replay_run_id &
                as.character(promotion$promoted$output) == output_name,
              , drop = FALSE
            ]
            replay_artifact_id <- if (nrow(promoted_rows)) {
              as.character(promoted_rows$artifact_id[1])
            } else NA_character_
            .wb_prov_verify_replay_output(
              bundle = bundle,
              original_run_id = as.character(row$run_id[1]),
              original_output_name = output_name,
              expected_kind = as.character(row$primitive_kind[1]),
              expected_content_sha256 = as.character(
                row$content_sha256[1] %||% NA_character_
              ),
              expected_content_identity_scheme = as.character(
                row$content_identity_scheme[1] %||% NA_character_
              ),
              replay_equivalence_policy = as.character(
                row$replay_equivalence_policy[1]
              ),
              expected_reference = as.character(
                row$replay_equivalence_reference[1] %||% NA_character_
              ),
              replayed_prim = target_result$run$outputs[[output_name]],
              replay_run_id = replay_run_id,
              replay_snapshot_id = promotion$provenance_snapshot_id,
              replay_artifact_id = replay_artifact_id, persist = TRUE
            )
          }
        ))
      })
    }
  )
  session <- wb_session_discard(session)
  completed <- TRUE
  structure(list(
    schema_version = "scworkbench.target_reproduction_result.v1",
    status = "promoted_and_verified",
    execution_bundle_dir = destination,
    original_run_order = as.character(plan$run_order),
    run_map = do.call(rbind, run_rows),
    promotion = promotion,
    verification = verification,
    prepromotion_verification = do.call(rbind, preverified)
  ), class = c("wb_target_reproduction_result", "list"))
}
