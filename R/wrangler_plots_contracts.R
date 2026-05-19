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
    trend_scatter = list(
      v1 = list(
        plot_type = "trend_scatter",
        dataset_type = "feature_scatter",
        version = "v1",
        required = c(feature_id = "character", x = "numeric", y = "numeric"),
        optional = c(
          p_adj = "numeric",
          p_raw = "numeric",
          direction = "character",
          significant = "logical",
          rank = "numeric",
          label = "character",
          color_value = "any",
          size_value = "numeric"
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
    category_count_bar = list(
      v1 = list(
        plot_type = "category_count_bar",
        dataset_type = "category_summary",
        version = "v1",
        required = c(category = "character", count = "numeric"),
        optional = c(
          pct = "numeric",
          rank = "numeric",
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
    ),
    pathway_bar = list(
      v1 = list(
        plot_type = "pathway_bar",
        dataset_type = "pathway_summary",
        version = "v1",
        required = c(pathway = "character", p_adj = "numeric"),
        optional = c(
          score = "numeric",
          overlap = "numeric",
          set_size = "numeric",
          query_size = "numeric",
          namespace = "character",
          significant = "logical",
          label = "character"
        )
      )
    ),
    ranked_lollipop = list(
      v1 = list(
        plot_type = "ranked_lollipop",
        dataset_type = "ranked_entities",
        version = "v1",
        required = c(feature_id = "character", score = "numeric"),
        optional = c(
          p_adj = "numeric",
          p_raw = "numeric",
          direction = "character",
          significant = "logical",
          rank = "numeric",
          label = "character"
        )
      )
    ),
    heatmap_ranked = list(
      v1 = list(
        plot_type = "heatmap_ranked",
        dataset_type = "matrix_like",
        version = "v1",
        required = c(feature_id = "character", group = "character", value = "numeric"),
        optional = c(
          rank = "numeric",
          label = "character",
          direction = "character",
          significant = "logical"
        )
      )
    ),
    feature_rank_bar = list(
      v1 = list(
        plot_type = "feature_rank_bar",
        dataset_type = "ranked_features",
        version = "v1",
        required = c(feature_id = "character", value = "numeric"),
        optional = c(
          rank = "numeric",
          label = "character",
          direction = "character",
          significant = "logical",
          p_adj = "numeric",
          p_raw = "numeric"
        )
      )
    ),
    pseudotime_smooth_panel = list(
      v1 = list(
        plot_type = "pseudotime_smooth_panel",
        dataset_type = "trajectory_smooth",
        version = "v1",
        required = c(feature_id = "character", pseudotime = "numeric", expr = "numeric"),
        optional = c(
          lineage_id = "character",
          n_cells = "integer",
          label = "character"
        )
      )
    ),
    pseudotime_signature_line = list(
      v1 = list(
        plot_type = "pseudotime_signature_line",
        dataset_type = "trajectory_signature_smooth",
        version = "v1",
        required = c(feature_set = "character", pseudotime = "numeric", value = "numeric"),
        optional = c(
          lineage_id = "character",
          n_cells = "integer",
          label = "character",
          feature_id = "character",
          driver_rank = "integer",
          value_raw = "numeric",
          value_smooth = "numeric",
          value_se = "numeric",
          value_ci_low = "numeric",
          value_ci_high = "numeric"
        )
      )
    )
  )
}

#' Get A Plot Contract Schema
#'
#' Fetch the canonical contract schema for one plot type and version.
#'
#' @param plot_type Plot type identifier.
#' @param version Contract version, default `"v1"`.
#'
#' @return A contract list with required and optional column schema.
#'
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

#' Validate A Wrangled Plot Dataset
#'
#' Check that a wrangled dataset satisfies the declared plot contract.
#'
#' @param plot_type Plot type identifier.
#' @param dataset Dataset list from [wb_wrangle_plot_dataset()].
#' @param version Contract version, default `"v1"`.
#'
#' @return `TRUE` invisibly, or an error when validation fails.
#'
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

#' Register A Plot Mapper
#'
#' Register an engine-side mapper from primitive inputs to a normalized plot
#' dataset.
#'
#' @param plot_type Plot type identifier.
#' @param mapper_id Unique mapper id within `plot_type`.
#' @param can_map Function `(bundle, inputs, runs, version) -> TRUE/FALSE`.
#' @param map_fn Function `(bundle, inputs, runs, version) -> dataset list`.
#' @param priority Lower values run first.
#'
#' @return Invisibly returns `TRUE`.
#'
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

#' List Registered Plot Mappers
#'
#' Inspect the current plot-mapper registry, optionally restricted to one plot
#' type.
#'
#' @param plot_type Optional plot type filter.
#'
#' @return A data frame with mapper metadata.
#'
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

.wb_plot_null_if_blank <- function(x) {
  y <- as.character(x %||% "")[1]
  if (!nzchar(y)) return(NULL)
  if (identical(tolower(y), "na")) return(NULL)
  y
}

.wb_plot_ref_artifact_id <- function(ref) {
  if (is.null(ref)) return("")
  if (.wb_is_primitive(ref)) {
    aid <- as.character(ref$artifact_id %||% "")[1]
    if (nzchar(aid)) return(aid)
  }
  if (is.list(ref) && identical(as.character(ref$ref_type %||% "")[1], "artifact")) {
    return(as.character(ref$artifact_id %||% "")[1])
  }
  if (is.character(ref) && length(ref) == 1L && startsWith(ref, "artifact:")) {
    raw <- sub("^artifact:", "", as.character(ref)[1])
    parts <- strsplit(raw, ":", fixed = TRUE)[[1]]
    if (length(parts) >= 1L) return(as.character(parts[1]))
  }
  ""
}

.wb_plot_ucell_signal_ref <- function(bundle, ref) {
  if (!inherits(bundle, "scworkbench_bundle")) return(NULL)
  aid <- .wb_plot_ref_artifact_id(ref)
  if (!nzchar(aid)) return(NULL)

  info <- try(wb_art_table_info(bundle, aid), silent = TRUE)
  if (inherits(info, "try-error") || !is.data.frame(info) || nrow(info) != 1L) return(NULL)
  if (!identical(as.character(info$type[1] %||% "")[1], "obs_table")) return(NULL)
  if (!identical(as.character(info$source_op[1] %||% "")[1], "ucell")) return(NULL)
  if (!identical(as.character(info$table_type[1] %||% "")[1], "ucell_signature_summary")) return(NULL)

  bc <- try(
    wb_art_birth_certificate(
      bundle,
      artifact_id = aid,
      include_parents = FALSE,
      include_children = FALSE,
      include_snapshot_run = TRUE
    ),
    silent = TRUE
  )
  if (inherits(bc, "try-error") || !is.list(bc)) return(NULL)

  link <- bc$persisted_provenance$selected_link %||% data.frame(stringsAsFactors = FALSE)
  if (!is.data.frame(link) || nrow(link) < 1L) return(NULL)
  sid <- as.character(link$snapshot_id[1] %||% "")[1]
  rid <- as.character(link$run_id[1] %||% "")[1]
  if (!nzchar(sid) || !nzchar(rid) || !.wb_table_exists(bundle$con, "prov_run_outputs")) return(NULL)

  hit <- try(DBI::dbGetQuery(
    bundle$con,
    "SELECT artifact_id
     FROM prov_run_outputs
     WHERE snapshot_id = ? AND run_id = ? AND output_name = ?
     ORDER BY artifact_id
     LIMIT 1;",
    params = list(sid, rid, "signature_scores")
  ), silent = TRUE)
  if (inherits(hit, "try-error") || !is.data.frame(hit) || nrow(hit) != 1L) return(NULL)

  sig_aid <- as.character(hit$artifact_id[1] %||% "")[1]
  if (!nzchar(sig_aid)) return(NULL)
  paste0("artifact:", sig_aid)
}

#' Build Minimal Plot Inputs For Compatibility Probing
#'
#' Encodes the canonical alias mapping from a single reference (`ref`) to
#' the minimal input list expected by plot mappers.
#'
#' @param plot_type Plot type identifier.
#' @param ref Primitive ref, artifact ref, or session ref accepted by plot
#'   wranglers.
#' @param bundle Optional bundle, used for limited inference on some plot paths.
#' @param runs Optional runs list for session refs.
#'
#' @return Named list suitable for [wb_wrangle_plot_dataset()].
#'
#' @export
wb_plot_min_inputs <- function(plot_type, ref, bundle = NULL, runs = NULL) {
  pt <- as.character(plot_type)[1]
  infer_ref_primitive <- function() {
    if (.wb_is_primitive(ref)) return(ref)
    if (!inherits(bundle, "scworkbench_bundle")) return(NULL)

    sib <- .wb_plot_ucell_signal_ref(bundle, ref)
    if (!is.null(sib)) {
      px2 <- try(.wb_plot_resolve_primitive(bundle, sib, runs = runs), silent = TRUE)
      if (!inherits(px2, "try-error") && .wb_is_primitive(px2)) return(px2)
    }

    px <- try(.wb_plot_resolve_primitive(bundle, ref, runs = runs), silent = TRUE)
    if (!inherits(px, "try-error") && .wb_is_primitive(px)) return(px)
    NULL
  }
  infer_matrix_id <- function() {
    if (!inherits(bundle, "scworkbench_bundle")) return(NULL)
    aid <- .wb_plot_ref_artifact_id(ref)
    if (nzchar(aid)) {
      mid_bc <- try({
        bc <- wb_art_birth_certificate(
          bundle,
          artifact_id = aid,
          include_parents = FALSE,
          include_children = FALSE,
          include_snapshot_run = FALSE
        )
        as.character(bc$identity$input_matrix_id %||% "")[1]
      }, silent = TRUE)
      if (!inherits(mid_bc, "try-error") && nzchar(as.character(mid_bc)[1])) return(as.character(mid_bc)[1])
    }

    tx <- try(.wb_plot_resolve_primitive(bundle, ref, runs = runs, expected_kind = "feature_table"), silent = TRUE)
    if (inherits(tx, "try-error") || !.wb_is_primitive(tx)) return(NULL)

    mid <- as.character(tx$meta$matrix_id %||% "")[1]
    if (nzchar(mid)) return(mid)

    tbl <- try(wb_primitive_to_table(tx, include_context = FALSE), silent = TRUE)
    if (!inherits(tbl, "try-error") && is.data.frame(tbl) && ("matrix_id" %in% colnames(tbl))) {
      mids <- unique(as.character(tbl$matrix_id))
      mids <- mids[nzchar(mids)]
      if (length(mids)) return(mids[1])
    }

    mm <- try(wb_matrices(bundle), silent = TRUE)
    if (!inherits(mm, "try-error") && is.data.frame(mm) && nrow(mm)) {
      mid <- as.character(mm$matrix_id[1] %||% "")[1]
      if (nzchar(mid)) return(mid)
    }
    NULL
  }
  infer_pseudotime_ref <- function() {
    if (!inherits(bundle, "scworkbench_bundle")) return(NULL)
    vv <- try(wb_list_vector_sources(bundle, runs = runs), silent = TRUE)
    if (inherits(vv, "try-error") || !is.data.frame(vv) || !nrow(vv) || !("ref" %in% colnames(vv))) return(NULL)

    refs <- as.character(vv$ref)
    refs <- refs[nzchar(refs)]
    if (!length(refs)) return(NULL)

    nms <- tolower(as.character(vv$name %||% vv$output_name %||% ""))
    hit <- which(grepl("pseudotime", nms, fixed = TRUE))
    if (length(hit)) return(refs[hit[1]])
    refs[1]
  }
  infer_space_ref <- function() {
    px <- infer_ref_primitive()
    if (.wb_is_primitive(px) && identical(as.character(px$kind %||% ""), "space_2d")) {
      sid <- as.character(px$space_id %||% "")[1]
      if (nzchar(sid)) return(px)
    }

    if (!inherits(bundle, "scworkbench_bundle")) return(NULL)

    aid <- .wb_plot_ref_artifact_id(ref)
    if (nzchar(aid)) {
      sid_bc <- try({
        bc <- wb_art_birth_certificate(
          bundle,
          artifact_id = aid,
          include_parents = FALSE,
          include_children = FALSE,
          include_snapshot_run = FALSE
        )
        as.character(bc$identity$input_space_id %||% "")[1]
      }, silent = TRUE)
      sid_bc <- as.character(sid_bc %||% "")[1]
      if (!inherits(sid_bc, "try-error") && nzchar(sid_bc)) {
        xy <- try(.wb_space_2d_safe(bundle, sid_bc, cells = NULL), silent = TRUE)
        if (!inherits(xy, "try-error") && is.data.frame(xy) && nrow(xy) > 0) {
          return(wb_prim_space_2d(sid_bc))
        }
      }
    }

    sp <- try(wb_spaces(bundle), silent = TRUE)
    if (inherits(sp, "try-error") || !is.data.frame(sp) || !nrow(sp) || !("space_id" %in% colnames(sp))) return(NULL)
    if ("dims" %in% colnames(sp)) {
      sp <- sp[!is.na(sp$dims) & as.integer(sp$dims) == 2L, , drop = FALSE]
    }
    if (!nrow(sp)) return(NULL)

    for (sid in as.character(sp$space_id)) {
      if (!nzchar(sid)) next
      xy <- try(.wb_space_2d_safe(bundle, sid, cells = NULL), silent = TRUE)
      if (!inherits(xy, "try-error") && is.data.frame(xy) && nrow(xy) > 0) {
        return(wb_prim_space_2d(sid))
      }
    }
    NULL
  }

  px <- infer_ref_primitive()
  pk <- as.character(px$kind %||% "")[1]

  switch(
    pt,
    embedding_overlay = {
      sig_ref <- .wb_plot_ucell_signal_ref(bundle, ref) %||% ref
      if (identical(pk, "cell_vector") || identical(pk, "cell_vector_family")) {
        sref <- infer_space_ref()
        if (is.null(sref)) list(space = sig_ref) else list(space = sref, color = sig_ref)
      } else {
        list(space = ref)
      }
    },
    volcano = list(table = ref),
    trend_scatter = list(table = ref),
    violin = if (identical(pk, "cell_vector") || identical(pk, "cell_vector_family")) list(vector = (.wb_plot_ucell_signal_ref(bundle, ref) %||% ref)) else list(vector = ref, table = ref),
    category_count_bar = list(vector = ref),
    dotplot = list(table = ref),
    pathway_bar = list(table = ref),
    ranked_lollipop = list(table = ref),
    heatmap_ranked = list(table = ref),
    feature_rank_bar = list(table = ref),
    pseudotime_smooth_panel = list(table = ref),
    pseudotime_signature_line = list(table = ref),
    stop("Unsupported plot_type for minimal input mapping: ", pt, call. = FALSE)
  )
}

#' Discover Compatible Plot Types
#'
#' Contract-first helper for clients: compatibility is determined by the engine's
#' registered plot mappers (`can_map` + `map_fn` + dataset validation), not by
#' client-side primitive-kind heuristics.
#'
#' @param ref Primitive ref or primitive accepted by plot wranglers.
#' @param bundle Open `scworkbench_bundle`.
#' @param runs Optional runs list for session refs.
#' @param plot_types Optional subset of plot types to probe.
#' @param version Contract version, default `"v1"`.
#'
#' @return A data frame with `plot_type`, `ok`, `mapper_id`, and `error`.
#'
#' @export
wb_plot_compatible_types <- function(ref, bundle, runs = NULL, plot_types = NULL, version = "v1") {
  rep <- wb_plot_compatibility_report(
    ref = ref,
    bundle = bundle,
    runs = runs,
    plot_types = plot_types,
    version = version
  )
  rep[, c("plot_type", "ok", "mapper_id", "error"), drop = FALSE]
}

.wb_plot_compat_reason_code <- function(msg) {
  txt <- tolower(as.character(msg %||% "")[1])
  if (!nzchar(txt)) return("ok")
  if (grepl("unsupported plot_type for minimal input mapping", txt, fixed = TRUE)) return("unsupported_plot_type")
  if (grepl("no compatible mapper found for plot_type", txt, fixed = TRUE)) return("no_compatible_mapper")
  if (grepl("unknown plot_type", txt, fixed = TRUE)) return("unknown_plot_type")
  if (grepl("unknown contract version", txt, fixed = TRUE)) return("unknown_contract_version")
  "wrangle_error"
}

#' Build A Plot Compatibility Report
#'
#' Engine-owned compatibility diagnostics for clients. This probes plot mappers
#' using canonical minimal inputs and returns structured reasons when a plot type
#' is not compatible with the provided ref.
#'
#' @inheritParams wb_plot_compatible_types
#'
#' @return A data frame with `plot_type`, `ok`, `mapper_id`, `reason_code`,
#'   `reason`, and `error`.
#'
#' @export
wb_plot_compatibility_report <- function(ref, bundle, runs = NULL, plot_types = NULL, version = "v1") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  if (is.null(ref) || (is.character(ref) && length(ref) == 1 && !nzchar(ref))) {
    return(data.frame(
      plot_type = character(0),
      ok = logical(0),
      mapper_id = character(0),
      reason_code = character(0),
      reason = character(0),
      error = character(0),
      stringsAsFactors = FALSE
    ))
  }

  pts <- if (is.null(plot_types)) names(.wb_plot_contracts()) else as.character(plot_types)
  pts <- unique(pts[nzchar(pts)])
  if (!length(pts)) {
    return(data.frame(
      plot_type = character(0),
      ok = logical(0),
      mapper_id = character(0),
      reason_code = character(0),
      reason = character(0),
      error = character(0),
      stringsAsFactors = FALSE
    ))
  }

  rows <- vector("list", length(pts))
  for (i in seq_along(pts)) {
    pt <- pts[[i]]
    ok <- FALSE
    mapper_id <- NA_character_
    err <- NA_character_
    reason_code <- "unknown"
    reason <- NA_character_

    inps_try <- try(wb_plot_min_inputs(pt, ref, bundle = bundle, runs = runs), silent = TRUE)
    if (inherits(inps_try, "try-error")) {
      err <- as.character(inps_try)
      reason_code <- .wb_plot_compat_reason_code(err)
      reason <- "Could not construct minimal inputs for this plot type."
    } else {
      ds_try <- try(
        wb_wrangle_plot_dataset(
          plot_type = pt,
          inputs = inps_try,
          bundle = bundle,
          runs = runs,
          version = version
        ),
        silent = TRUE
      )
      if (!inherits(ds_try, "try-error") && is.list(ds_try)) {
        ok <- TRUE
        mapper_id <- as.character(ds_try$mapper_id %||% NA_character_)[1]
        err <- NA_character_
        reason_code <- "ok"
        reason <- "Compatible mapper found and dataset validated."
      } else if (inherits(ds_try, "try-error")) {
        err <- as.character(ds_try)
        reason_code <- .wb_plot_compat_reason_code(err)
        reason <- switch(
          reason_code,
          no_compatible_mapper = "No registered mapper could map this ref to the requested plot contract.",
          unsupported_plot_type = "No canonical minimal-input mapping is defined for this plot type.",
          unknown_plot_type = "Plot type is not registered in engine plot contracts.",
          unknown_contract_version = "Requested plot contract version is not available.",
          "Plot wrangling failed while probing compatibility."
        )
      }
    }

    rows[[i]] <- data.frame(
      plot_type = as.character(pt),
      ok = isTRUE(ok),
      mapper_id = as.character(mapper_id %||% NA_character_),
      reason_code = as.character(reason_code %||% NA_character_),
      reason = as.character(reason %||% NA_character_),
      error = as.character(err %||% NA_character_),
      stringsAsFactors = FALSE
    )
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
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
  .wb_assert(!is.na(effect_col) && nzchar(effect_col), "Could not infer effect column for volcano")

  padj_candidates <- unique(c(
    as.character(inputs$p_adj_col %||% ""),
    "p_val_adj", "padj", "p_adj", "q_value", "fdr"
  ))
  padj_candidates <- padj_candidates[nzchar(padj_candidates)]
  p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(p_adj_col) && nzchar(p_adj_col), "Could not infer adjusted p-value column for volcano")

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

.wb_plot_mapper_trend_scatter_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "trend_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "feature_table")) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl)) return(FALSE)
  if (!("feature_id" %in% colnames(tbl))) return(FALSE)
  has_x <- any(c("mean_expr", "avg_expr", "avg_expr_a", "pct_nonzero", "abs_rho", "rank") %in% colnames(tbl))
  has_y <- any(c("rho", "slope", "score", "effect", "estimate") %in% colnames(tbl))
  isTRUE(has_x && has_y)
}

.wb_plot_mapper_trend_scatter_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "trend_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  .wb_assert("feature_id" %in% colnames(tbl), "trend_scatter mapping requires feature_id column")

  x_candidates <- unique(c(
    as.character(inputs$x_col %||% ""),
    "mean_expr", "avg_expr", "avg_expr_a", "pct_nonzero", "abs_rho", "rank"
  ))
  x_candidates <- x_candidates[nzchar(x_candidates)]
  x_col <- intersect(x_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(x_col) && nzchar(x_col), "Could not infer x column for trend_scatter")

  y_candidates <- unique(c(
    as.character(inputs$y_col %||% ""),
    "rho", "slope", "score", "effect", "estimate"
  ))
  y_candidates <- y_candidates[nzchar(y_candidates)]
  y_col <- intersect(y_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(y_col) && nzchar(y_col), "Could not infer y column for trend_scatter")

  out <- data.frame(
    feature_id = as.character(tbl$feature_id),
    x = suppressWarnings(as.numeric(tbl[[x_col]])),
    y = suppressWarnings(as.numeric(tbl[[y_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[nzchar(out$feature_id) & is.finite(out$x) & is.finite(out$y), , drop = FALSE]
  .wb_assert(nrow(out) > 0, "trend_scatter mapping yielded no finite rows")

  padj_candidates <- c("p_val_adj", "padj", "p_adj", "q_value", "fdr")
  p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
  if (!is.na(p_adj_col) && nzchar(p_adj_col)) out$p_adj <- suppressWarnings(as.numeric(tbl[[p_adj_col]]))

  praw_candidates <- c("p_val", "pvalue", "p_value")
  p_raw_col <- intersect(praw_candidates, colnames(tbl))[1] %||% NA_character_
  if (!is.na(p_raw_col) && nzchar(p_raw_col)) out$p_raw <- suppressWarnings(as.numeric(tbl[[p_raw_col]]))

  if ("direction" %in% colnames(tbl)) {
    out$direction <- as.character(tbl$direction)
  } else {
    out$direction <- ifelse(out$y > 0, "up", ifelse(out$y < 0, "down", "flat"))
  }

  p_adj_thresh <- suppressWarnings(as.numeric(inputs$p_adj_thresh %||% 0.05))
  if (!is.finite(p_adj_thresh)) p_adj_thresh <- 0.05
  out$significant <- if ("p_adj" %in% names(out)) (!is.na(out$p_adj) & out$p_adj <= p_adj_thresh) else TRUE

  if ("pct_nonzero" %in% colnames(tbl)) out$size_value <- suppressWarnings(as.numeric(tbl$pct_nonzero))
  out$label <- out$feature_id
  ord <- order(abs(out$y), decreasing = TRUE, na.last = TRUE)
  out$rank <- NA_real_
  out$rank[ord] <- seq_along(ord)
  rownames(out) <- NULL

  list(
    plot_type = "trend_scatter",
    dataset_type = "feature_scatter",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("trend_scatter", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_x_col = x_col,
      source_y_col = y_col,
      source_p_adj_col = p_adj_col,
      source_p_raw_col = p_raw_col,
      p_adj_thresh = p_adj_thresh,
      n_rows = nrow(out)
    )
  )
}

.wb_plot_mapper_violin_can <- function(bundle, inputs, runs, version) {
  # Path A: direct vector input
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  if (!is.null(vx)) {
    vv <- try(.wb_plot_resolve_primitive(bundle, vx, runs = runs), silent = TRUE)
    if (!inherits(vv, "try-error") && .wb_is_primitive(vv) && (vv$kind %in% c("cell_vector", "cell_vector_family"))) {
      vdf <- try(.wb_plot_resolve_vector_df(bundle, vv, key = inputs$value_key %||% inputs$key %||% NULL), silent = TRUE)
      if (!inherits(vdf, "try-error") && is.data.frame(vdf) && nrow(vdf)) {
        vtype <- unique(as.character(vdf$value_type %||% ""))
        vtype <- vtype[nzchar(vtype)]
        if (isTRUE(length(vtype) > 0 && all(vtype == "continuous"))) return(TRUE)
      }
    }
  }

  # Path B: obs_table with per-cell value/group columns (e.g. cell_vector_assoc_cells)
  tx <- .wb_plot_input_first(inputs, c("table", "obs_table", "assoc_cells"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "obs_table")) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl) || !nrow(tbl)) return(FALSE)
  val_col <- intersect(c("value", "score"), colnames(tbl))[1] %||% NA_character_
  id_col <- intersect(c("entity_id", "cell_id"), colnames(tbl))[1] %||% NA_character_
  grp_col <- intersect(c("group", "cluster", "label"), colnames(tbl))[1] %||% NA_character_
  has_group_override <- !is.null(.wb_plot_input_first(inputs, c("group", "group_ref", "group_vector"))) ||
    nzchar(as.character(inputs$group_by %||% "")[1])
  if (is.na(val_col) || is.na(id_col)) return(FALSE)
  if (is.na(grp_col) && !has_group_override) return(FALSE)
  v <- suppressWarnings(as.numeric(tbl[[val_col]]))
  any(is.finite(v))
}

.wb_plot_mapper_violin_map <- function(bundle, inputs, runs, version) {
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  out <- NULL
  use_vector_path <- FALSE
  vprim <- NULL
  if (!is.null(vx)) {
    vprim_try <- try(.wb_plot_resolve_primitive(bundle, vx, runs = runs), silent = TRUE)
    if (!inherits(vprim_try, "try-error") && .wb_is_primitive(vprim_try) &&
        (vprim_try$kind %in% c("cell_vector", "cell_vector_family"))) {
      use_vector_path <- TRUE
      vprim <- vprim_try
    }
  }

  if (isTRUE(use_vector_path)) {
    vdf <- .wb_plot_resolve_vector_df(bundle, vprim, key = inputs$value_key %||% inputs$key %||% NULL)
    vtype <- unique(as.character(vdf$value_type %||% ""))
    vtype <- vtype[nzchar(vtype)]
    .wb_assert(length(vtype) > 0 && all(vtype == "continuous"),
               "violin mapping requires a continuous cell vector (categorical vectors like Leiden clusters are not supported).")
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
  } else {
    tx <- .wb_plot_input_first(inputs, c("table", "obs_table", "assoc_cells"))
    tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table")
    tbl <- wb_primitive_to_table(tprim, include_context = FALSE)
    val_col <- intersect(c("value", "score"), colnames(tbl))[1] %||% NA_character_
    grp_col <- intersect(c("group", "cluster", "label"), colnames(tbl))[1] %||% NA_character_
    id_col <- intersect(c("entity_id", "cell_id"), colnames(tbl))[1] %||% NA_character_
    .wb_assert(!is.na(val_col) && !is.na(id_col),
               "violin table mapping requires columns for entity_id/cell_id and value.")
    out <- data.frame(
      entity_id = as.character(tbl[[id_col]]),
      value = suppressWarnings(as.numeric(tbl[[val_col]])),
      stringsAsFactors = FALSE
    )
    if (!is.na(grp_col)) {
      out$group <- as.character(tbl[[grp_col]])
    } else {
      out$group <- "all"
    }
    out <- out[is.finite(out$value) & !is.na(out$entity_id) & nzchar(out$entity_id), , drop = FALSE]
    has_group_override <- !is.null(.wb_plot_input_first(inputs, c("group", "group_ref", "group_vector"))) ||
      nzchar(as.character(inputs$group_by %||% "")[1])
    if (isTRUE(has_group_override)) {
      gdf <- .wb_plot_resolve_group_df(bundle, inputs, runs = runs, cell_ids = out$entity_id)
      if (is.data.frame(gdf) && nrow(gdf)) {
        gsel <- data.frame(
          entity_id = as.character(gdf$cell_id),
          group_override = as.character(gdf$group),
          stringsAsFactors = FALSE
        )
        out <- merge(out, gsel, by = "entity_id", all.x = TRUE, sort = FALSE)
        hit <- !is.na(out$group_override) & nzchar(out$group_override)
        out$group[hit] <- out$group_override[hit]
        out$group_override <- NULL
      }
    }
    out$group[is.na(out$group) | !nzchar(out$group)] <- "NA"
    .wb_assert(nrow(out) > 0, "violin table mapping yielded no numeric values")
  }

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

.wb_plot_mapper_category_count_bar_can <- function(bundle, inputs, runs, version) {
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  if (is.null(vx)) return(FALSE)
  vv <- try(.wb_plot_resolve_primitive(bundle, vx, runs = runs), silent = TRUE)
  if (inherits(vv, "try-error") || !.wb_is_primitive(vv) || !(vv$kind %in% c("cell_vector", "cell_vector_family"))) {
    return(FALSE)
  }
  vdf <- try(.wb_plot_resolve_vector_df(bundle, vv, key = inputs$value_key %||% inputs$key %||% NULL), silent = TRUE)
  if (inherits(vdf, "try-error") || !is.data.frame(vdf) || !nrow(vdf)) return(FALSE)
  vtype <- unique(as.character(vdf$value_type %||% ""))
  vtype <- vtype[nzchar(vtype)]
  isTRUE(length(vtype) > 0 && all(vtype == "categorical"))
}

.wb_plot_mapper_category_count_bar_map <- function(bundle, inputs, runs, version) {
  vx <- .wb_plot_input_first(inputs, c("vector", "value", "value_ref", "cell_vector"))
  vprim <- .wb_plot_resolve_primitive(bundle, vx, runs = runs)
  vdf <- .wb_plot_resolve_vector_df(bundle, vprim, key = inputs$value_key %||% inputs$key %||% NULL)
  vtype <- unique(as.character(vdf$value_type %||% ""))
  vtype <- vtype[nzchar(vtype)]
  .wb_assert(length(vtype) > 0 && all(vtype == "categorical"),
             "category_count_bar mapping requires a categorical cell vector.")

  cats <- as.character(vdf$value)
  cats[is.na(cats) | !nzchar(cats)] <- "NA"
  tab <- sort(table(cats), decreasing = TRUE)
  total_n <- sum(as.numeric(tab))

  out <- data.frame(
    category = as.character(names(tab)),
    count = as.numeric(tab),
    stringsAsFactors = FALSE
  )
  out$pct <- if (is.finite(total_n) && total_n > 0) out$count / total_n else NA_real_
  out$rank <- seq_len(nrow(out))
  out$label <- out$category
  rownames(out) <- NULL

  list(
    plot_type = "category_count_bar",
    dataset_type = "category_summary",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("category_count_bar", version = version),
    meta = list(
      n_rows = nrow(out),
      n_total = as.integer(total_n),
      vector_kind = as.character(vprim$kind %||% "")
    )
  )
}

.wb_plot_mapper_dotplot_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "markers_table", "de_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  # Pathway-enrich tables are a valid dotplot source:
  # pathway -> feature_id, overlap/query_size -> pct_expr, enrichment_ratio -> avg_expr.
  if (!("feature_id" %in% colnames(tbl)) && ("pathway" %in% colnames(tbl))) {
    tbl$feature_id <- as.character(tbl$pathway)
  }
  .wb_assert("feature_id" %in% colnames(tbl), "dotplot mapping requires feature_id/pathway column")

  group_candidates <- unique(c(as.character(inputs$group_col %||% ""), "cluster", "group", "cell_group"))
  group_candidates <- group_candidates[nzchar(group_candidates)]
  group_col <- intersect(group_candidates, colnames(tbl))[1] %||% NA_character_
  if (is.na(group_col) || !nzchar(group_col)) {
    # Fallback: single-group dotplot for pathway/summary tables
    if ("namespace" %in% colnames(tbl)) {
      tbl$.group_dotplot <- as.character(tbl$namespace)
    } else if ("matrix_id" %in% colnames(tbl)) {
      tbl$.group_dotplot <- as.character(tbl$matrix_id)
    } else {
      tbl$.group_dotplot <- "all"
    }
    group_col <- ".group_dotplot"
  }

  pct_candidates <- unique(c(as.character(inputs$pct_col %||% ""), "pct_expr", "pct_a", "percent_expr", "pct"))
  pct_candidates <- pct_candidates[nzchar(pct_candidates)]
  pct_col <- intersect(pct_candidates, colnames(tbl))[1] %||% NA_character_
  if (is.na(pct_col) || !nzchar(pct_col)) {
    if (all(c("overlap", "query_size") %in% colnames(tbl))) {
      q <- suppressWarnings(as.numeric(tbl$query_size))
      o <- suppressWarnings(as.numeric(tbl$overlap))
      tbl$.pct_dotplot <- ifelse(is.finite(q) & q > 0, o / q, NA_real_)
      pct_col <- ".pct_dotplot"
    } else if ("overlap" %in% colnames(tbl)) {
      tbl$.pct_dotplot <- suppressWarnings(as.numeric(tbl$overlap))
      pct_col <- ".pct_dotplot"
    }
  }
  .wb_assert(!is.na(pct_col) && nzchar(pct_col), "Could not infer pct_expr/overlap column for dotplot")

  avg_candidates <- unique(c(as.character(inputs$avg_col %||% ""), "avg_expr", "avg_expr_a", "mean_expr", "avg"))
  avg_candidates <- avg_candidates[nzchar(avg_candidates)]
  avg_col <- intersect(avg_candidates, colnames(tbl))[1] %||% NA_character_
  if (is.na(avg_col) || !nzchar(avg_col)) {
    if ("enrichment_ratio" %in% colnames(tbl)) {
      tbl$.avg_dotplot <- suppressWarnings(as.numeric(tbl$enrichment_ratio))
      avg_col <- ".avg_dotplot"
    }
  }
  .wb_assert(!is.na(avg_col) && nzchar(avg_col), "Could not infer avg_expr/enrichment column for dotplot")

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

.wb_plot_mapper_pathway_bar_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "pathway_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !(tt$kind %in% c("feature_table", "obs_table"))) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl)) return(FALSE)
  has_path <- "pathway" %in% colnames(tbl) || "feature_id" %in% colnames(tbl)
  has_padj <- any(c("p_val_adj", "padj", "p_adj", "q_value", "fdr") %in% colnames(tbl))
  isTRUE(has_path && has_padj)
}

.wb_plot_mapper_pathway_bar_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "pathway_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs)
  .wb_assert(.wb_is_primitive(tprim) && (tprim$kind %in% c("feature_table", "obs_table")),
             "pathway_bar requires feature_table or obs_table input")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  pathway_col <- if ("pathway" %in% colnames(tbl)) "pathway" else if ("feature_id" %in% colnames(tbl)) "feature_id" else NA_character_
  .wb_assert(!is.na(pathway_col) && nzchar(pathway_col), "Could not infer pathway column for pathway_bar")

  padj_candidates <- unique(c(as.character(inputs$p_adj_col %||% ""), "p_val_adj", "padj", "p_adj", "q_value", "fdr"))
  padj_candidates <- padj_candidates[nzchar(padj_candidates)]
  p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(p_adj_col) && nzchar(p_adj_col), "Could not infer adjusted p-value column for pathway_bar")

  p_adj_thresh <- suppressWarnings(as.numeric(inputs$p_adj_thresh %||% 0.05))
  if (!is.finite(p_adj_thresh)) p_adj_thresh <- 0.05

  out <- data.frame(
    pathway = as.character(tbl[[pathway_col]]),
    p_adj = suppressWarnings(as.numeric(tbl[[p_adj_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[!is.na(out$p_adj) & nzchar(out$pathway), , drop = FALSE]

  if ("enrichment_ratio" %in% colnames(tbl)) out$score <- suppressWarnings(as.numeric(tbl$enrichment_ratio))
  if ("overlap" %in% colnames(tbl)) out$overlap <- suppressWarnings(as.numeric(tbl$overlap))
  if ("set_size" %in% colnames(tbl)) out$set_size <- suppressWarnings(as.numeric(tbl$set_size))
  if ("query_size" %in% colnames(tbl)) out$query_size <- suppressWarnings(as.numeric(tbl$query_size))
  if ("namespace" %in% colnames(tbl)) out$namespace <- as.character(tbl$namespace)

  out$significant <- out$p_adj <= p_adj_thresh
  ord <- order(out$p_adj, decreasing = FALSE, na.last = TRUE)
  out$rank <- NA_real_
  out$rank[ord] <- seq_along(ord)
  out$label <- out$pathway
  rownames(out) <- NULL

  list(
    plot_type = "pathway_bar",
    dataset_type = "pathway_summary",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("pathway_bar", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_pathway_col = pathway_col,
      source_p_adj_col = p_adj_col,
      p_adj_thresh = p_adj_thresh,
      n_rows = nrow(out)
    )
  )
}

.wb_plot_mapper_ranked_lollipop_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "trend_table", "pathway_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !(tt$kind %in% c("feature_table", "obs_table"))) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl)) return(FALSE)
  if (identical(tt$kind, "obs_table")) {
    id_candidates <- c("feature_id", "feature_set", "group", "cluster", "label", "entity_id")
    score_candidates <- c(
      as.character(inputs$score_col %||% ""),
      "dynamic_score", "amplitude", "mean", "median", "score", "value", "sd", "n"
    )
    id_col <- intersect(id_candidates, colnames(tbl))[1] %||% NA_character_
    score_col <- intersect(score_candidates[nzchar(score_candidates)], colnames(tbl))[1] %||% NA_character_
    if (is.na(id_col) || is.na(score_col)) return(FALSE)
    vv <- suppressWarnings(as.numeric(tbl[[score_col]]))
    return(any(is.finite(vv)))
  }
  has_id <- "feature_id" %in% colnames(tbl) || "pathway" %in% colnames(tbl)
  score_candidates <- c(
    as.character(inputs$score_col %||% ""),
    "score", "avg_log1p_fc", "avg_log2FC", "log2FC", "logFC", "effect", "estimate", "rho", "enrichment_ratio", "overlap"
  )
  has_score <- any(score_candidates %in% colnames(tbl))
  isTRUE(has_id && has_score)
}

.wb_plot_mapper_ranked_lollipop_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "trend_table", "pathway_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs)
  .wb_assert(.wb_is_primitive(tprim) && (tprim$kind %in% c("feature_table", "obs_table")),
             "ranked_lollipop requires feature_table or obs_table input")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)
  source_id_col <- NA_character_
  source_score_col <- NA_character_
  p_adj_col <- NA_character_
  p_raw_col <- NA_character_

  if (identical(tprim$kind, "obs_table")) {
    id_candidates <- c("feature_id", "feature_set", "group", "cluster", "label", "entity_id")
    id_col <- intersect(id_candidates, colnames(tbl))[1] %||% NA_character_
    .wb_assert(!is.na(id_col) && nzchar(id_col), "Could not infer group/label column for ranked_lollipop obs_table mapping")

    score_candidates <- unique(c(
      as.character(inputs$score_col %||% ""),
      "dynamic_score", "amplitude", "mean", "median", "score", "value", "sd", "n"
    ))
    score_candidates <- score_candidates[nzchar(score_candidates)]
    score_col <- intersect(score_candidates, colnames(tbl))[1] %||% NA_character_
    .wb_assert(!is.na(score_col) && nzchar(score_col), "Could not infer score column for ranked_lollipop obs_table mapping")

    out <- data.frame(
      feature_id = as.character(tbl[[id_col]]),
      score = suppressWarnings(as.numeric(tbl[[score_col]])),
      stringsAsFactors = FALSE
    )
    source_id_col <- id_col
    source_score_col <- score_col
  } else {
    if (!("feature_id" %in% colnames(tbl)) && ("pathway" %in% colnames(tbl))) {
      tbl$feature_id <- as.character(tbl$pathway)
    }
    .wb_assert("feature_id" %in% colnames(tbl), "ranked_lollipop mapping requires feature_id/pathway column")

    score_candidates <- unique(c(
      as.character(inputs$score_col %||% ""),
      "score", "avg_log1p_fc", "avg_log2FC", "log2FC", "logFC",
      "effect", "estimate", "rho", "enrichment_ratio", "overlap"
    ))
    score_candidates <- score_candidates[nzchar(score_candidates)]
    score_col <- intersect(score_candidates, colnames(tbl))[1] %||% NA_character_
    .wb_assert(!is.na(score_col) && nzchar(score_col), "Could not infer score column for ranked_lollipop")

    out <- data.frame(
      feature_id = as.character(tbl$feature_id),
      score = suppressWarnings(as.numeric(tbl[[score_col]])),
      stringsAsFactors = FALSE
    )
    source_id_col <- "feature_id"
    source_score_col <- score_col

    padj_candidates <- c("p_val_adj", "padj", "p_adj", "q_value", "fdr")
    p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
    if (!is.na(p_adj_col) && nzchar(p_adj_col)) out$p_adj <- suppressWarnings(as.numeric(tbl[[p_adj_col]]))

    praw_candidates <- c("p_val", "pvalue", "p_value")
    p_raw_col <- intersect(praw_candidates, colnames(tbl))[1] %||% NA_character_
    if (!is.na(p_raw_col) && nzchar(p_raw_col)) out$p_raw <- suppressWarnings(as.numeric(tbl[[p_raw_col]]))
  }

  p_adj_thresh <- suppressWarnings(as.numeric(inputs$p_adj_thresh %||% 0.05))
  if (!is.finite(p_adj_thresh)) p_adj_thresh <- 0.05
  out$significant <- if ("p_adj" %in% names(out)) (!is.na(out$p_adj) & out$p_adj <= p_adj_thresh) else TRUE
  out$direction <- ifelse(out$score > 0, "up", ifelse(out$score < 0, "down", "flat"))
  out <- out[is.finite(out$score) & nzchar(out$feature_id), , drop = FALSE]

  ord <- order(abs(out$score), decreasing = TRUE, na.last = TRUE)
  out <- out[ord, , drop = FALSE]
  out$rank <- seq_len(nrow(out))
  out$label <- out$feature_id
  rownames(out) <- NULL

  list(
    plot_type = "ranked_lollipop",
    dataset_type = "ranked_entities",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("ranked_lollipop", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_id_col = source_id_col,
      source_score_col = source_score_col,
      source_p_adj_col = p_adj_col,
      source_p_raw_col = p_raw_col,
      p_adj_thresh = p_adj_thresh,
      n_rows = nrow(out)
    )
  )
}

.wb_plot_mapper_heatmap_ranked_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "markers_table", "pathway_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "feature_table")) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl)) return(FALSE)
  has_id <- "feature_id" %in% colnames(tbl) || "pathway" %in% colnames(tbl)
  has_val <- any(c("avg_expr", "avg_expr_a", "avg_log1p_fc", "enrichment_ratio", "rho", "score", "overlap") %in% colnames(tbl))
  isTRUE(has_id && has_val)
}

.wb_plot_mapper_heatmap_ranked_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "markers_table", "pathway_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  if (!("feature_id" %in% colnames(tbl)) && ("pathway" %in% colnames(tbl))) {
    tbl$feature_id <- as.character(tbl$pathway)
  }
  .wb_assert("feature_id" %in% colnames(tbl), "heatmap_ranked mapping requires feature_id/pathway column")

  group_candidates <- unique(c(as.character(inputs$group_col %||% ""), "group", "cluster", "namespace", "matrix_id", "direction"))
  group_candidates <- group_candidates[nzchar(group_candidates)]
  group_col <- intersect(group_candidates, colnames(tbl))[1] %||% NA_character_
  if (is.na(group_col) || !nzchar(group_col)) {
    tbl$.group_heatmap <- "all"
    group_col <- ".group_heatmap"
  }

  val_candidates <- unique(c(
    as.character(inputs$value_col %||% ""),
    "avg_expr", "avg_expr_a", "avg_log1p_fc", "enrichment_ratio",
    "rho", "score", "overlap", "pct_expr", "p_val_adj"
  ))
  val_candidates <- val_candidates[nzchar(val_candidates)]
  value_col <- intersect(val_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(value_col) && nzchar(value_col), "Could not infer value column for heatmap_ranked")

  out <- data.frame(
    feature_id = as.character(tbl$feature_id),
    group = as.character(tbl[[group_col]]),
    value = suppressWarnings(as.numeric(tbl[[value_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[nzchar(out$feature_id) & nzchar(out$group) & is.finite(out$value), , drop = FALSE]
  .wb_assert(nrow(out) > 0, "heatmap_ranked mapping yielded no finite rows")

  if ("rank" %in% colnames(tbl)) out$rank <- suppressWarnings(as.numeric(tbl$rank))
  if ("direction" %in% colnames(tbl)) out$direction <- as.character(tbl$direction)
  if ("significant" %in% colnames(tbl)) out$significant <- as.logical(tbl$significant)
  out$label <- out$feature_id

  rownames(out) <- NULL
  list(
    plot_type = "heatmap_ranked",
    dataset_type = "matrix_like",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("heatmap_ranked", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_group_col = group_col,
      source_value_col = value_col,
      n_rows = nrow(out)
    )
  )
}

.wb_plot_mapper_feature_rank_bar_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "markers_table", "pathway_table"))
  if (is.null(tx)) return(FALSE)
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "feature_table")) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl)) return(FALSE)
  has_id <- "feature_id" %in% colnames(tbl) || "pathway" %in% colnames(tbl)
  has_val <- any(c("value", "score", "avg_log1p_fc", "avg_log2FC", "log2FC", "logFC", "effect", "estimate", "rho", "enrichment_ratio", "overlap", "avg_expr", "avg_expr_a", "pct_expr", "p_val_adj") %in% colnames(tbl))
  isTRUE(has_id && has_val)
}

