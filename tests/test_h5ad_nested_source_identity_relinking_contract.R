test_h5ad_nested_source_identity_relinking_contract <- function() {
  required <- c("BPCells", "SingleCellExperiment", "SummarizedExperiment", "S4Vectors", "Matrix", "rhdf5", "zellkonverter")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  roots <- character()
  source_path <- tempfile("nested_source_", fileext = ".h5ad")
  rhdf5::h5createFile(source_path)
  on.exit(unlink(c(roots, source_path), recursive = TRUE, force = TRUE), add = TRUE)

  cells <- paste0("cell_", seq_len(4L))
  features <- paste0("gene_", seq_len(3L))
  rhdf5::h5write(matrix(seq_len(12L), 3L, 4L), source_path, "X")
  for (group in c("obs", "var", "obsm", "varm", "obsp", "varp", "layers")) {
    rhdf5::h5createGroup(source_path, group)
  }
  rhdf5::h5write(cells, source_path, "obs/_index")
  rhdf5::h5write(c("a", "a", "b", "b"), source_path, "obs/group")
  rhdf5::h5write(c("x", "y", "x", "y"), source_path, "obs/batch")
  rhdf5::h5write(features, source_path, "var/_index")
  rhdf5::h5write(paste0("G", seq_len(3L)), source_path, "var/symbol")
  rhdf5::h5write(matrix(seq_len(8L) / 10, 2L, 4L), source_path, "obsm/PCA")
  h5 <- rhdf5::H5Fopen(source_path)
  obs <- rhdf5::H5Gopen(h5, "obs")
  var <- rhdf5::H5Gopen(h5, "var")
  rhdf5::h5writeAttribute("anndata", h5, "encoding-type")
  rhdf5::h5writeAttribute("0.1.0", h5, "encoding-version")
  rhdf5::h5writeAttribute("_index", obs, "_index")
  rhdf5::h5writeAttribute(c("_index", "group", "batch"), obs, "column-order")
  rhdf5::h5writeAttribute("dataframe", obs, "encoding-type")
  rhdf5::h5writeAttribute("0.2.0", obs, "encoding-version")
  rhdf5::h5writeAttribute("_index", var, "_index")
  rhdf5::h5writeAttribute(c("_index", "symbol"), var, "column-order")
  rhdf5::h5writeAttribute("dataframe", var, "encoding-type")
  rhdf5::h5writeAttribute("0.2.0", var, "encoding-version")
  rhdf5::H5Gclose(obs); rhdf5::H5Gclose(var); rhdf5::H5Fclose(h5)

  sha <- wb_source_sha256(source_path)
  public_identity <- list(
    schema = "scworkbench.source_identity.v2",
    dataset_name = "synthetic nested H5AD",
    inputs = list(list(
      scope = "public_file", source_id = "synthetic_h5ad", accession = "SYNTHETIC_H5AD",
      path = source_path, uri = "https://example.org/SYNTHETIC_H5AD/source.h5ad",
      role = "source_object", format = "h5ad", sha256 = sha, checksum = sha,
      checksum_algorithm = "sha256", bundled = FALSE, accession_derived = TRUE
    ))
  )
  old_reader <- getOption("scworkbench.h5ad_reader")
  old_fault <- getOption("scworkbench.h5ad_ingestion_fault_hook")
  on.exit(options(scworkbench.h5ad_reader = old_reader,
                  scworkbench.h5ad_ingestion_fault_hook = old_fault), add = TRUE)
  options(scworkbench.h5ad_reader = "R")

  ingest <- function(report = TRUE, identity = public_identity, label = "ok") {
    root <- tempfile(paste0("scwb_h5ad_nested_", label, "_")); roots <<- c(roots, root)
    wb_bundle_from_h5ad(
      source_path, root, overwrite = TRUE, categorical_cols = "group",
      emit_report_artifact = report, source_identity = identity,
      created_by = "nested-source-contract"
    )
  }
  producer <- function(bundle, kind, id) DBI::dbGetQuery(bundle$con, paste(
    "SELECT snapshot_id,run_id FROM prov_run_entity_bindings WHERE entity_kind=? AND entity_id=?",
    "AND relationship_type IN ('PRODUCES','MATERIALIZES') ORDER BY snapshot_id,run_id;"
  ), params = list(kind, id))

  b <- ingest()
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  stopifnot(identical(wb_matrices(b)$matrix_id, "X"), "PCA" %in% wb_spaces(b)$space_id)
  matrix_producer <- producer(b, "matrix", "X")
  space_producer <- producer(b, "space", "PCA")
  stopifnot(nrow(matrix_producer) == 1L, nrow(space_producer) == 1L)

  reports <- wb_art_list(b)
  report_ids <- reports$artifact_id[reports$name == "container_ingest_report"]
  dispositions <- lapply(report_ids, function(id) {
    report <- wb_art_load(b, id, expected_kind = "obs_table")$table
    jsonlite::fromJSON(report$categorical_dispositions_json[[1]], simplifyVector = FALSE)
  })
  stopifnot(length(dispositions) == 2L, identical(dispositions[[1]], dispositions[[2]]),
    dispositions[[1]][[1]]$column == "group", dispositions[[1]][[1]]$status == "created")
  identities <- wb_prov_source_identity(b, "X")
  stopifnot(nrow(identities) == 1L)
  declared <- jsonlite::fromJSON(identities$source_identity_json[[1L]], simplifyVector = FALSE)
  stopifnot(identical(declared$nested_ingestion$schema, "scworkbench.nested_ingestion.v1"),
            identical(declared$nested_ingestion$authoritative_source_id, "synthetic_h5ad"),
            identical(declared$nested_ingestion$conversion_source_id, "synthetic_h5ad__converted_sce"),
            length(declared$inputs) == 2L)

  source_inputs <- wb_prov_source_inputs(b, matrix_producer$run_id[[1L]])
  stopifnot(setequal(source_inputs$source_id, c("synthetic_h5ad", "synthetic_h5ad__converted_sce")))
  conversion <- source_inputs[source_inputs$scope == "in_memory", , drop = FALSE]
  external <- source_inputs[source_inputs$scope == "public_file", , drop = FALSE]
  stopifnot(nrow(conversion) == 1L, nrow(external) == 1L,
            identical(conversion$parent_source_id[[1L]], "synthetic_h5ad"),
            identical(conversion$source_relation[[1L]], "CONVERTS_TO"),
            identical(external$checksum_value[[1L]], sha))

  for (subject in list(c("matrix", "X"), c("space", "PCA"))) {
    cert <- wb_entity_certificate(b, subject[[1L]], subject[[2L]])
    upstream <- vapply(cert$relationships$upstream$items, `[[`, character(1), "node_id")
    stopifnot(identical(cert$producer$status, "available"),
              sum(upstream == "external_source:synthetic_h5ad") == 1L,
              sum(upstream == "in_memory_source:synthetic_h5ad__converted_sce") == 1L)
  }

  fields <- wb_metadata_fields(b, include_core = FALSE)$field_id
  feature_artifact <- subset(wb_art_list(b), type == "feature_table" & name == "X_feature_metadata")$artifact_id
  stopifnot(length(feature_artifact) == 1L)
  for (fid in fields) {
    p <- producer(b, "metadata_field", fid)
    if (nrow(p) != 1L) stop("metadata field producer count for ", fid, ": ", nrow(p), call. = FALSE)
    stopifnot("synthetic_h5ad" %in% wb_prov_source_inputs(b, p$run_id[[1L]])$source_id)
  }
  feature_producer <- producer(b, "artifact", feature_artifact)
  stopifnot(nrow(feature_producer) == 1L,
    "synthetic_h5ad" %in% wb_prov_source_inputs(b, feature_producer$run_id[[1L]])$source_id)

  report_runs <- DBI::dbGetQuery(b$con,
    "SELECT snapshot_id,run_id FROM prov_runs WHERE op_name='bundle_ingest_anndata_h5ad';")
  stopifnot(nrow(report_runs) == 1L)
  report_claims <- DBI::dbGetQuery(b$con, paste(
    "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=?",
    "AND entity_kind IN ('matrix','space','metadata_field') AND relationship_type IN ('PRODUCES','MATERIALIZES');"
  ), params = unname(as.list(report_runs[1L, ])))$n[[1L]]
  stopifnot(report_claims == 0L)

  before_inputs <- wb_prov_source_inputs(b)
  scworkbench:::.wb_prov_link_source_to_existing_producers(
    b, "X", "PCA", declared, artifact_ids = feature_artifact,
    metadata_field_ids = fields)
  stopifnot(identical(before_inputs, wb_prov_source_inputs(b)),
            nrow(producer(b, "matrix", "X")) == 1L,
            nrow(producer(b, "space", "PCA")) == 1L)

  no_report <- ingest(FALSE, label = "no_report")
  stopifnot(!any(wb_art_list(no_report)$name == "container_ingest_report"),
            nrow(wb_prov_source_identity(no_report, "X")) == 1L,
            "synthetic_h5ad" %in% wb_prov_source_inputs(no_report)$source_id,
            nrow(producer(no_report, "matrix", "X")) == 1L,
            nrow(producer(no_report, "space", "PCA")) == 1L)
  wb_close_bundle(no_report)

  unrelated <- list(source_type = "SingleCellExperiment", inputs = list(list(
    scope = "in_memory", source_id = "unrelated", uri = "scworkbench-ingestion://unrelated",
    role = "source_object", format = "SingleCellExperiment", bundled = FALSE)))
  unrelated_error <- try(scworkbench:::.wb_prov_link_source_to_existing_producers(
    b, "X", character(), unrelated), silent = TRUE)
  stopifnot(inherits(unrelated_error, "try-error"),
            grepl("Conflicting immutable source identity", as.character(unrelated_error), fixed = TRUE))

  forged <- declared
  forged$inputs[[2L]]$parent_source_id <- "unrelated"
  forged_error <- try(wb_source_preflight(forged, verify_files = FALSE, strict = TRUE), silent = TRUE)
  stopifnot(inherits(forged_error, "try-error"),
            grepl("SOURCE_NESTED_CHILD_FORGED", as.character(forged_error), fixed = TRUE))
  conflicting <- public_identity
  conflicting$inputs[[1L]]$source_id <- "other_h5ad"
  conflicting$inputs[[1L]]$accession <- "OTHER"
  conflict_error <- try(scworkbench:::.wb_prov_link_source_to_existing_producers(
    b, "X", character(), conflicting), silent = TRUE)
  stopifnot(inherits(conflict_error, "try-error"), identical(before_inputs, wb_prov_source_inputs(b)))

  unrelated_path <- tempfile("unrelated_h5ad_", fileext = ".h5ad")
  rhdf5::h5createFile(unrelated_path)
  roots <- c(roots, unrelated_path)
  unrelated_sha <- wb_source_sha256(unrelated_path)
  unrelated_outer <- public_identity
  unrelated_outer$inputs[[1L]]$path <- unrelated_path
  unrelated_outer$inputs[[1L]]$sha256 <- unrelated_sha
  unrelated_outer$inputs[[1L]]$checksum <- unrelated_sha
  unrelated_root <- tempfile("scwb_h5ad_unrelated_outer_"); roots <- c(roots, unrelated_root)
  unrelated_outer_error <- try(wb_bundle_from_h5ad(
    source_path, unrelated_root, overwrite = TRUE, source_identity = unrelated_outer), silent = TRUE)
  stopifnot(inherits(unrelated_outer_error, "try-error"),
            grepl("exactly one checksummed external H5AD input", as.character(unrelated_outer_error), fixed = TRUE),
            !dir.exists(unrelated_root))

  mismatched <- public_identity
  mismatched$inputs[[1L]]$sha256 <- paste(rep("0", 64L), collapse = "")
  mismatched$inputs[[1L]]$checksum <- mismatched$inputs[[1L]]$sha256
  mismatch_root <- tempfile("scwb_h5ad_mismatch_"); roots <- c(roots, mismatch_root)
  mismatch_error <- try(wb_bundle_from_h5ad(source_path, mismatch_root, overwrite = TRUE,
    source_identity = mismatched), silent = TRUE)
  stopifnot(inherits(mismatch_error, "try-error"), !dir.exists(file.path(mismatch_root, "db")))

  for (boundary in c("after_nested_sce_ingestion", "before_outer_report_publication", "after_outer_report_publication")) {
    options(scworkbench.h5ad_ingestion_fault_hook = local({
      wanted <- boundary
      function(boundary, ...) if (identical(boundary, wanted)) stop("injected H5AD publication fault")
    }))
    fault_root <- tempfile(paste0("scwb_h5ad_fault_", boundary, "_")); roots <- c(roots, fault_root)
    failed <- try(wb_bundle_from_h5ad(source_path, fault_root, overwrite = TRUE,
      source_identity = public_identity), silent = TRUE)
    stopifnot(inherits(failed, "try-error"), !dir.exists(file.path(fault_root, "db")),
              file.exists(file.path(fault_root, "INGEST_FAILED.json")))
  }
  options(scworkbench.h5ad_ingestion_fault_hook = old_fault)

  DBI::dbGetQuery(b$con, "PRAGMA wal_checkpoint(TRUNCATE);")
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b); b <- NULL
  transfer_parent <- tempfile("scwb_h5ad_transfer_"); roots <- c(roots, transfer_parent)
  dir.create(transfer_parent)
  stopifnot(file.copy(roots[[1L]], transfer_parent, recursive = TRUE))
  transferred <- file.path(transfer_parent, basename(roots[[1L]]))
  ro <- wb_open_bundle(transferred, read_only = TRUE, validate = TRUE)
  on.exit(try(wb_close_bundle(ro), silent = TRUE), add = TRUE)
  ro_source <- wb_prov_source_inputs(ro)
  ro_cert <- wb_entity_certificate(ro, "matrix", "X")
  ro_upstream <- vapply(ro_cert$relationships$upstream$items, `[[`, character(1), "node_id")
  stopifnot(isTRUE(ro$read_only), "synthetic_h5ad" %in% ro_source$source_id,
            all(ro_source$checksum_value[ro_source$source_id == "synthetic_h5ad"] == sha),
            "external_source:synthetic_h5ad" %in% ro_upstream,
            isTRUE(wb_bundle_validation_report(transferred, level = "recipient")$ok))

  corrupt_parent <- tempfile("scwb_h5ad_corrupt_parent_"); roots <- c(roots, corrupt_parent)
  dir.create(corrupt_parent)
  stopifnot(file.copy(transferred, corrupt_parent, recursive = TRUE))
  corrupt <- file.path(corrupt_parent, basename(transferred))
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(corrupt, "db", "app.sqlite"))
  child <- DBI::dbGetQuery(con, "SELECT snapshot_id,run_id,source_id,source_json FROM prov_source_inputs WHERE source_id='synthetic_h5ad__converted_sce' LIMIT 1;")
  child_json <- jsonlite::fromJSON(child$source_json[[1L]], simplifyVector = FALSE)
  child_json$parent_source_id <- "missing_parent"
  DBI::dbExecute(con, "UPDATE prov_source_inputs SET source_json=? WHERE snapshot_id=? AND run_id=? AND source_id=?;",
    params = list(jsonlite::toJSON(child_json, auto_unbox = TRUE, null = "null"), child$snapshot_id[[1L]], child$run_id[[1L]], child$source_id[[1L]]))
  DBI::dbDisconnect(con)
  corrupt_report <- wb_bundle_validation_report(corrupt, level = "content")
  stopifnot(any(corrupt_report$diagnostics$code == "SOURCE_NESTED_PARENT_MISSING"))

  invisible(TRUE)
}
