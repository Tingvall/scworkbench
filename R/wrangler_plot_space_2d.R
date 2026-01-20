#' Plot a 2D space with projection-aware overlay semantics
#'
#' When cell_set = "all", core cells are drawn as a muted background layer
#' and non-core cells (set:*) are drawn as an overlay foreground layer.
#'
#' A single color scale is used for both layers. Missing values (NA) are kept
#' and displayed as grey.
#'
#' @param bundle Bundle handle
#' @param space_id 2D space id
#' @param cell_set "core" | "all" | "set:<name>"
#' @param overlay_sets Optional character vector like c("set:tumorA","set:queryB").
#'   Only used when cell_set="all". If NULL, all non-core are overlaid.
#' @param color_by One of:
#'   - NULL
#'   - character(1): column name in SQLite `cells` table (e.g. "orig.ident")
#'   - named vector: names are cell_id, values are the color variable
#'   - data.frame with columns cell_id and value
#' @param color_label Legend title override (optional)
#' @param base_alpha,base_size Background aesthetics (core)
#' @param overlay_alpha,overlay_size Foreground aesthetics (non-core)
#' @param overlay_shape Shape for overlay points (default 16)
#' @param label_groups If TRUE, label group ids at centroids (e.g. cluster numbers)
#' @param label_by Grouping used for centroid labels. If NULL, uses the plotted color variable.
#' @param label_min_n Only label groups with at least this many cells
#' @return ggplot2 plot
#' @export
wb_plot_space_2d <- function(bundle,
                             space_id,
                             cell_set = c("core", "all"),
                             overlay_sets = NULL,
                             color_by = NULL,
                             color_label = NULL,
                             base_alpha = 0.15,
                             base_size = 0.20,
                             overlay_alpha = 0.85,
                             overlay_size = 0.35,
                             overlay_shape = 16,
                             overlay_stroke = 0.4,
                             overlay_outline = "grey20",
                             label_groups = FALSE,
                             label_by = NULL,
                             label_min_n = 50) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  cell_set <- as.character(cell_set[1])

  # ---- Decide which cells are base vs overlay ----
  if (cell_set == "core") {
    base_cells <- wb_cells(bundle, cell_set = "core")
    overlay_cells <- character(0)

  } else if (cell_set == "all") {
    base_cells <- wb_cells(bundle, cell_set = "core")

    all_cells <- wb_cells(bundle, cell_set = "all")
    noncore_cells <- setdiff(all_cells, base_cells)

    if (!is.null(overlay_sets)) {
      overlay_sets <- as.character(overlay_sets)
      set_cells <- unlist(lapply(overlay_sets, function(s) wb_cells(bundle, cell_set = s)), use.names = FALSE)
      overlay_cells <- intersect(noncore_cells, set_cells)
    } else {
      overlay_cells <- noncore_cells
    }

  } else if (startsWith(cell_set, "set:")) {
    base_cells <- character(0)
    overlay_cells <- wb_cells(bundle, cell_set = cell_set)

  } else {
    stop("cell_set must be 'core', 'all', or 'set:<name>'.", call. = FALSE)
  }

  base_cells <- as.character(base_cells)
  overlay_cells <- as.character(overlay_cells)

  # ---- Fetch coords (non-strict) ----
  empty_xy <- function() {
    data.frame(cell_id = character(0), x = numeric(0), y = numeric(0), stringsAsFactors = FALSE)
  }

  df_base <- if (length(base_cells)) .wb_space_2d_safe(bundle, space_id, base_cells) else empty_xy()
  df_ov   <- if (length(overlay_cells)) .wb_space_2d_safe(bundle, space_id, overlay_cells) else empty_xy()

  # Ensure expected columns exist even if 0 rows
  for (nm in c("cell_id", "x", "y")) {
    if (!nm %in% colnames(df_base)) df_base[[nm]] <- empty_xy()[[nm]]
    if (!nm %in% colnames(df_ov))   df_ov[[nm]]   <- empty_xy()[[nm]]
  }

  if (!nrow(df_base) && !nrow(df_ov)) {
    stop("No cells found in this space for the requested selection (after dropping missing coords).", call. = FALSE)
  }

  df_base$role <- rep("core",    nrow(df_base))
  df_ov$role   <- rep("overlay", nrow(df_ov))

  df_base$cell_id <- as.character(df_base$cell_id)
  df_ov$cell_id   <- as.character(df_ov$cell_id)

  # ---- Resolve color values for BOTH layers (key fix) ----
  legend_name <- NULL
  df_base$value <- rep(NA, nrow(df_base))
  df_ov$value   <- rep(NA, nrow(df_ov))


  if (!is.null(color_by)) {

    if (is.character(color_by) && length(color_by) == 1) {
      col <- color_by
      q <- sprintf('SELECT cell_id, "%s" AS value FROM cells;', col)
      md <- DBI::dbGetQuery(bundle$con, q)
      md$cell_id <- as.character(md$cell_id)

      df_base$value <- md$value[match(df_base$cell_id, md$cell_id)]
      df_ov$value   <- md$value[match(df_ov$cell_id,   md$cell_id)]
      legend_name <- col

    } else if (is.data.frame(color_by)) {
      .wb_assert(all(c("cell_id", "value") %in% colnames(color_by)),
                 "color_by data.frame must have columns cell_id and value.")
      md <- color_by[, c("cell_id", "value")]
      md$cell_id <- as.character(md$cell_id)

      df_base$value <- md$value[match(df_base$cell_id, md$cell_id)]
      df_ov$value   <- md$value[match(df_ov$cell_id,   md$cell_id)]
      legend_name <- "value"

    } else if (is.atomic(color_by) && !is.null(names(color_by)) && any(nzchar(names(color_by)))) {
      v <- color_by
      df_base$value <- unname(v[df_base$cell_id])
      df_ov$value   <- unname(v[df_ov$cell_id])
      legend_name <- "value"

    } else {
      stop("color_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
           call. = FALSE)
    }
  }

  # ---- Plot: two layers, same color meaning ----
  p <- ggplot2::ggplot()

  if (nrow(df_base)) {
    if (is.null(color_by)) {
      p <- p + ggplot2::geom_point(
        data = df_base,
        ggplot2::aes(x = x, y = y),
        alpha = base_alpha, size = base_size
      )
    } else {
      p <- p + ggplot2::geom_point(
        data = df_base,
        ggplot2::aes(x = x, y = y, color = value),
        alpha = base_alpha, size = base_size
      )
    }
  }

  if (nrow(df_ov)) {
    if (is.null(color_by)) {
      p <- p + ggplot2::geom_point(
        data = df_ov,
        ggplot2::aes(x = x, y = y),
        alpha = overlay_alpha, size = overlay_size, shape = overlay_shape,
        stroke = overlay_stroke,
        color = overlay_outline
      )
    } else {
      if (overlay_shape %in% 21:25) {
        # fill carries the value, color is outline
        p <- p + ggplot2::geom_point(
          data = df_ov,
          ggplot2::aes(x = x, y = y, fill = value),
          alpha = overlay_alpha, size = overlay_size, shape = overlay_shape,
          stroke = overlay_stroke,
          color = overlay_outline
        )
      } else {
        # normal shapes: color carries the value
        p <- p + ggplot2::geom_point(
          data = df_ov,
          ggplot2::aes(x = x, y = y, color = value),
          alpha = overlay_alpha, size = overlay_size, shape = overlay_shape
        )
      }
    }
  }


  # ---- Legend title + NA handling ----
  if (!is.null(color_by)) {
    lab <- color_label %||% legend_name %||% "value"

    # Use a discrete scale if value is not numeric; continuous otherwise.
    if (is.numeric(c(df_base$value, df_ov$value))) {
      p <- p + ggplot2::scale_color_continuous(na.value = "grey80") +
        ggplot2::labs(color = lab)
    } else {
      p <- p + ggplot2::scale_color_discrete(na.value = "grey80") +
        ggplot2::labs(color = lab)
    }
  }

  p <- p + ggplot2::labs(
    title = paste0("Space: ", space_id),
    x = "x", y = "y"
  )

  # ---- Optional centroid labels (uses SAME grouping variable) ----
  if (isTRUE(label_groups)) {
    # Build df for labeling from what was actually plotted
    df <- rbind(
      df_base[, c("cell_id", "x", "y", "role", "value"), drop = FALSE],
      df_ov[,   c("cell_id", "x", "y", "role", "value"), drop = FALSE]
    )

    grp_col <- label_by
    if (is.null(grp_col)) grp_col <- if (!is.null(color_by)) "value" else NULL

    .wb_assert(!is.null(grp_col) && grp_col %in% colnames(df),
               "label_groups=TRUE requires a grouping column (set label_by or supply color_by).")

    agg <- stats::aggregate(
      df[, c("x", "y")],
      by = list(group = df[[grp_col]]),
      FUN = mean
    )
    sizes <- as.data.frame(table(df[[grp_col]]), stringsAsFactors = FALSE)
    colnames(sizes) <- c("group", "n")
    agg$group <- as.character(agg$group)
    sizes$group <- as.character(sizes$group)
    agg <- merge(agg, sizes, by = "group", all.x = TRUE, sort = FALSE)
    agg <- agg[agg$n >= as.integer(label_min_n), , drop = FALSE]

    p <- p + ggplot2::geom_text(
      data = agg,
      ggplot2::aes(x = x, y = y, label = group),
      inherit.aes = FALSE,
      color = "black",
      fontface = "bold",
      size = 4
    )
  }

  p
}


