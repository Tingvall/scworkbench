.fit_sibling_model <- function(readers, writers, params, context) {
  source <- readers$source()
  cells <- as.character(source$cell_id)
  writers$write_terminal_primitive("embedding",
    scworkbench::wb_prim_cell_vector(stats::setNames(
      seq_along(cells), cells), value_type = "continuous",
      meta = list(fixture = "phase5")))
  tree <- writers$open_model_tree("model")
  writeBin(charToRaw("phase5-contained-model-v1"),
    tree$path(tree$primary_path))
  model <- scworkbench::wb_prim_model_ref("fixture.output",
    as.character(context$input_ids$source)[1], engine = "fixture")
  model$model_type <- "phase5_model"
  tree$finish(model)
  invisible(list(status = "ok"))
}

.consume_self_linked_model <- function(readers, writers, params, context) {
  payload <- readers$fitted_model()
  bytes <- payload$read_bytes(payload$primary_path)
  stopifnot(identical(bytes,
    readBin(payload$runtime_private_path(payload$primary_path), "raw",
      n = length(bytes))))
  writers$write_terminal_primitive("summary",
    scworkbench::wb_prim_obs_table(data.frame(
      byte_count = length(bytes),
      sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE),
      stringsAsFactors = FALSE), table_type = "phase5_model_summary",
      meta = list(fixture = "phase5")))
  invisible(list(status = "ok"))
}

.adopt_external_state <- function(readers, writers, params, context) {
  adoption <- readers$adoption()
  tree <- writers$open_model_tree("model")
  for (entry in adoption$entries) {
    tree$write_bytes(entry$path, adoption$read_bytes(entry$path))
  }
  cells <- as.character(context$effective_cells)
  writers$write_terminal_primitive("summary",
    scworkbench::wb_prim_cell_vector(stats::setNames(
      rep("adopted", length(cells)), cells), value_type = "categorical",
      meta = list(execution = "external_state_adoption")))
  model <- scworkbench::wb_prim_model_ref("fixture.adopted",
    as.character(context$input_ids$source)[1], engine = "fixture")
  model$model_type <- "external_state"
  tree$finish(model)
  list(pack_source_association_attestation = TRUE,
    pack_no_refit_attestation = TRUE)
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json",
      package = "scwbV3Phase5"),
    list(
      `scwbv3phase5::fit_sibling_model` = .fit_sibling_model,
      `scwbv3phase5::consume_self_linked_model` =
        .consume_self_linked_model,
      `scwbv3phase5::adopt_external_state` = .adopt_external_state
    )
  )
}
