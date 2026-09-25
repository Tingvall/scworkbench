.wb_slingshot_require_pkgs <- function() {
  .wb_require_pkg("SingleCellExperiment", "Slingshot container")
  .wb_require_pkg("S4Vectors", "ReducedDims container")
  .wb_require_pkg("slingshot", "Trajectory inference")
}

.wb_trajectory_fit_meta <- function(trajectory_fit_id,
                                    engine,
                                    fit_space_id = NULL,
                                    n_lineages = NULL,
                                    family_kind = NULL,
                                    value_semantics = NULL) {
  list(
    trajectory_fit_id = as.character(trajectory_fit_id %||% "")[1],
    engine = as.character(engine %||% "")[1],
    fit_space_id = as.character(fit_space_id %||% "")[1],
    n_lineages = suppressWarnings(as.integer(n_lineages %||% NA_integer_))[1],
    family_kind = as.character(family_kind %||% "")[1],
    value_semantics = as.character(value_semantics %||% "")[1]
  )
}

.wb_slingshot_pseudotime_prim <- function(sds, trajectory_fit_id = NULL, fit_space_id = NULL) {
  pt <- slingshot::slingPseudotime(sds)
  n_lin <- ncol(pt)
  lineage_ids <- paste0("L", seq_len(n_lin))
  cells_fit <- rownames(pt)

  pseudotime <- do.call(rbind, lapply(seq_len(n_lin), function(j) {
    data.frame(
      cell_id = cells_fit,
      lineage_id = lineage_ids[j],
      pseudotime = as.numeric(pt[, j]),
      stringsAsFactors = FALSE
    )
  }))
  pseudotime <- pseudotime[!is.na(pseudotime$pseudotime), , drop = FALSE]

  wb_prim_cell_vector_family(
    key = pseudotime$lineage_id,
    cell_id = pseudotime$cell_id,
    value = pseudotime$pseudotime,
    value_type = "continuous",
    meta = .wb_trajectory_fit_meta(
      trajectory_fit_id = trajectory_fit_id,
      engine = "slingshot",
      fit_space_id = fit_space_id,
      n_lineages = n_lin,
      family_kind = "trajectory_pseudotime",
      value_semantics = "lineage_specific_pseudotime"
    )
  )
}

.wb_slingshot_lineage_weights_prim <- function(sds, trajectory_fit_id = NULL, fit_space_id = NULL, promoted = FALSE) {
  w <- slingshot::slingCurveWeights(sds)
  .wb_assert(!is.null(w) && length(w) > 0, "slingshot lineage weights are empty.")
  w <- as.matrix(w)
  n_lin <- ncol(w)
  .wb_assert(n_lin >= 1L, "slingshot lineage weights have no lineage columns.")
  lineage_ids <- paste0("L", seq_len(n_lin))
  cells_fit <- rownames(w)
  .wb_assert(!is.null(cells_fit) && length(cells_fit) == nrow(w),
             "slingshot lineage weights are missing cell rownames.")

  weights <- do.call(rbind, lapply(seq_len(n_lin), function(j) {
    data.frame(
      cell_id = cells_fit,
      lineage_id = lineage_ids[j],
      weight = as.numeric(w[, j]),
      stringsAsFactors = FALSE
    )
  }))
  weights <- weights[!is.na(weights$weight), , drop = FALSE]
  vals <- suppressWarnings(as.numeric(weights$weight))
  bad <- is.finite(vals) & (vals < -1e-8 | vals > 1 + 1e-8)
  .wb_assert(!any(bad), "slingshot lineage weights must be in [0, 1] when finite.")
  weights$weight <- pmin(1, pmax(0, vals))

  wb_prim_cell_vector_family(
    key = weights$lineage_id,
    cell_id = weights$cell_id,
    value = weights$weight,
    value_type = "continuous",
    meta = modifyList(
      .wb_trajectory_fit_meta(
        trajectory_fit_id = trajectory_fit_id,
        engine = "slingshot",
        fit_space_id = fit_space_id,
        n_lineages = n_lin,
        family_kind = "trajectory_membership_weight",
        value_semantics = "lineage_membership_weight"
      ),
      list(range = c(0, 1), promoted = isTRUE(promoted))
    )
  )
}

