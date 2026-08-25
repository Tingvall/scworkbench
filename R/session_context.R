# R/session_context.R
# scworkbench session: primitives-only DAG runner
#
# Contract:
# - Ops return: list(outputs = named list of primitive objects, params = list(...))
# - Session stores only primitives in run$outputs
# - Active context stores refs to primitives, keyed by output name (e.g. "clusters", "space_2d")
# - Dependencies ("parents") are inferred ONLY when a required input is satisfied by a run ref.

.wb_ops <- function() {
  cat <- .wb_operation_catalog()
  lapply(cat, function(x) {
    produces <- x$produces %||% list()
    replay_equivalence <- x$replay_equivalence %||% list()
    for (nm in names(produces)) {
      if (is.null(replay_equivalence[[nm]])) {
        replay_equivalence[[nm]] <- if (identical(as.character(produces[[nm]])[1], "model_ref")) {
          "loadable_reference"
        } else {
          "exact_canonical_value"
        }
      }
    }
    list(
      requires = x$requires %||% list(),
      optional_requires = x$optional_requires %||% list(),
      produces = produces,
      runner = x$runner,
      promotable = x$promotable %||% character(0),
      replay_equivalence = replay_equivalence,
      coverage = x$coverage %||% list(),
      chunking = x$chunking %||% NULL
    )
  })
}

.wb_op <- function(op_name) {
  reg <- .wb_ops()
  if (!op_name %in% names(reg) && grepl("::", as.character(op_name)[1], fixed = TRUE)) {
    namespace <- strsplit(as.character(op_name)[1], "::", fixed = TRUE)[[1]][1]
    .wb_operation_pack_abort(
      "OPERATION_PACK_REQUIRED",
      paste0("Operation '", op_name, "' requires its exact compatible operation pack. Install and explicitly activate namespace '", namespace, "' with wb_operation_pack_load()."),
      operation = as.character(op_name)[1], namespace = namespace,
      class = "wb_operation_pack_unavailable"
    )
  }
  .wb_assert(op_name %in% names(reg), paste0("Unknown op: ", op_name))
  reg[[op_name]]
}

# ---------- Refs ----------
#' (Advanced) Create a Reference to a Session Run Output
#'
#' Use this in programmatic clients that compose explicit typed operation
#' inputs. Ordinary analyst workflows should prefer operation interfaces and
#' promoted artifact references when crossing sessions.
#' @param run_id Session-local run identifier.
#' @param output_name Name of the output on that run.
#'
#' @return A symbolic run-reference list for use in typed op inputs.
#' @export
wb_ref_run <- function(run_id, output_name) {
  list(ref_type = "run", run_id = as.character(run_id), output = as.character(output_name))
}
#' (Advanced) Create a Reference to a Promoted Artifact
#'
#' Use this in programmatic clients that compose explicit typed operation
#' inputs. Ordinary analyst workflows should select artifacts through getters
#' and operation interfaces.
#' @param artifact_id Promoted artifact identifier.
#' @param output_name Declared output name represented by the artifact.
#'
#' @return A symbolic artifact-reference list for use in typed op inputs.
#' @export
wb_ref_artifact <- function(artifact_id, output_name) {
  list(ref_type = "artifact", artifact_id = as.character(artifact_id), output = as.character(output_name))
}

# ---------- Session object ----------
#' Create a new wb_session
#' @export
wb_session_new <- function() {
  s <- list(
    session_id = .wb_allocate_identifier("session_", 12L, purpose = "session"),
    runs = list(),         # run_id -> wb_run
    active = list(),       # output_name -> ref
    head_run_id = NULL,
    staging_dir = NULL,
    staging_bundle = NULL,
    staging_source_dir = NULL
  )
  class(s) <- "wb_session"
  s
}
#' (Advanced) Check Whether an Object Is a wb_session
#'
#' @param x Object to test.
#' @return `TRUE` when `x` is a `wb_session`.
#' @export
wb_is_session <- function(x) inherits(x, "wb_session")

