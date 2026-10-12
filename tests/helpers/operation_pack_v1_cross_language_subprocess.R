args <- commandArgs(trailingOnly = TRUE)
repo <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
python <- file.path(normalizePath(dirname(args[[2]]), winslash = "/", mustWork = TRUE),
                    basename(args[[2]]))
python_manifest <- normalizePath(args[[3]], winslash = "/", mustWork = TRUE)
if (identical(Sys.getenv("SCWORKBENCH_TEST_INSTALLED"), "1")) {
  library(scworkbench)
} else {
  devtools::load_all(repo, quiet = TRUE)
}
stopifnot(nrow(wb_operation_packs()) == 0L)

r_package <- "scworkbenchOperationPackTemplate"
r_manifest <- system.file("scworkbench", "operation-pack.json", package = r_package)
stopifnot(nzchar(r_manifest), file.exists(r_manifest))

copy_bundle <- function(source, destination) {
  dir.create(destination, recursive = TRUE)
  files <- list.files(source, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  stopifnot(all(file.copy(files, destination, recursive = TRUE)))
  invisible(destination)
}

# Explicit activation, inspection, public catalog composition, and load-order
# independent identities.
invisible(wb_operation_pack_load(r_package))
invisible(wb_operation_pack_load("scwbV2Reference"))
python_pack <- wb_operation_pack_activate(
  python_manifest, python = python, timeout_seconds = 60)
composite <- read.dcf(file.path(repo, "inst", "release", "composite_release.dcf"))
expected_pybench_revision <- as.character(composite[1L, "PyBenchCommit"])
stopifnot(
  identical(python_pack$identity$manifest_sha256,
    "9f9ed39a8f0506f7d67c43a3a5bb6356715b5f0ba3a0022c1e8113681bfb0253"),
  identical(python_pack$identity$operation_definition_sha256[[
    "scwbpython::affine_cell_vector"]],
    "059d06d5c8710958f3ec56fc0977e773cf30499c9d7396dd57778d6e7bd5487b"),
  identical(python_pack$identity$pack_sha256,
    "864bd72926807e55ab465580d2235e39d4512ac6c621070662c67586dc385aab"),
  !"executable" %in% names(python_pack$runtime_attestation$interpreter),
  identical(python_pack$runtime_attestation$pybench$source_revision,
    expected_pybench_revision)
)
forward_catalog <- wb_operation_catalog_identity()$sha256
forward_semantic <- wb_semantic_catalog()$catalog_sha256
stopifnot(all(c("scwbexample::affine_cell_vector", "scwbpython::affine_cell_vector") %in%
  wb_list_ops()))
python_record <- Filter(function(x) identical(x$record_id,
  "op:scwbpython::affine_cell_vector"), wb_semantic_catalog()$records)[[1]]
stopifnot(identical(python_record$source_pack$pack_sha256,
  python_pack$identity$pack_sha256))

order_script <- tempfile("operation_pack_order_", fileext = ".R")
on.exit(unlink(order_script), add = TRUE)
writeLines(c(
  "a<-commandArgs(trailingOnly=TRUE)",
  "if(identical(Sys.getenv('SCWORKBENCH_TEST_INSTALLED'),'1'))library(scworkbench)else devtools::load_all(a[[1]],quiet=TRUE)",
  "invisible(wb_operation_pack_load('scwbV2Reference'))",
  "invisible(wb_operation_pack_activate(a[[3]],python=a[[2]],timeout_seconds=60))",
  "invisible(wb_operation_pack_load('scworkbenchOperationPackTemplate'))",
  "cat(wb_operation_catalog_identity()$sha256,'\\n')",
  "cat(wb_semantic_catalog()$catalog_sha256,'\\n')"
), order_script)
order_log <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(order_script), shQuote(repo), shQuote(python), shQuote(python_manifest)
), stdout = TRUE, stderr = TRUE)
stopifnot(is.null(attr(order_log, "status")),
  identical(grep("^[0-9a-f]{64}$", trimws(order_log), value = TRUE),
            c(forward_catalog, forward_semantic)))

