#' Resolve a navigation source
.wb_nav_resolve_source <- function(source, bundle) {
  src <- source
  if (is.character(src) && length(src) == 1L && nzchar(src)) {
    ref <- as.character(src)[1]
    aid <- if (startsWith(ref, "artifact:")) sub("^artifact:", "", ref) else ref
    info <- try(wb_art_table_info(bundle, aid), silent = TRUE)
    if (!inherits(info, "try-error") && is.data.frame(info) && nrow(info) == 1L) {
      return(list(
        source_type = "artifact",
        ref = paste0("artifact:", aid),
        artifact_id = aid,
        info = info
      ))
    }
  }
  stop("Unsupported navigation source. Currently only artifact refs/IDs are supported.", call. = FALSE)
}

.wb_nav_entity_df <- function(entity_kind,
                              entity_id,
                              label = NULL,
                              group_kind = NULL,
                              group_id = NULL,
                              score = NULL,
                              rank = NULL,
                              direction = NULL,
                              source_ref = NULL) {
  data.frame(
    entity_kind = as.character(entity_kind %||% "")[1],
    entity_id = as.character(entity_id %||% ""),
    label = as.character(label %||% entity_id %||% ""),
    group_kind = as.character(group_kind %||% ""),
    group_id = as.character(group_id %||% ""),
    score = suppressWarnings(as.numeric(score %||% NA_real_)),
    rank = suppressWarnings(as.integer(rank %||% NA_integer_)),
    direction = as.character(direction %||% ""),
    source_ref = as.character(source_ref %||% ""),
    stringsAsFactors = FALSE
  )
}

.wb_nav_target_df <- function(target_kind,
                              target_id,
                              action,
                              label,
                              reason = NULL,
                              priority = 100L) {
  data.frame(
    target_kind = as.character(target_kind %||% "")[1],
    target_id = as.character(target_id %||% "")[1],
    action = as.character(action %||% "")[1],
    label = as.character(label %||% "")[1],
    reason = as.character(reason %||% "")[1],
    priority = suppressWarnings(as.integer(priority %||% 100L)),
    stringsAsFactors = FALSE
  )
}

.wb_nav_source_plot_type <- function(source_op, table_type = NULL) {
  src_op <- as.character(source_op %||% "")[1]
  tt <- as.character(table_type %||% "")[1]
  if (identical(src_op, "trajectory_de") && identical(tt, "trajectory_de")) return("ranked_lollipop")
  if (identical(src_op, "trajectory_smooth") && identical(tt, "trajectory_smooth")) return("pseudotime_smooth_panel")
  if (identical(src_op, "trajectory_signature_smooth") && identical(tt, "trajectory_signature_smooth")) return("pseudotime_signature_line")
  NA_character_
}