#' (Advanced) Set an Active Output Reference in a Session
#'
#' This mutates an in-memory execution session. Most analyst workflows should
#' provide explicit inputs to an operation rather than relying on active state.
#'
#' @param session A `wb_session`.
#' @param output_name Output name to associate with `ref`.
#' @param ref A `wb_ref_run()` or `wb_ref_artifact()` reference.
#' @return The updated session.
#' @export
wb_session_set_active <- function(session, output_name, ref) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  if (!is.null(session$durable)) {
    stop("DURABLE_SESSION_DIRECT_MUTATION: durable session graph changes must be made by wb_session_run_op().", call. = FALSE)
  }
  .wb_assert(is.list(ref) && !is.null(ref$ref_type), "ref must be a wb_ref_*")
  session$active[[as.character(output_name)]] <- ref
  session
}

.wb_session_set_active_checkpointable <- function(session, output_name, ref) {
  session$active[[as.character(output_name)]] <- ref
  session
}

#' (Advanced) Add a Run to a Session
#'
#' This is intended for controlled client or integration code. Use
#' [wb_session_run_op()] for ordinary operation execution.
#'
#' @param session A `wb_session`.
#' @param run A `wb_run` object.
#' @return The updated session.
#' @export
wb_session_add_run <- function(session, run) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(wb_is_run(run), "run must be a wb_run.")
  if (!is.null(session$durable)) stop("DURABLE_SESSION_DIRECT_MUTATION: durable session graph changes must be made by wb_session_run_op().", call. = FALSE)
  if (run$run_id %in% names(session$runs %||% list()) &&
      !identical(session$runs[[run$run_id]], run)) {
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_CONFLICT",
                         paste0("preallocated run identifier already exists: ", run$run_id), "run")
  }
  session$runs[[run$run_id]] <- run
  session$head_run_id <- run$run_id
  session
}

.wb_session_add_run_checkpointable <- function(session, run) {
  session$runs[[run$run_id]] <- run
  session$head_run_id <- run$run_id
  session
}

.wb_get_run <- function(session, run_id) {
  r <- session$runs[[run_id]]
  .wb_assert(!is.null(r), paste0("Run not found: ", run_id))
  r
}

.wb_session_output_refs_by_id <- function(session, expected_kind, value) {
  if (!is.character(value) || length(value) != 1L || !nzchar(value)) return(list())
  out <- list()
  for (rid in names(session$runs %||% list())) {
    run <- session$runs[[rid]]
    for (nm in names(run$outputs %||% list())) {
      prim <- run$outputs[[nm]]
      if (!.wb_is_primitive(prim) || !identical(as.character(prim$kind), expected_kind)) next
      id <- switch(expected_kind,
        matrix = as.character(prim$matrix_id %||% "")[1],
        space = as.character(prim$space_id %||% "")[1],
        space_2d = as.character(prim$space_id %||% "")[1],
        ""
      )
      if (identical(id, value)) out[[paste0(rid, "::", nm)]] <- wb_ref_run(rid, nm)
    }
  }
  out
}