# One durable mixed-backend DAG: core -> R pack -> Python pack -> core.
bundle_root <- tempfile("operation_pack_cross_language_bundle_")
strict_clone_root <- tempfile("operation_pack_cross_language_strict_")
target_clone_root <- tempfile("operation_pack_cross_language_target_")
script_clone_root <- tempfile("operation_pack_cross_language_script_")
workspace_root <- tempfile("operation_pack_cross_language_workspace_")
process_bundle_root <- tempfile("operation_pack_cross_language_process_bundle_")
process_workspace_root <- tempfile("operation_pack_cross_language_process_workspace_")
on.exit(unlink(c(bundle_root, strict_clone_root, target_clone_root, script_clone_root,
                 workspace_root,
                 process_bundle_root, process_workspace_root),
  recursive = TRUE, force = TRUE), add = TRUE)
bundle <- wb_init_bundle(bundle_root, overwrite = TRUE)
cells <- paste0("cell_", seq_len(16L))
wb_define_cells(bundle, cells, metadata = data.frame(
  cell_id = cells, signal = seq_len(16L) / 4,
  group = rep(c("A", "B"), each = 8L), stringsAsFactors = FALSE
))
wb_close_bundle(bundle)
copy_bundle(bundle_root, strict_clone_root)
copy_bundle(bundle_root, target_clone_root)
copy_bundle(bundle_root, script_clone_root)
bundle <- wb_open_bundle(bundle_root)
session <- wb_session_create(bundle, workspace_root, session_id = "cross_language")
source <- wb_session_run_op(session, bundle, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "cross_language_signal",
  value_type = "continuous", missing_policy = "error", min_cells = 1L))
r_run <- wb_session_run_op(source$session, bundle,
  "scwbexample::affine_cell_vector", inputs = list(
    signal = wb_ref_run(source$run$run_id, "vector"), scale = 2,
    shift = 1, min_cells = 1L))
python_run <- wb_session_run_op(r_run$session, bundle,
  "scwbpython::affine_cell_vector", inputs = list(
    signal = wb_ref_run(r_run$run$run_id, "vector"), scale = 3,
    min_cells = 1L))
terminal <- wb_session_run_op(python_run$session, bundle,
  "scwbv2reference::two_table_terminal", inputs = list(
    a = wb_ref_run(r_run$run$run_id, "vector"),
    b = wb_ref_run(python_run$run$run_id, "vector"),
    min_cells = 1L))
stopifnot(
  identical(r_run$run$operation_pack$pack_sha256,
    "f8abd3c8dcaa78c9f08494d98ce45adec68c05147fc0a01dbb3d11e20038b361"),
  identical(python_run$run$operation_pack$pack_sha256,
    "864bd72926807e55ab465580d2235e39d4512ac6c621070662c67586dc385aab"),
  identical(python_run$run$operation_pack_runtime$schema,
    "scworkbench.operation_pack_runtime.python.v1"),
  identical(as.numeric(python_run$run$outputs$vector$value),
    (seq_len(16L) / 4 * 2 + 1) * 3)
)
mixed_run_ids <- c(source$run$run_id, r_run$run$run_id,
                   python_run$run$run_id, terminal$run$run_id)
resumed <- wb_session_resume(bundle, terminal$session$durable$workspace)
promotion <- wb_session_promote_current(
  bundle, resumed, outputs = c("summary", "detail"),
  created_by = "operation-pack-cross-language-test")
promoted <- promotion$promoted[promotion$promoted$status == "ok", , drop = FALSE]
stopifnot(nrow(promoted) == 2L)
snapshot_id <- unique(as.character(promoted$snapshot_id))
summary_artifact <- as.character(promoted$artifact_id[promoted$output == "summary"])
detail_artifact <- as.character(promoted$artifact_id[promoted$output == "detail"])
stopifnot(length(snapshot_id) == 1L, length(summary_artifact) == 1L,
          length(detail_artifact) == 1L)
invisible(wb_session_discard(promotion$session))
wb_close_bundle(bundle)

# Reopen, load, content-validate, inspect the mixed DAG/certificate/runtime,
# and prove no host path entered persisted pack provenance.
bundle <- wb_open_bundle(bundle_root)
stopifnot(inherits(wb_art_load(bundle, summary_artifact, "obs_table"), "wb_primitive"),
          inherits(wb_art_load(bundle, detail_artifact, "obs_table"), "wb_primitive"),
          isTRUE(wb_bundle_validation_report(bundle_root, level = "content")$ok))
dag <- wb_prov_bundle_dag(bundle, include_snapshots = TRUE)
stopifnot(all(paste0("run:", mixed_run_ids) %in% dag$nodes$id),
          paste0("artifact:", summary_artifact) %in% dag$nodes$id)
