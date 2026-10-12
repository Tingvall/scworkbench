args <- commandArgs(trailingOnly = TRUE)
repo <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
real_python <- file.path(normalizePath(dirname(args[[2]]), winslash = "/", mustWork = TRUE),
                         basename(args[[2]]))
manifest <- normalizePath(args[[3]], winslash = "/", mustWork = TRUE)
library(scworkbench,lib.loc="/tmp/scwb-final-585.ki8nvr4e/library")
trace(".wb_graph_object_restore",where=asNamespace("scworkbench"),tracer=quote({cat("TRACE_OBJECT_RESTORE transaction=",RSQLite::sqliteIsTransacting(bundle$con),"\n");print(sys.calls())}),print=FALSE)

work <- tempfile("operation_pack_python_faults_")
dir.create(work, recursive = TRUE)
on.exit(unlink(work, recursive = TRUE, force = TRUE), add = TRUE)
driver <- file.path(work, "fault_driver.py")
wrapper <- file.path(work, "python")
mode_file <- file.path(work, "mode")
writeLines(c(
  "import json, os, signal, sqlite3, subprocess, sys, time",
  "from pathlib import Path",
  "real = os.environ['SCWB_FAULT_REAL_PYTHON']",
  "mode = Path(os.environ['SCWB_FAULT_MODE_FILE']).read_text().strip()",
  "argv = sys.argv[1:]",
  "if 'discover' in argv or mode == 'normal':",
  "    raise SystemExit(subprocess.call([real, *argv]))",
  "if 'execute' not in argv:",
  "    raise SystemExit(subprocess.call([real, *argv]))",
  "def value(flag): return argv[argv.index(flag) + 1]",
  "request_path = Path(value('--request'))",
  "request = json.loads(request_path.read_text())",
  "root = Path(request['bundle_dir'])",
  "dbrel = json.loads((root / 'manifest.json').read_text())['storage']['sqlite']['path']",
  "if mode == 'partial_nonzero':",
  "    con = sqlite3.connect(root / dbrel)",
  "    out = request['outputs']['vector']['artifact_id']",
  "    cell = con.execute('SELECT cell_id FROM cells ORDER BY rowid LIMIT 1').fetchone()[0]",
  "    con.execute('INSERT INTO artifact_labels(artifact_id,cell_id,label,value_type,value_num) VALUES(?,?,?,?,?)',(out,cell,'999','continuous',999.0))",
  "    con.commit(); con.close(); raise SystemExit(17)",
  "if mode == 'timeout': time.sleep(60)",
  "if mode == 'signal': os.kill(os.getpid(), signal.SIGKILL)",
  "status = subprocess.call([real, *argv])",
  "if status: raise SystemExit(status)",
  "if mode == 'forged_receipt':",
  "    p = Path(value('--receipt')); x = json.loads(p.read_text()); x['write_manifest'] = []; p.write_text(json.dumps(x))",
  "elif mode == 'incomplete_receipt':",
  "    p = Path(value('--receipt')); x = json.loads(p.read_text()); x.pop('outputs',None); p.write_text(json.dumps(x))",
  "elif mode == 'forged_runtime':",
  "    p = Path(value('--runtime-attestation')); x = json.loads(p.read_text()); x['interpreter']['executable_sha256'] = '0' * 64; p.write_text(json.dumps(x))",
  "elif mode == 'undeclared_file': (root / 'undeclared-operation-pack-file').write_text('forbidden')",
  "elif mode == 'undeclared_symlink': os.symlink('/etc/passwd', root / 'undeclared-operation-pack-link')",
  "raise SystemExit(0)"
), driver)
writeLines(c("#!/bin/sh", paste("exec", shQuote(real_python), shQuote(driver), '"$@"')), wrapper)
Sys.chmod(wrapper, mode = "0755")
writeLines("normal", mode_file)
Sys.setenv(SCWB_FAULT_REAL_PYTHON = real_python, SCWB_FAULT_MODE_FILE = mode_file)

invisible(wb_operation_pack_activate(manifest, python = wrapper, timeout_seconds = 2))
root <- tempfile("operation_pack_fault_bundle_")
workspace <- tempfile("operation_pack_fault_workspace_")
on.exit(unlink(c(root, workspace), recursive = TRUE, force = TRUE), add = TRUE)
bundle <- wb_init_bundle(root, overwrite = TRUE)
cells <- paste0("c", seq_len(12L))
wb_define_cells(bundle, cells, metadata = data.frame(cell_id = cells, signal = seq_len(12L)))
session <- wb_session_create(bundle, workspace, session_id = "faults")
source <- wb_session_run_op(session, bundle, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "fault_signal", value_type = "continuous",
  missing_policy = "error", min_cells = 1L))
