test_recipient_capsule_observation_contract <- function() {
  root <- tempfile("capsule-observation-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "bundle"); b <- wb_init_bundle(path)
  wb_define_cells(b, paste0("c", 1:3), metadata = data.frame(cell_id = paste0("c", 1:3), score = 1:3))
  run <- wb_session_run_op(wb_session_new(), b, "metadata_cell_vector", inputs = list(
    source_column = "score", value_type = "continuous", vector_name = "score", min_cells = 1L))
  promoted <- wb_session_promote_current(b, run$session, outputs = "vector")
  work <- file.path(root, "external"); dir.create(work)
  script <- file.path(work, "report.R")
  writeLines("writeBin(rep(as.raw(0:255),64L),'report.bin')", script)
  sys.source(script, envir = new.env(), chdir = TRUE)
  cap <- wb_capsule_register(b, "observation fixture", inputs = list(
    affected = wb_ref_entity("artifact", promoted$promoted$artifact_id[[1]])), script = script,
    outputs = list(report = list(path = file.path(work, "report.bin"), role = "diagnostic", media_type = "application/octet-stream")),
    purpose = "dataset_specific_reporting", rationale = "Synthetic validation fixture; no scientific transformation",
    catalog_review = list(catalog_identity = "scworkbench.operation_catalog", catalog_version = "0.1.0",
      reviewed_at = "2026-10-24T08:00:00Z", candidate_op_names = list(), decision = "retain_as_capsule"))
  payload <- wb_capsule_output_path(b, cap$capsule_id, "report")
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b)
  change <- function(byte) {
    f <- file(payload, "r+b"); on.exit(close(f)); writeBin(as.raw(byte), f)
  }
  clean <- wb_bundle_validation_report(path, "recipient")
  stopifnot(clean$ok, identical(clean$completed_levels, c("structural", "content", "recipient")))
  change(255L)
  for (level in c("content", "recipient")) {
    bad <- wb_bundle_validation_report(path, level)
    stopifnot(!bad$ok, "CAPSULE_OUTPUT_CONTENT_MISMATCH" %in% bad$diagnostics$code)
  }
  change(0L)
  altered <- FALSE
  progress <- function(event) {
    if (!altered && identical(event$event, "start") && identical(event$check_class, "analysis_capsules")) {
      change(255L); altered <<- TRUE
    }
  }
  during <- wb_bundle_validation_report(path, "recipient", progress = progress)
  stopifnot(altered, !during$ok, "VALIDATION_MUTATED_BUNDLE" %in% during$diagnostics$code,
    !identical(during$pre_validation_fingerprint, during$post_validation_fingerprint))
  change(0L)
  stopifnot(wb_bundle_validation_report(path, "recipient")$ok)
  TRUE
}
