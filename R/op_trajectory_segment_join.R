.wb_new_trajectory_composite_id <- function(label = "composite") {
  safe <- gsub("[^A-Za-z0-9_]+", "_", as.character(label %||% "composite")[1])
  safe <- gsub("^_+|_+$", "", safe)
  if (!nzchar(safe)) safe <- "composite"
  paste0(
    "trajcomp_",
    safe,
    "_",
    format(Sys.time(), "%Y%m%d_%H%M%S"),
    "_",
    paste0(sample(c(0:9, letters), 8, TRUE), collapse = "")
  )
}

.wb_segment_ref_artifact_id <- function(x) {
  aid <- .wb_ref_to_artifact_id(x)
  as.character(aid %||% "")[1]
}

.wb_segment_resolve_primitive <- function(bundle, x, runs = NULL, expected_kind = NULL, label = "segment input") {
  .wb_assert(!is.null(x), paste0("trajectory_segment_join(): missing ", label, "."))
  prim <- .wb_trajectory_resolve_primitive_for_fit(bundle, x, runs = runs)
  if (!is.null(expected_kind)) {
    .wb_assert_kind(prim, expected_kind, where = paste0(" for ", label))
  }
  prim
}

.wb_segment_family_values <- function(prim, lineage, label = "cell_vector_family") {
  .wb_assert_kind(prim, "cell_vector_family", where = paste0(" for ", label))
  lineage <- as.character(lineage %||% "")[1]
  .wb_assert(nzchar(lineage), "trajectory_segment_join(): lineage must be a single non-empty string.")
  key <- as.character(prim$key)
  hit <- key == lineage
  .wb_assert(any(hit), paste0("trajectory_segment_join(): lineage '", lineage, "' not found in ", label, "."))
  data.frame(
    cell_id = as.character(prim$cell_id[hit]),
    value = suppressWarnings(as.numeric(prim$value[hit])),
    stringsAsFactors = FALSE
  )
}

.wb_segment_scale01 <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  out <- rep(NA_real_, length(x))
  finite <- is.finite(x)
  if (!any(finite)) return(out)
  rng <- range(x[finite], na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2])) return(out)
  if (abs(rng[2] - rng[1]) < .Machine$double.eps) {
    out[finite] <- 0
    return(out)
  }
  out[finite] <- (x[finite] - rng[1]) / (rng[2] - rng[1])
  out
}

.wb_validate_trajectory_segment <- function(bundle, segment, runs = NULL, allow_legacy = FALSE) {
  .wb_assert(is.list(segment), "trajectory_segment_join(): each segment must be a list.")
  .wb_assert(!is.null(segment$pseudotime), "trajectory_segment_join(): each segment requires pseudotime.")
  .wb_assert(!is.null(segment$lineage), "trajectory_segment_join(): each segment requires lineage.")

  refs <- list(segment$model, segment$pseudotime, segment$lineage_weights, segment$path)
  refs <- refs[!vapply(refs, is.null, logical(1))]
  if (length(refs) >= 2L) {
    do.call(
      wb_trajectory_assert_fit_compatible,
      c(list(bundle = bundle), refs, list(runs = runs, allow_legacy = allow_legacy))
    )
  }
  info <- wb_trajectory_fit_info(bundle, segment$pseudotime, runs = runs)
  if (!nzchar(as.character(info$trajectory_fit_id[1] %||% ""))) {
    msg <- "trajectory_segment_join(): segment pseudotime is missing trajectory_fit_id; legacy trajectory segments cannot be joined without explicit allow_legacy=TRUE."
    if (isTRUE(allow_legacy)) warning(msg, call. = FALSE) else stop(msg, call. = FALSE)
  }
  info
}

