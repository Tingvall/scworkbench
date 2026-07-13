test_public_api_boundary_contract <- function() {
  exports <- getNamespaceExports("scworkbench")
  deprecated_ingest_aliases <- c(
    "bundle_ingest_10x_mtx",
    "bundle_ingest_h5ad",
    "bundle_ingest_sce",
    "bundle_ingest_seurat"
  )
  canonical_ingest_constructors <- c(
    "wb_bundle_from_10x_mtx",
    "wb_bundle_from_h5ad",
    "wb_bundle_from_sce",
    "wb_bundle_from_seurat"
  )

  stopifnot(!any(startsWith(exports, ".")))
  stopifnot(!any(deprecated_ingest_aliases %in% exports))
  stopifnot(all(canonical_ingest_constructors %in% exports))
  invisible(TRUE)
}