#' List Navigable Entities For A Source
#'
#' Enumerate entities that a client can navigate from an artifact-backed source.
#' This is the discovery entry point for engine-owned handoff workflows. The
#' returned data frame is intentionally client-agnostic and can be used by
#' Shiny, scripts, notebooks, or agents.
#'
#' Current built-in resolvers cover promoted `trajectory_de`,
#' `trajectory_smooth`, and `trajectory_signature_smooth` artifacts.
#'
#' @param source Artifact ref or artifact id. Refs may be passed as
#'   `"artifact:<artifact_id>"`.
#' @param bundle Open `scworkbench_bundle`.
#' @param entity_kind Entity family to enumerate. Use `"auto"` to return
#'   lineages first and lineage-specific features only when `lineage_id` is
#'   supplied.
#' @param lineage_id Optional lineage context for feature enumeration.
#' @param limit Maximum number of entities to return.
#' @param search Optional case-insensitive substring filter applied to entity
#'   identifiers where supported.
#' @param direction Direction filter for ranked `trajectory_de` features.
#' @param order_by Ranking rule for `trajectory_de` feature navigation.
#'
#' @return A data frame with navigation-ready entity rows. Columns include
#'   `entity_kind`, `entity_id`, `label`, optional grouping columns, and source
#'   provenance fields such as `source_ref`.
#'
#' @examples
#' \dontrun{
#' b <- wb_open_bundle("/path/to/bundle")
#' wb_nav_entities("artifact:feature_table_123", b, entity_kind = "lineage")
#' wb_nav_entities(
#'   "artifact:feature_table_123",
#'   b,
#'   entity_kind = "feature",
#'   lineage_id = "root:A::lineage:B",
#'   limit = 25
#' )
#' }
#' @export
wb_nav_entities <- function(source,
                            bundle,
                            entity_kind = c("auto", "lineage", "feature"),
                            lineage_id = NULL,
                            limit = 100L,
                            search = NULL,
                            direction = c("any", "up", "down"),
                            order_by = c("abs_rho", "rho_desc", "rho_asc", "p_adj")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  resolved <- .wb_nav_resolve_source(source, bundle)
  info <- resolved$info
  e_kind <- match.arg(entity_kind)
  dir_mode <- match.arg(direction)
  ord_mode <- match.arg(order_by)
  src_op <- as.character(info$source_op[1] %||% "")[1]
  tt <- as.character(info$table_type[1] %||% "")[1]

  if (identical(src_op, "trajectory_de") && identical(tt, "trajectory_de")) {
    ov <- wb_art_trajectory_de_overview(bundle, resolved$artifact_id)
    if (identical(e_kind, "auto")) e_kind <- if (nzchar(as.character(lineage_id %||% "")[1])) "feature" else "lineage"
    if (identical(e_kind, "lineage")) {
      out <- .wb_nav_entity_df(
        entity_kind = "lineage",
        entity_id = as.character(ov$lineages %||% character(0)),
        label = as.character(ov$lineages %||% character(0)),
        source_ref = resolved$ref
      )
      return(out[nzchar(out$entity_id), , drop = FALSE])
    }
    lin <- as.character(lineage_id %||% "")[1]
    .wb_assert(nzchar(lin), "lineage_id is required for feature navigation from trajectory_de.")
    ranked <- wb_art_trajectory_de_ranked(
      bundle = bundle,
      artifact_id = resolved$artifact_id,
      lineage_id = lin,
      limit = limit,
      direction = dir_mode,
      order_by = ord_mode,
      search = search
    )
    if (!is.data.frame(ranked) || !nrow(ranked)) return(.wb_nav_entity_df(entity_kind = character(0), entity_id = character(0)))
    out <- .wb_nav_entity_df(
      entity_kind = "feature",
      entity_id = as.character(ranked$feature_id %||% ""),
      label = as.character(ranked$feature_id %||% ""),
      group_kind = "lineage",
      group_id = lin,
      score = suppressWarnings(as.numeric(ranked$rho %||% ranked$abs_rho %||% NA_real_)),
      rank = seq_len(nrow(ranked)),
      direction = as.character(ranked$direction %||% ""),
      source_ref = resolved$ref
    )
    return(out[nzchar(out$entity_id), , drop = FALSE])
  }

  if (identical(src_op, "trajectory_smooth") && identical(tt, "trajectory_smooth")) {
    ov <- wb_art_trajectory_smooth_overview(bundle, resolved$artifact_id)
    if (identical(e_kind, "auto")) e_kind <- if (nzchar(as.character(lineage_id %||% "")[1])) "feature" else "lineage"
    if (identical(e_kind, "lineage")) {
      out <- .wb_nav_entity_df(
        entity_kind = "lineage",
        entity_id = as.character(ov$lineages %||% character(0)),
        label = as.character(ov$lineages %||% character(0)),
        source_ref = resolved$ref
      )
      return(out[nzchar(out$entity_id), , drop = FALSE])
    }
    lin <- as.character(lineage_id %||% "")[1]
    .wb_assert(nzchar(lin), "lineage_id is required for feature navigation from trajectory_smooth.")
    tbl <- wb_art_table_slice(bundle, resolved$artifact_id, filters = list(lineage_id = lin))
    if (!is.data.frame(tbl) || !nrow(tbl) || !("feature_id" %in% names(tbl))) {
      return(.wb_nav_entity_df(entity_kind = character(0), entity_id = character(0)))
    }
    feats <- unique(as.character(tbl$feature_id))
    feats <- feats[nzchar(feats)]
    if (nzchar(as.character(search %||% "")[1])) {
      keep <- grepl(tolower(as.character(search)[1]), tolower(feats), fixed = TRUE)
      feats <- feats[keep]
    }
    lim <- suppressWarnings(as.integer(limit %||% 100L))
    if (is.finite(lim) && lim > 0L && length(feats) > lim) feats <- feats[seq_len(lim)]
    out <- .wb_nav_entity_df(
      entity_kind = "feature",
      entity_id = feats,
      label = feats,
      group_kind = "lineage",
      group_id = lin,
      source_ref = resolved$ref
    )
    return(out[nzchar(out$entity_id), , drop = FALSE])
  }

  if (identical(src_op, "trajectory_signature_smooth") && identical(tt, "trajectory_signature_smooth")) {
    if (identical(e_kind, "auto")) e_kind <- if (nzchar(as.character(lineage_id %||% "")[1])) "feature" else "lineage"
    if (identical(e_kind, "lineage")) {
      lineages <- wb_art_table_distinct(bundle, resolved$artifact_id, "lineage_id")
      out <- .wb_nav_entity_df(
        entity_kind = "lineage",
        entity_id = as.character(lineages %||% character(0)),
        label = as.character(lineages %||% character(0)),
        source_ref = resolved$ref
      )
      return(out[nzchar(out$entity_id), , drop = FALSE])
    }
    lin <- as.character(lineage_id %||% "")[1]
    .wb_assert(nzchar(lin), "lineage_id is required for feature_set navigation from trajectory_signature_smooth.")
    sets <- wb_art_table_distinct(bundle, resolved$artifact_id, "feature_set", filters = list(lineage_id = lin), limit = limit)
    if (nzchar(as.character(search %||% "")[1])) {
      keep <- grepl(tolower(as.character(search)[1]), tolower(as.character(sets)), fixed = TRUE)
      sets <- as.character(sets)[keep]
    }
    out <- .wb_nav_entity_df(
      entity_kind = "feature_set",
      entity_id = as.character(sets %||% character(0)),
      label = as.character(sets %||% character(0)),
      group_kind = "lineage",
      group_id = lin,
      source_ref = resolved$ref
    )
    return(out[nzchar(out$entity_id), , drop = FALSE])
  }

  stop("No navigation resolver for source.", call. = FALSE)
}