certificate <- wb_entity_certificate(bundle, "artifact", summary_artifact)
stopifnot(identical(certificate$producer$operation$name,
  "scwbv2reference::two_table_terminal"))
python_details <- wb_prov_run_details(bundle, python_run$run$run_id, snapshot_id)
runtime <- python_details$run$runtime_fingerprint$operation_pack_runtime
stopifnot(
  identical(runtime$schema, "scworkbench.operation_pack_runtime.python.v1"),
  identical(runtime$distribution$artifact_identity$sha256,
    python_pack$runtime_attestation$distribution$artifact_identity$sha256),
  !"executable" %in% names(runtime$interpreter),
  !grepl("/home/|/tmp/|^[A-Za-z]:[/\\\\]", jsonlite::toJSON(runtime), perl = TRUE)
)
stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))

# Fresh recipient: installing either package is inert. Historical definitions,
# outputs, certificate, DAG, and runtime remain inspectable; execution and
# replay diagnostics require the exact absent pack identities.
recipient_script <- tempfile("operation_pack_cross_language_recipient_", fileext = ".R")
on.exit(unlink(recipient_script), add = TRUE)
writeLines(c(
  "a<-commandArgs(trailingOnly=TRUE)",
  "if(identical(Sys.getenv('SCWORKBENCH_TEST_INSTALLED'),'1'))library(scworkbench)else devtools::load_all(a[[1]],quiet=TRUE)",
  "b<-wb_open_bundle(a[[2]],read_only=TRUE)",
  "stopifnot(!nrow(wb_operation_packs()),isTRUE(wb_bundle_validation_report(a[[2]],level='content')$ok))",
  "stopifnot(inherits(wb_art_load(b,a[[3]],'obs_table'),'wb_primitive'))",
  "stopifnot(is.list(wb_entity_certificate(b,'artifact',a[[3]])),nrow(wb_prov_bundle_dag(b)$nodes)>0)",
  "r<-wb_prov_run_replay_inputs(b,a[[4]],a[[6]])",
  "p<-wb_prov_run_replay_inputs(b,a[[5]],a[[6]])",
  "codes<-function(x)vapply(x$diagnostics$issues,function(z)z$code,character(1))",
  "stopifnot('OPERATION_PACK_REQUIRED'%in%codes(r),'OPERATION_PACK_REQUIRED'%in%codes(p))",
  "d<-wb_prov_run_details(b,a[[5]],a[[6]])",
  "stopifnot(identical(d$run$contract$interface$source_pack$pack_sha256,'864bd72926807e55ab465580d2235e39d4512ac6c621070662c67586dc385aab'))",
  "wb_close_bundle(b)",
  "b<-wb_open_bundle(a[[2]])",
  "e<-tryCatch(wb_session_run_op(wb_session_new(),b,'scwbpython::affine_cell_vector',inputs=list()),error=identity)",
  "stopifnot(inherits(e,'wb_operation_pack_unavailable'),identical(e$code,'OPERATION_PACK_REQUIRED'))",
  "wb_close_bundle(b)",
  "cat('CROSS_LANGUAGE_RECIPIENT_OK\\n')"
), recipient_script)
recipient <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(recipient_script), shQuote(repo), shQuote(bundle_root),
  shQuote(summary_artifact), shQuote(r_run$run$run_id),
  shQuote(python_run$run$run_id), shQuote(snapshot_id)
), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(recipient, "status"))) {
  stop(paste(recipient, collapse = "\n"), call. = FALSE)
}
stopifnot(is.null(attr(recipient, "status")),
          any(recipient == "CROSS_LANGUAGE_RECIPIENT_OK"))

# Restored packs enable strict replay and targeted reproduction on source-only
# clones. The emitted script uses only public scworkbench APIs.
script <- wb_art_emit_r_script(bundle, summary_artifact,
  bundle_dir_literal = script_clone_root)
