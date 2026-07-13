#' Execute a selection plan into ordered cell IDs
#'
#' @param bundle An open scworkbench bundle.
#' @param plan A selector-plan list.
#' @param runs Optional session runs used to resolve run-backed selectors.
#' @return Ordered selected cell IDs.
#' @export
wb_exec_selection_plan <- function(bundle, plan, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.list(plan), "plan must be list")

  universe <- plan$universe %||% "all"
  rules <- plan$rules %||% list()
  groups <- plan$groups %||% NULL

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
  universe_cells <- wb_cells(bundle, cell_set = universe)
  universe_cells <- .as_cell_ids(universe_cells)
  .wb_assert(length(universe_cells) > 0, paste0("Universe is empty: ", universe))

  .apply_rule <- function(cells, r) {
    if (length(cells) == 0) return(cells)

    tp <- r$type %||% ""
    negate <- isTRUE(r$negate %||% FALSE)
    matched <- cells

    if (tp == "set") {
      matched <- wb_sel_set(
        matched,
        bundle = bundle,
        sets = as.character(r$sets %||% character(0))
      )
      matched <- .as_cell_ids(matched)
    }

    else if (tp == "vector_range") {
      spec <- wb_vector_ref_to_spec(r$vector_ref)

      v <- wb_resolve_cell_vector(
        bundle   = bundle,
        x        = spec,
        runs     = runs,
        cell_ids = matched,
        key      = r$key %||% NULL
      )

      ok <- rep(TRUE, length(v))
      if (!is.null(r$min)) ok <- ok & (v >= r$min)
      if (!is.null(r$max)) ok <- ok & (v <= r$max)
      if (isTRUE(r$na.rm %||% TRUE)) ok <- ok & !is.na(v)

      matched <- names(v)[ok]
      matched <- .wb_order_like_bundle(bundle, matched)
    }

    else if (tp == "space_box") {
      matched <- wb_sel_space_box(
        matched,
        bundle  = bundle,
        space_id = as.character(r$space_id),
        xmin = as.numeric(r$xmin),
        xmax = as.numeric(r$xmax),
        ymin = as.numeric(r$ymin),
        ymax = as.numeric(r$ymax)
      )
      matched <- .as_cell_ids(matched)
    }

    else if (tp == "expr") {
      mid <- r$matrix_id
      fid <- r$feature_id
      .wb_assert(is.character(mid) && length(mid) == 1 && nzchar(mid),
                 "expr rule requires matrix_id (length-1 string)")
      .wb_assert(is.character(fid) && length(fid) == 1 && nzchar(fid),
                 "expr rule requires feature_id (length-1 string)")

      matched <- wb_sel_expr(
        matched,
        bundle = bundle,
        matrix_id  = as.character(mid),
        feature_id = as.character(fid),
        min = r$min %||% NULL,
        max = r$max %||% NULL,
        na.rm = isTRUE(r$na.rm %||% TRUE)
      )
      matched <- .as_cell_ids(matched)
    }

    else {
      stop("Unknown rule type: ", tp, call. = FALSE)
    }

    if (negate) {
      cells <- setdiff(cells, matched)
      cells <- .wb_order_like_bundle(bundle, cells)
    } else {
      cells <- matched
    }

    cells
  }

  .run_group <- function(group_rules) {
    cells <- universe_cells
    for (r in group_rules %||% list()) {
      cells <- .apply_rule(cells, r)
      if (length(cells) == 0) break
    }
    cells
  }

  # --------------------------
  # 2) Apply boolean plan
  # --------------------------
  if (is.null(groups)) {
    groups <- list(list(rules = rules))
  }
  .wb_assert(is.list(groups), "plan$groups must be a list when provided")

  group_cells <- lapply(groups, function(g) {
    if (!is.list(g)) stop("Each group must be a list.", call. = FALSE)
    .run_group(g$rules %||% list())
  })

  if (length(group_cells) == 0) {
    cells <- universe_cells
  } else {
    cells <- unique(unlist(group_cells, use.names = FALSE))
    cells <- .wb_order_like_bundle(bundle, cells)
  }

  .wb_assert(length(cells) > 0, "Selection is empty at end of plan.")
  cells
}
