# Semantic inventory of scientific-state mutation ownership.

.wb_mutating_op_implementations <- function() c(
  "wb_op_matrix_log_normalize", "wb_op_pca_fit", "wb_op_umap_fit",
  "wb_op_umap_transform", "wb_op_palantir_fit", "wb_op_palantir_project",
  "wb_op_peakvi_project", "wb_op_feature_set_import"
)

.wb_mutation_inventory_groups <- function() list(
  registry_writer = c(
    "wb_set_create", "wb_cell_set_add", "wb_cell_set_remove", "wb_cell_set_set",
    "wb_cell_set_replace", "wb_cell_set_define", "wb_cell_set_derive",
    "wb_set_cell_set_style", "wb_feature_set_replace", "wb_feature_set_delete",
    "wb_feature_set_import_table", "wb_feature_set_import_list",
    "wb_feature_set_namespace_transfer", "wb_register_winner_cell_sets",
    "wb_matrix_set_genome", "wb_motif_library_register", "wb_motif_register",
    "wb_motif_library_import_jaspar", "wb_motif_match_replace"
  ),
  matrix_space_model_writer = c(
    "wb_add_space", "wb_register_matrix_fragment", "wb_attach_cell_vector",
    "wb_op_scvi_train", "wb_op_peakvi_fit", "wb_op_peakvi_project",
    ".wb_pybench_preregister_outputs", ".wb_promote_model_ref",
    "wb_repair_model_ref_paths"
  ),
  attachment_ingestion = c(
    "wb_init_bundle", "wb_define_cells", "wb_define_cells_from_seurat",
    "wb_attach_validate", "wb_attach_normalize",
    "wb_attach_apply", "wb_attach_to_cells", "wb_attach_matrix",
    "wb_attach_matrix_from_seurat", "wb_attach_space",
    "wb_attach_spaces_from_seurat", "wb_attach_metadata", "wb_ingest_apply",
    "wb_ingest_validate", "wb_ingest_normalize", "wb_ingest_report",
    "wb_ingest_reports", "wb_ingest_cells", "wb_bundle_from_10x_mtx", "wb_bundle_from_h5ad",
    "wb_bundle_from_sce", "wb_bundle_from_seurat", "wb_publish_app_bundle"
  ),
  guarded_derived_state_writer = c("wb_refresh_manifest"),
  primitive_payload_writer = c(
    "wb_promote_analysis", "wb_session_promote_current", "wb_client_promote",
    "wb_write_cell_vector", "wb_register_cell_vector",
    ".wb_promote_cell_vector", ".wb_promote_cell_vector_family",
    ".wb_promote_feature_table", ".wb_promote_obs_table",
    ".wb_promote_path_2d_family", ".wb_promote_relation_family",
    ".wb_promote_space_path_family", ".wb_promote_space_2d_ref",
    ".wb_stage_prepare_materializations", ".wb_prepare_materialization_payloads"
  )
)

.wb_mutation_route_for <- function(function_name, category, exported) {
  pure_attachment <- c(
    "wb_attach_validate", "wb_attach_normalize", "wb_ingest_validate",
    "wb_ingest_normalize", "wb_ingest_report", "wb_ingest_reports"
  )
  declared_ingestion <- c(
    "wb_init_bundle", "wb_define_cells", "wb_define_cells_from_seurat",
    "wb_attach_apply", "wb_attach_matrix", "wb_attach_matrix_from_seurat",
    "wb_attach_space", "wb_attach_spaces_from_seurat", "wb_attach_metadata",
    "wb_ingest_apply", "wb_bundle_from_10x_mtx", "wb_bundle_from_h5ad",
    "wb_bundle_from_sce", "wb_bundle_from_seurat", "wb_publish_app_bundle",
    "wb_attach_cell_vector",
    "wb_feature_set_import_table", "wb_feature_set_import_list",
    "wb_motif_library_import_jaspar"
  )
  promotion <- c("wb_promote_analysis", "wb_session_promote_current", "wb_client_promote")
  administrative <- c("wb_repair_model_ref_paths")
  guarded_derived_state <- c("wb_refresh_manifest")
  assembly_only <- c(
    "wb_add_space", "wb_register_matrix_fragment", "wb_attach_to_cells",
    "wb_ingest_cells", "wb_matrix_set_genome",
    "wb_motif_library_register", "wb_motif_register", "wb_motif_match_replace"
  )

  if (function_name %in% pure_attachment) {
    return(list(durable = FALSE, route = "direct_pure_validation", boundary = "pure"))
  }
  if (function_name %in% administrative) {
    return(list(durable = FALSE, route = "explicit_administrative_repair", boundary = "administrative_non_scientific"))
  }
  if (function_name %in% guarded_derived_state) {
    return(list(
      durable = TRUE,
      route = "engine_guarded_internal_refresh",
      boundary = "guarded_internal"
    ))
  }
  if (function_name %in% declared_ingestion) {
    return(list(durable = TRUE, route = "declared_ingestion_transaction", boundary = "public_transaction"))
  }
  if (function_name %in% promotion || startsWith(function_name, ".wb_promote_")) {
    return(list(durable = TRUE, route = "provenance_promotion", boundary = if (exported) "public_transaction" else "internal"))
  }
  if (function_name %in% assembly_only) {
    return(list(durable = TRUE, route = "active_bundle_assembly_transaction", boundary = "guarded_low_level"))
  }
  if (startsWith(function_name, "wb_op_") && !(function_name %in% .wb_mutating_op_implementations())) {
    return(list(durable = FALSE, route = "direct_pure_computation", boundary = "pure"))
  }
  list(
    durable = TRUE,
    route = "registered_session_execution_and_promotion",
    boundary = if (exported) "guarded_implementation" else "internal"
  )
}

