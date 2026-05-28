test_op_space_path_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface_def <- wb_op_interface("space_path_define")
  iface_score <- wb_op_interface("space_path_score")
  iface_proj <- wb_op_interface("space_path_project_2d")
  stopifnot(identical(as.character(iface_def$produces$path$kind), "space_path_family"))
  stopifnot(identical(as.character(iface_score$produces$path_scores$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface_score$produces$fit_summary$kind), "obs_table"))
  stopifnot(identical(as.character(iface_proj$produces$curves$kind), "path_2d_family"))

  all_cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(all_cells) >= 500L)

  raw_def <- suppressWarnings(
    wb_op_space_path_define(
      bundle = b,
      space_id = "lsi",
      checkpoint_sets = c("core", "set:il7"),
      cells = all_cells,
      path_id_out = "demo_path"
    )
  )
  stopifnot(is.list(raw_def), is.list(raw_def$outputs))
  path <- raw_def$outputs$path
  stopifnot(inherits(path, "wb_primitive"), identical(as.character(path$kind), "space_path_family"))
  stopifnot(identical(as.character(unique(path$space_id)), "lsi"))
  stopifnot(identical(as.character(unique(path$path_id)), "demo_path"))
  stopifnot(length(unique(path$point)) == 26L)
  stopifnot(identical(as.character(path$meta$fit_mode), "linear"))

  raw_smooth <- suppressWarnings(
    wb_op_space_path_define(
      bundle = b,
      space_id = "lsi",
      checkpoint_sets = c("core", "set:il7"),
      cells = all_cells,
      fit_mode = "manifold_smooth",
      smooth_k = 25L,
      smooth_n_iter = 2L,
      path_id_out = "demo_path_smooth"
    )
  )
  path_smooth <- raw_smooth$outputs$path
  stopifnot(inherits(path_smooth, "wb_primitive"), identical(as.character(path_smooth$kind), "space_path_family"))
  stopifnot(identical(as.character(path_smooth$meta$fit_mode), "manifold_smooth"))
  stopifnot(identical(as.character(path_smooth$meta$smooth_neighbor_mode), "knn"))
  stopifnot(isTRUE(path_smooth$meta$smooth_route_consistent))
  stopifnot(identical(as.integer(path_smooth$meta$smooth_k), 25L))
  stopifnot(identical(as.integer(path_smooth$meta$smooth_n_iter), 2L))

  lin_tbl <- wb_primitive_to_table(path, include_context = FALSE)
  sm_tbl <- wb_primitive_to_table(path_smooth, include_context = FALSE)
  stopifnot(identical(nrow(lin_tbl), nrow(sm_tbl)))

  anchor_idx <- as.integer(path_smooth$meta$anchor_point_index)
  lin_anchor <- lin_tbl[lin_tbl$point %in% anchor_idx, c("point", "dim", "value"), drop = FALSE]
  sm_anchor <- sm_tbl[sm_tbl$point %in% anchor_idx, c("point", "dim", "value"), drop = FALSE]
  lin_anchor <- lin_anchor[order(lin_anchor$point, lin_anchor$dim), , drop = FALSE]
  sm_anchor <- sm_anchor[order(sm_anchor$point, sm_anchor$dim), , drop = FALSE]
  stopifnot(isTRUE(all.equal(as.numeric(lin_anchor$value), as.numeric(sm_anchor$value), tolerance = 1e-8)))

  interior <- setdiff(sort(unique(lin_tbl$point)), anchor_idx)
  stopifnot(length(interior) > 0L)
  lin_int <- lin_tbl[lin_tbl$point %in% interior, c("point", "dim", "value"), drop = FALSE]
  sm_int <- sm_tbl[sm_tbl$point %in% interior, c("point", "dim", "value"), drop = FALSE]
  lin_int <- lin_int[order(lin_int$point, lin_int$dim), , drop = FALSE]
  sm_int <- sm_int[order(sm_int$point, sm_int$dim), , drop = FALSE]
  stopifnot(any(abs(as.numeric(lin_int$value) - as.numeric(sm_int$value)) > 1e-8))

  raw_score <- wb_op_space_path_score(
    bundle = b,
    space_id = "lsi",
    path = path_smooth,
    cells = all_cells[seq_len(500)]
  )
  stopifnot(is.list(raw_score), is.list(raw_score$outputs))
  scores <- raw_score$outputs$path_scores
  summary <- raw_score$outputs$fit_summary
  stopifnot(inherits(scores, "wb_primitive"), identical(as.character(scores$kind), "cell_vector_family"))
  stopifnot(inherits(summary, "wb_primitive"), identical(as.character(summary$kind), "obs_table"))
  stopifnot(setequal(unique(as.character(scores$key)), c("progress", "distance", "nearest_segment", "nearest_anchor")))
  stopifnot(nrow(summary$table) == 1L)
  stopifnot(all(c("path_id", "space_id", "fit_mode", "n_checkpoints", "n_path_points", "cells_scored") %in% names(summary$table)))

  raw_proj <- wb_op_space_path_project_2d(
    bundle = b,
    path = path_smooth,
    plot_space_id = "umap.atac",
    approx_points = 20L
  )
  stopifnot(is.list(raw_proj), is.list(raw_proj$outputs))
  curves <- raw_proj$outputs$curves
  stopifnot(inherits(curves, "wb_primitive"), identical(as.character(curves$kind), "path_2d_family"))
  stopifnot(identical(as.character(unique(curves$key)), "demo_path_smooth"))
  stopifnot(length(unique(curves$point)) == 20L)

  TRUE
}
