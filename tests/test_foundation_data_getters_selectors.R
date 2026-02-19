test_foundation_data_getters_selectors <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  # ---- Data/getter invariants ----
  cells_all <- wb_cells(b, cell_set = "all")
  stopifnot(is.character(cells_all), length(cells_all) > 0)
  meta_all <- wb_meta(b, cols = "cell_id")
  stopifnot(length(meta_all$cell_id) == length(cells_all))
  stopifnot(setequal(meta_all$cell_id, cells_all))
  stopifnot(identical(cells_all, wb_meta(b, cells = cells_all, cols = "cell_id")$cell_id))

  cells_core <- wb_cells(b, cell_set = "core")
  stopifnot(is.character(cells_core))
  stopifnot(all(cells_core %in% cells_all))
  stopifnot(identical(cells_core, cells_all[cells_all %in% cells_core]))

  # Unknown metadata column should error.
  err_meta <- try(wb_meta(b, cols = c("cell_id", ".__not_a_real_col__.")), silent = TRUE)
  stopifnot(inherits(err_meta, "try-error"))

  # Matrix coverage should return canonical bundle cells when matrix exists.
  mats <- wb_matrices(b)
  if (nrow(mats) > 0) {
    cov_mat <- wb_cells_with_matrix(b, mats$matrix_id[1])
    stopifnot(identical(cov_mat, cells_all))
  }

  # Space coverage returns existing cells; with dims it cannot increase the set.
  spaces <- wb_spaces(b)
  if (nrow(spaces) > 0) {
    sid <- spaces$space_id[1]
    cov_space <- wb_cells_with_space(b, sid)
    stopifnot(all(cov_space %in% cells_all))

    info <- wb_space_info(b, sid)
    dims <- as.integer(info$dims[1])
    if (!is.na(dims) && dims >= 2 && spaces$storage[1] == "long:space_coords") {
      cov_space_dims <- wb_cells_with_space(b, sid, dims = 1:2)
      stopifnot(all(cov_space_dims %in% cov_space))
    }

    cov <- wb_cell_coverage(
      b,
      cell_set = "core",
      inputs = list(space_id = sid)
    )
    stopifnot(is.list(cov), cov$requested >= cov$effective)

    # Unknown space should error in coverage helper.
    err_space <- try(wb_cells_with_space(b, ".__missing_space__."), silent = TRUE)
    stopifnot(inherits(err_space, "try-error"))
  }

  # Unknown matrix coverage should return empty (contract in getters_coverage.R).
  cov_missing_matrix <- wb_cells_with_matrix(b, ".__missing_matrix__.")
  stopifnot(is.character(cov_missing_matrix), length(cov_missing_matrix) == 0)

  # ---- Selector invariants ----
  sel_all <- wb_sel_all(b, cell_set = "all")
  stopifnot(identical(as.character(sel_all), cells_all))
  stopifnot(inherits(attr(sel_all, "wb_bundle", exact = TRUE), "scworkbench_bundle"))
  stopifnot(is.list(wb_sel_recipe(sel_all)))

  # Deterministic set algebra in canonical order
  left <- head(cells_all, min(50, length(cells_all)))
  right <- cells_all[seq(1, min(100, length(cells_all)), by = 2)]

  sel_and <- wb_sel_and(left, right, bundle = b)
  want_and <- cells_all[cells_all %in% intersect(left, right)]
  stopifnot(identical(as.character(sel_and), want_and))

  sel_or <- wb_sel_or(left, right, bundle = b)
  want_or <- cells_all[cells_all %in% unique(c(left, right))]
  stopifnot(identical(as.character(sel_or), want_or))

  # Empty selector algebra should be stable and keep attachments.
  sel_empty <- wb_sel_and(sel_all, character(0))
  stopifnot(is.character(sel_empty), length(sel_empty) == 0)
  stopifnot(inherits(attr(sel_empty, "wb_bundle", exact = TRUE), "scworkbench_bundle"))
  stopifnot(is.list(wb_sel_recipe(sel_empty)))

  # wb_sel_not must be called on cell_ids, not on bundle root.
  err_not <- try(wb_sel_not(b), silent = TRUE)
  stopifnot(inherits(err_not, "try-error"))

  # Space-box selector must return subset of input when a 2D space exists.
  sp2d <- spaces$space_id[spaces$storage == "wide:space_2d"]
  if (length(sp2d) > 0) {
    sid2d <- sp2d[1]
    box <- wb_sel_space_box(
      sel_all,
      space_id = sid2d,
      xmin = -Inf, xmax = Inf,
      ymin = -Inf, ymax = Inf
    )
    stopifnot(all(as.character(box) %in% cells_all))
  }

  TRUE
}