# ---------- Resolve required inputs ----------
# Required inputs are keyed by name (e.g. "clusters") with an expected kind (e.g. "cell_vector").
# Resolution priority:
# 1) explicit inputs[[name]] (primitive or ref)
# 2) explicit ref inputs[[paste0(name, "_ref")]] (rare)
# 3) session active[[name]]
#
# Returns list(value=<primitive>, parents=<run_ids>, provenance_refs=<list of artifact refs>)
.wb_resolve_input <- function(bundle, session, name, expected_kind, inputs) {
  parents <- character(0)
  prov_refs <- list()

  # legacy aliases
  alias <- switch(
    name,
    space       = "space_id",
    space_2d    = "space_id",
    matrix      = "matrix_id",
    in_space    = "in_space_id",
    model_space = "model_space_id",
    NULL
  )

  val <- inputs[[name]] %||% (if (!is.null(alias)) inputs[[alias]] else NULL)
  ref <- NULL

  # Ergonomics: allow refs directly in inputs[[name]] in addition to inputs[[paste0(name, "_ref")]].
  # This keeps programmatic chaining natural for agents and humans:
  #   inputs = list(feature_table = wb_ref_run(...))
  if (!is.null(val) && is.list(val) && !is.null(val$ref_type)) {
    ref <- val
    val <- NULL
  }

  # A matrix/space id can be a convenient alias for a session-produced value,
  # but it must retain the producer run edge. Resolve it before lifting strings
  # into bare primitives; ambiguity is never silently downgraded to bundle state.
  if (!is.null(val) && is.character(val) && length(val) == 1L &&
      expected_kind %in% c("matrix", "space", "space_2d")) {
    candidates <- .wb_session_output_refs_by_id(session, expected_kind, as.character(val)[1])
    if (length(candidates) > 1L) {
      stop(
        "Ambiguous session-produced ", expected_kind, " id '", as.character(val)[1],
        "'. Use wb_ref_run(run_id, output_name) explicitly.", call. = FALSE
      )
    }
    if (length(candidates) == 1L) {
      ref <- candidates[[1]]
      val <- NULL
    }
  }

  if (is.null(val)) {
    ref <- ref %||%
      inputs[[paste0(name, "_ref")]] %||%
      (if (!is.null(alias)) inputs[[paste0(alias, "_ref")]] else NULL) %||%
      session$active[[name]] %||%
      (if (!is.null(alias)) session$active[[alias]] else NULL) %||%
      (if (name == "space") session$active$space_id else NULL) %||%
      (if (name == "matrix") session$active$matrix_id else NULL) %||%
      NULL

    .wb_assert(
      !is.null(ref),
      paste0(
        "Missing required input '", name, "'. ",
        "Provide inputs[['", name, "']]",
        if (!is.null(alias)) paste0(" (or inputs[['", alias, "']])") else "",
        " or set session active '", name, "'."
      )
    )

    if (!is.list(ref) || is.null(ref$ref_type)) {
      val <- ref
    } else {
      if (identical(ref$ref_type, "run")) {
        run <- .wb_get_run(session, ref$run_id)
        .wb_assert(ref$output %in% names(run$outputs),
                   paste0("Run ", ref$run_id, " has no output '", ref$output, "'."))
        val <- run$outputs[[ref$output]]
        parents <- unique(c(parents, ref$run_id))
      } else if (identical(ref$ref_type, "artifact")) {
        val <- try(wb_art_load(bundle, artifact_id = ref$artifact_id, expected_kind = expected_kind), silent = TRUE)
        if (inherits(val, "try-error") && !is.null(session$staging_source_dir)) {
          source_bundle <- wb_open_bundle(session$staging_source_dir, validate = FALSE)
          on.exit(wb_close_bundle(source_bundle), add = TRUE)
          val <- wb_art_load(source_bundle, artifact_id = ref$artifact_id, expected_kind = expected_kind)
        }
        if (inherits(val, "try-error")) stop(val)
        prov_refs[[name]] <- ref
      } else {
        stop("Unknown ref_type: ", ref$ref_type, call. = FALSE)
      }
    }
  }

  # ---- NEW: lift scalar IDs into primitives when caller supplied *_id ----
  # This keeps your nice UX: inputs=list(space_id="foo") works,
  # while the internal contract stays: inputs are primitives.
  if (!.wb_is_primitive(val)) {
    if (expected_kind == "space" && is.character(val) && length(val) == 1 && nzchar(val)) {
      val <- wb_prim_space(val)          # must return a space primitive
    }
    if (expected_kind == "matrix" && is.character(val) && length(val) == 1 && nzchar(val)) {
      val <- wb_prim_matrix(val)         # must return a matrix primitive
    }
    if (expected_kind == "in_space" && is.character(val) && length(val) == 1 && nzchar(val)) {
      val <- wb_prim_space(val)          # in_space is still a space primitive
    }
    if (expected_kind == "model_space" && is.character(val) && length(val) == 1 && nzchar(val)) {
      val <- wb_prim_space(val)          # model_space is also a space primitive
    }
    if (expected_kind == "space_2d" && is.character(val) && length(val) == 1 && nzchar(val)) {
      val <- wb_prim_space_2d(val)
    }
    if (expected_kind == "model_ref" && is.character(val) && length(val)==1 && nzchar(val)) {
      # interpret as model_space_id; but then in_space_id is unknown -> not safe
      val <- wb_prim_model_ref(model_space_id = val, in_space_id = "")
    }
    if (expected_kind == "cell_vector" && is.atomic(val) && !is.null(names(val))) {
      val <- wb_prim_cell_vector(val, value_type = "categorical")
    }
  }

  .wb_assert_kind(val, expected_kind, where = paste0(" for input '", name, "'"))
  list(value = val, parents = parents, prov_refs = prov_refs)
}

