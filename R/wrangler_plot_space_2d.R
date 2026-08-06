#' Plot a 2D Space with Overlay Sets and Per-Set Glyph Styles
#'
#' @param bundle An open scworkbench bundle.
#' @param space_id Two-dimensional space identifier.
#' @param cell_set Base display universe: `"core"`, `"all"`, or a cell set.
#' @param overlay_sets Optional cell sets drawn over base cells.
#' @param color_by Optional metadata column or compatible vector source.
#' @param color_label Optional legend label for `color_by`.
#' @param base_alpha Base-point alpha.
#' @param base_size Base-point size.
#' @param overlay_alpha Overlay-point alpha.
#' @param overlay_size Overlay-point size.
#' @param overlay_shape ggplot point shape for overlays.
#' @param overlay_stroke Outline stroke width for overlays.
#' @param overlay_outline Outline color for overlays.
#' @param label_groups Whether to label groups.
#' @param label_by Optional grouping column used for labels.
#' @param label_min_n Minimum group size for labels.
#' @param continuous_palette Continuous palette name.
#' @param continuous_na_color Color for missing continuous values.
#' @param debug Whether to return debugging details with the plot.
#' @return A ggplot object, or debugging output when `debug = TRUE`.
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
                             label_min_n = 50,
                             continuous_palette = "magma",
                             continuous_na_color = "grey80",
                             debug = FALSE) {

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Missing suggested package 'ggplot2' for plotting.", call. = FALSE)
  }

  `%||%` <- function(x, y) if (is.null(x)) y else x
  cell_set <- as.character(cell_set[1])
  cont_pal <- tolower(as.character(continuous_palette %||% "magma")[1])
  if (!nzchar(cont_pal)) cont_pal <- "magma"
  cont_na <- as.character(continuous_na_color %||% "grey80")[1]
  if (!nzchar(cont_na)) cont_na <- "grey80"
  cont_pal_ok <- cont_pal %in% c("magma", "viridis", "plasma", "inferno", "cividis", "rocket", "mako", "turbo")

  # -------------------------
  # 1) Resolve base vs overlay cell IDs
  # -------------------------
  if (cell_set == "core") {
    base_cells <- wb_cells(bundle, cell_set = "core")
    overlay_sets <- character(0)

  } else if (cell_set == "all") {
    base_cells <- wb_cells(bundle, cell_set = "core")
    if (is.null(overlay_sets)) {
      # default for "all": overlay all non-core (but only if you actually have them)
      overlay_sets <- setdiff(wb_cell_sets(bundle), "core")
      overlay_sets <- overlay_sets[startsWith(overlay_sets, "set:")]
    } else {
      overlay_sets <- as.character(overlay_sets)
    }

  } else if (startsWith(cell_set, "set:")) {
    base_cells <- character(0)
    overlay_sets <- cell_set

  } else {
    stop("cell_set must be 'core', 'all', or 'set:<name>'.", call. = FALSE)
  }

  # base cells
  base_cells <- as.character(base_cells)

  # overlay cells: union of overlay_sets (each set plotted separately)
  overlay_sets <- as.character(overlay_sets %||% character(0))
  overlay_sets <- unique(overlay_sets[nzchar(overlay_sets)])

  overlay_cells_by_set <- list()
  for (s in overlay_sets) {
    overlay_cells_by_set[[s]] <- as.character(wb_cells(bundle, cell_set = s))
  }

  overlay_cells <- unique(unlist(overlay_cells_by_set, use.names = FALSE))

  # prevent double-plotting: if base is core and overlay includes core members, remove them from base
  if (length(base_cells) && length(overlay_cells)) {
    base_cells <- setdiff(base_cells, overlay_cells)
  }

  # -------------------------
  # 2) Fetch coords
  # -------------------------
  empty_xy <- function() data.frame(cell_id = character(0), x = numeric(0), y = numeric(0), stringsAsFactors = FALSE)

  df_base <- if (length(base_cells)) .wb_space_2d_safe(bundle, space_id, base_cells) else empty_xy()
  df_base$cell_id <- as.character(df_base$cell_id)

  df_ov_all <- if (length(overlay_cells)) .wb_space_2d_safe(bundle, space_id, overlay_cells) else empty_xy()
  df_ov_all$cell_id <- as.character(df_ov_all$cell_id)

  # Defensive sanitization: malformed/partial space rows (NA/Inf coords) should not
  # leak into ggplot layers and cause warning loops in reactive clients.
  if (nrow(df_base)) {
    keep_base <- is.finite(df_base$x) & is.finite(df_base$y)
    keep_base[is.na(keep_base)] <- FALSE
    df_base <- df_base[keep_base, , drop = FALSE]
    rownames(df_base) <- NULL
  }
  if (nrow(df_ov_all)) {
    keep_ov <- is.finite(df_ov_all$x) & is.finite(df_ov_all$y)
    keep_ov[is.na(keep_ov)] <- FALSE
    df_ov_all <- df_ov_all[keep_ov, , drop = FALSE]
    rownames(df_ov_all) <- NULL
  }

  if (!nrow(df_base) && !nrow(df_ov_all)) {
    stop("No cells found in this space for requested selection.", call. = FALSE)
  }

  # -------------------------
  # 3) Resolve color values (single legend)
  # -------------------------
  df_base$value <- rep(NA, nrow(df_base))
  df_ov_all$value <- rep(NA, nrow(df_ov_all))
  legend_name <- NULL

  if (!is.null(color_by)) {

    if (.wb_is_metadata_field_ref(color_by) || (is.character(color_by) && length(color_by) == 1)) {
      col <- color_by
      md <- wb_meta(bundle, cols = list(wb_ref_metadata_field("core:cell_id"), col))
      names(md)[2L] <- "value"
      md$cell_id <- as.character(md$cell_id)

      df_base$value   <- md$value[match(df_base$cell_id,   md$cell_id)]
      df_ov_all$value <- md$value[match(df_ov_all$cell_id, md$cell_id)]
      legend_name <- if (.wb_is_metadata_field_ref(col)) col$field_id else col

    } else if (is.data.frame(color_by)) {
      .wb_assert(all(c("cell_id", "value") %in% colnames(color_by)),
                 "color_by data.frame must have columns cell_id and value.")
      md <- color_by[, c("cell_id", "value")]
      md$cell_id <- as.character(md$cell_id)

      df_base$value   <- md$value[match(df_base$cell_id,   md$cell_id)]
      df_ov_all$value <- md$value[match(df_ov_all$cell_id, md$cell_id)]
      legend_name <- "value"

    } else if (is.atomic(color_by) && !is.null(names(color_by))) {
      v <- color_by
      df_base$value   <- unname(v[df_base$cell_id])
      df_ov_all$value <- unname(v[df_ov_all$cell_id])
      legend_name <- "value"

    } else {
      stop("color_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
           call. = FALSE)
    }
  }

  # -------------------------
  # 4) Helper: style fetch (NO silent failure)
  # -------------------------
  get_style <- function(cs) {
    # local defaults
    d <- list(
      alpha = overlay_alpha,
      size = overlay_size,
      shape = overlay_shape,
      stroke = overlay_stroke,
      outline = overlay_outline,
      fill_mode = "auto"
    )

    sty <- NULL
    sty <- tryCatch(
      wb_get_cell_set_style(bundle, cs),
      error = function(e) NULL
    )

    if (is.null(sty) || !is.data.frame(sty) || nrow(sty) == 0) {
      return(d)
    }

    # Normalize from the first row
    row <- sty[1, , drop = FALSE]

    out <- d
    if ("alpha" %in% names(row) && !is.na(row$alpha))   out$alpha  <- as.numeric(row$alpha)
    if ("size"  %in% names(row) && !is.na(row$size))    out$size   <- as.numeric(row$size)
    if ("shape" %in% names(row) && !is.na(row$shape))   out$shape  <- as.integer(row$shape)
    if ("stroke" %in% names(row) && !is.na(row$stroke)) out$stroke <- as.numeric(row$stroke)

    if ("outline" %in% names(row) && !is.null(row$outline) && !is.na(row$outline) && nzchar(row$outline)) {
      out$outline <- as.character(row$outline)
    }

    if ("fill_mode" %in% names(row) && !is.null(row$fill_mode) && !is.na(row$fill_mode) && nzchar(row$fill_mode)) {
      out$fill_mode <- as.character(row$fill_mode)
    }

    out
  }

  # -------------------------
  # 5) Plot base
  # -------------------------
  p <- ggplot2::ggplot()

  if (nrow(df_base)) {
    if (is.null(color_by)) {
      p <- p + ggplot2::geom_point(
        data = df_base,
        ggplot2::aes(x = x, y = y),
        alpha = base_alpha, size = base_size,
        color = "grey80"
      )
    } else {
      p <- p + ggplot2::geom_point(
        data = df_base,
        ggplot2::aes(x = x, y = y, color = value),
        alpha = base_alpha, size = base_size
      )
    }
  }

  # -------------------------
  # 6) Plot overlay: each set separately with its style
  # -------------------------
  if (length(overlay_sets)) {
    for (cs in overlay_sets) {
      cells_cs <- overlay_cells_by_set[[cs]] %||% character(0)
      if (!length(cells_cs)) next

      sub <- df_ov_all[df_ov_all$cell_id %in% cells_cs, , drop = FALSE]
      if (!nrow(sub)) next

      sty <- get_style(cs)

      if (isTRUE(debug)) {
        message("overlay set: ", cs, " n=", nrow(sub),
                " shape=", sty$shape, " size=", sty$size,
                " alpha=", sty$alpha, " stroke=", sty$stroke,
                " outline=", sty$outline, " fill_mode=", sty$fill_mode)
      }

      if (is.null(color_by)) {
        p <- p + ggplot2::geom_point(
          data = sub,
          ggplot2::aes(x = x, y = y),
          shape  = sty$shape,
          size   = sty$size,
          alpha  = sty$alpha,
          stroke = sty$stroke,
          color  = sty$outline
        )
      } else {
        use_fill <- (sty$fill_mode == "fill") || (sty$fill_mode == "auto" && sty$shape %in% 21:25)

        if (use_fill) {
          p <- p + ggplot2::geom_point(
            data = sub,
            ggplot2::aes(x = x, y = y, fill = value),
            shape  = sty$shape,
            size   = sty$size,
            alpha  = sty$alpha,
            stroke = sty$stroke,
            color  = sty$outline
          )
        } else {
          p <- p + ggplot2::geom_point(
            data = sub,
            ggplot2::aes(x = x, y = y, color = value),
            shape = sty$shape,
            size  = sty$size,
            alpha = sty$alpha
          )
        }
      }
    }
  }


  # -------------------------
  # 7) Single legend handling (only if color_by used)
  # -------------------------
  if (!is.null(color_by)) {
    lab <- color_label %||% legend_name %||% "value"

    if (is.numeric(c(df_base$value, df_ov_all$value))) {
      if (!identical(cont_pal, "default") && isTRUE(cont_pal_ok) && requireNamespace("viridisLite", quietly = TRUE)) {
        p <- p +
          ggplot2::scale_color_viridis_c(option = cont_pal, na.value = cont_na) +
          ggplot2::scale_fill_viridis_c(option = cont_pal, na.value = cont_na) +
          ggplot2::labs(color = lab, fill = lab)
      } else {
        p <- p +
          ggplot2::scale_color_continuous(na.value = cont_na) +
          ggplot2::scale_fill_continuous(na.value = cont_na) +
          ggplot2::labs(color = lab, fill = lab)
      }
    } else {
      p <- p +
        ggplot2::scale_color_discrete(na.value = cont_na) +
        ggplot2::scale_fill_discrete(na.value = cont_na) +
        ggplot2::labs(color = lab, fill = lab)
    }
  }

  # -------------------------
  # 8) Optional centroid labels (typically for categorical overlays like Leiden)
  # -------------------------
  if (isTRUE(label_groups)) {
    df_lbl <- rbind(
      df_base[, c("cell_id", "x", "y", "value"), drop = FALSE],
      df_ov_all[, c("cell_id", "x", "y", "value"), drop = FALSE]
    )
    rownames(df_lbl) <- NULL

    if (nrow(df_lbl)) {
      # label_by can override the grouping source. Supported forms mirror color_by.
      if (!is.null(label_by)) {
        df_lbl$label_value <- NA
        if (.wb_is_metadata_field_ref(label_by) || (is.character(label_by) && length(label_by) == 1L)) {
          col <- label_by
          md <- wb_meta(bundle, cols = list(wb_ref_metadata_field("core:cell_id"), col))
          names(md)[2L] <- "label_value"
          md$cell_id <- as.character(md$cell_id)
          df_lbl$label_value <- md$label_value[match(df_lbl$cell_id, md$cell_id)]
        } else if (is.data.frame(label_by)) {
          .wb_assert(all(c("cell_id", "value") %in% colnames(label_by)),
                     "label_by data.frame must have columns cell_id and value.")
          md <- label_by[, c("cell_id", "value"), drop = FALSE]
          md$cell_id <- as.character(md$cell_id)
          df_lbl$label_value <- md$value[match(df_lbl$cell_id, md$cell_id)]
        } else if (is.atomic(label_by) && !is.null(names(label_by))) {
          vv <- label_by
          df_lbl$label_value <- unname(vv[df_lbl$cell_id])
        } else {
          stop("label_by must be NULL, a metadata column name, a named vector, or data.frame(cell_id,value).",
               call. = FALSE)
        }
      } else {
        df_lbl$label_value <- df_lbl$value
      }

      keep_lbl <- is.finite(df_lbl$x) & is.finite(df_lbl$y) & !is.na(df_lbl$label_value)
      keep_lbl[is.na(keep_lbl)] <- FALSE
      df_lbl <- df_lbl[keep_lbl, , drop = FALSE]

      # Avoid nonsense centroid labels for continuous scales unless caller explicitly supplies label_by
      # and it is categorical.
      if (nrow(df_lbl)) {
        lab_is_numeric <- is.numeric(df_lbl$label_value)
        if (!isTRUE(lab_is_numeric)) {
          df_lbl$label_chr <- as.character(df_lbl$label_value)
          df_lbl <- df_lbl[nzchar(df_lbl$label_chr), , drop = FALSE]
          if (nrow(df_lbl)) {
            split_idx <- split(seq_len(nrow(df_lbl)), df_lbl$label_chr)
            cent <- do.call(rbind, lapply(names(split_idx), function(g) {
              ii <- split_idx[[g]]
              data.frame(
                label = g,
                n = length(ii),
                x = mean(df_lbl$x[ii], na.rm = TRUE),
                y = mean(df_lbl$y[ii], na.rm = TRUE),
                stringsAsFactors = FALSE
              )
            }))
            rownames(cent) <- NULL
            cent <- cent[is.finite(cent$x) & is.finite(cent$y), , drop = FALSE]
            cent <- cent[cent$n >= as.integer(label_min_n %||% 1L), , drop = FALSE]

            if (nrow(cent)) {
              p <- p + ggplot2::geom_text(
                data = cent,
                ggplot2::aes(x = x, y = y, label = label),
                inherit.aes = FALSE,
                size = 3.5,
                color = "black",
                fontface = "bold",
                check_overlap = TRUE
              )
            }
          }
        }
      }
    }
  }

  p + ggplot2::labs(title = paste0("Space: ", space_id), x = "x", y = "y")
}
