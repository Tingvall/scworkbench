# pybench bridge scaffolding (subprocess request/receipt protocol)

.wb_pybench_default_python <- function() {
  # 1) Explicit env var always wins (portable, deployment-friendly).
  env_py <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = "")
  if (nzchar(env_py)) return(env_py)

  # 2) R option override for session-level configuration.
  opt_py <- getOption("scworkbench.pybench.python", default = "")
  opt_py <- as.character(opt_py %||% "")[1]
  if (nzchar(opt_py)) return(opt_py)

  # 3) Common local dev locations (POSIX + Windows) relative to current wd.
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  cand <- c(
    file.path(wd, ".venv", "bin", "python"),
    file.path(wd, ".venv", "Scripts", "python.exe"),
    file.path(wd, "..", "pybench", ".venv", "bin", "python"),
    file.path(wd, "..", "pybench", ".venv", "Scripts", "python.exe"),
    file.path(wd, "..", "..", "pybench", ".venv", "bin", "python"),
    file.path(wd, "..", "..", "pybench", ".venv", "Scripts", "python.exe"),
    Sys.which("python3"),
    Sys.which("python")
  )
  cand <- unique(as.character(cand))
  cand <- cand[nzchar(cand)]
  for (p in cand) {
    if (file.exists(p)) return(p)
  }

  ""
}

