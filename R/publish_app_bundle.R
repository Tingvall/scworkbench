#' Publish a scworkbench app bundle from a Seurat object
#'
#' Compatibility publisher routed through the canonical Seurat ingestion and
#' staged bundle-promotion transaction. The destination is not touched until a
#' complete, provenance-bearing bundle has been assembled successfully.
#'
#' A published bundle is matrix_id-native:
#' - Seurat assays are only used during ingestion.
#' - The SQLite schema stores features keyed by matrix_id (not assay).
#' - matrices table has no assay column.
#'
#' @param seurat A Seurat object.
#' @param out_dir Output directory for the bundle. If `NULL`, a default is chosen.
#' @param dataset_col Optional meta.data column used as dataset identity.
#' @param bundle_id Optional bundle identifier used for default naming.
#' @param bundle_name Optional human-readable bundle name.
#' @param overwrite Whether an existing destination may be atomically replaced
#'   after successful staged assembly.
#' @param export_assays Seurat assays to export. If `NULL`, sane defaults are
#'   selected.
#' @param matrix_layer Default Seurat layer/slot to export.
#' @param matrix_specs Optional list produced by [wb_matrix_spec()].
#' @param feature_type_map Optional named assay-to-feature-type mapping.
#' @param write_spaces Whether Seurat reductions are ingested as spaces.
#' @param write_matrices Whether matrix payloads are ingested.
#'
#' @return The reopened published manifest, invisibly.
#' @export
wb_publish_app_bundle <- function(
    seurat,
    out_dir = NULL,
    dataset_col = NULL,
    bundle_id = NULL,
    bundle_name = NULL,
    overwrite = FALSE,
    export_assays = NULL,
    matrix_layer = "counts",
    matrix_specs = NULL,
    feature_type_map = NULL,
    write_spaces = TRUE,
    write_matrices = TRUE
) {
  .wb_assert(inherits(seurat, "Seurat"), "seurat must be a Seurat object")

  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  if (is.null(bundle_id) || !nzchar(bundle_id)) bundle_id <- paste0("scworkbench_", stamp)
  if (is.null(bundle_name) || !nzchar(bundle_name)) bundle_name <- bundle_id
  if (is.null(out_dir) || !nzchar(out_dir)) {
    base_out <- Sys.getenv("SCWORKBENCH_OUT_DIR", unset = "")
    if (!nzchar(base_out)) base_out <- file.path(getwd(), "scworkbench_bundles")
    out_dir <- file.path(base_out, bundle_id)
  }

  final_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  .wb_assert(is.character(final_dir) && length(final_dir) == 1L && nzchar(final_dir),
             "out_dir must be a non-empty path")
  if (dir.exists(final_dir) && !isTRUE(overwrite)) {
    stop("out_dir exists: ", out_dir, " (set overwrite=TRUE)", call. = FALSE)
  }
  parent_dir <- dirname(final_dir)
  dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)

  export_assays <- export_assays %||% .wb_default_export_assays(seurat)
  if (is.null(matrix_specs)) {
    matrix_specs <- .wb_default_matrix_specs(
      seurat = seurat,
      layer = matrix_layer,
      export_assays = export_assays,
      feature_type_map = feature_type_map
    )
  }
  .wb_assert(is.list(matrix_specs), "matrix_specs must be a list")
  if (!isTRUE(write_matrices)) matrix_specs <- list()

  stage_dir <- tempfile(
    pattern = paste0(".", basename(final_dir), "_publish_staging_"),
    tmpdir = parent_dir
  )
  stage_bundle <- NULL
  final_bundle <- NULL
  backup_dir <- NULL
  promotion_started <- FALSE
  destination_lock <- NULL
  on.exit({
    if (!is.null(destination_lock)) .wb_bundle_writer_lock_release(destination_lock)
  }, add = TRUE)

  source_identity <- list(
    source_type = "Seurat",
    publisher = "wb_publish_app_bundle",
    inputs = list(list(
      uri = "scworkbench-ingestion://wb_publish_app_bundle/in-memory-seurat",
      role = "source_object",
      format = "Seurat"
    ))
  )

  result <- tryCatch({
    stage_bundle <- wb_bundle_from_seurat(
      input = seurat,
      bundle_dir = stage_dir,
      matrix_specs = matrix_specs,
      reductions = if (isTRUE(write_spaces)) NULL else character(0),
      create_cell_sets = FALSE,
      dataset_col = dataset_col,
      overwrite = TRUE,
      created_by = "wb_publish_app_bundle",
      emit_report_artifact = TRUE,
      source_identity = source_identity
    )
    wb_close_bundle(stage_bundle)
    stage_bundle <- NULL

    destination_lock <- .wb_bundle_writer_lock_acquire(
      final_dir, operation = "application bundle publication"
    )
    if (dir.exists(final_dir) && !isTRUE(overwrite)) {
      stop("out_dir exists: ", out_dir, " (set overwrite=TRUE)", call. = FALSE)
    }

    # Keep an existing destination intact until staged construction succeeds.
    # Moving it aside in the same parent also gives failure recovery a precise,
    # validated target instead of deleting caller state pre-emptively.
    if (dir.exists(final_dir)) {
      backup_dir <- tempfile(
        pattern = paste0(".", basename(final_dir), "_publish_backup_"),
        tmpdir = parent_dir
      )
      .wb_assert(file.rename(final_dir, backup_dir),
                 "Could not stage the existing publish destination for atomic replacement.")
    }

    promotion_started <- TRUE
    final_bundle <- .wb_ingest_promote_staged_bundle(
      stage_dir, final_dir, source_type = "Seurat", overwrite = FALSE
    )
    final_bundle$manifest$bundle_id <- bundle_id
    final_bundle$manifest$bundle_name <- bundle_name
    final_bundle$manifest$creation$bundle_id <- bundle_id
    final_bundle$manifest$creation$bundle_name <- bundle_name
    id_policy <- final_bundle$manifest$id_policy %||% list()
    id_policy$compatibility_publisher <- "wb_publish_app_bundle"
    final_bundle$manifest$id_policy <- id_policy
    final_bundle$manifest$creation$id_policy <- id_policy
    manifest <- .wb_with_mutation_context(
      bundle = final_bundle,
      route = "ingestion",
      code = wb_refresh_manifest(final_bundle)
    )
    wb_close_bundle(final_bundle)
    final_bundle <- NULL
    if (!is.null(backup_dir) && dir.exists(backup_dir)) {
      unlink(backup_dir, recursive = TRUE, force = TRUE)
      backup_dir <- NULL
    }
    invisible(manifest)
  }, error = function(e) {
    if (!is.null(stage_bundle)) try(wb_close_bundle(stage_bundle), silent = TRUE)
    if (!is.null(final_bundle)) try(wb_close_bundle(final_bundle), silent = TRUE)
    if (dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE, force = TRUE)
    if (isTRUE(promotion_started) && dir.exists(final_dir)) {
      unlink(final_dir, recursive = TRUE, force = TRUE)
    }
    restore_error <- NULL
    if (!is.null(backup_dir) && dir.exists(backup_dir)) {
      if (!isTRUE(file.rename(backup_dir, final_dir))) {
        restore_error <- paste0(" Existing destination recovery failed from ", backup_dir, ".")
      }
    }
    stop(
      "wb_publish_app_bundle() staged Seurat ingestion failed; no partial published bundle was accepted. Error: ",
      conditionMessage(e), restore_error %||% "",
      call. = FALSE
    )
  })
  result
}

