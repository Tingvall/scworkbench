# Plot contracts + mapper-based wranglers

.wb_plot_mapper_env <- local({
  e <- new.env(parent = emptyenv())
  e$registry <- list()
  e$defaults_registered <- FALSE
  e
})

.wb_plot_contracts <- function() {
  list(
    embedding_overlay = list(
      v1 = list(
        plot_type = "embedding_overlay",
        dataset_type = "embedding_overlay",
        version = "v1",
        required = c(cell_id = "character", x = "numeric", y = "numeric"),
        optional = c(
          color_value = "any",
          color_type = "character",
          shape_value = "any",
          size_value = "numeric",
          alpha_value = "numeric",
          set_name = "character",
          label = "character"
        )
      )
    ),
    volcano = list(
      v1 = list(
        plot_type = "volcano",
        dataset_type = "ranked_features",
        version = "v1",
        required = c(feature_id = "character", effect = "numeric", p_adj = "numeric"),
        optional = c(
          p_raw = "numeric",
          label = "character",
          significant = "logical",
          direction = "character",
          rank = "numeric"
        )
      )
    ),
    violin = list(
      v1 = list(
        plot_type = "violin",
        dataset_type = "distribution",
        version = "v1",
        required = c(entity_id = "character", group = "character", value = "numeric"),
        optional = c(
          color_value = "any",
          facet = "character",
          label = "character"
        )
      )
    ),
    dotplot = list(
      v1 = list(
        plot_type = "dotplot",
        dataset_type = "feature_group_summary",
        version = "v1",
        required = c(feature_id = "character", group = "character", pct_expr = "numeric", avg_expr = "numeric"),
        optional = c(
          rank = "numeric",
          significant = "logical",
          direction = "character",
          label = "character"
        )
      )
    )
  )
}

#' Get plot contract schema
#'
#' @param plot_type Plot type identifier
#' @param version Contract version (default: "v1")
#' @return Contract list with required/optional column schema
#' @export
wb_plot_contract <- function(plot_type, version = "v1") {
  pt <- as.character(plot_type)[1]
  vv <- as.character(version)[1]
  reg <- .wb_plot_contracts()
  .wb_assert(pt %in% names(reg), paste0("Unknown plot_type: ", pt))
  .wb_assert(vv %in% names(reg[[pt]]), paste0("Unknown contract version for ", pt, ": ", vv))
  reg[[pt]][[vv]]
}

.wb_plot_validate_col_type <- function(x, typ) {
  if (identical(typ, "any")) return(TRUE)
  if (identical(typ, "character")) return(is.character(x))
  if (identical(typ, "numeric")) return(is.numeric(x))
  if (identical(typ, "logical")) return(is.logical(x))
  if (identical(typ, "integer")) return(is.integer(x))
  TRUE
}

#' Validate wrangled plot dataset against a plot contract
#'
#' @param plot_type Plot type identifier
#' @param dataset Dataset list from `wb_wrangle_plot_dataset()`
#' @param version Contract version (default: "v1")
#' @return TRUE (invisibly) or error
#' @export
wb_plot_validate_dataset <- function(plot_type, dataset, version = "v1") {
  ct <- wb_plot_contract(plot_type, version = version)

  .wb_assert(is.list(dataset), "dataset must be a list")
  .wb_assert(is.data.frame(dataset$table), "dataset$table must be a data.frame")

  df <- dataset$table

  req <- ct$required %||% c()
  for (nm in names(req)) {
    .wb_assert(nm %in% colnames(df), paste0("dataset missing required column: ", nm))
    ok <- .wb_plot_validate_col_type(df[[nm]], req[[nm]])
    .wb_assert(isTRUE(ok), paste0("dataset column '", nm, "' must be type ", req[[nm]]))
  }

  opt <- ct$optional %||% c()
  for (nm in intersect(names(opt), colnames(df))) {
    ok <- .wb_plot_validate_col_type(df[[nm]], opt[[nm]])
    .wb_assert(isTRUE(ok), paste0("dataset column '", nm, "' must be type ", opt[[nm]]))
  }

  invisible(TRUE)
}

