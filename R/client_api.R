#' Client Facade: Discover Bundle and Runtime Capabilities
#'
#' Thin, client-agnostic discovery surface for Shiny, web/mobile, Python, and agents.
#' This function only composes existing `wb_*` APIs and does not introduce new logic.
#'
#' @param bundle scworkbench bundle handle.
#' @param session Optional wb_session to include session-scoped runtime outputs.
#' @param include_op_interfaces If TRUE, include full per-op interface specs.
#' @param include_vectors If TRUE, include vector sources.
#' @param include_feature_sets If TRUE, include bundle-level feature sets.
#' @return Named list with discoverable registries and capabilities.
#' @export
wb_client_discover <- function(bundle,
                               session = NULL,
                               include_op_interfaces = TRUE,
                               include_vectors = TRUE,
                               include_feature_sets = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  out <- list(
    manifest = wb_manifest(bundle),
    status = .wb_client_status(bundle),
    datasets = wb_list(bundle, "datasets"),
    spaces = wb_spaces(bundle),
    matrices = wb_matrices(bundle),
    cell_sets = wb_cell_sets(bundle),
    ops = wb_ops(),
    mutation_capabilities = list(
      scientific_state_boundary = "provenance_only",
      operation_execution = "wb_client_run -> wb_session_run_op",
      durable_commit = "wb_client_promote -> wb_session_promote_current",
      declared_ingestion = c(
        "wb_bundle_from_10x_mtx", "wb_bundle_from_h5ad", "wb_bundle_from_sce",
        "wb_bundle_from_seurat", "wb_ingest_apply", "wb_attach_apply"
      ),
      direct_mutating_implementation_calls = FALSE,
      catalog = "wb_mutation_catalog_semantic"
    )
  )

  if (isTRUE(include_op_interfaces)) {
    op_names <- wb_list_ops()
    out$op_interfaces <- setNames(
      lapply(op_names, function(op_name) wb_op_interface(op_name, bundle = bundle)),
      op_names
    )
  }

  if (isTRUE(include_vectors)) {
    runs <- session$runs %||% NULL
    out$vector_sources <- wb_list_vector_sources(bundle, runs = runs)
    out$cell_vectors <- wb_list_cell_vectors(bundle, session = session, include_session = !is.null(session))
  }

  if (isTRUE(include_feature_sets)) {
    out$feature_sets <- wb_feature_sets(bundle)
  }

  out
}

#' Client Facade: Execute a Selection Plan
#'
#' @param bundle scworkbench bundle handle.
#' @param plan Selection plan consumed by `wb_exec_selection_plan()`.
#' @param session Optional wb_session; used to resolve session vector refs.
#' @param runs Optional run list; overrides `session$runs` when provided.
#' @return Ordered character vector of selected cell IDs.
#' @export
wb_client_select <- function(bundle, plan, session = NULL, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  rr <- runs %||% (session$runs %||% NULL)
  wb_exec_selection_plan(bundle = bundle, plan = plan, runs = rr)
}

#' Client Facade: Run an Operation
#'
#' Thin wrapper over `wb_session_run_op()` for client code.
#'
#' @param session wb_session object.
#' @param bundle scworkbench bundle handle.
#' @param op_name Operation name.
#' @param ... Must be empty. Supply all operation inputs and parameters through
#'   `inputs`.
#' @param inputs Named list of op inputs.
#' @param notes Optional run notes.
#' @return List with `session`, `run`, and `result` from `wb_session_run_op()`.
#' @export
wb_client_run <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) {
  dots <- list(...)
  .wb_assert(
    length(dots) == 0L,
    "wb_client_run(): operation inputs and parameters must be supplied in inputs."
  )
  wb_session_run_op(
    session = session,
    bundle = bundle,
    op_name = op_name,
    inputs = inputs,
    notes = notes
  )
}

