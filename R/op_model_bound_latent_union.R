#' Combine Fitted And Projected Latent Coordinates Under One Model Identity
#'
#' Creates a new durable latent space from a model's fitted reference space and
#' a disjoint projected query space. The projection summary must identify the
#' same model and query-space output. This operation combines existing
#' coordinates; it does not fit, transform, or otherwise alter them.
#'
#' @param bundle Open scworkbench bundle.
#' @param reference_space Space primitive containing coordinates fitted by the
#'   supplied model.
#' @param query_space Disjoint space primitive containing query coordinates
#'   projected through the supplied model.
#' @param model Retained PeakVI or scVI `model_ref` primitive.
#' @param projection_summary One-row projection receipt emitted by the
#'   registered projection operation.
#' @param cells Complete union of reference and query cell ids, resolved by the
#'   session engine.
#' @param space_id_out New identity for the unchanged row-wise coordinate
#'   union.
#' @return Standard operation result containing the combined space reference
#'   and a model-bound union summary.
#' @export
wb_op_model_bound_latent_union <- function(bundle,
                                           reference_space,
                                           query_space,
                                           model,
                                           projection_summary,
                                           cells,
                                           space_id_out = "model_bound_latent_union") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "model_bound_latent_union")
  .wb_assert_kind(reference_space, "space")
  .wb_assert_kind(query_space, "space")
  .wb_assert_kind(model, "model_ref")
  .wb_assert_kind(projection_summary, "obs_table")

  engine <- tolower(as.character(model$engine %||% "")[1])
  .wb_assert(engine %in% c("peakvi", "scvi"),
             "model_bound_latent_union requires a PeakVI or scVI model_ref")
  reference_space_id <- as.character(reference_space$space_id %||% "")[1]
  query_space_id <- as.character(query_space$space_id %||% "")[1]
  model_space_id <- as.character(model$model_space_id %||% model$space_id %||% "")[1]
  model_artifact_id <- as.character(model$artifact_id %||% "")[1]
  space_id_out <- as.character(space_id_out %||% "")[1]
  .wb_assert(all(nzchar(c(reference_space_id, query_space_id, model_space_id, space_id_out))),
             "model_bound_latent_union requires non-empty source, model, and output space identities")
  .wb_assert(identical(reference_space_id, model_space_id),
             "reference_space must be the fitted model_space_id")
  .wb_assert(nzchar(model_artifact_id),
             "model_bound_latent_union requires a retained model artifact identity")
  retained_model <- DBI::dbGetQuery(
    bundle$con,
    "SELECT a.type, m.engine, m.model_space_id
     FROM artifacts AS a
     JOIN artifact_model_ref AS m ON m.artifact_id = a.artifact_id
     WHERE a.artifact_id = ?;",
    params = list(model_artifact_id)
  )
  .wb_assert(
    nrow(retained_model) == 1L &&
      identical(as.character(retained_model$type[[1L]]), "model_ref") &&
      identical(tolower(as.character(retained_model$engine[[1L]])), engine) &&
      identical(as.character(retained_model$model_space_id[[1L]]), model_space_id),
    "model_bound_latent_union model identity is not registered as the supplied retained model"
  )
  .wb_assert(!identical(reference_space_id, query_space_id),
             "reference_space and query_space must be distinct")
  .wb_assert(!space_id_out %in% wb_spaces(bundle)$space_id,
             paste0("model_bound_latent_union output space already exists: ", space_id_out))

  projection <- projection_summary$table %||% data.frame()
  .wb_assert(is.data.frame(projection) && nrow(projection) == 1L,
             "projection_summary must contain exactly one projection receipt row")
  expected_receipt_type <- paste0(engine, "_project_summary")
  .wb_assert(identical(as.character(projection_summary$table_type %||% "")[1], expected_receipt_type),
             paste0("projection_summary must have table_type='", expected_receipt_type, "'"))
  .wb_assert(identical(tolower(as.character(projection$engine %||% "")[1]), engine),
             "projection_summary engine does not match the supplied model")
  .wb_assert(identical(as.character(projection$projection_mode %||% "")[1], "transform_without_refit"),
             "projection_summary does not attest projection without refitting")
  .wb_assert(identical(as.character(projection$output_space_id %||% "")[1], query_space_id),
             "projection_summary output_space_id does not match query_space")
  .wb_assert(identical(as.character(projection$model_space_id %||% "")[1], model_space_id),
             "projection_summary model_space_id does not match the supplied model")
  receipt_artifact_id <- as.character(projection$model_artifact_id %||% "")[1]
  .wb_assert(nzchar(receipt_artifact_id) && identical(receipt_artifact_id, model_artifact_id),
             "projection_summary model_artifact_id does not match the supplied model")

  reference_cells <- wb_cells_with_space(bundle, reference_space_id)
  query_cells <- wb_cells_with_space(bundle, query_space_id)
  .wb_assert(length(reference_cells) > 0L && length(query_cells) > 0L,
             "model_bound_latent_union requires non-empty reference and query spaces")
  overlap <- intersect(reference_cells, query_cells)
  .wb_assert(!length(overlap), paste0(
    "reference and query latent spaces must have disjoint cell identities: ",
    paste(utils::head(overlap, 10L), collapse = ", ")
  ))

  cells <- unique(as.character(cells %||% character(0)))
  expected <- c(reference_cells, query_cells)
  .wb_assert(setequal(cells, expected) && length(cells) == length(expected),
             "declared cells must equal the complete disjoint union of reference and query latent cells")
  canonical <- wb_cells(bundle, cell_set = "all")
  cells <- canonical[canonical %in% cells]

  reference_coords <- .wb_as_coord_matrix(wb_space(bundle, reference_space_id, cells = reference_cells))
  query_coords <- .wb_as_coord_matrix(wb_space(bundle, query_space_id, cells = query_cells))
  .wb_assert(ncol(reference_coords) == ncol(query_coords),
             "reference and query latent spaces must have equal dimensions")
  receipt_dimensions <- suppressWarnings(as.integer(projection$n_latent %||% NA_integer_))[1]
  .wb_assert(is.finite(receipt_dimensions) && receipt_dimensions == ncol(query_coords),
             "projection_summary latent dimensionality does not match the query space")
  .wb_assert(ncol(reference_coords) >= 2L,
             "model_bound_latent_union requires at least two latent dimensions")
  .wb_assert(all(is.finite(reference_coords)) && all(is.finite(query_coords)),
             "reference and query latent coordinates must be finite")
  colnames(query_coords) <- colnames(reference_coords)
  combined <- rbind(reference_coords, query_coords)
  combined <- combined[match(cells, rownames(combined)), , drop = FALSE]
  .wb_assert(!anyNA(combined), "combined latent coordinates are incomplete")

  wb_add_space(
    bundle,
    space_id = space_id_out,
    coords = combined,
    description = paste0("Model-bound union of ", reference_space_id, " and ", query_space_id),
    source = paste0("model_bound_latent_union:", engine),
    overwrite = FALSE
  )

  summary <- data.frame(
    engine = engine,
    model_artifact_id = model_artifact_id,
    model_space_id = model_space_id,
    reference_space_id = reference_space_id,
    query_space_id = query_space_id,
    output_space_id = space_id_out,
    n_reference_cells = as.integer(length(reference_cells)),
    n_query_cells = as.integer(length(query_cells)),
    n_cells = as.integer(length(cells)),
    n_dimensions = as.integer(ncol(combined)),
    cells_disjoint = TRUE,
    coordinate_operation = "row_bind_without_transformation",
    projection_receipt_type = expected_receipt_type,
    projection_mode = "transform_without_refit",
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      space = wb_prim_space(space_id_out),
      union_summary = wb_prim_obs_table(
        summary,
        table_type = "model_bound_latent_union_summary",
        entity_kind = "space",
        meta = list(
          engine = engine,
          model_artifact_id = model_artifact_id,
          model_space_id = model_space_id,
          coordinate_operation = "row_bind_without_transformation",
          projection_receipt_type = expected_receipt_type,
          projection_mode = "transform_without_refit"
        )
      )
    ),
    params = as.list(summary[1, , drop = FALSE])
  )
}