#' Export the Scientific Mutation Route Catalog
#'
#' Inventories operation implementations, registry writers, matrix/space/model
#' writers, attachment and ingestion APIs, and primitive payload writers. Every
#' durable public transformation declares exactly one supported
#' provenance-producing route; engine-internal contexts are implementation
#' details of that route, not alternate caller entry points.
#'
#' @return JSON-friendly mutation catalog and invariant audit.
#' @export
wb_mutation_catalog_semantic <- function() {
  exports <- getNamespaceExports("scworkbench")
  exported_ops <- sort(exports[startsWith(exports, "wb_op_")])
  guard_calls <- c(".wb_assert_mutation_context", ".wb_assert_operation_execution")
  exported_guarded <- sort(exports[vapply(exports, function(fn) {
    value <- getExportedValue("scworkbench", fn)
    is.function(value) && any(all.names(body(value), functions = TRUE) %in% guard_calls)
  }, logical(1))])
  groups <- .wb_mutation_inventory_groups()
  records <- list()

  add_record <- function(fn, category) {
    key <- fn
    if (!is.null(records[[key]])) return(invisible(NULL))
    exported <- fn %in% exports
    implemented <- exists(fn, envir = asNamespace("scworkbench"), inherits = FALSE)
    route <- .wb_mutation_route_for(fn, category, exported)
    records[[key]] <<- list(
      interface_id = paste(category, fn, sep = ":"),
      function_name = fn,
      category = category,
      exported = exported,
      implemented = implemented,
      durable_mutation = isTRUE(route$durable),
      supported_route = route$route,
      supported_route_count = if (isTRUE(route$durable)) 1L else 0L,
      boundary = route$boundary,
      direct_committed_write = FALSE
    )
  }
  for (fn in exported_ops) add_record(fn, "operation_implementation")
  for (category in names(groups)) for (fn in groups[[category]]) add_record(fn, category)

  recs <- unname(records)
  meaningful <- Filter(function(x) isTRUE(x$exported) && isTRUE(x$durable_mutation), recs)
  bad <- Filter(function(x) !identical(as.integer(x$supported_route_count), 1L), meaningful)
  missing <- Filter(function(x) !isTRUE(x$implemented), recs)
  cataloged_functions <- vapply(recs, function(x) x$function_name, character(1))
  missing_guarded <- setdiff(exported_guarded, cataloged_functions)
  list(
    schema_version = "scworkbench.mutation_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    record_count = length(recs),
    meaningful_public_transformation_count = length(meaningful),
    exported_guarded_function_count = length(exported_guarded),
    exported_guarded_functions = exported_guarded,
    invariant = list(
      name = "one_supported_provenance_route_per_public_meaningful_transformation",
      ok = !length(bad) && !length(missing) && !length(missing_guarded),
      violation_ids = c(
        vapply(bad, function(x) x$interface_id, character(1)),
        if (length(missing)) {
          paste0("missing_implementation:", vapply(missing, function(x) x$interface_id, character(1)))
        } else character(0),
        if (length(missing_guarded)) {
          paste0("uncataloged_exported_guard:", missing_guarded)
        } else character(0)
      )
    ),
    records = recs
  )
}

.wb_mutation_catalog_reference_lines <- function(catalog) {
  lines <- c(
    "# scworkbench Scientific Mutation Route Catalog", "",
    "<!-- Generated from wb_mutation_catalog_semantic(); do not edit entries by hand. -->", "",
    paste0("Record count: ", catalog$record_count), "",
    paste0("Meaningful public transformations: ", catalog$meaningful_public_transformation_count), "",
    paste0("Exported directly guarded functions: ", catalog$exported_guarded_function_count), "",
    paste0("Exactly-one-route invariant: ", if (isTRUE(catalog$invariant$ok)) "PASS" else "FAIL"), ""
  )
  for (rec in catalog$records) {
    lines <- c(lines,
      paste0("## `", rec$function_name, "`"), "",
      paste0("Category: ", rec$category), "",
      paste0("Exported: ", tolower(as.character(rec$exported))), "",
      paste0("Implemented: ", tolower(as.character(rec$implemented))), "",
      paste0("Durable mutation: ", tolower(as.character(rec$durable_mutation))), "",
      paste0("Boundary: `", rec$boundary, "`"), "",
      paste0("Supported route: `", rec$supported_route, "`"), ""
    )
  }
  while (length(lines) && !nzchar(lines[[length(lines)]])) {
    lines <- head(lines, -1L)
  }
  lines
}

#' Write the Scientific Mutation Route Catalog Reference
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @return Invisibly returns the mutation catalog from
#'   `wb_mutation_catalog_semantic()`.
#' @export
wb_write_mutation_catalog_reference <- function(
    path_md = "docs/mutation_catalog_reference.md",
    path_json = "docs/mutation_catalog_semantic.json") {
  catalog <- wb_mutation_catalog_semantic()
  .wb_assert(isTRUE(catalog$invariant$ok), "Scientific mutation route catalog invariant failed.")
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    markdown_lines <- sub("[[:blank:]]+$", "", .wb_mutation_catalog_reference_lines(catalog))
    writeLines(markdown_lines, path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}
