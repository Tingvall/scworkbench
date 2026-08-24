args <- commandArgs(trailingOnly = TRUE)
repo <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
devtools::load_all(repo, quiet = TRUE)
options(scworkbench.catalog_generated_at = "2000-01-01T00:00:00+0000")

template_package <- "scworkbenchOperationPackTemplate"
template_op <- "scwbexample::affine_cell_vector"
stopifnot(requireNamespace(template_package, quietly = TRUE))

expect_pack_error <- function(expr, code = NULL, class = "wb_operation_pack_error") {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, class))
  if (!is.null(code)) stopifnot(identical(as.character(error$code), code))
  error
}

# No-pack parity and installation inertia.
core_names <- names(scworkbench:::.wb_op_catalog())
stopifnot(!nrow(wb_operation_packs()), identical(wb_list_ops(), core_names))
core_interfaces <- lapply(core_names, wb_op_interface)
core_ops_json <- jsonlite::toJSON(wb_op_catalog_semantic(), auto_unbox = TRUE, null = "null")
report <- wb_operation_pack_validate(template_package)
stopifnot(isTRUE(report$ok), !isTRUE(report$activated), !nrow(wb_operation_packs()),
          identical(wb_list_ops(), core_names),
          identical(jsonlite::toJSON(wb_op_catalog_semantic(), auto_unbox = TRUE, null = "null"), core_ops_json))

# Definition-level negative cases remain process-local and do not activate.
manifest_path <- system.file("scworkbench", "operation-pack.json", package = template_package)
manifest <- scworkbench:::.wb_operation_pack_read_manifest(manifest_path)
validate_bad <- function(change, code) {
  bad <- change(manifest)
  before <- wb_operation_packs()
  error <- expect_pack_error(scworkbench:::.wb_operation_pack_validate_manifest(
    bad, package = template_package,
    package_description = utils::packageDescription(template_package)
  ), code)
  stopifnot(identical(before, wb_operation_packs()))
  invisible(error)
}
validate_bad(function(x) { x$namespace <- "core"; x }, "OPERATION_PACK_NAMESPACE_RESERVED")
validate_bad(function(x) { x$operations[[1]]$name <- "affine_cell_vector"; x }, "OPERATION_PACK_MANIFEST_INVALID")
validate_bad(function(x) { x$operations <- c(x$operations, x$operations); x }, "OPERATION_PACK_OPERATION_DUPLICATE")
validate_bad(function(x) { x$backend <- "Python"; x }, "OPERATION_PACK_BACKEND_UNSUPPORTED")
validate_bad(function(x) { x$compatibility$scworkbench <- ">=99.0.0"; x }, "OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE")
validate_bad(function(x) { x$protocol_version <- "2"; x }, "OPERATION_PACK_PROTOCOL_INCOMPATIBLE")
validate_bad(function(x) { x$package$version <- "9.9.9"; x }, "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH")
validate_bad(function(x) { x$operations[[1]]$requires$signal <- "new_primitive"; x }, "OPERATION_PACK_PRIMITIVE_UNSUPPORTED")
validate_bad(function(x) { x$operations[[1]]$params[[1]]$type <- "formula"; x }, "OPERATION_PACK_PARAMETER_INVALID")
validate_bad(function(x) { x$operations[[1]]$interface_produces$vector$kind <- "obs_table"; x }, "OPERATION_PACK_OUTPUT_INVALID")
validate_bad(function(x) { x$operations[[1]]$promotable <- "missing"; x }, "OPERATION_PACK_PROMOTABLE_INVALID")
validate_bad(function(x) { x$operations[[1]]$validation_hook <- "unsafe"; x }, "OPERATION_PACK_DEFINITION_INVALID")
validated <- scworkbench:::.wb_operation_pack_validate_manifest(
  manifest, package = template_package,
  package_description = utils::packageDescription(template_package))
invisible(expect_pack_error(scworkbench:::.wb_operation_pack_registration(
  validated, stats::setNames(list("not-a-function"), template_op)),
  "OPERATION_PACK_ENTRY_POINT_INVALID"))

# Explicit activation, inspection, safe unused unload, duplicate rejection.
wb_operation_pack_load(template_package)
stopifnot(template_op %in% wb_list_ops(), nrow(wb_operation_packs()) == 1L)
identity_a <- wb_operation_pack_inspect("scwbexample")$identity
stopifnot(grepl("^[0-9a-f]{64}$", identity_a$manifest_sha256),
          grepl("^[0-9a-f]{64}$", identity_a$pack_sha256),
          identical(wb_op_interface(template_op)$source_pack$pack_sha256, identity_a$pack_sha256))