.wb_plot_mapper_feature_rank_bar_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "markers_table", "pathway_table"))
  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)

  if (!("feature_id" %in% colnames(tbl)) && ("pathway" %in% colnames(tbl))) {
    tbl$feature_id <- as.character(tbl$pathway)
  }
  .wb_assert("feature_id" %in% colnames(tbl), "feature_rank_bar mapping requires feature_id/pathway column")

  value_candidates <- unique(c(
    as.character(inputs$value_col %||% ""),
    "value", "score", "avg_log1p_fc", "avg_log2FC", "log2FC", "logFC",
    "effect", "estimate", "rho", "enrichment_ratio", "overlap",
    "avg_expr", "avg_expr_a", "pct_expr", "p_val_adj"
  ))
  value_candidates <- value_candidates[nzchar(value_candidates)]
  value_col <- intersect(value_candidates, colnames(tbl))[1] %||% NA_character_
  .wb_assert(!is.na(value_col) && nzchar(value_col), "Could not infer value column for feature_rank_bar")

  out <- data.frame(
    feature_id = as.character(tbl$feature_id),
    value = suppressWarnings(as.numeric(tbl[[value_col]])),
    stringsAsFactors = FALSE
  )
  out <- out[nzchar(out$feature_id) & is.finite(out$value), , drop = FALSE]

  if ("rank" %in% colnames(tbl)) out$rank <- suppressWarnings(as.numeric(tbl$rank))
  if ("direction" %in% colnames(tbl)) out$direction <- as.character(tbl$direction)
  if ("significant" %in% colnames(tbl)) out$significant <- as.logical(tbl$significant)
  out$label <- out$feature_id

  padj_candidates <- c("p_val_adj", "padj", "p_adj", "q_value", "fdr")
  p_adj_col <- intersect(padj_candidates, colnames(tbl))[1] %||% NA_character_
  if (!is.na(p_adj_col) && nzchar(p_adj_col)) out$p_adj <- suppressWarnings(as.numeric(tbl[[p_adj_col]]))

  praw_candidates <- c("p_val", "pvalue", "p_value")
  p_raw_col <- intersect(praw_candidates, colnames(tbl))[1] %||% NA_character_
  if (!is.na(p_raw_col) && nzchar(p_raw_col)) out$p_raw <- suppressWarnings(as.numeric(tbl[[p_raw_col]]))

  p_adj_thresh <- suppressWarnings(as.numeric(inputs$p_adj_thresh %||% NA_real_))
  if (is.finite(p_adj_thresh) && ("p_adj" %in% names(out))) {
    out <- out[!is.na(out$p_adj) & out$p_adj <= p_adj_thresh, , drop = FALSE]
  }

  top_n <- suppressWarnings(as.integer(inputs$top_n %||% 50L))
  if (!is.finite(top_n) || top_n < 0L) top_n <- 50L
  order_mode <- as.character(inputs$order_mode %||% "abs_desc")[1]
  ord <- switch(
    order_mode,
    desc = order(out$value, decreasing = TRUE, na.last = TRUE),
    asc = order(out$value, decreasing = FALSE, na.last = TRUE),
    abs_desc = order(abs(out$value), decreasing = TRUE, na.last = TRUE)
  )
  if (is.null(ord)) ord <- order(abs(out$value), decreasing = TRUE, na.last = TRUE)
  out <- out[ord, , drop = FALSE]
  if (top_n > 0L && nrow(out) > top_n) out <- out[seq_len(top_n), , drop = FALSE]
  out$rank <- seq_len(nrow(out))
  rownames(out) <- NULL

  list(
    plot_type = "feature_rank_bar",
    dataset_type = "ranked_features",
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("feature_rank_bar", version = version),
    meta = list(
      table_type = as.character(tprim$table_type %||% "generic"),
      source_value_col = value_col,
      source_p_adj_col = p_adj_col,
      source_p_raw_col = p_raw_col,
      p_adj_thresh = p_adj_thresh,
      top_n = top_n,
      order_mode = order_mode,
      n_rows = nrow(out)
    )
  )
}

