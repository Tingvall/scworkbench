# R/session_context.R
# scworkbench session: primitives-only DAG runner
#
# Contract:
# - Ops return: list(outputs = named list of primitive objects, params = list(...))
# - Session stores only primitives in run$outputs
# - Active context stores refs to primitives, keyed by output name (e.g. "clusters", "space_2d")
# - Dependencies ("parents") are inferred ONLY when a required input is satisfied by a run ref.

`%||%` <- function(x, y) if (is.null(x)) y else x

.wb_ops <- function() {
  cat <- .wb_op_catalog()
  lapply(cat, function(x) {
    list(
      requires = x$requires %||% list(),
      optional_requires = x$optional_requires %||% list(),
      produces = x$produces %||% list(),
      runner = x$runner,
      promotable = x$promotable %||% character(0),
      chunking = x$chunking %||% NULL
    )
  })
}

.wb_op <- function(op_name) {
  reg <- .wb_ops()
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
    session_id = paste0("session_", paste(sample(c(letters, 0:9), 12, TRUE), collapse = "")),
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
  .wb_assert(is.list(ref) && !is.null(ref$ref_type), "ref must be a wb_ref_*")
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
#'   inputs for the operation.
#' @param notes Optional run notes.
#' @return A list with `session` (the updated `wb_session`), `run` (the
#'   completed `wb_run`), and `result` (the operation result). Continue a
#'   session with `rr <- wb_session_run_op(...); session <- rr$session`.
#' @export
wb_session_run_op <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) {
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
  op <- .wb_op(op_name)
  .wb_validate_op_inputs_contract(op_name = op_name, inputs = inputs)

  staged <- .wb_session_stage_bundle(bundle, session)
  session <- staged$session
  work_bundle <- staged$bundle

  # Resolve effective_cells once, here. Nothing else is allowed to compute cells.
  cell_set <- inputs$cell_set %||% "all"
  effective_cells <- .wb_effective_cells(
    bundle = work_bundle,
    cell_set = cell_set,
    inputs = inputs,     # your coverage function can inspect space_id/matrix_id etc if you want
    op_name = op_name,
    min_cells = inputs$min_cells %||% 10
  )

  # Resolve required inputs (primitives)
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

  runner <- op$runner
  .wb_assert(is.function(runner), paste0("No runner registered for op: ", op_name))
  planned_run_id <- paste0("run_", paste(sample(c(letters, 0:9), 12, TRUE), collapse = ""))
  previous_context <- getOption("scworkbench.registry_mutation_context")
  options(scworkbench.registry_mutation_context = list(run_id = planned_run_id, op_name = op_name))
  on.exit(options(scworkbench.registry_mutation_context = previous_context), add = TRUE)
  res <- runner(bundle = work_bundle, resolved = resolved, effective_cells = effective_cells, inputs = inputs)
  res <- .wb_assert_op_result(op_name, res)


  .wb_assert(
    is.list(res) && is.list(res$outputs),
    paste0("Op '", op_name, "' must return list(outputs=<named list>, params=<list>).")
  )


  # Validate produced outputs
  out <- res$outputs
  prod <- op$produces %||% list()
  for (nm in names(prod)) {
    .wb_assert(nm %in% names(out),
               paste0("Op '", op_name, "' did not produce required output '", nm, "'."))
    .wb_assert_kind(out[[nm]], prod[[nm]], where = paste0(" for output '", nm, "'"))
  }

  run_inputs <- list(
    cell_set = cell_set,
    effective_n = length(effective_cells),
    parents = parents,
    provenance_refs = prov_refs,
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
    params  = res$params %||% list(),
    outputs = out,
    notes   = notes,
    run_id = planned_run_id
  )

  session <- wb_session_add_run(session, run)

  # Update active outputs (by name) for anything produced
  for (nm in names(out)) {
    session <- wb_session_set_active(session, nm, wb_ref_run(run$run_id, nm))
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
  cat <- .wb_op_catalog()
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

.wb_validate_cell_ids_or_set <- function(val, nm) {
  if (.wb_is_ref_run(val) || .wb_is_ref_artifact(val)) return(invisible(TRUE))
  .wb_assert(is.character(val), paste0("inputs$", nm, " must be character, wb_ref_run(), or wb_ref_artifact()."))
  .wb_assert(length(val) > 0, paste0("inputs$", nm, " must be non-empty."))
  vv <- unique(as.character(val))
  vv <- vv[nzchar(vv)]
  .wb_assert(length(vv) > 0, paste0("inputs$", nm, " is empty after cleaning."))
  set_flags <- startsWith(vv, "set:")
  .wb_assert(all(set_flags | !set_flags), paste0("inputs$", nm, " invalid value."))
  invisible(TRUE)
}

.wb_validate_op_inputs_contract <- function(op_name, inputs) {
  inputs <- inputs %||% list()
  .wb_assert(is.list(inputs), "inputs must be a list.")
  cat <- .wb_op_catalog()
  op <- cat[[op_name]] %||% list()
  params <- op$params %||% list()
  if (!length(params)) return(invisible(TRUE))

  for (p in params) {
    nm <- as.character(p$name %||% "")[1]
    tp <- as.character(p$type %||% "")[1]
    if (!nzchar(nm) || !nzchar(tp)) next
    if (is.null(inputs[[nm]])) next
    val <- inputs[[nm]]

    if (identical(tp, "cell_ids_or_set")) {
      .wb_validate_cell_ids_or_set(val, nm)
      next
    }
    if (identical(tp, "int")) {
      .wb_assert(length(val) == 1 && !is.na(suppressWarnings(as.integer(val))),
                 paste0("inputs$", nm, " must be scalar int-like."))
      next
    }
    if (identical(tp, "dbl")) {
      .wb_assert(length(val) == 1 && !is.na(suppressWarnings(as.numeric(val))),
                 paste0("inputs$", nm, " must be scalar numeric-like."))
      next
    }
    if (identical(tp, "bool")) {
      b <- suppressWarnings(as.logical(val))
      .wb_assert(length(b) == 1 && !is.na(b),
                 paste0("inputs$", nm, " must be scalar logical-like."))
      next
    }
    if (identical(tp, "string")) {
      .wb_assert(length(val) == 1 && is.character(val),
                 paste0("inputs$", nm, " must be scalar character."))
      next
    }
    if (identical(tp, "string_vec")) {
      .wb_assert(is.character(val), paste0("inputs$", nm, " must be character vector."))
      next
    }
    if (identical(tp, "string_vec_or_list")) {
      ok <- is.character(val) || (is.list(val) && all(vapply(val, is.character, logical(1))))
      .wb_assert(ok, paste0("inputs$", nm, " must be character vector or list of character vectors."))
      next
    }
  }
  invisible(TRUE)
}
