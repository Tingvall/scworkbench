test_object_primitive_family_durable_roundtrip_contract <- function() {
  root <- tempfile("scwb_object_family_roundtrip_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c3", "c1", "c4", "c2")
  wb_define_cells(b, cells)
  wb_attach_space(
    b,
    "latent",
    data.frame(cell_id = cells, d1 = seq_along(cells), d2 = rev(seq_along(cells)))
  )

  metadata <- list(
    label = "durable presentation",
    numeric_double = c(1, 2.5),
    integer_order = c(2L, 1L),
    named = c(left = "L", right = "R")
  )
  primitives <- list(
    cell_vector = wb_prim_cell_vector(
      stats::setNames(c(3.5, 1.5, 4.5, 2.5), cells),
      value_type = "continuous",
      meta = metadata
    ),
    cell_vector_family = wb_prim_cell_vector_family(
      key = c("L2", "L1", "L2", "L1"),
      cell_id = c("c4", "c3", "c2", "c1"),
      value = c(0.4, 0.1, 0.3, 0.2),
      value_type = "probability",
      meta = metadata
    ),
    relation_family = wb_prim_relation_family(
      key = c("edge_b", "edge_a", "edge_b", "edge_a"),
      cell_id = c("c4", "c3", "c2", "c1"),
      weight = c(0.4, 0.1, 0.3, 0.2),
      value = rep(NA_real_, 4L),
      distance = NULL,
      meta = metadata
    ),
    path_2d_family = wb_prim_path_2d_family(
      key = c("path_b", "path_a", "path_b", "path_a"),
      point = c(2L, 2L, 1L, 1L),
      x = c(4, 2, 3, 1),
      y = c(40, 20, 30, 10),
      meta = metadata
    ),
    space_path_family = wb_prim_space_path_family(
      space_id = rep("latent", 4L),
      path_id = c("path_b", "path_a", "path_b", "path_a"),
      point = c(2L, 2L, 1L, 1L),
      dim = c(2L, 1L, 1L, 2L),
      value = c(4, 2, 3, 1),
      meta = metadata
    )
  )

  promoters <- scworkbench:::.wb_promoters_by_kind()
  artifact_ids <- character()
  identities_before <- character()
  for (kind in names(primitives)) {
    primitive <- primitives[[kind]]
    run <- wb_new_run(
      op_name = "durable_object_family_fixture",
      inputs = list(cell_set = "all", parents = character(), user_inputs = list()),
      params = list(kind = kind),
      outputs = stats::setNames(list(primitive), kind)
    )
    artifact_ids[[kind]] <- promoters[[kind]](
      b, run, kind, primitive,
      created_by = "object-family-roundtrip-contract"
    )
    identities_before[[kind]] <- scworkbench:::.wb_prov_payload_identity(
      b, primitive
    )$content_sha256
  }

  loaded <- lapply(artifact_ids, function(id) wb_art_load(b, id))
  for (kind in names(primitives)) {
    stopifnot(
      identical(unclass(loaded[[kind]]), unclass(primitives[[kind]])),
      identical(loaded[[kind]]$meta, metadata),
      identical(
        scworkbench:::.wb_prov_payload_identity(b, loaded[[kind]])$content_sha256,
        identities_before[[kind]]
      )
    )
  }
  stopifnot(
    identical(loaded$cell_vector$value_type, "continuous"),
    identical(loaded$cell_vector_family$value_type, "probability"),
    !is.null(loaded$relation_family$value),
    is.null(loaded$relation_family$distance)
  )

  mutations <- list(
    cell_vector = list(
      sql = "UPDATE artifact_labels SET value_num = value_num + 9 WHERE artifact_id = ? AND cell_id = 'c3';"
    ),
    cell_vector_family = list(
      sql = "UPDATE artifact_pseudotime SET pseudotime = pseudotime + 9 WHERE artifact_id = ? AND lineage_id = 'L2' AND cell_id = 'c4';"
    ),
    relation_family = list(
      sql = "UPDATE artifact_relation_rows SET weight = weight + 9 WHERE artifact_id = ? AND relation_key = 'edge_b' AND cell_id = 'c4';"
    ),
    path_2d_family = list(
      sql = "UPDATE artifact_curves_2d SET x = x + 9 WHERE artifact_id = ? AND lineage_id = 'path_b' AND point = 2;"
    ),
    space_path_family = list(
      sql = "UPDATE artifact_space_path_rows SET value = value + 9 WHERE artifact_id = ? AND path_id = 'path_b' AND point = 2 AND dim = 2;"
    )
  )
  for (kind in names(mutations)) {
    DBI::dbExecute(b$con, mutations[[kind]]$sql, params = list(artifact_ids[[kind]]))
    mutated <- wb_art_load(b, artifact_ids[[kind]])
    stopifnot(
      scworkbench:::.wb_prov_payload_identity(b, mutated)$content_sha256 !=
        identities_before[[kind]]
    )
  }

  TRUE
}