.wb_optional_input_present <- function(session, name, inputs) {
  alias <- switch(
    name,
    space       = "space_id",
    space_2d    = "space_id",
    matrix      = "matrix_id",
    in_space    = "in_space_id",
    model_space = "model_space_id",
    NULL
  )

  candidates <- list(
    inputs[[name]],
    if (!is.null(alias)) inputs[[alias]] else NULL,
    inputs[[paste0(name, "_ref")]],
    if (!is.null(alias)) inputs[[paste0(alias, "_ref")]] else NULL,
    session$active[[name]],
    if (!is.null(alias)) session$active[[alias]] else NULL,
    if (name == "space") session$active$space_id else NULL,
    if (name == "matrix") session$active$matrix_id else NULL
  )

  any(vapply(candidates, function(x) !is.null(x), logical(1)))
}



# ---------- Run op ----------
# Op contract: op(bundle, effective_cells, inputs = list(...), ...) -> list(outputs=<named primitives>, params=<list>)
#' (Advanced) Run an Operation in a Session
#'
#' This is the programmatic session executor used by clients and integrations.
#' Analysts should normally discover operation interfaces with
#' [wb_op_interface()] before constructing explicit inputs.
#'
#' @param session A `wb_session`.
#' @param bundle An open scworkbench bundle.
#' @param op_name Registered operation name.
#' @param ... Must be empty. Supply all operation inputs and parameters through
#'   the named `inputs` list.
#' @param inputs Named typed primitives, references, or supported symbolic
#'   inputs for the operation. After resolving all required and present optional
#'   typed inputs, the engine intersects their cell coverage once in canonical
#'   requested order. Structured input-by-input coverage is stored in
#'   `run$inputs$coverage`.
#' @param notes Optional run notes.
#' @return A list with `session` (the updated `wb_session`), `run` (the
#'   completed `wb_run`), and `result` (the operation result). Continue a
#'   session with `rr <- wb_session_run_op(...); session <- rr$session`.
#'
#' @section Long-running operation safety:
#' `run` is a structured `wb_run`, not a `data.frame` or `data.table`; do not
#' coerce or serialize it wholesale before promotion. For expensive operations,
#' immediately retain the returned `session`, inspect staged state with
#' [wb_session_view()], and promote the known terminal outputs with
#' [wb_session_promote_current()]. Write reports, exports, plots, identity
#' cards, and diagnostics only after promotion has succeeded. This guidance is
#' also shipped in `inst/onboarding/AGENT_ENGINEER_GUIDE.md` and `PLAYBOOK.md`.
#' @export
wb_session_run_op <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) {
  .wb_assert_bundle_writable(bundle, "session operations")
  dots <- list(...)
  .wb_assert(
    length(dots) == 0L,
    paste0(
      "wb_session_run_op(): operation inputs and parameters must be supplied in inputs. ",
      "Use wb_session_run_op(session, bundle, '", as.character(op_name)[1],
      "', inputs = list(matrix = ..., features = ..., top_n = ...))."
    )
  )
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  if (!is.null(session$durable)) {
    durable_state <- as.character(session$durable$state %||% "")[1]
    .wb_assert(identical(durable_state, "active"),
               paste0("DURABLE_SESSION_", toupper(durable_state), ": terminal sessions cannot run new operations."))
    .wb_session_validate_source(session, bundle)
    .wb_session_validate_payloads(session)
  }
  session_lock <- NULL
  if (!is.null(session$durable)) {
    session_lock <- .wb_bundle_writer_lock_acquire(
      session$durable$workspace, operation = "durable session operation"
    )
    on.exit(.wb_bundle_writer_lock_release(session_lock), add = TRUE)
    # This must be inside the workspace lock: a handle may have been opened
    # before another process published a later checkpoint.
    .wb_session_assert_mutation_owner(session)
    .wb_session_validate_checkpoint_state(session)
    .wb_session_validate_source(session, bundle)
    .wb_session_validate_payloads(session)
  }
  op <- .wb_op(op_name)
  validated <- .wb_validate_op_inputs_contract(op_name = op_name, inputs = inputs, session = session)
  inputs <- validated$inputs

  # Allocate administrative identity before staging or runner execution. A
  # collision or entropy failure is therefore a strict zero-write failure.
  planned_run_id <- .wb_allocate_identifier(
    "run_", 12L, purpose = "run",
    occupied = function(candidate) {
      staged_con <- if (!is.null(session$staging_bundle)) session$staging_bundle$con else NULL
      candidate %in% names(session$runs %||% list()) ||
        .wb_db_identifier_exists(bundle$con, "prov_runs", "run_id", candidate) ||
        .wb_db_identifier_exists(staged_con, "prov_runs", "run_id", candidate) ||
        .wb_db_identifier_exists(staged_con, "registry_mutation_events", "run_id", candidate)
    }
  )

  staged <- .wb_session_stage_bundle(bundle, session)
  session <- staged$session
  work_bundle <- staged$bundle

  cell_set <- inputs$cell_set %||% "all"
  # Resolve the complete typed input contract before deriving cell coverage.
  resolved <- list()
  parents <- character(0)
  prov_refs <- list()

  req <- op$requires %||% list()
  if (length(req)) {
    for (nm in names(req)) {
      kind <- req[[nm]]
      rr <- .wb_resolve_input(work_bundle, session, nm, kind, inputs)
      resolved[[nm]] <- rr$value
      parents <- unique(c(parents, rr$parents))
      prov_refs <- c(prov_refs, rr$prov_refs)
    }
  }

  opt_req <- op$optional_requires %||% list()
  if (length(opt_req)) {
    for (nm in names(opt_req)) {
      if (!.wb_optional_input_present(session, nm, inputs)) next
      kind <- opt_req[[nm]]
      rr <- .wb_resolve_input(work_bundle, session, nm, kind, inputs)
      resolved[[nm]] <- rr$value
      parents <- unique(c(parents, rr$parents))
      prov_refs <- c(prov_refs, rr$prov_refs)
    }
  }
  .wb_validate_resolved_op_inputs(op_name, resolved)

  # This is the sole operation-runner ownership point for effective cells.
  # Every cell-bearing required or present optional primitive participates.
  requirements <- c(req, opt_req[names(opt_req) %in% names(resolved)])
  coverage <- .wb_typed_effective_cells(
    bundle = work_bundle,
    cell_set = cell_set,
    inputs = inputs,
    resolved = resolved,
    requirements = requirements,
    op_name = op_name,
    min_cells = inputs$min_cells %||% 10L,
    coverage_modes = op$coverage %||% list()
  )
  effective_cells <- coverage$cells

  runner <- op$runner
  .wb_assert(is.function(runner), paste0("No runner registered for op: ", op_name))
  work_bundle$pybench_session_binding <- list(
    session_id = as.character(session$session_id)[1],
    source_attestation = list(
      scheme = "scworkbench-scientific-state-v1",
      content_sha256 = as.character((session$durable %||% list(source_identity = .wb_session_source_identity(bundle)))$source_identity$scientific_state_fingerprint)[1]
    ),
    checkpoint_generation = as.character((session$durable %||% list(checkpoint_generation = "ephemeral"))$checkpoint_generation %||% "ephemeral")[1],
    root_sha256 = .wb_prov_sha256_object(list(
      session_id = as.character(session$session_id)[1],
      stage_root = normalizePath(work_bundle$dir, winslash = "/", mustWork = TRUE)
    ))
  )
  if (!is.null(session$durable)) {
    .wb_session_operation_marker(session, op_name = op_name, run_id = planned_run_id)
    completed_operation <- FALSE
    on.exit(if (!isTRUE(completed_operation)) invisible(NULL), add = TRUE)
  }
  res <- .wb_with_mutation_context(
    bundle = work_bundle,
    route = "session_execution",
    run_id = planned_run_id,
    op_name = op_name,
    code = runner(bundle = work_bundle, resolved = resolved, effective_cells = effective_cells, inputs = inputs)
  )
  res <- .wb_assert_op_result(op_name, res)


  .wb_assert(
    is.list(res) && is.list(res$outputs),
    paste0("Op '", op_name, "' must return list(outputs=<named list>, params=<list>).")
  )


  # Validate produced outputs
  out <- res$outputs
  prod <- op$produces %||% list()
  .wb_validate_op_outputs(op_name, out)

  run_inputs <- list(
    cell_set = cell_set,
    effective_n = length(effective_cells),
    parents = parents,
    provenance_refs = prov_refs,
    coverage = coverage$diagnostics,
    user_inputs = inputs,
    symbolic_inputs = .wb_symbolic_inputs_snapshot(op_name = op_name, inputs = inputs),
    execution_inputs = .wb_execution_inputs_snapshot(
      resolved = resolved,
      effective_cells = effective_cells
    )
  )

  run <- wb_new_run(
    op_name = op_name,
    inputs  = run_inputs,
    params  = .wb_merge_validated_run_params(res$params, validated$params),
    outputs = out,
    notes   = notes,
    run_id = planned_run_id
  )
  pack_identity <- .wb_operation_pack_identity_for_op(op_name)
  if (!is.null(pack_identity)) {
    run$operation_pack <- pack_identity
    run$operation_definition_sha256 <- as.character(
      pack_identity$operation_definition_sha256[[op_name]] %||% NA_character_
    )[1]
    if (!is.null(res$operation_pack_runtime)) {
      run$operation_pack_runtime <- res$operation_pack_runtime
    }
  }

  session <- if (is.null(session$durable)) wb_session_add_run(session, run) else .wb_session_add_run_checkpointable(session, run)

  # Update active outputs (by name) for anything produced
  for (nm in names(out)) {
    session <- if (is.null(session$durable)) wb_session_set_active(session, nm, wb_ref_run(run$run_id, nm)) else .wb_session_set_active_checkpointable(session, nm, wb_ref_run(run$run_id, nm))
  }

  if (!is.null(session$durable)) {
    session$durable$runtime_attestations[[run$run_id]] <- .wb_prov_runtime_fingerprint(
      op_name, operation_pack_runtime = run$operation_pack_runtime %||% NULL)
    session <- .wb_session_record_payload_identities(session, run)
    session <- .wb_session_checkpoint(session, "active", allow_uncheckpointed_state = TRUE)
    .wb_session_operation_marker(session, clear = TRUE)
    completed_operation <- TRUE
  }

  list(session = session, run = run, result = res)
}


