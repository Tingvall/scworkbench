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
#' @param outputs Optional terminal output names to expose as public artifacts.
#'   Required ancestors are committed as internal provenance materializations.
#' @return The result of wb_promote_analysis(): list(artifact_pool=..., promoted=...)
#' @export
wb_session_promote_current <- function(bundle,
                                       session,
                                       name_prefix = NULL,
                                       description = NULL,
                                       created_by = NULL,
                                       fail_fast = TRUE,
                                       outputs = NULL) {
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
    } else {
      stop(
        "wb_session_promote_current(): head run has multiple promotable outputs. Supply outputs= explicitly. Available: ",
        paste(choices, collapse = ", "), call. = FALSE
      )
    }
  }

  output_heads <- character(0)
  for (out_name in as.character(outputs)) {
    candidates <- vapply(session$runs, function(run) {
      out_name %in% names(run$outputs %||% list()) &&
        out_name %in% as.character(.wb_get_op(run$op_name)$promotable %||% character(0))
    }, logical(1))
    ids <- names(session$runs)[candidates]
    .wb_assert(length(ids) == 1L,
               paste0("Output '", out_name, "' must resolve to exactly one promotable session run; found ", length(ids), "."))
    output_heads <- c(output_heads, ids)
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
    outputs = outputs,
    staging_bundle = session$staging_bundle %||% NULL
  )
}