.wb_plot_resolve_matrix_id <- function(bundle, inputs, runs = NULL) {
  mx <- .wb_plot_input_first(inputs, c("matrix", "matrix_ref", "matrix_id"))
  if (!is.null(mx)) {
    if (.wb_is_primitive(mx)) {
      .wb_assert(identical(as.character(mx$kind %||% "")[1], "matrix"),
                 "pseudotime_smooth_panel matrix input must be kind='matrix'.")
      return(as.character(mx$matrix_id %||% "")[1])
    }
    if (is.character(mx) && length(mx) == 1L && nzchar(mx)) return(as.character(mx)[1])

    mprim <- .wb_plot_resolve_primitive(bundle, mx, runs = runs, expected_kind = "matrix")
    .wb_assert(.wb_is_primitive(mprim) && identical(as.character(mprim$kind %||% "")[1], "matrix"),
               "pseudotime_smooth_panel matrix input could not be resolved to matrix primitive.")
    return(as.character(mprim$matrix_id %||% "")[1])
  }

  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "trend_table"))
  if (!is.null(tx)) {
    aid <- .wb_plot_ref_artifact_id(tx)
    if (nzchar(aid)) {
      mid_bc <- try({
        bc <- wb_art_birth_certificate(
          bundle,
          artifact_id = aid,
          include_parents = FALSE,
          include_children = FALSE,
          include_snapshot_run = FALSE
        )
        as.character(bc$identity$input_matrix_id %||% "")[1]
      }, silent = TRUE)
      if (!inherits(mid_bc, "try-error") && nzchar(as.character(mid_bc)[1])) return(as.character(mid_bc)[1])
    }

    tprim <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table"), silent = TRUE)
    if (!inherits(tprim, "try-error") && .wb_is_primitive(tprim)) {
      mid <- as.character(tprim$meta$matrix_id %||% "")[1]
      if (nzchar(mid)) return(mid)
      tbl <- try(wb_primitive_to_table(tprim, include_context = FALSE), silent = TRUE)
      if (!inherits(tbl, "try-error") && is.data.frame(tbl) && ("matrix_id" %in% colnames(tbl))) {
        mids <- unique(as.character(tbl$matrix_id))
        mids <- mids[nzchar(mids)]
        if (length(mids)) return(mids[1])
      }
    }
  }

  mm <- try(wb_matrices(bundle), silent = TRUE)
  if (!inherits(mm, "try-error") && is.data.frame(mm) && nrow(mm)) {
    mid <- as.character(mm$matrix_id[1] %||% "")[1]
    if (nzchar(mid)) return(mid)
  }

  stop("pseudotime_smooth_panel could not infer matrix_id from inputs/table metadata.", call. = FALSE)
}

