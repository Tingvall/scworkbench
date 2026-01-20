# R/session_context.R
# Minimal session DAG + auto-wiring by *typed inputs* (NOT "previous run").
#
# Goal:
# - Clients (Shiny/Streamlit/agents) keep ONE session object
# - Running ops creates wb_run nodes automatically
# - Parents are inferred ONLY when an op actually consumes outputs from prior runs/artifacts
# - "Active outputs" act like a context (labels, trajectory, scores, ...)
#
# Assumptions:
# - You already have:
#     wb_new_run(), wb_is_run()
#     wb_promote_analysis() / wb_promote_run()
#     wb_art_get_labels() (returns cell_id,label) for persisted labels
# - Ops exist with names: wb_op_leiden(), wb_op_slingshot(), wb_op_meanexpr() (later)
#
# You can extend registry entries as new ops arrive.

`%||%` <- function(x, y) if (is.null(x)) y else x


# ---- Op registry: define REQUIRED input TYPES and PRODUCED output TYPES ----
# This is what enables auto-wiring without "previous run" nonsense.
.wb_session_op_registry <- function() {
  list(
    leiden = list(requires = c("space"), produces = c("labels")),
    slingshot = list(requires = c("space", "labels"), produces = c("trajectory")),
    meanexpr = list(requires = c("matrix", "features"), produces = c("scores")),
    umap_fit = list(
      requires = c("space"),
      produces = c("space_2d", "model")  # names are up to you, but must exist
    )
  )
}

.wb_session_op_spec <- function(op_name) {
  reg <- .wb_session_op_registry()
  .wb_assert(op_name %in% names(reg), paste0("Unknown op: ", op_name))
  reg[[op_name]]
}


.wb_op_spec <- function(op_name) {
  reg <- .wb_op_registry()
  .wb_assert(op_name %in% names(reg), paste0("Unknown op: ", op_name))
  reg[[op_name]]
}

# ---- Session object ----
wb_session_new <- function(space_id = NULL, matrix_id = NULL) {
  s <- list(
    runs = list(),  # named by run_id
    active = list(
      space_id = space_id,
      matrix_id = matrix_id,
      outputs = list()  # typed: labels/trajectory/scores/... each is a ref
    ),
    head_run_id = NULL
  )
  class(s) <- "wb_session"
  s
}

wb_is_session <- function(x) inherits(x, "wb_session")

# A typed output reference: where to fetch an input from (run output or artifact id)
wb_ref_run_output <- function(run_id, output_type) {
  list(ref_type = "run", run_id = run_id, output_type = output_type)
}
wb_ref_artifact <- function(artifact_id, output_type) {
  list(ref_type = "artifact", artifact_id = artifact_id, output_type = output_type)
}

wb_session_add_run <- function(session, run) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(wb_is_run(run), "run must be a wb_run.")
  session$runs[[run$run_id]] <- run
  session$head_run_id <- run$run_id
  session
}

wb_session_set_active_space <- function(session, space_id) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  session$active$space_id <- as.character(space_id)
  session
}

wb_session_set_active_matrix <- function(session, matrix_id) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  session$active$matrix_id <- as.character(matrix_id)
  session
}

wb_session_set_active_output <- function(session, output_type, ref) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(is.list(ref) && !is.null(ref$ref_type), "ref must be a ref object from wb_ref_*.")
  session$active$outputs[[output_type]] <- ref
  session
}

# ---- Resolve typed inputs from session active outputs ----
.wb_get_run <- function(session, run_id) {
  r <- session$runs[[run_id]]
  .wb_assert(!is.null(r), paste0("Run not found in session: ", run_id))
  r
}

.wb_resolve_labels_df <- function(bundle, session, labels = NULL) {
  # If labels explicitly provided, treat as external input (no parent run edge).
  if (!is.null(labels)) return(list(value = labels, parents = character(0)))

  ref <- session$active$outputs$labels
  .wb_assert(!is.null(ref), "No labels provided and no active labels in session.")

  if (identical(ref$ref_type, "run")) {
    run <- .wb_get_run(session, ref$run_id)
    lab <- run$outputs$labels
    .wb_assert(is.data.frame(lab) && all(c("cell_id","cluster") %in% colnames(lab)),
               "Active labels run does not contain outputs$labels as data.frame(cell_id, cluster).")
    return(list(value = lab, parents = run$run_id))
  }

  if (identical(ref$ref_type, "artifact")) {
    # artifact returns cell_id,label -> convert to cell_id,cluster
    lab <- wb_art_get_labels(bundle, ref$artifact_id)
    .wb_assert(is.data.frame(lab) && all(c("cell_id","label") %in% colnames(lab)),
               "wb_art_get_labels() must return data.frame(cell_id, label).")
    lab2 <- data.frame(cell_id = lab$cell_id, cluster = as.character(lab$label), stringsAsFactors = FALSE)
    return(list(value = lab2, parents = character(0)))
  }

  stop("Unknown labels ref_type: ", ref$ref_type, call. = FALSE)
}