#' Client Facade: Inspect Session and Bundle Runtime State
#'
#' Thin inspection wrapper that exposes bundle status, active session state,
#' and optionally one run view without adding new engine semantics.
#'
#' @param bundle scworkbench bundle handle.
#' @param session Optional wb_session.
#' @param run_id Optional run_id to inspect.
#' @param include_run_outputs If TRUE and `run_id` is provided, include full output objects.
#' @return Named list with status, active refs, and optional run details.
#' @export
wb_client_inspect <- function(bundle, session = NULL, run_id = NULL, include_run_outputs = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  out <- list(
    status = .wb_client_status(bundle),
    session_present = !is.null(session),
    session_head_run_id = NULL,
    session_active = list()
  )

  if (!is.null(session)) {
    .wb_assert(wb_is_session(session), "session must be wb_session when provided")
    out$session_head_run_id <- session$head_run_id %||% NULL
    out$session_active <- session$active %||% list()
  }

  if (!is.null(run_id)) {
    .wb_assert(!is.null(session), "run_id inspection requires session")
    rid <- as.character(run_id)[1]
    run <- session$runs[[rid]]
    .wb_assert(!is.null(run) && wb_is_run(run), paste0("run not found in session: ", rid))

    run_view <- list(
      run_id = run$run_id,
      op_name = run$op_name,
      created_at = run$created_at,
      inputs = run$inputs,
      params = run$params,
      output_names = names(run$outputs %||% list())
    )
    if (isTRUE(include_run_outputs)) {
      run_view$outputs <- run$outputs
    }
    out$run <- run_view
  }

  out
}

#' Client Facade: Promote Current Session Analysis
#'
#' Thin wrapper over [wb_session_promote_current()] for client code.
#'
#' @inheritParams wb_session_promote_current
#' @return Result from `wb_session_promote_current()`.
#' @export
wb_client_promote <- function(bundle,
                              session,
                              name_prefix = NULL,
                              description = NULL,
                              created_by = NULL,
                              fail_fast = TRUE,
                              outputs = NULL) {
  wb_session_promote_current(
    bundle = bundle,
    session = session,
    name_prefix = name_prefix,
    description = description,
    created_by = created_by,
    fail_fast = fail_fast,
    outputs = outputs
  )
}

#' Client Facade: Load Primitive by Reference
#'
#' Accepts a primitive, artifact id, resolve-spec list, run ref, or artifact
#' ref, and routes all resolution through [wb_resolve_primitive()].
#'
#' @param bundle scworkbench bundle handle.
#' @param ref Primitive-like reference.
#' @param session Optional wb_session for run refs.
#' @param runs Optional runs list; overrides `session$runs` when provided.
#' @param expected_kind Optional primitive kind to enforce.
#' @return wb_primitive (or NULL if ref resolves to none).
#' @export
wb_client_load <- function(bundle, ref, session = NULL, runs = NULL, expected_kind = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  rr <- runs %||% (session$runs %||% NULL)

  if (is.list(ref) && identical(ref$ref_type %||% "", "artifact")) {
    return(wb_resolve_primitive(
      bundle = bundle,
      spec = list(type = "artifact", value = as.character(ref$artifact_id)),
      runs = rr,
      expected_kind = expected_kind
    ))
  }

  if (is.list(ref) && identical(ref$ref_type %||% "", "run")) {
    return(wb_resolve_primitive(
      bundle = bundle,
      spec = list(
        type = "session",
        value = list(
          run_id = as.character(ref$run_id),
          output = as.character(ref$output)
        )
      ),
      runs = rr,
      expected_kind = expected_kind
    ))
  }

  wb_resolve_primitive(
    bundle = bundle,
    spec = ref,
    runs = rr,
    expected_kind = expected_kind
  )
}

.wb_client_status <- function(bundle) {
  tabs <- DBI::dbListTables(bundle$con)
  list(
    bundle_dir = bundle$dir %||% NA_character_,
    table_count = length(tabs),
    tables = tabs
  )
}