#' Register a plot mapper
#'
#' @param plot_type Plot type identifier
#' @param mapper_id Unique mapper id within plot_type
#' @param can_map Function(bundle, inputs, runs, version) -> TRUE/FALSE
#' @param map_fn Function(bundle, inputs, runs, version) -> dataset list
#' @param priority Lower runs first
#' @export
wb_plot_mapper_register <- function(plot_type,
                                    mapper_id,
                                    can_map,
                                    map_fn,
                                    priority = 100L) {
  pt <- as.character(plot_type)[1]
  mid <- as.character(mapper_id)[1]
  .wb_assert(nzchar(pt), "plot_type is required")
  .wb_assert(nzchar(mid), "mapper_id is required")
  .wb_assert(is.function(can_map), "can_map must be a function")
  .wb_assert(is.function(map_fn), "map_fn must be a function")

  cur <- .wb_plot_mapper_env$registry[[pt]] %||% list()
  keep <- vapply(cur, function(x) !identical(x$mapper_id, mid), logical(1))
  cur <- cur[keep]
  cur[[length(cur) + 1]] <- list(
    plot_type = pt,
    mapper_id = mid,
    can_map = can_map,
    map_fn = map_fn,
    priority = as.integer(priority)[1]
  )
  .wb_plot_mapper_env$registry[[pt]] <- cur
  invisible(TRUE)
}