#' Join Separately Fitted Trajectory Segments
#'
#' Builds an auditable composite pseudotime from ordered trajectory segments
#' without merging the parent trajectory model objects. Within each segment,
#' trajectory artifacts must share one `trajectory_fit_id`; across segments,
#' different fit IDs are allowed and recorded as parent fit families.
#'
#' @param bundle Open scworkbench bundle.
#' @param segments List of segment specifications. Each segment must include
#'   `segment_id`, `pseudotime`, `lineage`, and `order`; it may include
#'   `model`, `lineage_weights`, `path`, `start_label`, and `end_label`.
#' @param composite_id Optional stable trajectory composite id.
#' @param composite_key Key used in the output `cell_vector_family`.
#' @param join_policy Currently only `"waypoint_collapse"` is supported.
#' @param min_weight Optional minimum lineage weight required for segment-local
#'   membership when `lineage_weights` is supplied.
#' @param allow_legacy Passed to trajectory fit-family compatibility checks.
#' @param runs Optional session runs for resolving run refs.
#'
#' @return List with promotable primitives: `composite_pseudotime`,
#'   `segment_local_table`, `composite_manifest`, and `composite_membership`.
#' @export
wb_op_trajectory_segment_join <- function(bundle,
                                          segments,
                                          composite_id = NULL,
                                          composite_key = NULL,
                                          join_policy = "waypoint_collapse",
                                          min_weight = NULL,
                                          allow_legacy = FALSE,
                                          runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  .wb_assert(is.list(segments) && length(segments) >= 2L,
             "trajectory_segment_join(): segments must be a list with at least two entries.")
  join_policy <- as.character(join_policy %||% "")[1]
  .wb_assert(identical(join_policy, "waypoint_collapse"),
             "trajectory_segment_join(): only join_policy='waypoint_collapse' is supported in v1.")
  if (!is.null(min_weight)) {
    min_weight <- suppressWarnings(as.numeric(min_weight)[1])
    .wb_assert(is.finite(min_weight), "min_weight must be numeric when supplied.")
  }

  seg_rows <- vector("list", length(segments))
  meta_rows <- vector("list", length(segments))
  segment_ids <- character(length(segments))
  segment_orders <- numeric(length(segments))

  for (i in seq_along(segments)) {
    seg <- segments[[i]]
    segment_id <- as.character(seg$segment_id %||% paste0("segment", i))[1]
    segment_id <- gsub("[^A-Za-z0-9_.:-]+", "_", segment_id)
    .wb_assert(nzchar(segment_id), "trajectory_segment_join(): segment_id must be non-empty.")
    order <- suppressWarnings(as.numeric(seg$order %||% i))[1]
    .wb_assert(is.finite(order), paste0("trajectory_segment_join(): invalid order for segment ", segment_id, "."))
    lineage <- as.character(seg$lineage %||% "")[1]
    .wb_assert(nzchar(lineage), paste0("trajectory_segment_join(): missing lineage for segment ", segment_id, "."))

    info <- .wb_validate_trajectory_segment(bundle, seg, runs = runs, allow_legacy = allow_legacy)
    pt <- .wb_segment_resolve_primitive(bundle, seg$pseudotime, runs = runs, expected_kind = "cell_vector_family",
                                        label = paste0(segment_id, " pseudotime"))
    pt_df <- .wb_segment_family_values(pt, lineage, label = paste0(segment_id, " pseudotime"))
    pt_df <- pt_df[is.finite(pt_df$value), , drop = FALSE]
    .wb_assert(nrow(pt_df) > 0L, paste0("trajectory_segment_join(): no finite pseudotime values for segment ", segment_id, "."))

    wt_df <- data.frame(cell_id = pt_df$cell_id, local_weight = NA_real_, stringsAsFactors = FALSE)
    if (!is.null(seg$lineage_weights)) {
      wt <- .wb_segment_resolve_primitive(bundle, seg$lineage_weights, runs = runs, expected_kind = "cell_vector_family",
                                          label = paste0(segment_id, " lineage_weights"))
      w0 <- .wb_segment_family_values(wt, lineage, label = paste0(segment_id, " lineage_weights"))
      names(w0)[names(w0) == "value"] <- "local_weight"
      wt_df <- merge(data.frame(cell_id = pt_df$cell_id, stringsAsFactors = FALSE), w0, by = "cell_id", all.x = TRUE, sort = FALSE)
    }

    dat <- merge(pt_df, wt_df, by = "cell_id", all.x = TRUE, sort = FALSE)
    names(dat)[names(dat) == "value"] <- "local_pseudotime"
    if (!is.null(min_weight)) {
      dat <- dat[!is.na(dat$local_weight) & dat$local_weight >= min_weight, , drop = FALSE]
      .wb_assert(nrow(dat) > 0L, paste0("trajectory_segment_join(): no cells remain after min_weight for segment ", segment_id, "."))
    }
    dat$local_pseudotime_scaled <- .wb_segment_scale01(dat$local_pseudotime)
    dat$segment_id <- segment_id
    dat$segment_order <- order
    dat$lineage_id <- lineage
    dat$segment_role <- "segment"

    segment_ids[i] <- segment_id
    segment_orders[i] <- order
    seg_rows[[i]] <- dat[, c(
      "cell_id", "segment_id", "segment_order", "lineage_id",
      "local_pseudotime", "local_pseudotime_scaled", "local_weight", "segment_role"
    ), drop = FALSE]

    meta_rows[[i]] <- data.frame(
      segment_id = segment_id,
      segment_order = order,
      lineage_id = lineage,
      trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
      trajectory_engine = as.character(info$engine[1] %||% ""),
      model_artifact_id = .wb_segment_ref_artifact_id(seg$model),
      pseudotime_artifact_id = .wb_segment_ref_artifact_id(seg$pseudotime),
      lineage_weights_artifact_id = .wb_segment_ref_artifact_id(seg$lineage_weights),
      path_artifact_id = .wb_segment_ref_artifact_id(seg$path),
      start_label = as.character(seg$start_label %||% "")[1],
      end_label = as.character(seg$end_label %||% "")[1],
      n_segment_cells = nrow(dat),
      stringsAsFactors = FALSE
    )
  }

  .wb_assert(!anyDuplicated(segment_ids), "trajectory_segment_join(): segment_id values must be unique.")
  .wb_assert(!anyDuplicated(segment_orders), "trajectory_segment_join(): segment order values must be unique.")
  ord <- order(segment_orders, segment_ids)
  seg_rows <- seg_rows[ord]
  meta_rows <- meta_rows[ord]
  segment_ids <- segment_ids[ord]

  local <- do.call(rbind, seg_rows)
  manifest <- do.call(rbind, meta_rows)
  rownames(local) <- NULL
  rownames(manifest) <- NULL
  manifest$segment_index <- seq_len(nrow(manifest))
  idx_map <- stats::setNames(manifest$segment_index, manifest$segment_id)
  local$segment_index <- unname(idx_map[local$segment_id])
  local$composite_candidate <- (local$segment_index - 1L) + local$local_pseudotime_scaled

  split_rows <- split(seq_len(nrow(local)), local$cell_id)
  comp_rows <- lapply(names(split_rows), function(cid) {
    ii <- split_rows[[cid]]
    seg_idx <- sort(unique(local$segment_index[ii]))
    if (length(seg_idx) == 1L) {
      data.frame(
        cell_id = cid,
        composite_pseudotime = local$composite_candidate[ii[1]],
        composite_segment_assignment = as.character(local$segment_id[ii[1]]),
        composite_membership_role = "segment_unique",
        contributing_segments = as.character(local$segment_id[ii[1]]),
        stringsAsFactors = FALSE
      )
    } else {
      adjacent <- length(seg_idx) == 2L && diff(seg_idx) == 1L
      if (!adjacent) {
        stop(
          paste0(
            "trajectory_segment_join(): cell '", cid,
            "' appears in non-adjacent or multi-segment overlap; waypoint_collapse v1 only supports adjacent pair overlaps."
          ),
          call. = FALSE
        )
      }
      data.frame(
        cell_id = cid,
        composite_pseudotime = min(seg_idx),
        composite_segment_assignment = "waypoint",
        composite_membership_role = "waypoint_overlap",
        contributing_segments = paste(sort(unique(as.character(local$segment_id[ii]))), collapse = "|"),
        stringsAsFactors = FALSE
      )
    }
  })
  comp <- do.call(rbind, comp_rows)
  rownames(comp) <- NULL

  waypoint_cells <- comp$cell_id[identical(FALSE, is.null(comp$composite_membership_role)) &
                                  comp$composite_membership_role == "waypoint_overlap"]
  if (length(waypoint_cells)) {
    is_wp <- local$cell_id %in% waypoint_cells
    for (cid in waypoint_cells) {
      ii <- which(local$cell_id == cid)
      min_i <- min(local$segment_index[ii])
      max_i <- max(local$segment_index[ii])
      local$segment_role[ii[local$segment_index[ii] == min_i]] <- "waypoint_arrival"
      local$segment_role[ii[local$segment_index[ii] == max_i]] <- "waypoint_departure"
    }
  }

  composite_id <- as.character(composite_id %||% .wb_new_trajectory_composite_id(segment_ids[1]))[1]
  composite_key <- as.character(composite_key %||% "composite_L1")[1]
  .wb_assert(nzchar(composite_id), "composite_id must be non-empty.")
  .wb_assert(nzchar(composite_key), "composite_key must be non-empty.")

  parent_fit_ids <- unique(as.character(manifest$trajectory_fit_id))
  parent_fit_ids <- parent_fit_ids[nzchar(parent_fit_ids)]
  meta <- list(
    trajectory_composite_id = composite_id,
    family_kind = "trajectory_composite_pseudotime",
    value_semantics = "segmented_composite_pseudotime",
    join_policy = join_policy,
    scaling_rule = "segment-local min-max pseudotime scaled to [0,1]",
    overlap_handling_rule = "adjacent overlaps collapse to the shared boundary without averaging",
    parent_segment_ids = segment_ids,
    parent_trajectory_fit_ids = parent_fit_ids,
    n_segments = length(segment_ids),
    n_cells = nrow(comp),
    n_waypoint_cells = length(waypoint_cells)
  )

  manifest$trajectory_composite_id <- composite_id
  manifest$join_policy <- join_policy
  manifest$scaling_rule <- meta$scaling_rule
  manifest$overlap_handling_rule <- meta$overlap_handling_rule
  manifest$n_unique_cells <- vapply(manifest$segment_id, function(sid) {
    sum(comp$composite_segment_assignment == sid)
  }, integer(1))
  manifest$n_waypoint_cells <- length(waypoint_cells)
  manifest$caveats <- "Composite pseudotime is derived from separately fitted trajectory segments; parent model RDS objects are not merged."
  manifest <- manifest[, c(
    "trajectory_composite_id", "segment_id", "segment_order", "segment_index",
    "lineage_id", "trajectory_fit_id", "trajectory_engine",
    "model_artifact_id", "pseudotime_artifact_id", "lineage_weights_artifact_id", "path_artifact_id",
    "start_label", "end_label", "join_policy", "scaling_rule", "overlap_handling_rule",
    "n_segment_cells", "n_unique_cells", "n_waypoint_cells", "caveats"
  ), drop = FALSE]

  local$trajectory_composite_id <- composite_id
  local <- local[, c(
    "trajectory_composite_id", "cell_id", "segment_id", "segment_order", "segment_index",
    "lineage_id", "local_pseudotime", "local_pseudotime_scaled", "local_weight",
    "segment_role", "composite_candidate"
  ), drop = FALSE]

  membership <- setNames(as.character(comp$composite_segment_assignment), as.character(comp$cell_id))

  list(
    outputs = list(
      composite_pseudotime = wb_prim_cell_vector_family(
        key = rep(composite_key, nrow(comp)),
        cell_id = comp$cell_id,
        value = comp$composite_pseudotime,
        value_type = "continuous",
        meta = meta
      ),
      segment_local_table = wb_prim_obs_table(
        local,
        table_type = "trajectory_segment_local_membership",
        entity_kind = "cell_segment",
        meta = meta
      ),
      composite_manifest = wb_prim_obs_table(
        manifest,
        table_type = "trajectory_segment_join_manifest",
        entity_kind = "trajectory_segment",
        meta = meta
      ),
      composite_membership = wb_prim_cell_vector(
        membership,
        value_type = "categorical"
      )
    ),
    params = list(
      trajectory_composite_id = composite_id,
      composite_key = composite_key,
      join_policy = join_policy,
      min_weight = min_weight,
      n_segments = length(segment_ids),
      n_cells = nrow(comp),
      n_waypoint_cells = length(waypoint_cells),
      parent_segment_ids = segment_ids,
      parent_trajectory_fit_ids = parent_fit_ids
    )
  )
}

