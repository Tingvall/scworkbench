test_primitives_contract <- function() {
  contract_test_activate_statistics_pack()
  # Primitive constructors
  cv <- wb_prim_cell_vector(setNames(c("a", "b"), c("c1", "c2")))
  stopifnot(.wb_is_primitive(cv), identical(cv$kind, "cell_vector"))

  cvf <- wb_prim_cell_vector_family(
    key = c("L1", "L1"),
    cell_id = c("c1", "c2"),
    value = c(0.1, 0.2)
  )
  stopifnot(.wb_is_primitive(cvf), identical(cvf$kind, "cell_vector_family"))

  rf <- wb_prim_relation_family(
    key = c("B1", "B2", "B2"),
    cell_id = c("c1", "c1", "c2"),
    weight = c(0.8, 0.2, 1.0),
    value = c(0.4, 0.1, 0.7)
  )
  stopifnot(.wb_is_primitive(rf), identical(rf$kind, "relation_family"))
  stopifnot(identical(length(rf$key), 3L), identical(length(rf$weight), 3L))

  p2 <- wb_prim_path_2d_family(
    key = c("L1", "L1"),
    point = c(1L, 2L),
    x = c(0, 1),
    y = c(0, 1)
  )
  stopifnot(.wb_is_primitive(p2), identical(p2$kind, "path_2d_family"))

  spf <- wb_prim_space_path_family(
    space_id = c("peakvi_space", "peakvi_space", "peakvi_space", "peakvi_space"),
    path_id = c("P1", "P1", "P1", "P1"),
    point = c(1L, 1L, 2L, 2L),
    dim = c(1L, 2L, 1L, 2L),
    value = c(0, 0, 1, 1),
    meta = list(
      fit_mode = "linear",
      anchor_label = c("A", "B"),
      anchor_order = c(1L, 2L)
    )
  )
  stopifnot(.wb_is_primitive(spf), identical(spf$kind, "space_path_family"))
  stopifnot(identical(length(spf$space_id), 4L), identical(length(spf$path_id), 4L))

  mr <- wb_prim_model_ref(model_space_id = "umap.lsi", in_space_id = "lsi")
  stopifnot(
    .wb_is_primitive(mr),
    identical(mr$kind, "model_ref"),
    identical(mr$model_space_id, "umap.lsi"),
    identical(mr$in_space_id, "lsi")
  )

  ft <- wb_prim_feature_table(
    table = data.frame(feature_id = c("g1", "g2"), stat = c(1, 2), stringsAsFactors = FALSE),
    table_type = "unit_test"
  )
  stopifnot(.wb_is_primitive(ft), identical(ft$kind, "feature_table"))

  ot <- wb_prim_obs_table(
    table = data.frame(sample_id = c("s1", "s2"), value = c(0.1, 0.2), stringsAsFactors = FALSE),
    table_type = "unit_test",
    entity_kind = "sample"
  )
  stopifnot(.wb_is_primitive(ot), identical(ot$kind, "obs_table"))

  rf_tbl <- wb_primitive_to_table(rf, include_context = TRUE)
  stopifnot(is.data.frame(rf_tbl), nrow(rf_tbl) == 3L)
  stopifnot(all(c("key", "cell_id", "weight", "value", "kind") %in% names(rf_tbl)))

  spf_tbl <- wb_primitive_to_table(spf, include_context = TRUE)
  stopifnot(is.data.frame(spf_tbl), nrow(spf_tbl) == 4L)
  stopifnot(all(c("space_id", "path_id", "point", "dim", "value", "kind") %in% names(spf_tbl)))

  # Op contract invariants
  ops <- .wb_ops()
  stopifnot(is.list(ops), length(ops) > 0)

  promoters <- .wb_promoters_by_kind()
  stopifnot(is.list(promoters), length(promoters) > 0)

  for (op_name in names(ops)) {
    op <- ops[[op_name]]
    stopifnot(is.list(op$produces), is.character(op$promotable))
    stopifnot(all(op$promotable %in% names(op$produces)))

    for (out_name in op$promotable) {
      kind <- op$produces[[out_name]]
      stopifnot(is.character(kind), length(kind) == 1, kind %in% names(promoters))
    }
  }

  # UI interface should speak primitive output kinds for all canonical ops
  must_align <- names(ops)
  for (op_name in must_align) {
    iface <- wb_op_interface(op_name)
    op <- ops[[op_name]]
    iface_out <- iface$produces %||% list()
    stopifnot(length(iface_out) > 0)
    stopifnot(all(names(iface_out) %in% names(op$produces)))
    for (nm in names(iface_out)) {
      stopifnot(identical(as.character(iface_out[[nm]]$kind), as.character(op$produces[[nm]])))
    }
  }

  sp_def <- wb_op_interface("space_path_define")
  stopifnot(identical(as.character(sp_def$produces$path$kind), "space_path_family"))

  sp_score <- wb_op_interface("space_path_score")
  stopifnot(identical(as.character(sp_score$produces$path_scores$kind), "cell_vector_family"))
  stopifnot(identical(as.character(sp_score$produces$fit_summary$kind), "obs_table"))

  sp_proj <- wb_op_interface("space_path_project_2d")
  stopifnot(identical(as.character(sp_proj$produces$curves$kind), "path_2d_family"))

  cvc <- wb_op_interface("cell_vector_compare")
  stopifnot(identical(as.character(cvc$produces$summary$kind), "obs_table"))
  stopifnot(identical(as.character(cvc$produces$comparison$kind), "obs_table"))

  TRUE
}
