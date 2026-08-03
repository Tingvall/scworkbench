# Provenance-only mutation boundary.
#
# Durable writers are callable from many engine modules, but authority to use
# them is deliberately not represented by a caller-supplied flag or option.
# The capability token and active context stack live in this package-private
# environment and are matched to the exact DBI connection being mutated.

.wb_mutation_boundary_state <- local({
  state <- new.env(parent = emptyenv())
  state$capability <- new.env(parent = emptyenv())
  state$contexts <- list()
  state$assembly_connections <- list()
  state
})

.wb_connection_matches <- function(x, y) {
  isTRUE(identical(x, y))
}

.wb_register_assembly_bundle <- function(bundle, writer_lock) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(inherits(writer_lock, "scworkbench_writer_lock"),
             "active bundle assembly requires an exclusive writer lock")
  .wb_mutation_boundary_state$assembly_connections <- c(
    .wb_mutation_boundary_state$assembly_connections,
    list(list(
      con = bundle$con,
      dir = normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
      writer_lock = writer_lock,
      capability = .wb_mutation_boundary_state$capability
    ))
  )
  invisible(bundle)
}

.wb_unregister_assembly_connection <- function(con) {
  entries <- .wb_mutation_boundary_state$assembly_connections
  if (length(entries)) {
    removed <- entries[vapply(entries, function(x) .wb_connection_matches(x$con, con), logical(1))]
    keep <- !vapply(entries, function(x) .wb_connection_matches(x$con, con), logical(1))
    .wb_mutation_boundary_state$assembly_connections <- entries[keep]
    if (length(removed)) {
      for (entry in removed) .wb_bundle_writer_lock_release(entry$writer_lock)
    }
  }
  invisible(TRUE)
}

.wb_is_assembly_connection <- function(con) {
  entries <- .wb_mutation_boundary_state$assembly_connections
  length(entries) > 0L && any(vapply(entries, function(x) {
    identical(x$capability, .wb_mutation_boundary_state$capability) &&
      .wb_connection_matches(x$con, con)
  }, logical(1)))
}

.wb_assembly_connection_dir <- function(con) {
  entries <- .wb_mutation_boundary_state$assembly_connections
  if (!length(entries)) return(NULL)
  hit <- Filter(function(x) .wb_connection_matches(x$con, con), entries)
  if (!length(hit)) NULL else as.character(hit[[length(hit)]]$dir)[1]
}

.wb_with_mutation_context <- function(bundle = NULL,
                                      con = bundle$con,
                                      route,
                                      run_id = NULL,
                                      op_name = NULL,
                                      staging_bundle = NULL,
                                      code) {
  .wb_assert(!is.null(con), "mutation context requires a bundle connection")
  route <- match.arg(route, c("session_execution", "promotion", "ingestion"))
  if (identical(route, "session_execution")) {
    .wb_assert(
      !is.null(bundle) && inherits(bundle, "scworkbench_bundle") &&
        nzchar(as.character(bundle$staging_source_dir %||% "")[1]),
      paste0(route, " mutation authority is available only on an engine-created staging bundle.")
    )
  }
  if (identical(route, "promotion")) {
    .wb_assert(
      !is.null(bundle) && inherits(bundle, "scworkbench_bundle") &&
        !is.null(staging_bundle) && inherits(staging_bundle, "scworkbench_bundle") &&
        nzchar(as.character(staging_bundle$staging_source_dir %||% "")[1]) &&
        identical(
          normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
          normalizePath(staging_bundle$staging_source_dir, winslash = "/", mustWork = TRUE)
        ),
      "promotion mutation authority requires an engine-created staging bundle bound to the destination bundle."
    )
  }
  lock_target <- if (!is.null(bundle) && inherits(bundle, "scworkbench_bundle")) {
    bundle$dir
  } else {
    .wb_writer_lock_target_from_connection(con)
  }
  run_in_context <- function() {
    old <- .wb_mutation_boundary_state$contexts
    .wb_mutation_boundary_state$contexts <- c(old, list(list(
      capability = .wb_mutation_boundary_state$capability,
      con = con,
      dir = if (!is.null(bundle) && inherits(bundle, "scworkbench_bundle")) {
        normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
      } else normalizePath(lock_target, winslash = "/", mustWork = TRUE),
      route = route,
      run_id = as.character(run_id %||% "")[1],
      op_name = as.character(op_name %||% "")[1]
    )))
    on.exit({ .wb_mutation_boundary_state$contexts <- old }, add = TRUE)
    force(code)
  }
  .wb_with_bundle_writer_lock(
    lock_target,
    operation = paste0("mutation route: ", route),
    code = run_in_context()
  )
}