.wb_pybench_run_module <- function(module,
                                   request,
                                   bundle = NULL,
                                   python_bin = .wb_pybench_default_python(),
                                   env = character(0),
                                   request_path = tempfile("pybench_req_", fileext = ".json"),
                                   receipt_path = tempfile("pybench_rec_", fileext = ".json"),
                                   isolated = TRUE,
                                   command_args = NULL,
                                   timeout_seconds = 0,
                                   prepare_transition = NULL,
                                   finalize_transition = NULL,
                                   validate_transition = NULL) {
  .wb_pyproto_validate_request(request)
  if (isTRUE(isolated)) {
    return(.wb_pybench_execute_isolated(
      module = module, request = request, bundle = bundle, python_bin = python_bin,
      env = env, request_path = request_path, receipt_path = receipt_path,
      command_args = command_args, timeout_seconds = timeout_seconds,
      prepare_transition = prepare_transition, finalize_transition = finalize_transition,
      validate_transition = validate_transition
    ))
  }
  if (is.null(command_args)) {
    .wb_pyproto_assert_scalar_chr(as.character(module %||% ""), "module")
  } else {
    .wb_assert(is.function(command_args), "PyBench command_args must be a function")
  }
  py <- as.character(python_bin %||% "")[1]
  if (!nzchar(py) || !file.exists(py)) {
    stop(
      paste0(
        "pybench python interpreter not found. ",
        "Set env var SCWORKBENCH_PYBENCH_PYTHON to your pybench venv python ",
        "(or set options(scworkbench.pybench.python=...)). ",
        "Current value: '", py, "'."
      ),
      call. = FALSE
    )
  }
  .wb_pyproto_assert_scalar_chr(py, "python_bin")

  on.exit(unlink(c(request_path, receipt_path), force = TRUE), add = TRUE)
  .wb_pyproto_write_request_json(request_path, request)

  cache_root <- file.path(tempdir(), "pybench_cache")
  if (!dir.exists(cache_root)) dir.create(cache_root, recursive = TRUE, showWarnings = FALSE)
  env_names <- sub("=.*$", "", as.character(env))
  env_extra <- character(0)
  if (!("NUMBA_CACHE_DIR" %in% env_names)) {
    numba_dir <- file.path(cache_root, "numba")
    if (!dir.exists(numba_dir)) dir.create(numba_dir, recursive = TRUE, showWarnings = FALSE)
    env_extra <- c(env_extra, paste0("NUMBA_CACHE_DIR=", numba_dir))
  }
  if (!("XDG_CACHE_HOME" %in% env_names)) {
    xdg_dir <- file.path(cache_root, "xdg")
    if (!dir.exists(xdg_dir)) dir.create(xdg_dir, recursive = TRUE, showWarnings = FALSE)
    env_extra <- c(env_extra, paste0("XDG_CACHE_HOME=", xdg_dir))
  }

  args <- if (is.null(command_args)) {
    c("-m", module, "--request", request_path, "--receipt", receipt_path)
  } else {
    as.character(command_args(request_path = request_path, receipt_path = receipt_path))
  }
  .wb_assert(length(args) > 0L && !anyNA(args), "PyBench command_args returned invalid arguments")
  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds)[1])
  .wb_assert(is.finite(timeout_seconds) && timeout_seconds >= 0,
             "PyBench timeout_seconds must be a finite non-negative number")
  env_values <- c(env_extra, env)
  env_split <- strsplit(env_values, "=", fixed = TRUE)
  env_named <- if (length(env_split)) stats::setNames(
    vapply(env_split, function(x) paste(x[-1L], collapse = "="), character(1)),
    vapply(env_split, function(x) x[[1L]], character(1))
  ) else character(0)
  process <- tryCatch(
    processx::run(
      py, args = args, env = c("current", env_named), echo = FALSE,
      error_on_status = FALSE,
      timeout = if (timeout_seconds > 0) timeout_seconds else Inf
    ),
    error = identity
  )
  if (inherits(process, "error")) {
    condition <- structure(list(
      message = paste0("PyBench subprocess failed: ", conditionMessage(process)), call = NULL,
      parent = process, timed_out = inherits(process, c(
        "processx_timeout", "system_command_timeout_error")),
      status = NA_integer_, stdout_stderr = conditionMessage(process), receipt = NULL
    ), class = c("wb_pybench_process_error", "error", "condition"))
    stop(condition)
  }
  if (isTRUE(process$timeout)) {
    condition <- structure(list(
      message = "PyBench subprocess exceeded its execution timeout", call = NULL,
      timed_out = TRUE, status = NA_integer_,
      stdout_stderr = c(process$stdout %||% "", process$stderr %||% ""), receipt = NULL
    ), class = c("wb_pybench_process_error", "error", "condition"))
    stop(condition)
  }
  out <- c(strsplit(process$stdout %||% "", "\n", fixed = TRUE)[[1]],
           strsplit(process$stderr %||% "", "\n", fixed = TRUE)[[1]])
  out <- out[nzchar(out)]
  status <- as.integer(process$status %||% 0L)

  if (!identical(as.integer(status), 0L)) {
    msg <- paste(c(
      paste0("pybench module failed (module=", module, ", status=", status, ")"),
      if (length(out)) out else NULL
    ), collapse = "\n")

    # If a receipt exists, prefer protocol error context.
    if (file.exists(receipt_path)) {
      rec_try <- try(jsonlite::read_json(receipt_path, simplifyVector = FALSE), silent = TRUE)
      if (!inherits(rec_try, "try-error") && is.list(rec_try)) {
        condition <- structure(list(
          message = msg, call = NULL, timed_out = FALSE, status = as.integer(status),
          stdout_stderr = out, receipt = rec_try
        ), class = c("wb_pybench_process_error", "error", "condition"))
        stop(condition)
      }
    }
    condition <- structure(list(
      message = msg, call = NULL, timed_out = FALSE, status = as.integer(status),
      stdout_stderr = out, receipt = NULL
    ), class = c("wb_pybench_process_error", "error", "condition"))
    stop(condition)
  }

  receipt <- .wb_pyproto_read_receipt_json(receipt_path, request = request)
  if (!is.null(bundle)) .wb_pybench_canonicalize_model_paths(bundle, request$outputs)
  list(
    status = 0L,
    stdout_stderr = out,
    request = request,
    receipt = receipt,
    request_path = request_path,
    receipt_path = receipt_path
  )
}

.wb_pybench_canonicalize_model_paths <- function(bundle, outputs) {
  .wb_assert(inherits(bundle,"scworkbench_bundle"),"bundle must be scworkbench_bundle")
  ids <- if (length(outputs)) vapply(outputs,function(x) as.character(x$artifact_id %||% "")[1],character(1)) else character()
  ids <- ids[nzchar(ids)]
  if (!length(ids) || !.wb_table_exists(bundle$con,"artifact_model_ref")) return(invisible(TRUE))
  for (artifact_id in ids) {
    row <- DBI::dbGetQuery(bundle$con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(artifact_id))
    if (!nrow(row)) next
    raw <- as.character(row$model_path[1] %||% "")[1]
    if (.wb_path_is_absolute(raw)) {
      resolved <- normalizePath(raw,winslash="/",mustWork=FALSE)
      root <- .wb_bundle_root(bundle)
      .wb_assert(.wb_path_inside(resolved,root) && (file.exists(resolved)||dir.exists(resolved)),
                 "PYBENCH_PATH_CONTRACT_VIOLATION: model output resolves outside the mounted bundle.")
      relative <- substring(resolved,nchar(root)+2L)
    } else {
      status <- .wb_path_status(bundle$dir,raw,expected_type="either",must_exist=TRUE,purpose="PyBench model output")
      .wb_assert(isTRUE(status$ok),paste0("PYBENCH_PATH_CONTRACT_VIOLATION: ",status$code))
      relative <- status$relative
    }
    DBI::dbExecute(bundle$con,"UPDATE artifact_model_ref SET model_path=? WHERE artifact_id=?;",params=list(relative,artifact_id))
  }
  invisible(TRUE)
}

