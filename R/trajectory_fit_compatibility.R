.wb_ref_to_artifact_id <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) == 1L && nzchar(x)) return(sub("^artifact:", "", as.character(x)[1]))
  if (is.list(x) && identical(as.character(x$ref_type %||% "")[1], "artifact")) {
    aid <- as.character(x$artifact_id %||% "")[1]
    if (nzchar(aid)) return(aid)
  }
  NULL
}

.wb_trajectory_artifact_provenance <- function(bundle, artifact_id) {
  aid <- as.character(artifact_id %||% "")[1]
  if (!nzchar(aid)) return(list())
  row <- DBI::dbGetQuery(
    bundle$con,
    "SELECT artifact_id, type, source_op, provenance_json
     FROM artifacts
     WHERE artifact_id = ?;",
    params = list(aid)
  )
  if (!nrow(row)) return(list())
  prov <- .wb_art_parse_provenance_json(row$provenance_json[1] %||% "")
  prov$artifact_id <- aid
  prov$artifact_type <- as.character(row$type[1] %||% "")
  prov$source_op <- as.character(row$source_op[1] %||% "")
  prov
}

.wb_trajectory_artifact_output_name <- function(bundle, artifact_id) {
  aid <- as.character(artifact_id %||% "")[1]
  if (!nzchar(aid) || !.wb_table_exists(bundle$con, "prov_run_outputs")) return("")
  out <- DBI::dbGetQuery(
    bundle$con,
    "SELECT output_name
     FROM prov_run_outputs
     WHERE artifact_id = ?
     ORDER BY snapshot_id DESC, run_id DESC
     LIMIT 1;",
    params = list(aid)
  )
  if (!nrow(out)) return("")
  as.character(out$output_name[1] %||% "")
}

.wb_trajectory_meta_from_artifact <- function(bundle, artifact_id) {
  prov <- .wb_trajectory_artifact_provenance(bundle, artifact_id)
  params <- prov$params %||% list()
  out_name <- .wb_trajectory_artifact_output_name(bundle, artifact_id)
  source_op <- as.character(prov$op_name %||% prov$source_op %||% "")[1]
  engine <- as.character(params$trajectory_engine %||% params$engine %||% "")[1]
  if (!nzchar(engine) && grepl("^slingshot(_|$)", source_op)) engine <- "slingshot"
  family_kind <- switch(
    out_name,
    pseudotime = "trajectory_pseudotime",
    lineage_weights = "trajectory_membership_weight",
    curves = "trajectory_curve_2d",
    ""
  )
  value_semantics <- switch(
    out_name,
    pseudotime = "lineage_specific_pseudotime",
    lineage_weights = "lineage_membership_weight",
    curves = "projected_lineage_curve",
    ""
  )
  list(
    trajectory_fit_id = as.character(params$trajectory_fit_id %||% "")[1],
    engine = engine,
    fit_space_id = as.character(params$fit_space_id %||% "")[1],
    n_lineages = suppressWarnings(as.integer(params$n_lineages %||% NA_integer_))[1],
    family_kind = family_kind,
    value_semantics = value_semantics,
    artifact_id = as.character(artifact_id)[1],
    output_name = out_name,
    source_op = source_op
  )
}

.wb_trajectory_hydrate_primitive_meta <- function(bundle, artifact_id, prim) {
  if (!.wb_is_primitive(prim)) return(prim)
  if (!as.character(prim$kind %||% "")[1] %in% c("cell_vector_family", "path_2d_family", "model_ref")) return(prim)
  meta <- .wb_trajectory_meta_from_artifact(bundle, artifact_id)
  if (!nzchar(as.character(meta$trajectory_fit_id %||% "")[1])) return(prim)
  if (identical(as.character(prim$kind), "model_ref")) {
    prim$trajectory_fit_id <- meta$trajectory_fit_id
    prim$fit_space_id <- meta$fit_space_id %||% prim$fit_space_id
    prim$n_lineages <- meta$n_lineages %||% prim$n_lineages
    return(prim)
  }
  # Current trajectory payloads persist their complete fit metadata in the
  # artifact descriptor. Adding artifact-context fields after loading would
  # change an otherwise identical content hash. Hydration is therefore only a
  # compatibility backfill for legacy payloads without a retained fit id.
  retained_fit_id <- as.character((prim$meta %||% list())$trajectory_fit_id %||% "")[1]
  if (nzchar(retained_fit_id)) return(prim)
  prim$meta <- modifyList(meta, prim$meta %||% list())
  prim
}