#' List Compatible Navigation Targets
#'
#' Ask the engine which navigation targets are valid for a source and optional
#' selected entity. This centralizes "best friendships" in the engine rather
#' than re-implementing handoff rules in clients.
#'
#' @param source Artifact ref or artifact id.
#' @param bundle Open `scworkbench_bundle`.
#' @param entity Optional entity row, typically taken from
#'   [wb_nav_entities()].
#' @param lineage_id Optional lineage context. When `entity` already carries a
#'   `group_id`, that lineage is used automatically.
#'
#' @return A data frame describing compatible targets. Columns include
#'   `target_kind`, `target_id`, `action`, `label`, `reason`, and `priority`.
#'
#' @examples
#' \dontrun{
#' b <- wb_open_bundle("/path/to/bundle")
#' ent <- wb_nav_entities(
#'   "artifact:feature_table_123",
#'   b,
#'   entity_kind = "feature",
#'   lineage_id = "root:A::lineage:B",
#'   limit = 1
#' )
#' wb_nav_targets("artifact:feature_table_123", b, entity = ent[1, , drop = FALSE])
#' }
#' @export
wb_nav_targets <- function(source,
                           bundle,
                           entity = NULL,
                           lineage_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  resolved <- .wb_nav_resolve_source(source, bundle)
  info <- resolved$info
  src_op <- as.character(info$source_op[1] %||% "")[1]
  tt <- as.character(info$table_type[1] %||% "")[1]
  out <- data.frame(stringsAsFactors = FALSE)

  entity_kind <- as.character(entity$entity_kind %||% entity[["entity_kind"]] %||% "")[1]
  entity_id <- as.character(entity$entity_id %||% entity[["entity_id"]] %||% "")[1]
  lin <- as.character(lineage_id %||% entity$group_id %||% entity[["group_id"]] %||% "")[1]

  if (identical(src_op, "trajectory_de") && identical(tt, "trajectory_de")) {
    rel <- wb_art_trajectory_related(bundle, resolved$artifact_id)
    sm <- rel$trajectory_smooth %||% data.frame(stringsAsFactors = FALSE)
    if (is.data.frame(sm) && nrow(sm) && nzchar(entity_id) && identical(entity_kind, "feature") && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = paste0("artifact:", as.character(sm$artifact_id[1])),
        action = "open_smooth_plot",
        label = "Open in smooth plot",
        reason = "Matching trajectory_smooth artifact",
        priority = 10L
      ))
    }
    if (identical(entity_kind, "feature") && nzchar(entity_id) && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = resolved$ref,
        action = "compare_other_lineage",
        label = "Compare in other lineage",
        reason = "Same trajectory_de artifact",
        priority = 20L
      ))
    }
    rownames(out) <- NULL
    return(out)
  }

  if (identical(src_op, "trajectory_smooth") && identical(tt, "trajectory_smooth")) {
    rel <- wb_art_trajectory_related(bundle, resolved$artifact_id)
    de <- rel$trajectory_de %||% data.frame(stringsAsFactors = FALSE)
    sig <- rel$trajectory_signature_smooth %||% data.frame(stringsAsFactors = FALSE)
    if (is.data.frame(de) && nrow(de) && nzchar(entity_id) && identical(entity_kind, "feature") && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = paste0("artifact:", as.character(de$artifact_id[1])),
        action = "open_de_plot",
        label = "Open in trajectory DE",
        reason = "Matching trajectory_de artifact",
        priority = 10L
      ))
    }
    if (is.data.frame(sig) && nrow(sig) && identical(entity_kind, "lineage") && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = paste0("artifact:", as.character(sig$artifact_id[1])),
        action = "open_signature_plot",
        label = "Open signature plot",
        reason = "Matching trajectory_signature_smooth artifact",
        priority = 15L
      ))
    }
    if (identical(entity_kind, "feature") && nzchar(entity_id) && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = resolved$ref,
        action = "compare_other_lineage",
        label = "Compare in other lineage",
        reason = "Same trajectory_smooth artifact",
        priority = 20L
      ))
    }
    rownames(out) <- NULL
    return(out)
  }

  if (identical(src_op, "trajectory_signature_smooth") && identical(tt, "trajectory_signature_smooth")) {
    if (identical(entity_kind, "feature_set") && nzchar(entity_id) && nzchar(lin)) {
      out <- rbind(out, .wb_nav_target_df(
        target_kind = "artifact_plot",
        target_id = resolved$ref,
        action = "compare_other_lineage",
        label = "Compare in other lineage",
        reason = "Same trajectory_signature_smooth artifact",
        priority = 20L
      ))
    }
    rownames(out) <- NULL
    return(out)
  }

  stop("No navigation resolver for source.", call. = FALSE)
}