# op contract:

.wb_assert_op_result <- function(op_name, res) {
  .wb_assert(is.list(res),
             paste0("Op '", op_name, "' must return a list."))

  .wb_assert(!is.null(res$outputs) && is.list(res$outputs),
             paste0("Op '", op_name, "' must return list(outputs=<named list>, params=<list>)."))

  .wb_assert(!is.null(names(res$outputs)) && all(nzchar(names(res$outputs))),
             paste0("Op '", op_name, "' outputs must be a named list."))

  if (is.null(res$params)) res$params <- list()
  .wb_assert(is.list(res$params),
             paste0("Op '", op_name, "' params must be a list (or NULL)."))

  # primitives are the currency
  for (nm in names(res$outputs)) {
    .wb_assert(
      .wb_is_primitive(res$outputs[[nm]]),
      paste0("Expected primitive object for output '", nm, "'.")
    )
  }

  res
}

.wb_is_ref_run <- function(x) {
  is.list(x) && identical(as.character(x$ref_type %||% "")[1], "run")
}

.wb_is_ref_artifact <- function(x) {
  is.list(x) && identical(as.character(x$ref_type %||% "")[1], "artifact")
}

.wb_symbolic_ref_compact <- function(x) {
  if (.wb_is_ref_run(x)) {
    return(list(
      ref_type = "run",
      run_id = as.character(x$run_id %||% NA_character_)[1],
      output = as.character(x$output %||% NA_character_)[1]
    ))
  }
  if (.wb_is_ref_artifact(x)) {
    return(list(
      ref_type = "artifact",
      artifact_id = as.character(x$artifact_id %||% NA_character_)[1],
      output = as.character(x$output %||% NA_character_)[1]
    ))
  }
  x
}