# Build the output-bound SQLite/payload authority for a pybench-op-v2 request.
.wb_pybench_write_allowlist <- function(outputs, params = list()) {
  table_map <- list(
    cell_vector = c("artifact_labels"),
    cell_vector_family = c("artifact_relation_rows"),
    relation_family = c("artifact_relation_rows"),
    pseudotime = c("artifact_pseudotime"),
    path_2d_family = c("artifact_curves_2d"),
    space_path = c("artifact_space_path_meta", "artifact_space_path_rows"),
    space_2d = character(),
    obs_table = c("artifact_tables", "artifact_table_rows"),
    feature_table = c("artifact_tables", "artifact_table_rows"),
    model_ref = c("artifact_model_ref")
  )
  out <- list()
  add <- function(x) { out[[length(out) + 1L]] <<- x }
  for (nm in names(outputs %||% list())) {
    spec <- outputs[[nm]]
    id <- as.character(spec$artifact_id %||% "")[1]
    kind <- as.character(spec$type %||% "")[1]
    if (identical(kind, "space")) next
    tables <- table_map[[kind]] %||% character()
    .wb_assert(length(tables) > 0L || identical(kind, "space_2d"),
               paste0("PYBENCH_CAPABILITY_MISMATCH: no v2 mutation mapping for output kind '", kind, "'"))
    for (table in tables) add(list(
      output_name = nm, output_id = id, output_kind = kind, mutation_class = "sqlite_rows",
      table = table, key_scope = list(column = "artifact_id", values = list(id))
    ))
    if (identical(kind, "model_ref")) add(list(
      output_name = nm, output_id = id, output_kind = kind, mutation_class = "payload_tree",
      path = paste0("artifact_models/", id)
    ))
  }
  space_id <- as.character(params$output_space_id %||% params$space_id_out %||% "")[1]
  if (nzchar(space_id)) {
    # A space is an operation output even where the legacy bridge returned it
    # as a typed registry primitive rather than a preregistered artifact.
    space_name <- if ("space_registry" %in% names(outputs)) "space_registry" else if ("space" %in% names(outputs)) "space" else names(outputs)[1]
    if (!length(space_name) || !nzchar(space_name)) space_name <- "space"
    synthetic <- list(output_name = space_name, output_id = space_id, output_kind = "space")
    for (table in c("spaces", "space_payloads")) add(c(synthetic, list(
      mutation_class = "sqlite_rows", table = table,
      key_scope = list(column = "space_id", values = list(space_id))
    )))
    add(c(synthetic, list(
      mutation_class = "payload_tree", path = "space_payloads"
    )))
  }
  out
}

.wb_pybench_current_run_id <- function(bundle) {
  ctx <- .wb_current_mutation_context(bundle$con, bundle$dir)
  .wb_assert(!is.null(ctx) && identical(as.character(ctx$route), "session_execution") && nzchar(as.character(ctx$run_id %||% "")[1]),
             "PYBENCH_CAPABILITY_MISMATCH: writable PyBench requests require a preallocated session run")
  as.character(ctx$run_id)[1]
}