.wb_current_mutation_context <- function(con, bundle_dir = NULL) {
  contexts <- rev(.wb_mutation_boundary_state$contexts)
  if (!length(contexts)) return(NULL)
  for (ctx in contexts) {
    path_match <- !is.null(bundle_dir) && nzchar(as.character(ctx$dir %||% "")[1]) &&
      identical(
        as.character(ctx$dir)[1],
        normalizePath(bundle_dir, winslash = "/", mustWork = TRUE)
      )
    if (identical(ctx$capability, .wb_mutation_boundary_state$capability) &&
        (.wb_connection_matches(ctx$con, con) || path_match)) return(ctx)
  }
  NULL
}

.wb_assert_mutation_context <- function(bundle = NULL,
                                        con = bundle$con,
                                        action = "durable mutation",
                                        allowed = c("assembly", "session_execution", "promotion", "ingestion"),
                                        replacement = "wb_session_run_op() followed by wb_session_promote_current()") {
  if (!is.null(bundle)) .wb_assert_bundle_writable(bundle, action)
  .wb_assert(!is.null(con), paste0(action, " requires a bundle connection."))

  ctx <- .wb_current_mutation_context(
    con, bundle_dir = if (!is.null(bundle)) bundle$dir else NULL
  )
  if (!is.null(ctx) && ctx$route %in% allowed) {
    .wb_assert(
      nzchar(as.character(ctx$dir %||% "")[1]) && .wb_writer_lock_held(ctx$dir),
      paste0(action, " requires the exclusive bundle-writer lock before any SQLite transaction.")
    )
    return(invisible(ctx$route))
  }
  if ("assembly" %in% allowed && .wb_is_assembly_connection(con)) {
    assembly_dir <- .wb_assembly_connection_dir(con)
    .wb_assert(!is.null(assembly_dir) && .wb_writer_lock_held(assembly_dir),
               paste0(action, " requires the active assembly writer lock."))
    return(invisible("assembly"))
  }

  stop(
    action, " cannot write directly to a committed bundle. Use ", replacement,
    "; low-level writers are restricted to engine-bound staging, promotion, or declared ingestion transactions.",
    call. = FALSE
  )
}

.wb_assert_operation_execution <- function(bundle, op_name) {
  .wb_assert_mutation_context(
    bundle = bundle,
    action = paste0("Operation implementation '", op_name, "'"),
    allowed = "session_execution",
    replacement = paste0("wb_session_run_op(session, bundle, '", op_name,
                         "', inputs = ...) followed by wb_session_promote_current()")
  )
}

.wb_registry_mutation_context <- function(bundle) {
  ctx <- .wb_current_mutation_context(bundle$con)
  if (is.null(ctx) || !identical(ctx$route, "session_execution") ||
      !nzchar(as.character(ctx$run_id %||% "")[1])) return(NULL)
  ctx
}

.wb_record_declared_ingestion <- function(bundle,
                                          transaction_name,
                                          matrix_ids = character(0),
                                          space_ids = character(0),
                                          source = "ingestion",
                                          created_by = NULL,
                                          source_identity = NULL,
                                          additional_outputs = list(),
                                          transaction_open = FALSE) {
  matrix_ids <- unique(as.character(matrix_ids %||% character(0)))
  matrix_ids <- matrix_ids[nzchar(matrix_ids)]
  space_ids <- unique(as.character(space_ids %||% character(0)))
  space_ids <- space_ids[nzchar(space_ids)]
  outputs <- if (length(space_ids)) {
    stats::setNames(lapply(space_ids, wb_prim_space), paste0("space_", space_ids))
  } else list()
  outputs <- c(outputs, additional_outputs %||% list())
  run <- wb_new_run(
    op_name = as.character(transaction_name)[1],
    inputs = list(
      cell_set = "all", parents = character(0), provenance_refs = list(),
      user_inputs = list(source = as.character(source %||% "ingestion")[1])
    ),
    params = list(route = "declared_ingestion_transaction"),
    outputs = outputs,
    notes = "Declared provenance-producing ingestion transaction"
  )
  if (is.null(source_identity)) {
    source_identity <- list(
      source_type = as.character(source %||% "ingestion")[1],
      inputs = list(list(
        uri = paste0("scworkbench-ingestion://", as.character(transaction_name)[1]),
        role = "caller_supplied_payload",
        format = "in_memory"
      ))
    )
  }
  .wb_prov_record_ingestion(
    bundle = bundle, run = run, matrix_ids = matrix_ids,
    created_by = created_by, transaction_open = transaction_open,
    source_identity = source_identity
  )
}
