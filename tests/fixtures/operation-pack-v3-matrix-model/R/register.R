.fit_matrix_model <- function(readers, writers, params, context) {
  capability <- context$typed_slice_reads$chunks
  cells <- as.character(capability$cells)
  features <- as.character(capability$features)
  chunks <- scworkbench::wb_partition_axis(cells, as.integer(params$chunk_size))
  totals <- numeric(length(cells))
  names(totals) <- cells
  for (chunk in chunks) {
    piece <- readers$chunks(features = features, cells = chunk)
    totals[chunk] <- colSums(as.matrix(piece$values))
  }
  n_latent <- as.integer(params$n_latent)
  latent <- vapply(seq_len(n_latent), function(j) as.numeric(totals) + j,
    numeric(length(cells)))
  dimnames(latent) <- list(cells, paste0("latent_", seq_len(n_latent)))
  if (identical(as.character(params$attack), "wrong_axis"))
    latent <- latent[rev(seq_len(nrow(latent))), , drop = FALSE]
  if (!identical(as.character(params$attack), "omit_space")) {
    written <- writers$write_space("space", structure(list(kind = "space",
      values = latent,
      dimensions = as.integer(dim(latent)), cell_id = rownames(latent),
      storage_profile = "space_dense_v1"), class = "wb_primitive"))
  }
  writers$write_terminal_primitive("summary",
    scworkbench::wb_prim_obs_table(data.frame(n_cells = length(cells),
      n_latent = n_latent), table_type = "matrix_model_summary"))
  tree <- writers$open_model_tree("model")
  if (!identical(as.character(params$attack), "incomplete_tree"))
    writeBin(charToRaw("matrix-model-fixture-v1"),
      tree$path(tree$primary_path))
  model <- scworkbench::wb_prim_model_ref(
    if (exists("written")) written$allocated_id else "missing",
    if (exists("written")) written$allocated_id else "missing",
    engine = "fixture")
  model$model_type <- "matrix_model"
  tree$finish(model)
  invisible(list(status = "ok"))
}

.read_matrix_model <- function(readers, writers, params, context) {
  model <- readers$model_tree()
  bytes <- model$read_bytes(model$primary_path)
  writers$write_terminal_primitive("summary",
    scworkbench::wb_prim_obs_table(data.frame(byte_count = length(bytes)),
      table_type = "matrix_model_read_summary"))
  invisible(list(status = "ok"))
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json",
      package = "scwbV3MatrixModel"),
    list(`scwbv3matrixmodel::fit_matrix_model` = .fit_matrix_model,
      `scwbv3matrixmodel::read_matrix_model` = .read_matrix_model))
}