invisible(expect_pack_error(wb_operation_pack_load(template_package), "OPERATION_PACK_NAMESPACE_DUPLICATE"))
stopifnot(wb_operation_pack_unload("scwbexample"), !template_op %in% wb_list_ops())
wb_operation_pack_load(template_package)

# Semantic catalog composition and source-pack edges.
semantic <- wb_semantic_catalog()
stopifnot(grepl("^[0-9a-f]{64}$", semantic$catalog_sha256))
pack_records <- Filter(function(x) identical(x$record_id, paste0("op:", template_op)), semantic$records)
stopifnot(length(pack_records) == 1L,
          identical(pack_records[[1]]$source_pack$pack_sha256, identity_a$pack_sha256),
          any(vapply(semantic$graph$edges, function(x) {
            observed <- if (is.null(x$source_pack$pack_sha256)) "" else x$source_pack$pack_sha256
            identical(observed, identity_a$pack_sha256)
          }, logical(1))))

# Source-only clone, core -> pack session, promotion, reopen, validation, replay,
# composed DAG, certificate, and executable target reproduction.
bundle_root <- tempfile("operation_pack_bundle_")
clone_root <- tempfile("operation_pack_clone_")
workspace <- tempfile("operation_pack_workspace_")
on.exit(unlink(c(bundle_root, clone_root, workspace), recursive = TRUE, force = TRUE), add = TRUE)
bundle <- wb_init_bundle(bundle_root, overwrite = TRUE)
cells <- paste0("c", seq_len(8L))
wb_define_cells(bundle, cells)
wb_attach_metadata(bundle, data.frame(cell_id = cells, signal = seq_along(cells), stringsAsFactors = FALSE))
wb_close_bundle(bundle)
dir.create(clone_root, recursive = TRUE)
stopifnot(all(file.copy(list.files(bundle_root, all.files = TRUE, no.. = TRUE, full.names = TRUE),
                        clone_root, recursive = TRUE)))
bundle <- wb_open_bundle(bundle_root)
source <- wb_session_run_op(wb_session_new(), bundle, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "pack_source", value_type = "continuous",
  missing_policy = "error", overwrite = FALSE, min_cells = 1L))

# Parameter and output violations do not mutate the committed bundle.
state_before <- scworkbench:::.wb_session_source_identity(bundle)$scientific_state_fingerprint
bad_param <- try(wb_session_run_op(source$session, bundle, template_op,
  inputs = list(signal = wb_ref_run(source$run$run_id, "vector"), scale = "bad", min_cells = 1L)), silent = TRUE)
stopifnot(inherits(bad_param, "try-error"), identical(state_before,
  scworkbench:::.wb_session_source_identity(bundle)$scientific_state_fingerprint))
pack_registry <- get(".wb_operation_pack_registry", envir = asNamespace("scworkbench"))
record <- pack_registry$operations[[template_op]]
original_definition <- record$definition
record$definition$runner <- function(bundle, resolved, effective_cells, inputs, ...) {
  list(outputs = list(undeclared = wb_prim_obs_table(data.frame(x = 1))), params = list())
}
pack_registry$operations[[template_op]] <- record
bad_output <- try(wb_session_run_op(source$session, bundle, template_op,
  inputs = list(signal = wb_ref_run(source$run$run_id, "vector"), min_cells = 1L)), silent = TRUE)
record$definition <- original_definition
pack_registry$operations[[template_op]] <- record
stopifnot(inherits(bad_output, "try-error"), grepl("output cardinality mismatch", as.character(bad_output), fixed = TRUE),
          identical(state_before, scworkbench:::.wb_session_source_identity(bundle)$scientific_state_fingerprint))

run <- wb_session_run_op(source$session, bundle, template_op, inputs = list(
  signal = wb_ref_run(source$run$run_id, "vector"), scale = 2, shift = -1, min_cells = 1L))
stopifnot(identical(run$run$operation_pack$pack_sha256, identity_a$pack_sha256),
          identical(as.numeric(run$run$outputs$vector$value), seq_along(cells) * 2 - 1))