# ---- Main runner: auto-wire parents + compute effective cells (Issue #3) ----
# For each required input type:
# - if it is satisfied by an active run-output ref, add that run_id as a parent
# - if satisfied by an artifact or explicit argument, no run parent edge
# Additionally:
# - compute "effective_cells" = requested cell_set ∩ coverage(required inputs)
# - pass effective_cells into the op runner (single enforcement point)
wb_session_run_op <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  spec <- .wb_session_op_spec(op_name)

  # Start building resolved inputs + parents list
  parents <- character(0)

  # Resolve bundle-entity inputs (space, matrix) from explicit inputs or active context
  space_id  <- inputs[["space_id"]]  %||% session$active$space_id
  matrix_id <- inputs[["matrix_id"]] %||% session$active$matrix_id


  if ("space" %in% spec$requires) {
    .wb_assert(!is.null(space_id) && nzchar(space_id),
               paste0(op_name, " requires a space_id (set session active space or pass inputs$space_id)."))
  }
  if ("matrix" %in% spec$requires) {
    .wb_assert(!is.null(matrix_id) && nzchar(matrix_id),
               paste0(op_name, " requires a matrix_id (set session active matrix or pass inputs$matrix_id)."))
  }

  # Resolve typed run/artifact inputs
  labels_df <- NULL
  if ("labels" %in% spec$requires) {
    rr <- .wb_resolve_labels_df(bundle, session, labels = inputs$labels %||% NULL)
    labels_df <- rr$value
    parents <- unique(c(parents, rr$parents))
  }

  # ---- Effective cell set (Issue #3) ----
  # requested cell_set can be:
  # - "all" (default)
  # - "core"
  # - "set:<name>"
  cell_set <- inputs[["cell_set"]] %||% "all"

  # Build required input coverage request (only what the op needs)
  cov_inputs <- list()

  # dims are an op param, but coverage needs to know it for ND spaces
  # (e.g. leiden dims=2:30). We look for dims in inputs first, then ...
  # then in ... via match.call for safety; simplest is to expect inputs$dims
  dims_req <- inputs[["dims"]] %||% NULL

  if ("space" %in% spec$requires) {
    cov_inputs$space_id <- space_id
    if (!is.null(dims_req)) cov_inputs$dims <- dims_req
  }
  if ("matrix" %in% spec$requires) {
    cov_inputs$matrix_id <- matrix_id
  }
  # labels do not affect "has input" coverage (they are just a vector mapping),
  # so we don't include them here.

  # Compute effective cells only when we have something to constrain by.
  # Still safe to compute for empty cov_inputs (returns wb_cells(cell_set)).
  effective_cells <- .wb_effective_cells(
    bundle   = bundle,
    cell_set = cell_set,
    inputs   = cov_inputs,
    op_name  = op_name,
    min_cells = inputs$min_cells %||% 10
  )

  # ---- Dispatch op via registry ----
  runner <- .wb_get_op_runner(op_name)

  # Ensure RNG exists (some ops rely on it)
  if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    set.seed(1)
  }

  # IMPORTANT: pass effective_cells into the op runner.
  # Ops should trust and use ONLY these cells for any data access.
  res <- runner(
    bundle = bundle,
    space_id = space_id,
    matrix_id = matrix_id,
    labels_df = labels_df,
    effective_cells = effective_cells,
    inputs = inputs,
    ...
  )

  # Wrap outputs into a run object with parents (DAG edge correctness!)
  outputs <- list()

  if ("labels" %in% spec$produces) {
    .wb_assert(!is.null(res$labels), "Op produced 'labels' but res$labels is NULL.")
    outputs$labels <- res$labels
  }

  if ("trajectory" %in% spec$produces) {
    # accept either res$trajectory or res$pseudotime + res$curves
    if (!is.null(res$trajectory)) {
      .wb_assert(is.list(res$trajectory), "res$trajectory must be a list.")
      .wb_assert(!is.null(res$trajectory$pseudotime) && !is.null(res$trajectory$curves),
                 "res$trajectory must contain pseudotime and curves.")
      outputs$pseudotime <- res$trajectory$pseudotime
      outputs$curves     <- res$trajectory$curves
    } else {
      .wb_assert(!is.null(res$pseudotime) && !is.null(res$curves),
                 "slingshot op must return res$pseudotime and res$curves (or res$trajectory).")
      outputs$pseudotime <- res$pseudotime
      outputs$curves     <- res$curves
    }
    outputs$trajectory <- TRUE
  }

  if ("scores" %in% spec$produces) {
    .wb_assert(!is.null(res$scores), "Op produced 'scores' but res$scores is NULL.")
    outputs$scores <- res$scores
  }

  # Build run inputs metadata (for provenance)
  run_inputs <- list(
    space_id = if ("space" %in% spec$requires) space_id else NULL,
    matrix_id = if ("matrix" %in% spec$requires) matrix_id else NULL,
    cell_set = cell_set,
    effective_n = length(effective_cells),
    parents = parents
  )

  run <- wb_new_run(
    op_name = op_name,
    inputs = run_inputs,
    params = res$params %||% list(),
    outputs = outputs,
    notes = notes
  )

  # Update session
  session <- wb_session_add_run(session, run)

  # Update active outputs produced by this run
  if ("labels" %in% spec$produces) {
    session <- wb_session_set_active_output(session, "labels", wb_ref_run_output(run$run_id, "labels"))
  }
  if ("trajectory" %in% spec$produces) {
    session <- wb_session_set_active_output(session, "trajectory", wb_ref_run_output(run$run_id, "trajectory"))
  }
  if ("scores" %in% spec$produces) {
    session <- wb_session_set_active_output(session, "scores", wb_ref_run_output(run$run_id, "scores"))
  }

  list(session = session, run = run, result = res)
}

