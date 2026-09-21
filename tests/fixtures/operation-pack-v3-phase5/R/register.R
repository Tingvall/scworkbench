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

.derived_subset <- function(readers, writers, params, context) {
  source <- readers$source()
  selected <- as.character(params$selected_cells)
  positions <- match(selected, as.character(source$cell_id))
  values <- source$value[positions]
  writers$write_terminal_primitive("vector",
    scworkbench::wb_prim_cell_vector(stats::setNames(values, selected),
      value_type = as.character(source$value_type),
      meta = list(fixture = "g7-subset")))
  if (isTRUE(params$fault_after_first_output)) stop("fixture partial write")
  keys <- paste0(as.character(params$key_prefix), c("score", "confidence"))
  writers$write_terminal_primitive("family",
    scworkbench::wb_prim_cell_vector_family(rep(keys, each = length(selected)),
      rep(selected, times = length(keys)), rep(seq_along(selected),
        times = length(keys)),
      value_type = "continuous", meta = list(fixture = "g7-subset")))
  grant <- context$derived_cell_output_axis_grants[[1L]]
  declaration <- scworkbench::wb_derived_cell_output_axis_declaration(grant,
    selected)
  declarations <- if (isTRUE(params$omit_declaration)) list() else if (
    isTRUE(params$repeat_declaration)) list(declaration, declaration) else
      list(declaration)
  list(derived_cell_output_axis_declarations = declarations)
}

.derived_union <- function(readers, writers, params, context) {
  grants <- context$derived_cell_output_axis_grants
  grant <- grants[[1L]]
  selected <- params$member_selections
  for (i in seq_along(grant$source_axes))
    readers$read_retained_artifact_collection_item("sources", i, "axis")
  final <- as.character(params$final_cells)
  writers$write_terminal_primitive("vector",
    scworkbench::wb_prim_cell_vector(stats::setNames(seq_along(final), final),
      value_type = "continuous", meta = list(fixture = "g7-union")))
  list(derived_cell_output_axis_declarations = list(
    scworkbench::wb_derived_cell_output_axis_declaration(grant, final,
      selected)))
}

.derived_effective_key <- function(readers, writers, params, context) {
  source <- readers$source()
  selected <- as.character(params$selected_cells)
  override <- !is.null(readers$override_present) &&
    is.null(readers$override_absent)
  key <- if (override) as.character(params$fallback_key) else if (
    is.null(params$primary_key)) as.character(params$fallback_key) else
      as.character(params$primary_key)
  if (!is.null(params$forge_key)) key <- as.character(params$forge_key)
  writers$write_terminal_primitive("family",
    scworkbench::wb_prim_cell_vector_family(rep(key, length(selected)),
      selected, source$value[match(selected, source$cell_id)],
      value_type = "continuous", meta = list(fixture = "g7-effective-key")))
  if (isTRUE(params$fault_after_output)) stop("effective key fixture fault")
  list(derived_cell_output_axis_declarations = list(
    scworkbench::wb_derived_cell_output_axis_declaration(
      context$derived_cell_output_axis_grants[[1L]], selected)))
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
      , `scwbv3phase5::derived_subset` = .derived_subset
      , `scwbv3phase5::derived_union` = .derived_union
      , `scwbv3phase5::derived_effective_key` = .derived_effective_key
    )
  )
}
