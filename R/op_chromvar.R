#' Run chromVAR With Genome-Backed Motif Matching
#'
#' Computes chromVAR deviations on a peak matrix using real peak coordinates,
#' genome-backed GC bias correction, and motif matching against a JASPAR PWM
#' collection.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Peak-count matrix identifier.
#' @param cells Explicit cell ids. Required in session context.
#' @param motif_library Canonical motif-library key from the motif registry.
#' @param motifs Optional motif-key subset within `motif_library`.
#' @param motif_match_set Optional canonical motif-match-set key. When provided,
#'   chromVAR reuses cached motif-to-peak matches instead of rerunning
#'   `motifmatchr::matchMotifs()`.
#' @param min_motif_peaks Minimum number of matched peaks per retained motif.
#' @param max_motif_peaks Optional maximum number of matched peaks per retained
#'   motif.
#' @param motif_p_cutoff Motifmatchr p-value cutoff.
#' @param motif_w Motifmatchr background window width.
#' @param seqlevels_mode Seqlevel policy. `"standard"` keeps only standard
#'   chromosomes from the loaded genome by default; `"all"` keeps all parsed
#'   seqlevels unless further restricted.
#' @param seqlevels_include Optional explicit seqlevels to keep after applying
#'   `seqlevels_mode`.
#' @param seqlevels_exclude Optional seqlevels to drop after applying
#'   `seqlevels_mode`.
#' @param background_iterations Number of chromVAR background iterations.
#' @param background_w chromVAR background matching window width.
#' @param background_bs chromVAR background matching bin count.
#'
#' @return A standard op result list with `deviation_z`, `deviation_raw`, and
#'   `motif_summary`.
#'
#' @export
wb_op_chromvar <- function(bundle,
                           matrix_id,
                           cells,
                           motif_library,
                           motifs = NULL,
                           motif_match_set = NULL,
                           min_motif_peaks = 10L,
                           max_motif_peaks = NULL,
                           motif_p_cutoff = 5e-05,
                           motif_w = 7L,
                           seqlevels_mode = c("standard", "all"),
                           seqlevels_include = NULL,
                           seqlevels_exclude = NULL,
                           background_iterations = 50L,
                           background_w = 0.1,
                           background_bs = 50L) {
  .wb_require_pkg("Matrix", "chromVAR")
  .wb_require_pkg("chromVAR", "chromVAR deviations")
  .wb_require_pkg("SummarizedExperiment", "chromVAR container")
  .wb_require_pkg("GenomicRanges", "chromVAR peak ranges")
  .wb_require_pkg("GenomeInfoDb", "chromVAR peak ranges")
  .wb_require_pkg("S4Vectors", "chromVAR container")
  .wb_require_pkg("BiocParallel", "chromVAR background matching")
  .wb_require_pkg("TFBSTools", "JASPAR motif loading")
  .wb_require_pkg("motifmatchr", "motif matching for chromVAR")
  seqlevels_mode <- match.arg(seqlevels_mode)

  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(!missing(cells) && length(cells) > 1,
             "Internal: wb_op_chromvar() must be called with >=2 cells (use wb_session_run_op).")
  .wb_assert(is.character(motif_library) && length(motif_library) == 1 && nzchar(motif_library),
             "motif_library must be a single non-empty string.")
  .wb_assert(is.null(motif_match_set) || (is.character(motif_match_set) && length(motif_match_set) == 1 && nzchar(motif_match_set)),
             "motif_match_set must be NULL or a single non-empty string.")
  .wb_assert(is.numeric(min_motif_peaks) && length(min_motif_peaks) == 1 && min_motif_peaks >= 1,
             "min_motif_peaks must be >= 1.")
  .wb_assert(is.null(max_motif_peaks) || (is.numeric(max_motif_peaks) && length(max_motif_peaks) == 1 && max_motif_peaks >= min_motif_peaks),
             "max_motif_peaks must be NULL or >= min_motif_peaks.")
  .wb_assert(is.numeric(motif_p_cutoff) && length(motif_p_cutoff) == 1 && is.finite(motif_p_cutoff) &&
               motif_p_cutoff > 0 && motif_p_cutoff < 1,
             "motif_p_cutoff must be a finite number in (0, 1).")
  .wb_assert(is.numeric(motif_w) && length(motif_w) == 1 && motif_w >= 1,
             "motif_w must be >= 1.")
  .wb_assert(is.null(seqlevels_include) || is.character(seqlevels_include),
             "seqlevels_include must be NULL or a character vector.")
  .wb_assert(is.null(seqlevels_exclude) || is.character(seqlevels_exclude),
             "seqlevels_exclude must be NULL or a character vector.")
  .wb_assert(is.numeric(background_iterations) && length(background_iterations) == 1 && background_iterations >= 1,
             "background_iterations must be >= 1.")
  .wb_assert(is.numeric(background_bs) && length(background_bs) == 1 && background_bs >= 2,
             "background_bs must be >= 2.")
  .wb_assert(is.numeric(background_w) && length(background_w) == 1 && is.finite(background_w) && background_w > 0,
             "background_w must be a positive finite number.")

  cells <- unique(as.character(cells))
  mats <- wb_matrices(bundle)
  mrow <- mats[as.character(mats$matrix_id) == matrix_id, , drop = FALSE]
  .wb_assert(nrow(mrow) == 1L, paste0("Unknown matrix_id: ", matrix_id))
  ftype <- as.character(mrow$feature_type[1] %||% "")
  .wb_assert(identical(ftype, "peak"),
             paste0("chromvar requires a peak matrix; matrix '", matrix_id, "' has feature_type='", ftype, "'."))
  genome_pkg <- as.character(mrow$genome_provider[1] %||% "")
  genome_build <- as.character(mrow$genome_build[1] %||% "")
  organism <- as.character(mrow$organism[1] %||% "")
  .wb_assert(nzchar(genome_pkg),
             paste0("chromvar requires matrix genome metadata; matrix '", matrix_id, "' is missing genome_provider."))
  .wb_require_pkg(genome_pkg, "chromVAR genome")

  features_tbl <- wb_features(bundle, matrix_id = matrix_id)
  libs <- wb_motif_libraries(bundle)
  lrow <- libs[as.character(libs$motif_library) == motif_library, , drop = FALSE]
  .wb_assert(nrow(lrow) == 1L, paste0("Unknown motif_library: ", motif_library))
  if (nzchar(as.character(lrow$organism[1] %||% "")) && nzchar(organism)) {
    .wb_assert(identical(as.character(lrow$organism[1]), organism),
               paste0("Motif library organism ('", lrow$organism[1], "') does not match matrix organism ('", organism, "')."))
  }
  if (nzchar(as.character(lrow$genome_build[1] %||% "")) && nzchar(genome_build)) {
    .wb_assert(identical(as.character(lrow$genome_build[1]), genome_build),
               paste0("Motif library genome_build ('", lrow$genome_build[1], "') does not match matrix genome_build ('", genome_build, "')."))
  }

  genome_obj <- .wb_chromvar_load_exported_singleton(genome_pkg, expected_class = "BSgenome")
  peak_ranges_all <- .wb_chromvar_peak_ranges(features_tbl, genome_pkg = genome_pkg)
  seqlevel_filter <- .wb_chromvar_filter_seqlevels(
    peak_ranges = peak_ranges_all,
    genome_obj = genome_obj,
    seqlevels_mode = seqlevels_mode,
    seqlevels_include = seqlevels_include %||% NULL,
    seqlevels_exclude = seqlevels_exclude %||% NULL
  )
  features_tbl <- features_tbl[seqlevel_filter$keep, , drop = FALSE]
  peak_ranges <- peak_ranges_all[seqlevel_filter$keep]
  all_features <- as.character(features_tbl$feature_id)
  .wb_assert(length(all_features) > 0L, paste0("Matrix '", matrix_id, "' has no features after seqlevel filtering."))

  counts <- wb_slice(bundle, matrix_id = matrix_id, features = all_features, cells = cells)
  .wb_assert(inherits(counts, "Matrix"), "chromvar requires wb_slice() to return a sparse Matrix.")
  counts <- methods::as(counts, "dgCMatrix")
  nonzero_peaks <- Matrix::rowSums(counts) > 0
  .wb_assert(any(nonzero_peaks),
             paste0("Matrix '", matrix_id, "' has no nonzero peaks in the selected cells after seqlevel filtering."))
  if (!all(nonzero_peaks)) {
    counts <- counts[nonzero_peaks, , drop = FALSE]
    peak_ranges <- peak_ranges[nonzero_peaks]
    features_tbl <- features_tbl[nonzero_peaks, , drop = FALSE]
    all_features <- as.character(features_tbl$feature_id)
  }
  motifs_obj <- .wb_motifs_load_tfbstools(bundle, motif_library = motif_library, motif_keys = motifs %||% NULL)
  motif_meta <- .wb_chromvar_motif_meta(motifs_obj)

  se <- SummarizedExperiment::SummarizedExperiment(
    assays = list(counts = counts),
    rowRanges = peak_ranges,
    colData = S4Vectors::DataFrame(
      cell_id = as.character(cells),
      row.names = as.character(cells)
    )
  )
  se <- chromVAR::addGCBias(se, genome = genome_obj)
  .wb_assert(nrow(motif_meta) > 0L, "No motifs remained after JASPAR filtering.")

  old_bp <- NULL
  if (requireNamespace("BiocParallel", quietly = TRUE)) {
    old_bp <- try(BiocParallel::registered(), silent = TRUE)
    suppressWarnings(BiocParallel::register(BiocParallel::SerialParam(), default = TRUE))
    on.exit({
      if (is.list(old_bp) && length(old_bp) >= 1L) {
        try(suppressWarnings(BiocParallel::register(old_bp[[1]], default = TRUE)), silent = TRUE)
      }
    }, add = TRUE)
  }

  match_source <- "computed"
  match_matrix <- NULL
  if (!is.null(motif_match_set)) {
    match_info <- wb_motif_match_sets(bundle, motif_match_set = motif_match_set)
    .wb_assert(nrow(match_info) == 1L, paste0("Unknown motif_match_set: ", motif_match_set))
    .wb_assert(identical(as.character(match_info$matrix_id[1]), matrix_id),
               paste0("motif_match_set '", motif_match_set, "' belongs to matrix_id='",
                      match_info$matrix_id[1], "', not '", matrix_id, "'."))
    .wb_assert(identical(as.character(match_info$motif_library[1]), motif_library),
               paste0("motif_match_set '", motif_match_set, "' belongs to motif_library='",
                      match_info$motif_library[1], "', not '", motif_library, "'."))
    match_matrix <- .wb_motif_match_matrix(
      bundle = bundle,
      motif_match_set = motif_match_set,
      feature_ids = all_features,
      motif_keys = motifs %||% NULL
    )
    match_source <- "registry"
  } else {
    match_matrix <- motifmatchr::matchMotifs(
      pwms = motifs_obj,
      subject = se,
      genome = genome_obj,
      p.cutoff = as.numeric(motif_p_cutoff),
      w = as.integer(motif_w)
    )
  }

  match_assay <- if (inherits(match_matrix, "RangedSummarizedExperiment") || inherits(match_matrix, "SummarizedExperiment")) {
    SummarizedExperiment::assay(match_matrix)
  } else {
    match_matrix
  }
  .wb_assert(inherits(match_assay, "Matrix") || is.matrix(match_assay),
             "chromvar motif matches must resolve to a matrix-like assay.")
  match_counts <- Matrix::colSums(match_assay)
  keep <- match_counts >= as.integer(min_motif_peaks)
  if (!is.null(max_motif_peaks)) {
    keep <- keep & match_counts <= as.integer(max_motif_peaks)
  }
  .wb_assert(any(keep),
             "No motifs remained after motif matching and peak-count filters.")

  if (inherits(match_matrix, "RangedSummarizedExperiment") || inherits(match_matrix, "SummarizedExperiment")) {
    matches <- match_matrix[, keep, drop = FALSE]
    match_assay <- SummarizedExperiment::assay(matches)
  } else {
    matches <- match_matrix[, keep, drop = FALSE]
    match_assay <- matches
  }
  match_counts <- as.integer(match_counts[keep])
  motif_meta <- motif_meta[match(colnames(match_assay), motif_meta$motif_key), , drop = FALSE]

  bg <- .wb_chromvar_get_background_peaks(
    se,
    niterations = as.integer(background_iterations),
    w = as.numeric(background_w),
    bs = as.integer(background_bs)
  )
  dev <- chromVAR::computeDeviations(se, matches, background_peaks = bg)
  var_tbl <- chromVAR::computeVariability(dev, bootstrap_error = FALSE)

  z_mat <- SummarizedExperiment::assay(dev, "z")
  d_mat <- SummarizedExperiment::assay(dev, "deviations")
  stopifnot(identical(rownames(z_mat), rownames(d_mat)), identical(colnames(z_mat), colnames(d_mat)))

  rd <- as.data.frame(SummarizedExperiment::rowData(dev))
  rd$motif_key <- rownames(z_mat)
  rd$matched_peaks <- match_counts[match(rd$motif_key, colnames(match_assay))]
  meta_tbl <- motif_meta[match(rd$motif_key, motif_meta$motif_key), , drop = FALSE]
  var_tbl$motif_key <- rownames(var_tbl)

  summary_tbl <- data.frame(
    motif_key = as.character(rd$motif_key),
    motif_id = as.character(meta_tbl$motif_id),
    motif_name = as.character(meta_tbl$motif_name),
    motif_library = as.character(motif_library),
    collection = as.character(lrow$collection[1] %||% NA_character_),
    source_id = as.character(lrow$source_id[1] %||% NA_character_),
    source_version = as.character(lrow$source_version[1] %||% NA_character_),
    genome_pkg = as.character(genome_pkg),
    genome_build = as.character(genome_build %||% NA_character_),
    organism = as.character(organism %||% NA_character_),
    matched_peaks = as.integer(rd$matched_peaks %||% NA_integer_),
    fraction_matches = as.numeric(rd$fractionMatches %||% NA_real_),
    fraction_background_overlap = as.numeric(rd$fractionBackgroundOverlap %||% NA_real_),
    variability = as.numeric(var_tbl$variability[match(rd$motif_key, var_tbl$motif_key)]),
    variability_p_value = as.numeric(var_tbl$p_value[match(rd$motif_key, var_tbl$motif_key)]),
    variability_p_value_adj = as.numeric(var_tbl$p_value_adj[match(rd$motif_key, var_tbl$motif_key)]),
    mean_abs_z = rowMeans(abs(z_mat), na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      deviation_z = .wb_chromvar_matrix_to_cvf(z_mat),
      deviation_raw = .wb_chromvar_matrix_to_cvf(d_mat),
      motif_summary = wb_prim_obs_table(
        summary_tbl,
        table_type = "chromvar_summary",
        entity_kind = "motif",
        meta = list(
          matrix_id = matrix_id,
          genome_pkg = as.character(genome_pkg),
          motif_library = as.character(motif_library),
          motif_match_set = if (is.null(motif_match_set)) NULL else as.character(motif_match_set),
          seqlevels_mode = as.character(seqlevels_mode),
          seqlevels_kept = seqlevel_filter$seqlevels_kept,
          n_peaks_input = as.integer(seqlevel_filter$n_input),
          n_peaks_retained = as.integer(seqlevel_filter$n_retained),
          n_peaks_nonzero = as.integer(length(all_features))
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      n_cells = length(cells),
      genome_pkg = as.character(genome_pkg),
      motif_library = as.character(motif_library),
      motifs = if (is.null(motifs)) NULL else as.character(motifs),
      motif_match_set = if (is.null(motif_match_set)) NULL else as.character(motif_match_set),
      motif_match_source = as.character(match_source),
      seqlevels_mode = as.character(seqlevels_mode),
      seqlevels_include = if (is.null(seqlevels_include)) NULL else unique(as.character(seqlevels_include)),
      seqlevels_exclude = if (is.null(seqlevels_exclude)) NULL else unique(as.character(seqlevels_exclude)),
      seqlevels_kept = seqlevel_filter$seqlevels_kept,
      seqlevels_dropped = seqlevel_filter$seqlevels_dropped,
      n_peaks_input = as.integer(seqlevel_filter$n_input),
      n_peaks_retained = as.integer(seqlevel_filter$n_retained),
      n_peaks_nonzero = as.integer(length(all_features)),
      n_motifs = nrow(summary_tbl),
      min_motif_peaks = as.integer(min_motif_peaks),
      max_motif_peaks = if (is.null(max_motif_peaks)) NULL else as.integer(max_motif_peaks),
      motif_p_cutoff = as.numeric(motif_p_cutoff),
      motif_w = as.integer(motif_w),
      background_iterations = as.integer(background_iterations),
      background_w = as.numeric(background_w),
      background_bs = as.integer(background_bs)
    )
  )
}

.wb_chromvar_peak_ranges <- function(features_tbl, genome_pkg) {
  .wb_assert(is.data.frame(features_tbl) && nrow(features_tbl) > 0L,
             "features_tbl must be a non-empty data.frame.")
  .wb_assert("feature_id" %in% colnames(features_tbl),
             "Peak features must expose feature_id.")

  chr <- if ("chr" %in% colnames(features_tbl)) as.character(features_tbl$chr) else rep(NA_character_, nrow(features_tbl))
  start <- if ("start" %in% colnames(features_tbl)) suppressWarnings(as.integer(features_tbl$start)) else rep(NA_integer_, nrow(features_tbl))
  end <- if ("end" %in% colnames(features_tbl)) suppressWarnings(as.integer(features_tbl$end)) else rep(NA_integer_, nrow(features_tbl))

  bad <- is.na(chr) | !nzchar(chr) | is.na(start) | is.na(end)
  if (any(bad)) {
    parsed <- .wb_chromvar_parse_peak_ids(as.character(features_tbl$feature_id[bad]))
    chr[bad] <- parsed$chr
    start[bad] <- parsed$start
    end[bad] <- parsed$end
    bad <- is.na(chr) | !nzchar(chr) | is.na(start) | is.na(end)
  }
  .wb_assert(!any(bad),
             "chromvar requires peak features with non-missing chr/start/end coordinates, either as columns or parseable feature_id values.")

  gr <- GenomicRanges::GRanges(
    seqnames = chr,
    ranges = IRanges::IRanges(
      start = start,
      end = end
    )
  )
  names(gr) <- as.character(features_tbl$feature_id)

  build <- sub("^.*\\.([A-Za-z0-9]+)$", "\\1", as.character(genome_pkg)[1])
  if (!identical(build, as.character(genome_pkg)[1])) {
    GenomeInfoDb::genome(gr) <- build
  }
  gr
}

.wb_chromvar_filter_seqlevels <- function(peak_ranges,
                                          genome_obj,
                                          seqlevels_mode = c("standard", "all"),
                                          seqlevels_include = NULL,
                                          seqlevels_exclude = NULL) {
  seqlevels_mode <- match.arg(seqlevels_mode)
  seqs <- as.character(GenomicRanges::seqnames(peak_ranges))
  observed <- unique(seqs)

  keep_levels <- if (identical(seqlevels_mode, "standard")) {
    intersect(observed, as.character(GenomeInfoDb::standardChromosomes(genome_obj)))
  } else {
    observed
  }
  if (!is.null(seqlevels_include)) {
    keep_levels <- intersect(keep_levels, unique(as.character(seqlevels_include)))
  }
  if (!is.null(seqlevels_exclude)) {
    keep_levels <- setdiff(keep_levels, unique(as.character(seqlevels_exclude)))
  }

  keep <- seqs %in% keep_levels
  .wb_assert(any(keep),
             "No peaks remained after chromVAR seqlevel filtering.")

  list(
    keep = keep,
    seqlevels_kept = unique(seqs[keep]),
    seqlevels_dropped = unique(seqs[!keep]),
    n_input = length(seqs),
    n_retained = sum(keep)
  )
}

.wb_chromvar_parse_peak_ids <- function(feature_ids) {
  ids <- as.character(feature_ids)
  ids <- trimws(ids)

  pat1 <- "^([^:]+):(\\d+)-(\\d+)$"
  pat2 <- "^([^\\-]+)-(\\d+)-(\\d+)$"

  chr <- rep(NA_character_, length(ids))
  start <- rep(NA_integer_, length(ids))
  end <- rep(NA_integer_, length(ids))

  m1 <- regexec(pat1, ids, perl = TRUE)
  p1 <- regmatches(ids, m1)
  ok1 <- lengths(p1) == 4L
  if (any(ok1)) {
    chr[ok1] <- vapply(p1[ok1], `[`, character(1), 2)
    start[ok1] <- as.integer(vapply(p1[ok1], `[`, character(1), 3))
    end[ok1] <- as.integer(vapply(p1[ok1], `[`, character(1), 4))
  }

  rem <- !ok1
  if (any(rem)) {
    m2 <- regexec(pat2, ids[rem], perl = TRUE)
    p2 <- regmatches(ids[rem], m2)
    ok2 <- lengths(p2) == 4L
    if (any(ok2)) {
      idx <- which(rem)[ok2]
      chr[idx] <- vapply(p2[ok2], `[`, character(1), 2)
      start[idx] <- as.integer(vapply(p2[ok2], `[`, character(1), 3))
      end[idx] <- as.integer(vapply(p2[ok2], `[`, character(1), 4))
    }
  }

  data.frame(
    chr = chr,
    start = start,
    end = end,
    stringsAsFactors = FALSE
  )
}

.wb_chromvar_load_exported_singleton <- function(pkg, expected_class = NULL) {
  obj <- try(getExportedValue(pkg, pkg), silent = TRUE)
  if (inherits(obj, "try-error")) {
    stop("Could not load exported singleton object from package: ", pkg, call. = FALSE)
  }
  if (!is.null(expected_class)) {
    .wb_assert(inherits(obj, expected_class),
               paste0("Package '", pkg, "' did not export an object of class '", expected_class, "'."))
  }
  obj
}

.wb_chromvar_motif_meta <- function(motifs) {
  data.frame(
    motif_key = names(motifs),
    motif_id = vapply(motifs, TFBSTools::ID, character(1)),
    motif_name = vapply(motifs, TFBSTools::name, character(1)),
    stringsAsFactors = FALSE
  )
}

.wb_chromvar_get_background_peaks <- function(object, niterations, w, bs) {
  tryCatch(
    chromVAR::getBackgroundPeaks(
      object,
      niterations = as.integer(niterations),
      w = as.numeric(w),
      bs = as.integer(bs)
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      needs_jitter <- grepl("chol.default\\(cov\\(norm_mat\\)\\)", msg) ||
        grepl("leading minor", msg, fixed = TRUE)
      if (!needs_jitter) stop(e)

      bias <- as.numeric(SummarizedExperiment::rowData(object)$bias %||% numeric(0))
      .wb_assert(length(bias) == nrow(object),
                 "chromVAR background fallback requires rowData(object)$bias.")
      scale0 <- stats::sd(bias, na.rm = TRUE)
      if (!is.finite(scale0) || scale0 <= 0) scale0 <- 1
      base_rank <- rank(bias, ties.method = "first") / max(1L, length(bias))
      attempts <- list(
        bias + base_rank * (scale0 * 1e-4),
        bias + base_rank * (scale0 * 1e-3),
        bias + base_rank * (scale0 * 1e-2),
        base_rank
      )

      last_err <- e
      for (bias_try in attempts) {
        out <- try(
          chromVAR::getBackgroundPeaks(
            object,
            bias = as.numeric(bias_try),
            niterations = as.integer(niterations),
            w = as.numeric(w),
            bs = as.integer(bs)
          ),
          silent = TRUE
        )
        if (!inherits(out, "try-error")) return(out)
        last_err <- out
      }
      stop(last_err)
    }
  )
}

.wb_chromvar_matrix_to_cvf <- function(mat) {
  rn <- rownames(mat)
  cn <- colnames(mat)
  .wb_assert(!is.null(rn) && !is.null(cn), "chromVAR output matrix must have row and column names.")
  wb_prim_cell_vector_family(
    key = rep(as.character(rn), times = ncol(mat)),
    cell_id = rep(as.character(cn), each = nrow(mat)),
    value = as.numeric(mat),
    value_type = "continuous"
  )
}
