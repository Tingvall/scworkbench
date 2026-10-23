.tenx_counts_source_fixture <- function(root, n_features = 3L, n_cells = 2L) {
  dir.create(root, recursive = TRUE)
  sources <- lapply(seq_len(2L), function(library) {
    path <- file.path(root, paste0("library", library)); dir.create(path)
    m <- Matrix::sparseMatrix(i = seq_len(n_cells) %% n_features + 1L,
      j = seq_len(n_cells), x = as.double(seq_len(n_cells) + library),
      dims = c(n_features, n_cells))
    matrix <- file.path(path, "matrix.mtx")
    barcodes <- file.path(path, "barcodes.tsv")
    features <- file.path(path, "features.tsv")
    Matrix::writeMM(m, matrix)
    writeLines(paste0("cell", seq_len(n_cells)), barcodes)
    utils::write.table(data.frame(paste0("gene", seq_len(n_features)),
      paste0("G", seq_len(n_features)), "Gene Expression"), features,
      sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
    data.frame(sample_id = paste0("lib", library), matrix_path = matrix,
      barcodes_path = barcodes, features_path = features)
  })
  do.call(rbind, sources)
}

.tenx_binding_replace <- function(name, replacement) {
  ns <- asNamespace("scworkbench"); original <- get(name, ns)
  unlockBinding(name, ns); assign(name, replacement(original), ns); lockBinding(name, ns)
  function() { unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns) }
}

test_10x_counts_producer_relocation_and_alteration_contract <- function() {
  stopifnot(requireNamespace("BPCells", quietly = TRUE), requireNamespace("Matrix", quietly = TRUE))
  root <- tempfile("tenx_counts_binding_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  for (report in c(FALSE, TRUE)) {
    source_root <- file.path(root, paste0("sources_", report))
    samples <- .tenx_counts_source_fixture(source_root)
    matrix_identities <- 0L; tree_hashes <- 0L
    undo_identity <- .tenx_binding_replace(".wb_prov_payload_identity", function(original)
      function(bundle, prim, ...) {
        if (identical(prim$kind, "matrix")) matrix_identities <<- matrix_identities + 1L
        original(bundle, prim, ...)
      })
    undo_tree <- .tenx_binding_replace(".wb_prov_file_tree_sha256", function(original)
      function(...) { tree_hashes <<- tree_hashes + 1L; original(...) })
    b <- NULL; ro <- NULL
    tryCatch({
      b <- wb_bundle_from_10x_mtx(source_root,
        file.path(root, paste0("original_", report)), sample_table = samples,
        emit_report_artifact = report)
      stopifnot(matrix_identities == 1L)
      before <- tree_hashes
      slice <- wb_slice(b, "RNA_counts", features = "gene2", cells = c("lib1:cell1", "lib2:cell1"))
      stopifnot(identical(as.numeric(slice), c(2, 3)), tree_hashes == before)
      certificate <- wb_entity_certificate(b, "matrix", "RNA_counts")
      stopifnot(identical(certificate$producer$status, "available"),
        identical(certificate$producer$operation$name, "bundle_ingest_10x_mtx_counts"),
        identical(certificate$identity$verification_status, "content_verified"),
        identical(certificate$identity$content_identity_scheme, "scworkbench.content.matrix.fragment-tree.v2"),
        identical(certificate$lifecycle$state, "current"),
        certificate$lifecycle$record$value$provenance_bound == 1L)
      producers <- DBI::dbGetQuery(b$con,
        "SELECT * FROM prov_run_entity_bindings WHERE entity_kind='matrix' AND entity_id='RNA_counts' AND relationship_type IN ('PRODUCES','MATERIALIZES')")
      stopifnot(nrow(producers) == 1L, identical(producers$content_hash[[1L]], certificate$identity$content_sha256))
      stopifnot(wb_finalize_recipient_bundle(b)$ready)
      original <- b$dir; wb_close_bundle(b); b <- NULL
      transfer <- file.path(root, paste0("transfer_", report)); dir.create(transfer)
      stopifnot(file.copy(original, transfer, recursive = TRUE)); unlink(c(original, source_root), recursive = TRUE)
      recipient <- file.path(transfer, basename(original))
      ro <- wb_open_bundle(recipient, read_only = TRUE, validate = TRUE)
      after <- wb_entity_certificate(ro, "matrix", "RNA_counts")
      stopifnot(identical(after$identity$content_sha256, certificate$identity$content_sha256),
        identical(after$identity$verification_status, "content_verified"),
        identical(after$producer$run_id, certificate$producer$run_id))
      report_good <- wb_bundle_validation_report(recipient, "content")
      stopifnot(report_good$ok)
      wb_close_bundle(ro); ro <- NULL
      # Alter only a disposable payload copy; preserve original evidence.
      corrupt_parent <- file.path(root, paste0("corrupt_", report)); dir.create(corrupt_parent)
      stopifnot(file.copy(recipient, corrupt_parent, recursive = TRUE))
      corrupt <- file.path(corrupt_parent, basename(recipient))
      con <- DBI::dbConnect(RSQLite::SQLite(), file.path(corrupt, "db", "app.sqlite"))
      path <- DBI::dbGetQuery(con, "SELECT path FROM matrix_fragments WHERE matrix_id='RNA_counts' ORDER BY fragment_id LIMIT 1")$path[[1L]]
      DBI::dbDisconnect(con)
      files <- list.files(file.path(corrupt, path), recursive = TRUE, full.names = TRUE)
      files <- files[!file.info(files)$isdir & file.info(files)$size > 0]
      stopifnot(length(files) > 0L)
      file <- file(files[[1L]], "r+b")
      byte <- readBin(file, "raw", n = 1L); seek(file, 0L)
      writeBin(as.raw(bitwXor(as.integer(byte), 1L)), file); close(file)
      altered <- wb_bundle_validation_report(corrupt, "content")
      stopifnot(!altered$ok, any(altered$diagnostics$code %in%
        c("ENTITY_CONTENT_IDENTITY_MISMATCH", "DURABLE_CONTENT_IDENTITY_MISMATCH") &
        altered$diagnostics$entity_kind == "matrix"))
    }, finally = {
      if (!is.null(b)) try(wb_close_bundle(b), silent = TRUE)
      if (!is.null(ro)) try(wb_close_bundle(ro), silent = TRUE)
      undo_tree(); undo_identity()
    })
  }
  TRUE
}
