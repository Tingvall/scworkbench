.all_contracts <- function(readers, writers, params, context) {
  invisible(lapply(readers, function(reader) reader()))
  cell <- "cell_1"
  matrix_value <- function(profile) structure(list(kind = "matrix", values = matrix(1, 1, 1),
    dimensions = c(1L, 1L), cell_id = cell, feature_id = "feature_1",
    storage_profile = profile), class = "wb_primitive")
  space_value <- function(profile, dimensions = 1L) structure(list(kind = "space",
    values = matrix(seq_len(dimensions), 1, dimensions), dimensions = c(1L, dimensions),
    cell_id = cell, storage_profile = profile), class = "wb_primitive")
  space_2d <- structure(list(kind = "space_2d", values = matrix(c(0, 1), 1, 2),
    dimensions = c(1L, 2L), cell_id = cell, storage_profile = "space_2d_dense_v1"),
    class = "wb_primitive")
  writers$write_matrix("matrix_ordinary", matrix_value("matrix_ordinary_v1"))
  writers$write_matrix("matrix_backed", matrix_value("matrix_backed_chunked_v1"))
  writers$write_space("space_dense", space_value("space_dense_v1", 1L))
  writers$write_space("space_file", space_value("space_file_backed_hdf5_v1", 1L))
  writers$write_space_2d("space_materialized_2d", space_2d)
  writers$write_space_2d("space_terminal_2d", space_2d)
  writers$write_model_ref("model", structure(list(kind = "model_ref", engine = "synthetic",
    model_space_id = "space_file", in_space_id = "matrix_backed",
    payload_tree = list(`model.txt` = "synthetic")), class = "wb_primitive"))
  writers$write_terminal_primitive("cell_vector", scworkbench::wb_prim_cell_vector(
    stats::setNames("a", cell), value_type = "categorical", meta = list(fixture = "v2")))
  writers$write_terminal_primitive("cell_vector_family", scworkbench::wb_prim_cell_vector_family(
    "k", cell, 1, meta = list(fixture = "v2")))
  writers$write_terminal_primitive("relation_family", scworkbench::wb_prim_relation_family(
    "k", cell, value = 1, meta = list(fixture = "v2")))
  writers$write_terminal_primitive("feature_table", scworkbench::wb_prim_feature_table(
    data.frame(feature_id = "feature_1"), table_type = "v2_fixture"))
  writers$write_terminal_primitive("obs_table", scworkbench::wb_prim_obs_table(
    data.frame(value = 1), table_type = "v2_fixture"))
  writers$write_path_2d_family("path_2d", scworkbench::wb_prim_path_2d_family(
    "p", 1L, 0, 1, meta = list(fixture = "v2")))
  writers$write_space_path_family("space_path", scworkbench::wb_prim_space_path_family(
    "space_file", "p", 1L, 1L, 0, meta = list(fixture = "v2")))
  writers$request_cell_set_admission("cell_set", list(name = "v2_cells", cells = cell))
  writers$request_cell_set_family_admission("cell_set_family", list(
    kind = "cell_set_family_admission", sets = list(), mode = "add",
    source = list(label = "operation_pack_v2_family_fixture",
      created_by = NULL, input_artifact_id = NULL, input_run_id = NULL,
      input_snapshot_id = NULL)))
  invisible(list(status = "ok"))
}

.cell_set_family_contract <- function(readers, writers, params, context) {
  or_default <- function(value, default) if (is.null(value)) default else value
  labels <- readers$labels()
  cells <- as.character(labels$cell_id)
  values <- as.character(labels$value)
  keep <- !is.na(values) & nzchar(values)
  keys <- sort(unique(values[keep]), method = "radix")
  prefix <- as.character(or_default(params$prefix, "family_"))[1]
  sets <- lapply(keys, function(key) {
    members <- rev(cells[keep & values == key])
    list(
      name = paste0("set:", prefix, gsub("[^A-Za-z0-9_.-]", "_", key)),
      cells = members,
      description = paste0("Synthetic family for ", key),
      selection_rule = paste0("label == '", key, "'")
    )
  })
  manifest <- if (length(sets)) data.frame(
    cell_set = vapply(sets, `[[`, character(1), "name"),
    label = keys,
    n_cells = as.integer(vapply(sets, function(x) length(x$cells), integer(1))),
    stringsAsFactors = FALSE
  ) else data.frame(
    cell_set = character(), label = character(), n_cells = integer(),
    stringsAsFactors = FALSE)
  writers$write_terminal_primitive("manifest", scworkbench::wb_prim_obs_table(
    manifest, table_type = "cell_set_family_manifest"))
  writers$request_cell_set_family_admission("cell_set_family", list(
    kind = "cell_set_family_admission", sets = rev(sets),
    mode = as.character(or_default(params$mode, "add"))[1],
    source = list(
      label = as.character(or_default(params$source_label,
        "operation_pack_v2_family_fixture"))[1],
      created_by = NULL, input_artifact_id = NULL, input_run_id = NULL,
      input_snapshot_id = NULL)))
  invisible(list(status = "ok"))
}

.single_cell_set_contract <- function(readers, writers, params, context) {
  labels <- readers$labels()
  cells <- as.character(labels$cell_id)
  writers$write_terminal_primitive("manifest", scworkbench::wb_prim_obs_table(
    data.frame(cell_set = "set:single_contract", n_cells = length(cells),
      stringsAsFactors = FALSE), table_type = "single_cell_set_manifest"))
  writers$request_cell_set_admission("cell_set", list(
    name = "set:single_contract", cells = cells))
  invisible(list(status = "ok"))
}

