test_imported_state_provenance_identity_contract <- function() {
  required <- c("BPCells", "SingleCellExperiment", "SummarizedExperiment", "S4Vectors", "Matrix", "rhdf5")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  make_sce <- function(order = seq_len(6L), swap_values = FALSE) {
    ids <- paste0("cell_", seq_len(6L))
    counts <- Matrix::Matrix(matrix(seq_len(24L), 4L, 6L,
      dimnames = list(paste0("gene_", seq_len(4L)), ids)), sparse = TRUE)
    md <- S4Vectors::DataFrame(
      category = factor(c("a", "a", "b", "b", "c", NA)),
      text = c("one", "two", NA, "four", "five", "six"),
      integer = c(1L, NA, 3L, 4L, 5L, 6L),
      real = c(1.25, 2.5, NA, 4.75, 5, 6.125),
      logical = c(TRUE, FALSE, NA, TRUE, FALSE, TRUE), row.names = ids
    )
    if (isTRUE(swap_values)) md$integer[c(1L, 2L)] <- md$integer[c(2L, 1L)]
    sce <- SingleCellExperiment::SingleCellExperiment(
      assays = list(counts = counts[, order, drop = FALSE]), colData = md[order, , drop = FALSE]
    )
    SingleCellExperiment::reducedDim(sce, "UMAP") <- matrix(
      c(seq_len(6L), rev(seq_len(6L))), 6L, 2L,
      dimnames = list(ids[order], c("UMAP1", "UMAP2"))
    )
    sce
  }
  source_file <- tempfile("imported_state_source_", fileext = ".rds")
  saveRDS(list(fixture = "external declaration"), source_file)
  sha <- wb_source_sha256(source_file)
  source_identity <- list(source_type = "SingleCellExperiment", inputs = list(list(
    scope = "external_file", source_id = "sce_fixture", accession = "SCE_FIXTURE",
    path = source_file, role = "source_object", format = "rds", sha256 = sha,
    checksum = sha, checksum_algorithm = "sha256", bundled = FALSE
  )))
  roots <- character()
  on.exit(unlink(c(roots, source_file), recursive = TRUE, force = TRUE), add = TRUE)
  ingest <- function(sce) {
    root <- tempfile("scwb_imported_state_"); roots <<- c(roots, root)
    wb_bundle_from_sce(sce, root, overwrite = TRUE, source_identity = source_identity,
                       categorical_cols = "category", created_by = "identity-contract")
  }

  b <- ingest(make_sce())
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  for (subject in list(c("matrix", "counts"), c("space", "UMAP"))) {
    certificate <- wb_entity_certificate(b, subject[[1L]], subject[[2L]])
    stopifnot(identical(certificate$producer$status, "available"),
              identical(certificate$identity$verification_status, "content_verified"))
    producers <- DBI::dbGetQuery(b$con, paste(
      "SELECT snapshot_id,run_id FROM prov_run_entity_bindings WHERE entity_kind=? AND entity_id=?",
      "AND relationship_type IN ('PRODUCES','MATERIALIZES');"
    ), params = list(subject[[1L]], subject[[2L]]))
    stopifnot(nrow(producers) == 1L)
    upstream <- DBI::dbGetQuery(b$con, paste(
      "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=?",
      "AND entity_kind='external_source' AND relationship_type='CONSUMES';"
    ), params = list(producers$snapshot_id[[1L]], producers$run_id[[1L]]))$n[[1L]]
    stopifnot(upstream >= 1L)
  }
  aggregate <- DBI::dbGetQuery(b$con,
    "SELECT snapshot_id,run_id FROM prov_runs WHERE op_name='bundle_ingest_singlecellexperiment';")
  stopifnot(nrow(aggregate) == 1L)
  aggregate_competitors <- DBI::dbGetQuery(b$con, paste(
    "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=?",
    "AND entity_kind IN ('matrix','space') AND relationship_type IN ('PRODUCES','MATERIALIZES');"
  ), params = list(aggregate$snapshot_id[[1L]], aggregate$run_id[[1L]]))$n[[1L]]
  stopifnot(aggregate_competitors == 0L)

  fields <- subset(wb_metadata_fields(b), is_core == 0L)
  identities <- DBI::dbGetQuery(b$con,
    "SELECT * FROM metadata_field_identities WHERE is_current=1 ORDER BY field_id;")
  stopifnot(nrow(identities) == nrow(fields),
            all(grepl("^[0-9a-f]{64}$", identities$content_sha256)),
            all(identities$content_identity_scheme == "scworkbench.content.metadata-field.cell-id-fold.v1"))
  for (fid in fields$field_id) {
    certificate <- wb_entity_certificate(b, "metadata_field", fid)
    stopifnot(identical(certificate$producer$status, "available"),
              identical(certificate$identity$verification_status, "content_verified"),
              length(certificate$producer$history) == 1L)
  }
  DBI::dbGetQuery(b$con, "PRAGMA wal_checkpoint(TRUNCATE);")
  coverage_report <- wb_bundle_validation_report(b$dir, level = "content")
  coverage <- coverage_report$content_coverage
  metadata_coverage <- coverage[coverage$entity_kind == "metadata_field", , drop = FALSE]
  stopifnot(nrow(metadata_coverage) == nrow(fields),
            all(metadata_coverage$verification_status == "content_verified"))

  graph <- wb_prov_bundle_dag(b, include_snapshots = TRUE, include_registry_mutations = TRUE)
  stopifnot(!anyDuplicated(graph$nodes$node_id), !anyDuplicated(graph$edges$edge_id))

  base_hash <- stats::setNames(identities$content_sha256, identities$field_id)
  b_perm <- ingest(make_sce(c(6L, 2L, 5L, 1L, 4L, 3L)))
  perm <- DBI::dbGetQuery(b_perm$con, "SELECT field_id,content_sha256 FROM metadata_field_identities WHERE is_current=1;")
  perm_names <- wb_metadata_fields(b_perm); perm$source_name <- perm_names$source_name[match(perm$field_id, perm_names$field_id)]
  base_names <- fields$source_name[match(names(base_hash), fields$field_id)]
  stopifnot(identical(unname(base_hash[match(perm$source_name, base_names)]), perm$content_sha256))
  wb_close_bundle(b_perm)
  b_swap <- ingest(make_sce(swap_values = TRUE))
  swapped <- merge(subset(wb_metadata_fields(b_swap), is_core == 0L),
                   DBI::dbGetQuery(b_swap$con, "SELECT field_id,content_sha256 FROM metadata_field_identities WHERE is_current=1;"), by = "field_id")
  stopifnot(swapped$content_sha256[swapped$source_name == "integer"] != base_hash[fields$field_id[fields$source_name == "integer"]])
  wb_close_bundle(b_swap)

  prior_fields <- DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY field_id;")
  prior_ids <- DBI::dbGetQuery(b$con, "SELECT * FROM metadata_field_identities ORDER BY identity_id;")
  old_hook <- getOption("scworkbench.metadata_writer_test_hook")
  on.exit(options(scworkbench.metadata_writer_test_hook = old_hook), add = TRUE)
  options(scworkbench.metadata_writer_test_hook = function(event, ...) if (identical(event, "after_identity_publication")) stop("forced identity publication fault"))
  failed <- try(wb_attach_metadata(b, data.frame(cell_id = paste0("cell_", seq_len(6L)), doomed = seq_len(6L))), silent = TRUE)
  options(scworkbench.metadata_writer_test_hook = old_hook)
  stopifnot(inherits(failed, "try-error"), identical(prior_fields, DBI::dbGetQuery(b$con, "SELECT * FROM metadata_fields ORDER BY field_id;")),
            identical(prior_ids, DBI::dbGetQuery(b$con, "SELECT * FROM metadata_field_identities ORDER BY identity_id;")),
            !"doomed" %in% DBI::dbListFields(b$con, "cells"))

  integer_field <- fields[fields$source_name == "integer", , drop = FALSE]
  wb_attach_metadata(b, data.frame(cell_id = paste0("cell_", seq_len(6L)), integer = 11:16),
                     field_refs = list(wb_ref_metadata_field(integer_field$field_id)), source = "compatible-update")
  current <- DBI::dbGetQuery(b$con, "SELECT * FROM metadata_field_identities WHERE field_id=? ORDER BY identity_version;", params = list(integer_field$field_id))
  updated_certificate <- wb_entity_certificate(b, "metadata_field", integer_field$field_id)
  stopifnot(nrow(current) == 2L, sum(current$is_current) == 1L,
            identical(updated_certificate$producer$status, "available"),
            length(updated_certificate$producer$history) == 2L)
  DBI::dbGetQuery(b$con, "PRAGMA wal_checkpoint(TRUNCATE);")

  # Independent corruption checks use disposable copies of the committed bundle.
  corruption_check <- function(sql, params = list()) {
    copy_root <- tempfile("scwb_metadata_corrupt_"); roots <<- c(roots, copy_root)
    dir.create(copy_root)
    stopifnot(file.copy(b$dir, copy_root, recursive = TRUE))
    candidate <- if (file.exists(file.path(copy_root, "app.sqlite"))) copy_root else file.path(copy_root, basename(b$dir))
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(candidate, "db", "app.sqlite"))
    if (is.function(sql)) sql(con) else if (length(params)) DBI::dbExecute(con, sql, params = params) else DBI::dbExecute(con, sql)
    DBI::dbGetQuery(con, "PRAGMA wal_checkpoint(TRUNCATE);")
    DBI::dbDisconnect(con)
    report <- wb_bundle_validation_report(candidate, level = "content")
    stopifnot(any(report$diagnostics$code == "DURABLE_CONTENT_IDENTITY_MISMATCH" & report$diagnostics$entity_kind == "metadata_field"))
  }
  text_field <- fields[fields$source_name == "text", , drop = FALSE]
  corruption_check(paste0("UPDATE cells SET ", DBI::dbQuoteIdentifier(b$con, text_field$storage_name), "='mutated' WHERE cell_id='cell_1';"))
  corruption_check(paste0("UPDATE cells SET ", DBI::dbQuoteIdentifier(b$con, text_field$storage_name), "=NULL WHERE cell_id='cell_1';"))
  corruption_check("UPDATE metadata_fields SET storage_type='REAL' WHERE field_id=?;", list(text_field$field_id))
  other_field <- fields[fields$source_name == "real", , drop = FALSE]
  corruption_check(function(con) {
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con, "UPDATE metadata_fields SET storage_name='__identity_swap' WHERE field_id=?;", params=list(text_field$field_id))
      DBI::dbExecute(con, "UPDATE metadata_fields SET storage_name=? WHERE field_id=?;", params=list(text_field$storage_name, other_field$field_id))
      DBI::dbExecute(con, "UPDATE metadata_fields SET storage_name=? WHERE field_id=?;", params=list(other_field$storage_name, text_field$field_id))
    })
  })

  unlink(source_file)
  wb_finalize_recipient_bundle(b); wb_close_bundle(b); b <- NULL
  ro <- wb_open_bundle(roots[[1L]], read_only = TRUE, validate = TRUE)
  on.exit(try(wb_close_bundle(ro), silent = TRUE), add = TRUE)
  stopifnot(isTRUE(ro$read_only), isTRUE(wb_validate_bundle(ro$dir, read_only = TRUE)))
  final_report <- wb_bundle_validation_report(ro$dir, level = "recipient")
  stopifnot(isTRUE(final_report$ok), any(final_report$diagnostics$code == "EXTERNAL_SOURCE_UNVERIFIABLE"))
  invisible(TRUE)
}