.wb_segment_path_values <- function(prim, lineage, label = "path_2d_family") {
  .wb_assert_kind(prim, "path_2d_family", where = paste0(" for ", label))
  lineage <- as.character(lineage %||% "")[1]
  .wb_assert(nzchar(lineage), "trajectory_segment_path_join(): lineage must be a single non-empty string.")
  key <- as.character(prim$key)
  hit <- key == lineage
  .wb_assert(any(hit), paste0("trajectory_segment_path_join(): lineage '", lineage, "' not found in ", label, "."))
  out <- data.frame(
    lineage_id = key[hit],
    point = as.integer(prim$point[hit]),
    x = as.numeric(prim$x[hit]),
    y = as.numeric(prim$y[hit]),
    stringsAsFactors = FALSE
  )
  out <- out[is.finite(out$point) & is.finite(out$x) & is.finite(out$y), , drop = FALSE]
  .wb_assert(nrow(out) > 0L, paste0("trajectory_segment_path_join(): no finite path points for ", label, "."))
  out[order(out$point), , drop = FALSE]
}

#' Join Display Paths For A Segmented Composite Trajectory
#'
#' Derives a display-only composite `path_2d_family` from ordered parent
#' `path_2d_family` segment artifacts. This does not merge or refit parent
#' trajectory models.
#'
#' @param bundle Open scworkbench bundle.
#' @param paths List of path segment specs. Each requires `segment_id`, `path`,
#'   `lineage`, and `order`; labels are optional.
#' @param composite_id Optional trajectory composite id.
#' @param composite_key Key for the output path family.
#' @param allow_legacy Allow missing parent `trajectory_fit_id` with warning.
#'
#' @return Standard op result with `curves` and `path_manifest`.
#' @export
wb_op_trajectory_segment_path_join <- function(bundle,
                                               paths,
                                               composite_id = NULL,
                                               composite_key = NULL,
                                               allow_legacy = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  .wb_assert(is.list(paths) && length(paths) >= 2L,
             "trajectory_segment_path_join(): paths must be a list with at least two entries.")

  rows <- vector("list", length(paths))
  manifests <- vector("list", length(paths))
  segment_ids <- character(length(paths))
  segment_orders <- numeric(length(paths))

  for (i in seq_along(paths)) {
    seg <- paths[[i]]
    .wb_assert(is.list(seg), "trajectory_segment_path_join(): each path segment must be a list.")
    segment_id <- as.character(seg$segment_id %||% paste0("segment", i))[1]
    segment_id <- gsub("[^A-Za-z0-9_.:-]+", "_", segment_id)
    order <- suppressWarnings(as.numeric(seg$order %||% i))[1]
    lineage <- as.character(seg$lineage %||% "")[1]
    .wb_assert(nzchar(segment_id), "trajectory_segment_path_join(): segment_id must be non-empty.")
    .wb_assert(is.finite(order), paste0("trajectory_segment_path_join(): invalid order for segment ", segment_id, "."))
    .wb_assert(nzchar(lineage), paste0("trajectory_segment_path_join(): missing lineage for segment ", segment_id, "."))
    .wb_assert(!is.null(seg$path), paste0("trajectory_segment_path_join(): missing path for segment ", segment_id, "."))

    info <- wb_trajectory_fit_info(bundle, seg$path)
    if (!nzchar(as.character(info$trajectory_fit_id[1] %||% ""))) {
      msg <- "trajectory_segment_path_join(): parent path is missing trajectory_fit_id; legacy paths cannot be joined without explicit allow_legacy=TRUE."
      if (isTRUE(allow_legacy)) warning(msg, call. = FALSE) else stop(msg, call. = FALSE)
    }
    prim <- .wb_segment_resolve_primitive(bundle, seg$path, expected_kind = "path_2d_family",
                                          label = paste0(segment_id, " path"))
    pv <- .wb_segment_path_values(prim, lineage, label = paste0(segment_id, " path"))
    pv$segment_id <- segment_id
    pv$segment_order <- order
    pv$source_lineage_id <- lineage

    segment_ids[i] <- segment_id
    segment_orders[i] <- order
    rows[[i]] <- pv
    manifests[[i]] <- data.frame(
      segment_id = segment_id,
      segment_order = order,
      lineage_id = lineage,
      trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
      trajectory_engine = as.character(info$engine[1] %||% ""),
      path_artifact_id = .wb_segment_ref_artifact_id(seg$path),
      start_label = as.character(seg$start_label %||% "")[1],
      end_label = as.character(seg$end_label %||% "")[1],
      n_path_points = nrow(pv),
      stringsAsFactors = FALSE
    )
  }

  .wb_assert(!anyDuplicated(segment_ids), "trajectory_segment_path_join(): segment_id values must be unique.")
  .wb_assert(!anyDuplicated(segment_orders), "trajectory_segment_path_join(): segment order values must be unique.")
  ord <- order(segment_orders, segment_ids)
  rows <- rows[ord]
  manifests <- manifests[ord]
  segment_ids <- segment_ids[ord]

  composite_id <- as.character(composite_id %||% .wb_new_trajectory_composite_id(segment_ids[1]))[1]
  composite_key <- as.character(composite_key %||% "composite_path")[1]
  .wb_assert(nzchar(composite_id), "composite_id must be non-empty.")
  .wb_assert(nzchar(composite_key), "composite_key must be non-empty.")

  joined <- do.call(rbind, rows)
  manifest <- do.call(rbind, manifests)
  rownames(joined) <- NULL
  rownames(manifest) <- NULL
  manifest$segment_index <- seq_len(nrow(manifest))
  idx_map <- stats::setNames(manifest$segment_index, manifest$segment_id)
  joined$segment_index <- unname(idx_map[joined$segment_id])
  joined$composite_point <- seq_len(nrow(joined))

  manifest$trajectory_composite_id <- composite_id
  manifest$composite_key <- composite_key
  manifest$composite_point_start <- vapply(manifest$segment_id, function(sid) min(joined$composite_point[joined$segment_id == sid]), integer(1))
  manifest$composite_point_end <- vapply(manifest$segment_id, function(sid) max(joined$composite_point[joined$segment_id == sid]), integer(1))
  manifest$caveats <- "Derived display path from separately fitted segment paths; no parent trajectory model objects were merged."
  manifest <- manifest[, c(
    "trajectory_composite_id", "composite_key", "segment_id", "segment_order", "segment_index",
    "lineage_id", "trajectory_fit_id", "trajectory_engine", "path_artifact_id",
    "start_label", "end_label", "n_path_points", "composite_point_start", "composite_point_end", "caveats"
  ), drop = FALSE]

  parent_fit_ids <- unique(as.character(manifest$trajectory_fit_id))
  parent_fit_ids <- parent_fit_ids[nzchar(parent_fit_ids)]
  meta <- list(
    trajectory_composite_id = composite_id,
    family_kind = "trajectory_composite_display_path",
    value_semantics = "derived_segmented_display_geometry",
    parent_segment_ids = segment_ids,
    parent_trajectory_fit_ids = parent_fit_ids,
    n_segments = length(segment_ids),
    n_points = nrow(joined),
    caveat = "Display geometry only; not a merged fitted model."
  )

  list(
    outputs = list(
      curves = wb_prim_path_2d_family(
        key = rep(composite_key, nrow(joined)),
        point = joined$composite_point,
        x = joined$x,
        y = joined$y,
        meta = meta
      ),
      path_manifest = wb_prim_obs_table(
        manifest,
        table_type = "trajectory_segment_path_join_manifest",
        entity_kind = "trajectory_segment",
        meta = meta
      )
    ),
    params = list(
      trajectory_composite_id = composite_id,
      composite_key = composite_key,
      n_segments = length(segment_ids),
      n_points = nrow(joined),
      parent_segment_ids = segment_ids,
      parent_trajectory_fit_ids = parent_fit_ids
    )
  )
}