.feature_set_registry_contract <- function(readers, writers, params, context) {
  or_default <- function(value, default) if (is.null(value)) default else value
  registry <- readers$feature_sets()
  sets <- registry$sets
  rows <- if (length(sets)) do.call(rbind, lapply(sets, function(item) {
    data.frame(
      namespace = as.character(or_default(item$namespace, "")),
      feature_set = as.character(item$feature_set),
      n_features = as.integer(item$n_features),
      members = paste(vapply(item$memberships, `[[`, character(1), "feature_id"),
        collapse = ","),
      ranks = paste(vapply(item$memberships, function(x) as.integer(x$rank), integer(1)),
        collapse = ","),
      source_id = as.character(or_default(item$source_id, "")),
      recipe_json = as.character(or_default(item$recipe_json, "")),
      stringsAsFactors = FALSE
    )
  })) else data.frame(
    namespace = character(), feature_set = character(), n_features = integer(),
    members = character(), ranks = character(), source_id = character(),
    recipe_json = character(), stringsAsFactors = FALSE)
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    rows, table_type = "synthetic_feature_set_registry_summary",
    entity_kind = "feature_set", meta = list(
      matrix_id = registry$matrix_id,
      feature_universe = unlist(registry$feature_universe, use.names = FALSE))))
  invisible(list(status = "ok"))
}

.dynamic_provider <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  cells <- as.character(matrix$cell_id)
  writers$write_terminal_primitive("provider", scworkbench::wb_prim_cell_vector(
    stats::setNames(rep("available", length(cells)), cells), meta = list(provider = matrix$meta$genome_provider)))
  invisible(list(status = "ok"))
}

.two_table_terminal <- function(readers, writers, params, context) {
  a <- readers$a()
  b <- readers$b()
  cells <- intersect(as.character(a$cell_id), as.character(b$cell_id))
  detail <- data.frame(
    cell_id = cells,
    value_a = as.character(a$value[match(cells, a$cell_id)]),
    value_b = as.character(b$value[match(cells, b$cell_id)]),
    stringsAsFactors = FALSE
  )
  summary <- data.frame(
    record_type = "paired_cell_vectors",
    n_cells = length(cells),
    stringsAsFactors = FALSE
  )
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    summary, "synthetic_pair_summary", "pair"))
  writers$write_terminal_primitive("detail", scworkbench::wb_prim_obs_table(
    detail, "synthetic_pair_detail", "cell"))
  invisible(list(status = "ok"))
}

.feature_table_from_matrix <- function(readers, writers, params, context) {
  matrix <- readers$matrix(features = params$selected_features)
  labels <- readers$labels()
  features <- as.character(matrix$feature_id)
  limit <- min(length(features), as.integer(params$result_limit))
  rows <- data.frame(
    feature_id = utils::head(features, limit),
    observed_cells = length(intersect(matrix$cell_id, labels$cell_id)),
    stringsAsFactors = FALSE
  )
  writers$write_terminal_primitive("result", scworkbench::wb_prim_feature_table(
    rows, "synthetic_feature_result", meta = list(
      matrix_id = matrix$matrix_id, selected_feature_count = length(features),
      result_limit = limit)))
  invisible(list(status = "ok"))
}

.grouped_feature_table <- function(readers, writers, params, context) {
  cells <- unique(c(unlist(params$left_cells, use.names = FALSE),
    unlist(params$right_cells, use.names = FALSE)))
  matrix <- readers$matrix(features = params$selected_features, cells = cells)
  rows <- data.frame(
    feature_id = as.character(matrix$feature_id),
    observed_cells = length(matrix$cell_id),
    stringsAsFactors = FALSE
  )
  writers$write_terminal_primitive("result", scworkbench::wb_prim_feature_table(
    rows, "synthetic_grouped_feature_result", meta = list(
      matrix_id = matrix$matrix_id,
      left_n = length(params$left_cells), right_n = length(params$right_cells))))
  invisible(list(status = "ok"))
}

.chunked_feature_table <- function(readers, writers, params, context) {
  items <- unlist(params$items, use.names = FALSE)
  batch_size <- as.integer(params$batch_size)
  batches <- split(items, ceiling(seq_along(items) / batch_size))
  rows <- lapply(batches, function(batch) {
    value <- readers$matrix(features = batch)
    data.frame(feature_id = as.character(value$feature_id), p_val = 1,
      stringsAsFactors = FALSE)
  })
  writers$write_terminal_primitive("result", scworkbench::wb_prim_feature_table(
    do.call(rbind, rows), "synthetic_chunked_feature_result"))
  invisible(list(status = "ok"))
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json", package = "scwbV2Reference"),
    list(
      `scwbv2reference::all_contracts` = .all_contracts,
      `scwbv2reference::dynamic_provider` = .dynamic_provider,
      `scwbv2reference::two_table_terminal` = .two_table_terminal,
      `scwbv2reference::feature_table_from_matrix` = .feature_table_from_matrix,
      `scwbv2reference::grouped_feature_table` = .grouped_feature_table,
      `scwbv2reference::chunked_feature_table` = .chunked_feature_table,
      `scwbv2reference::cell_set_family_contract` = .cell_set_family_contract,
      `scwbv2reference::single_cell_set_contract` = .single_cell_set_contract,
      `scwbv2reference::feature_set_registry_contract` = .feature_set_registry_contract
    )
  )
}
