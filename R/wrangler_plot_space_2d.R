# R/wrangler_plot_space_2d.R

#' Plot a 2D space (e.g. UMAP) with flexible coloring
#'
#' @param bundle Bundle handle
#' @param space_id 2D space id (default "umap")
#' @param cells Optional subset of cells (default all)
#' @param color_by One of:
#'   - NULL (no color)
#'   - character(1): column name in SQLite `cells` table (e.g. "orig.ident")
#'   - named vector: names are cell_id, values are the color variable
#'   - data.frame with columns cell_id and value
#' @param color_label Legend title override (optional)
#' @param alpha,size Point aesthetics
#' @param label_groups If TRUE, label group ids at centroids (e.g. cluster numbers)
#' @param label_by Grouping used for centroid labels. If NULL, uses color_by (must be categorical-ish)
#' @param label_min_n Only label groups with at least this many cells
#' @return ggplot2 plot
#' @export
wb_plot_space_2d <- function(bundle,
                             space_id = NULL,
                             cells = NULL,
                             color_by = NULL,
                             color_label = NULL,
                             alpha = 0.6,
                             size = 0.25,
                             label_groups = FALSE,
                             label_by = NULL,
                             label_min_n = 50) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  # 1) base coords
  if (is.null(cells)) cells <- wb_cells(bundle)
  cells <- as.character(cells)

  sp <- wb_space(bundle, space_id = space_id, cells = cells)
  if (!is.data.frame(sp) || !all(c("cell_id", "x", "y") %in% colnames(sp))) {
    stop("wb_space() must return data.frame(cell_id, x, y) for 2D spaces.", call. = FALSE)
  }

  df <- sp[, c("cell_id", "x", "y")]
  df$cell_id <- as.character(df$cell_id)

  # 2) resolve color values (optional)
  color_vec <- NULL
  color_name <- NULL

  if (is.null(color_by)) {
    # no color
  } else if (is.character(color_by) && length(color_by) == 1) {
    col <- color_by
    con <- bundle$con

    # Fetch full column mapping (avoids SQLite "too many variables" from IN (...))
    q <- sprintf('SELECT cell_id, "%s" AS value FROM cells;', col)
    md <- DBI::dbGetQuery(con, q)

    md$cell_id <- as.character(md$cell_id)
    df <- merge(df, md, by = "cell_id", all.x = TRUE, sort = FALSE)
    color_name <- "value"
   }else if (is.data.frame(color_by)) {
    stopifnot(all(c("cell_id", "value") %in% colnames(color_by)))
    md <- color_by[, c("cell_id", "value")]
    md$cell_id <- as.character(md$cell_id)
    df <- merge(df, md, by = "cell_id", all.x = TRUE, sort = FALSE)
    color_name <- "value"
  } else if (is.atomic(color_by) && !is.null(names(color_by))) {
    v <- color_by
    md <- data.frame(cell_id = names(v), value = unname(v), stringsAsFactors = FALSE)
    md$cell_id <- as.character(md$cell_id)
    df <- merge(df, md, by = "cell_id", all.x = TRUE, sort = FALSE)
    color_name <- "value"
  } else {
    stop("color_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
         call. = FALSE)
  }

  # 3) base plot
  gp <- ggplot2::ggplot(df, ggplot2::aes(x = x, y = y))

  if (!is.null(color_by)) {
    gp <- gp + ggplot2::geom_point(
      ggplot2::aes(color = .data[[color_name]]),
      alpha = alpha, size = size
    ) + ggplot2::labs(color = color_label %||% color_name)
  } else {
    gp <- gp + ggplot2::geom_point(alpha = alpha, size = size)
  }

  gp <- gp + ggplot2::labs(
    title = paste0("Space: ", space_id),
    x = "x", y = "y"
  )

  # 4) optional centroid labels
  if (isTRUE(label_groups)) {
    # determine grouping column
    grp_col <- label_by
    if (is.null(grp_col)) grp_col <- color_name
    if (is.null(grp_col) || !grp_col %in% colnames(df)) {
      stop("label_groups=TRUE requires a grouping column. Provide label_by or color_by categorical.",
           call. = FALSE)
    }

    # compute centroids + sizes
    agg <- aggregate(
      df[, c("x", "y")],
      by = list(group = df[[grp_col]]),
      FUN = mean
    )
    sizes <- as.data.frame(table(df[[grp_col]]), stringsAsFactors = FALSE)
    colnames(sizes) <- c("group", "n")
    sizes$group <- as.character(sizes$group)

    agg$group <- as.character(agg$group)
    agg <- merge(agg, sizes, by = "group", all.x = TRUE, sort = FALSE)
    agg <- agg[agg$n >= as.integer(label_min_n), , drop = FALSE]

    gp <- gp + ggplot2::geom_text(
      data = agg,
      ggplot2::aes(x = x, y = y, label = group),
      inherit.aes = FALSE,
      color = "black",
      fontface = "bold",
      size = 4
    )
  }

  gp
}

`%||%` <- function(x, y) if (is.null(x)) y else x
