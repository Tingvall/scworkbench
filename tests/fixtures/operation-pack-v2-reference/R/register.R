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
  invisible(list(status = "ok"))
}

.dynamic_provider <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  cells <- as.character(matrix$cell_id)
  writers$write_terminal_primitive("provider", scworkbench::wb_prim_cell_vector(
    stats::setNames(rep("available", length(cells)), cells), meta = list(provider = matrix$meta$genome_provider)))
  invisible(list(status = "ok"))
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json", package = "scwbV2Reference"),
    list(
      `scwbv2reference::all_contracts` = .all_contracts,
      `scwbv2reference::dynamic_provider` = .dynamic_provider
    )
  )
}

