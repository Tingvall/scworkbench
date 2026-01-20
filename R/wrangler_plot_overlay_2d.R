#' Plot a 2D space (e.g. UMAP) with flexible coloring + core/query overlay semantics
#'
#' cell_set semantics:
#' - "core": plot only core
#' - "all":  plot core (muted) + non-core (foreground overlay)
#' - "set:<name>": plot only that set
#'
#' @param bundle Bundle handle
#' @param space_id 2D space id
#' @param cell_set "core" (default), "all", or "set:<name>"
#' @param cells Optional explicit subset of cells (advanced; overrides cell_set)
#' @param overlay_sets Optional subset of sets to overlay when cell_set="all"
#' @param color_by NULL, metadata column, named vector, or df(cell_id,value)
#' @param color_label Legend title override (optional)
#' @param base_alpha,base_size aesthetics for base (core) layer when overlaying
#' @param overlay_alpha,overlay_size aesthetics for overlay layer
#' @param label_groups If TRUE, label group ids at centroids (uses overlay groups if overlaying)
#' @param label_by Grouping used for centroid labels ("value" by default when colored)
#' @param label_min_n Only label groups with at least this many cells
#' @return ggplot2 plot
#' @export
wb_plot_space_2d <- function(bundle,
                             space_id,
                             cell_set = "core",
                             cells = NULL,
                             overlay_sets = NULL,
                             color_by = NULL,
                             color_label = NULL,
                             base_alpha = 0.15,
                             base_size = 0.20,
                             overlay_alpha = 0.80,
                             overlay_size = 0.35,
                             label_groups = FALSE,
                             label_by = NULL,
                             label_min_n = 50) {

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  # ---- resolve cells that actually exist in this space (prevents wb_space hard-fail) ----
  have_space <- wb_cells_with_space(bundle, space_id)

  # ---- explicit cells override everything (advanced mode) ----
  if (!is.null(cells)) {
    plot_cells <- intersect(as.character(cells), have_space)
    .wb_assert(length(plot_cells) > 0, "No requested cells exist in this space.")
    df <- wb_space(bundle, space_id = space_id, cells = plot_cells)
    df$cell_id <- as.character(df$cell_id)
    df_base <- df
    df_ov <- NULL
  } else {

    # overlay semantics driven by cell_set
    core_cells <- intersect(wb_cells(bundle, cell_set = "core"), have_space)

    if (identical(cell_set, "all")) {
      # base = core
      base_cells <- core_cells

      # overlay = all non-core cells that exist in this space
      all_cells <- intersect(wb_cells(bundle, cell_set = "all"), have_space)
      ov_cells <- setdiff(all_cells, core_cells)

      # optional restriction by overlay_sets
      if (!is.null(overlay_sets) && length(overlay_sets) > 0) {
        ov_from_sets <- unique(unlist(lapply(overlay_sets, function(s) wb_cells(bundle, cell_set = s))))
        ov_cells <- intersect(ov_cells, ov_from_sets)
      }

      df_base <- wb_space(bundle, space_id = space_id, cells = base_cells)
      df_base$cell_id <- as.character(df_base$cell_id)

      df_ov <- NULL
      if (length(ov_cells) > 0) {
        df_ov <- wb_space(bundle, space_id = space_id, cells = ov_cells)
        df_ov$cell_id <- as.character(df_ov$cell_id)
      }

    } else {
      # non-overlay mode: just plot the requested set
      plot_cells <- intersect(wb_cells(bundle, cell_set = cell_set), have_space)
      .wb_assert(length(plot_cells) > 0,
                 paste0("No cells for cell_set='", cell_set, "' exist in space '", space_id, "'."))
      df_base <- wb_space(bundle, space_id = space_id, cells = plot_cells)
      df_base$cell_id <- as.character(df_base$cell_id)
      df_ov <- NULL
    }
  }

  # ---- helper: attach df$value given color spec ----
  .wb_attach_value <- function(df, color_by) {
    legend_name <- "value"
    if (is.null(color_by)) return(list(df = df, legend_name = legend_name))

    if (is.character(color_by) && length(color_by) == 1) {
      col <- color_by
      q <- sprintf('SELECT cell_id, "%s" AS value FROM cells;', col)
      md <- DBI::dbGetQuery(bundle$con, q)
      md$cell_id <- as.character(md$cell_id)
      df$value <- md$value[match(df$cell_id, md$cell_id)]
      legend_name <- col

    } else if (is.data.frame(color_by)) {
      stopifnot(all(c("cell_id", "value") %in% colnames(color_by)))
      md <- color_by[, c("cell_id", "value")]
      md$cell_id <- as.character(md$cell_id)
      df$value <- md$value[match(df$cell_id, md$cell_id)]
      legend_name <- "value"

    } else if (is.atomic(color_by) && !is.null(names(color_by)) && any(nzchar(names(color_by)))) {
      v <- color_by
      df$value <- unname(v[df$cell_id])
      legend_name <- "value"

    } else {
      stop("color_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
           call. = FALSE)
    }

    list(df = df, legend_name = legend_name)
  }

  # Rule: when overlaying (cell_set="all"), color applies to overlay; base stays muted.
  legend_name <- "value"
  if (!is.null(df_ov)) {
    tmp <- .wb_attach_value(df_ov, color_by)
    df_ov <- tmp$df
    legend_name <- tmp$legend_name
  } else if (!is.null(color_by)) {
    tmp <- .wb_attach_value(df_base, color_by)
    df_base <- tmp$df
    legend_name <- tmp$legend_name
  }

  # ---- plot ----
  p <- ggplot2::ggplot()

  # base layer
  p <- p + ggplot2::geom_point(
    data = df_base,
    ggplot2::aes(x = x, y = y),
    alpha = if (!is.null(df_ov)) base_alpha else overlay_alpha,
    size  = if (!is.null(df_ov)) base_size  else overlay_size
  )

  # overlay layer if present
  if (!is.null(df_ov) && nrow(df_ov) > 0) {
    if (!is.null(color_by)) {
      .wb_assert("value" %in% colnames(df_ov), "Internal error: expected df_ov$value for coloring.")
      p <- p +
        ggplot2::geom_point(
          data = df_ov,
          ggplot2::aes(x = x, y = y, color = value),
          alpha = overlay_alpha,
          size  = overlay_size
        ) +
        ggplot2::labs(color = color_label %||% legend_name)
    } else {
      p <- p +
        ggplot2::geom_point(
          data = df_ov,
          ggplot2::aes(x = x, y = y),
          alpha = overlay_alpha,
          size  = overlay_size
        )
    }
  } else {
    # single-layer coloring case
    if (!is.null(color_by)) {
      .wb_assert("value" %in% colnames(df_base), "Internal error: expected df_base$value for coloring.")
      p <- p +
        ggplot2::geom_point(
          data = df_base,
          ggplot2::aes(x = x, y = y, color = value),
          alpha = overlay_alpha,
          size  = overlay_size
        ) +
        ggplot2::labs(color = color_label %||% legend_name)
    }
  }

  p <- p + ggplot2::labs(
    title = paste0("Space: ", space_id, " (cell_set=", cell_set, ")"),
    x = "x", y = "y"
  )

  # ---- centroid labels ----
  if (isTRUE(label_groups)) {
    df_lab <- if (!is.null(df_ov) && nrow(df_ov) > 0) df_ov else df_base

    grp_col <- label_by
    if (is.null(grp_col)) grp_col <- if (!is.null(color_by)) "value" else NULL
    if (is.null(grp_col) || !grp_col %in% colnames(df_lab)) {
      stop("label_groups=TRUE requires a grouping column. Provide label_by or color_by categorical.",
           call. = FALSE)
    }

    agg <- aggregate(df_lab[, c("x", "y")], by = list(group = df_lab[[grp_col]]), FUN = mean)
    sizes <- as.data.frame(table(df_lab[[grp_col]]), stringsAsFactors = FALSE)
    colnames(sizes) <- c("group", "n")
    agg$group <- as.character(agg$group)
    sizes$group <- as.character(sizes$group)
    agg <- merge(agg, sizes, by = "group", all.x = TRUE, sort = FALSE)
    agg <- agg[agg$n >= as.integer(label_min_n), , drop = FALSE]

    if (nrow(agg) > 0) {
      p <- p + ggplot2::geom_text(
        data = agg,
        ggplot2::aes(x = x, y = y, label = group),
        inherit.aes = FALSE,
        fontface = "bold",
        size = 4
      )
    }
  }

  p
}
