test_op_cell_vector_family_calibrate_contract <- function() {
  iface <- wb_op_interface("cell_vector_family_calibrate")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "cell_vector_family_calibrate"))
  stopifnot(identical(as.character(iface$produces$calibrated_signal$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$calibration_summary$kind), "obs_table"))
  stopifnot("cell_vector_family_calibrate" %in% wb_list_ops())

  sig <- wb_prim_cell_vector_family(
    key = c(
      "A", "A", "A", "A",
      "B", "B", "B", "B"
    ),
    cell_id = c(
      "c1", "c2", "c3", "c4",
      "c1", "c2", "c3", "c4"
    ),
    value = c(
      1, 2, 3, 4,
      10, 10, 20, 40
    ),
    value_type = "continuous"
  )

  raw_pct <- wb_op_cell_vector_family_calibrate(
    signal = sig,
    method = "percentile"
  )
  stopifnot(is.list(raw_pct), is.list(raw_pct$outputs))
  pct <- raw_pct$outputs$calibrated_signal
  pct_sm <- raw_pct$outputs$calibration_summary
  stopifnot(inherits(pct, "wb_primitive"), identical(as.character(pct$kind), "cell_vector_family"))
  stopifnot(inherits(pct_sm, "wb_primitive"), identical(as.character(pct_sm$kind), "obs_table"))
  stopifnot(identical(as.character(pct_sm$table_type), "cell_vector_family_calibration_summary"))

  pct_df <- data.frame(
    cell_id = as.character(pct$cell_id),
    key = as.character(pct$key),
    value = as.numeric(pct$value),
    stringsAsFactors = FALSE
  )
  a_pct <- pct_df$value[pct_df$key == "A"]
  b_pct <- pct_df$value[pct_df$key == "B"]
  stopifnot(isTRUE(all.equal(a_pct, c(0, 1/3, 2/3, 1))))
  stopifnot(isTRUE(all.equal(b_pct, c(1/6, 1/6, 2/3, 1))))

  raw_z <- wb_op_cell_vector_family_calibrate(
    signal = sig,
    method = "zscore"
  )
  z <- raw_z$outputs$calibrated_signal
  z_df <- data.frame(
    cell_id = as.character(z$cell_id),
    key = as.character(z$key),
    value = as.numeric(z$value),
    stringsAsFactors = FALSE
  )
  stopifnot(abs(mean(z_df$value[z_df$key == "A"])) < 1e-8)
  stopifnot(abs(mean(z_df$value[z_df$key == "B"])) < 1e-8)

  raw_rz <- wb_op_cell_vector_family_calibrate(
    signal = sig,
    method = "robust_zscore"
  )
  rz <- raw_rz$outputs$calibrated_signal
  rz_df <- data.frame(
    cell_id = as.character(rz$cell_id),
    key = as.character(rz$key),
    value = as.numeric(rz$value),
    stringsAsFactors = FALSE
  )
  stopifnot(isTRUE(all.equal(rz_df$value[rz_df$key == "A"], c(-1.5, -0.5, 0.5, 1.5))))
  stopifnot(isTRUE(all.equal(rz_df$value[rz_df$key == "B"], c(-1, -1, 1, 5))))
  stopifnot(all(c(
    "key", "n_cells", "n_finite", "raw_mean", "calibrated_mean",
    "calibration_center", "calibration_scale"
  ) %in% colnames(raw_rz$outputs$calibration_summary$table)))

  TRUE
}
