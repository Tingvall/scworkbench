test_op_cell_vector_compare_contract <- function() {
  iface <- wb_op_interface("cell_vector_compare")
  stopifnot(identical(as.character(iface$produces$summary$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$comparison$kind), "obs_table"))
  stopifnot("cell_vector_compare" %in% wb_list_ops())

  a <- wb_prim_cell_vector(stats::setNames(c(1, 2, 3, 4, 5), paste0("c", 1:5)), value_type = "continuous")
  b <- wb_prim_cell_vector(stats::setNames(c(10, 20, 30, 40, 50), paste0("c", 1:5)), value_type = "continuous")

  raw <- wb_op_cell_vector_compare(
    a = a,
    b = b,
    compare_space = "raw",
    signal_a = "sigA",
    signal_b = "sigB"
  )
  stopifnot(is.list(raw), is.list(raw$outputs))
  sum_tbl <- raw$outputs$summary
  cmp_tbl <- raw$outputs$comparison
  stopifnot(inherits(sum_tbl, "wb_primitive"), identical(as.character(sum_tbl$kind), "obs_table"))
  stopifnot(inherits(cmp_tbl, "wb_primitive"), identical(as.character(cmp_tbl$kind), "obs_table"))
  stopifnot(identical(as.character(sum_tbl$table_type), "cell_vector_compare_summary"))
  stopifnot(identical(as.character(cmp_tbl$table_type), "cell_vector_compare"))
  stopifnot(nrow(sum_tbl$table) == 1L)
  stopifnot(nrow(cmp_tbl$table) == 5L)
  stopifnot(all(c("pearson", "spearman", "kendall", "mean_delta", "mean_abs_delta",
                  "median_abs_delta", "rmse", "max_abs_delta") %in% names(sum_tbl$table)))
  stopifnot(all(c("cell_id", "a", "b", "a_cmp", "b_cmp", "delta", "abs_delta") %in% names(cmp_tbl$table)))
  stopifnot(identical(as.character(sum_tbl$table$signal_a[1]), "sigA"))
  stopifnot(identical(as.character(sum_tbl$table$signal_b[1]), "sigB"))
  stopifnot(isTRUE(all.equal(as.numeric(sum_tbl$table$pearson[1]), 1, tolerance = 1e-8)))
  stopifnot(isTRUE(all.equal(as.numeric(sum_tbl$table$spearman[1]), 1, tolerance = 1e-8)))

  rr <- wb_op_cell_vector_compare(
    a = a,
    b = b,
    compare_space = "rank",
    cells = c("c1", "c2", "c3", "c4")
  )
  stopifnot(nrow(rr$outputs$comparison$table) == 4L)
  stopifnot(identical(as.character(rr$outputs$summary$table$compare_space[1]), "rank"))
  stopifnot(identical(as.integer(rr$outputs$summary$table$n_shared_cells[1]), 4L))
  stopifnot(identical(sort(rr$outputs$comparison$table$a_cmp), c(1, 2, 3, 4)))
  stopifnot(identical(sort(rr$outputs$comparison$table$b_cmp), c(1, 2, 3, 4)))

  TRUE
}
