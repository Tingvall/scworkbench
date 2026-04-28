#' Define Bundle Cells From a Seurat Object
#'
#' Source adapter for staged bundle assembly. Uses a Seurat object's cell ids and
#' meta.data to establish the canonical bundle cell universe.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param seurat A Seurat object.
#' @param dataset_col Optional meta.data column for dataset assignment. Defaults
#'   to `orig.ident` when present, otherwise `"dataset_1"`.
#' @param set_name Membership set name. Defaults to `"core"`.
#' @param metadata_cols Optional metadata columns to include. Defaults to all
#'   meta.data columns.
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#'
#' @return Result from [wb_define_cells()].
#' @export
wb_define_cells_from_seurat <- function(bundle,
                                        seurat,
                                        dataset_col = NULL,
                                        set_name = "core",
                                        metadata_cols = NULL,
                                        source = "seurat",
                                        created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(inherits(seurat, "Seurat"), "seurat must be a Seurat object")

  cell_ids <- colnames(seurat)
  .wb_assert(length(cell_ids) > 0, "Seurat has no cells (colnames empty)")

  meta <- as.data.frame(seurat@meta.data, stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(meta)) {
    meta <- data.frame(cell_id = cell_ids, stringsAsFactors = FALSE)
  } else {
    .wb_assert(!is.null(rownames(meta)), "Seurat meta.data must have rownames aligned to cells")
    meta <- meta[match(cell_ids, rownames(meta)), , drop = FALSE]
    .wb_assert(!anyNA(match(cell_ids, rownames(seurat@meta.data))), "meta.data rows not aligned to Seurat colnames")
    if (!is.null(metadata_cols)) {
      keep <- intersect(as.character(metadata_cols), colnames(meta))
      meta <- meta[, keep, drop = FALSE]
    }
    meta <- cbind(cell_id = cell_ids, meta, stringsAsFactors = FALSE)
  }

  if (is.null(dataset_col) || !nzchar(dataset_col)) {
    dataset_col <- if ("orig.ident" %in% colnames(seurat@meta.data)) "orig.ident" else NULL
  }
  if (!is.null(dataset_col) && dataset_col %in% colnames(seurat@meta.data)) {
    dataset_id <- as.character(seurat@meta.data[[dataset_col]])
  } else {
    dataset_id <- rep("dataset_1", length(cell_ids))
  }

  wb_define_cells(
    bundle = bundle,
    cell_ids = cell_ids,
    metadata = meta,
    dataset_id = dataset_id,
    set_name = set_name,
    source = source,
    created_by = created_by
  )
}

#' Attach One Seurat Assay As a Bundle Matrix
#'
#' Source adapter for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param seurat A Seurat object.
#' @param matrix_id Target matrix id in the bundle.
#' @param assay Seurat assay to export.
#' @param layer Assay layer/slot. Defaults to `"counts"`.
#' @param feature_type Optional feature type label. If `NULL`, guessed from the
#'   exported feature ids.
#' @param description Optional description.
#' @param source Provenance source label.
#' @param created_by Optional author tag.
#'
#' @return Result from [wb_attach_matrix()].
#' @export
wb_attach_matrix_from_seurat <- function(bundle,
                                         seurat,
                                         matrix_id,
                                         assay,
                                         layer = "counts",
                                         feature_type = NULL,
                                         description = NULL,
                                         source = "seurat",
                                         created_by = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(inherits(seurat, "Seurat"), "seurat must be a Seurat object")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id required")
  .wb_assert(is.character(assay) && length(assay) == 1L && nzchar(assay), "assay required")
  .wb_assert(assay %in% names(seurat@assays), paste0("Unknown assay: ", assay))

  feature_ids <- rownames(seurat@assays[[assay]])
  .wb_assert(length(feature_ids) > 0, paste0("No features in Seurat assay: ", assay))
  if (is.null(feature_type) || !nzchar(feature_type)) {
    feature_type <- .wb_guess_feature_type(feature_ids)
  }

  m <- .get_assay_counts(seurat, assay = assay, layer_or_slot = layer)
  m <- .align_matrix_to_ids(m, feature_ids = feature_ids, cell_ids = colnames(seurat))

  if (is.null(description) || !nzchar(description)) {
    description <- paste0("Matrix from Seurat assay '", assay, "' layer '", layer, "' (", feature_type, ")")
  }

  wb_attach_matrix(
    bundle = bundle,
    matrix_id = matrix_id,
    mat = m,
    layer = layer,
    feature_type = feature_type,
    description = description,
    source = source,
    created_by = created_by
  )
}

#' Attach Selected Seurat Reductions As Bundle Spaces
#'
#' Source adapter for staged bundle assembly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param seurat A Seurat object.
#' @param reductions Optional reduction names. Defaults to all reductions.
#' @param overwrite Passed through to [wb_add_space()].
#' @param source Provenance source label.
#'
#' @return Named list of results from [wb_add_space()].
#' @export
wb_attach_spaces_from_seurat <- function(bundle,
                                         seurat,
                                         reductions = NULL,
                                         overwrite = FALSE,
                                         source = "seurat") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(inherits(seurat, "Seurat"), "seurat must be a Seurat object")

  reds <- names(seurat@reductions)
  if (!is.null(reductions)) reds <- intersect(reds, as.character(reductions))
  .wb_assert(length(reds) > 0, "No Seurat reductions selected for export")

  out <- setNames(vector("list", length(reds)), reds)
  for (r in reds) {
    emb <- seurat@reductions[[r]]@cell.embeddings
    .wb_assert(!is.null(emb), paste0("Reduction has no embeddings: ", r))
    out[[r]] <- wb_add_space(
      bundle = bundle,
      space_id = r,
      coords = emb,
      description = r,
      source = source,
      overwrite = overwrite
    )
  }
  invisible(out)
}
