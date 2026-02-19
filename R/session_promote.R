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
#' @return The result of wb_promote_analysis(): list(artifact_pool=..., promoted=...)
#' @export
wb_session_promote_current <- function(bundle,
                                       session,
                                       name_prefix = NULL,
                                       description = NULL,
                                       created_by = NULL,
                                       fail_fast = TRUE) {
  .wb_assert(wb_is_session(session), "session must be a wb_session.")
  .wb_assert(!is.null(session$head_run_id) && nzchar(session$head_run_id),
             "session$head_run_id is NULL/empty. Run at least one op before promoting.")
  .wb_assert(is.list(session$runs) && length(session$runs) > 0,
             "session$runs is empty. Nothing to promote.")
  .wb_assert(session$head_run_id %in% names(session$runs),
             "session$head_run_id not found in session$runs. Session may be corrupted.")

  wb_promote_analysis(
    bundle = bundle,
    runs = session$runs,
    head_run_id = session$head_run_id,
    name_prefix = name_prefix,
    description = description,
    created_by = created_by,
    fail_fast = fail_fast
  )
}