# Build a pybench-op-v2 request payload (internal helper).
.wb_pybench_build_request <- function(bundle,
                                      op_name,
                                      run_id = NULL,
                                      inputs = list(),
                                      params = list(),
                                      outputs = list(),
                                      mode = "staging_write") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  mode <- match.arg(mode, c("staging_write", "read_only"))
  binding <- bundle$pybench_session_binding %||% NULL
  if (identical(mode, "staging_write")) {
    .wb_assert(nzchar(as.character(bundle$staging_source_dir %||% "")[1]) && !is.null(binding),
               "PYBENCH_SOURCE_WRITE_ATTEMPT: writable PyBench requests are restricted to an engine-created session stage")
    actual_run <- .wb_pybench_current_run_id(bundle)
    if (!is.null(run_id) && nzchar(as.character(run_id)[1])) {
      .wb_assert(identical(as.character(run_id)[1], actual_run),
                 "PYBENCH_CAPABILITY_MISMATCH: supplied run ID is not the session's preallocated run ID")
    }
  } else {
    actual_run <- as.character(run_id %||% paste0("read_", .wb_writer_lock_token()))[1]
    if (is.null(binding)) {
      source <- .wb_session_source_identity(bundle)
      binding <- list(
        session_id = paste0("read_only_", substr(.wb_prov_sha256_object(bundle$dir), 1L, 16L)),
        source_attestation = list(scheme = "scworkbench-scientific-state-v1", content_sha256 = source$scientific_state_fingerprint),
        checkpoint_generation = "committed-read-only",
        root_sha256 = .wb_prov_sha256_object(list(source = source$bundle_dir, mode = "read_only"))
      )
    }
  }
  space_id <- as.character(params$output_space_id %||% params$space_id_out %||% "")[1]
  if (identical(mode, "staging_write") && nzchar(space_id) && !"space_registry" %in% names(outputs)) {
    outputs$space_registry <- list(artifact_id = space_id, type = "space")
  }
  allow <- if (identical(mode, "read_only")) list() else .wb_pybench_write_allowlist(outputs, params)
  capability <- list(
    capability_id = paste0("cap_", .wb_writer_lock_token()), mode = mode,
    session_id = as.character(binding$session_id)[1], run_id = actual_run,
    source_attestation = binding$source_attestation,
    staging_identity = list(root_sha256 = as.character(binding$root_sha256)[1],
                            checkpoint_generation = as.character(binding$checkpoint_generation)[1]),
    write_allowlist = allow
  )
  req <- list(
    message_type = "request",
    protocol_version = .wb_pyproto_version(),
    bundle_dir = normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
    path_contract = .wb_pyproto_path_contract(),
    op_name = as.character(op_name)[1],
    run = list(session_id = as.character(binding$session_id)[1], run_id = actual_run),
    execution_capability = capability,
    inputs = inputs %||% list(),
    params = params %||% list(),
    outputs = outputs %||% list()
  )
  .wb_pyproto_validate_request(req)
  req
}

# Pre-register artifact rows for a Python op (internal payload-only bridge).
.wb_pybench_preregister_outputs <- function(bundle,
                                            run,
                                            outputs_spec,
                                            created_by = "pybench-bridge") {
  con <- bundle$con
  .wb_assert(wb_is_run(run), "run must be a wb_run")
  .wb_assert(is.list(outputs_spec) && length(outputs_spec) > 0L, "outputs_spec must be a non-empty named list")
  .wb_assert(!is.null(names(outputs_spec)) && all(nzchar(names(outputs_spec))), "outputs_spec must be named")

  wb_migrate_artifacts(bundle)

  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- jsonlite::toJSON(list(pybench_pending = TRUE, run_id = run$run_id %||% NA_character_),
                                auto_unbox = TRUE, null = "null")

  out <- list()
  for (nm in names(outputs_spec)) {
    spec <- outputs_spec[[nm]]
    type <- as.character(spec$type %||% "")[1]
    .wb_pyproto_assert_scalar_chr(type, paste0("outputs_spec$", nm, "$type"))
    artifact_id <- as.character(spec$artifact_id %||% "")[1]
    if (!nzchar(artifact_id)) {
      artifact_id <- .wb_allocate_db_identifier(
        con, "artifacts", "artifact_id",
        paste0(type, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
        n = 8L, purpose = "PyBench artifact"
      )
    } else {
      .wb_assert_preallocated_identifier_available(
        con, "artifacts", "artifact_id", artifact_id, "PyBench artifact"
      )
    }

    DBI::dbExecute(con, "
      INSERT INTO artifacts(
        artifact_id, type, name, description, created_at, created_by,
        source_op, input_space_id, input_matrix_id, cell_set,
        provenance_json, scworkbench_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ", params = list(
      artifact_id,
      type,
      as.character(spec$name %||% paste0(nm, " (", run$op_name, ")"))[1],
      as.character(spec$description %||% NA_character_)[1],
      created_at,
      created_by,
      as.character(run$op_name %||% "pybench_op")[1],
      .wb_run_input_space_id(run),
      .wb_run_input_matrix_id(run),
      run$inputs$cell_set %||% "all",
      as.character(prov_json),
      as.character(utils::packageVersion("scworkbench"))
    ))
    out[[nm]] <- list(artifact_id = artifact_id, type = type)
  }
  out
}
