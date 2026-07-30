# R/session_promote.R
# One-liner "Save analysis" for clients: promote the current head run DAG.
#
# Requires:
# - session_context.R session object with fields:
#     session$runs (named list of wb_run)
#     session$head_run_id (current head run_id)
# - wb_promote_analysis() (promotes DAG from head)
#
# Export:
# - wb_session_promote_current

#' Promote the current analysis in a session
#'
#' Promotes all saveable outputs reachable from the session head run id, in dependency order.
#' This is the UI/agent-friendly "Save analysis" entry point.
#'
#' @param bundle Bundle handle
#' @param session wb_session created by wb_session_new() / updated by wb_session_run_op()
#' @param name_prefix Optional prefix for generated artifact names
#' @param description Optional description stored with promoted artifacts
#' @param created_by Optional actor string (user/agent)
#' @param fail_fast If TRUE, stop on first promotion failure
#' @param outputs Optional terminal output names or [wb_ref_run()] selectors to
#'   expose as public artifacts. A run-qualified selector chooses that exact
#'   terminal on that exact session run, which is required when runs share an
#'   output name such as `fit_summary`.
#'   Required ancestors are committed as internal provenance materializations.
#'   When an output name occurs in multiple session runs, the active head run is
#'   selected when it provides that output; otherwise the name must resolve
#'   uniquely within the session.
#' @return The result of wb_promote_analysis(): list(artifact_pool=..., promoted=...)
#'
#' @section Long-running operation safety:
#' Promote expensive staged results immediately after [wb_session_run_op()] and
#' retaining `session <- result$session`. The returned `result$run` is a
#' structured `wb_run`, not a tabular object to coerce or serialize. Select
#' terminal `outputs=` using [wb_op_interface()] and emit reports, exports,
#' plots, identity cards, and diagnostics only after this call succeeds. See
#' the shipped `inst/onboarding/PLAYBOOK.md` for a minimal safe workflow.
#' @export
wb_session_promote_current <- function(bundle,
                                       session,
                                       name_prefix = NULL,
                                       description = NULL,
                                       created_by = NULL,
                                       fail_fast = TRUE,
                                       outputs = NULL) {
  .wb_assert_bundle_writable(bundle, "promotion")
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(!is.null(session$head_run_id) && nzchar(session$head_run_id),
             "session$head_run_id is NULL/empty. Run at least one op before promoting.")
  .wb_assert(is.list(session$runs) && length(session$runs) > 0,
             "session$runs is empty. Nothing to promote.")
  .wb_assert(session$head_run_id %in% names(session$runs),
             "session$head_run_id not found in session$runs. Session may be corrupted.")

  if (is.null(outputs)) {
    head <- session$runs[[session$head_run_id]]
    choices <- intersect(
      as.character(.wb_get_op(head$op_name)$promotable %||% character(0)),
      names(head$outputs %||% list())
    )
    if (length(choices) == 1L) {
      outputs <- choices
    } else if (!length(choices)) {
      stop("wb_session_promote_current(): head run has zero promotable terminal outputs; no durable output can be committed.", call.=FALSE)
    } else {
      stop(
        "wb_session_promote_current(): head run has multiple promotable outputs. Supply outputs= explicitly. Available: ",
        paste(choices, collapse = ", "), call. = FALSE
      )
    }
  }

  selectors <- if (is.character(outputs)) as.list(outputs) else outputs
  .wb_assert(is.list(selectors), "outputs must be character output names or a list of wb_ref_run() selectors.")
  output_heads <- character(0)
  selected_by_run <- list()
  head <- session$runs[[session$head_run_id]]
  for (selector in selectors) {
    if (.wb_is_ref_run(selector)) {
      rid <- as.character(selector$run_id)[1]
      out_name <- as.character(selector$output)[1]
      .wb_assert(rid %in% names(session$runs), paste0("Run-qualified selector references absent session run: ", rid, "."))
      run <- session$runs[[rid]]
      .wb_assert(out_name %in% names(run$outputs %||% list()), paste0("Run-qualified selector output '", out_name, "' is absent from run ", rid, "."))
      .wb_assert(out_name %in% as.character(.wb_get_op(run$op_name)$promotable %||% character(0)), paste0("Run-qualified selector output '", out_name, "' on run ", rid, " is not promotable."))
      output_heads <- c(output_heads, rid)
      selected_by_run[[rid]] <- unique(c(selected_by_run[[rid]] %||% character(0), out_name))
      next
    }
    .wb_assert(is.character(selector) && length(selector) == 1L, "Each outputs selector must be a plain output name or wb_ref_run().")
    out_name <- as.character(selector)[1]
    # Prefer the active head when it produces the requested output. Output
    # names are op-level names, so earlier independent fits can legitimately
    # have another `pseudotime` or `model` output in the same session.
    if (out_name %in% names(head$outputs %||% list()) &&
        out_name %in% as.character(.wb_get_op(head$op_name)$promotable %||% character(0))) {
      output_heads <- c(output_heads, session$head_run_id)
      selected_by_run[[session$head_run_id]] <- unique(c(selected_by_run[[session$head_run_id]] %||% character(0), out_name))
      next
    }
    candidates <- vapply(session$runs, function(run) {
      out_name %in% names(run$outputs %||% list()) &&
        out_name %in% as.character(.wb_get_op(run$op_name)$promotable %||% character(0))
    }, logical(1))
    ids <- names(session$runs)[candidates]
    if (!length(ids)) {
      materialized <- vapply(session$runs, function(run) out_name %in% names(run$outputs %||% list()), logical(1))
      mids <- names(session$runs)[materialized]
      if (length(mids)) {
        run <- session$runs[[mids[1]]]
        terminals <- intersect(as.character(.wb_get_op(run$op_name)$promotable %||% character(0)), names(run$outputs %||% list()))
        stop(paste0("Output '", out_name, "' is a durability_role=materialization, not a terminal artifact. It is materialized when promoting terminal output(s): ", paste(terminals, collapse=", "), ". Request one or more of those terminal outputs."), call.=FALSE)
      }
    }
    .wb_assert(length(ids) == 1L,
               paste0("Output '", out_name, "' must resolve to exactly one promotable session run; found ", length(ids), "."))
    output_heads <- c(output_heads, ids)
    selected_by_run[[ids]] <- unique(c(selected_by_run[[ids]] %||% character(0), out_name))
  }
  output_heads <- unique(output_heads)

  wb_promote_analysis(
    bundle = bundle,
    runs = session$runs,
    head_run_id = output_heads,
    name_prefix = name_prefix,
    description = description,
    created_by = created_by,
    fail_fast = fail_fast,
    outputs = unique(unlist(selected_by_run, use.names = FALSE)),
    selected_by_run = selected_by_run,
    staging_bundle = session$staging_bundle %||% NULL
  )
}