.wb_trajectory_primitive_keys <- function(prim) {
  if (!.wb_is_primitive(prim)) return(character(0))
  kind <- as.character(prim$kind %||% "")[1]
  keys <- if (identical(kind, "space_path_family")) {
    as.character(prim$path_id %||% character(0))
  } else {
    as.character(prim$key %||% character(0))
  }
  sort(unique(keys[nzchar(keys)]))
}

.wb_trajectory_primitive_cells <- function(prim) {
  if (!.wb_is_primitive(prim)) return(character(0))
  sort(unique(as.character(prim$cell_id %||% prim$cells %||% character(0))))
}

.wb_trajectory_resolve_primitive_for_fit <- function(bundle, x, runs = NULL) {
  if (.wb_is_primitive(x)) return(x)
  aid <- .wb_ref_to_artifact_id(x)
  if (!is.null(aid)) return(wb_art_load(bundle, artifact_id = aid))
  if (is.list(x) && identical(as.character(x$ref_type %||% "")[1], "run")) {
    .wb_assert(is.list(runs), "runs are required to resolve run refs.")
    run <- runs[[as.character(x$run_id)]]
    .wb_assert(!is.null(run), paste0("run not found: ", as.character(x$run_id)))
    prim <- run$outputs[[as.character(x$output)]]
    .wb_assert(.wb_is_primitive(prim), paste0("run output is not a primitive: ", as.character(x$output)))
    return(prim)
  }
  stop("unsupported trajectory reference.", call. = FALSE)
}

.wb_trajectory_info_from_primitive <- function(prim, artifact_id = "") {
  .wb_assert(.wb_is_primitive(prim), "trajectory fit info requires a primitive or artifact ref.")
  kind <- as.character(prim$kind %||% "")[1]
  meta <- prim$meta %||% list()
  data.frame(
    artifact_id = as.character(artifact_id %||% meta$artifact_id %||% prim$artifact_id %||% "")[1],
    primitive_kind = kind,
    output_name = as.character(meta$output_name %||% "")[1],
    source_op = as.character(meta$source_op %||% "")[1],
    trajectory_fit_id = as.character(meta$trajectory_fit_id %||% prim$trajectory_fit_id %||% "")[1],
    engine = as.character(meta$engine %||% prim$engine %||% "")[1],
    fit_space_id = as.character(meta$fit_space_id %||% prim$fit_space_id %||% prim$model_space_id %||% "")[1],
    n_lineages = suppressWarnings(as.integer(meta$n_lineages %||% prim$n_lineages %||% NA_integer_))[1],
    lineage_keys = paste(.wb_trajectory_primitive_keys(prim), collapse = ","),
    n_lineage_keys = length(.wb_trajectory_primitive_keys(prim)),
    n_cells = length(.wb_trajectory_primitive_cells(prim)),
    stringsAsFactors = FALSE
  )
}

