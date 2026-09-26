# Read-only trajectory-model payload inspection for core reporting.
#' @keywords internal
.wb_reporting_trajectory_load_model_obj <- function(model) {
  .wb_assert_kind(model, "model_ref")
  obj <- model$model_obj %||% NULL
  if (!is.null(obj)) return(obj)

  path <- as.character(model$model_path %||% "")[1]
  .wb_assert(
    identical(as.character(model$deserialization_trust %||% "")[1], "trusted_provenance_or_runtime"),
    "MODEL_DESERIALIZATION_TRUST_REQUIRED: trajectory model_path deserialization requires a model_ref loaded through the trusted bundle boundary."
  )
  .wb_assert(nzchar(path) && file.exists(path),
             "trajectory model report requires model_ref with in-memory model_obj or readable model_path.")
  readRDS(path)
}

#' @keywords internal
.wb_reporting_trajectory_pt_from_slingshot <- function(model) {
  .wb_require_pkg("slingshot", "trajectory model report for slingshot models")
  sds <- .wb_reporting_trajectory_load_model_obj(model)
  pt <- slingshot::slingPseudotime(sds)
  .wb_assert(is.matrix(pt) || is.data.frame(pt), "trajectory model report: invalid slingshot pseudotime payload.")

  n_lin <- ncol(pt)
  .wb_assert(n_lin >= 1L, "trajectory model report: slingshot model has no lineages.")
  cells <- rownames(pt) %||% character(0)
  .wb_assert(length(cells) == nrow(pt), "trajectory model report: slingshot pseudotime rownames missing.")

  # Keep lineage keys aligned with retained and pack-produced Slingshot fits.
  keys <- paste0("L", seq_len(n_lin))
  out <- lapply(seq_len(n_lin), function(j) {
    data.frame(
      lineage_id = as.character(keys[j]),
      cell_id = as.character(cells),
      pseudotime = as.numeric(pt[, j]),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

# Read-only reporting reconstructs lineage keys from a retained CDS when a
# model_ref artifact does not carry the fit runner's transient lineage fields.
#' @keywords internal
.wb_reporting_monocle3_paths <- function(cds) {
  graph <- monocle3::principal_graph(cds)[["UMAP"]] %||% NULL
  aux <- monocle3::principal_graph_aux(cds)[["UMAP"]] %||% NULL
  .wb_assert(!is.null(graph) && !is.null(aux),
    "trajectory model report: Monocle3 graph is unavailable.")
  vertices <- as.character(igraph::V(graph)$name %||% character())
  roots <- unique(as.character(aux$root_pr_nodes %||% character()))
  roots <- roots[nzchar(roots)]
  .wb_assert(length(vertices) > 0L && length(roots) > 0L &&
    all(roots %in% vertices) && isTRUE(igraph::is_connected(graph)) &&
    isTRUE(igraph::is_tree(graph, mode = "all")),
    "trajectory model report: Monocle3 graph is not a rooted tree.")
  degree <- igraph::degree(graph)
  all_leaves <- as.character(names(degree)[degree == 1L])
  leaves <- setdiff(all_leaves, roots)
  use_root_leaves <- !length(leaves)
  if (use_root_leaves) leaves <- all_leaves
  .wb_assert(length(leaves) > 0L,
    "trajectory model report: Monocle3 graph has no terminal leaves.")
  paths <- lapply(leaves, function(leaf) {
    distances <- as.numeric(igraph::distances(graph, v = roots,
      to = leaf, mode = "all"))
    .wb_assert(any(is.finite(distances)),
      "trajectory model report: Monocle3 leaf is unreachable.")
    nearest <- which(is.finite(distances) &
      distances == min(distances[is.finite(distances)]))
    root <- sort(roots[nearest])[[1L]]
    route <- igraph::shortest_paths(graph, from = root, to = leaf,
      output = "vpath")$vpath[[1L]]
    nodes <- as.character(igraph::V(graph)[route]$name)
    .wb_assert(length(nodes) >= if (use_root_leaves) 1L else 2L,
      "trajectory model report: Monocle3 root-to-leaf path is invalid.")
    list(key = paste0("root:", root, "::lineage:", leaf), nodes = nodes)
  })
  stats::setNames(lapply(paths, `[[`, "nodes"),
    vapply(paths, `[[`, character(1), "key"))
}

#' @keywords internal
.wb_reporting_trajectory_pt_from_monocle3 <- function(model) {
  .wb_require_pkg("monocle3", "trajectory model report for Monocle3 models")
  .wb_require_pkg("igraph", "trajectory model report for Monocle3 models")
  cds <- .wb_reporting_trajectory_load_model_obj(model)

  pt <- monocle3::pseudotime(cds)
  pt <- suppressWarnings(as.numeric(pt))
  names(pt) <- as.character(names(monocle3::pseudotime(cds)) %||% names(pt))
  .wb_assert(length(pt) > 0, "trajectory model report: monocle3 pseudotime is empty.")
  .wb_assert(!is.null(names(pt)) && all(nzchar(names(pt))), "trajectory model report: monocle3 pseudotime names missing.")

  paths <- model$lineage_paths %||%
    .wb_reporting_monocle3_paths(cds)
  .wb_assert(is.list(paths) && length(paths) > 0L &&
    !is.null(names(paths)) && all(nzchar(names(paths))),
    "trajectory model report: Monocle3 model has no retained lineage paths.")
  graph <- monocle3::principal_graph(cds)[["UMAP"]] %||% NULL
  aux <- monocle3::principal_graph_aux(cds)[["UMAP"]] %||% NULL
  .wb_assert(!is.null(graph) && !is.null(aux),
    "trajectory model report: Monocle3 graph is unavailable.")
  closest <- aux$pr_graph_cell_proj_closest_vertex %||% NULL
  .wb_assert(!is.null(closest),
    "trajectory model report: Monocle3 closest-vertex mapping is unavailable.")
  if (is.matrix(closest) || is.array(closest)) {
    cell_ids <- rownames(closest)
    vertices <- closest[, 1L, drop = TRUE]
  } else {
    cell_ids <- names(closest)
    vertices <- closest
  }
  .wb_assert(length(cell_ids) == length(vertices) &&
    !anyDuplicated(cell_ids),
    "trajectory model report: Monocle3 closest-vertex mapping is malformed.")
  names_of_vertices <- as.character(igraph::V(graph)$name)
  if (is.numeric(vertices) || is.integer(vertices)) {
    indices <- suppressWarnings(as.integer(vertices))
    mapped <- rep(NA_character_, length(indices))
    valid <- !is.na(indices) & indices >= 1L &
      indices <= length(names_of_vertices)
    mapped[valid] <- names_of_vertices[indices[valid]]
  } else {
    mapped <- as.character(vertices)
    mapped[!mapped %in% names_of_vertices] <- NA_character_
  }
  rows <- lapply(seq_along(paths), function(i) {
    hit <- !is.na(mapped) & mapped %in% as.character(paths[[i]]) &
      cell_ids %in% names(pt)
    data.frame(key = rep(names(paths)[[i]], sum(hit)),
      cell_id = as.character(cell_ids[hit]), stringsAsFactors = FALSE)
  })
  rel_tbl <- do.call(rbind, rows)
  .wb_assert(nrow(rel_tbl) > 0L,
    "trajectory model report: no overlap between Monocle3 branch members and pseudotime.")

  data.frame(
    lineage_id = as.character(rel_tbl$key),
    cell_id = as.character(rel_tbl$cell_id),
    pseudotime = as.numeric(pt[as.character(rel_tbl$cell_id)]),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
.wb_reporting_trajectory_resolve_pt <- function(model) {
  pt_tbl <- model$pseudotime_table %||% model$pseudotime_df %||% NULL
  if (is.data.frame(pt_tbl)) {
    .wb_assert(all(c("lineage_id", "cell_id", "pseudotime") %in% colnames(pt_tbl)),
               "trajectory model report: model_ref pseudotime_table must contain lineage_id, cell_id, and pseudotime.")
    out <- pt_tbl[, c("lineage_id", "cell_id", "pseudotime"), drop = FALSE]
    out$lineage_id <- as.character(out$lineage_id)
    out$cell_id <- as.character(out$cell_id)
    out$pseudotime <- suppressWarnings(as.numeric(out$pseudotime))
    out <- out[nzchar(out$lineage_id) & nzchar(out$cell_id) & is.finite(out$pseudotime), , drop = FALSE]
    .wb_assert(nrow(out) > 0L, "trajectory model report: model_ref pseudotime_table has no finite pseudotime rows.")
    rownames(out) <- NULL
    return(out)
  }

  engine <- as.character(model$engine %||% "")[1]
  .wb_assert(nzchar(engine), "trajectory model report: model_ref is missing engine.")

  if (identical(engine, "slingshot")) return(.wb_reporting_trajectory_pt_from_slingshot(model))
  if (identical(engine, "monocle3")) return(.wb_reporting_trajectory_pt_from_monocle3(model))

  stop(
    "trajectory model report currently supports model_ref engines 'slingshot' and 'monocle3'. ",
    "Received engine='", engine, "'.",
    call. = FALSE
  )
}

#' @keywords internal
.wb_reporting_trajectory_lineages <- function(model, lineage = NULL, cells = NULL) {
  pt_df <- .wb_reporting_trajectory_resolve_pt(model)
  .wb_assert(is.data.frame(pt_df) && nrow(pt_df) > 0L,
             "trajectory model report: resolved pseudotime is empty.")

  if (!is.null(cells)) {
    keep_cells <- unique(as.character(cells))
    pt_df <- pt_df[as.character(pt_df$cell_id) %in% keep_cells, , drop = FALSE]
  }

  if (!is.null(lineage)) {
    lineage <- unique(as.character(lineage))
    lineage <- lineage[nzchar(lineage)]
    .wb_assert(length(lineage) > 0L, "trajectory model report: lineage is empty after cleaning.")
    pt_df <- pt_df[as.character(pt_df$lineage_id) %in% lineage, , drop = FALSE]
  }

  .wb_assert(nrow(pt_df) > 0L, "trajectory model report: no pseudotime rows remain after filters.")
  split(pt_df, as.character(pt_df$lineage_id))
}
