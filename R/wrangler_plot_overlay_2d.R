# R/wrangler_plot_overlay_2d.R

#' Overlay two 2D spaces (atlas + query) in one plot
#'
#' Core idea: plot "base" cells from a reference space (atlas),
#' then overlay "query" cells that live in another (often partial) space.
#'
#' This avoids ggplot layer-transplant pitfalls by always giving each geom
#' an explicit data= argument.
#'
#' @param bundle Bundle handle
#' @param base_space_id 2D space for the atlas/background cells
#' @param overlay_space_id 2D space for the query/overlay cells (can be partial)
#' @param base_cells Cells to draw in the background (default: core)
#' @param overlay_cells Cells to draw in the overlay (default: all non-core if you pass it)
#' @param overlay_color_by One of:
#'   - NULL (no color)
#'   - character(1): column name in SQLite `cells` table (e.g. "orig.ident")
#'   - named vector: names are cell_id, values are the color variable
#'   - data.frame with columns cell_id and value
#' @param overlay_color_label Legend title override (optional)
#' @param base_alpha,base_size Aesthetics for background points
#' @param overlay_alpha,overlay_size Aesthetics for overlay points
#' @return ggplot2 plot
#' @export
wb_plot_overlay_2d <- function(bundle,
                               base_space_id,
                               overlay_space_id,
                               base_cells = NULL,
                               overlay_cells = NULL,
                               overlay_color_by = NULL,
                               overlay_color_label = NULL,
                               base_alpha = 0.15,
                               base_size = 0.20,
                               overlay_alpha = 0.80,
                               overlay_size = 0.35) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  # defaults
  if (is.null(base_cells))   base_cells   <- wb_cells(bundle, cell_set = "core")
  if (is.null(overlay_cells)) overlay_cells <- wb_cells(bundle, cell_set = "all")

  base_cells <- as.character(base_cells)
  overlay_cells <- as.character(overlay_cells)

  # --- coords ---
  df_base <- wb_space(bundle, space_id = base_space_id, cells = base_cells)
  if (!is.data.frame(df_base) || !all(c("cell_id", "x", "y") %in% colnames(df_base))) {
    stop("wb_space() must return data.frame(cell_id, x, y) for base space.", call. = FALSE)
  }
  df_base <- df_base[, c("cell_id", "x", "y")]
  df_base$cell_id <- as.character(df_base$cell_id)

  df_ov <- wb_space(bundle, space_id = overlay_space_id, cells = overlay_cells)
  if (!is.data.frame(df_ov) || !all(c("cell_id", "x", "y") %in% colnames(df_ov))) {
    stop("wb_space() must return data.frame(cell_id, x, y) for overlay space.", call. = FALSE)
  }
  df_ov <- df_ov[, c("cell_id", "x", "y")]
  df_ov$cell_id <- as.character(df_ov$cell_id)

  # --- resolve overlay color to df_ov$value ---
  legend_name <- "value"
  if (!is.null(overlay_color_by)) {

    if (is.character(overlay_color_by) && length(overlay_color_by) == 1) {
      col <- overlay_color_by
      q <- sprintf('SELECT cell_id, "%s" AS value FROM cells;', col)
      md <- DBI::dbGetQuery(bundle$con, q)
      md$cell_id <- as.character(md$cell_id)

      df_ov$value <- md$value[match(df_ov$cell_id, md$cell_id)]
      legend_name <- col

    } else if (is.data.frame(overlay_color_by)) {
      stopifnot(all(c("cell_id", "value") %in% colnames(overlay_color_by)))
      md <- overlay_color_by[, c("cell_id", "value")]
      md$cell_id <- as.character(md$cell_id)

      df_ov$value <- md$value[match(df_ov$cell_id, md$cell_id)]
      legend_name <- "value"

    } else if (is.atomic(overlay_color_by) &&
               !is.null(names(overlay_color_by)) &&
               any(nzchar(names(overlay_color_by)))) {
      v <- overlay_color_by
      # preserve df_ov order; missing names -> NA
      df_ov$value <- unname(v[df_ov$cell_id])
      legend_name <- "value"

    } else {
      stop("overlay_color_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
           call. = FALSE)
    }
  }

  # --- plot ---
  p <- ggplot2::ggplot() +
    ggplot2::geom_point(
      data = df_base,
      ggplot2::aes(x = x, y = y),
      alpha = base_alpha, size = base_size
    )

  if (!is.null(overlay_color_by)) {
    .wb_assert("value" %in% colnames(df_ov), "Internal error: expected df_ov$value for overlay coloring.")
    p <- p +
      ggplot2::geom_point(
        data = df_ov,
        ggplot2::aes(x = x, y = y, color = value),
        alpha = overlay_alpha, size = overlay_size
      ) +
      ggplot2::labs(color = overlay_color_label %||% legend_name)
  } else {
    p <- p +
      ggplot2::geom_point(
        data = df_ov,
        ggplot2::aes(x = x, y = y),
        alpha = overlay_alpha, size = overlay_size
      )
  }

  p + ggplot2::labs(
    title = paste0("Overlay: ", base_space_id, " + ", overlay_space_id),
    x = "x", y = "y"
  )
}