.wb_plot_resolve_features_for_pseudotime <- function(bundle, inputs, runs, lineage_key) {
  feats <- as.character(inputs$features %||% character(0))
  feats <- unique(feats[nzchar(feats)])
  if (length(feats)) return(feats)

  tx <- .wb_plot_input_first(inputs, c("table", "feature_table", "de_table", "trend_table"))
  .wb_assert(!is.null(tx), "pseudotime_smooth_panel requires features or table input.")

  tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "feature_table")
  tbl <- wb_primitive_to_table(tprim, include_context = FALSE)
  .wb_assert("feature_id" %in% colnames(tbl), "pseudotime_smooth_panel table input requires feature_id column.")

  if (!is.null(lineage_key) && "lineage_id" %in% colnames(tbl)) {
    kk <- as.character(lineage_key)[1]
    tbl <- tbl[as.character(tbl$lineage_id) == kk, , drop = FALSE]
  }
  .wb_assert(nrow(tbl) > 0, "pseudotime_smooth_panel table has no rows after lineage filter.")

  top_n <- suppressWarnings(as.integer(inputs$top_n_features %||% 12L))
  if (!is.finite(top_n) || top_n <= 0L) top_n <- 12L

  score <- rep(NA_real_, nrow(tbl))
  if ("p_val_adj" %in% colnames(tbl)) {
    p <- suppressWarnings(as.numeric(tbl$p_val_adj))
    score <- -log10(pmax(p, 1e-300))
  } else if ("p_val" %in% colnames(tbl)) {
    p <- suppressWarnings(as.numeric(tbl$p_val))
    score <- -log10(pmax(p, 1e-300))
  }
  if ("rho" %in% colnames(tbl)) {
    rr <- suppressWarnings(as.numeric(tbl$rho))
    ifelse(is.finite(score), score <- score + abs(rr), score <- abs(rr))
  }
  if (all(!is.finite(score)) && "abs_rho" %in% colnames(tbl)) score <- suppressWarnings(as.numeric(tbl$abs_rho))
  if (all(!is.finite(score)) && "rank" %in% colnames(tbl)) {
    rr <- suppressWarnings(as.numeric(tbl$rank))
    score <- ifelse(is.finite(rr), -rr, NA_real_)
  }
  if (all(!is.finite(score))) score <- seq_len(nrow(tbl))

  ord <- order(score, decreasing = TRUE, na.last = TRUE)
  tbl <- tbl[ord, , drop = FALSE]
  feats <- unique(as.character(tbl$feature_id))
  feats <- feats[nzchar(feats)]
  if (length(feats) > top_n) feats <- feats[seq_len(top_n)]
  .wb_assert(length(feats) > 0, "pseudotime_smooth_panel could not select features.")
  feats
}

