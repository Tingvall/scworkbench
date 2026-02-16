wb_exec_selection_plan <- function(bundle, plan, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.list(plan), "plan must be list")

  universe <- plan$universe %||% "all"
  rules <- plan$rules %||% list()

  # helper: normalize to cell_ids char vector
  .as_cell_ids <- function(x) {
    ids <- .wb_sel_resolve_cell_ids(x)
    if (is.null(ids)) ids <- x
    ids <- as.character(ids)
    ids <- ids[nzchar(ids)]
    ids
  }

  # --------------------------
  # 1) Universe -> cell_ids
  # --------------------------
  # Use your canonical cell-set getter (NOT wb_sel_all)
  cells <- wb_cells(bundle, cell_set = universe)
  cells <- .as_cell_ids(cells)
  .wb_assert(length(cells) > 0, paste0("Universe is empty: ", universe))

  # --------------------------
  # 2) Apply AND rules
  # --------------------------
  for (r in rules) {
    if (length(cells) == 0) break
    tp <- r$type %||% ""

    if (tp == "set") {
      cells <- wb_sel_set(
        cells,
        bundle = bundle,
        sets = as.character(r$sets %||% character(0))
      )
      cells <- .as_cell_ids(cells)
    }

    else if (tp == "vector_range") {
      spec <- wb_vector_ref_to_spec(r$vector_ref)

      v <- wb_resolve_cell_vector(
        bundle   = bundle,
        x        = spec,
        runs     = runs,
        cell_ids = cells,
        key      = r$key %||% NULL
      )

      ok <- rep(TRUE, length(v))
      if (!is.null(r$min)) ok <- ok & (v >= r$min)
      if (!is.null(r$max)) ok <- ok & (v <= r$max)
      if (isTRUE(r$na.rm %||% TRUE)) ok <- ok & !is.na(v)

      cells <- names(v)[ok]
      cells <- .wb_order_like_bundle(bundle, cells)
      .wb_assert(length(cells) > 0, "Selection became empty after vector_range rule.")
    }

    else if (tp == "space_box") {
      cells <- wb_sel_space_box(
        cells,
        bundle  = bundle,
        space_id = as.character(r$space_id),
        xmin = as.numeric(r$xmin),
        xmax = as.numeric(r$xmax),
        ymin = as.numeric(r$ymin),
        ymax = as.numeric(r$ymax)
      )
      cells <- .as_cell_ids(cells)
    }

    else if (tp == "expr") {
      mid <- r$matrix_id
      fid <- r$feature_id
      .wb_assert(is.character(mid) && length(mid) == 1 && nzchar(mid),
                 "expr rule requires matrix_id (length-1 string)")
      .wb_assert(is.character(fid) && length(fid) == 1 && nzchar(fid),
                 "expr rule requires feature_id (length-1 string)")

      cells <- wb_sel_expr(
        cells,
        bundle = bundle,
        matrix_id  = as.character(mid),
        feature_id = as.character(fid),
        min = r$min %||% NULL,
        max = r$max %||% NULL,
        na.rm = isTRUE(r$na.rm %||% TRUE)
      )
      cells <- .as_cell_ids(cells)
    }

    else {
      stop("Unknown rule type: ", tp, call. = FALSE)
    }
  }

  .wb_assert(length(cells) > 0, "Selection is empty at end of plan.")
  cells
}