stopifnot(!grepl("scworkbench:::", script, fixed = TRUE))
emitted_path <- tempfile("operation_pack_public_replay_", fileext = ".R")
emitted_wrapper <- tempfile("operation_pack_public_replay_wrapper_", fileext = ".R")
on.exit(unlink(c(emitted_path, emitted_wrapper)), add = TRUE)
writeLines(script, emitted_path)
writeLines(c(
  "a<-commandArgs(trailingOnly=TRUE)",
  "if(identical(Sys.getenv('SCWORKBENCH_TEST_INSTALLED'),'1'))library(scworkbench)else devtools::load_all(a[[1]],quiet=TRUE)",
  "invisible(wb_operation_pack_load('scworkbenchOperationPackTemplate'))",
  "invisible(wb_operation_pack_load('scwbV2Reference'))",
  "invisible(wb_operation_pack_activate(a[[3]],python=a[[2]],timeout_seconds=60))",
  "source(a[[4]],local=TRUE)",
  "cat('PUBLIC_EMITTED_REPLAY_OK\\n')"
), emitted_wrapper)
emitted <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(emitted_wrapper), shQuote(repo), shQuote(python),
  shQuote(python_manifest), shQuote(emitted_path)
), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(emitted, "status"))) stop(paste(emitted, collapse = "\n"), call. = FALSE)
stopifnot(any(emitted == "PUBLIC_EMITTED_REPLAY_OK"),
          isTRUE(wb_bundle_validation_report(script_clone_root, level = "content")$ok))
strict_clone <- wb_open_bundle(strict_clone_root)
strict <- wb_prov_validate_replay(bundle, snapshot_id = snapshot_id,
  profile = "strict", strict = TRUE, destination_bundle = strict_clone)
stopifnot(isTRUE(strict$summary$valid))
invisible(wb_session_discard(strict$replay_session))
wb_close_bundle(strict_clone)
plan <- wb_target_reproduction_plan(bundle, paste0("artifact:", summary_artifact))
stopifnot(identical(plan$status, "ok"), identical(plan$run_order, mixed_run_ids))
target <- wb_target_execute_plan(plan, target_clone_root)
stopifnot(identical(target$status, "promoted_and_verified"),
          all(target$verification$status == "equivalent"))

# A durable checkpoint crosses two actual R process replacements: the first
# recipient resumes after the R-pack run and executes Python; the second resumes
# after the Python checkpoint, continues through core, and promotes.
process_bundle <- wb_init_bundle(process_bundle_root, overwrite = TRUE)
wb_define_cells(process_bundle, cells, metadata = data.frame(
  cell_id = cells, signal = seq_len(16L) / 4, stringsAsFactors = FALSE))
process_session <- wb_session_create(
  process_bundle, process_workspace_root, session_id = "cross_language_process")
process_source <- wb_session_run_op(
  process_session, process_bundle, "metadata_cell_vector", inputs = list(
    source_column = "signal", vector_name = "process_signal",
    value_type = "continuous", missing_policy = "error", min_cells = 1L))
process_r <- wb_session_run_op(process_source$session, process_bundle,
  "scwbexample::affine_cell_vector", inputs = list(
    signal = wb_ref_run(process_source$run$run_id, "vector"),
    scale = 2, shift = 1, min_cells = 1L))
process_workspace <- process_r$session$durable$workspace
wb_close_bundle(process_r$session$staging_bundle)
process_r$session$staging_bundle <- NULL
wb_close_bundle(process_bundle)

resume_python_script <- tempfile("operation_pack_resume_python_", fileext = ".R")
resume_core_script <- tempfile("operation_pack_resume_core_", fileext = ".R")
on.exit(unlink(c(resume_python_script, resume_core_script)), add = TRUE)
load_line <- paste0(
  "if(identical(Sys.getenv('SCWORKBENCH_TEST_INSTALLED'),'1'))",
  "library(scworkbench)else devtools::load_all(a[[1]],quiet=TRUE)")
writeLines(c(
  "a<-commandArgs(trailingOnly=TRUE)", load_line,
  "invisible(wb_operation_pack_load('scworkbenchOperationPackTemplate'))",
  "invisible(wb_operation_pack_load('scwbV2Reference'))",
  "invisible(wb_operation_pack_activate(a[[5]],python=a[[4]],timeout_seconds=60))",
  "b<-wb_open_bundle(a[[2]])", "s<-wb_session_resume(b,a[[3]])",
  "x<-wb_session_run_op(s,b,'scwbpython::affine_cell_vector',inputs=list(signal=wb_ref_run(a[[6]],'vector'),scale=3,min_cells=1L))",
  "cat('PROCESS_PYTHON_RUN_ID',x$run$run_id,'\\n')",
  "wb_close_bundle(x$session$staging_bundle);wb_close_bundle(b)"
), resume_python_script)
python_resume <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(resume_python_script), shQuote(repo), shQuote(process_bundle_root),
  shQuote(process_workspace), shQuote(python), shQuote(python_manifest),
  shQuote(process_r$run$run_id)
), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(python_resume, "status"))) {
  stop(paste(python_resume, collapse = "\n"), call. = FALSE)
}
process_python_id <- trimws(sub("^PROCESS_PYTHON_RUN_ID\\s+", "",
  grep("^PROCESS_PYTHON_RUN_ID\\s+", python_resume, value = TRUE)))
