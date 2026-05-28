.wb_space_path_coord_matrix <- function(bundle, space_id, cells = NULL) {
  X <- .wb_as_coord_matrix(wb_space(bundle, space_id = space_id, cells = cells))
  .wb_assert(is.matrix(X) && nrow(X) > 0L && ncol(X) >= 2L,
             "space path ops require a non-empty space with at least 2 dimensions.")
  .wb_assert(!anyNA(X), "space path ops require coordinates without NA values.")
  X
}

.wb_space_path_warn_checkpoint_quality <- function(checkpoint_cells, checkpoint_sets) {
  ns <- vapply(checkpoint_cells, length, integer(1))
  if (any(ns < 5L)) {
    bad <- checkpoint_sets[ns < 5L]
    warning(
      paste0(
        "space_path_define: very small checkpoints detected: ",
        paste(bad, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (length(checkpoint_cells) >= 2L) {
    overlaps <- character(0)
    for (i in seq_len(length(checkpoint_cells) - 1L)) {
      for (j in seq.int(i + 1L, length(checkpoint_cells))) {
        if (length(intersect(checkpoint_cells[[i]], checkpoint_cells[[j]])) > 0L) {
          overlaps <- c(overlaps, paste0(checkpoint_sets[i], " ~ ", checkpoint_sets[j]))
        }
      }
    }
    if (length(overlaps)) {
      warning(
        paste0(
          "space_path_define: overlapping checkpoints detected: ",
          paste(overlaps, collapse = "; "),
          "."
        ),
        call. = FALSE
      )
    }
  }

  if (length(ns) >= 2L) {
    nn <- ns[ns > 0L]
    if (length(nn) >= 2L && (max(nn) / max(1L, min(nn))) >= 10) {
      warning("space_path_define: large checkpoint-size imbalance detected.", call. = FALSE)
    }
  }

  invisible(TRUE)
}

.wb_space_path_resolve_checkpoints <- function(bundle, checkpoint_sets, effective_cells, available_cells) {
  checkpoint_sets <- as.character(checkpoint_sets %||% character(0))
  .wb_assert(length(checkpoint_sets) >= 2L, "checkpoint_sets must define at least two ordered checkpoints.")
  .wb_assert(all(nzchar(checkpoint_sets)), "checkpoint_sets must be non-empty strings.")

  eff <- as.character(effective_cells)
  avail <- unique(as.character(available_cells))
  keep_universe <- intersect(eff, avail)

  checkpoint_cells <- lapply(checkpoint_sets, function(cs) {
    cells <- tryCatch(wb_cells(bundle, cell_set = cs), error = function(e) character(0))
    intersect(keep_universe, as.character(cells))
  })

  ns <- vapply(checkpoint_cells, length, integer(1))
  if (any(ns == 0L)) {
    bad <- checkpoint_sets[ns == 0L]
    stop(
      paste0(
        "space_path_define: checkpoint(s) resolved to zero cells in the selected space/effective cell universe: ",
        paste(bad, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }
  if (sum(ns > 0L) < 2L) {
    stop("space_path_define: fewer than two non-empty checkpoints remain after resolution.", call. = FALSE)
  }

  .wb_space_path_warn_checkpoint_quality(checkpoint_cells, checkpoint_sets)
  checkpoint_cells
}

.wb_space_path_anchor_centroids <- function(X, checkpoint_cells, checkpoint_sets) {
  anchors <- lapply(seq_along(checkpoint_cells), function(i) {
    ids <- checkpoint_cells[[i]]
    Xi <- X[ids, , drop = FALSE]
    .wb_assert(nrow(Xi) > 0L, paste0("No anchor cells remain for checkpoint: ", checkpoint_sets[i]))
    stats::setNames(colMeans(Xi), colnames(X))
  })
  A <- do.call(rbind, anchors)
  rownames(A) <- checkpoint_sets
  A
}

.wb_space_path_sample_linear <- function(anchors, n_points = NULL, points_per_segment = 25L) {
  anchors <- as.matrix(anchors)
  .wb_assert(nrow(anchors) >= 2L, "Need at least two anchors to define a path.")
  .wb_assert(ncol(anchors) >= 2L, "Anchors must live in a space with at least 2 dimensions.")

  seg_vec <- anchors[-1, , drop = FALSE] - anchors[-nrow(anchors), , drop = FALSE]
  seg_len <- sqrt(rowSums(seg_vec^2))
  .wb_assert(all(seg_len > 0), "Consecutive checkpoints must not collapse to identical centroids.")
  total_len <- sum(seg_len)
  cum_len <- c(0, cumsum(seg_len))

  if (is.null(n_points)) {
    points_per_segment <- as.integer(points_per_segment)[1]
    .wb_assert(is.finite(points_per_segment) && points_per_segment >= 1L,
               "points_per_segment must be >= 1.")
    pieces <- vector("list", nrow(anchors) - 1L)
    for (j in seq_len(nrow(anchors) - 1L)) {
      frac <- seq(0, 1, length.out = points_per_segment + 1L)
      seg_pts <- matrix(seg_vec[j, ], nrow = length(frac), ncol = ncol(anchors), byrow = TRUE)
      seg_pts <- seg_pts * frac
      seg_pts <- sweep(seg_pts, 2, anchors[j, ], FUN = "+")
      if (j > 1L) seg_pts <- seg_pts[-1L, , drop = FALSE]
      pieces[[j]] <- seg_pts
    }
    out <- do.call(rbind, pieces)
    anchor_point_index <- 1L + (seq_len(nrow(anchors)) - 1L) * points_per_segment
    colnames(out) <- colnames(anchors)
    return(list(
      points = out,
      segment_lengths = seg_len,
      total_length = total_len,
      anchor_point_index = as.integer(anchor_point_index),
      anchor_arclength = cum_len
    ))
  } else {
    n_points <- as.integer(n_points)[1]
    .wb_assert(is.finite(n_points) && n_points >= 2L, "n_path_points must be >= 2.")

    s_vals <- seq(0, total_len, length.out = n_points)
    out <- matrix(NA_real_, nrow = n_points, ncol = ncol(anchors))
    colnames(out) <- colnames(anchors)

    for (i in seq_along(s_vals)) {
      s <- s_vals[i]
      seg_idx <- findInterval(s, cum_len, rightmost.closed = TRUE)
      seg_idx <- min(max(1L, seg_idx), length(seg_len))
      local <- s - cum_len[seg_idx]
      frac <- if (seg_len[seg_idx] <= 0) 0 else local / seg_len[seg_idx]
      frac <- min(max(frac, 0), 1)
      out[i, ] <- anchors[seg_idx, ] + frac * seg_vec[seg_idx, ]
    }

    anchor_point_index <- vapply(cum_len, function(s) {
      which.min(abs(s_vals - s))
    }, integer(1))
    return(list(
      points = out,
      segment_lengths = seg_len,
      total_length = total_len,
      anchor_point_index = as.integer(anchor_point_index),
      anchor_arclength = cum_len
    ))
  }
}

.wb_space_path_weight_vec <- function(d, method = "inverse_distance") {
  method <- as.character(method %||% "inverse_distance")[1]
  if (identical(method, "inverse_distance")) {
    w <- 1 / (d + 1e-8)
  } else if (identical(method, "gaussian")) {
    sc <- stats::median(d)
    if (!is.finite(sc) || sc <= 0) sc <- max(d, 1e-8)
    w <- exp(-(d^2) / (2 * sc^2))
  } else {
    stop("Unsupported smooth_weight: ", method, call. = FALSE)
  }
  w / sum(w)
}

.wb_space_path_point_progress <- function(points) {
  P <- as.matrix(points)
  if (nrow(P) <= 1L) return(rep(0, nrow(P)))
  seg_len <- sqrt(rowSums((P[-1L, , drop = FALSE] - P[-nrow(P), , drop = FALSE])^2))
  total <- sum(seg_len)
  if (!is.finite(total) || total <= 0) return(rep(0, nrow(P)))
  c(0, cumsum(seg_len)) / total
}

.wb_space_path_point_segments <- function(anchor_point_index, n_points) {
  anchor_idx <- sort(as.integer(anchor_point_index))
  n_seg <- length(anchor_idx) - 1L
  out <- integer(n_points)
  if (n_seg <= 0L) return(out)
  for (j in seq_len(n_seg)) {
    lo <- anchor_idx[j]
    hi <- anchor_idx[j + 1L]
    out[lo:hi] <- j
  }
  out[n_points] <- max(out)
  out
}

.wb_space_path_smooth_points <- function(cells_coords,
                                         anchors,
                                         linear_sample,
                                         smooth_k = 30L,
                                         smooth_n_iter = 2L,
                                         smooth_weight = "inverse_distance") {
  X <- as.matrix(cells_coords)
  P <- as.matrix(linear_sample$points)
  anchors <- as.matrix(anchors)
  anchor_idx <- as.integer(linear_sample$anchor_point_index)
  smooth_k <- as.integer(smooth_k)[1]
  smooth_n_iter <- as.integer(smooth_n_iter)[1]
  .wb_assert(is.finite(smooth_k) && smooth_k >= 2L, "smooth_k must be >= 2.")
  .wb_assert(is.finite(smooth_n_iter) && smooth_n_iter >= 1L, "smooth_n_iter must be >= 1.")

  kk <- min(smooth_k, nrow(X))
  out <- P
  movable <- setdiff(seq_len(nrow(out)), anchor_idx)
  point_seg <- .wb_space_path_point_segments(anchor_idx, nrow(out))
  n_seg <- max(point_seg)
  progress_window <- max(0.05, 0.5 / max(1, n_seg))
  pull_alpha <- 0.25
  neighbor_alpha <- 0.35

  for (iter in seq_len(smooth_n_iter)) {
    point_prog <- .wb_space_path_point_progress(out)
    scored <- .wb_space_path_score_linear(X, out, anchor_points = anchors)
    if (length(movable)) {
      target <- out
      for (i in seq_along(movable)) {
        p_idx <- movable[i]
        seg_here <- point_seg[p_idx]
        prog_here <- point_prog[p_idx]

        route_keep <- abs(scored$nearest_segment - seg_here) <= 1L &
          abs(scored$progress - prog_here) <= progress_window
        cand_idx <- which(route_keep)
        if (length(cand_idx) < min(5L, kk)) {
          cand_idx <- which(abs(scored$nearest_segment - seg_here) <= 1L)
        }
        if (length(cand_idx) < min(5L, kk)) {
          cand_idx <- seq_len(nrow(X))
        }

        d <- sqrt(rowSums((X[cand_idx, , drop = FALSE] -
                             matrix(out[p_idx, ], nrow = length(cand_idx), ncol = ncol(X), byrow = TRUE))^2))
        ord <- order(d, scored$distance[cand_idx], abs(scored$progress[cand_idx] - prog_here))
        use <- cand_idx[ord[seq_len(min(kk, length(ord)))]]
        d_use <- d[ord[seq_len(min(kk, length(ord)))]]
        prog_penalty <- abs(scored$progress[use] - prog_here) / max(progress_window, 1e-8)
        dist_penalty <- scored$distance[use]

        if (any(d_use == 0)) {
          target[p_idx, ] <- colMeans(X[use[d_use == 0], , drop = FALSE])
        } else {
          w_space <- .wb_space_path_weight_vec(d_use, method = smooth_weight)
          w_route <- 1 / (1 + prog_penalty)
          w_path <- 1 / (1 + dist_penalty)
          w <- w_space * w_route * w_path
          w <- w / sum(w)
          target[p_idx, ] <- colSums(X[use, , drop = FALSE] * w)
        }
      }
      proposed <- out
      proposed[movable, ] <- (1 - pull_alpha) * out[movable, , drop = FALSE] +
        pull_alpha * target[movable, , drop = FALSE]

      smoothed <- proposed
      for (j in seq_len(n_seg)) {
        lo <- anchor_idx[j]
        hi <- anchor_idx[j + 1L]
        if ((hi - lo) <= 1L) next
        for (p_idx in seq.int(lo + 1L, hi - 1L)) {
          local_avg <- 0.5 * proposed[p_idx, ] +
            0.25 * proposed[p_idx - 1L, ] +
            0.25 * proposed[p_idx + 1L, ]
          smoothed[p_idx, ] <- (1 - neighbor_alpha) * proposed[p_idx, ] +
            neighbor_alpha * local_avg
        }
      }
      out[movable, ] <- smoothed[movable, , drop = FALSE]
    }
    out[anchor_idx, ] <- anchors
  }

  out
}

.wb_space_path_points_to_primitive <- function(space_id, path_id, points, meta = list()) {
  n_points <- nrow(points)
  n_dims <- ncol(points)
  wb_prim_space_path_family(
    space_id = rep(as.character(space_id), each = n_dims * n_points),
    path_id = rep(as.character(path_id), each = n_dims * n_points),
    point = rep(seq_len(n_points), each = n_dims),
    dim = rep(seq_len(n_dims), times = n_points),
    value = as.numeric(t(points)),
    meta = meta
  )
}

.wb_space_path_matrix <- function(path_prim) {
  .wb_assert_kind(path_prim, "space_path_family")
  path_ids <- unique(as.character(path_prim$path_id))
  .wb_assert(length(path_ids) == 1L, "V1 space_path_score/project_2d expects a single path_id per primitive.")
  point_ids <- sort(unique(as.integer(path_prim$point)))
  dim_ids <- sort(unique(as.integer(path_prim$dim)))
  M <- matrix(NA_real_, nrow = length(point_ids), ncol = length(dim_ids))
  rownames(M) <- as.character(point_ids)
  colnames(M) <- paste0("dim", dim_ids)
  ri <- match(as.integer(path_prim$point), point_ids)
  ci <- match(as.integer(path_prim$dim), dim_ids)
  M[cbind(ri, ci)] <- as.numeric(path_prim$value)
  .wb_assert(!anyNA(M), "space_path_family contains incomplete path coordinates.")
  list(path_id = path_ids[1], points = M, dim_ids = dim_ids)
}

.wb_space_path_anchor_matrix <- function(path_prim) {
  meta <- path_prim$meta %||% list()
  cent <- meta$anchor_centroids %||% NULL
  if (is.null(cent)) return(NULL)
  cent <- as.matrix(cent)
  storage.mode(cent) <- "double"
  cent
}

.wb_space_path_score_linear <- function(X, path_points, anchor_points = NULL) {
  X <- as.matrix(X)
  P <- as.matrix(path_points)
  .wb_assert(nrow(P) >= 2L, "Need at least two path points to score against a path.")

  A <- P[-nrow(P), , drop = FALSE]
  B <- P[-1L, , drop = FALSE]
  AB <- B - A
  seg_len <- sqrt(rowSums(AB^2))
  .wb_assert(all(seg_len > 0), "Path contains zero-length segments.")
  cum_len <- c(0, cumsum(seg_len))
  total_len <- sum(seg_len)

  best_dist2 <- rep(Inf, nrow(X))
  best_seg <- rep(NA_integer_, nrow(X))
  best_t <- rep(NA_real_, nrow(X))

  for (j in seq_len(nrow(A))) {
    a <- A[j, ]
    ab <- AB[j, ]
    denom <- sum(ab^2)
    .wb_assert(denom > 0, "Path contains zero-length segment.")
    Xa <- sweep(X, 2, a, FUN = "-")
    t <- as.numeric((Xa %*% ab) / denom)
    t <- pmin(1, pmax(0, t))
    proj <- sweep(matrix(t, nrow = nrow(X), ncol = ncol(X)), 2, ab, FUN = "*")
    proj <- sweep(proj, 2, a, FUN = "+")
    d2 <- rowSums((X - proj)^2)
    take <- d2 < best_dist2
    best_dist2[take] <- d2[take]
    best_seg[take] <- j
    best_t[take] <- t[take]
  }

  progress <- (cum_len[best_seg] + best_t * seg_len[best_seg]) / total_len
  distance <- sqrt(best_dist2)

  if (is.null(anchor_points)) {
    anchor_points <- P[c(1L, nrow(P)), , drop = FALSE]
  }
  anchor_points <- as.matrix(anchor_points)
  nearest_anchor <- rep(NA_integer_, nrow(X))
  for (i in seq_len(nrow(X))) {
    d2 <- rowSums((matrix(X[i, ], nrow = nrow(anchor_points), ncol = ncol(anchor_points), byrow = TRUE) - anchor_points)^2)
    nearest_anchor[i] <- which.min(d2)
  }

  list(
    progress = as.numeric(progress),
    distance = as.numeric(distance),
    nearest_segment = as.numeric(best_seg),
    nearest_anchor = as.numeric(nearest_anchor),
    summary = data.frame(
      mean_distance = mean(distance),
      median_distance = stats::median(distance),
      p90_distance = as.numeric(stats::quantile(distance, 0.9, names = FALSE)),
      stringsAsFactors = FALSE
    )
  )
}

.wb_space_path_project_local_interpolation <- function(source_coords, target_xy, path_points, k = 20L) {
  .wb_require_pkg("RANN", "space_path_project_2d local interpolation")
  S <- as.matrix(source_coords)
  Y <- as.matrix(target_xy[, c("x", "y"), drop = FALSE])
  Q <- as.matrix(path_points)
  .wb_assert(nrow(S) == nrow(Y), "Source and target coordinates must align by cell.")
  .wb_assert(nrow(S) >= 2L, "Need at least two shared cells to project analytical path into 2D.")
  kk <- min(as.integer(k), nrow(S))
  nn <- RANN::nn2(data = S, query = Q, k = kk)
  out <- matrix(NA_real_, nrow = nrow(Q), ncol = 2L)
  colnames(out) <- c("x", "y")
  for (i in seq_len(nrow(Q))) {
    idx <- nn$nn.idx[i, ]
    d <- nn$nn.dists[i, ]
    if (length(idx) == 1L && d[1] == 0) {
      out[i, ] <- Y[idx[1], ]
      next
    }
    if (any(d == 0)) {
      out[i, ] <- colMeans(Y[idx[d == 0], , drop = FALSE])
      next
    }
    w <- 1 / (d + 1e-8)
    w <- w / sum(w)
    out[i, ] <- colSums(Y[idx, , drop = FALSE] * w)
  }
  out
}

#' Define A Checkpoint-Anchored Path In A Space
#'
#' @export
wb_op_space_path_define <- function(bundle,
                                    space_id,
                                    checkpoint_sets,
                                    cells = NULL,
                                    fit_mode = "linear",
                                    checkpoint_summary = "centroid",
                                    n_path_points = NULL,
                                    smooth_k = 30L,
                                    smooth_n_iter = 2L,
                                    smooth_weight = "inverse_distance",
                                    path_id_out = "space_path") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  fit_mode <- as.character(fit_mode)[1]
  .wb_assert(fit_mode %in% c("linear", "manifold_smooth"),
             "fit_mode must be one of: linear, manifold_smooth.")
  .wb_assert(identical(as.character(checkpoint_summary)[1], "centroid"), "V1 only supports checkpoint_summary='centroid'.")

  cells_use <- as.character(cells %||% wb_cells(bundle, cell_set = "all"))
  X <- .wb_space_path_coord_matrix(bundle, space_id = space_id, cells = cells_use)
  checkpoint_cells <- .wb_space_path_resolve_checkpoints(
    bundle = bundle,
    checkpoint_sets = checkpoint_sets,
    effective_cells = rownames(X),
    available_cells = rownames(X)
  )
  anchors <- .wb_space_path_anchor_centroids(X, checkpoint_cells, as.character(checkpoint_sets))
  linear_sample <- .wb_space_path_sample_linear(anchors, n_points = n_path_points, points_per_segment = 25L)
  fit_points <- if (identical(fit_mode, "manifold_smooth")) {
    .wb_space_path_smooth_points(
      cells_coords = X,
      anchors = anchors,
      linear_sample = linear_sample,
      smooth_k = smooth_k,
      smooth_n_iter = smooth_n_iter,
      smooth_weight = smooth_weight
    )
  } else {
    linear_sample$points
  }

  meta <- list(
    space_id = as.character(space_id)[1],
    fit_mode = fit_mode,
    path_class = fit_mode,
    n_dims = ncol(fit_points),
    n_points = nrow(fit_points),
    checkpoint_n = length(checkpoint_sets),
    coordinate_space_kind = "space",
    anchor_mode = "checkpoint_centroid",
    anchor_label = as.character(checkpoint_sets),
    anchor_order = seq_along(checkpoint_sets),
    anchor_cell_set = as.character(checkpoint_sets),
    anchor_n_cells = vapply(checkpoint_cells, length, integer(1)),
    anchor_summary = "centroid",
    anchor_centroids = unname(anchors),
    anchor_point_index = as.integer(linear_sample$anchor_point_index),
    smooth_neighbor_mode = if (identical(fit_mode, "manifold_smooth")) "knn" else NULL,
    smooth_route_consistent = if (identical(fit_mode, "manifold_smooth")) TRUE else NULL,
    smooth_segment_window = if (identical(fit_mode, "manifold_smooth")) 1L else NULL,
    smooth_progress_window = if (identical(fit_mode, "manifold_smooth")) max(0.05, 0.5 / max(1, length(checkpoint_sets) - 1L)) else NULL,
    smooth_k = if (identical(fit_mode, "manifold_smooth")) as.integer(smooth_k)[1] else NULL,
    smooth_n_iter = if (identical(fit_mode, "manifold_smooth")) as.integer(smooth_n_iter)[1] else NULL,
    smooth_weight = if (identical(fit_mode, "manifold_smooth")) as.character(smooth_weight)[1] else NULL
  )

  list(
    outputs = list(
      path = .wb_space_path_points_to_primitive(
        space_id = as.character(space_id)[1],
        path_id = as.character(path_id_out)[1],
        points = fit_points,
        meta = meta
      )
    ),
    params = list(
      space_id = as.character(space_id)[1],
      checkpoint_sets = as.character(checkpoint_sets),
      fit_mode = fit_mode,
      checkpoint_summary = "centroid",
      n_checkpoints = length(checkpoint_sets),
      n_path_points = nrow(fit_points),
      smooth_route_consistent = if (identical(fit_mode, "manifold_smooth")) TRUE else NULL,
      smooth_k = if (identical(fit_mode, "manifold_smooth")) as.integer(smooth_k)[1] else NULL,
      smooth_n_iter = if (identical(fit_mode, "manifold_smooth")) as.integer(smooth_n_iter)[1] else NULL,
      smooth_weight = if (identical(fit_mode, "manifold_smooth")) as.character(smooth_weight)[1] else NULL,
      path_id_out = as.character(path_id_out)[1]
    )
  )
}

#' Score Cells Against An Analytical Space Path
#'
#' @export
wb_op_space_path_score <- function(bundle,
                                   space_id,
                                   path,
                                   cells = NULL,
                                   score_mode = "orthogonal_projection",
                                   distance_metric = "euclidean",
                                   score_prefix = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_kind(path, "space_path_family")
  .wb_assert(identical(as.character(score_mode)[1], "orthogonal_projection"),
             "V1 only supports score_mode='orthogonal_projection'.")
  .wb_assert(identical(as.character(distance_metric)[1], "euclidean"),
             "V1 only supports distance_metric='euclidean'.")

  pm <- .wb_space_path_matrix(path)
  path_space_id <- unique(as.character(path$space_id))
  .wb_assert(length(path_space_id) == 1L, "space_path_score expects a single source space_id.")
  .wb_assert(identical(as.character(space_id)[1], path_space_id[1]),
             "space_path_score requires path and scoring space to match.")

  cells_use <- as.character(cells %||% wb_cells(bundle, cell_set = "all"))
  X <- .wb_space_path_coord_matrix(bundle, space_id = as.character(space_id)[1], cells = cells_use)
  anchor_points <- .wb_space_path_anchor_matrix(path)
  scored <- .wb_space_path_score_linear(X, pm$points, anchor_points = anchor_points)

  prefix <- as.character(score_prefix %||% "")[1]
  key_of <- function(x) if (nzchar(prefix)) paste0(prefix, x) else x

  score_prim <- wb_prim_cell_vector_family(
    key = rep(c(key_of("progress"), key_of("distance"), key_of("nearest_segment"), key_of("nearest_anchor")),
              each = nrow(X)),
    cell_id = rep(rownames(X), times = 4L),
    value = c(scored$progress, scored$distance, scored$nearest_segment, scored$nearest_anchor),
    value_type = "continuous"
  )

  summary_tbl <- data.frame(
    path_id = pm$path_id,
    space_id = as.character(space_id)[1],
    fit_mode = as.character(path$meta$fit_mode %||% "linear")[1],
    n_checkpoints = as.integer(path$meta$checkpoint_n %||% NA_integer_)[1],
    n_path_points = nrow(pm$points),
    cells_scored = nrow(X),
    mean_distance = scored$summary$mean_distance[1],
    median_distance = scored$summary$median_distance[1],
    p90_distance = scored$summary$p90_distance[1],
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      path_scores = score_prim,
      fit_summary = wb_prim_obs_table(
        table = summary_tbl,
        table_type = "space_path_score_summary",
        entity_kind = "path",
        meta = list(path_id = pm$path_id, space_id = as.character(space_id)[1])
      )
    ),
    params = list(
      space_id = as.character(space_id)[1],
      path_id = pm$path_id,
      score_mode = "orthogonal_projection",
      distance_metric = "euclidean",
      n_cells = nrow(X)
    )
  )
}

#' Project An Analytical Space Path Into A 2D Plot Space
#'
#' @export
wb_op_space_path_project_2d <- function(bundle,
                                        path,
                                        plot_space_id,
                                        project_mode = "local_interpolation",
                                        approx_points = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_kind(path, "space_path_family")
  .wb_assert(identical(as.character(project_mode)[1], "local_interpolation"),
             "V1 only supports project_mode='local_interpolation'.")

  pm <- .wb_space_path_matrix(path)
  source_space_id <- unique(as.character(path$space_id))
  .wb_assert(length(source_space_id) == 1L, "space_path_project_2d expects a single source space_id.")

  source_all <- .wb_space_path_coord_matrix(bundle, source_space_id[1], cells = NULL)
  plot_df <- .wb_space_2d_safe(bundle, plot_space_id, cells = NULL)
  .wb_assert(nrow(plot_df) > 0L, paste0("No 2D coordinates found for plot_space_id: ", plot_space_id))

  shared <- intersect(rownames(source_all), as.character(plot_df$cell_id))
  .wb_assert(length(shared) >= 2L, "Need at least two cells shared between source space and plot space for projection.")
  source_shared <- source_all[shared, , drop = FALSE]
  plot_shared <- plot_df[match(shared, plot_df$cell_id), c("cell_id", "x", "y"), drop = FALSE]

  xy <- .wb_space_path_project_local_interpolation(
    source_coords = source_shared,
    target_xy = plot_shared,
    path_points = pm$points,
    k = min(20L, nrow(source_shared))
  )

  if (!is.null(approx_points)) {
    keep_n <- min(as.integer(approx_points)[1], nrow(xy))
    .wb_assert(keep_n >= 2L, "approx_points must be >= 2 when provided.")
    idx <- unique(round(seq(1, nrow(xy), length.out = keep_n)))
    xy <- xy[idx, , drop = FALSE]
  }

  list(
    outputs = list(
      curves = wb_prim_path_2d_family(
        key = rep(pm$path_id, nrow(xy)),
        point = seq_len(nrow(xy)),
        x = xy[, 1],
        y = xy[, 2]
      )
    ),
    params = list(
      space_id = source_space_id[1],
      plot_space_id = as.character(plot_space_id)[1],
      path_id = pm$path_id,
      project_mode = "local_interpolation",
      approx_points = if (is.null(approx_points)) NA_integer_ else as.integer(approx_points)[1]
    )
  )
}
