.wb_new_trajectory_composite_id <- function(label = "composite") {
  safe <- gsub("[^A-Za-z0-9_]+", "_", as.character(label %||% "composite")[1])
  safe <- gsub("^_+|_+$", "", safe)
  if (!nzchar(safe)) safe <- "composite"
  .wb_allocate_identifier(
    paste0("trajcomp_", safe, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
    8L, purpose = "trajectory composite"
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

.wb_segment_clean_source_kind <- function(x) {
  x <- as.character(x %||% "fitted_model")[1]
  if (!nzchar(x)) x <- "fitted_model"
  allowed <- c(.wb_segment_implemented_source_kinds(), .wb_segment_reserved_source_kinds())
  .wb_assert(x %in% allowed, paste0("trajectory segment source_kind must be one of: ", paste(allowed, collapse = ", ")))
  x
}

.wb_segment_implemented_source_kinds <- function() c("fitted_model", "space_path_bridge")

.wb_segment_reserved_source_kinds <- function() c("graph_path_bridge", "imported_pseudotime", "manual_pseudotime", "composite")

.wb_segment_assert_implemented_source_kind <- function(source_kind) {
  source_kind <- .wb_segment_clean_source_kind(source_kind)
  .wb_assert(
    source_kind %in% .wb_segment_implemented_source_kinds(),
    paste0(
      "trajectory segment source_kind '", source_kind,
      "' is reserved but not currently implemented. Implemented source kinds: ",
      paste(.wb_segment_implemented_source_kinds(), collapse = ", "),
      "."
    )
  )
  source_kind
}

.wb_segment_clean_source_engine <- function(x, source_kind = NULL) {
  if (is.null(x) || !nzchar(as.character(x)[1])) {
    if (identical(source_kind, "space_path_bridge")) return("space_path")
    if (identical(source_kind, "manual_pseudotime")) return("manual")
    if (identical(source_kind, "imported_pseudotime")) return("imported")
    if (identical(source_kind, "graph_path_bridge")) return("graph")
    return("unknown")
  }
  x <- as.character(x)[1]
  allowed <- c("slingshot", "monocle3", "palantir", "space_path", "manual", "imported", "graph", "unknown")
  .wb_assert(x %in% allowed, paste0("trajectory segment source_engine must be one of: ", paste(allowed, collapse = ", ")))
  x
}

.wb_segment_membership_cells <- function(bundle, membership, runs = NULL) {
  if (is.null(membership)) return(NULL)
  if (.wb_is_primitive(membership)) {
    .wb_assert_kind(membership, "cell_vector", where = " for segment membership")
    vals <- as.character(membership$value %||% character(0))
    cells <- as.character(membership$cell_id %||% character(0))
    keep <- nzchar(cells) & !is.na(vals) & nzchar(vals)
    return(unique(cells[keep]))
  }
  aid <- .wb_ref_to_artifact_id(membership)
  if (!is.null(aid) && nzchar(as.character(aid)[1])) {
    prim <- wb_art_load(bundle, as.character(aid)[1], expected_kind = "cell_vector")
    return(.wb_segment_membership_cells(bundle, prim, runs = runs))
  }
  if (is.character(membership)) {
    x <- as.character(membership)
    x <- x[nzchar(x)]
    if (length(x) == 1L && startsWith(x, "artifact:")) {
      prim <- wb_art_load(bundle, sub("^artifact:", "", x), expected_kind = "cell_vector")
      return(.wb_segment_membership_cells(bundle, prim, runs = runs))
    }
    if (length(x) == 1L && (identical(x, "all") || startsWith(x, "set:"))) {
      return(as.character(wb_cells(bundle, cell_set = x)))
    }
    return(unique(x))
  }
  stop("trajectory segment membership must be a cell_vector primitive/artifact, cell set, or cell_id vector.", call. = FALSE)
}

.wb_segment_vector_values <- function(bundle, x, key = NULL, runs = NULL, expected_label = "segment vector") {
  if (is.null(x)) return(NULL)
  prim <- .wb_segment_resolve_primitive(bundle, x, runs = runs, expected_kind = NULL, label = expected_label)
  kind <- as.character(prim$kind %||% "")[1]
  if (identical(kind, "cell_vector")) {
    return(data.frame(
      cell_id = as.character(prim$cell_id),
      value = suppressWarnings(as.numeric(prim$value)),
      stringsAsFactors = FALSE
    ))
  }
  if (identical(kind, "cell_vector_family")) {
    key <- as.character(key %||% "")[1]
    .wb_assert(nzchar(key), paste0(expected_label, ": key is required for cell_vector_family."))
    return(.wb_segment_family_values(prim, key, label = expected_label))
  }
  stop(expected_label, " must be a cell_vector or cell_vector_family.", call. = FALSE)
}

.wb_validate_trajectory_segment <- function(bundle, segment, runs = NULL, allow_legacy = FALSE) {
  .wb_assert(is.list(segment), "trajectory_segment_join(): each segment must be a list.")
  .wb_assert(!is.null(segment$pseudotime), "trajectory_segment_join(): each segment requires pseudotime.")
  .wb_assert(!is.null(segment$lineage), "trajectory_segment_join(): each segment requires lineage.")

  source_kind <- .wb_segment_clean_source_kind(segment$source_kind %||% "fitted_model")
  .wb_segment_assert_implemented_source_kind(source_kind)
  source_engine <- .wb_segment_clean_source_engine(segment$source_engine %||% NULL, source_kind = source_kind)

  if (!identical(source_kind, "fitted_model")) {
    info <- wb_trajectory_fit_info(bundle, segment$pseudotime, runs = runs)
    info$engine <- source_engine
    return(info)
  }

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
  if (!nzchar(as.character(info$engine[1] %||% ""))) info$engine <- source_engine
  info
}

#' Create A Trajectory Segment From Fitted Trajectory Artifacts
#'
#' Materializes the generic segment contract for fitted-model trajectory
#' artifacts. This validates fit-family compatibility and emits the same
#' pseudotime/membership/confidence/manifest shape used by other segment
#' adapters.
#'
#' @export
wb_op_trajectory_segment_from_artifacts <- function(bundle,
                                                    pseudotime,
                                                    lineage,
                                                    segment_id,
                                                    segment_order = 1L,
                                                    model = NULL,
                                                    lineage_weights = NULL,
                                                    membership = NULL,
                                                    confidence = NULL,
                                                    confidence_key = NULL,
                                                    path = NULL,
                                                    source_engine = NULL,
                                                    start_label = NULL,
                                                    end_label = NULL,
                                                    composite_id = NULL,
                                                    runs = NULL,
                                                    allow_legacy = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  segment_id <- gsub("[^A-Za-z0-9_.:-]+", "_", as.character(segment_id %||% "")[1])
  .wb_assert(nzchar(segment_id), "trajectory_segment_from_artifacts(): segment_id must be non-empty.")
  segment_order <- suppressWarnings(as.numeric(segment_order)[1])
  .wb_assert(is.finite(segment_order), "trajectory_segment_from_artifacts(): segment_order must be numeric.")
  lineage <- as.character(lineage %||% "")[1]
  .wb_assert(nzchar(lineage), "trajectory_segment_from_artifacts(): lineage must be non-empty.")

  seg <- list(
    segment_id = segment_id,
    order = segment_order,
    source_kind = "fitted_model",
    source_engine = source_engine %||% NULL,
    model = model,
    pseudotime = pseudotime,
    lineage = lineage,
    lineage_weights = lineage_weights,
    membership = membership,
    confidence = confidence,
    confidence_key = confidence_key,
    path = path,
    start_label = start_label,
    end_label = end_label
  )
  info <- .wb_validate_trajectory_segment(bundle, seg, runs = runs, allow_legacy = allow_legacy)
  source_engine <- .wb_segment_clean_source_engine(source_engine %||% info$engine[1] %||% NULL, source_kind = "fitted_model")
  pt <- .wb_segment_resolve_primitive(bundle, pseudotime, runs = runs, expected_kind = "cell_vector_family",
                                      label = paste0(segment_id, " pseudotime"))
  pt_df <- .wb_segment_family_values(pt, lineage, label = paste0(segment_id, " pseudotime"))
  pt_df <- pt_df[is.finite(pt_df$value), , drop = FALSE]
  .wb_assert(nrow(pt_df) > 0L, paste0("trajectory_segment_from_artifacts(): no finite pseudotime values for segment ", segment_id, "."))

  membership_cells <- .wb_segment_membership_cells(bundle, membership, runs = runs)
  if (!is.null(membership_cells)) {
    pt_df <- pt_df[pt_df$cell_id %in% membership_cells, , drop = FALSE]
    .wb_assert(nrow(pt_df) > 0L, paste0("trajectory_segment_from_artifacts(): no pseudotime cells remain after membership filter for segment ", segment_id, "."))
  }

  membership_vec <- stats::setNames(rep(segment_id, nrow(pt_df)), pt_df$cell_id)
  conf_key <- as.character(confidence_key %||% lineage)[1]
  if (!is.null(confidence)) {
    conf_df <- .wb_segment_vector_values(bundle, confidence, key = conf_key, runs = runs,
                                         expected_label = paste0(segment_id, " confidence"))
    conf_df <- conf_df[conf_df$cell_id %in% pt_df$cell_id, , drop = FALSE]
  } else if (!is.null(lineage_weights)) {
    conf_df <- .wb_segment_vector_values(bundle, lineage_weights, key = lineage, runs = runs,
                                         expected_label = paste0(segment_id, " lineage_weights"))
    conf_df <- conf_df[conf_df$cell_id %in% pt_df$cell_id, , drop = FALSE]
    conf_key <- lineage
  } else {
    conf_df <- data.frame(cell_id = pt_df$cell_id, value = rep(1, nrow(pt_df)), stringsAsFactors = FALSE)
  }

  composite_id <- as.character(composite_id %||% "")[1]
  manifest <- data.frame(
    trajectory_composite_id = composite_id,
    segment_id = segment_id,
    segment_order = segment_order,
    source_kind = "fitted_model",
    source_engine = source_engine,
    lineage_id = lineage,
    source_pseudotime_key = lineage,
    confidence_key = conf_key,
    trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
    model_artifact_id = .wb_segment_ref_artifact_id(model),
    pseudotime_artifact_id = .wb_segment_ref_artifact_id(pseudotime),
    membership_artifact_id = .wb_segment_ref_artifact_id(membership),
    lineage_weights_artifact_id = .wb_segment_ref_artifact_id(lineage_weights),
    confidence_artifact_id = .wb_segment_ref_artifact_id(confidence),
    path_artifact_id = .wb_segment_ref_artifact_id(path),
    start_label = as.character(start_label %||% "")[1],
    end_label = as.character(end_label %||% "")[1],
    normalization_rule = "segment-local min-max pseudotime scaled to [0,1]",
    boundary_policy = "exact_boundary_collapse",
    membership_rule = if (is.null(membership)) "all finite pseudotime cells" else "explicit membership intersection",
    n_segment_cells = nrow(pt_df),
    caveats = "Fitted-model segment: parent trajectory model artifacts remain separate; this adapter materializes segment-local contract state.",
    stringsAsFactors = FALSE
  )
  meta <- list(
    segment_id = segment_id,
    segment_order = segment_order,
    source_kind = "fitted_model",
    source_engine = source_engine,
    trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
    value_semantics = "trajectory_segment_fitted_pseudotime",
    normalization_rule = "segment-local min-max pseudotime scaled to [0,1]",
    boundary_policy = "exact_boundary_collapse"
  )

  list(
    outputs = list(
      pseudotime = wb_prim_cell_vector_family(
        key = rep(lineage, nrow(pt_df)),
        cell_id = pt_df$cell_id,
        value = pt_df$value,
        value_type = "continuous",
        meta = meta
      ),
      membership = wb_prim_cell_vector(membership_vec, value_type = "categorical"),
      confidence = wb_prim_cell_vector_family(
        key = rep(conf_key, nrow(conf_df)),
        cell_id = conf_df$cell_id,
        value = suppressWarnings(as.numeric(conf_df$value)),
        value_type = "continuous",
        meta = c(meta, list(value_semantics = "segment_confidence_or_membership_weight"))
      ),
      segment_manifest = wb_prim_obs_table(
        manifest,
        table_type = "trajectory_segment_manifest",
        entity_kind = "trajectory_segment",
        meta = meta
      )
    ),
    params = list(
      segment_id = segment_id,
      segment_order = segment_order,
      source_kind = "fitted_model",
      source_engine = source_engine,
      pseudotime_key = lineage,
      confidence_key = conf_key,
      trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
      n_cells = nrow(pt_df)
    )
  )
}

.wb_space_path_score_values <- function(path_scores, key) {
  .wb_assert_kind(path_scores, "cell_vector_family", where = " for path_scores")
  .wb_segment_family_values(path_scores, key, label = paste0("path_scores/", key))
}

#' Create A Trajectory Segment From Space-Path Scores
#'
#' Converts `scwbtrajectory::space_path_score` output into a generic trajectory
#' segment payload.
#' The analytical coordinate is path arclength progress, and membership is based
#' on an explicit distance-to-path rule.
#'
#' @export
wb_op_trajectory_space_path_segment <- function(bundle,
                                                path_scores,
                                                segment_id,
                                                segment_order = 1L,
                                                score_prefix = NULL,
                                                candidate_cells = NULL,
                                                distance_threshold = NULL,
                                                distance_quantile = NULL,
                                                start_label = NULL,
                                                end_label = NULL,
                                                path = NULL,
                                                display_path = NULL,
                                                display_lineage = NULL,
                                                display_space_id = NULL,
                                                start_endpoint = NULL,
                                                end_endpoint = NULL,
                                                start_cell_set = NULL,
                                                end_cell_set = NULL,
                                                endpoint_summary_method = "centroid",
                                                endpoint_max_distance = NULL,
                                                endpoint_qc_action = "fail",
                                                composite_id = NULL,
                                                pseudotime_key = NULL,
                                                confidence_key = NULL,
                                                runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  .wb_assert_kind(path_scores, "cell_vector_family")
  segment_id <- gsub("[^A-Za-z0-9_.:-]+", "_", as.character(segment_id %||% "")[1])
  .wb_assert(nzchar(segment_id), "trajectory_space_path_segment(): segment_id must be non-empty.")
  segment_order <- suppressWarnings(as.numeric(segment_order)[1])
  .wb_assert(is.finite(segment_order), "trajectory_space_path_segment(): segment_order must be numeric.")

  prefix <- as.character(score_prefix %||% "")[1]
  key_of <- function(x) if (nzchar(prefix)) paste0(prefix, x) else x
  progress_key <- key_of("progress")
  distance_key <- key_of("distance")
  pt_key <- as.character(pseudotime_key %||% segment_id)[1]
  conf_key <- as.character(confidence_key %||% segment_id)[1]

  prog <- .wb_space_path_score_values(path_scores, progress_key)
  dist <- .wb_space_path_score_values(path_scores, distance_key)
  names(prog)[names(prog) == "value"] <- "progress"
  names(dist)[names(dist) == "value"] <- "distance"
  score <- merge(prog, dist, by = "cell_id", all = FALSE, sort = FALSE)
  score$progress <- suppressWarnings(as.numeric(score$progress))
  score$distance <- suppressWarnings(as.numeric(score$distance))
  score <- score[is.finite(score$progress) & is.finite(score$distance), , drop = FALSE]
  .wb_assert(nrow(score) > 0L, "trajectory_space_path_segment(): no finite progress/distance rows.")

  cand <- .wb_segment_membership_cells(bundle, candidate_cells, runs = runs)
  if (!is.null(cand)) {
    score <- score[score$cell_id %in% cand, , drop = FALSE]
    .wb_assert(nrow(score) > 0L, "trajectory_space_path_segment(): no scored cells remain after candidate filter.")
  }

  distance_threshold <- suppressWarnings(as.numeric(distance_threshold)[1])
  distance_quantile <- suppressWarnings(as.numeric(distance_quantile)[1])
  if (is.finite(distance_threshold)) {
    threshold <- distance_threshold
    membership_rule <- paste0("distance_to_path <= ", signif(threshold, 6))
  } else if (is.finite(distance_quantile)) {
    .wb_assert(distance_quantile > 0 && distance_quantile <= 1,
               "trajectory_space_path_segment(): distance_quantile must be in (0, 1].")
    threshold <- as.numeric(stats::quantile(score$distance, probs = distance_quantile, names = FALSE, na.rm = TRUE))
    membership_rule <- paste0("distance_to_path <= quantile(distance, ", signif(distance_quantile, 6), ")")
  } else {
    threshold <- Inf
    membership_rule <- "all finite path-scored candidate cells"
  }
  keep <- if (is.finite(threshold)) score$distance <= threshold else rep(TRUE, nrow(score))
  score <- score[keep, , drop = FALSE]
  .wb_assert(nrow(score) > 0L, "trajectory_space_path_segment(): no cells pass the distance membership rule.")

  confidence <- if (is.finite(threshold) && threshold > 0) {
    pmax(0, pmin(1, 1 - (score$distance / threshold)))
  } else {
    1 / (1 + score$distance)
  }

  composite_id <- as.character(composite_id %||% "")[1]
  manifest <- data.frame(
    trajectory_composite_id = composite_id,
    segment_id = segment_id,
    segment_order = segment_order,
    source_kind = "space_path_bridge",
    source_engine = "space_path",
    lineage_id = pt_key,
    source_pseudotime_key = progress_key,
    confidence_key = conf_key,
    path_artifact_id = .wb_segment_ref_artifact_id(path),
    display_path_artifact_id = .wb_segment_ref_artifact_id(display_path),
    path_scores_artifact_id = .wb_segment_ref_artifact_id(path_scores),
    start_label = as.character(start_label %||% "")[1],
    end_label = as.character(end_label %||% "")[1],
    normalization_rule = "path_progress_0_1",
    boundary_policy = "exact_boundary_collapse",
    membership_rule = membership_rule,
    distance_threshold = if (is.finite(threshold)) threshold else NA_real_,
    n_candidate_cells = if (is.null(cand)) nrow(prog) else length(unique(cand)),
    n_segment_cells = nrow(score),
    caveats = "Space-path bridge segment: pseudotime is path arclength progress; confidence is distance-derived; no fitted trajectory model is implied.",
    stringsAsFactors = FALSE
  )

  meta <- list(
    segment_id = segment_id,
    segment_order = segment_order,
    source_kind = "space_path_bridge",
    source_engine = "space_path",
    value_semantics = "trajectory_segment_path_progress",
    normalization_rule = "path_progress_0_1",
    boundary_policy = "exact_boundary_collapse",
    membership_rule = membership_rule
  )
  outputs <- list(
    pseudotime = wb_prim_cell_vector_family(
      key = rep(pt_key, nrow(score)),
      cell_id = score$cell_id,
      value = score$progress,
      value_type = "continuous",
      meta = meta
    ),
    membership = wb_prim_cell_vector(
      stats::setNames(rep(segment_id, nrow(score)), score$cell_id),
      value_type = "categorical"
    ),
    confidence = wb_prim_cell_vector_family(
      key = rep(conf_key, nrow(score)),
      cell_id = score$cell_id,
      value = confidence,
      value_type = "continuous",
      meta = c(meta, list(value_semantics = "distance_derived_segment_confidence"))
    ),
    segment_manifest = wb_prim_obs_table(
      manifest,
      table_type = "trajectory_segment_manifest",
      entity_kind = "trajectory_segment",
      meta = meta
    )
  )
  if (!is.null(display_path)) {
    display_prim <- .wb_segment_resolve_primitive(bundle, display_path, runs = runs, expected_kind = "path_2d_family",
                                                  label = paste0(segment_id, " display_path"))
    display_lineage <- as.character(display_lineage %||% "")[1]
    display_xy <- .wb_segment_path_values(display_prim, display_lineage, label = paste0(segment_id, " display_path"))
    endpoint_qc <- .wb_display_endpoint_qc(
      bundle = bundle,
      segment_id = segment_id,
      path_xy = display_xy,
      start_endpoint = start_endpoint,
      end_endpoint = end_endpoint,
      start_label = start_label,
      end_label = end_label,
      start_cell_set = start_cell_set,
      end_cell_set = end_cell_set,
      display_space_id = display_space_id,
      summary_method = endpoint_summary_method,
      max_distance = endpoint_max_distance,
      action = endpoint_qc_action
    )
    outputs$display_path <- display_prim
    outputs$display_endpoint_qc <- wb_prim_obs_table(
      endpoint_qc,
      table_type = "trajectory_segment_display_path_endpoint_qc",
      entity_kind = "trajectory_segment_endpoint",
      meta = c(meta, list(endpoint_qc_action = endpoint_qc_action))
    )
  } else {
    endpoint_qc <- .wb_display_endpoint_qc(
      bundle = bundle,
      segment_id = segment_id,
      path_xy = data.frame(x = numeric(0), y = numeric(0)),
      start_endpoint = NULL,
      end_endpoint = NULL,
      action = "none"
    )
    outputs$display_endpoint_qc <- wb_prim_obs_table(
      endpoint_qc,
      table_type = "trajectory_segment_display_path_endpoint_qc",
      entity_kind = "trajectory_segment_endpoint",
      meta = c(meta, list(endpoint_qc_action = "none"))
    )
  }

  list(
    outputs = outputs,
    params = list(
      segment_id = segment_id,
      segment_order = segment_order,
      source_kind = "space_path_bridge",
      source_engine = "space_path",
      pseudotime_key = pt_key,
      confidence_key = conf_key,
      membership_rule = membership_rule,
      distance_threshold = if (is.finite(threshold)) threshold else NA_real_,
      n_cells = nrow(score),
      endpoint_qc_action = endpoint_qc_action
    )
  )
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
#' @param join_policy Boundary policy. The current implementation supports
#'   `"exact_boundary_collapse"`.
#' @param min_weight Optional minimum lineage weight required for segment-local
#'   membership when `lineage_weights` is supplied.
#' @param allow_legacy Passed to trajectory fit-family compatibility checks.
#' @param runs Optional session runs for resolving run refs.
#'
#' @return List with promotable primitives: `composite_pseudotime_unit_segment`,
#'   `composite_pseudotime_cell_weighted_0_1`, `segment_local_table`,
#'   `composite_manifest`, and `composite_membership`.
#' @export
wb_op_trajectory_segment_join <- function(bundle,
                                          segments,
                                          composite_id = NULL,
                                          composite_key = NULL,
                                          join_policy = "exact_boundary_collapse",
                                          min_weight = NULL,
                                          allow_legacy = FALSE,
                                          runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  .wb_assert(is.list(segments) && length(segments) >= 2L,
             "trajectory_segment_join(): segments must be a list with at least two entries.")
  join_policy <- as.character(join_policy %||% "")[1]
  .wb_assert(identical(join_policy, "exact_boundary_collapse"),
             "trajectory_segment_join(): unsupported join_policy. The current implementation supports join_policy='exact_boundary_collapse'.")
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
    source_kind <- .wb_segment_clean_source_kind(seg$source_kind %||% "fitted_model")
    .wb_segment_assert_implemented_source_kind(source_kind)
    source_engine <- .wb_segment_clean_source_engine(seg$source_engine %||% NULL, source_kind = source_kind)
    normalization_rule <- as.character(seg$normalization_rule %||% if (identical(source_kind, "space_path_bridge")) "path_progress_0_1" else "segment-local min-max pseudotime scaled to [0,1]")[1]
    boundary_policy <- as.character(seg$boundary_policy %||% join_policy)[1]
    .wb_assert(identical(boundary_policy, "exact_boundary_collapse"),
               "trajectory_segment_join(): unsupported boundary_policy. The current implementation requires exact_boundary_collapse.")

    info <- .wb_validate_trajectory_segment(bundle, seg, runs = runs, allow_legacy = allow_legacy)
    pt <- .wb_segment_resolve_primitive(bundle, seg$pseudotime, runs = runs, expected_kind = "cell_vector_family",
                                        label = paste0(segment_id, " pseudotime"))
    pt_df <- .wb_segment_family_values(pt, lineage, label = paste0(segment_id, " pseudotime"))
    pt_df <- pt_df[is.finite(pt_df$value), , drop = FALSE]
    .wb_assert(nrow(pt_df) > 0L, paste0("trajectory_segment_join(): no finite pseudotime values for segment ", segment_id, "."))
    membership_cells <- .wb_segment_membership_cells(bundle, seg$membership %||% NULL, runs = runs)
    if (!is.null(membership_cells)) {
      pt_df <- pt_df[pt_df$cell_id %in% membership_cells, , drop = FALSE]
      .wb_assert(nrow(pt_df) > 0L, paste0("trajectory_segment_join(): no pseudotime cells remain after membership filter for segment ", segment_id, "."))
    }

    wt_df <- data.frame(cell_id = pt_df$cell_id, local_weight = NA_real_, stringsAsFactors = FALSE)
    if (!is.null(seg$lineage_weights)) {
      wt <- .wb_segment_resolve_primitive(bundle, seg$lineage_weights, runs = runs, expected_kind = "cell_vector_family",
                                          label = paste0(segment_id, " lineage_weights"))
      w0 <- .wb_segment_family_values(wt, lineage, label = paste0(segment_id, " lineage_weights"))
      names(w0)[names(w0) == "value"] <- "local_weight"
      wt_df <- merge(data.frame(cell_id = pt_df$cell_id, stringsAsFactors = FALSE), w0, by = "cell_id", all.x = TRUE, sort = FALSE)
    }
    conf_df <- data.frame(cell_id = pt_df$cell_id, confidence = NA_real_, stringsAsFactors = FALSE)
    if (!is.null(seg$confidence)) {
      ck <- as.character(seg$confidence_key %||% lineage)[1]
      c0 <- .wb_segment_vector_values(bundle, seg$confidence, key = ck, runs = runs,
                                      expected_label = paste0(segment_id, " confidence"))
      names(c0)[names(c0) == "value"] <- "confidence"
      conf_df <- merge(data.frame(cell_id = pt_df$cell_id, stringsAsFactors = FALSE), c0, by = "cell_id", all.x = TRUE, sort = FALSE)
    }

    dat <- merge(pt_df, wt_df, by = "cell_id", all.x = TRUE, sort = FALSE)
    dat <- merge(dat, conf_df, by = "cell_id", all.x = TRUE, sort = FALSE)
    names(dat)[names(dat) == "value"] <- "local_pseudotime"
    if (all(is.na(dat$local_weight)) && any(is.finite(dat$confidence))) {
      dat$local_weight <- dat$confidence
    }
    if (!is.null(min_weight)) {
      dat <- dat[!is.na(dat$local_weight) & dat$local_weight >= min_weight, , drop = FALSE]
      .wb_assert(nrow(dat) > 0L, paste0("trajectory_segment_join(): no cells remain after min_weight for segment ", segment_id, "."))
    }
    dat$raw_pseudotime <- dat$local_pseudotime
    dat$local_pseudotime_scaled <- if (identical(normalization_rule, "path_progress_0_1")) {
      pmax(0, pmin(1, suppressWarnings(as.numeric(dat$local_pseudotime))))
    } else {
      .wb_segment_scale01(dat$local_pseudotime)
    }
    dat$local_pseudotime_0_1 <- dat$local_pseudotime_scaled
    dat$segment_id <- segment_id
    dat$segment_order <- order
    dat$lineage_id <- lineage
    dat$source_kind <- source_kind
    dat$source_engine <- source_engine
    dat$segment_role <- "segment"

    segment_ids[i] <- segment_id
    segment_orders[i] <- order
    seg_rows[[i]] <- dat[, c(
      "cell_id", "segment_id", "segment_order", "lineage_id",
      "source_kind", "source_engine", "raw_pseudotime", "local_pseudotime",
      "local_pseudotime_scaled", "local_pseudotime_0_1", "local_weight",
      "confidence", "segment_role"
    ), drop = FALSE]

    meta_rows[[i]] <- data.frame(
      segment_id = segment_id,
      segment_order = order,
      source_kind = source_kind,
      source_engine = source_engine,
      lineage_id = lineage,
      trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
      trajectory_engine = as.character(info$engine[1] %||% ""),
      model_artifact_id = .wb_segment_ref_artifact_id(seg$model),
      pseudotime_artifact_id = .wb_segment_ref_artifact_id(seg$pseudotime),
      membership_artifact_id = .wb_segment_ref_artifact_id(seg$membership),
      lineage_weights_artifact_id = .wb_segment_ref_artifact_id(seg$lineage_weights),
      confidence_artifact_id = .wb_segment_ref_artifact_id(seg$confidence),
      path_artifact_id = .wb_segment_ref_artifact_id(seg$path),
      segment_manifest_artifact_id = .wb_segment_ref_artifact_id(seg$segment_manifest),
      start_label = as.character(seg$start_label %||% "")[1],
      end_label = as.character(seg$end_label %||% "")[1],
      normalization_rule = normalization_rule,
      boundary_policy = boundary_policy,
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
        composite_pseudotime_unit_segment = local$composite_candidate[ii[1]],
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
            "' appears in non-adjacent or multi-segment overlap; exact_boundary_collapse requires adjacent pair overlaps only."
          ),
          call. = FALSE
        )
      }
      data.frame(
        cell_id = cid,
        composite_pseudotime_unit_segment = min(seg_idx),
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

  segment_weight <- manifest$n_segment_cells / sum(manifest$n_segment_cells)
  segment_weight[!is.finite(segment_weight)] <- 0
  if (sum(segment_weight) <= 0) segment_weight[] <- 1 / length(segment_weight)
  segment_weight <- segment_weight / sum(segment_weight)
  weighted_start <- c(0, head(cumsum(segment_weight), -1L))
  weighted_boundary <- cumsum(segment_weight)
  weight_df <- data.frame(
    segment_index = seq_along(segment_weight),
    segment_weight = segment_weight,
    weighted_start = weighted_start,
    weighted_boundary = weighted_boundary,
    stringsAsFactors = FALSE
  )
  comp$composite_pseudotime_cell_weighted_0_1 <- vapply(seq_len(nrow(comp)), function(i) {
    role <- as.character(comp$composite_membership_role[i])
    if (identical(role, "waypoint_overlap")) {
      seg_idx <- sort(unique(local$segment_index[local$cell_id == comp$cell_id[i]]))
      return(weighted_boundary[min(seg_idx)])
    }
    sid <- as.character(comp$composite_segment_assignment[i])
    seg_idx <- as.integer(manifest$segment_index[match(sid, manifest$segment_id)])
    cand <- local[local$cell_id == comp$cell_id[i] & local$segment_index == seg_idx, , drop = FALSE]
    if (!nrow(cand)) return(NA_real_)
    weighted_start[seg_idx] + cand$local_pseudotime_0_1[1] * segment_weight[seg_idx]
  }, numeric(1))

  parent_fit_ids <- unique(as.character(manifest$trajectory_fit_id))
  parent_fit_ids <- parent_fit_ids[nzchar(parent_fit_ids)]
  meta <- list(
    trajectory_composite_id = composite_id,
    family_kind = "trajectory_composite_pseudotime",
    value_semantics = "segmented_composite_pseudotime",
    join_policy = join_policy,
    scaling_rule = "segment-local source-specific normalization to [0,1]",
    composite_coordinate_unit_segment = "canonical audit coordinate with integer segment boundaries",
    composite_coordinate_cell_weighted_0_1 = "display/comparison coordinate with segment lengths weighted by segment-local cell counts",
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
  manifest$segment_weight_cell_fraction <- segment_weight
  manifest$weighted_coordinate_start <- weighted_start
  manifest$weighted_coordinate_end <- weighted_boundary
  manifest$overlap_handling_rule <- meta$overlap_handling_rule
  manifest$n_unique_cells <- vapply(manifest$segment_id, function(sid) {
    sum(comp$composite_segment_assignment == sid)
  }, integer(1))
  manifest$n_waypoint_cells <- length(waypoint_cells)
  manifest$caveats <- "Composite pseudotime is derived from separately fitted trajectory segments; parent model RDS objects are not merged."
  manifest <- manifest[, c(
    "trajectory_composite_id", "segment_id", "segment_order", "segment_index",
    "source_kind", "source_engine", "lineage_id", "trajectory_fit_id", "trajectory_engine",
    "model_artifact_id", "pseudotime_artifact_id", "membership_artifact_id",
    "lineage_weights_artifact_id", "confidence_artifact_id", "path_artifact_id",
    "segment_manifest_artifact_id", "start_label", "end_label",
    "normalization_rule", "boundary_policy", "join_policy", "scaling_rule", "overlap_handling_rule",
    "segment_weight_cell_fraction", "weighted_coordinate_start", "weighted_coordinate_end",
    "n_segment_cells", "n_unique_cells", "n_waypoint_cells", "caveats"
  ), drop = FALSE]

  local$trajectory_composite_id <- composite_id
  local <- local[, c(
    "trajectory_composite_id", "cell_id", "segment_id", "segment_order", "segment_index",
    "source_kind", "source_engine", "lineage_id", "raw_pseudotime", "local_pseudotime",
    "local_pseudotime_scaled", "local_pseudotime_0_1", "local_weight", "confidence",
    "segment_role", "composite_candidate"
  ), drop = FALSE]

  membership <- setNames(as.character(comp$composite_segment_assignment), as.character(comp$cell_id))

  list(
    outputs = list(
      composite_pseudotime_unit_segment = wb_prim_cell_vector_family(
        key = rep(composite_key, nrow(comp)),
        cell_id = comp$cell_id,
        value = comp$composite_pseudotime_unit_segment,
        value_type = "continuous",
        meta = c(meta, list(value_semantics = "composite_pseudotime_unit_segment"))
      ),
      composite_pseudotime_cell_weighted_0_1 = wb_prim_cell_vector_family(
        key = rep(composite_key, nrow(comp)),
        cell_id = comp$cell_id,
        value = comp$composite_pseudotime_cell_weighted_0_1,
        value_type = "continuous",
        meta = c(meta, list(value_semantics = "composite_pseudotime_cell_weighted_0_1"))
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
      coordinate_outputs = c("composite_pseudotime_unit_segment", "composite_pseudotime_cell_weighted_0_1"),
      parent_segment_ids = segment_ids,
      parent_trajectory_fit_ids = parent_fit_ids
    )
  )
}

.wb_segment_path_values <- function(prim, lineage, label = "path_2d_family") {
  .wb_assert_kind(prim, "path_2d_family", where = paste0(" for ", label))
  lineage <- as.character(lineage %||% "")[1]
  if (!nzchar(lineage)) {
    keys <- unique(as.character(prim$key))
    keys <- keys[nzchar(keys)]
    .wb_assert(length(keys) == 1L, "trajectory_segment_path_join(): lineage must be supplied when path has multiple keys.")
    lineage <- keys[1]
  }
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

.wb_endpoint_descriptor <- function(x, label = NULL, cell_set = NULL) {
  if (is.null(x) && is.null(cell_set)) return(NULL)
  if (is.list(x) && !is.data.frame(x)) {
    out <- x
  } else if (is.data.frame(x)) {
    .wb_assert(nrow(x) >= 1L, "Endpoint data.frame descriptors must have at least one row.")
    out <- as.list(x[1, , drop = FALSE])
  } else {
    out <- list(cell_set = as.character(x)[1])
  }
  if (!is.null(cell_set)) out$cell_set <- as.character(cell_set)[1]
  if (!is.null(label) && is.null(out$label)) out$label <- as.character(label)[1]
  out
}

.wb_endpoint_cells <- function(bundle, endpoint) {
  if (is.null(endpoint)) return(character(0))
  if (!is.null(endpoint$cells)) return(unique(as.character(endpoint$cells)))
  if (!is.null(endpoint$cell_ids)) return(unique(as.character(endpoint$cell_ids)))
  cell_set <- as.character(endpoint$cell_set %||% "")[1]
  if (!nzchar(cell_set)) return(character(0))
  candidates <- unique(c(cell_set, paste0("set:", cell_set), sub("^set:", "", cell_set)))
  for (cs in candidates) {
    cells <- tryCatch(as.character(wb_cells(bundle, cell_set = cs)), error = function(e) character(0))
    if (length(cells)) return(unique(cells))
  }
  character(0)
}

.wb_endpoint_display_summary <- function(bundle, endpoint, display_space_id, summary_method = "centroid") {
  summary_method <- as.character(summary_method %||% "centroid")[1]
  .wb_assert(summary_method %in% c("centroid", "medoid"),
             "Endpoint summary method must be 'centroid' or 'medoid'.")
  endpoint <- .wb_endpoint_descriptor(endpoint)
  label <- as.character(endpoint$label %||% endpoint$cell_set %||% "")[1]
  if (!is.null(endpoint$x) && !is.null(endpoint$y)) {
    return(list(
      label = label,
      x = suppressWarnings(as.numeric(endpoint$x)[1]),
      y = suppressWarnings(as.numeric(endpoint$y)[1]),
      n_cells = NA_integer_,
      radius_median = NA_real_,
      source = "explicit_xy"
    ))
  }
  cells <- .wb_endpoint_cells(bundle, endpoint)
  .wb_assert(length(cells) > 0L, paste0("Endpoint '", label, "' did not resolve to any cells."))
  display_space_id <- as.character(endpoint$display_space_id %||% display_space_id %||% "")[1]
  .wb_assert(nzchar(display_space_id), paste0("Endpoint '", label, "' requires display_space_id for cell-set coordinate QC."))
  xy <- .wb_space_2d_safe(bundle, display_space_id, cells = cells)
  xy <- xy[is.finite(xy$x) & is.finite(xy$y), , drop = FALSE]
  .wb_assert(nrow(xy) > 0L, paste0("Endpoint '", label, "' has no finite coordinates in display_space_id='", display_space_id, "'."))
  cx <- mean(xy$x)
  cy <- mean(xy$y)
  dist <- sqrt((xy$x - cx)^2 + (xy$y - cy)^2)
  if (identical(summary_method, "medoid")) {
    j <- which.min(dist)
    cx <- xy$x[j]
    cy <- xy$y[j]
    dist <- sqrt((xy$x - cx)^2 + (xy$y - cy)^2)
  }
  list(
    label = label,
    x = cx,
    y = cy,
    n_cells = nrow(xy),
    radius_median = stats::median(dist, na.rm = TRUE),
    source = paste0("cell_set:", as.character(endpoint$cell_set %||% "cells")[1])
  )
}

.wb_endpoint_global_tolerance <- function(bundle, display_space_id) {
  display_space_id <- as.character(display_space_id %||% "")[1]
  if (!nzchar(display_space_id)) return(NA_real_)
  xy <- .wb_space_2d_safe(bundle, display_space_id, cells = NULL)
  xy <- xy[is.finite(xy$x) & is.finite(xy$y), , drop = FALSE]
  if (!nrow(xy)) return(NA_real_)
  dx <- diff(range(xy$x))
  dy <- diff(range(xy$y))
  diag <- sqrt(dx^2 + dy^2)
  if (!is.finite(diag) || diag <= 0) return(NA_real_)
  0.02 * diag
}

.wb_display_endpoint_qc_one <- function(bundle, segment_id, endpoint_role, endpoint, path_xy,
                                        display_space_id = NULL, summary_method = "centroid",
                                        max_distance = NULL, tolerance_multiplier = 3) {
  endpoint <- .wb_endpoint_descriptor(endpoint)
  display_space_id <- as.character(endpoint$display_space_id %||% display_space_id %||% "")[1]
  e <- .wb_endpoint_display_summary(bundle, endpoint, display_space_id = display_space_id, summary_method = summary_method)
  px <- if (identical(endpoint_role, "start")) path_xy$x[1] else path_xy$x[nrow(path_xy)]
  py <- if (identical(endpoint_role, "start")) path_xy$y[1] else path_xy$y[nrow(path_xy)]
  distance <- sqrt((px - e$x)^2 + (py - e$y)^2)
  max_distance <- suppressWarnings(as.numeric(max_distance)[1])
  base_tol <- if (is.finite(max_distance)) max_distance else {
    global_tol <- .wb_endpoint_global_tolerance(bundle, display_space_id)
    radius_tol <- suppressWarnings(as.numeric(e$radius_median) * suppressWarnings(as.numeric(tolerance_multiplier)[1]))
    max(c(radius_tol, global_tol, 1e-8), na.rm = TRUE)
  }
  if (!is.finite(base_tol) || base_tol <= 0) base_tol <- 1e-8
  status <- if (!is.finite(distance)) {
    "fail"
  } else if (distance <= base_tol) {
    "ok"
  } else if (distance <= 2 * base_tol) {
    "warn"
  } else {
    "fail"
  }
  data.frame(
    segment_id = as.character(segment_id)[1],
    endpoint_role = endpoint_role,
    endpoint_label = as.character(e$label %||% "")[1],
    display_space_id = display_space_id,
    summary_method = as.character(summary_method)[1],
    endpoint_source = as.character(e$source %||% "")[1],
    n_endpoint_cells = as.integer(e$n_cells %||% NA_integer_),
    display_path_x = px,
    display_path_y = py,
    endpoint_x = e$x,
    endpoint_y = e$y,
    endpoint_radius_median = suppressWarnings(as.numeric(e$radius_median %||% NA_real_)),
    distance = distance,
    tolerance = base_tol,
    status = status,
    stringsAsFactors = FALSE
  )
}

.wb_display_endpoint_qc <- function(bundle, segment_id, path_xy,
                                    start_endpoint = NULL, end_endpoint = NULL,
                                    start_label = NULL, end_label = NULL,
                                    start_cell_set = NULL, end_cell_set = NULL,
                                    display_space_id = NULL,
                                    summary_method = "centroid",
                                    max_distance = NULL,
                                    action = "fail") {
  action <- as.character(action %||% "fail")[1]
  .wb_assert(action %in% c("fail", "warn", "none"),
             "endpoint_qc_action must be one of: fail, warn, none.")
  rows <- list()
  start_endpoint <- .wb_endpoint_descriptor(start_endpoint, label = start_label, cell_set = start_cell_set)
  end_endpoint <- .wb_endpoint_descriptor(end_endpoint, label = end_label, cell_set = end_cell_set)
  if (!is.null(start_endpoint)) {
    rows[[length(rows) + 1L]] <- .wb_display_endpoint_qc_one(
      bundle, segment_id, "start", start_endpoint, path_xy,
      display_space_id = display_space_id, summary_method = summary_method,
      max_distance = max_distance
    )
  }
  if (!is.null(end_endpoint)) {
    rows[[length(rows) + 1L]] <- .wb_display_endpoint_qc_one(
      bundle, segment_id, "end", end_endpoint, path_xy,
      display_space_id = display_space_id, summary_method = summary_method,
      max_distance = max_distance
    )
  }
  if (!length(rows)) {
    return(data.frame(
      segment_id = character(0), endpoint_role = character(0), endpoint_label = character(0),
      display_space_id = character(0), summary_method = character(0), endpoint_source = character(0),
      n_endpoint_cells = integer(0), display_path_x = numeric(0), display_path_y = numeric(0),
      endpoint_x = numeric(0), endpoint_y = numeric(0), endpoint_radius_median = numeric(0),
      distance = numeric(0), tolerance = numeric(0), status = character(0),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, rows)
  bad <- out$status == "fail"
  warn <- out$status == "warn"
  msg <- paste0(
    "display path endpoint QC for segment '", segment_id, "': ",
    paste(paste0(out$endpoint_role, " distance=", signif(out$distance, 4),
                 " tolerance=", signif(out$tolerance, 4), " status=", out$status), collapse = "; ")
  )
  if (any(bad) && identical(action, "fail")) stop(msg, call. = FALSE)
  if ((any(bad) || any(warn)) && identical(action, "warn")) warning(msg, call. = FALSE)
  out
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
                                               display_space_id = NULL,
                                               endpoint_summary_method = "centroid",
                                               endpoint_max_distance = NULL,
                                               endpoint_qc_action = "fail",
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
    source_kind <- .wb_segment_clean_source_kind(seg$source_kind %||% "fitted_model")
    source_engine <- .wb_segment_clean_source_engine(seg$source_engine %||% NULL, source_kind = source_kind)
    .wb_assert(nzchar(segment_id), "trajectory_segment_path_join(): segment_id must be non-empty.")
    .wb_assert(is.finite(order), paste0("trajectory_segment_path_join(): invalid order for segment ", segment_id, "."))
    .wb_assert(nzchar(lineage), paste0("trajectory_segment_path_join(): missing lineage for segment ", segment_id, "."))
    .wb_assert(!is.null(seg$path), paste0("trajectory_segment_path_join(): missing path for segment ", segment_id, "."))

    info <- wb_trajectory_fit_info(bundle, seg$path)
    if (!nzchar(as.character(info$trajectory_fit_id[1] %||% ""))) {
      msg <- "trajectory_segment_path_join(): parent path is missing trajectory_fit_id; legacy paths cannot be joined without explicit allow_legacy=TRUE."
      if (identical(source_kind, "fitted_model")) {
        if (isTRUE(allow_legacy)) warning(msg, call. = FALSE) else stop(msg, call. = FALSE)
      }
    }
    prim <- .wb_segment_resolve_primitive(bundle, seg$path, expected_kind = "path_2d_family",
                                          label = paste0(segment_id, " path"))
    pv <- .wb_segment_path_values(prim, lineage, label = paste0(segment_id, " path"))
    pv$segment_id <- segment_id
    pv$segment_order <- order
    pv$source_lineage_id <- lineage
    endpoint_qc <- .wb_display_endpoint_qc(
      bundle = bundle,
      segment_id = segment_id,
      path_xy = pv,
      start_endpoint = seg$start_endpoint %||% NULL,
      end_endpoint = seg$end_endpoint %||% NULL,
      start_label = seg$start_label %||% NULL,
      end_label = seg$end_label %||% NULL,
      start_cell_set = seg$start_cell_set %||% NULL,
      end_cell_set = seg$end_cell_set %||% NULL,
      display_space_id = seg$display_space_id %||% display_space_id %||% NULL,
      summary_method = seg$endpoint_summary_method %||% endpoint_summary_method,
      max_distance = seg$endpoint_max_distance %||% endpoint_max_distance %||% NULL,
      action = seg$endpoint_qc_action %||% endpoint_qc_action
    )

    segment_ids[i] <- segment_id
    segment_orders[i] <- order
    rows[[i]] <- pv
    manifests[[i]] <- data.frame(
      segment_id = segment_id,
      segment_order = order,
      source_kind = source_kind,
      source_engine = source_engine,
      lineage_id = lineage,
      trajectory_fit_id = as.character(info$trajectory_fit_id[1] %||% ""),
      trajectory_engine = as.character(info$engine[1] %||% source_engine),
      path_artifact_id = .wb_segment_ref_artifact_id(seg$path),
      start_label = as.character(seg$start_label %||% "")[1],
      end_label = as.character(seg$end_label %||% "")[1],
      n_path_points = nrow(pv),
      stringsAsFactors = FALSE
    )
    manifests[[i]]$endpoint_qc_rows <- nrow(endpoint_qc)
    attr(manifests[[i]], "endpoint_qc") <- endpoint_qc
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
  endpoint_qc <- do.call(rbind, lapply(manifests, function(x) attr(x, "endpoint_qc")))
  if (is.null(endpoint_qc)) endpoint_qc <- .wb_display_endpoint_qc(bundle, "", data.frame(x = numeric(0), y = numeric(0)))
  rownames(joined) <- NULL
  rownames(manifest) <- NULL
  rownames(endpoint_qc) <- NULL
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
    "source_kind", "source_engine", "lineage_id", "trajectory_fit_id", "trajectory_engine", "path_artifact_id",
    "start_label", "end_label", "n_path_points", "endpoint_qc_rows", "composite_point_start", "composite_point_end", "caveats"
  ), drop = FALSE]
  if (nrow(endpoint_qc)) {
    endpoint_qc$trajectory_composite_id <- composite_id
    endpoint_qc$composite_key <- composite_key
    endpoint_qc <- endpoint_qc[, c(
      "trajectory_composite_id", "composite_key", "segment_id", "endpoint_role",
      "endpoint_label", "display_space_id", "summary_method", "endpoint_source",
      "n_endpoint_cells", "display_path_x", "display_path_y", "endpoint_x", "endpoint_y",
      "endpoint_radius_median", "distance", "tolerance", "status"
    ), drop = FALSE]
  }

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
      ),
      endpoint_qc = wb_prim_obs_table(
        endpoint_qc,
        table_type = "trajectory_segment_display_path_endpoint_qc",
        entity_kind = "trajectory_segment_endpoint",
        meta = c(meta, list(endpoint_qc_action = endpoint_qc_action))
      )
    ),
    params = list(
      trajectory_composite_id = composite_id,
      composite_key = composite_key,
      n_segments = length(segment_ids),
      n_points = nrow(joined),
      endpoint_qc_rows = nrow(endpoint_qc),
      parent_segment_ids = segment_ids,
      parent_trajectory_fit_ids = parent_fit_ids
    )
  )
}