# ==============================================================================
# Seurat compatibility helpers shared with canonical ingestion.
# ==============================================================================

.wb_default_export_assays <- function(seurat) {
  assays <- names(seurat@assays)
  chosen <- character(0)
  if ("RNA" %in% assays) chosen <- c(chosen, "RNA")
  atac_candidates <- c("ATAC", "peaks", "Chromatin", "chromatin", "Peak", "Peaks")
  atac_hit <- intersect(atac_candidates, assays)
  if (length(atac_hit)) chosen <- c(chosen, atac_hit[1])
  if (!length(chosen)) chosen <- setdiff(assays, "SCT")
  unique(chosen)
}

.wb_guess_feature_type <- function(feature_ids) {
  sample_ids <- feature_ids[seq_len(min(2000L, length(feature_ids)))]
  peakish <- mean(grepl("^[^:]+:[0-9]+-[0-9]+$", sample_ids))
  if (is.finite(peakish) && peakish > 0.5) return("peak")
  "gene"
}

#' Define a Seurat matrix publication specification
#'
#' @param matrix_id Target bundle matrix identifier.
#' @param seurat_assay Source Seurat assay.
#' @param layer Source layer/slot.
#' @param feature_type Bundle feature type.
#' @param description Optional description.
#' @return A matrix publication specification list.
#' @export
wb_matrix_spec <- function(matrix_id,
                           seurat_assay,
                           layer = "counts",
                           feature_type = c("gene", "peak", "feature"),
                           description = NULL) {
  feature_type <- match.arg(feature_type)
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id required")
  .wb_assert(is.character(seurat_assay) && length(seurat_assay) == 1L && nzchar(seurat_assay), "seurat_assay required")
  list(
    matrix_id = matrix_id,
    seurat_assay = seurat_assay,
    layer = layer,
    feature_type = feature_type,
    description = description %||% paste0(
      "Matrix from Seurat assay '", seurat_assay, "' layer '", layer, "' (", feature_type, ")"
    )
  )
}