workspace_path <- source$session$durable$workspace
wb_close_bundle(source$session$staging_bundle)
source$session$staging_bundle <- NULL
source_identity <- getFromNamespace(".wb_session_source_identity", "scworkbench")
committed_before <- source_identity(bundle)$scientific_state_fingerprint

attempt <- function(mode, expected_code = NULL, pattern = NULL) {
  cat("FAULT_ATTEMPT",mode,"\n");flush.console()
  writeLines(mode, mode_file)
  resumed <- wb_session_resume(bundle, workspace_path)
  before_db <- getFromNamespace(".wb_pybench_db_snapshot", "scworkbench")(
    resumed$staging_bundle$con)
  before_payload <- getFromNamespace(".wb_pybench_payload_snapshot", "scworkbench")(
    resumed$staging_bundle$dir)
  error <- tryCatch(wb_session_run_op(resumed, bundle,
    "scwbpython::affine_cell_vector", inputs = list(
      signal = wb_ref_run(source$run$run_id, "vector"), scale = 2, min_cells = 1L)),
    error = identity)
  stopifnot(inherits(error, "error"))
  if (!is.null(expected_code) && !identical(error$code, expected_code)) {
    stop("fault mode ", mode, " returned code ", error$code %||% "<none>",
         " instead of ", expected_code, ": ", conditionMessage(error), call. = FALSE)
  }
  if (!is.null(pattern) && !grepl(pattern, conditionMessage(error), fixed = TRUE)) {
    stop("fault mode ", mode, " did not report '", pattern, "': ",
         conditionMessage(error), call. = FALSE)
  }
  wb_close_bundle(resumed$staging_bundle)
  resumed$staging_bundle <- NULL
  after <- wb_session_resume(bundle, workspace_path)
  stopifnot(
    identical(before_db, getFromNamespace(".wb_pybench_db_snapshot", "scworkbench")(
      after$staging_bundle$con)),
    identical(before_payload, getFromNamespace(".wb_pybench_payload_snapshot", "scworkbench")(
      after$staging_bundle$dir)),
    identical(committed_before, source_identity(bundle)$scientific_state_fingerprint)
  )
  wb_close_bundle(after$staging_bundle)
  after$staging_bundle <- NULL
  invisible(after)
}

attempt("partial_nonzero", "OPERATION_PACK_EXECUTION_FAILED")
attempt("timeout", "OPERATION_PACK_EXECUTION_TIMEOUT")
attempt("signal", "OPERATION_PACK_EXECUTION_SIGNALLED")
attempt("forged_runtime", "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH")
attempt("forged_receipt", pattern = "PYBENCH_RECEIPT_MISMATCH")
attempt("incomplete_receipt", pattern = "receipt$outputs")
attempt("undeclared_file", pattern = "PYBENCH_OUT_OF_SCOPE_MUTATION")
attempt("undeclared_symlink", pattern = "PYBENCH_OUT_OF_SCOPE_MUTATION")

old_hook <- getOption("scworkbench.pybench_transition_fault_hook")
options(scworkbench.pybench_transition_fault_hook = function(boundary) {
  if (identical(boundary, "after_receipt_before_publication")) stop("injected publication fault")
})
attempt("normal", pattern = "PYBENCH_PUBLICATION_FAILED")
options(scworkbench.pybench_transition_fault_hook = old_hook)

# Exact retry succeeds after every durable failure and promotes once, without
# duplicate publication or fault residue.
cat("FAULT_LEGITIMATE_RETRY\n");flush.console()
writeLines("normal", mode_file)
retry_session <- wb_session_resume(bundle, workspace_path)
retry <- wb_session_run_op(retry_session, bundle,
  "scwbpython::affine_cell_vector", inputs = list(
    signal = wb_ref_run(source$run$run_id, "vector"), scale = 2, min_cells = 1L))
promotion <- wb_session_promote_current(bundle, retry$session,
  outputs = c("vector", "summary"), created_by = "operation-pack-fault-retry")
stopifnot(sum(promotion$promoted$status == "ok") == 2L,
          !any(grepl("undeclared-operation-pack", list.files(root, recursive = TRUE))))
invisible(wb_session_discard(promotion$session))
wb_close_bundle(bundle)
cat("OPERATION_PACK_V1_PYTHON_FAULTS_OK\n")
