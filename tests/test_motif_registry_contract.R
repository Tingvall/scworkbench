test_motif_registry_contract <- function(bundle_dir) {
  tmp <- tempfile("scwb_motif_registry_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("cell", seq_len(4))
  wb_define_cells(b, cells)
  mat <- Matrix::Matrix(
    matrix(
      c(1L, 0L, 2L, 1L, 0L, 3L, 1L, 1L),
      nrow = 2,
      dimnames = list(c("chr1:100-199", "chr1:300-399"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "ATAC_counts", mat = mat, feature_type = "peak")

  wb_matrix_set_genome(
    b,
    matrix_id = "ATAC_counts",
    organism = "mouse",
    genome_build = "mm10",
    genome_provider = "BSgenome.Mmusculus.UCSC.mm10"
  )

  mats <- wb_matrices(b)
  row <- mats[as.character(mats$matrix_id) == "ATAC_counts", , drop = FALSE]
  stopifnot(nrow(row) == 1L)
  stopifnot(identical(as.character(row$organism[1]), "mouse"))
  stopifnot(identical(as.character(row$genome_build[1]), "mm10"))

  wb_motif_library_register(
    b,
    motif_library = "jaspar2020_core_mouse",
    source_type = "jaspar",
    organism = "mouse",
    genome_build = "mm10",
    collection = "CORE",
    source_version = "2020",
    created_by = "test"
  )
  wb_motif_register(
    b,
    motif_library = "jaspar2020_core_mouse",
    motif_key = "MA0004.1_Arnt",
    motif_id = "MA0004.1",
    motif_name = "Arnt",
    source_type = "jaspar",
    matrix_class = "PWMatrix",
    payload_json = "{\"profile_matrix\": [[1,2],[3,4]]}",
    metadata = list(species = "mouse"),
    created_by = "test"
  )

  libs <- wb_motif_libraries(b)
  stopifnot(is.data.frame(libs), nrow(libs) == 1L)
  stopifnot(identical(as.character(libs$motif_library[1]), "jaspar2020_core_mouse"))

  mts <- wb_motifs(b, motif_library = "jaspar2020_core_mouse")
  stopifnot(is.data.frame(mts), nrow(mts) == 1L)
  stopifnot(identical(as.character(mts$motif_key[1]), "MA0004.1_Arnt"))
  stopifnot(identical(as.character(mts$motif_id[1]), "MA0004.1"))

  if (requireNamespace("JASPAR2020", quietly = TRUE) &&
      requireNamespace("TFBSTools", quietly = TRUE)) {
    wb_motif_library_import_jaspar(
      b,
      motif_library = "jaspar_roundtrip_mouse",
      jaspar_pkg = "JASPAR2020",
      species = "10090",
      collection = "CORE",
      motif_ids = c("MA0004.1"),
      organism = "mouse",
      genome_build = "mm10",
      created_by = "test"
    )
    roundtrip <- .wb_motifs_load_tfbstools(b, motif_library = "jaspar_roundtrip_mouse")
    stopifnot(length(roundtrip) == 1L)
    stopifnot(identical(names(roundtrip), "MA0004.1_Arnt"))
  }

  TRUE
}