#' Build A Client-Agnostic Navigation Handoff
#'
#' Resolve a concrete navigation target into a handoff payload that another
#' client surface can apply. The payload is intentionally minimal: it names the
#' destination ref, a suggested plot type when relevant, and the minimal
#' parameter context needed to continue the workflow.
#'
#' @param source Artifact ref or artifact id.
#' @param target Target descriptor returned by [wb_nav_targets()] or a target
#'   action / target id that can be resolved against that target table.
#' @param bundle Open `scworkbench_bundle`.
#' @param entity Optional entity row, typically taken from
#'   [wb_nav_entities()].
#' @param lineage_id Optional lineage context when the entity does not already
#'   carry one.
#'
#' @return A named list describing the handoff. Fields typically include
#'   `ref`, `plot_type`, `params`, `selection`, `source_ref`, and
#'   `target_action`.
#'
#' @examples
#' \dontrun{
#' b <- wb_open_bundle("/path/to/bundle")
#' ent <- wb_nav_entities(
#'   "artifact:feature_table_123",
#'   b,
#'   entity_kind = "feature",
#'   lineage_id = "root:A::lineage:B",
#'   limit = 1
#' )
#' wb_nav_handoff(
#'   "artifact:feature_table_123",
#'   "open_smooth_plot",
#'   b,
#'   entity = ent[1, , drop = FALSE]
#' )
#' }
#' @export
wb_nav_handoff <- function(source,
                           target,
                           bundle,
                           entity = NULL,
                           lineage_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  resolved <- .wb_nav_resolve_source(source, bundle)
  src_info <- resolved$info
  src_op <- as.character(src_info$source_op[1] %||% "")[1]
  src_tt <- as.character(src_info$table_type[1] %||% "")[1]
  target_df <- if (is.data.frame(target)) target else NULL
  if (is.null(target_df)) {
    tdf <- wb_nav_targets(source = source, bundle = bundle, entity = entity, lineage_id = lineage_id)
    idx <- which(as.character(tdf$action %||% "") == as.character(target)[1] | as.character(tdf$target_id %||% "") == as.character(target)[1])
    .wb_assert(length(idx) >= 1L, "Could not resolve target for navigation handoff.")
    target_df <- tdf[idx[1], , drop = FALSE]
  }

  action <- as.character(target_df$action[1] %||% "")[1]
  ref <- as.character(target_df$target_id[1] %||% "")[1]
  entity_kind <- as.character(entity$entity_kind %||% entity[["entity_kind"]] %||% "")[1]
  entity_id <- as.character(entity$entity_id %||% entity[["entity_id"]] %||% "")[1]
  lin <- as.character(lineage_id %||% entity$group_id %||% entity[["group_id"]] %||% "")[1]

  out <- switch(
    action,
    open_smooth_plot = list(
      ref = ref,
      plot_type = "pseudotime_smooth_panel",
      params = list(lineage = lin, feature = entity_id),
      selection = list(entity_kind = entity_kind, entity_id = entity_id, lineage_id = lin),
      notes = "trajectory_de -> trajectory_smooth"
    ),
    open_de_plot = list(
      ref = ref,
      plot_type = "ranked_lollipop",
      params = list(lineage = lin, feature = entity_id),
      selection = list(entity_kind = entity_kind, entity_id = entity_id, lineage_id = lin),
      notes = "trajectory_smooth -> trajectory_de"
    ),
    open_signature_plot = list(
      ref = ref,
      plot_type = "pseudotime_signature_line",
      params = list(lineage = lin),
      selection = list(entity_kind = entity_kind, entity_id = entity_id, lineage_id = lin),
      notes = "trajectory_smooth -> trajectory_signature_smooth"
    ),
    compare_other_lineage = list(
      ref = ref,
      plot_type = .wb_nav_source_plot_type(src_op, src_tt),
      params = list(
        lineage = lin,
        feature = if (identical(entity_kind, "feature")) entity_id else NULL,
        feature_set = if (identical(entity_kind, "feature_set")) entity_id else NULL
      ),
      selection = list(entity_kind = entity_kind, entity_id = entity_id, lineage_id = lin),
      notes = "same-artifact comparison target"
    ),
    stop("Unsupported navigation action.", call. = FALSE)
  )
  out$source_ref <- resolved$ref
  out$target_action <- action
  out
}