#' List registered plot mappers
#'
#' @param plot_type Optional plot type filter
#' @return data.frame with mapper metadata
#' @export
wb_plot_mapper_list <- function(plot_type = NULL) {
  .wb_register_default_plot_mappers()

  reg <- .wb_plot_mapper_env$registry %||% list()
  pts <- names(reg)
  if (!is.null(plot_type)) {
    pts <- intersect(pts, as.character(plot_type))
  }

  rows <- list()
  for (pt in pts) {
    rr <- reg[[pt]] %||% list()
    if (!length(rr)) next
    ord <- order(vapply(rr, function(x) x$priority %||% 100L, numeric(1)),
                 vapply(rr, function(x) x$mapper_id %||% "", character(1)))
    rr <- rr[ord]
    for (x in rr) {
      rows[[length(rows) + 1]] <- data.frame(
        plot_type = as.character(x$plot_type),
        mapper_id = as.character(x$mapper_id),
        priority = as.integer(x$priority %||% 100L),
        stringsAsFactors = FALSE
      )
    }
  }

  if (!length(rows)) {
    return(data.frame(plot_type = character(0), mapper_id = character(0), priority = integer(0), stringsAsFactors = FALSE))
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.wb_plot_resolve_primitive <- function(bundle, x, runs = NULL, expected_kind = NULL) {
  if (is.null(x)) return(NULL)

  if (is.list(x) && identical(x$ref_type %||% "", "artifact")) {
    x <- list(type = "artifact", value = as.character(x$artifact_id)[1])
  } else if (is.list(x) && identical(x$ref_type %||% "", "run")) {
    x <- list(type = "session", value = list(run_id = as.character(x$run_id)[1], output = as.character(x$output)[1]))
  } else if (is.character(x) && length(x) == 1 && startsWith(x, "artifact:")) {
    x <- list(type = "artifact", value = sub("^artifact:", "", x))
  } else if (is.character(x) && length(x) == 1 && startsWith(x, "session:")) {
    parts <- strsplit(sub("^session:", "", x), ":", fixed = TRUE)[[1]]
    .wb_assert(length(parts) >= 2, "Bad session ref; expected session:<run_id>:<output>")
    x <- list(type = "session", value = list(run_id = parts[1], output = paste(parts[-1], collapse = ":")))
  }

  wb_resolve_primitive(bundle = bundle, spec = x, runs = runs, expected_kind = expected_kind)
}

.wb_plot_input_first <- function(inputs, keys) {
  for (k in keys) {
    if (!is.null(inputs[[k]])) return(inputs[[k]])
  }
  NULL
}

.wb_plot_resolve_vector_df <- function(bundle, vprim, key = NULL) {
  .wb_assert(.wb_is_primitive(vprim), "vector input did not resolve to primitive")

  if (identical(vprim$kind, "cell_vector")) {
    vv <- if (identical(vprim$value_type %||% "", "continuous")) as.numeric(vprim$value) else as.character(vprim$value)
    data.frame(
      cell_id = as.character(vprim$cell_id),
      value = vv,
      value_type = as.character(vprim$value_type %||% if (is.numeric(vv)) "continuous" else "categorical"),
      stringsAsFactors = FALSE
    )
  } else if (identical(vprim$kind, "cell_vector_family")) {
    k <- as.character(key %||% "")[1]
    if (!nzchar(k)) {
      ks <- unique(as.character(vprim$key))
      ks <- ks[nzchar(ks)]
      .wb_assert(length(ks) > 0, "cell_vector_family has no keys")
      k <- ks[1]
    }
    ii <- as.character(vprim$key) == k
    data.frame(
      cell_id = as.character(vprim$cell_id[ii]),
      value = as.numeric(vprim$value[ii]),
      value_type = "continuous",
      stringsAsFactors = FALSE
    )
  } else {
    stop("Expected cell_vector or cell_vector_family, got kind=", vprim$kind, call. = FALSE)
  }
}

.wb_plot_resolve_group_df <- function(bundle, inputs, runs = NULL, cell_ids = NULL) {
  gx <- .wb_plot_input_first(inputs, c("group", "group_ref", "group_vector"))
  if (!is.null(gx)) {
    gprim <- .wb_plot_resolve_primitive(bundle, gx, runs = runs)
    gdf <- .wb_plot_resolve_vector_df(bundle, gprim, key = inputs$group_key %||% NULL)
    out <- data.frame(
      cell_id = as.character(gdf$cell_id),
      group = as.character(gdf$value),
      stringsAsFactors = FALSE
    )
    return(out)
  }

  gcol <- as.character(inputs$group_by %||% "")[1]
  if (nzchar(gcol)) {
    md <- wb_meta(bundle, cells = cell_ids %||% NULL, cols = c("cell_id", gcol))
    out <- data.frame(
      cell_id = as.character(md$cell_id),
      group = as.character(md[[gcol]]),
      stringsAsFactors = FALSE
    )
    return(out)
  }

  data.frame(
    cell_id = as.character(cell_ids %||% wb_cells(bundle, cell_set = "all")),
    group = "all",
    stringsAsFactors = FALSE
  )
}

.wb_plot_mapper_embedding_can <- function(bundle, inputs, runs, version) {
  space_x <- .wb_plot_input_first(inputs, c("space", "space_ref", "space_2d", "embedding"))
  if (is.null(space_x)) return(FALSE)
  sx <- try(.wb_plot_resolve_primitive(bundle, space_x, runs = runs, expected_kind = "space_2d"), silent = TRUE)
  !inherits(sx, "try-error") && .wb_is_primitive(sx) && identical(sx$kind, "space_2d")
}

.wb_plot_mapper_embedding_map <- function(bundle, inputs, runs, version) {
  sref <- .wb_plot_input_first(inputs, c("space", "space_ref", "space_2d", "embedding"))
  sprim <- .wb_plot_resolve_primitive(bundle, sref, runs = runs, expected_kind = "space_2d")

  sid <- as.character(sprim$space_id)[1]
  .wb_assert(nzchar(sid), "space_2d input missing space_id")

  df <- .wb_space_2d_safe(bundle, sid, cells = NULL)
  .wb_assert(is.data.frame(df) && all(c("cell_id", "x", "y") %in% colnames(df)),
             "Could not resolve 2D coordinates for embedding overlay")

  cells <- .wb_order_like_bundle(bundle, unique(as.character(df$cell_id)))
  ii <- match(cells, as.character(df$cell_id))
  ii <- ii[!is.na(ii)]
  df <- df[ii, c("cell_id", "x", "y"), drop = FALSE]

  color_x <- .wb_plot_input_first(inputs, c("color", "color_ref", "color_vector"))
  if (!is.null(color_x)) {
    cprim <- .wb_plot_resolve_primitive(bundle, color_x, runs = runs)
    cdf <- .wb_plot_resolve_vector_df(bundle, cprim, key = inputs$color_key %||% inputs$key %||% NULL)
    cdf <- cdf[, c("cell_id", "value", "value_type"), drop = FALSE]
    names(cdf) <- c("cell_id", "color_value", "color_type")
    df <- merge(df, cdf, by = "cell_id", all.x = TRUE, sort = FALSE)
  }

  shape_x <- .wb_plot_input_first(inputs, c("shape", "shape_ref", "shape_vector"))
  if (!is.null(shape_x)) {
    sprim2 <- .wb_plot_resolve_primitive(bundle, shape_x, runs = runs)
    sdf <- .wb_plot_resolve_vector_df(bundle, sprim2, key = inputs$shape_key %||% NULL)
    sdf <- sdf[, c("cell_id", "value"), drop = FALSE]
    names(sdf) <- c("cell_id", "shape_value")
    df <- merge(df, sdf, by = "cell_id", all.x = TRUE, sort = FALSE)
  }

  sz_x <- .wb_plot_input_first(inputs, c("size", "size_ref", "size_vector"))
  if (!is.null(sz_x)) {
    zprim <- .wb_plot_resolve_primitive(bundle, sz_x, runs = runs)
    zdf <- .wb_plot_resolve_vector_df(bundle, zprim, key = inputs$size_key %||% NULL)
    zdf <- zdf[, c("cell_id", "value"), drop = FALSE]
    names(zdf) <- c("cell_id", "size_value")
    zdf$size_value <- suppressWarnings(as.numeric(zdf$size_value))
    df <- merge(df, zdf, by = "cell_id", all.x = TRUE, sort = FALSE)
  }

  a_x <- .wb_plot_input_first(inputs, c("alpha", "alpha_ref", "alpha_vector"))
  if (!is.null(a_x)) {
    aprim <- .wb_plot_resolve_primitive(bundle, a_x, runs = runs)
    adf <- .wb_plot_resolve_vector_df(bundle, aprim, key = inputs$alpha_key %||% NULL)
    adf <- adf[, c("cell_id", "value"), drop = FALSE]
    names(adf) <- c("cell_id", "alpha_value")
    adf$alpha_value <- suppressWarnings(as.numeric(adf$alpha_value))
    df <- merge(df, adf, by = "cell_id", all.x = TRUE, sort = FALSE)
  }

  overlay_sets <- as.character(inputs$overlay_sets %||% character(0))
  overlay_sets <- overlay_sets[nzchar(overlay_sets)]
  if (length(overlay_sets)) {
    df$set_name <- NA_character_
    for (sn in overlay_sets) {
      ids <- try(as.character(wb_cells(bundle, cell_set = sn)), silent = TRUE)
      if (inherits(ids, "try-error")) next
      hit <- match(df$cell_id, ids, nomatch = 0L) > 0L
      df$set_name[is.na(df$set_name) & hit] <- sn
    }
  }

  rownames(df) <- NULL

  list(
    plot_type = "embedding_overlay",
    dataset_type = "embedding_overlay",
    contract_version = as.character(version)[1],
    table = df,
    schema = wb_plot_contract("embedding_overlay", version = version),
    meta = list(
      space_id = sid,
      n_cells = nrow(df)
    )
  )
}

.wb_plot_mapper_volcano_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
  !inherits(tt, "try-error") && .wb_is_primitive(tt) && identical(tt$kind, "feature_table")
}

.wb_plot_mapper_volcano_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  .wb_assert("feature_id" %in% colnames(tbl), "volcano mapping requires feature_id column")

  effect_candidates <- unique(c(
    as.character(inputs$effect_col %||% ""),
    "avg_log1p_fc", "avg_log2FC", "log2FC", "logFC", "effect", "estimate"
  ))
  effect_candidates <- effect_candidates[nzchar(effect_candidates)]
  effect_col <- intersect(effect_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(nzchar(effect_col), "Could not infer effect column for volcano")

  padj_candidates <- unique(c(
    as.character(inputs$p_adj_col %||% ""),
    "p_val_adj", "padj", "p_adj", "q_value", "fdr"
  ))
  padj_candidates <- padj_candidates[nzchar(padj_candidates)]
  p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(nzchar(p_adj_col), "Could not infer adjusted p-value column for volcano")

  praw_candidates <- unique(c(
    as.character(inputs$p_raw_col %||% ""),
    "p_val", "pvalue", "p_value"
  ))
  praw_candidates <- praw_candidates[nzchar(praw_candidates)]
  p_raw_col <- intersect(praw_candidates, colnames(tbl))[1] %||% NA_character_

  out <- data.frame(
    feature_id = as.character(tbl$feature_id),
    effect = suppressWarnings(as.numeric(tbl[[effect_col]])),
    p_adj = suppressWarnings(as.numeric(tbl[[p_adj_col]])),
    stringsAsFactors = FALSE
  )

  if (nzchar(p_raw_col)) out$p_raw <- suppressWarnings(as.numeric(tbl[[p_raw_col]]))

  p_adj_thresh <- suppressWarnings(as.numeric(inputs$p_adj_thresh %||% 0.05))
  if (!is.finite(p_adj_thresh)) p_adj_thresh <- 0.05
  eff_thresh <- suppressWarnings(as.numeric(inputs$effect_thresh %||% 0))
  if (!is.finite(eff_thresh)) eff_thresh <- 0

  out$significant <- !is.na(out$p_adj) & (out$p_adj <= p_adj_thresh) & !is.na(out$effect) & (abs(out$effect) >= eff_thresh)
  out$direction <- ifelse(out$significant & out$effect > 0, "up",
                          ifelse(out$significant & out$effect < 0, "down", "ns"))

  ord <- order(out$p_adj, decreasing = FALSE, na.last = TRUE)
  out$rank <- NA_real_
  out$rank[ord] <- seq_along(ord)

  out$label <- ""
  nlab <- suppressWarnings(as.integer(inputs$top_n_labels %||% 0L))
  if (is.finite(nlab) && nlab > 0L) {
    sig_ord <- ord[out$significant[ord] %in% TRUE]
    take <- utils::head(sig_ord, nlab)
    out$label[take] <- out$feature_id[take]
  }

  out <- out[!is.na(out$effect) & !is.na(out$p_adj), , drop = FALSE]
  rownames(out) <- NULL

  list(
    plot_type = "volcano",
    dataset_type = "ranked_features",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("volcano", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_effect_col = effect_col,
      source_p_adj_col = p_adj_col,
      p_adj_thresh = p_adj_thresh,
      effect_thresh = eff_thresh,
      n_features = nrow(out)
    )
  )
}

.wb_plot_mapper_violin_can <- function(bundle, inputs, runs, version) {
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  if (is.null(vx)) return(FALSE)
  vv <- try(.wb_plot_resolve_primitive(bundle, vx, runs = runs), silent = TRUE)
  !inherits(vv, "try-error") && .wb_is_primitive(vv) && vv$kind %in% c("cell_vector", "cell_vector_family")
}

.wb_plot_mapper_violin_map <- function(bundle, inputs, runs, version) {
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  vprim <- .wb_plot_resolve_primitive(bundle, vx, runs = runs)
  vdf <- .wb_plot_resolve_vector_df(bundle, vprim, key = inputs$value_key %||% inputs$key %||% NULL)
  vdf$value <- suppressWarnings(as.numeric(vdf$value))
  vdf <- vdf[!is.na(vdf$value), , drop = FALSE]
  .wb_assert(nrow(vdf) > 0, "violin mapping yielded no numeric values")

  gdf <- .wb_plot_resolve_group_df(bundle, inputs, runs = runs, cell_ids = vdf$cell_id)
  out <- merge(
    data.frame(entity_id = as.character(vdf$cell_id), value = as.numeric(vdf$value), stringsAsFactors = FALSE),
    data.frame(entity_id = as.character(gdf$cell_id), group = as.character(gdf$group), stringsAsFactors = FALSE),
    by = "entity_id",
    all.x = TRUE,
    sort = FALSE
  )
  out$group[is.na(out$group) | !nzchar(out$group)] <- "NA"

  rownames(out) <- NULL
  list(
    plot_type = "violin",
    dataset_type = "distribution",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("violin", version = version),
    meta = list(
      n_rows = nrow(out),
      n_groups = length(unique(out$group))
    )
  )
}

.wb_plot_mapper_dotplot_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "markers_table", "de_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
  !inherits(tt, "try-error") && .wb_is_primitive(tt) && identical(tt$kind, "feature_table")
}

