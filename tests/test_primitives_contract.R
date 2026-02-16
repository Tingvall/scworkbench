test_primitives_contract <- function() {
  # Primitive constructors
  cv <- wb_prim_cell_vector(setNames(c("a", "b"), c("c1", "c2")))
  stopifnot(.wb_is_primitive(cv), identical(cv$kind, "cell_vector"))

  cvf <- wb_prim_cell_vector_family(
    key = c("L1", "L1"),
    cell_id = c("c1", "c2"),
    value = c(0.1, 0.2)
  )
  stopifnot(.wb_is_primitive(cvf), identical(cvf$kind, "cell_vector_family"))

  p2 <- wb_prim_path_2d_family(
    key = c("L1", "L1"),
    point = c(1L, 2L),
    x = c(0, 1),
    y = c(0, 1)
  )
  stopifnot(.wb_is_primitive(p2), identical(p2$kind, "path_2d_family"))

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

  TRUE
}
