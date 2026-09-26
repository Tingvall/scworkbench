# Regression reproducer for the corrected generic G2 two-dimensional label path.
# At and after d8feee3b3da96c9a7616dd654e7387da681f2c32, expect exit 0:
# wb_space exposes x/y; the durable matrix and selected axis use dim1/dim2.
# Run with an installed scworkbench and its scwbV3Phase5 test fixture.
library(scworkbench)

reproduce_g2_2d <- function() {
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Phase5")
  stopifnot(nzchar(manifest))
  wb_operation_pack_activate(manifest)

  root <- tempfile("g2-2d-dimensions-")
  bundle <- wb_init_bundle(root)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("c", seq_len(12L))
  coordinates <- cbind(d1 = seq_along(cells),
    d2 = 2 * seq_along(cells))
  rownames(coordinates) <- cells
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "source", coordinates)

  source <- scworkbench:::wb_space(bundle, "source")
  durable <- scworkbench:::.wb_as_coord_matrix(source)
  cat("wb_space labels:", paste(colnames(source), collapse = ","), "\n")
  cat("durable matrix labels:", paste(colnames(durable),
    collapse = ","), "\n")
  result <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
    "scwbv3phase5::fit_derived_axis_relation", inputs = list(
      source = "source", dims = as.integer(1:2),
      fitted_cells = cells[1:3], cell_set = "all", min_cells = 1L)),
    error = identity)
  cat("durable artifact rows:", nrow(wb_art_list(bundle)), "\n")
  if (inherits(result, "error")) stop(conditionMessage(result),
    call. = FALSE)
  invisible(result)
}

reproduce_g2_2d()
