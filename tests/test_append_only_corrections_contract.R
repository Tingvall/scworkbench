test_append_only_corrections_contract <- function() {
  root <- tempfile("correction-bundle-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "bundle"); b <- wb_init_bundle(path)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  cells <- paste0("c", 1:4)
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells, label = c("a", "b", "a", "b")))
  run <- wb_session_run_op(wb_session_new(), b, "metadata_cell_vector", inputs = list(
    source_column = "label", vector_name = "labels", value_type = "categorical", min_cells = 1L))
  promoted <- wb_session_promote_current(b, run$session, outputs = "vector")
  aid <- promoted$promoted$artifact_id[[1]]
  original <- wb_art_load(b, aid)
  original_identity <- wb_entity_certificate(b, "artifact", aid)$identity
  external <- file.path(root, "external"); dir.create(external)
  register <- function(name, text, type = NULL, related = NULL) {
    work <- file.path(external, name); dir.create(work)
    script <- file.path(work, "report.R")
    writeLines(paste0("writeLines(", deparse(text), ", 'report.md')"), script)
    sys.source(script, envir = new.env(), chdir = TRUE)
    wb_capsule_register(b, name = name, inputs = list(affected = wb_ref_entity("artifact", aid)),
      script = script, outputs = list(report = list(path = file.path(work, "report.md"), role = "report", media_type = "text/markdown")),
      parameters = list(statement_kind = if (is.null(type)) "report" else type,
        reason = "Document interpretation separately from retained values", affected_run_id = run$run$run_id),
      command = c("Rscript", "report.R"), created_by = "correction-author",
      purpose = "dataset_specific_reporting", rationale = "Documentary statement about retained evidence; no scientific transformation",
      catalog_review = list(catalog_identity = "scworkbench.operation_catalog", catalog_version = "0.1.0",
        reviewed_at = "2026-10-24T08:00:00Z", candidate_op_names = list(), decision = "retain_as_capsule"),
      family_hint = if (is.null(type)) "terminal-report" else "correction",
      relationships = if (is.null(type)) list() else list(list(type = type, capsule_id = related)),
      limitations = list("Operator declaration; content registration does not establish that this statement is scientifically true."))
  }
  initial <- register("original-report", "Original statement remains immutable.")
  original_report <- readBin(wb_capsule_output_path(b, initial$capsule_id, "report"), "raw", n = 10000)
  correction <- register("correction", "Correction: the prior interpretation needs qualification.", "correction_of", initial$capsule_id)
  dispute <- register("dispute", "Dispute: an alternative interpretation remains open.", "dispute_of", initial$capsule_id)
  stopifnot(identical(wb_art_load(b, aid), original),
    identical(wb_entity_certificate(b, "artifact", aid)$identity, original_identity),
    identical(wb_capsule(b, initial$capsule_id)$manifest_sha256, initial$manifest_sha256),
    identical(wb_entity_certificate(b, "artifact", aid)$lifecycle$state, "current"))
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); unlink(external, recursive = TRUE)
  ro <- wb_open_bundle(path, read_only = TRUE)
  on.exit(wb_close_bundle(ro), add = TRUE)
  discovered <- wb_capsules(ro)
  correction_ids <- discovered$capsule_id[discovered$family_hint == "correction"]
  stopifnot(setequal(correction_ids, c(correction$capsule_id, dispute$capsule_id)))
  dag <- wb_prov_bundle_dag(ro)
  stopifnot(any(dag$edges$edge_type == "CORRECTION_OF"), any(dag$edges$edge_type == "DISPUTE_OF"))
  for (id in correction_ids) {
    cap <- wb_capsule(ro, id)
    parameters <- setNames(lapply(cap$parameters, `[[`, "value"), vapply(cap$parameters, `[[`, "", "name"))
    ins <- wb_capsule_inputs(ro, id); outs <- wb_capsule_outputs(ro, id)
    stopifnot(cap$created_by == "correction-author", nzchar(parameters$reason),
      parameters$affected_run_id == run$run$run_id,
      cap$relationships$related_capsule_id == initial$capsule_id,
      cap$relationships$relationship_type %in% c("correction_of", "dispute_of"),
      ins$entity_id == aid, ins$content_sha256 == original_identity$content_sha256,
      outs$content_sha256 == digest::digest(file = wb_capsule_output_path(ro, id, "report"), algo = "sha256"))
  }
  stopifnot(identical(readBin(wb_capsule_output_path(ro, initial$capsule_id, "report"), "raw", n = 10000), original_report),
    identical(wb_art_load(ro, aid), original), wb_bundle_validation_report(path, "recipient")$ok)
  wb_close_bundle(ro)
  # Test association integrity, not truth of either statement.
  b <- wb_open_bundle(path)
  DBI::dbExecute(b$con, "UPDATE analysis_capsule_relationships SET relationship_type='variant_of' WHERE capsule_id=?;", params = list(correction$capsule_id))
  wb_close_bundle(b)
  bad <- wb_bundle_validation_report(path, "content")
  stopifnot(!bad$ok, "CAPSULE_RELATIONSHIP_MANIFEST_REGISTRY_DISAGREEMENT" %in% bad$diagnostics$code)
  TRUE
}
