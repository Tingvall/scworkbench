test_op_cell_vector_family_reduce_contract <- function() {
  iface <- wb_op_interface("cell_vector_family_reduce")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "cell_vector_family_reduce"))
  stopifnot(identical(as.character(iface$produces$label$kind), "cell_vector"))
  stopifnot(identical(as.character(iface$produces$runner_up_score$kind), "cell_vector"))
  stopifnot(identical(as.character(iface$produces$decision_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$label_summary$kind), "obs_table"))
  stopifnot("cell_vector_family_reduce" %in% wb_list_ops())

  sig <- wb_prim_cell_vector_family(
    key = c(
      "A", "B", "C",
      "A", "B", "C",
      "A", "B", "C",
      "A", "B", "C"
    ),
    cell_id = c(
      "c1", "c1", "c1",
      "c2", "c2", "c2",
      "c3", "c3", "c3",
      "c4", "c4", "c4"
    ),
    value = c(
      2.0, 1.0, 0.2,
      0.5, 0.5, 0.1,
      0.3, 0.1, 0.2,
      1.2, 0.9, 0.8
    ),
    value_type = "continuous"
  )

  raw <- wb_op_cell_vector_family_reduce(
    signal = sig,
    rule = "argmax",
    min_score = 0.4,
    min_margin = 0.25,
    unknown_label = "unknown",
    ties = "unknown"
  )

  stopifnot(is.list(raw), is.list(raw$outputs))
  stopifnot(all(c("label", "top_score", "runner_up_score", "score_margin", "abstain_reason", "decision_table", "label_summary") %in% names(raw$outputs)))

  lab <- raw$outputs$label
  top <- raw$outputs$top_score
  run2 <- raw$outputs$runner_up_score
  mar <- raw$outputs$score_margin
  absr <- raw$outputs$abstain_reason
  dec <- raw$outputs$decision_table
  sm <- raw$outputs$label_summary

  stopifnot(inherits(lab, "wb_primitive"), identical(as.character(lab$kind), "cell_vector"))
  stopifnot(inherits(top, "wb_primitive"), identical(as.character(top$kind), "cell_vector"))
  stopifnot(inherits(run2, "wb_primitive"), identical(as.character(run2$kind), "cell_vector"))
  stopifnot(inherits(mar, "wb_primitive"), identical(as.character(mar$kind), "cell_vector"))
  stopifnot(inherits(absr, "wb_primitive"), identical(as.character(absr$kind), "cell_vector"))
  stopifnot(inherits(dec, "wb_primitive"), identical(as.character(dec$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(dec$table_type), "cell_vector_family_reduce_decision_table"))
  stopifnot(identical(as.character(sm$table_type), "cell_vector_family_reduce_summary"))

  labv <- stats::setNames(as.character(lab$value), as.character(lab$cell_id))
  topv <- stats::setNames(as.numeric(top$value), as.character(top$cell_id))
  run2v <- stats::setNames(as.numeric(run2$value), as.character(run2$cell_id))
  marv <- stats::setNames(as.numeric(mar$value), as.character(mar$cell_id))
  absv <- stats::setNames(as.character(absr$value), as.character(absr$cell_id))

  stopifnot(identical(unname(labv[c("c1", "c2", "c3", "c4")]), c("A", "unknown", "unknown", "A")))
  stopifnot(isTRUE(all.equal(unname(topv[c("c1", "c4")]), c(2.0, 1.2))))
  stopifnot(isTRUE(all.equal(unname(run2v[c("c1", "c4")]), c(1.0, 0.9))))
  stopifnot(isTRUE(all.equal(unname(marv[c("c1", "c4")]), c(1.0, 0.3))))
  stopifnot(identical(unname(absv[c("c1", "c2", "c3", "c4")]), c("none", "tie", "min_score", "none")))
  stopifnot(all(c("cell_id", "label", "top_score", "runner_up_score", "score_margin", "abstain_reason") %in% colnames(dec$table)))
  stopifnot(all(c("label", "n_cells", "pct_cells", "mean_top_score", "mean_margin", "n_abstained") %in% colnames(sm$table)))

  TRUE
}