.wb_slingshot_curves_prim <- function(sds) {
  curves <- slingshot::slingCurves(sds)
  lineage_ids <- paste0("L", seq_along(curves))
  curves_2d <- do.call(rbind, lapply(seq_along(curves), function(j) {
    s <- curves[[j]]$s
    data.frame(
      lineage_id = lineage_ids[j],
      point = seq_len(nrow(s)),
      x = as.numeric(s[, 1]),
      y = as.numeric(s[, 2]),
      stringsAsFactors = FALSE
    )
  }))

  wb_prim_path_2d_family(
    key = curves_2d$lineage_id,
    point = curves_2d$point,
    x = curves_2d$x,
    y = curves_2d$y
  )
}

.wb_path_2d_family_compact <- function(curves_prim, max_points_per_lineage = NULL) {
  .wb_assert_kind(curves_prim, "path_2d_family")
  if (is.null(max_points_per_lineage)) return(curves_prim)

  nmax <- suppressWarnings(as.integer(max_points_per_lineage)[1])
  if (is.na(nmax) || nmax <= 0) return(curves_prim)

  key <- as.character(curves_prim$key %||% character(0))
  point <- as.integer(curves_prim$point %||% integer(0))
  x <- as.numeric(curves_prim$x %||% numeric(0))
  y <- as.numeric(curves_prim$y %||% numeric(0))
  .wb_assert(length(key) == length(point) && length(point) == length(x) && length(x) == length(y),
             ".wb_path_2d_family_compact(): malformed path_2d_family lengths.")

  if (!length(key)) return(curves_prim)

  out_rows <- lapply(unique(key), function(k) {
    ii <- which(key == k)
    if (!length(ii)) return(NULL)
    # Respect incoming point order first; fall back to row order for ties/NAs.
    ord <- order(ifelse(is.na(point[ii]), seq_along(ii), point[ii]), seq_along(ii))
    ii <- ii[ord]
    n <- length(ii)
    if (n > nmax) {
      keep_idx <- unique(round(seq.int(1, n, length.out = nmax)))
      ii <- ii[keep_idx]
      n <- length(ii)
    }
    data.frame(
      key = rep(k, n),
      point = seq_len(n),
      x = x[ii],
      y = y[ii],
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, out_rows)
  if (is.null(out) || !nrow(out)) return(curves_prim)
  rownames(out) <- NULL
  wb_prim_path_2d_family(key = out$key, point = out$point, x = out$x, y = out$y)
}

#' Prepare An Existing Slingshot Fit For Adoption
#'
#' Validates an in-memory `SlingshotDataSet` against a retained bundle space
#' and returns a typed model reference for the registered `slingshot_adopt`
#' operation. The source object is not refitted. Callers should obtain `sds`
#' from the declared source object explicitly (for example, from a known Seurat
#' `misc` entry) rather than searching for a plausible fit.
#'
#' @param bundle Open scworkbench bundle containing the adopted fit space.
#' @param sds Existing `SlingshotDataSet` selected by the operator.
#' @param fit_space_id Retained space corresponding to the Slingshot fit
#'   coordinates.
#' @param source_sha256 SHA-256 of the declared external source file.
#' @param coordinate_tolerance Maximum absolute coordinate difference when
#'   matching the source fit to the retained bundle space.
#' @return A `model_ref(engine="slingshot")` primitive carrying the source fit
#'   in memory for a subsequent `slingshot_adopt` session run.
#' @export
wb_slingshot_adoption_model <- function(bundle,
                                        sds,
                                        fit_space_id,
                                        source_sha256,
                                        coordinate_tolerance = 1e-8) {
  .wb_slingshot_require_pkgs()
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(inherits(sds, "SlingshotDataSet"), "sds must inherit from SlingshotDataSet")
  .wb_assert(is.character(fit_space_id) && length(fit_space_id) == 1L && nzchar(fit_space_id),
             "fit_space_id must be one non-empty string")
  source_sha256 <- tolower(as.character(source_sha256 %||% "")[1])
  .wb_assert(grepl("^[0-9a-f]{64}$", source_sha256), "source_sha256 must be 64 lower-case hexadecimal characters")
  coordinate_tolerance <- suppressWarnings(as.numeric(coordinate_tolerance)[1])
  .wb_assert(is.finite(coordinate_tolerance) && coordinate_tolerance >= 0,
             "coordinate_tolerance must be finite and non-negative")

  source_coords <- as.matrix(methods::slot(sds, "reducedDim"))
  .wb_assert(nrow(source_coords) > 0L && ncol(source_coords) >= 2L,
             "SlingshotDataSet reducedDim must contain at least two dimensions")
  .wb_assert(!is.null(rownames(source_coords)) && !anyDuplicated(rownames(source_coords)),
             "SlingshotDataSet reducedDim must have unique cell rownames")
  .wb_assert(all(is.finite(source_coords)), "SlingshotDataSet reducedDim contains non-finite coordinates")
  cells <- as.character(rownames(source_coords))
  missing_cells <- setdiff(cells, wb_cells(bundle, cell_set = "all"))
  .wb_assert(!length(missing_cells), paste0(
    "SlingshotDataSet contains cells absent from the bundle: ",
    paste(utils::head(missing_cells, 10L), collapse = ", ")
  ))

  retained <- .wb_as_coord_matrix(wb_space(bundle, fit_space_id, cells = cells))
  retained <- retained[match(cells, rownames(retained)), , drop = FALSE]
  .wb_assert(ncol(retained) == ncol(source_coords),
             "retained fit space and SlingshotDataSet have different dimensions")
  max_difference <- max(abs(retained - source_coords))
  .wb_assert(max_difference <= coordinate_tolerance, paste0(
    "SlingshotDataSet coordinates do not match retained fit space; maximum absolute difference=",
    format(max_difference, scientific = TRUE)
  ))

  pseudotime <- slingshot::slingPseudotime(sds)
  weights <- slingshot::slingCurveWeights(sds)
  curves <- slingshot::slingCurves(sds)
  .wb_assert(ncol(pseudotime) >= 1L && ncol(weights) == ncol(pseudotime) && length(curves) == ncol(pseudotime),
             "SlingshotDataSet fit-family outputs disagree on lineage count")
  .wb_assert(identical(rownames(pseudotime), cells) && identical(rownames(weights), cells),
             "SlingshotDataSet fit-family outputs disagree on fitted cell order")
  curve_dimensions <- vapply(curves, function(curve) ncol(as.matrix(curve$s)), integer(1))
  .wb_assert(all(curve_dimensions == 2L),
             "slingshot_adopt currently requires source lineage curves fitted in exactly two dimensions")
  .wb_assert(all(vapply(curves, function(curve) all(is.finite(as.matrix(curve$s))), logical(1))),
             "SlingshotDataSet contains non-finite lineage-curve coordinates")

  source_object_sha256 <- digest::digest(sds, algo = "sha256", serialize = TRUE)
  trajectory_fit_id <- .wb_identifier_sha256(
    c(source_sha256, source_object_sha256, fit_space_id), "trajectory_fit"
  )
  model <- wb_prim_model_ref(fit_space_id, fit_space_id, engine = "slingshot")
  model$model_obj <- sds
  model$model_type <- "slingshot"
  model$fit_space_id <- fit_space_id
  model$cells <- cells
  model$n_lineages <- ncol(pseudotime)
  model$trajectory_fit_id <- trajectory_fit_id
  model$lineage_weight_family_kind <- "trajectory_membership_weight"
  model$source_derived <- TRUE
  model$source_sha256 <- source_sha256
  model$source_object_sha256 <- source_object_sha256
  model$coordinate_match_required <- TRUE
  model$coordinate_match_max_abs_difference <- max_difference
  model$coordinate_tolerance <- coordinate_tolerance
  model
}

.wb_slingshot_adoption_source <- function(bundle, source, expected_sha256) {
  ref <- .wb_capsule_normalize_ref(source, "source")
  .wb_assert(identical(ref$entity_kind, "external_source"),
             "slingshot_adopt source must reference an external_source")
  rows <- DBI::dbGetQuery(
    bundle$con,
    "SELECT source_json FROM prov_source_inputs WHERE source_id = ? ORDER BY snapshot_id, run_id;",
    params = list(ref$entity_id)
  )
  .wb_assert(nrow(rows) > 0L, paste0("slingshot_adopt source is not registered: ", ref$entity_id))
  checksums <- unique(vapply(rows$source_json, function(value) {
    parsed <- jsonlite::fromJSON(as.character(value), simplifyVector = FALSE)
    tolower(as.character(parsed$sha256 %||% parsed$checksum %||% "")[1])
  }, character(1)))
  checksums <- checksums[grepl("^[0-9a-f]{64}$", checksums)]
  .wb_assert(length(checksums) == 1L && identical(checksums, expected_sha256),
             "slingshot_adopt source checksum does not match the prepared model source")
  ref
}

#' Adopt An Existing Slingshot Fit Without Refitting
#'
#' Extracts a complete trajectory fit family from a source-derived Slingshot
#' model prepared by [wb_slingshot_adoption_model()]. The registered source is
#' consumed explicitly and upstream fitting remains external.
#'
#' @param bundle Open scworkbench bundle.
#' @param model_ref Source-derived Slingshot `model_ref` primitive.
#' @param cells Complete fitted cell universe in the canonical order resolved by
#'   the session engine. Its identities and order must exactly match the source
#'   model.
#' @param source Registered external-source reference created with
#'   [wb_ref_entity()].
#' @return Standard operation result containing pseudotime, lineage weights,
#'   two-dimensional curves, the adopted model, and an adoption summary.
#' @export
wb_op_slingshot_adopt <- function(bundle, model_ref, cells, source) {
  .wb_slingshot_require_pkgs()
  .wb_assert_kind(model_ref, "model_ref")
  .wb_assert(identical(as.character(model_ref$engine %||% "")[1], "slingshot"),
             "slingshot_adopt requires model_ref(engine='slingshot')")
  .wb_assert(isTRUE(model_ref$source_derived),
             "slingshot_adopt requires a source-derived model from wb_slingshot_adoption_model()")
  source_sha256 <- tolower(as.character(model_ref$source_sha256 %||% "")[1])
  source <- .wb_slingshot_adoption_source(bundle, source, source_sha256)
  model_cells <- as.character(model_ref$cells %||% character(0))
  .wb_assert(identical(as.character(cells), model_cells),
             "slingshot_adopt complete fitted cell universe and order must match the source model")
  sds <- model_ref$model_obj %||% NULL
  .wb_assert(inherits(sds, "SlingshotDataSet"), "slingshot_adopt model payload is unavailable")
  trajectory_fit_id <- as.character(model_ref$trajectory_fit_id %||% "")[1]
  fit_space_id <- as.character(model_ref$fit_space_id %||% model_ref$model_space_id %||% "")[1]

  pseudotime <- .wb_slingshot_pseudotime_prim(sds, trajectory_fit_id, fit_space_id)
  lineage_weights <- .wb_slingshot_lineage_weights_prim(sds, trajectory_fit_id, fit_space_id)
  curves <- .wb_slingshot_curves_prim(sds)
  curves$meta <- .wb_trajectory_fit_meta(
    trajectory_fit_id, "slingshot", fit_space_id,
    n_lineages = model_ref$n_lineages,
    family_kind = "trajectory_curve_2d",
    value_semantics = "source_derived_lineage_curve"
  )
  summary <- data.frame(
    source_id = source$entity_id,
    source_sha256 = source_sha256,
    source_object_sha256 = as.character(model_ref$source_object_sha256),
    trajectory_fit_id = trajectory_fit_id,
    fit_space_id = fit_space_id,
    n_cells = as.integer(length(model_cells)),
    n_lineages = as.integer(model_ref$n_lineages),
    coordinate_match_required = isTRUE(model_ref$coordinate_match_required),
    coordinate_match_max_abs_difference = as.numeric(model_ref$coordinate_match_max_abs_difference),
    upstream_execution = "external",
    scworkbench_refit_performed = FALSE,
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      pseudotime = pseudotime,
      lineage_weights = lineage_weights,
      curves = curves,
      model = model_ref,
      adoption_summary = wb_prim_obs_table(
        summary, table_type = "slingshot_adoption_summary",
        entity_kind = "trajectory_fit",
        meta = list(
          trajectory_fit_id = trajectory_fit_id,
          engine = "slingshot",
          source_derived = TRUE,
          upstream_execution = "external"
        )
      )
    ),
    params = as.list(summary[1, , drop = FALSE])
  )
}
