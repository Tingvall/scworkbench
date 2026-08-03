test_provenance_only_mutation_boundary_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)

  cells <- as.character(wb_cells(b, "all"))
  matrices <- wb_matrices(b)
  spaces <- wb_spaces(b)
  stopifnot(length(cells) >= 10L, nrow(matrices) >= 1L, nrow(spaces) >= 1L)
  matrix_id <- as.character(matrices$matrix_id[1])
  source_space <- as.character(spaces$space_id[1])

  scientific_state <- function(bundle) {
    tables <- intersect(
      c("matrices", "matrix_fragments", "spaces", "space_models", "artifacts",
        "feature_sets", "feature_set_membership", "cell_set_membership"),
      DBI::dbListTables(bundle$con)
    )
    db <- stats::setNames(lapply(tables, function(tbl) {
      x <- DBI::dbReadTable(bundle$con, tbl)
      if (nrow(x) && ncol(x)) {
        ord <- do.call(order, c(lapply(x, function(v) as.character(v)), list(na.last = TRUE)))
        x <- x[ord, , drop = FALSE]
      }
      rownames(x) <- NULL
      x
    }), tables)
    roots <- intersect(c("mat", "models", "artifact_models"), list.files(bundle$dir))
    paths <- sort(unlist(lapply(roots, function(root) {
      list.files(file.path(bundle$dir, root), recursive = TRUE, full.names = TRUE)
    }), use.names = FALSE))
    paths <- paths[file.info(paths)$isdir %in% FALSE]
    files <- if (length(paths)) data.frame(
      path = substring(paths, nchar(normalizePath(bundle$dir)) + 2L),
      size = as.numeric(file.info(paths)$size),
      md5 = unname(tools::md5sum(paths)),
      stringsAsFactors = FALSE
    ) else data.frame(path = character(), size = numeric(), md5 = character())
    list(db = db, files = files)
  }

  coords <- matrix(
    seq_len(length(cells) * 2L), nrow = length(cells), ncol = 2L,
    dimnames = list(cells, c("x", "y"))
  )
  attempts <- list(
    normalization = function() wb_op_matrix_log_normalize(
      b, matrix_id, output_matrix_id = ".__blocked_normalized__."
    ),
    pca = function() wb_op_pca_fit(
      b, matrix_id, cells = cells, feature_ids = head(wb_feature_ids(b, matrix_id), 10L),
      n_components = 2L, backend = "prcomp", space_id_out = ".__blocked_pca__."
    ),
    umap_fit = function() wb_op_umap_fit(
      b, source_space_id = source_space, cells = cells,
      space_id_out = ".__blocked_umap__."
    ),
    umap_transform = function() wb_op_umap_transform(
      b, model_space_id = ".__absent_model__.", in_space_id = source_space, cells = cells
    ),
    scvi = function() scworkbench:::wb_op_scvi_train(
      b, matrix_id = matrix_id, cells = cells, output_space_id = ".__blocked_scvi__."
    ),
    peakvi_fit = function() scworkbench:::wb_op_peakvi_fit(
      b, matrix_id = matrix_id, cells = cells, space_id_out = ".__blocked_peakvi__."
    ),
    peakvi_project = function() wb_op_peakvi_project(
      b, peakvi_model = NULL, matrix_id = matrix_id, cells = cells,
      space_id_out = ".__blocked_peakvi_project__."
    ),
    space_write = function() wb_add_space(b, ".__blocked_space__.", coords),
    registry = function() wb_cell_set_replace(b, ".__blocked_set__.", cells[1:2]),
    matrix_registry = function() wb_register_matrix_fragment(
      b$con, ".__blocked_matrix__.", ".__absent_payload__.", "f", cells[1]
    )
  )

  before <- scientific_state(b)
  old <- getOption("scworkbench.registry_mutation_context")
  options(scworkbench.registry_mutation_context = list(run_id = "forged", op_name = "pca_fit"))
  on.exit(options(scworkbench.registry_mutation_context = old), add = TRUE)
  errors <- lapply(attempts, function(f) try(f(), silent = TRUE))
  stopifnot(
    all(vapply(errors, inherits, logical(1), "try-error")),
    all(vapply(errors, function(x) grepl("cannot write directly to a committed bundle", as.character(x), fixed = TRUE), logical(1))),
    identical(before, scientific_state(b))
  )

  # Exported pure computation remains directly usable on committed state.
  hvg <- wb_op_hvg_select(
    b, matrix_id, cells = cells, n_features = 3L, method = "variance"
  )
  stopifnot(
    identical(hvg$outputs$selected_features$kind, "feature_table"),
    identical(before, scientific_state(b))
  )

  normalized_id <- ".__prov_boundary_normalized__."
  pca_id <- ".__prov_boundary_pca__."
  s <- wb_session_new()
  rr_norm <- wb_session_run_op(
    s, b, "matrix_log_normalize",
    inputs = list(matrix = matrix_id, output_matrix_id = normalized_id, cell_set = "all")
  )
  s <- rr_norm$session
  normalized_features <- head(wb_feature_ids(wb_session_view(s), normalized_id), 12L)
  stopifnot(length(normalized_features) >= 3L)

  # A session view is inspectable, but the handle alone does not carry writer
  # authority outside the dynamic registered runner invocation.
  staged_direct <- try(wb_add_space(wb_session_view(s), ".__blocked_stage_space__.", coords), silent = TRUE)
  stopifnot(inherits(staged_direct, "try-error"))

  rr_pca <- wb_session_run_op(
    s, b, "pca_fit",
    inputs = list(
      matrix = wb_ref_run(rr_norm$run$run_id, "matrix"),
      feature_ids = normalized_features,
      n_components = 2L,
      backend = "prcomp",
      space_id_out = pca_id,
      cell_set = "all"
    )
  )
  s <- rr_pca$session
  promoted <- wb_session_promote_current(
    b, s, outputs = "fit_summary", name_prefix = "provenance_boundary", created_by = "contract"
  )
  stopifnot(nrow(promoted$promoted) >= 1L)

  wb_close_bundle(b)
  b <- wb_open_bundle(bundle_dir)
  stopifnot(
    normalized_id %in% as.character(wb_matrices(b)$matrix_id),
    pca_id %in% as.character(wb_spaces(b)$space_id)
  )
  heads <- wb_prov_list_heads(b)
  sid <- as.character(heads$snapshot_id[1])
  persisted <- DBI::dbGetQuery(
    b$con,
    "SELECT run_id, op_name FROM prov_runs WHERE snapshot_id = ? ORDER BY run_id;",
    params = list(sid)
  )
  stopifnot(
    all(c(rr_norm$run$run_id, rr_pca$run$run_id) %in% persisted$run_id),
    all(c("matrix_log_normalize", "pca_fit") %in% persisted$op_name)
  )
  norm_details <- wb_prov_run_details(b, rr_norm$run$run_id, sid)
  pca_details <- wb_prov_run_details(b, rr_pca$run$run_id, sid)
  stopifnot(
    any(norm_details$outputs$primitive_kind == "matrix"),
    any(pca_details$outputs$primitive_kind == "space"),
    rr_norm$run$run_id %in% pca_details$parents
  )

  catalog <- wb_mutation_catalog_semantic()
  stopifnot(
    isTRUE(catalog$invariant$ok),
    !length(catalog$invariant$violation_ids),
    all(vapply(catalog$records, function(x) isTRUE(x$implemented), logical(1)))
  )
  capabilities <- wb_client_discover(
    b, include_op_interfaces = FALSE, include_vectors = FALSE,
    include_feature_sets = FALSE
  )$mutation_capabilities
  stopifnot(
    identical(capabilities$scientific_state_boundary, "provenance_only"),
    identical(capabilities$direct_mutating_implementation_calls, FALSE)
  )
  records <- catalog$records
  cataloged_functions <- vapply(records, function(x) x$function_name, character(1))
  cataloged_ops <- vapply(Filter(function(x) identical(x$category, "operation_implementation"), records),
    function(x) x$function_name, character(1))
  stopifnot(setequal(sort(getNamespaceExports("scworkbench")[startsWith(getNamespaceExports("scworkbench"), "wb_op_")]), sort(cataloged_ops)))
  attachment_exports <- grep(
    "^wb_(attach_|ingest_|bundle_from_|define_cells)",
    getNamespaceExports("scworkbench"), value = TRUE
  )
  stopifnot(!length(setdiff(attachment_exports, cataloged_functions)))

  # Completeness is derived from the exported function bodies themselves: no
  # directly guarded writer can be omitted while the invariant remains green.
  exports <- getNamespaceExports("scworkbench")
  guard_calls <- c(".wb_assert_mutation_context", ".wb_assert_operation_execution")
  exported_guarded <- sort(exports[vapply(exports, function(fn) {
    value <- getExportedValue("scworkbench", fn)
    is.function(value) && any(all.names(body(value), functions = TRUE) %in% guard_calls)
  }, logical(1))])
  stopifnot(
    identical(exported_guarded, sort(catalog$exported_guarded_functions)),
    identical(length(exported_guarded), catalog$exported_guarded_function_count),
    !length(setdiff(exported_guarded, cataloged_functions))
  )
  refresh_record <- Filter(function(x) identical(x$function_name, "wb_refresh_manifest"), records)
  publish_record <- Filter(function(x) identical(x$function_name, "wb_publish_app_bundle"), records)
  stopifnot(
    length(refresh_record) == 1L,
    identical(refresh_record[[1]]$supported_route, "engine_guarded_internal_refresh"),
    identical(refresh_record[[1]]$boundary, "guarded_internal"),
    length(publish_record) == 1L,
    identical(publish_record[[1]]$supported_route, "declared_ingestion_transaction"),
    identical(publish_record[[1]]$boundary, "public_transaction")
  )

  generated_md <- tempfile(fileext = ".md")
  generated_json <- tempfile(fileext = ".json")
  wb_write_mutation_catalog_reference(generated_md, generated_json)
  generated_lines <- readLines(generated_md, warn = FALSE)
  stopifnot(
    length(generated_lines) > 0L,
    nzchar(tail(generated_lines, 1L)),
    !any(grepl("[ \\t]+$", generated_lines)),
    is.list(jsonlite::read_json(generated_json, simplifyVector = FALSE))
  )

  client_source <- paste(readLines(file.path("R", "client_api.R"), warn = FALSE), collapse = "\n")
  stopifnot(
    grepl("wb_session_run_op", client_source, fixed = TRUE),
    grepl("wb_session_promote_current", client_source, fixed = TRUE)
  )
  TRUE
}
