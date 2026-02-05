# R/session_context.R
# scworkbench session: primitives-only DAG runner
#
# Contract:
# - Ops return: list(outputs = named list of primitive objects, params = list(...))
# - Session stores only primitives in run$outputs
# - Active context stores refs to primitives, keyed by output name (e.g. "clusters", "space_2d")
# - Dependencies ("parents") are inferred ONLY when a required input is satisfied by a run ref.

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------- Registry ----------
#### NEW REGISTRY!

.wb_ops <- function() {
  list(
    leiden = list(
      requires = list(space = "space"),
      produces = list(clusters = "cell_vector"),
      runner   = wb_op_leiden,
      promotable = c("clusters")
    ),

    slingshot = list(
      requires = list(space_2d = "space_2d", clusters = "cell_vector"),
      produces = list(
        pseudotime = "cell_vector_family",   # can be multiple vectors if lineage-specific
        curves     = "path_2d_family"
      ),
      runner   = wb_op_slingshot,
      promotable = c("pseudotime", "curves")
    ),

    umap_fit = list(
      requires = list(space = "space"),
      produces = list(space_2d = "space_2d", model = "model_ref"),
      runner   = wb_op_umap_fit,
      promotable = c("space_2d", "model") # optional
    ),

    umap_transform = list(
      requires = list(in_space = "space", model = "model_ref"),
      produces = list(space_2d = "space_2d"),
      runner   = wb_op_umap_transform,
      promotable = c("space_2d") # optional snapshot
    )
  )
}

.wb_op <- function(op_name) {
  reg <- .wb_ops()
  .wb_assert(op_name %in% names(reg), paste0("Unknown op: ", op_name))
  reg[[op_name]]
}

# ---------- Refs ----------
wb_ref_run <- function(run_id, output_name) {
  list(ref_type = "run", run_id = as.character(run_id), output = as.character(output_name))
}
wb_ref_artifact <- function(artifact_id, output_name) {
  list(ref_type = "artifact", artifact_id = as.character(artifact_id), output = as.character(output_name))
}

# ---------- Session object ----------
wb_session_new <- function() {
  s <- list(
    runs = list(),         # run_id -> wb_run
    active = list(),       # output_name -> ref
    head_run_id = NULL
  )
  class(s) <- "wb_session"
  s
}
wb_is_session <- function(x) inherits(x, "wb_session")

wb_session_set_active <- function(session, output_name, ref) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(is.list(ref) && !is.null(ref$ref_type), "ref must be a wb_ref_*")
  session$active[[as.character(output_name)]] <- ref
  session
}

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

# ---------- Primitive checks ----------
.wb_is_primitive <- function(x) {
  is.list(x) && !is.null(x$kind) && is.character(x$kind) && length(x$kind) == 1
}

.wb_assert_kind <- function(x, kind, where = "") {
  .wb_assert(.wb_is_primitive(x), paste0("Expected primitive object", where, "."))
  .wb_assert(identical(x$kind, kind),
             paste0("Expected kind='", kind, "'", where, " but got kind='", x$kind, "'."))
  invisible(TRUE)
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

  if (is.null(val)) {
    ref <- inputs[[paste0(name, "_ref")]] %||%
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
        val <- wb_art_load(bundle, artifact_id = ref$artifact_id, output = ref$output)
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
    if (expected_kind == "cell_vector" && is.atomic(val) && !is.null(names(val))) {
      val <- wb_prim_cell_vector(val, value_type = "categorical")
    }
  }

  .wb_assert_kind(val, expected_kind, where = paste0(" for input '", name, "'"))
  list(value = val, parents = parents, prov_refs = prov_refs)
}



# ---------- Run op ----------
# Op contract: op(bundle, effective_cells, inputs = list(...), ...) -> list(outputs=<named primitives>, params=<list>)
wb_session_run_op <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  op <- .wb_op(op_name)

  # Resolve effective_cells once, here. Nothing else is allowed to compute cells.
  cell_set <- inputs$cell_set %||% "all"
  effective_cells <- .wb_effective_cells(
    bundle = bundle,
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
      rr <- .wb_resolve_input(bundle, session, nm, kind, inputs)
      resolved[[nm]] <- rr$value
      parents <- unique(c(parents, rr$parents))
      prov_refs <- c(prov_refs, rr$prov_refs)
    }
  }

  runner <- .wb_get_op_runner(op_name)
  res <- runner(
    bundle = bundle,
    resolved = resolved,
    effective_cells = effective_cells,
    inputs = inputs,
    ...
  )
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
    user_inputs = inputs
  )

  run <- wb_new_run(
    op_name = op_name,
    inputs  = run_inputs,
    params  = res$params %||% list(),
    outputs = out,
    notes   = notes
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

