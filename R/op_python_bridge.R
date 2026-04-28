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
                                   python_bin = .wb_pybench_default_python(),
                                   env = character(0),
                                   request_path = tempfile("pybench_req_", fileext = ".json"),
                                   receipt_path = tempfile("pybench_rec_", fileext = ".json")) {
  .wb_pyproto_validate_request(request)
  .wb_pyproto_assert_scalar_chr(as.character(module %||% ""), "module")
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

  args <- c("-m", module, "--request", request_path, "--receipt", receipt_path)
  out <- system2(py, args = args, stdout = TRUE, stderr = TRUE, env = c(env_extra, env))
  status <- attr(out, "status") %||% 0L

  if (!identical(as.integer(status), 0L)) {
    msg <- paste(c(
      paste0("pybench module failed (module=", module, ", status=", status, ")"),
      if (length(out)) out else NULL
    ), collapse = "\n")

    # If a receipt exists, prefer protocol error context.
    if (file.exists(receipt_path)) {
      rec_try <- try(jsonlite::read_json(receipt_path, simplifyVector = TRUE), silent = TRUE)
      if (!inherits(rec_try, "try-error") && is.list(rec_try)) {
        return(list(status = as.integer(status), stdout_stderr = out, request = request, receipt = rec_try))
      }
    }
    stop(msg, call. = FALSE)
  }

  receipt <- .wb_pyproto_read_receipt_json(receipt_path, request = request)
  list(
    status = 0L,
    stdout_stderr = out,
    request = request,
    receipt = receipt,
    request_path = request_path,
    receipt_path = receipt_path
  )
}

#' Build a pybench-op-v1 request payload (scaffold helper)
.wb_pybench_build_request <- function(bundle,
                                      op_name,
                                      run_id,
                                      inputs = list(),
                                      params = list(),
                                      outputs = list()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  req <- list(
    protocol_version = .wb_pyproto_version(),
    bundle_dir = normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
    op_name = as.character(op_name)[1],
    run = list(run_id = as.character(run_id)[1]),
    inputs = inputs %||% list(),
    params = params %||% list(),
    outputs = outputs %||% list()
  )
  .wb_pyproto_validate_request(req)
  req
}

#' Pre-register artifact rows for a Python op (payload-only write model)
#'
#' Returns a named list mapping output name -> list(artifact_id=..., type=...)
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
    artifact_id <- paste0(type, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
                          paste0(sample(c(0:9, letters), 8, TRUE), collapse = ""))

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
