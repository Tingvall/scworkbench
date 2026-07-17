test_bundle_ingest_containers_contract <- function(bundle_dir = NULL) {
  if (!requireNamespace("BPCells", quietly = TRUE)) return(TRUE)
  if (!requireNamespace("SingleCellExperiment", quietly = TRUE)) return(TRUE)
  if (!requireNamespace("SummarizedExperiment", quietly = TRUE)) return(TRUE)
  if (!requireNamespace("S4Vectors", quietly = TRUE)) return(TRUE)
  if (!requireNamespace("Matrix", quietly = TRUE)) return(TRUE)

  write_10x_triplet <- function(dir, sample_prefix, mat, feature_ids = rownames(mat), feature_names = feature_ids, feature_type = "Gene Expression") {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    mtx_path <- file.path(dir, paste0(sample_prefix, "_matrix.mtx"))
    barcodes_path <- file.path(dir, paste0(sample_prefix, "_barcodes.tsv"))
    features_path <- file.path(dir, paste0(sample_prefix, "_features.tsv"))
    Matrix::writeMM(mat, mtx_path)
    writeLines(colnames(mat), barcodes_path, useBytes = TRUE)
    utils::write.table(
      data.frame(feature_ids, feature_names, feature_type, stringsAsFactors = FALSE),
      features_path,
      sep = "\t",
      quote = FALSE,
      row.names = FALSE,
      col.names = FALSE
    )
    invisible(list(matrix_path = mtx_path, barcodes_path = barcodes_path, features_path = features_path))
  }

  counts <- Matrix::Matrix(
    c(
      1, 0, 3, 0,
      0, 2, 0, 4,
      5, 0, 1, 0,
      0, 1, 0, 1,
      2, 2, 2, 2
    ),
    nrow = 5,
    ncol = 4,
    sparse = TRUE
  )
  rownames(counts) <- paste0("gene", seq_len(5))
  colnames(counts) <- paste0("cell", seq_len(4))

  sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = counts),
    colData = S4Vectors::DataFrame(
      donor = c("d1", "d1", "d2", "d2"),
      cluster = factor(c("naive", "naive", "activated", "activated"))
    ),
    rowData = S4Vectors::DataFrame(symbol = paste0("G", seq_len(5)))
  )
  SingleCellExperiment::reducedDim(sce, "PCA") <- matrix(
    c(1, 0, 0, 1, 2, 0, 0, 2),
    nrow = 4,
    ncol = 2,
    dimnames = list(colnames(counts), c("PC1", "PC2"))
  )

  out <- tempfile("wb_sce_ingest_")
  b <- wb_bundle_from_sce(
    sce,
    bundle_dir = out,
    categorical_cols = "cluster",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(b), add = TRUE)

  stopifnot(inherits(b, "scworkbench_bundle"))
  mats <- wb_matrices(b)
  stopifnot("counts" %in% mats$matrix_id)
  mi <- mats[mats$matrix_id == "counts", , drop = FALSE]
  stopifnot(mi$n_cells[[1]] == 4L, mi$n_features[[1]] == 5L)

  stopifnot(identical(wb_cells(b, "core"), colnames(counts)))
  meta <- wb_meta(b)
  stopifnot(all(c("cell_id", "donor", "cluster") %in% names(meta)))

  spaces <- wb_spaces(b)
  stopifnot("PCA" %in% spaces$space_id)

  sets <- wb_cell_sets(b)
  stopifnot("set:sce_cluster__activated" %in% sets)
  stopifnot("set:sce_cluster__naive" %in% sets)

  arts <- wb_art_list(b)
  stopifnot(any(arts$type == "obs_table" & arts$name == "container_ingest_report"))
  stopifnot(any(arts$type == "feature_table" & arts$name == "counts_feature_metadata"))
  report_id <- as.character(arts$artifact_id[arts$type == "obs_table" & arts$name == "container_ingest_report"][1])
  report <- wb_art_load(b, report_id, expected_kind = "obs_table")$table
  stopifnot("duplicate_feature_id_policy" %in% names(report))
  stopifnot(identical(as.character(report$duplicate_feature_id_policy[1]), "error"))
  stopifnot(identical(as.integer(report$duplicate_feature_id_rows[1]), 0L))

  dup_counts <- counts
  colnames(dup_counts) <- c("dup_cell", "dup_cell", "unique_cell", "dup_cell")
  dup_sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = dup_counts),
    colData = S4Vectors::DataFrame(
      donor = c("d1", "d1", "d2", "d3"),
      cluster = factor(c("naive", "naive", "activated", "activated"))
    ),
    rowData = S4Vectors::DataFrame(symbol = paste0("G", seq_len(5)))
  )
  out_dup <- tempfile("wb_sce_ingest_dup_")
  bdup <- wb_bundle_from_sce(
    dup_sce,
    bundle_dir = out_dup,
    categorical_cols = "cluster",
    dataset_col = "donor",
    duplicate_cell_id_policy = "make_unique",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(bdup), add = TRUE)
  expected_ids <- make.unique(colnames(dup_counts), sep = ".")
  stopifnot(identical(wb_cells(bdup, "core"), expected_ids))
  dup_meta <- wb_meta(bdup)
  stopifnot("original_cell_id" %in% names(dup_meta))
  stopifnot(identical(as.character(dup_meta$original_cell_id), as.character(colnames(dup_counts))))
  stopifnot(identical(as.character(dup_meta$dataset_id), c("d1", "d1", "d2", "d3")))
  stopifnot(!anyDuplicated(dup_meta$cell_id))

  dup_arts <- wb_art_list(bdup)
  dup_report_id <- as.character(dup_arts$artifact_id[dup_arts$type == "obs_table" & dup_arts$name == "container_ingest_report"][1])
  stopifnot(nzchar(dup_report_id))
  dup_report <- wb_art_load(bdup, dup_report_id, expected_kind = "obs_table")$table
  stopifnot(identical(as.character(dup_report$duplicate_cell_id_policy[1]), "make_unique"))
  stopifnot(identical(as.integer(dup_report$duplicate_cell_id_rows[1]), 3L))
  stopifnot(identical(as.integer(dup_report$duplicate_cell_id_unique_values[1]), 1L))
  stopifnot(identical(as.character(dup_report$original_cell_id_column[1]), "original_cell_id"))

  out_dup_err <- tempfile("wb_sce_ingest_dup_error_")
  err <- try(
    wb_bundle_from_sce(
      dup_sce,
      bundle_dir = out_dup_err,
      duplicate_cell_id_policy = "error",
      overwrite = TRUE,
      created_by = "test"
    ),
    silent = TRUE
  )
  stopifnot(inherits(err, "try-error"))
  stopifnot(grepl("Duplicate cell IDs detected", as.character(err), fixed = TRUE))

  bcore <- wb_init_bundle(tempfile("wb_define_cells_dup_"), overwrite = TRUE)
  on.exit(wb_close_bundle(bcore), add = TRUE)
  core_err <- try(
    wb_define_cells(
      bcore,
      cell_ids = c("dup_cell", "dup_cell"),
      metadata = data.frame(cell_id = c("dup_cell", "dup_cell"), donor = c("d1", "d2")),
      dataset_id = c("d1", "d2")
    ),
    silent = TRUE
  )
  stopifnot(inherits(core_err, "try-error"))
  stopifnot(grepl("cell_ids must be unique", as.character(core_err), fixed = TRUE))

  large_n <- 20000L
  large_cells <- paste0("large_cell_", seq_len(large_n))
  large_meta <- data.frame(
    cell_id = large_cells,
    sample_id = rep(paste0("sample_", seq_len(4)), length.out = large_n),
    stage = rep(c("Pupa", "Nurse", "Forager", "Pupa"), length.out = large_n),
    stringsAsFactors = FALSE
  )
  blarge <- wb_init_bundle(tempfile("wb_define_cells_large_"), overwrite = TRUE)
  on.exit(wb_close_bundle(blarge), add = TRUE)
  t_large <- system.time(
    wb_define_cells(
      blarge,
      cell_ids = large_cells,
      metadata = large_meta,
      dataset_id = large_meta$sample_id,
      set_name = "core",
      source = "large_test",
      created_by = "test"
    )
  )[["elapsed"]]
  stopifnot(identical(length(wb_cells(blarge, "core")), large_n))
  stopifnot(identical(sum(wb_list(blarge, "datasets")$n_cells), large_n))
  stopifnot(is.finite(t_large), t_large < 20)

  dup_feature_counts <- counts
  rownames(dup_feature_counts) <- c("dup_gene", "dup_gene", "unique_gene", "dup_gene", "another_gene")
  dup_feature_sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(counts = dup_feature_counts),
    colData = S4Vectors::DataFrame(donor = c("d1", "d1", "d2", "d2")),
    rowData = S4Vectors::DataFrame(symbol = paste0("SYM", seq_len(5)))
  )
  out_dup_feature <- tempfile("wb_sce_ingest_dup_feature_")
  bdup_feature <- wb_bundle_from_sce(
    dup_feature_sce,
    bundle_dir = out_dup_feature,
    duplicate_feature_id_policy = "make_unique",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(bdup_feature), add = TRUE)
  expected_feature_ids <- make.unique(rownames(dup_feature_counts), sep = ".")
  stopifnot(identical(wb_feature_ids(bdup_feature, "counts"), expected_feature_ids))
  dup_feature_arts <- wb_art_list(bdup_feature)
  dup_feature_table_id <- as.character(dup_feature_arts$artifact_id[dup_feature_arts$type == "feature_table" & dup_feature_arts$name == "counts_feature_metadata"][1])
  stopifnot(nzchar(dup_feature_table_id))
  dup_feature_table <- wb_art_load(bdup_feature, dup_feature_table_id, expected_kind = "feature_table")$table
  stopifnot("original_feature_id" %in% names(dup_feature_table))
  stopifnot(identical(as.character(dup_feature_table$original_feature_id), as.character(rownames(dup_feature_counts))))
  dup_feature_report_id <- as.character(dup_feature_arts$artifact_id[dup_feature_arts$type == "obs_table" & dup_feature_arts$name == "container_ingest_report"][1])
  dup_feature_report <- wb_art_load(bdup_feature, dup_feature_report_id, expected_kind = "obs_table")$table
  stopifnot(identical(as.character(dup_feature_report$duplicate_feature_id_policy[1]), "make_unique"))
  stopifnot(identical(as.integer(dup_feature_report$duplicate_feature_id_rows[1]), 3L))
  stopifnot(identical(as.integer(dup_feature_report$duplicate_feature_id_unique_values[1]), 1L))
  stopifnot(identical(as.character(dup_feature_report$original_feature_id_column[1]), "original_feature_id"))

  out_dup_feature_err <- tempfile("wb_sce_ingest_dup_feature_error_")
  feature_err <- try(
    wb_bundle_from_sce(
      dup_feature_sce,
      bundle_dir = out_dup_feature_err,
      duplicate_feature_id_policy = "error",
      overwrite = TRUE,
      created_by = "test"
    ),
    silent = TRUE
  )
  stopifnot(inherits(feature_err, "try-error"))
  stopifnot(grepl("Duplicate feature IDs detected", as.character(feature_err), fixed = TRUE))

  # H5AD round-trips use zellkonverter's external Conda environment. Do not
  # bootstrap that environment (and potentially download Miniconda) as part of
  # the offline package contract suite. CI/container jobs with a provisioned
  # AnnData runtime can opt in explicitly.
  run_h5ad <- identical(tolower(Sys.getenv("SCWORKBENCH_TEST_H5AD", unset = "false")), "true")
  if (requireNamespace("zellkonverter", quietly = TRUE) && run_h5ad) {
    h5ad_path <- tempfile("wb_dup_obs_", fileext = ".h5ad")
    zellkonverter::writeH5AD(dup_sce, h5ad_path, X_name = "counts")

    out_h5_explicit <- tempfile("wb_h5ad_dup_explicit_")
    bh5_explicit <- wb_bundle_from_h5ad(
      h5ad_path,
      bundle_dir = out_h5_explicit,
      duplicate_cell_id_policy = "make_unique",
      overwrite = TRUE,
      created_by = "test"
    )
    on.exit(wb_close_bundle(bh5_explicit), add = TRUE)
    stopifnot(identical(wb_cells(bh5_explicit, "core"), expected_ids))

    out_h5_default <- tempfile("wb_h5ad_dup_default_")
    bh5_default <- wb_bundle_from_h5ad(
      h5ad_path,
      bundle_dir = out_h5_default,
      overwrite = TRUE,
      created_by = "test"
    )
    on.exit(wb_close_bundle(bh5_default), add = TRUE)
    stopifnot(identical(wb_cells(bh5_default, "core"), expected_ids))
    h5_meta <- wb_meta(bh5_default)
    stopifnot("ann_data_obs_name" %in% names(h5_meta))
    stopifnot(identical(as.character(h5_meta$ann_data_obs_name), as.character(colnames(dup_counts))))
    h5_arts <- wb_art_list(bh5_default)
    h5_report_id <- as.character(h5_arts$artifact_id[h5_arts$type == "obs_table" & h5_arts$name == "container_ingest_report" & h5_arts$source_op == "bundle_ingest_anndata_h5ad"][1])
    stopifnot(nzchar(h5_report_id))
    h5_report <- wb_art_load(bh5_default, h5_report_id, expected_kind = "obs_table")$table
    stopifnot(identical(as.character(h5_report$duplicate_cell_id_policy[1]), "make_unique"))
    stopifnot(identical(as.integer(h5_report$duplicate_cell_id_rows[1]), 3L))
    stopifnot(identical(as.integer(h5_report$duplicate_cell_id_unique_values[1]), 1L))
    stopifnot(identical(as.character(h5_report$original_cell_id_column[1]), "ann_data_obs_name"))

    out_h5_error <- tempfile("wb_h5ad_dup_error_")
    h5_err <- try(
      wb_bundle_from_h5ad(
        h5ad_path,
        bundle_dir = out_h5_error,
        duplicate_cell_id_policy = "error",
        overwrite = TRUE,
        created_by = "test"
      ),
      silent = TRUE
    )
    stopifnot(inherits(h5_err, "try-error"))
    stopifnot(grepl("Duplicate cell IDs detected", as.character(h5_err), fixed = TRUE))

    h5ad_feature_path <- tempfile("wb_dup_var_", fileext = ".h5ad")
    zellkonverter::writeH5AD(dup_feature_sce, h5ad_feature_path, X_name = "counts")

    out_h5_feature_default <- tempfile("wb_h5ad_dup_feature_default_")
    bh5_feature_default <- wb_bundle_from_h5ad(
      h5ad_feature_path,
      bundle_dir = out_h5_feature_default,
      overwrite = TRUE,
      created_by = "test"
    )
    on.exit(wb_close_bundle(bh5_feature_default), add = TRUE)
    stopifnot(identical(wb_feature_ids(bh5_feature_default, "counts"), expected_feature_ids))
    h5_feature_arts <- wb_art_list(bh5_feature_default)
    h5_feature_report_id <- as.character(h5_feature_arts$artifact_id[h5_feature_arts$type == "obs_table" & h5_feature_arts$name == "container_ingest_report" & h5_feature_arts$source_op == "bundle_ingest_anndata_h5ad"][1])
    stopifnot(nzchar(h5_feature_report_id))
    h5_feature_report <- wb_art_load(bh5_feature_default, h5_feature_report_id, expected_kind = "obs_table")$table
    stopifnot(identical(as.character(h5_feature_report$duplicate_feature_id_policy[1]), "make_unique"))
    stopifnot(identical(as.integer(h5_feature_report$duplicate_feature_id_rows[1]), 3L))
    stopifnot(identical(as.integer(h5_feature_report$duplicate_feature_id_unique_values[1]), 1L))
    stopifnot(identical(as.character(h5_feature_report$original_feature_id_column[1]), "ann_data_var_name"))
    h5_feature_table_id <- as.character(h5_feature_arts$artifact_id[h5_feature_arts$type == "feature_table" & h5_feature_arts$name == "counts_feature_metadata"][1])
    h5_feature_table <- wb_art_load(bh5_feature_default, h5_feature_table_id, expected_kind = "feature_table")$table
    stopifnot("ann_data_var_name" %in% names(h5_feature_table))
    stopifnot(identical(as.character(h5_feature_table$ann_data_var_name), as.character(rownames(dup_feature_counts))))

    out_h5_feature_error <- tempfile("wb_h5ad_dup_feature_error_")
    h5_feature_err <- try(
      wb_bundle_from_h5ad(
        h5ad_feature_path,
        bundle_dir = out_h5_feature_error,
        duplicate_feature_id_policy = "error",
        overwrite = TRUE,
        created_by = "test"
      ),
      silent = TRUE
    )
    stopifnot(inherits(h5_feature_err, "try-error"))
    stopifnot(grepl("Duplicate feature IDs detected", as.character(h5_feature_err), fixed = TRUE))
    stopifnot(file.exists(file.path(out_h5_feature_error, "INGEST_FAILED.json")))
    stopifnot(!dir.exists(file.path(out_h5_feature_error, "db")))
    h5_feature_val_err <- try(wb_validate_bundle(out_h5_feature_error), silent = TRUE)
    stopifnot(inherits(h5_feature_val_err, "try-error"))
    stopifnot(grepl("ingestion failed/incomplete", as.character(h5_feature_val_err), fixed = TRUE))
  } else if (requireNamespace("zellkonverter", quietly = TRUE)) {
    message("Skipping H5AD round-trip contract checks; set SCWORKBENCH_TEST_H5AD=1 in a provisioned zellkonverter runtime.")
  }

  if (requireNamespace("Seurat", quietly = TRUE) && requireNamespace("SeuratObject", quietly = TRUE)) {
    seurat_counts <- counts
    so <- Seurat::CreateSeuratObject(counts = seurat_counts, assay = "RNA")
    so$cluster <- factor(c("naive", "naive", "activated", "activated"))
    emb <- matrix(
      c(1, 0, 0, 1, 2, 0, 0, 2),
      nrow = 4,
      ncol = 2,
      dimnames = list(colnames(seurat_counts), c("PC_1", "PC_2"))
    )
    so[["pca"]] <- SeuratObject::CreateDimReducObject(embeddings = emb, key = "PC_", assay = "RNA")

    out_seurat <- tempfile("wb_seurat_ingest_")
    bs <- wb_bundle_from_seurat(
      so,
      bundle_dir = out_seurat,
      assays = "RNA",
      layers = "counts",
      categorical_cols = "cluster",
      overwrite = TRUE,
      created_by = "test"
    )
    on.exit(wb_close_bundle(bs), add = TRUE)
    smats <- wb_matrices(bs)
    stopifnot("RNA" %in% smats$matrix_id)
    smi <- smats[smats$matrix_id == "RNA", , drop = FALSE]
    stopifnot(smi$n_cells[[1]] == 4L, smi$n_features[[1]] == 5L)
    stopifnot("pca" %in% wb_spaces(bs)$space_id)
    stopifnot("set:seurat_cluster__activated" %in% wb_cell_sets(bs))
  }

  tenx_root <- tempfile("wb_10x_ingest_")
  mat_a <- counts[, 1:2, drop = FALSE]
  rownames(mat_a) <- paste0("gene", seq_len(5))
  colnames(mat_a) <- c("AAAC-1", "TTTG-1")
  mat_b <- counts[, 3:4, drop = FALSE]
  rownames(mat_b) <- rownames(mat_a)
  colnames(mat_b) <- c("AAAC-1", "GGGA-1")
  p_a <- write_10x_triplet(tenx_root, "GSM1_R1_Pupa", mat_a)
  p_b <- write_10x_triplet(tenx_root, "GSM2_R2_Nurse", mat_b)
  st <- data.frame(
    sample_id = c("R1_Pupa", "R2_Nurse"),
    matrix_path = c(p_a$matrix_path, p_b$matrix_path),
    barcodes_path = c(p_a$barcodes_path, p_b$barcodes_path),
    features_path = c(p_a$features_path, p_b$features_path),
    gsm = c("GSM1", "GSM2"),
    replicate = c("1", "2"),
    stage = c("Pupa", "Nurse"),
    stringsAsFactors = FALSE
  )
  out_10x <- tempfile("wb_10x_bundle_")
  b10x <- wb_bundle_from_10x_mtx(
    tenx_root,
    bundle_dir = out_10x,
    sample_table = st,
    matrix_id = "RNA_counts",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(b10x), add = TRUE)
  tenx_cells <- wb_cells(b10x, "core")
  stopifnot(identical(tenx_cells, c("R1_Pupa:AAAC-1", "R1_Pupa:TTTG-1", "R2_Nurse:AAAC-1", "R2_Nurse:GGGA-1")))
  tenx_meta <- wb_meta(b10x)
  stopifnot(all(c("barcode", "sample_id", "gsm", "replicate", "stage") %in% names(tenx_meta)))
  stopifnot(identical(as.character(tenx_meta$barcode), c("AAAC-1", "TTTG-1", "AAAC-1", "GGGA-1")))
  stopifnot(identical(as.character(tenx_meta$stage), c("Pupa", "Pupa", "Nurse", "Nurse")))
  tenx_mats <- wb_matrices(b10x)
  stopifnot("RNA_counts" %in% tenx_mats$matrix_id)
  tenx_row <- tenx_mats[tenx_mats$matrix_id == "RNA_counts", , drop = FALSE]
  stopifnot(identical(as.integer(tenx_row$n_cells[1]), 4L))
  stopifnot(identical(as.integer(tenx_row$n_features[1]), 5L))
  stopifnot(identical(wb_feature_ids(b10x, "RNA_counts"), rownames(mat_a)))
  stopifnot(isTRUE(wb_validate_bundle(out_10x)))
  tenx_manifest <- wb_manifest(b10x)
  stopifnot(identical(as.character(tenx_manifest$bundle_id), basename(out_10x)))
  stopifnot(identical(as.character(tenx_manifest$bundle_name), basename(out_10x)))
  stopifnot(identical(as.character(tenx_manifest$id_policy$staging_provenance$source_type), "10x_mtx"))
  tenx_arts <- wb_art_list(b10x)
  stopifnot(any(tenx_arts$type == "obs_table" & tenx_arts$name == "container_ingest_report" & tenx_arts$source_op == "bundle_ingest_10x_mtx"))
  stopifnot(any(tenx_arts$type == "feature_table" & tenx_arts$name == "RNA_counts_feature_metadata"))
  tenx_report_id <- as.character(tenx_arts$artifact_id[tenx_arts$type == "obs_table" & tenx_arts$name == "container_ingest_report" & tenx_arts$source_op == "bundle_ingest_10x_mtx"][1])
  tenx_report <- wb_art_load(b10x, tenx_report_id, expected_kind = "obs_table")$table
  stopifnot(identical(as.character(tenx_report$duplicate_cell_id_policy[1]), "prefix"))
  stopifnot(identical(as.integer(tenx_report$duplicate_cell_id_rows[1]), 2L))
  stopifnot(identical(as.character(tenx_report$duplicate_feature_id_policy[1]), "error"))

  tenx_norm <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b10x,
    op_name = "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log1p_cp10k",
      scale_factor = 10000,
      overwrite = TRUE
    )
  )
  tenx_source <- cbind(as.matrix(mat_a), as.matrix(mat_b))
  tenx_expected <- log1p(t(t(tenx_source) / Matrix::colSums(tenx_source) * 10000))
  tenx_got <- as.matrix(wb_slice(b10x, "RNA_log1p_cp10k", rownames(mat_a), tenx_cells))
  stopifnot(isTRUE(all.equal(tenx_got, tenx_expected, tolerance = 1e-8, check.attributes = FALSE)))
  stopifnot(any(tenx_got != 0))

  tenx_hvg <- wb_session_run_op(
    session = tenx_norm$session,
    bundle = b10x,
    op_name = "hvg_select",
    inputs = list(
      matrix = "RNA_log1p_cp10k",
      cell_set = "all",
      min_cells = 1L,
      n_features = 3L,
      method = "variance"
    )
  )
  tenx_hvg_table <- tenx_hvg$run$outputs$selected_features$table
  stopifnot(any(tenx_hvg_table$variance > 0))

  # A one-library Matrix Market import is a single physical fragment. BPCells
  # payload dimnames are optional here, so normalization must use the fragment
  # registry rather than colnames() to align library sizes with cell IDs.
  one_tenx_root <- tempfile("wb_10x_one_library_")
  p_one <- write_10x_triplet(one_tenx_root, "GSM1_R1_Pupa", mat_a)
  one_st <- data.frame(
    sample_id = "R1_Pupa",
    matrix_path = p_one$matrix_path,
    barcodes_path = p_one$barcodes_path,
    features_path = p_one$features_path,
    stage = "Pupa",
    stringsAsFactors = FALSE
  )
  out_10x_one <- tempfile("wb_10x_one_library_bundle_")
  b10x_one <- wb_bundle_from_10x_mtx(
    one_tenx_root,
    bundle_dir = out_10x_one,
    sample_table = one_st,
    matrix_id = "RNA_counts",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(b10x_one), add = TRUE)
  one_cells <- wb_cells(b10x_one, "core")
  one_raw <- wb_matrix(b10x_one, "RNA_counts")
  one_raw_without_names <- one_raw
  colnames(one_raw_without_names) <- NULL
  stopifnot(is.null(colnames(one_raw_without_names)))
  legacy_sizes <- as.numeric(Matrix::colSums(one_raw_without_names))
  names(legacy_sizes) <- colnames(one_raw_without_names)
  legacy_sizes <- legacy_sizes[match(one_cells, names(legacy_sizes))]
  stopifnot(all(is.na(legacy_sizes)))
  stopifnot(identical(
    .wb_matrix_single_fragment_cell_ids(
      b10x_one,
      "RNA_counts",
      one_raw_without_names,
      one_cells
    ),
    one_cells
  ))
  wrong_order <- try(
    .wb_matrix_single_fragment_cell_ids(
      b10x_one,
      "RNA_counts",
      one_raw_without_names,
      rev(one_cells)
    ),
    silent = TRUE
  )
  stopifnot(inherits(wrong_order, "try-error"))

  one_norm <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b10x_one,
    op_name = "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log1p_cp10k",
      scale_factor = 10000,
      overwrite = TRUE
    )
  )
  one_expected <- log1p(t(t(as.matrix(mat_a)) / Matrix::colSums(mat_a) * 10000))
  one_got <- as.matrix(wb_slice(b10x_one, "RNA_log1p_cp10k", rownames(mat_a), one_cells))
  one_summary <- one_norm$run$outputs$summary$table
  one_info <- wb_matrix_info(b10x_one, "RNA_log1p_cp10k")
  one_path <- file.path(b10x_one$dir, as.character(one_info$path[1]))
  stopifnot(isTRUE(all.equal(one_got, one_expected, tolerance = 1e-8, check.attributes = FALSE)))
  stopifnot(any(one_got != 0))
  stopifnot(identical(as.integer(one_summary$n_zero_library_cells[1]), 0L))
  stopifnot(identical(BPCells::matrix_type(.wb_bp_open_matrix_dir(one_path)), "double"))

  one_hvg <- wb_session_run_op(
    session = one_norm$session,
    bundle = b10x_one,
    op_name = "hvg_select",
    inputs = list(
      matrix = "RNA_log1p_cp10k",
      cell_set = "all",
      min_cells = 1L,
      n_features = 3L,
      method = "variance"
    )
  )
  stopifnot(any(one_hvg$run$outputs$selected_features$table$variance > 0))

  tenx_dup_feature_root <- tempfile("wb_10x_dup_feature_")
  dup_feature_mat <- mat_a
  rownames(dup_feature_mat) <- c("dup_gene", "dup_gene", "gene3", "gene4", "gene5")
  p_dup <- write_10x_triplet(tenx_dup_feature_root, "sample_dup", dup_feature_mat, feature_ids = rownames(dup_feature_mat))
  st_dup <- data.frame(
    sample_id = "sample_dup",
    matrix_path = p_dup$matrix_path,
    barcodes_path = p_dup$barcodes_path,
    features_path = p_dup$features_path,
    stringsAsFactors = FALSE
  )
  out_10x_dup <- tempfile("wb_10x_dup_feature_bundle_")
  b10x_dup <- wb_bundle_from_10x_mtx(
    tenx_dup_feature_root,
    bundle_dir = out_10x_dup,
    sample_table = st_dup,
    matrix_id = "RNA_counts",
    duplicate_feature_id_policy = "make_unique",
    overwrite = TRUE,
    created_by = "test"
  )
  on.exit(wb_close_bundle(b10x_dup), add = TRUE)
  stopifnot(identical(wb_feature_ids(b10x_dup, "RNA_counts"), make.unique(rownames(dup_feature_mat), sep = ".")))
  tenx_dup_arts <- wb_art_list(b10x_dup)
  tenx_dup_ft_id <- as.character(tenx_dup_arts$artifact_id[tenx_dup_arts$type == "feature_table" & tenx_dup_arts$name == "RNA_counts_feature_metadata"][1])
  tenx_dup_ft <- wb_art_load(b10x_dup, tenx_dup_ft_id, expected_kind = "feature_table")$table
  stopifnot("original_feature_id" %in% names(tenx_dup_ft))
  stopifnot(identical(as.character(tenx_dup_ft$original_feature_id), rownames(dup_feature_mat)))

  out_10x_err <- tempfile("wb_10x_dup_feature_error_bundle_")
  tenx_err <- try(
    wb_bundle_from_10x_mtx(
      tenx_dup_feature_root,
      bundle_dir = out_10x_err,
      sample_table = st_dup,
      matrix_id = "RNA_counts",
      duplicate_feature_id_policy = "error",
      overwrite = TRUE,
      created_by = "test"
    ),
    silent = TRUE
  )
  stopifnot(inherits(tenx_err, "try-error"))
  stopifnot(grepl("Duplicate feature IDs detected", as.character(tenx_err), fixed = TRUE))
  stopifnot(file.exists(file.path(out_10x_err, "INGEST_FAILED.json")))
  stopifnot(!dir.exists(file.path(out_10x_err, "db")))

  TRUE
}
