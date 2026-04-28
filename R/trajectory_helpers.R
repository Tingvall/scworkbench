#' List keys for a family primitive
#'
#' Resolves a family primitive/reference and returns one row per key with counts.
#' This is useful for clients (Shiny, agents, notebooks) that need to build
#' lineage selectors without duplicating primitive parsing logic.
#'
#' @param bundle scworkbench bundle handle
#' @param x primitive | artifact_id | spec list (type=primitive/artifact/session)
#' @param runs optional list of wb_run objects (needed for session refs)
#' @return data.frame with columns `key`, `kind`, `n`
#' @export
wb_family_keys <- function(bundle, x, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  # Ergonomics: accept wb_ref_run()/wb_ref_artifact() directly in addition to specs.
  if (is.list(x) && !is.null(x$ref_type)) {
    if (identical(as.character(x$ref_type[[1]]), "run")) {
      x <- list(
        type = "session",
        value = list(run_id = as.character(x$run_id %||% ""), output = as.character(x$output %||% ""))
      )
    } else if (identical(as.character(x$ref_type[[1]]), "artifact")) {
      x <- list(type = "artifact", value = as.character(x$artifact_id %||% ""))
    }
  }

  prim <- wb_resolve_primitive(bundle, x, runs = runs, expected_kind = NULL)
  .wb_assert(.wb_is_primitive(prim), "wb_family_keys(): resolved object is not a wb_primitive")
  .wb_assert(prim$kind %in% c("cell_vector_family", "relation_family", "path_2d_family", "space_path_family"),
             paste0("wb_family_keys(): expected family primitive, got kind=", prim$kind))

  keys <- if (identical(as.character(prim$kind), "space_path_family")) {
    as.character(prim$path_id %||% character(0))
  } else {
    as.character(prim$key %||% character(0))
  }
  keys <- keys[nzchar(keys)]
  if (!length(keys)) {
    return(data.frame(
      key = character(0),
      kind = character(0),
      n = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  tab <- sort(table(keys), decreasing = TRUE)
  out <- data.frame(
    key = as.character(names(tab)),
    kind = rep(as.character(prim$kind), length(tab)),
    n = as.integer(tab),
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

#' Parse canonical monocle-style lineage relation keys
#'
#' Parses keys of the form `root:<root_id>::lineage:<leaf_id>`.
#' Invalid/non-matching keys are returned with `ok = FALSE` and `NA` ids.
#'
#' @param keys character vector of relation/lineage keys
#' @return data.frame with columns `key`, `ok`, `root_id`, `lineage_leaf_id`
#' @export
wb_relation_key_parse_lineage <- function(keys) {
  keys <- as.character(keys %||% character(0))
  if (!length(keys)) {
    return(data.frame(
      key = character(0),
      ok = logical(0),
      root_id = character(0),
      lineage_leaf_id = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # Canonical format only; avoid permissive parsing drift in clients.
  m <- regexec("^root:([^:]+)::lineage:([^:]+)$", keys, perl = TRUE)
  mm <- regmatches(keys, m)
  ok <- vapply(mm, function(x) length(x) == 3L, logical(1))
  root_id <- rep(NA_character_, length(keys))
  leaf_id <- rep(NA_character_, length(keys))
  if (any(ok)) {
    root_id[ok] <- vapply(mm[ok], `[[`, character(1), 2L)
    leaf_id[ok] <- vapply(mm[ok], `[[`, character(1), 3L)
  }

  out <- data.frame(
    key = keys,
    ok = ok,
    root_id = root_id,
    lineage_leaf_id = leaf_id,
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

#' Compare pseudotime and curve family keys for a trajectory
#'
#' Resolves a pseudotime family (`cell_vector_family`) and a curve family
#' (`path_2d_family`) and returns a merged lineage-key summary for client UIs.
#'
#' @param bundle scworkbench bundle handle
#' @param pseudotime primitive | artifact_id | spec list for `cell_vector_family`
#' @param curves primitive | artifact_id | spec list for `path_2d_family`
#' @param runs optional list of wb_run objects (needed for session refs)
#' @return data.frame with lineage key presence/count columns
#' @export
wb_trajectory_keys <- function(bundle, pseudotime, curves, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  # Normalize wb_ref_* ergonomics before strict kind checks.
  if (is.list(pseudotime) && !is.null(pseudotime$ref_type)) {
    if (identical(as.character(pseudotime$ref_type[[1]]), "run")) {
      pseudotime <- list(type = "session", value = list(
        run_id = as.character(pseudotime$run_id %||% ""),
        output = as.character(pseudotime$output %||% "")
      ))
    } else if (identical(as.character(pseudotime$ref_type[[1]]), "artifact")) {
      pseudotime <- list(type = "artifact", value = as.character(pseudotime$artifact_id %||% ""))
    }
  }
  if (is.list(curves) && !is.null(curves$ref_type)) {
    if (identical(as.character(curves$ref_type[[1]]), "run")) {
      curves <- list(type = "session", value = list(
        run_id = as.character(curves$run_id %||% ""),
        output = as.character(curves$output %||% "")
      ))
    } else if (identical(as.character(curves$ref_type[[1]]), "artifact")) {
      curves <- list(type = "artifact", value = as.character(curves$artifact_id %||% ""))
    }
  }

  pt <- wb_resolve_primitive(bundle, pseudotime, runs = runs, expected_kind = "cell_vector_family")
  cv <- wb_resolve_primitive(bundle, curves, runs = runs, expected_kind = "path_2d_family")

  pt_keys <- wb_family_keys(bundle, pt, runs = runs)
  cv_keys <- wb_family_keys(bundle, cv, runs = runs)

  if (nrow(pt_keys)) {
    names(pt_keys)[names(pt_keys) == "n"] <- "n_pseudotime_cells"
    pt_keys$kind <- NULL
  }
  if (nrow(cv_keys)) {
    names(cv_keys)[names(cv_keys) == "n"] <- "n_curve_points"
    cv_keys$kind <- NULL
  }

  all_keys <- sort(unique(c(as.character(pt_keys$key %||% character(0)),
                            as.character(cv_keys$key %||% character(0)))))
  if (!length(all_keys)) {
    return(data.frame(
      lineage_id = character(0),
      in_pseudotime = logical(0),
      in_curves = logical(0),
      shared = logical(0),
      n_pseudotime_cells = integer(0),
      n_curve_points = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- data.frame(
    lineage_id = all_keys,
    stringsAsFactors = FALSE
  )
  out$n_pseudotime_cells <- 0L
  out$n_curve_points <- 0L

  if (nrow(pt_keys)) {
    ii <- match(out$lineage_id, pt_keys$key)
    hit <- !is.na(ii)
    out$n_pseudotime_cells[hit] <- as.integer(pt_keys$n_pseudotime_cells[ii[hit]])
  }
  if (nrow(cv_keys)) {
    ii <- match(out$lineage_id, cv_keys$key)
    hit <- !is.na(ii)
    out$n_curve_points[hit] <- as.integer(cv_keys$n_curve_points[ii[hit]])
  }

  out$in_pseudotime <- out$n_pseudotime_cells > 0L
  out$in_curves <- out$n_curve_points > 0L
  out$shared <- out$in_pseudotime & out$in_curves

  out <- out[, c(
    "lineage_id", "in_pseudotime", "in_curves", "shared",
    "n_pseudotime_cells", "n_curve_points"
  )]
  rownames(out) <- NULL
  out
}

#' Resolve the plotting space for a trajectory curve family (birth-certificate lookup)
#'
#' Returns the 2D `space_id` a `path_2d_family` trajectory was projected into.
#' The lookup is provenance-driven for refs (session run params or artifact
#' `provenance_json$params$plot_space_id`) and does not rely on enriching the
#' primitive itself.
#'
#' @param bundle scworkbench bundle handle
#' @param x path_2d_family primitive | artifact_id | spec list | wb_ref_run()/wb_ref_artifact()
#' @param runs optional list of wb_run objects (needed for session refs)
#' @return scalar `space_id` string when recoverable, otherwise `NA_character_`
#' @export
wb_path_2d_family_space_id <- function(bundle, x, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  # Ergonomics: accept wb_ref_* directly.
  if (is.list(x) && !is.null(x$ref_type)) {
    if (identical(as.character(x$ref_type[[1]]), "run")) {
      x <- list(
        type = "session",
        value = list(run_id = as.character(x$run_id %||% ""), output = as.character(x$output %||% ""))
      )
    } else if (identical(as.character(x$ref_type[[1]]), "artifact")) {
      x <- list(type = "artifact", value = as.character(x$artifact_id %||% ""))
    }
  } else if (is.character(x) && length(x) == 1L && nzchar(x)) {
    # Accept bare artifact_id or "artifact:<id>" string.
    if (startsWith(x, "artifact:")) {
      x <- list(type = "artifact", value = sub("^artifact:", "", x))
    } else if (grepl("^artifact_[0-9]{8}_[0-9]{6}_[a-z0-9]{8}$", x)) {
      x <- list(type = "artifact", value = x)
    }
  }

  # Future-proof primitive path: if metadata is ever added, honor it.
  if (inherits(x, "wb_primitive")) {
    if (!identical(as.character(x$kind %||% ""), "path_2d_family")) return(NA_character_)
    sid <- as.character(x$space_id %||% x$plot_space_id %||% "")[1]
    return(if (nzchar(sid)) sid else NA_character_)
  }

  if (!(is.list(x) && !is.null(x$type))) return(NA_character_)

  tp <- as.character(x$type %||% "")[1]
  if (identical(tp, "session")) {
    if (is.null(runs) || !is.list(runs)) return(NA_character_)
    rid <- as.character(x$value$run_id %||% "")[1]
    out <- as.character(x$value$output %||% "")[1]
    if (!nzchar(rid) || !nzchar(out) || !(rid %in% names(runs))) return(NA_character_)
    run <- runs[[rid]]
    if (!wb_is_run(run)) return(NA_character_)
    prim <- run$outputs[[out]] %||% NULL
    if (!inherits(prim, "wb_primitive") || !identical(as.character(prim$kind %||% ""), "path_2d_family")) {
      return(NA_character_)
    }
    sid <- as.character(
      run$params$plot_space_id %||%
        run$params$space_id %||%
        run$params$model_space_id %||%
        ""
    )[1]
    if (nzchar(sid)) return(sid)
    ui <- run$inputs$user_inputs %||% list()
    sid <- as.character(ui$plot_space_id %||% ui$plot_space %||% ui$space_2d %||% ui$space_id %||% "")[1]
    return(if (nzchar(sid)) sid else NA_character_)
  }

  if (identical(tp, "artifact")) {
    aid <- as.character(x$value %||% "")[1]
    if (!nzchar(aid)) return(NA_character_)
    art <- try(.wb_art_row_one(bundle, aid), silent = TRUE)
    if (inherits(art, "try-error") || !is.data.frame(art) || nrow(art) != 1L) return(NA_character_)
    if (!identical(as.character(art$type[1] %||% ""), "path_2d_family")) return(NA_character_)

    prov <- .wb_art_parse_prov_json(art$provenance_json[1] %||% "")
    sid <- as.character(
      prov$params$plot_space_id %||%
        prov$params$space_id %||%
        prov$inputs$user_inputs$plot_space_id %||%
        prov$inputs$user_inputs$plot_space %||%
        ""
    )[1]
    if (nzchar(sid)) return(sid)

    # Fallback for legacy/non-slingshot artifacts.
    sid <- as.character(art$input_space_id[1] %||% "")[1]
    return(if (nzchar(sid)) sid else NA_character_)
  }

  NA_character_
}
