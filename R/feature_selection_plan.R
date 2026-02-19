#' Execute a feature selection plan into ordered feature IDs
#'
#' Plan shape:
#' - universe: matrix_id (required)
#' - rules: list of rule objects applied sequentially (AND chain)
#'   each rule supports optional negate=TRUE
#'
#' Supported rule types:
#' - feature_set: list(type="feature_set", sets=c("name1","name2"), negate=FALSE)
#' - name_match:  list(type="name_match", query="PAX", mode="substring|prefix|regex", ignore_case=TRUE, negate=FALSE)
#' - expr_prevalence:
#'     list(type="expr_prevalence", cells="all|core|set:<name>|<set name>|cell_ids",
#'          min=0, max=1, negate=FALSE)
#' - variance:
#'     list(type="variance", cells=..., min=NULL, max=NULL, top_n=NULL, negate=FALSE)
#'
#' @param bundle scworkbench bundle
#' @param plan list selection plan
#' @return ordered character vector of feature_ids
#' @export
wb_exec_feature_selection_plan <- function(bundle, plan) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.list(plan), "plan must be list")

  matrix_id <- as.character(plan$universe %||% "")[1]
  .wb_assert(nzchar(matrix_id), "plan$universe must be matrix_id (non-empty string)")

  rules <- plan$rules %||% list()

  all_features <- as.character(wb_feature_ids(bundle, matrix_id = matrix_id))
  .wb_assert(length(all_features) > 0, paste0("No features found for matrix_id: ", matrix_id))
  matrix_cells <- try(colnames(wb_matrix(bundle, matrix_id = matrix_id)), silent = TRUE)
  if (inherits(matrix_cells, "try-error") || is.null(matrix_cells)) {
    matrix_cells <- as.character(wb_cells_with_matrix(bundle, matrix_id = matrix_id))
  }
  matrix_cells <- unique(as.character(matrix_cells))
  matrix_cells <- matrix_cells[nzchar(matrix_cells)]
  .wb_assert(length(matrix_cells) > 0, paste0("No cells found for matrix_id: ", matrix_id))

  .order_like_universe <- function(ids) {
    ids <- unique(as.character(ids))
    ids <- ids[nzchar(ids)]
    all_features[all_features %in% ids]
  }
  .chunk_ix <- function(n, chunk_size) {
    if (n <= 0) return(list())
    starts <- seq.int(1L, n, by = as.integer(chunk_size))
    lapply(starts, function(s) s:min(n, s + as.integer(chunk_size) - 1L))
  }

  .resolve_cells <- function(x) {
    if (is.null(x)) return(as.character(wb_cells(bundle, cell_set = "all")))

    if (is.character(x) && length(x) == 1) {
      token <- as.character(x)[1]
      known_sets <- try(as.character(wb_cell_sets(bundle)), silent = TRUE)
      if (inherits(known_sets, "try-error")) known_sets <- character(0)

      is_set <- startsWith(token, "set:") || (token %in% c("all", "core")) || (token %in% known_sets)
      if (is_set) {
        cand <- as.character(wb_cells(bundle, cell_set = token))
        if (!length(cand) && !startsWith(token, "set:") && !(token %in% c("all", "core"))) {
          cand <- as.character(wb_cells(bundle, cell_set = paste0("set:", token)))
        }
        return(cand)
      }
    }

    .wb_assert(is.character(x), "cells selector must be set token or character cell_ids")
    as.character(x)
  }

  .rule_feature_set <- function(cur, r) {
    sets <- as.character(r$sets %||% character(0))
    .wb_assert(length(sets) > 0, "feature_set rule requires non-empty sets")

    hit <- character(0)
    for (sn in sets) {
      ids <- try(as.character(wb_feature_set_get(bundle, feature_set = sn, matrix_id = matrix_id)), silent = TRUE)
      if (inherits(ids, "try-error")) next
      hit <- c(hit, ids)
    }
    .order_like_universe(intersect(cur, unique(hit)))
  }

  .rule_name_match <- function(cur, r) {
    mode <- as.character(r$mode %||% "substring")[1]
    query <- as.character(r$query %||% "")[1]
    .wb_assert(nzchar(query), "name_match rule requires query")

    if (identical(mode, "regex")) {
      ig <- isTRUE(r$ignore_case %||% TRUE)
      hit <- grepl(query, cur, ignore.case = ig, perl = TRUE)
      return(.order_like_universe(cur[hit]))
    }

    if (identical(mode, "prefix")) {
      hit <- wb_search_features(bundle, matrix_id = matrix_id, query = query, limit = max(length(all_features), 1000L), mode = "prefix")
      return(.order_like_universe(intersect(cur, hit)))
    }

    # default substring
    hit <- wb_search_features(bundle, matrix_id = matrix_id, query = query, limit = max(length(all_features), 1000L), mode = "substring")
    .order_like_universe(intersect(cur, hit))
  }

  .rule_expr_prevalence <- function(cur, r) {
    cells <- .resolve_cells(r$cells %||% "all")
    cells <- unique(as.character(cells))
    cells <- cells[nzchar(cells)]
    cells <- intersect(cells, matrix_cells)
    .wb_assert(length(cells) > 0, "expr_prevalence rule resolved to 0 cells")

    if (!length(cur)) return(character(0))
    chunk_size <- suppressWarnings(
      as.integer(r$chunk_size %||% getOption("scworkbench.feature_plan_chunk_size", 500L))
    )
    if (!is.finite(chunk_size) || chunk_size <= 0L) chunk_size <- 500L

    prev <- numeric(length(cur))
    names(prev) <- cur
    for (ix in .chunk_ix(length(cur), chunk_size)) {
      feats <- cur[ix]
      x <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells)
      vals <- if (methods::is(x, "sparseMatrix")) {
        xnz <- x
        xnz@x <- rep.int(1, length(xnz@x))
        Matrix::rowSums(xnz) / ncol(xnz)
      } else {
        Matrix::rowMeans(x > 0)
      }
      prev[names(vals)] <- as.numeric(vals)
    }

    ok <- rep(TRUE, length(prev))
    if (!is.null(r$min)) ok <- ok & (prev >= as.numeric(r$min))
    if (!is.null(r$max)) ok <- ok & (prev <= as.numeric(r$max))

    .order_like_universe(names(prev)[ok])
  }

  .rule_variance <- function(cur, r) {
    cells <- .resolve_cells(r$cells %||% "all")
    cells <- unique(as.character(cells))
    cells <- cells[nzchar(cells)]
    cells <- intersect(cells, matrix_cells)
    .wb_assert(length(cells) > 0, "variance rule resolved to 0 cells")

    if (!length(cur)) return(character(0))
    chunk_size <- suppressWarnings(
      as.integer(r$chunk_size %||% getOption("scworkbench.feature_plan_chunk_size", 500L))
    )
    if (!is.finite(chunk_size) || chunk_size <= 0L) chunk_size <- 500L

    vv <- numeric(length(cur))
    names(vv) <- cur
    for (ix in .chunk_ix(length(cur), chunk_size)) {
      feats <- cur[ix]
      x <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells)

      mu <- Matrix::rowMeans(x)
      mu2 <- if (methods::is(x, "sparseMatrix")) {
        x2 <- x
        x2@x <- x2@x^2
        Matrix::rowSums(x2) / ncol(x2)
      } else {
        Matrix::rowMeans(x^2)
      }
      v <- pmax(0, mu2 - mu^2)
      vv[names(v)] <- as.numeric(v)
    }

    ok <- rep(TRUE, length(vv))
    if (!is.null(r$min)) ok <- ok & (vv >= as.numeric(r$min))
    if (!is.null(r$max)) ok <- ok & (vv <= as.numeric(r$max))

    ids <- names(vv)[ok]
    ids <- .order_like_universe(ids)

    tn <- suppressWarnings(as.integer(r$top_n %||% NA_integer_))
    if (is.finite(tn) && tn > 0L && length(ids) > tn) {
      ord <- order(vv[ids], decreasing = TRUE, na.last = TRUE)
      ids <- ids[ord][seq_len(tn)]
      ids <- .order_like_universe(ids)
    }

    ids
  }

  .apply_rule <- function(cur, r) {
    tp <- as.character(r$type %||% "")[1]
    .wb_assert(nzchar(tp), "feature rule missing type")
    neg <- isTRUE(r$negate %||% FALSE)

    matched <- switch(
      tp,
      feature_set = .rule_feature_set(cur, r),
      name_match = .rule_name_match(cur, r),
      expr_prevalence = .rule_expr_prevalence(cur, r),
      variance = .rule_variance(cur, r),
      stop("Unknown feature rule type: ", tp, call. = FALSE)
    )

    if (neg) {
      return(.order_like_universe(setdiff(cur, matched)))
    }
    matched
  }

  feats <- all_features
  for (r in rules) {
    if (!length(feats)) break
    feats <- .apply_rule(feats, r)
  }

  .wb_assert(length(feats) > 0, "Feature selection is empty at end of plan.")
  feats
}