session_dag <- wb_session_dag(run$session, bundle = bundle, include_artifacts = TRUE, include_active = TRUE)
stopifnot(all(c(paste0("run:", source$run$run_id), paste0("run:", run$run$run_id)) %in% session_dag$nodes$id))
promotion <- wb_session_promote_current(bundle, run$session, outputs = c("vector", "summary"), created_by = "operation-pack-test")
stopifnot(all(promotion$promoted$status %in% c("ok", "skipped")))
pack_promoted <- promotion$promoted[promotion$promoted$run_id == run$run$run_id & promotion$promoted$status == "ok", , drop = FALSE]
stopifnot(nrow(pack_promoted) == 2L)
vector_artifact <- as.character(pack_promoted$artifact_id[pack_promoted$output == "vector"])
snapshot_id <- unique(as.character(pack_promoted$snapshot_id))
wb_close_bundle(bundle)
bundle <- wb_open_bundle(bundle_root)
vector <- wb_art_load(bundle, vector_artifact, expected_kind = "cell_vector")
stopifnot(identical(as.numeric(vector$value), seq_along(cells) * 2 - 1))
details <- wb_prov_run_details(bundle, run$run$run_id, snapshot_id)
stopifnot(identical(details$run$contract$interface$source_pack$pack_sha256, identity_a$pack_sha256),
          identical(details$run$runtime_fingerprint$operation_pack$pack_sha256, identity_a$pack_sha256))
typed_replay <- wb_prov_run_replay_inputs(bundle, run$run$run_id, snapshot_id)
stopifnot(isTRUE(typed_replay$diagnostics$compatible))
strict <- wb_prov_validate_replay(bundle, snapshot_id = snapshot_id, profile = "strict", strict = TRUE)
stopifnot(isTRUE(strict$summary$valid))
dag <- wb_prov_bundle_dag(bundle, include_snapshots = TRUE)
stopifnot(all(c(paste0("run:", source$run$run_id), paste0("run:", run$run$run_id),
                paste0("artifact:", vector_artifact)) %in% dag$nodes$id))
certificate <- wb_entity_certificate(bundle, "artifact", vector_artifact)
stopifnot(identical(certificate$producer$operation$contract$value$interface$source_pack$pack_sha256,
                    identity_a$pack_sha256))
plan <- wb_target_reproduction_plan(bundle, paste0("artifact:", vector_artifact))
stopifnot(identical(plan$status, "ok"), identical(plan$run_order, c(source$run$run_id, run$run$run_id)))
reproduced <- wb_target_execute_plan(plan, clone_root)
stopifnot(identical(reproduced$status, "promoted_and_verified"), nrow(reproduced$verification) == 2L)
content <- wb_bundle_validation_report(bundle_root, level = "content")
stopifnot(isTRUE(content$ok))

# Durable checkpoint/resume path with the pack operation.
durable <- wb_session_create(bundle, workspace, session_id = "pack_durable")
durable_source <- wb_session_run_op(durable, bundle, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "pack_durable_source", value_type = "continuous",
  missing_policy = "error", overwrite = FALSE, min_cells = 1L))
durable_pack <- wb_session_run_op(durable_source$session, bundle, template_op, inputs = list(
  signal = wb_ref_run(durable_source$run$run_id, "vector"), scale = 3, shift = 1, min_cells = 1L))
resumed <- wb_session_resume(bundle, durable_pack$session$durable$workspace)
durable_promotion <- wb_session_promote_current(bundle, resumed, outputs = "vector", created_by = "operation-pack-test")
stopifnot(any(durable_promotion$promoted$status == "ok"))
invisible(wb_session_discard(durable_promotion$session))

# Once executed, conservative unload fails so staged session contracts cannot be lost.
invisible(expect_pack_error(wb_operation_pack_unload("scwbexample"), "OPERATION_PACK_IN_USE", "wb_operation_pack_in_use"))
wb_close_bundle(bundle)

