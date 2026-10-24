# Source this file, then call public_getters_and_continuation(bundle_dir,
# workspace_root). Both paths must be new task-owned directories.
public_getters_and_continuation <- function(bundle_dir, workspace_root) {
  library(scworkbench)
  b <- wb_init_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  cells <- paste0("c", seq_len(12L))
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells, score = seq_len(12L)))
  wb_attach_matrix(b, "counts", matrix(seq_len(24L), nrow = 2L,
    dimnames = list(c("g1", "g2"), cells)), feature_type = "gene")
  s <- wb_session_create(b, workspace_root = workspace_root)
  r <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(
    source_column = "score", value_type = "continuous", vector_name = "score_vector",
    missing_policy = "error", cell_set = "all"))
  first <- wb_session_promote_current(b, r$session, outputs = "vector")
  s <- first$session  # terminal durable state returned by promotion
  aid <- first$promoted$artifact_id[first$promoted$output == "vector"]
  vector_id <- paste0("artifact:", aid)
  primitive <- wb_cell_vector_load(b, vector_id = vector_id, expected_kind = "cell_vector")
  values <- wb_read_cell_vector(b, vector_id, cells)
  metadata <- wb_meta(b, cols = c("cell_id", "score"))
  feature_values <- wb_vector(b, matrix_id = "counts", feature_id = "g1", cells = cells)
  selected <- wb_sel_vector(wb_sel_all(b), vector_id = vector_id, min = 7)

  # A fresh session observes the newly committed bundle and its retained vector.
  next_session <- wb_session_create(b, workspace_root = workspace_root)
  continued <- wb_session_run_op(next_session, b, "cell_set_derive", inputs = list(
    cell_ids = as.character(selected), target_cell_set = "set:high_score",
    role = "analysis_universe", status = "accepted", source = "selector_recipe",
    recipe = wb_recipe(selected), min_cells = 1L))
  second <- wb_session_promote_current(b, continued$session, outputs = c("manifest", "rule_table"))
  table_id <- second$promoted$artifact_id[second$promoted$output == "manifest"]
  table <- wb_art_load(b, table_id, expected_kind = "obs_table")$table
  list(bundle_dir = bundle_dir, first = first, second = second,
    vector_id = vector_id, primitive = primitive, values = values,
    metadata = metadata, feature_values = feature_values, table = table,
    sets = wb_cell_sets(b), members = wb_cells(b, "set:high_score"))
}
