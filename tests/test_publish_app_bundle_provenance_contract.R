test_publish_app_bundle_provenance_contract <- function() {
  required <- c("Seurat", "SeuratObject", "BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  root <- tempfile("scwb_public_publish_")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  counts <- Matrix::Matrix(
    c(
      1, 0, 3, 0,
      0, 2, 0, 4,
      5, 0, 1, 0,
      0, 1, 0, 1,
      2, 2, 2, 2
    ),
    nrow = 5L, ncol = 4L, sparse = TRUE,
    dimnames = list(paste0("gene", seq_len(5L)), paste0("cell", seq_len(4L)))
  )
  seurat <- Seurat::CreateSeuratObject(counts = counts, assay = "RNA")
  seurat$orig.ident <- c("donor_a", "donor_a", "donor_b", "donor_b")
  seurat$cluster <- factor(c("naive", "naive", "activated", "activated"))
  embedding <- matrix(
    c(1, 0, 0, 1, 2, 0, 0, 2), nrow = 4L, ncol = 2L,
    dimnames = list(colnames(counts), c("PC_1", "PC_2"))
  )
  seurat[["pca"]] <- SeuratObject::CreateDimReducObject(
    embeddings = embedding, key = "PC_", assay = "RNA"
  )

  destination <- file.path(root, "published")
  manifest <- wb_publish_app_bundle(
    seurat = seurat,
    out_dir = destination,
    dataset_col = "orig.ident",
    bundle_id = "published_fixture",
    bundle_name = "Published fixture",
    matrix_specs = list(wb_matrix_spec(
      matrix_id = "RNA_counts", seurat_assay = "RNA", layer = "counts",
      feature_type = "gene"
    )),
    overwrite = FALSE
  )
  stopifnot(
    identical(as.character(manifest$bundle_id), "published_fixture"),
    identical(as.character(manifest$bundle_name), "Published fixture")
  )

  bundle <- wb_open_bundle(destination, validate = TRUE)
  stopifnot(
    identical(wb_cells(bundle, "all"), colnames(counts)),
    "RNA_counts" %in% as.character(wb_matrices(bundle)$matrix_id),
    "pca" %in% as.character(wb_spaces(bundle)$space_id),
    identical(dim(wb_matrix(bundle, "RNA_counts")), dim(counts)),
    identical(as.character(bundle$manifest$bundle_id), "published_fixture"),
    identical(as.character(bundle$manifest$bundle_name), "Published fixture")
  )

  source_inputs <- wb_prov_source_inputs(bundle)
  source_identity <- wb_prov_source_identity(bundle, "RNA_counts")
  publisher_inputs <- source_inputs[
    as.character(source_inputs$uri) ==
      "scworkbench-ingestion://wb_publish_app_bundle/in-memory-seurat",
    , drop = FALSE
  ]
  publisher_identity <- source_identity[
    grepl("wb_publish_app_bundle", source_identity$source_identity_json, fixed = TRUE),
    , drop = FALSE
  ]
  run_bindings <- DBI::dbGetQuery(
    bundle$con,
    "SELECT direction, binding_name, entity_kind, entity_id, relationship_type
       FROM prov_run_entity_bindings ORDER BY direction, binding_name, entity_kind, entity_id;"
  )
  ingest_runs <- DBI::dbGetQuery(
    bundle$con,
    "SELECT snapshot_id, run_id, op_name FROM prov_runs WHERE op_name = 'bundle_ingest_seurat';"
  )
  artifacts <- wb_art_list(bundle)
  report <- artifacts[
    artifacts$name == "container_ingest_report" &
      artifacts$source_op == "bundle_ingest_seurat",
    , drop = FALSE
  ]
  stopifnot(
    nrow(publisher_inputs) == 1L,
    identical(as.character(publisher_inputs$scope), "in_memory"),
    identical(as.character(publisher_inputs$checksum_status), "nonportable_in_memory"),
    identical(
      as.character(publisher_inputs$uri),
      "scworkbench-ingestion://wb_publish_app_bundle/in-memory-seurat"
    ),
    nrow(publisher_identity) == 1L,
    nrow(ingest_runs) == 1L,
    any(run_bindings$direction == "input" & run_bindings$entity_kind == "in_memory_source" &
          run_bindings$relationship_type == "CONSUMES"),
    any(run_bindings$direction == "output" & run_bindings$entity_kind == "matrix" &
          run_bindings$entity_id == "RNA_counts"),
    any(run_bindings$direction == "output" & run_bindings$entity_kind == "space" &
          run_bindings$entity_id == "pca"),
    nrow(report) == 1L
  )
  birth <- wb_art_birth_certificate(bundle, as.character(report$artifact_id[1]))
  stopifnot(
    nrow(birth$persisted_provenance$links) >= 1L,
    identical(
      as.character(birth$persisted_provenance$run_details$run$op_name),
      "bundle_ingest_seurat"
    )
  )
  wb_close_bundle(bundle)

  # A failure after one matrix fragment has already been assembled must remain
  # confined to the hidden stage. An existing destination stays byte-for-byte
  # recognizable and no stage or backup directory is retained.
  failed_destination <- file.path(root, "existing_destination")
  dir.create(failed_destination)
  sentinel <- file.path(failed_destination, "sentinel.txt")
  writeLines("keep existing destination", sentinel, useBytes = TRUE)
  before_listing <- sort(list.files(failed_destination, all.files = TRUE, no.. = TRUE))
  failure <- try(
    wb_publish_app_bundle(
      seurat = seurat,
      out_dir = failed_destination,
      overwrite = TRUE,
      matrix_specs = list(
        wb_matrix_spec("RNA_counts", "RNA", "counts", "gene"),
        wb_matrix_spec("invalid_matrix", "missing_assay", "counts", "gene")
      )
    ),
    silent = TRUE
  )
  leftovers <- list.files(root, all.files = TRUE, no.. = TRUE)
  stopifnot(
    inherits(failure, "try-error"),
    grepl("no partial published bundle was accepted", as.character(failure), fixed = TRUE),
    identical(readLines(sentinel, warn = FALSE), "keep existing destination"),
    identical(sort(list.files(failed_destination, all.files = TRUE, no.. = TRUE)), before_listing),
    !file.exists(file.path(failed_destination, "manifest.json")),
    !dir.exists(file.path(failed_destination, "db")),
    !any(grepl("^\\.existing_destination_publish_(staging|backup)_", leftovers))
  )
  TRUE
}
