.local_source_tiny_h5ad <- function(path) {
  rhdf5::h5createFile(path)
  rhdf5::h5write(matrix(seq_len(12L), 3L, 4L), path, "X")
  for (group in c("obs", "var", "obsm", "varm", "obsp", "varp", "layers")) rhdf5::h5createGroup(path, group)
  rhdf5::h5write(paste0("c", 1:4), path, "obs/_index")
  rhdf5::h5write(paste0("g", 1:3), path, "var/_index")
  file <- rhdf5::H5Fopen(path)
  rhdf5::h5writeAttribute("anndata", file, "encoding-type")
  rhdf5::h5writeAttribute("0.1.0", file, "encoding-version")
  for (name in c("obs", "var")) {
    group <- rhdf5::H5Gopen(file, name)
    rhdf5::h5writeAttribute("_index", group, "_index")
    rhdf5::h5writeAttribute("_index", group, "column-order")
    rhdf5::h5writeAttribute("dataframe", group, "encoding-type")
    rhdf5::h5writeAttribute("0.2.0", group, "encoding-version")
    rhdf5::H5Gclose(group)
  }
  rhdf5::H5Fclose(file)
}

.local_source_transfer <- function(bundle, parent) {
  stopifnot(wb_finalize_recipient_bundle(bundle)$ready)
  source <- bundle$dir
  wb_close_bundle(bundle)
  dir.create(parent)
  stopifnot(file.copy(source, parent, recursive = TRUE))
  file.path(parent, basename(source))
}

test_local_source_no_invented_accession_contract <- function() {
  path <- tempfile(fileext = ".rds"); saveRDS(list(x = 1L), path)
  on.exit(unlink(path), add = TRUE)
  expected <- wb_source_sha256(path)
  ns <- asNamespace("scworkbench"); original <- get("wb_source_sha256", ns); calls <- 0L
  unlockBinding("wb_source_sha256", ns)
  assign("wb_source_sha256", function(path) { calls <<- calls + 1L; original(path) }, ns)
  lockBinding("wb_source_sha256", ns)
  on.exit({unlockBinding("wb_source_sha256", ns);assign("wb_source_sha256", original, ns);lockBinding("wb_source_sha256", ns)}, add = TRUE)
  source <- wb_source_input(path = path, source_id = "local_rds", role = "source_object",
    format = "rds", scope = "external_file")
  stopifnot(calls == 1L, is.null(source$accession), identical(source$sha256, expected),
    identical(source$checksum, expected))
  checked <- wb_source_preflight(list(inputs = list(source)), verify_files = FALSE)
  stopifnot(checked$valid, calls == 1L)
  public <- source; public$scope <- "public_file"
  stopifnot("SOURCE_ACCESSION_MISSING" %in% wb_source_preflight(list(inputs = list(public)),
    verify_files = FALSE, strict = FALSE)$diagnostics$code)
  broken <- source; broken$sha256 <- broken$checksum <- strrep("0", 64L)
  stopifnot("SOURCE_CHECKSUM_MISMATCH" %in% wb_source_preflight(list(inputs = list(broken)),
    verify_files = TRUE, strict = FALSE)$diagnostics$code)
  TRUE
}

test_local_rds_source_relocation_contract <- function() {
  required <- c("BPCells", "SingleCellExperiment", "SummarizedExperiment", "Matrix")
  stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
  root <- tempfile("rds_source_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "input.rds")
  matrix <- Matrix::Matrix(matrix(seq_len(12L), 3L, dimnames = list(paste0("g", 1:3), paste0("c", 1:4))), sparse = TRUE)
  sce <- SingleCellExperiment::SingleCellExperiment(assays = list(counts = matrix))
  saveRDS(sce, path); expected <- wb_source_sha256(path)
  b <- wb_bundle_from_sce(path, file.path(root, "original.bundle"), emit_report_artifact = FALSE,
    created_by = "source-contract")
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  src <- wb_prov_source_inputs(b)
  external <- src[src$source_id == "sce_rds", , drop = FALSE]
  stopifnot(nrow(external) > 0L, all(is.na(external$accession)),
    all(external$format == "rds"), all(external$checksum_value == expected))
  relocated <- .local_source_transfer(b, file.path(root, "recipient")); b <- NULL
  unlink(c(path, file.path(root, "original.bundle")), recursive = TRUE)
  ro <- wb_open_bundle(relocated, read_only = TRUE, validate = TRUE)
  on.exit(wb_close_bundle(ro), add = TRUE)
  source <- wb_entity_certificate(ro, "external_source", "sce_rds")
  stopifnot(identical(source$details$availability$status, "external_uninspected"),
    identical(source$details$availability$reason, "identified_source_not_bundled"),
    identical(source$details$checksum$value, expected),
    identical(source$identity$verification_level, "declaration"),
    nrow(wb_prov_source_identity(ro, "counts")) == 1L,
    wb_bundle_validation_report(relocated, "recipient")$ok)
  TRUE
}

test_local_h5ad_conversion_source_relocation_contract <- function() {
  stopifnot(requireNamespace("zellkonverter", quietly = TRUE), requireNamespace("rhdf5", quietly = TRUE))
  root <- tempfile("h5ad_source_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "input.h5ad"); .local_source_tiny_h5ad(path)
  expected <- wb_source_sha256(path)
  old <- options(scworkbench.h5ad_reader = "R"); on.exit(options(old), add = TRUE)
  identity <- list(dataset_name = "local tiny H5AD", attribution = "synthetic source contract",
    inputs = list(wb_source_input(path = path, source_id = "local_h5ad", role = "source_object",
      format = "h5ad", scope = "external_file")))
  b <- wb_bundle_from_h5ad(path, file.path(root, "original.bundle"),
    emit_report_artifact = FALSE, source_identity = identity)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  relocated <- .local_source_transfer(b, file.path(root, "recipient")); b <- NULL
  unlink(c(path, file.path(root, "original.bundle")), recursive = TRUE)
  ro <- wb_open_bundle(relocated, read_only = TRUE, validate = TRUE)
  on.exit(wb_close_bundle(ro), add = TRUE)
  src <- wb_prov_source_inputs(ro)
  parent <- src[src$source_id == "local_h5ad", , drop = FALSE]
  child <- src[src$source_id == "local_h5ad__converted_sce", , drop = FALSE]
  stopifnot(nrow(parent) > 0L, all(parent$checksum_value == expected), all(is.na(parent$accession)),
    all(child$parent_source_id == "local_h5ad"), all(child$source_relation == "CONVERTS_TO"),
    all(is.na(child$checksum_value)))
  declared <- jsonlite::fromJSON(wb_prov_source_identity(ro, "X")$source_identity_json[[1L]], simplifyVector = FALSE)
  stopifnot(identical(declared$attribution, identity$attribution),
    identical(declared$nested_ingestion$authoritative_source_id, "local_h5ad"))
  certificate <- wb_entity_certificate(ro, "external_source", "local_h5ad")
  stopifnot(identical(certificate$details$availability$status, "external_uninspected"),
    identical(certificate$details$checksum$value, expected),
    wb_bundle_validation_report(relocated, "recipient")$ok)
  TRUE
}