stopifnot(length(process_python_id) == 1L, nzchar(process_python_id))

writeLines(c(
  "a<-commandArgs(trailingOnly=TRUE)", load_line,
  "invisible(wb_operation_pack_load('scworkbenchOperationPackTemplate'))",
  "invisible(wb_operation_pack_load('scwbV2Reference'))",
  "invisible(wb_operation_pack_activate(a[[5]],python=a[[4]],timeout_seconds=60))",
  "b<-wb_open_bundle(a[[2]])", "s<-wb_session_resume(b,a[[3]])",
  "x<-wb_session_run_op(s,b,'scwbv2reference::two_table_terminal',inputs=list(a=wb_ref_run(a[[6]],'vector'),b=wb_ref_run(a[[7]],'vector'),min_cells=1L))",
  "p<-wb_session_promote_current(b,x$session,outputs=c('summary','detail'),created_by='process-replacement-proof')",
  "stopifnot(sum(p$promoted$status=='ok')==2L)",
  "cat('PROCESS_REPLACEMENT_OK',unique(p$promoted$snapshot_id[p$promoted$status=='ok']),'\\n')",
  "invisible(wb_session_discard(p$session));wb_close_bundle(b)"
), resume_core_script)
core_resume <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(resume_core_script), shQuote(repo), shQuote(process_bundle_root),
  shQuote(process_workspace), shQuote(python), shQuote(python_manifest),
  shQuote(process_r$run$run_id), shQuote(process_python_id)
), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(core_resume, "status"))) {
  stop(paste(core_resume, collapse = "\n"), call. = FALSE)
}
process_snapshot <- trimws(sub("^PROCESS_REPLACEMENT_OK\\s+", "",
  grep("^PROCESS_REPLACEMENT_OK\\s+", core_resume, value = TRUE)))
stopifnot(length(process_snapshot) == 1L, nzchar(process_snapshot),
          isTRUE(wb_bundle_validation_report(process_bundle_root, level = "content")$ok))

# A sibling parameter branch through Python and core remains private and does
# not alter the original promoted bundle.
source_identity <- getFromNamespace(".wb_session_source_identity", "scworkbench")
original_before <- source_identity(bundle)$scientific_state_fingerprint
sibling <- wb_session_run_op(wb_session_new(), bundle, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "sibling_signal", value_type = "continuous",
  missing_policy = "error", min_cells = 1L))
sibling_python <- wb_session_run_op(sibling$session, bundle,
  "scwbpython::affine_cell_vector", inputs = list(
    signal = wb_ref_run(sibling$run$run_id, "vector"), scale = -2, min_cells = 1L))
sibling_core <- wb_session_run_op(sibling_python$session, bundle,
  "scwbv2reference::two_table_terminal", inputs = list(
    a = wb_ref_run(sibling$run$run_id, "vector"),
    b = wb_ref_run(sibling_python$run$run_id, "vector"), min_cells = 1L))
stopifnot(identical(original_before,
  source_identity(bundle)$scientific_state_fingerprint))
invisible(wb_session_discard(sibling_core$session))
wb_close_bundle(bundle)

cat("CROSS_LANGUAGE_RUN_IDS", paste(mixed_run_ids, collapse = ","), "\n")
cat("CROSS_LANGUAGE_SNAPSHOT_ID", snapshot_id, "\n")
cat("CROSS_LANGUAGE_SUMMARY_ARTIFACT", summary_artifact, "\n")
cat("CROSS_LANGUAGE_DETAIL_ARTIFACT", detail_artifact, "\n")
cat("CROSS_LANGUAGE_CATALOG_SHA256", forward_catalog, "\n")
cat("CROSS_LANGUAGE_SEMANTIC_SHA256", forward_semantic, "\n")
cat("CROSS_LANGUAGE_DISTRIBUTION_SHA256",
    python_pack$runtime_attestation$distribution$artifact_identity$sha256, "\n")
cat("CROSS_LANGUAGE_PROCESS_SNAPSHOT", process_snapshot, "\n")
cat("OPERATION_PACK_V1_CROSS_LANGUAGE_OK\n")
