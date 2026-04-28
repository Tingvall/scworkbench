test_motif_match_contract <- function(bundle_dir) {
  tmp <- tempfile("scwb_motif_match_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("cell", seq_len(4))
  features <- c("chr1:100-199", "chr1:300-399", "chr2:500-599")
  wb_define_cells(b, cells)
  mat <- Matrix::Matrix(
    matrix(
      c(
        1L, 0L, 2L, 1L,
        0L, 3L, 1L, 1L,
        2L, 1L, 0L, 2L
      ),
      nrow = length(features),
      byrow = TRUE,
      dimnames = list(features, cells)
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
    created_by = "test"
  )
  wb_motif_register(
    b,
    motif_library = "jaspar2020_core_mouse",
    motif_key = "MA0497.1_Mef2c",
    motif_id = "MA0497.1",
    motif_name = "Mef2c",
    source_type = "jaspar",
    matrix_class = "PWMatrix",
    payload_json = "{\"profile_matrix\": [[1,2],[3,4]]}",
    created_by = "test"
  )

  wb_motif_match_replace(
    b,
    motif_match_set = "mm10_core_matches_v1",
    matrix_id = "ATAC_counts",
    motif_library = "jaspar2020_core_mouse",
    matches = data.frame(
      motif_key = c("MA0004.1_Arnt", "MA0004.1_Arnt", "MA0497.1_Mef2c"),
      feature_id = c("chr1:100-199", "chr2:500-599", "chr1:300-399"),
      stringsAsFactors = FALSE
    ),
    organism = "mouse",
    genome_build = "mm10",
    genome_provider = "BSgenome.Mmusculus.UCSC.mm10",
    match_engine = "motifmatchr",
    match_params = list(p_cutoff = 5e-05, w = 7L),
    created_by = "test"
  )

  sets <- wb_motif_match_sets(b, matrix_id = "ATAC_counts")
  stopifnot(is.data.frame(sets), nrow(sets) == 1L)
  stopifnot(identical(as.character(sets$motif_match_set[1]), "mm10_core_matches_v1"))
  stopifnot(identical(as.character(sets$motif_library[1]), "jaspar2020_core_mouse"))
  stopifnot(identical(as.integer(sets$n_features[1]), 3L))
  stopifnot(identical(as.integer(sets$n_motifs[1]), 2L))

  membership <- wb_motif_match_get(b, motif_match_set = "mm10_core_matches_v1")
  stopifnot(is.data.frame(membership), nrow(membership) == 3L)
  stopifnot(identical(unique(as.character(membership$motif_key)),
                      c("MA0004.1_Arnt", "MA0497.1_Mef2c")))

  ann <- .wb_motif_match_matrix(
    b,
    motif_match_set = "mm10_core_matches_v1",
    feature_ids = features
  )
  stopifnot(inherits(ann, "sparseMatrix"))
  stopifnot(identical(dim(ann), c(3L, 2L)))
  stopifnot(identical(rownames(ann), features))
  stopifnot(identical(colnames(ann), c("MA0004.1_Arnt", "MA0497.1_Mef2c")))
  stopifnot(as.vector(ann[, "MA0004.1_Arnt"]) == c(TRUE, FALSE, TRUE))
  stopifnot(as.vector(ann[, "MA0497.1_Mef2c"]) == c(FALSE, TRUE, FALSE))

  TRUE
}