.wb_plot_pick_matrix_features <- function(bundle, matrix_id, features) {
  feats <- unique(as.character(features %||% character(0)))
  feats <- feats[nzchar(feats)]
  .wb_assert(length(feats) > 0, "pseudotime_smooth_panel could not select features.")

  mids <- try(as.character(wb_matrices(bundle)$matrix_id), silent = TRUE)
  if (inherits(mids, "try-error")) mids <- character(0)
  mids <- unique(c(as.character(matrix_id %||% "")[1], mids))
  mids <- mids[nzchar(mids)]
  .wb_assert(length(mids) > 0, "pseudotime_smooth_panel could not enumerate bundle matrices.")

  best_mid <- NA_character_
  best_overlap <- -1L
  best_feats <- character(0)
  for (mid in mids) {
    fmid <- try(as.character(wb_feature_ids(bundle, matrix_id = mid)), silent = TRUE)
    if (inherits(fmid, "try-error")) next
    fmid <- fmid[nzchar(fmid)]
    if (!length(fmid)) next
    keep <- intersect(feats, fmid)
    n_keep <- length(keep)
    if (n_keep > best_overlap) {
      best_overlap <- n_keep
      best_mid <- mid
      best_feats <- keep
      if (n_keep == length(feats)) break
    }
  }

  .wb_assert(is.finite(best_overlap) && best_overlap > 0L,
             "pseudotime_smooth_panel could not match selected features to any matrix in bundle.")
  list(matrix_id = as.character(best_mid)[1], features = as.character(best_feats))
}

