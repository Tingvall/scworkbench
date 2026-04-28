test_op_cell_vector_family_qc_contract <- function() {
  iface <- wb_op_interface("cell_vector_family_qc")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "cell_vector_family_qc"))
  stopifnot(identical(as.character(iface$produces$key_summary$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$pairwise_summary$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$group_summary$kind), "obs_table"))
  stopifnot("cell_vector_family_qc" %in% wb_list_ops())

  sig <- wb_prim_cell_vector_family(
    key = c(
      "A", "A", "A", "A",
      "B", "B", "B", "B",
      "C", "C", "C", "C"
    ),
    cell_id = c(
      "c1", "c2", "c3", "c4",
      "c1", "c2", "c3", "c4",
      "c1", "c2", "c3", "c4"
    ),
    value = c(
      1, 2, 3, 4,
      2, 4, 6, 8,
      4, 3, 2, 1
    ),
    value_type = "continuous"
  )
  grp <- wb_prim_cell_vector(
    c(c1 = "G1", c2 = "G1", c3 = "G2", c4 = "G2"),
    value_type = "categorical"
  )

  raw <- wb_op_cell_vector_family_qc(
    signal = sig,
    grouping = grp,
    correlation_methods = c("pearson", "spearman")
  )

  stopifnot(is.list(raw), is.list(raw$outputs))
  stopifnot(all(c("key_summary", "pairwise_summary", "group_summary") %in% names(raw$outputs)))

  ks <- raw$outputs$key_summary
  ps <- raw$outputs$pairwise_summary
  gs <- raw$outputs$group_summary
  stopifnot(inherits(ks, "wb_primitive"), identical(as.character(ks$kind), "obs_table"))
  stopifnot(inherits(ps, "wb_primitive"), identical(as.character(ps$kind), "obs_table"))
  stopifnot(inherits(gs, "wb_primitive"), identical(as.character(gs$kind), "obs_table"))
  stopifnot(identical(as.character(ks$table_type), "cell_vector_family_qc_key_summary"))
  stopifnot(identical(as.character(ps$table_type), "cell_vector_family_qc_pairwise_summary"))
  stopifnot(identical(as.character(gs$table_type), "cell_vector_family_qc_group_summary"))

  ktab <- ks$table
  ptab <- ps$table
  gtab <- gs$table
  stopifnot(all(c("key", "n_cells_total", "n_finite", "score_mean", "top1_count", "tied_top_count") %in% colnames(ktab)))
  stopifnot(nrow(ktab) == 3)
  stopifnot(all(ktab$n_cells_total == 4L))

  arow <- ktab[ktab$key == "A", , drop = FALSE]
  brow <- ktab[ktab$key == "B", , drop = FALSE]
  crow <- ktab[ktab$key == "C", , drop = FALSE]
  stopifnot(nrow(arow) == 1, nrow(brow) == 1, nrow(crow) == 1)
  stopifnot(isTRUE(all.equal(as.numeric(arow$score_mean), 2.5)))
  stopifnot(isTRUE(all.equal(as.numeric(brow$score_mean), 5.0)))
  stopifnot(isTRUE(all.equal(as.numeric(crow$score_mean), 2.5)))
  stopifnot(as.integer(arow$top1_count) == 0L)
  stopifnot(as.integer(brow$top1_count) == 3L)
  stopifnot(as.integer(crow$top1_count) == 1L)

  stopifnot(all(c("key_a", "key_b", "n_overlap", "pearson_cor", "spearman_cor") %in% colnames(ptab)))
  stopifnot(nrow(ptab) == 3)

  ab <- ptab[ptab$key_a == "A" & ptab$key_b == "B", , drop = FALSE]
  ac <- ptab[ptab$key_a == "A" & ptab$key_b == "C", , drop = FALSE]
  stopifnot(nrow(ab) == 1, nrow(ac) == 1)
  stopifnot(as.integer(ab$n_overlap) == 4L)
  stopifnot(isTRUE(all.equal(as.numeric(ab$pearson_cor), 1.0)))
  stopifnot(isTRUE(all.equal(as.numeric(ac$pearson_cor), -1.0)))

  stopifnot(all(c("group_id", "key", "n_cells_group", "score_mean", "top1_count", "top1_pct") %in% colnames(gtab)))
  stopifnot(nrow(gtab) == 6L)
  g1b <- gtab[gtab$group_id == "G1" & gtab$key == "B", , drop = FALSE]
  g2c <- gtab[gtab$group_id == "G2" & gtab$key == "C", , drop = FALSE]
  g2b <- gtab[gtab$group_id == "G2" & gtab$key == "B", , drop = FALSE]
  stopifnot(nrow(g1b) == 1L, nrow(g2c) == 1L)
  stopifnot(isTRUE(all.equal(as.numeric(g1b$score_mean), 3.0)))
  stopifnot(as.integer(g1b$top1_count) == 1L)
  stopifnot(as.integer(g2c$top1_count) == 0L)
  stopifnot(as.integer(g2b$top1_count) == 2L)

  tmp <- tempfile("scwb_cvf_qc_session_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)
  cells <- c("grpA-1", "grpA-2", "grpB-1", "grpB-2")
  wb_define_cells(b, cells)
  sig2 <- wb_prim_cell_vector_family(
    key = rep(c("A", "B"), each = 4),
    cell_id = rep(cells, times = 2),
    value = c(1, 2, 3, 4, 2, 4, 6, 8),
    value_type = "continuous"
  )
  s <- wb_session_new()
  lab <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "cell_suffix_label",
    inputs = list(cell_set = "all", min_cells = 1L, sep = "-", mapping = c(grpA = "A", grpB = "B"))
  )
  s <- lab$session
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "cell_vector_family_qc",
    inputs = list(
      signal = sig2,
      grouping = wb_ref_run(lab$run$run_id, "labels"),
      cell_set = "all",
      min_cells = 1L
    )
  )
  stopifnot(is.list(rr$run$outputs$group_summary))
  stopifnot(nrow(rr$run$outputs$group_summary$table) >= 1L)
  stopifnot(identical(as.logical(rr$run$params$has_grouping), TRUE))

  TRUE
}
