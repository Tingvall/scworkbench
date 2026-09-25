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

  # Keep lineage key semantics aligned with wb_op_slingshot_fit output.
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

#' @keywords internal
.wb_reporting_trajectory_pt_from_monocle3 <- function(model) {
  .wb_monocle3_require_pkgs()
  cds <- .wb_reporting_trajectory_load_model_obj(model)

  pt <- monocle3::pseudotime(cds)
  pt <- suppressWarnings(as.numeric(pt))
  names(pt) <- as.character(names(monocle3::pseudotime(cds)) %||% names(pt))
  .wb_assert(length(pt) > 0, "trajectory model report: monocle3 pseudotime is empty.")
  .wb_assert(!is.null(names(pt)) && all(nzchar(names(pt))), "trajectory model report: monocle3 pseudotime names missing.")

  lin <- .wb_monocle3_lineage_paths(cds)
  rel <- .wb_monocle3_branch_membership_prim(cds, lin)
  rel_tbl <- wb_primitive_to_table(rel, include_context = FALSE)
  .wb_assert(is.data.frame(rel_tbl) && nrow(rel_tbl) > 0,
             "trajectory model report: monocle3 branch membership is empty.")

  keep <- as.character(rel_tbl$cell_id) %in% names(pt)
  rel_tbl <- rel_tbl[keep, c("key", "cell_id"), drop = FALSE]
  .wb_assert(nrow(rel_tbl) > 0, "trajectory model report: no overlap between monocle3 branch members and pseudotime.")

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