.wb_symbolic_param_types <- function(op_name) {
  cat <- .wb_operation_catalog()
  op <- cat[[op_name]] %||% list()
  p <- op$params %||% list()
  if (!length(p)) return(stats::setNames(character(0), character(0)))
  nm <- vapply(p, function(x) as.character(x$name %||% "")[1], character(1))
  tp <- vapply(p, function(x) as.character(x$type %||% "")[1], character(1))
  keep <- nzchar(nm) & nzchar(tp)
  stats::setNames(tp[keep], nm[keep])
}

.wb_symbolic_inputs_snapshot <- function(op_name, inputs) {
  x <- inputs %||% list()
  if (!is.list(x)) x <- list()

  out <- list(
    cell_set = as.character(x$cell_set %||% "all")[1],
    min_cells = as.integer(x$min_cells %||% 10L)
  )

  ptypes <- .wb_symbolic_param_types(op_name)
  for (nm in names(ptypes)) {
    val <- x[[nm]]
    if (is.null(val)) next
    tp <- ptypes[[nm]]

    if (identical(tp, "cell_ids_or_set")) {
      if (.wb_is_ref_run(val) || .wb_is_ref_artifact(val)) {
        out[[nm]] <- .wb_symbolic_ref_compact(val)
        next
      }
      if (is.character(val)) {
        vv <- unique(as.character(val))
        vv <- vv[nzchar(vv)]
        if (!length(vv)) next
        if (length(vv) == 1 && startsWith(vv, "set:")) {
          out[[nm]] <- vv[[1]]
        } else {
          out[[nm]] <- vv
        }
        next
      }
    }

    out[[nm]] <- .wb_symbolic_ref_compact(val)
  }

  # Required primitives can be supplied as durable identifiers (for example
  # matrix = "RNA_log_norm" or space = "rna_pca"), not only as run/artifact
  # refs.  Preserve them in symbolic provenance so a cross-snapshot replay
  # does not have to infer a source input from runner diagnostics.
  op <- .wb_op(op_name)
  required_names <- unique(c(names(op$requires %||% list()), names(op$optional_requires %||% list())))
  for (nm in required_names) {
    if (is.null(out[[nm]]) && !is.null(x[[nm]])) out[[nm]] <- .wb_symbolic_ref_compact(x[[nm]])
  }

  # keep explicit symbolic run/artifact refs even if they are not op params
  extras <- names(x)
  for (nm in extras) {
    if (!is.null(out[[nm]])) next
    val <- x[[nm]]
    if (.wb_is_ref_run(val) || .wb_is_ref_artifact(val)) {
      out[[nm]] <- .wb_symbolic_ref_compact(val)
    }
  }

  out
}

.wb_execution_inputs_snapshot <- function(resolved, effective_cells) {
  res_compact <- list()
  if (length(resolved %||% list())) {
    for (nm in names(resolved)) {
      val <- resolved[[nm]]
      if (.wb_is_primitive(val)) {
        res_compact[[nm]] <- .wb_prim_summary(val)
      }
    }
  }

  list(
    effective_n = as.integer(length(effective_cells %||% character(0))),
    resolved = res_compact
  )
}