.wb_plot_mapper_pseudotime_smooth_panel_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "trend_table", "obs_table"))
  if (is.null(tx)) return(FALSE)
  if (is.character(tx) && length(tx) == 1L && startsWith(tx, "artifact:")) {
    aid <- sub("^artifact:", "", tx)
    info <- try(wb_art_table_info(bundle, aid), silent = TRUE)
    return(!inherits(info, "try-error") &&
             identical(as.character(info$type[1] %||% "")[1], "obs_table") &&
             as.character(info$table_type[1] %||% "")[1] %in% c("trajectory_smooth", "trajectory_route_smooth"))
  }
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "obs_table")) return(FALSE)
  if (!(as.character(tt$table_type %||% "")[1] %in% c("trajectory_smooth", "trajectory_route_smooth"))) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl) || !nrow(tbl)) return(FALSE)
  all(c("feature_id", "pseudotime", "expr") %in% colnames(tbl))
}

.wb_plot_mapper_pseudotime_smooth_panel_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "trend_table", "obs_table"))
  lineage <- as.character(inputs$lineage %||% inputs$lineages %||% character(0))
  lineage <- lineage[!is.na(lineage) & nzchar(lineage)]
  feats <- as.character(inputs$features %||% inputs$feature_ids %||% character(0))
  feats <- feats[!is.na(feats) & nzchar(feats)]
  top_n <- suppressWarnings(as.integer(inputs$top_n_features %||% NA_integer_))
  meta_src <- list()

  if (is.character(tx) && length(tx) == 1L && startsWith(tx, "artifact:")) {
    aid <- sub("^artifact:", "", tx)
    info <- wb_art_table_info(bundle, aid)
    table_type <- as.character(info$table_type[1] %||% "")[1]
    key_col <- if (identical(table_type, "trajectory_route_smooth")) "route_key" else "lineage_id"
    .wb_assert(identical(as.character(info$type[1] %||% "")[1], "obs_table") &&
                 table_type %in% c("trajectory_smooth", "trajectory_route_smooth"),
               "pseudotime_smooth_panel requires obs_table(table_type='trajectory_smooth' or 'trajectory_route_smooth').")
    if (!length(feats) && is.finite(top_n) && top_n > 0L) {
      ov <- try(wb_art_trajectory_smooth_overview(bundle, aid), silent = TRUE)
      if (!inherits(ov, "try-error")) {
        feats <- as.character(utils::head(ov$feature_ids %||% character(0), top_n))
      }
      if (!length(feats)) {
        feats <- wb_art_table_distinct(
          bundle,
          aid,
          "feature_id",
          filters = if (length(lineage)) stats::setNames(list(lineage), key_col) else NULL,
          limit = top_n
        )
      }
    }
    filters <- list()
    if (length(lineage)) filters[[key_col]] <- lineage
    if (length(feats)) filters$feature_id <- feats
    tbl <- wb_art_table_slice(bundle, aid, filters = filters)
    meta_src <- list(
      artifact_id = aid,
      sliced = TRUE,
      selected_lineages = lineage,
      selected_features = feats
    )
  } else {
    tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table")
    table_type <- as.character(tprim$table_type %||% "")[1]
    .wb_assert(table_type %in% c("trajectory_smooth", "trajectory_route_smooth"),
               "pseudotime_smooth_panel requires obs_table(table_type='trajectory_smooth' or 'trajectory_route_smooth').")
    tbl <- wb_primitive_to_table(tprim, include_context = FALSE)
    key_col <- if ("lineage_id" %in% colnames(tbl)) "lineage_id" else if ("route_key" %in% colnames(tbl)) "route_key" else ""
    if (length(lineage) && nzchar(key_col)) {
      tbl <- tbl[as.character(tbl[[key_col]]) %in% lineage, , drop = FALSE]
    }
    if (length(feats) && "feature_id" %in% colnames(tbl)) {
      tbl <- tbl[as.character(tbl$feature_id) %in% feats, , drop = FALSE]
    } else if (is.finite(top_n) && top_n > 0L && "feature_id" %in% colnames(tbl)) {
      keep <- unique(as.character(tbl$feature_id))
      keep <- utils::head(keep[nzchar(keep)], top_n)
      tbl <- tbl[as.character(tbl$feature_id) %in% keep, , drop = FALSE]
    }
    meta_src <- tprim$meta %||% list()
  }
  .wb_assert(all(c("feature_id", "pseudotime", "expr") %in% colnames(tbl)),
             "pseudotime_smooth_panel table requires feature_id, pseudotime, expr columns.")
  if (!("lineage_id" %in% colnames(tbl)) && "route_key" %in% colnames(tbl)) {
    tbl$lineage_id <- as.character(tbl$route_key)
  }
  out <- tbl[, intersect(c("feature_id", "lineage_id", "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "expr", "n_cells", "label"), colnames(tbl)), drop = FALSE]
  out <- out[is.finite(suppressWarnings(as.numeric(out$pseudotime))) & is.finite(suppressWarnings(as.numeric(out$expr))), , drop = FALSE]
  rownames(out) <- NULL

  list(
    plot_type = "pseudotime_smooth_panel",
    dataset_type = as.character(if ("route_key" %in% colnames(tbl)) "trajectory_route_smooth" else "trajectory_smooth"),
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("pseudotime_smooth_panel", version = version),
    meta = utils::modifyList(
      list(
        n_features = length(unique(as.character(out$feature_id))),
        n_rows = nrow(out)
      ),
      meta_src
    )
  )
}

.wb_plot_mapper_pseudotime_signature_line_can <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "signature_table", "obs_table"))
  if (is.null(tx)) return(FALSE)
  if (is.character(tx) && length(tx) == 1L && startsWith(tx, "artifact:")) {
    aid <- sub("^artifact:", "", tx)
    info <- try(wb_art_table_info(bundle, aid), silent = TRUE)
    return(!inherits(info, "try-error") &&
             identical(as.character(info$type[1] %||% "")[1], "obs_table") &&
             as.character(info$table_type[1] %||% "")[1] %in% c(
               "trajectory_signature_smooth",
               "trajectory_geneset_dynamics_curve",
               "trajectory_geneset_dynamics_driver_curve",
               "trajectory_signal_dynamics_curve"
             ))
  }
  tt <- try(.wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table"), silent = TRUE)
  if (inherits(tt, "try-error") || !.wb_is_primitive(tt) || !identical(tt$kind, "obs_table")) return(FALSE)
  if (!(as.character(tt$table_type %||% "")[1] %in% c(
    "trajectory_signature_smooth",
    "trajectory_geneset_dynamics_curve",
    "trajectory_geneset_dynamics_driver_curve",
    "trajectory_signal_dynamics_curve"
  ))) return(FALSE)
  tbl <- try(wb_primitive_to_table(tt, include_context = FALSE), silent = TRUE)
  if (inherits(tbl, "try-error") || !is.data.frame(tbl) || !nrow(tbl)) return(FALSE)
  all(c("feature_set", "pseudotime", "value") %in% colnames(tbl))
}