#' Inspect trajectory fit-family identity for a trajectory artifact or primitive
#'
#' @param bundle Open scworkbench bundle.
#' @param x Trajectory primitive, artifact id, or `wb_ref_artifact()`.
#' @param runs Optional session runs for resolving run refs.
#'
#' @return One-row data frame with `trajectory_fit_id`, engine, lineage keys,
#'   and cell-count metadata where available.
#' @export
wb_trajectory_fit_info <- function(bundle, x, runs = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  aid <- .wb_ref_to_artifact_id(x)
  if (!is.null(aid)) {
    prim <- wb_art_load(bundle, artifact_id = aid)
    return(.wb_trajectory_info_from_primitive(prim, artifact_id = aid))
  }
  if (is.list(x) && identical(as.character(x$ref_type %||% "")[1], "run")) {
    .wb_assert(is.list(runs), "runs are required to resolve run refs.")
    run <- runs[[as.character(x$run_id)]]
    .wb_assert(!is.null(run), paste0("run not found: ", as.character(x$run_id)))
    prim <- run$outputs[[as.character(x$output)]]
    return(.wb_trajectory_info_from_primitive(prim))
  }
  if (.wb_is_primitive(x)) return(.wb_trajectory_info_from_primitive(x))
  stop("wb_trajectory_fit_info(): unsupported trajectory reference.", call. = FALSE)
}

#' Assert Trajectory Fit-Family Compatibility
#'
#' Fails loudly when trajectory artifacts come from different fit families.
#' Lineage labels such as `L1` are scoped to one `trajectory_fit_id` and are not
#' interchangeable across fits.
#'
#' @param bundle Open scworkbench bundle.
#' @param ... Trajectory primitives, artifact ids, or refs.
#' @param runs Optional session runs for run refs.
#' @param allow_legacy If TRUE, missing `trajectory_fit_id` emits a warning
#'   instead of an error. Use only for explicit legacy review.
#'
#' @return Invisibly returns a data frame of fit info rows.
#' @export
wb_trajectory_assert_fit_compatible <- function(bundle, ..., runs = NULL, allow_legacy = FALSE) {
  xs <- list(...)
  .wb_assert(length(xs) >= 2L, "Need at least two trajectory artifacts/primitives to validate compatibility.")
  infos <- do.call(rbind, lapply(xs, function(x) wb_trajectory_fit_info(bundle, x, runs = runs)))
  rownames(infos) <- NULL

  fit_ids <- unique(as.character(infos$trajectory_fit_id %||% ""))
  fit_ids <- fit_ids[nzchar(fit_ids)]
  if (length(fit_ids) == 0L) {
    msg <- paste(
      "trajectory artifacts are missing trajectory_fit_id;",
      "legacy trajectory artifacts cannot be assumed compatible by lineage label."
    )
    if (isTRUE(allow_legacy)) warning(msg, call. = FALSE) else stop(msg, call. = FALSE)
  } else if (length(fit_ids) > 1L || any(!nzchar(as.character(infos$trajectory_fit_id %||% "")))) {
    stop(
      "trajectory artifacts are from different trajectory fit families; cross-fit lineage labels are not interchangeable.",
      call. = FALSE
    )
  }

  engines <- unique(as.character(infos$engine %||% ""))
  engines <- engines[nzchar(engines)]
  if (length(engines) > 1L) {
    stop("trajectory artifacts use different trajectory engines and are not fit-family compatible.", call. = FALSE)
  }

  key_sets <- strsplit(as.character(infos$lineage_keys %||% ""), ",", fixed = TRUE)
  key_sets <- lapply(key_sets, function(x) sort(x[nzchar(x)]))
  non_empty_keys <- key_sets[vapply(key_sets, length, integer(1)) > 0L]
  if (length(non_empty_keys) >= 2L) {
    ref <- non_empty_keys[[1]]
    if (!all(vapply(non_empty_keys[-1], function(x) identical(x, ref), logical(1)))) {
      stop("trajectory artifacts from the same fit family have incompatible lineage keys.", call. = FALSE)
    }
  }

  cell_sets <- lapply(xs, function(x) {
    prim <- .wb_trajectory_resolve_primitive_for_fit(bundle, x, runs = runs)
    .wb_trajectory_primitive_cells(prim)
  })
  non_empty_cells <- cell_sets[vapply(cell_sets, length, integer(1)) > 0L]
  if (length(non_empty_cells) >= 2L) {
    ref <- non_empty_cells[[1]]
    if (!all(vapply(non_empty_cells[-1], function(x) setequal(x, ref), logical(1)))) {
      stop("trajectory artifacts have incompatible cell universes.", call. = FALSE)
    }
  }

  invisible(infos)
}