.wb_default_matrix_specs <- function(seurat,
                                     layer = "counts",
                                     export_assays = NULL,
                                     feature_type_map = NULL) {
  assays <- names(seurat@assays)
  if (!is.null(export_assays)) assays <- intersect(assays, export_assays)
  specs <- list()
  for (assay in assays) {
    features <- rownames(seurat@assays[[assay]])
    if (!length(features)) next
    feature_type <- if (!is.null(feature_type_map) && assay %in% names(feature_type_map)) {
      as.character(feature_type_map[[assay]])
    } else {
      .wb_guess_feature_type(features)
    }
    specs[[length(specs) + 1L]] <- wb_matrix_spec(
      matrix_id = paste0(assay, "_", layer),
      seurat_assay = assay,
      layer = layer,
      feature_type = feature_type,
      description = paste0("Exported from Seurat assay '", assay, "' (feature_type=", feature_type, ")")
    )
  }
  specs
}

.wb_parse_peak_ids <- function(peak_ids) {
  parsed <- do.call(rbind, lapply(peak_ids, function(peak_id) {
    match <- regexec("^([^:]+):([0-9]+)-([0-9]+)$", peak_id)
    fields <- regmatches(peak_id, match)[[1]]
    if (length(fields) == 4L) {
      c(chr = fields[2], start = fields[3], end = fields[4])
    } else {
      c(chr = NA_character_, start = NA_character_, end = NA_character_)
    }
  }))
  data.frame(
    chr = parsed[, "chr"],
    start = suppressWarnings(as.integer(parsed[, "start"])),
    end = suppressWarnings(as.integer(parsed[, "end"])),
    stringsAsFactors = FALSE
  )
}

.get_assay_counts <- function(seurat, assay, layer_or_slot = "counts") {
  assay_object <- seurat@assays[[assay]]
  .wb_assert(!is.null(assay_object), paste0("Unknown assay: ", assay))
  if (inherits(assay_object, "Assay5")) {
    matrix <- SeuratObject::LayerData(assay_object, layer = layer_or_slot)
  } else if (methods::is(assay_object, "Assay") && layer_or_slot %in% methods::slotNames(assay_object)) {
    matrix <- methods::slot(assay_object, layer_or_slot)
  } else if (requireNamespace("Seurat", quietly = TRUE)) {
    if ("layer" %in% names(formals(Seurat::GetAssayData))) {
      matrix <- Seurat::GetAssayData(seurat, assay = assay, layer = layer_or_slot)
    } else {
      matrix <- Seurat::GetAssayData(seurat, assay = assay, slot = layer_or_slot)
    }
  } else {
    stop(
      "Could not resolve assay data for assay '", assay,
      "' layer/slot '", layer_or_slot, "'.",
      call. = FALSE
    )
  }
  if (!inherits(matrix, "Matrix")) matrix <- Matrix::Matrix(matrix, sparse = TRUE)
  matrix
}

.align_matrix_to_ids <- function(matrix, feature_ids, cell_ids) {
  .wb_assert(!is.null(rownames(matrix)) && !is.null(colnames(matrix)),
             "Matrix must have rownames (features) and colnames (cells) to align")
  feature_index <- match(feature_ids, rownames(matrix))
  cell_index <- match(cell_ids, colnames(matrix))
  .wb_assert(!anyNA(feature_index), "Some features are missing from the assay matrix")
  .wb_assert(!anyNA(cell_index), "Some cells are missing from the assay matrix")
  matrix[feature_index, cell_index, drop = FALSE]
}