.wb_plot_mapper_pseudotime_signature_line_map <- function(bundle, inputs, runs, version) {
  tx <- .wb_plot_input_first(inputs, c("table", "signature_table", "obs_table"))
  feature_sets <- as.character(inputs$feature_sets %||% inputs$feature_set %||% character(0))
  feature_sets <- feature_sets[!is.na(feature_sets) & nzchar(feature_sets)]
  feature_ids <- as.character(inputs$features %||% inputs$feature_ids %||% character(0))
  feature_ids <- feature_ids[!is.na(feature_ids) & nzchar(feature_ids)]
  lineage <- as.character(inputs$lineage %||% inputs$lineages %||% character(0))
  lineage <- lineage[!is.na(lineage) & nzchar(lineage)]
  top_n <- suppressWarnings(as.integer(inputs$top_n_feature_sets %||% inputs$top_n %||% NA_integer_))
  meta_src <- list()

  if (is.character(tx) && length(tx) == 1L && startsWith(tx, "artifact:")) {
    aid <- sub("^artifact:", "", tx)
    info <- wb_art_table_info(bundle, aid)
    table_type <- as.character(info$table_type[1] %||% "")[1]
    .wb_assert(identical(as.character(info$type[1] %||% "")[1], "obs_table") &&
                 table_type %in% c("trajectory_signature_smooth", "trajectory_geneset_dynamics_curve", "trajectory_geneset_dynamics_driver_curve", "trajectory_signal_dynamics_curve"),
               "pseudotime_signature_line requires a trajectory signature/gene-set curve obs_table.")
    filters <- list()
    if (length(feature_sets)) filters$feature_set <- feature_sets
    if (length(feature_ids)) filters$feature_id <- feature_ids
    if (length(lineage)) filters$lineage_id <- lineage
    tbl <- wb_art_table_slice(bundle, aid, filters = filters)
    meta_src <- list(artifact_id = aid, sliced = TRUE)
  } else {
    tprim <- .wb_plot_resolve_primitive(bundle, tx, runs = runs, expected_kind = "obs_table")
    table_type <- as.character(tprim$table_type %||% "")[1]
    .wb_assert(table_type %in% c("trajectory_signature_smooth", "trajectory_geneset_dynamics_curve", "trajectory_geneset_dynamics_driver_curve", "trajectory_signal_dynamics_curve"),
               "pseudotime_signature_line requires trajectory signature/gene-set curve obs_table.")
    tbl <- wb_primitive_to_table(tprim, include_context = FALSE)
    meta_src <- tprim$meta %||% list()
    if (length(feature_sets) && "feature_set" %in% colnames(tbl)) {
      tbl <- tbl[as.character(tbl$feature_set) %in% feature_sets, , drop = FALSE]
    }
    if (length(feature_ids) && "feature_id" %in% colnames(tbl)) {
      tbl <- tbl[as.character(tbl$feature_id) %in% feature_ids, , drop = FALSE]
    }
    if (length(lineage) && "lineage_id" %in% colnames(tbl)) {
      tbl <- tbl[as.character(tbl$lineage_id) %in% lineage, , drop = FALSE]
    }
  }
  .wb_assert(all(c("feature_set", "pseudotime", "value") %in% colnames(tbl)),
             "pseudotime_signature_line table requires feature_set, pseudotime, value columns.")
  if (!length(feature_sets) && is.finite(top_n) && top_n > 0L && "feature_set" %in% colnames(tbl)) {
    keep <- unique(as.character(tbl$feature_set))
    keep <- utils::head(keep[nzchar(keep)], top_n)
    tbl <- tbl[as.character(tbl$feature_set) %in% keep, , drop = FALSE]
  }
  out <- tbl[, intersect(c("feature_set", "signal_key", "feature_id", "driver_rank", "lineage_id", "bin",
                           "pseudotime", "pseudotime_min", "pseudotime_max", "value",
                           "value_raw", "value_smooth", "value_se", "value_ci_low",
                           "value_ci_high", "n_cells", "label"), colnames(tbl)), drop = FALSE]
  for (nm in intersect(c("bin", "pseudotime", "pseudotime_min", "pseudotime_max",
                         "value", "value_raw", "value_smooth", "value_se", "value_ci_low",
                         "value_ci_high"), colnames(out))) {
    out[[nm]] <- suppressWarnings(as.numeric(out[[nm]]))
  }
  for (nm in intersect(c("driver_rank", "n_cells"), colnames(out))) {
    out[[nm]] <- suppressWarnings(as.integer(out[[nm]]))
  }
  out <- out[is.finite(suppressWarnings(as.numeric(out$pseudotime))) & is.finite(suppressWarnings(as.numeric(out$value))), , drop = FALSE]
  rownames(out) <- NULL
  dataset_type <- table_type %||% "trajectory_signature_smooth"

  list(
    plot_type = "pseudotime_signature_line",
    dataset_type = as.character(dataset_type)[1],
    contract_version = as.character(version)[1],
    table = out,
    schema = wb_plot_contract("pseudotime_signature_line", version = version),
    meta = utils::modifyList(
      list(
        n_feature_sets = length(unique(as.character(out$feature_set))),
        n_rows = nrow(out)
      ),
      meta_src
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
    plot_type = "trend_scatter",
    mapper_id = "feature_table_trend_scatter_v1",
    can_map = .wb_plot_mapper_trend_scatter_can,
    map_fn = .wb_plot_mapper_trend_scatter_map,
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
    plot_type = "category_count_bar",
    mapper_id = "cell_vector_category_count_bar_v1",
    can_map = .wb_plot_mapper_category_count_bar_can,
    map_fn = .wb_plot_mapper_category_count_bar_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "dotplot",
    mapper_id = "feature_table_dotplot_v1",
    can_map = .wb_plot_mapper_dotplot_can,
    map_fn = .wb_plot_mapper_dotplot_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "pathway_bar",
    mapper_id = "feature_table_pathway_bar_v1",
    can_map = .wb_plot_mapper_pathway_bar_can,
    map_fn = .wb_plot_mapper_pathway_bar_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "ranked_lollipop",
    mapper_id = "feature_table_ranked_lollipop_v1",
    can_map = .wb_plot_mapper_ranked_lollipop_can,
    map_fn = .wb_plot_mapper_ranked_lollipop_map,
    priority = 10L
  )

  wb_plot_mapper_register(
    plot_type = "heatmap_ranked",
    mapper_id = "feature_table_heatmap_ranked_v1",
    can_map = .wb_plot_mapper_heatmap_ranked_can,
    map_fn = .wb_plot_mapper_heatmap_ranked_map,
    priority = 10L
  )
  wb_plot_mapper_register(
    plot_type = "feature_rank_bar",
    mapper_id = "feature_table_feature_rank_bar_v1",
    can_map = .wb_plot_mapper_feature_rank_bar_can,
    map_fn = .wb_plot_mapper_feature_rank_bar_map,
    priority = 10L
  )
  wb_plot_mapper_register(
    plot_type = "pseudotime_smooth_panel",
    mapper_id = "trajectory_pseudotime_smooth_panel_v1",
    can_map = .wb_plot_mapper_pseudotime_smooth_panel_can,
    map_fn = .wb_plot_mapper_pseudotime_smooth_panel_map,
    priority = 10L
  )
  wb_plot_mapper_register(
    plot_type = "pseudotime_signature_line",
    mapper_id = "trajectory_pseudotime_signature_line_v1",
    can_map = .wb_plot_mapper_pseudotime_signature_line_can,
    map_fn = .wb_plot_mapper_pseudotime_signature_line_map,
    priority = 10L
  )

  .wb_plot_mapper_env$defaults_registered <- TRUE
  invisible(TRUE)
}

#' Wrangle Inputs Into A Validated Plot Dataset
#'
#' Any suitable primitive(s) that satisfy a plot contract can be mapped.
#'
#' @param plot_type Plot type identifier.
#' @param inputs Named list of primitive refs or primitives.
#' @param bundle Open `scworkbench_bundle`.
#' @param runs Optional runs list for session refs.
#' @param version Contract version, default `"v1"`.
#'
#' @return A dataset list with normalized table and mapper metadata.
#'
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

#' Build A Renderer-Agnostic Plot Spec
#'
#' Convert a validated plot dataset into a renderer-neutral plot spec for
#' clients.
#'
#' @param plot_type Plot type identifier.
#' @param dataset Dataset list from [wb_wrangle_plot_dataset()].
#' @param style Optional style preset identifier.
#' @param version Contract version, default `"v1"`.
#'
#' @return A plot-spec list suitable for client renderers.
#'
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
  if (identical(pt, "trend_scatter")) {
    tip <- c("feature_id", "x", "y")
    for (nm in c("p_adj", "p_raw", "direction", "significant", "rank", "label", "size_value")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "feature_scatter",
      version = vv,
      style = as.character(style)[1],
      geom = "point",
      encoding = list(
        x = "x",
        y = "y",
        color = if ("direction" %in% names(df)) "direction" else if ("p_adj" %in% names(df)) "p_adj" else NULL,
        size = if ("size_value" %in% names(df)) "size_value" else NULL,
        label = if ("label" %in% names(df)) "label" else NULL
      ),
      guides = list(color = TRUE, size = "size_value" %in% names(df), label = TRUE),
      reference = list(y = 0),
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

  if (identical(pt, "category_count_bar")) {
    tip <- c("category", "count")
    for (nm in c("pct", "rank", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "category_summary",
      version = vv,
      style = as.character(style)[1],
      geom = "bar",
      encoding = list(
        x = "category",
        y = "count",
        fill = "category"
      ),
      guides = list(fill = TRUE),
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

  if (identical(pt, "pathway_bar")) {
    tip <- c("pathway", "p_adj")
    for (nm in c("score", "overlap", "set_size", "query_size", "namespace", "significant", "rank")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "pathway_summary",
      version = vv,
      style = as.character(style)[1],
      geom = "bar",
      encoding = list(
        x = "pathway",
        y = "p_adj",
        y_transform = "neg_log10",
        fill = if ("namespace" %in% names(df)) "namespace" else NULL
      ),
      guides = list(fill = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "ranked_lollipop")) {
    tip <- c("feature_id", "score")
    for (nm in c("rank", "direction", "significant", "p_adj", "p_raw", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "ranked_entities",
      version = vv,
      style = as.character(style)[1],
      geom = "lollipop",
      encoding = list(
        x = "score",
        y = "feature_id",
        color = if ("direction" %in% names(df)) "direction" else NULL
      ),
      guides = list(color = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "heatmap_ranked")) {
    tip <- c("feature_id", "group", "value")
    for (nm in c("rank", "direction", "significant", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "matrix_like",
      version = vv,
      style = as.character(style)[1],
      geom = "tile",
      encoding = list(
        x = "group",
        y = "feature_id",
        fill = "value"
      ),
      guides = list(fill = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }
  if (identical(pt, "feature_rank_bar")) {
    tip <- c("feature_id", "value")
    for (nm in c("rank", "direction", "significant", "p_adj", "p_raw", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "ranked_features",
      version = vv,
      style = as.character(style)[1],
      geom = "bar",
      encoding = list(
        x = "feature_id",
        y = "value",
        fill = if ("direction" %in% names(df)) "direction" else NULL
      ),
      guides = list(fill = TRUE),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "pseudotime_smooth_panel")) {
    tip <- c("feature_id", "pseudotime", "expr")
    for (nm in c("lineage_id", "n_cells", "label")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = "trajectory_smooth",
      version = vv,
      style = as.character(style)[1],
      geom = "line",
      encoding = list(
        x = "pseudotime",
        y = "expr",
        color = if ("lineage_id" %in% names(df)) "lineage_id" else NULL,
        group = "feature_id",
        facet = "feature_id"
      ),
      guides = list(color = "lineage_id" %in% names(df)),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  if (identical(pt, "pseudotime_signature_line")) {
    tip <- c("feature_set", "pseudotime", "value")
    for (nm in c("feature_id", "driver_rank", "lineage_id", "n_cells", "label", "value_raw", "value_smooth", "value_ci_low", "value_ci_high")) {
      if (nm %in% names(df)) tip <- c(tip, nm)
    }
    spec <- list(
      plot_type = pt,
      dataset_type = as.character(dataset$dataset_type %||% "trajectory_signature_smooth")[1],
      version = vv,
      style = as.character(style)[1],
      geom = "line",
      encoding = list(
        x = "pseudotime",
        y = "value",
        color = if ("feature_id" %in% names(df)) "feature_id" else if ("lineage_id" %in% names(df)) "lineage_id" else NULL,
        group = if ("feature_id" %in% names(df)) "feature_id" else if ("lineage_id" %in% names(df)) "lineage_id" else "feature_set",
        facet = "feature_set"
      ),
      guides = list(color = any(c("feature_id", "lineage_id") %in% names(df))),
      tooltip_fields = unique(tip),
      meta = dataset$meta %||% list()
    )
    return(spec)
  }

  stop("wb_plot_spec(): unsupported plot_type: ", pt, call. = FALSE)
}