# Fresh recipient process: pack is installed but absent from the process-local
# registry; read-only inspection/loading/validation succeed and replay/execution
# report the exact required identity without mutating the bundle.
recipient_script <- tempfile("operation_pack_recipient_", fileext = ".R")
writeLines(c(
  "args <- commandArgs(trailingOnly=TRUE)",
  "devtools::load_all(args[[1]], quiet=TRUE)",
  "stopifnot(!nrow(wb_operation_packs()))",
  "b <- wb_open_bundle(args[[2]], read_only=TRUE)",
  "p <- wb_art_load(b,args[[3]],expected_kind='cell_vector')",
  "d <- wb_prov_run_details(b,args[[4]],args[[5]])",
  "r <- wb_prov_run_replay_inputs(b,args[[4]],args[[5]])",
  "v <- wb_bundle_validation_report(args[[2]],level='content')",
  "stopifnot(inherits(p,'wb_primitive'), identical(d$run$contract$interface$source_pack$namespace,'scwbexample'), !r$diagnostics$compatible, any(vapply(r$diagnostics$issues,function(x) identical(x$code,'OPERATION_PACK_REQUIRED'),logical(1))), isTRUE(v$ok))",
  "wb_close_bundle(b); b <- wb_open_bundle(args[[2]])",
  "state_identity <- getFromNamespace('.wb_session_source_identity','scworkbench')",
  "before <- state_identity(b)$scientific_state_fingerprint",
  "e <- tryCatch({wb_session_run_op(wb_session_new(),b,'scwbexample::affine_cell_vector',inputs=list());NULL},error=identity)",
  "stopifnot(inherits(e,'wb_operation_pack_unavailable'), identical(e$code,'OPERATION_PACK_REQUIRED'))",
  "after <- state_identity(b)$scientific_state_fingerprint",
  "stopifnot(identical(before,after)); wb_close_bundle(b); cat('RECIPIENT_OK\\n')"
), recipient_script)
recipient_log <- tempfile("operation_pack_recipient_", fileext = ".log")
recipient_status <- system2(file.path(R.home("bin"), "Rscript"),
  c(shQuote(recipient_script), shQuote(repo), shQuote(bundle_root), shQuote(vector_artifact),
    shQuote(run$run$run_id), shQuote(snapshot_id)), stdout = recipient_log, stderr = recipient_log)
recipient_output <- readLines(recipient_log, warn = FALSE)
if (!identical(recipient_status, 0L) || !any(recipient_output == "RECIPIENT_OK")) {
  stop(paste(c("Recipient subprocess failed:", recipient_output), collapse = "\n"), call. = FALSE)
}

# Static reference-repository boundary proof when its clean checkout is present.
template_root <- normalizePath(file.path(repo, "..", "..", "scworkbench-operation-pack-template-r"),
                               winslash = "/", mustWork = FALSE)
if (dir.exists(template_root)) {
  files <- list.files(file.path(template_root, "R"), pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  text <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
  stopifnot(!grepl("scworkbench:::", text, fixed = TRUE),
            !grepl("dbExecute(", text, fixed = TRUE),
            !grepl("manifest.json", text, fixed = TRUE),
            !grepl("wb_register_", text, fixed = TRUE))
}

# Multi-pack load order and cross-process identity determinism.
fixture_source <- file.path(repo, "tests", "fixtures", "operation-pack-second")
fixture_lib <- tempfile("operation_pack_fixture_lib_")
dir.create(fixture_lib)
install_log <- tempfile("operation_pack_fixture_install_", fileext = ".log")
install_status <- system2(file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-multiarch", "-l", shQuote(fixture_lib), shQuote(fixture_source)),
  stdout = install_log, stderr = install_log)
stopifnot(identical(install_status, 0L))
identity_script <- tempfile("operation_pack_identity_", fileext = ".R")
writeLines(c(
  "args <- commandArgs(trailingOnly=TRUE)",
  "devtools::load_all(args[[1]],quiet=TRUE)",
  "order <- strsplit(args[[3]],',',fixed=TRUE)[[1]]",
  "for(pkg in order) wb_operation_pack_load(pkg,lib.loc=if(pkg=='scworkbenchOperationPackFixture') args[[2]] else NULL)",
  "cat(wb_operation_pack_inspect('scwbexample')$identity$manifest_sha256,'\\n')",
  "cat(wb_operation_pack_inspect('scwbexample')$operations[[1]]$definition_sha256,'\\n')",
  "cat(wb_operation_catalog_identity()$sha256,'\\n')",
  "cat(wb_semantic_catalog()$catalog_sha256,'\\n')"
), identity_script)
run_identity <- function(order) {
  output <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(identity_script), shQuote(repo), shQuote(fixture_lib), shQuote(paste(order, collapse = ","))),
    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  stopifnot(identical(status, 0L))
  hashes <- grep("^[0-9a-f]{64}$", trimws(output), value = TRUE)
  if (!length(hashes)) stop(paste(c("Identity subprocess emitted no hashes:", output), collapse = "\n"), call. = FALSE)
  hashes
}
forward <- run_identity(c(template_package, "scworkbenchOperationPackFixture"))
reverse <- run_identity(c("scworkbenchOperationPackFixture", template_package))
if (length(forward) != 4L || !identical(forward, reverse)) {
  stop(paste0("Catalog identity disagreement: forward=[", paste(forward, collapse = ","),
              "] reverse=[", paste(reverse, collapse = ","), "]"), call. = FALSE)
}

unlink(c(recipient_script, recipient_log, identity_script, fixture_lib, install_log), recursive = TRUE, force = TRUE)
cat("OPERATION_PACK_V1_SUBPROCESS_OK\n")