.wb_plot_mapper_dotplot_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "markers_table", "de_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  .wb_assert("feature_id" %in% colnames(tbl), "dotplot mapping requires feature_id column")

  group_candidates <- unique(c(as.character(inputs$group_col %||% ""), "cluster", "group", "cell_group"))
  group_candidates <- group_candidates[nzchar(group_candidates)]
  group_col <- intersect(group_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(nzchar(group_col), "Could not infer group column for dotplot")

  pct_candidates <- unique(c(as.character(inputs$pct_col %||% ""), "pct_expr", "pct_a", "percent_expr", "pct"))
  pct_candidates <- pct_candidates[nzchar(pct_candidates)]
  pct_col <- intersect(pct_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(nzchar(pct_col), "Could not infer pct_expr column for dotplot")

  avg_candidates <- unique(c(as.character(inputs$avg_col %||% ""), "avg_expr", "avg_expr_a", "mean_expr", "avg"))
  avg_candidates <- avg_candidates[nzchar(avg_candidates)]
  avg_col <- intersect(avg_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(nzchar(avg_col), "Could not infer avg_expr column for dotplot")

  out <- data.frame(
    feature_id = as.character(tbl$feature_id),
    group = as.character(tbl[[group_col]]),
    pct_expr = suppressWarnings(as.numeric(tbl[[pct_col]])),
    avg_expr = suppressWarnings(as.numeric(tbl[[avg_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$pct_expr) & !is.na(out$avg_expr), , drop = FALSE]

  if ("rank" %in% colnames(tbl)) out$rank <- suppressWarnings(as.numeric(tbl$rank))
  if ("direction" %in% colnames(tbl)) out$direction <- as.character(tbl$direction)
  if ("significant" %in% colnames(tbl)) out$significant <- as.logical(tbl$significant)

  rownames(out) <- NULL
  list(
    plot_type = "dotplot",
    dataset_type = "feature_group_summary",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("dotplot", version = version),
    meta = list(
      source_group_col = group_col,
      source_pct_col = pct_col,
      source_avg_col = avg_col,
      n_rows = nrow(out)
    )
  )
}

.wb_register_default_plot_mappers <- function() {
  if (isTRUE(.wb_plot_mapper_env$defaults_registered)) return(invisible(TRUE))

  wb_plot_mapper_register(
    plot_type = "embedding_overlay",
    mapper_id = "space2d_overlay_v1",
    can_map = .wb_plot_mapper_embedding_can,
    map_fn = .wb_plot_mapper_embedding_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "volcano",
    mapper_id = "feature_table_volcano_v1",
    can_map = .wb_plot_mapper_volcano_can,
    map_fn = .wb_plot_mapper_volcano_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "violin",
    mapper_id = "cell_vector_violin_v1",
    can_map = .wb_plot_mapper_violin_can,
    map_fn = .wb_plot_mapper_violin_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "dotplot",
    mapper_id = "feature_table_dotplot_v1",
    can_map = .wb_plot_mapper_dotplot_can,
    map_fn = .wb_plot_mapper_dotplot_map,
    priority = 10L
  )

  .wb_plot_mapper_env$defaults_registered <- TRUE
  invisible(TRUE)
}

#' Wrangle inputs into a validated plot dataset
#'
#' Any suitable primitive(s) that satisfy a plot contract can be mapped.
#'
#' @param plot_type Plot type identifier
#' @param inputs Named list of primitive refs / primitives
#' @param bundle Bundle handle
#' @param runs Optional runs list for session refs
#' @param version Contract version (default: "v1")
#' @return Dataset list with normalized table and metadata
#' @export
wb_wrangle_plot_dataset <- function(plot_type, inputs, bundle, runs = NULL, version = "v1") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.list(inputs), "inputs must be a named list")

  pt <- as.character(plot_type)[1]
  vv <- as.character(version)[1]

  wb_plot_contract(pt, vv) # validate known plot type/version
  .wb_register_default_plot_mappers()

  reg <- .wb_plot_mapper_env$registry[[pt]] %||% list()
  .wb_assert(length(reg) > 0, paste0("No mappers registered for plot_type: ", pt))

  ord <- order(vapply(reg, function(x) x$priority %||% 100L, numeric(1)),
               vapply(reg, function(x) x$mapper_id %||% "", character(1)))
  reg <- reg[ord]

  for (m in reg) {
    ok <- try(isTRUE(m$can_map(bundle = bundle, inputs = inputs, runs = runs, version = vv)), silent = TRUE)
    if (inherits(ok, "try-error") || !isTRUE(ok)) next

    ds <- m$map_fn(bundle = bundle, inputs = inputs, runs = runs, version = vv)
    .wb_assert(is.list(ds) && is.data.frame(ds$table),
               paste0("Mapper '", m$mapper_id, "' returned invalid dataset"))
    ds$plot_type <- pt
    ds$contract_version <- vv
    ds$mapper_id <- m$mapper_id

    wb_plot_validate_dataset(pt, ds, version = vv)
    return(ds)
  }

  mids <- vapply(reg, function(x) as.character(x$mapper_id), character(1))
  stop(
    "No compatible mapper found for plot_type '", pt,
    "'. Registered mappers: ", paste(mids, collapse = ", "),
    call. = FALSE
  )
}

#' Build renderer-agnostic plot spec from a validated dataset
#'
#' @param plot_type Plot type identifier
#' @param dataset Dataset list from `wb_wrangle_plot_dataset()`
#' @param style Optional style preset identifier
#' @param version Contract version (default: "v1")
#' @return Plot spec list suitable for client renderers
#' @export
wb_plot_spec <- function(plot_type, dataset, style = "default", version = "v1") {
  pt <- as.character(plot_type)[1]
  vv <- as.character(version)[1]
  wb_plot_validate_dataset(pt, dataset, version = vv)

  df <- dataset$table

  if (identical(pt, "embedding_overlay")) {
    tip <- c("cell_id")
    for (nm in c("color_value", "shape_value", "size_value", "alpha_value", "set_name", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "embedding_overlay",
      version = vv,
      style = as.character(style)[1],
      geom = "point",
      encoding = list(
        x = "x",
        y = "y",
        color = if ("color_value" %in% names(df)) "color_value" else NULL,
        shape = if ("shape_value" %in% names(df)) "shape_value" else NULL,
        size = if ("size_value" %in% names(df)) "size_value" else NULL,
        alpha = if ("alpha_value" %in% names(df)) "alpha_value" else NULL,
        group = if ("set_name" %in% names(df)) "set_name" else NULL
      ),
      scales = list(
        color_type = if ("color_type" %in% names(df)) {
          ux <- unique(as.character(stats::na.omit(df$color_type)))
          if (length(ux) == 1) ux[1] else "mixed"
        } else NULL
      ),
      guides = list(color = TRUE, shape = TRUE, size = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "volcano")) {
    tip <- c("feature_id", "effect", "p_adj")
    for (nm in c("direction", "significant", "p_raw", "rank", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "ranked_features",
      version = vv,
      style = as.character(style)[1],
      geom = "point",
      encoding = list(
        x = "effect",
        y = "p_adj",
        y_transform = "neg_log10",
        color = if ("direction" %in% names(df)) "direction" else NULL,
        label = if ("label" %in% names(df)) "label" else NULL
      ),
      guides = list(color = TRUE, label = TRUE),
      reference = list(x = 0, y = dataset$meta$p_adj_thresh %||% 0.05),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "violin")) {
    tip <- c("entity_id", "group", "value")
    for (nm in c("color_value", "facet", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "distribution",
      version = vv,
      style = as.character(style)[1],
      geom = "violin",
      encoding = list(
        x = "group",
        y = "value",
        color = "group",
        entity = "entity_id"
      ),
      guides = list(color = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "dotplot")) {
    tip <- c("feature_id", "group", "pct_expr", "avg_expr")
    for (nm in c("direction", "significant", "rank", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "feature_group_summary",
      version = vv,
      style = as.character(style)[1],
      geom = "point",
      encoding = list(
        x = "group",
        y = "feature_id",
        size = "pct_expr",
        color = "avg_expr"
      ),
      guides = list(size = TRUE, color = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  stop("wb_plot_spec(): unsupported plot_type: ", pt, call. = FALSE)
}
