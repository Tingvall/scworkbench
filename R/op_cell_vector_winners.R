.wb_winner_set_token <- function(x) {
  out <- gsub("[^A-Za-z0-9_]+", "_", as.character(x))
  out <- gsub("^_+|_+$", "", out)
  out[!nzchar(out)] <- "unknown"
  out
}

.wb_winner_scalar_chr <- function(x, default = "") {
  x <- x %||% default
  if (!length(x) || is.null(x)) return(as.character(default)[1])
  x <- as.character(x)[1]
  if (is.na(x)) as.character(default)[1] else x
}

.wb_cell_vector_family_score_matrix <- function(signal, signal_keys = NULL) {
  .wb_assert_kind(signal, "cell_vector_family")
  keys_all <- unique(as.character(signal$key))
  keys_all <- keys_all[!is.na(keys_all) & nzchar(keys_all)]
  .wb_assert(length(keys_all) > 0L, "signal has no non-empty keys.")

  keys_use <- if (is.null(signal_keys)) keys_all else intersect(as.character(signal_keys), keys_all)
  keys_use <- unique(as.character(keys_use))
  .wb_assert(length(keys_use) > 0L, "No signal_keys remain after filtering.")

  df <- data.frame(
    cell_id = as.character(signal$cell_id),
    key = as.character(signal$key),
    value = suppressWarnings(as.numeric(signal$value)),
    stringsAsFactors = FALSE
  )
  df <- df[df$key %in% keys_use, , drop = FALSE]
  .wb_assert(nrow(df) > 0L, "No score rows remain after signal_keys filtering.")
  .wb_assert(!anyDuplicated(df[, c("cell_id", "key"), drop = FALSE]),
             "signal contains duplicate cell_id/key pairs; expected one score per key/cell.")

  cells <- unique(as.character(df$cell_id))
  cells <- cells[!is.na(cells) & nzchar(cells)]
  mat <- matrix(NA_real_, nrow = length(cells), ncol = length(keys_use),
                dimnames = list(cells, keys_use))
  mat[cbind(match(df$cell_id, cells), match(df$key, keys_use))] <- df$value
  list(matrix = mat, cells = cells, keys = keys_use)
}

#' Assign winner labels from a `cell_vector_family`
#'
#' Reduces a continuous keyed per-cell score family to one winner row per cell,
#' including runner-up, margin, percentile, confidence score, confidence ranks,
#' and pruning status.
#'
#' @param signal `cell_vector_family` primitive.
#' @param signal_keys Optional key subset.
#' @param min_winners Minimum raw winner count required for a winner to pass
#'   pruning. Use `NULL` or `0` to keep all winners.
#' @param tie_method Tie handling passed to `max.col()`. Defaults to `"first"`
#'   to preserve Gate 2/Track 3 behavior.
#' @param source_score_artifact_id Optional source score artifact ID.
#' @param source_run_id Optional source run ID.
#' @param source_snapshot_id Optional source provenance snapshot ID.
#'
#' @return Standard op result with `outputs$winners` as an `obs_table`.
#' @export
wb_op_cell_vector_winners <- function(signal,
                                      signal_keys = NULL,
                                      min_winners = 10L,
                                      tie_method = c("first", "random", "last"),
                                      source_score_artifact_id = NULL,
                                      source_run_id = NULL,
                                      source_snapshot_id = NULL) {
  tie_method <- match.arg(as.character(tie_method)[1], c("first", "random", "last"))
  if (identical(tie_method, "random")) {
    stop("tie_method='random' is not supported for deterministic winner assignment.", call. = FALSE)
  }
  min_winners_i <- suppressWarnings(as.integer(min_winners %||% 0L)[1])
  .wb_assert(is.finite(min_winners_i) && min_winners_i >= 0L,
             "min_winners must be NULL or a non-negative integer.")

  sm <- .wb_cell_vector_family_score_matrix(signal, signal_keys = signal_keys)
  score_mat <- sm$matrix
  cells <- sm$cells
  keys <- sm$keys
  .wb_assert(ncol(score_mat) >= 1L, "winner assignment requires at least one key.")

  ok_any <- rowSums(is.finite(score_mat)) > 0L
  max_idx <- rep(NA_integer_, nrow(score_mat))
  if (any(ok_any)) {
    score_for_max <- score_mat[ok_any, , drop = FALSE]
    score_for_max[!is.finite(score_for_max)] <- -Inf
    if (identical(tie_method, "last")) {
      rev_idx <- max.col(score_for_max[, rev(seq_len(ncol(score_for_max))), drop = FALSE], ties.method = "first")
      max_idx[ok_any] <- ncol(score_for_max) - rev_idx + 1L
    } else {
      max_idx[ok_any] <- max.col(score_for_max, ties.method = "first")
    }
  }

  runner_idx <- max_idx
  if (ncol(score_mat) >= 2L && any(ok_any)) {
    runner_idx[ok_any] <- apply(score_mat[ok_any, , drop = FALSE], 1, function(v) {
      ord <- order(v, decreasing = TRUE, na.last = TRUE)
      ord[2]
    })
  }

  winner <- ifelse(is.na(max_idx), NA_character_, keys[max_idx])
  runner_up <- ifelse(is.na(runner_idx), NA_character_, keys[runner_idx])
  row_i <- seq_len(nrow(score_mat))
  winner_score <- rep(NA_real_, nrow(score_mat))
  runner_up_score <- rep(NA_real_, nrow(score_mat))
  winner_score[!is.na(max_idx)] <- score_mat[cbind(row_i[!is.na(max_idx)], max_idx[!is.na(max_idx)])]
  runner_up_score[!is.na(runner_idx)] <- score_mat[cbind(row_i[!is.na(runner_idx)], runner_idx[!is.na(runner_idx)])]
  margin <- winner_score - runner_up_score
  tie_count <- vapply(seq_len(nrow(score_mat)), function(i) {
    if (!is.finite(winner_score[i])) return(0L)
    sum(score_mat[i, ] == winner_score[i], na.rm = TRUE)
  }, integer(1))

  winner_percentile <- rep(NA_real_, nrow(score_mat))
  for (key in keys) {
    vals <- score_mat[, key]
    pct <- rank(vals, ties.method = "max", na.last = "keep") / length(vals)
    idx <- identical(FALSE, is.na(key)) & winner == key
    if (any(idx, na.rm = TRUE)) winner_percentile[idx] <- pct[idx]
  }
  confidence_score <- margin * winner_percentile
  confidence_rank_low <- rank(-confidence_score, ties.method = "max", na.last = "keep")
  confidence_rank_high <- rank(-confidence_score, ties.method = "min", na.last = "keep")

  counts <- table(winner[!is.na(winner) & nzchar(winner)])
  winner_count <- as.integer(counts[winner])
  winner_count[is.na(winner_count)] <- 0L
  passes_pruning <- winner_count >= min_winners_i
  pruned_winner <- ifelse(passes_pruning, winner, NA_character_)
  pruned_cell_set <- ifelse(
    passes_pruning,
    paste0("set:winner_", .wb_winner_set_token(winner)),
    NA_character_
  )
  pruning_status <- ifelse(passes_pruning, "kept", "dropped_min_winners")
  pruning_status[is.na(winner) | !nzchar(winner)] <- "no_finite_scores"
  winner_out <- ifelse(is.na(winner), "", winner)
  runner_up_out <- ifelse(is.na(runner_up), "", runner_up)
  pruned_winner_out <- ifelse(is.na(pruned_winner), "", pruned_winner)
  pruned_cell_set_out <- ifelse(is.na(pruned_cell_set), "", pruned_cell_set)

  tbl <- data.frame(
    cell_id = cells,
    winner = winner_out,
    winner_score = winner_score,
    runner_up = runner_up_out,
    runner_up_score = runner_up_score,
    margin = margin,
    winner_percentile = winner_percentile,
    confidence_score = confidence_score,
    confidence_rank_low = as.integer(confidence_rank_low),
    confidence_rank_high = as.integer(confidence_rank_high),
    tie_count = as.integer(tie_count),
    winner_count = as.integer(winner_count),
    passes_pruning = as.logical(passes_pruning),
    pruning_status = pruning_status,
    pruned_winner = pruned_winner_out,
    pruned_cell_set = pruned_cell_set_out,
    stringsAsFactors = FALSE
  )

  meta <- list(
    source_score_artifact_id = as.character(source_score_artifact_id %||% NA_character_)[1],
    source_run_id = as.character(source_run_id %||% NA_character_)[1],
    source_snapshot_id = as.character(source_snapshot_id %||% NA_character_)[1],
    vector_order = keys,
    winner_method = "argmax",
    tie_method = tie_method,
    min_winners = min_winners_i,
    confidence_method = "margin * winner_percentile",
    confidence_rank_method = "rank(-confidence_score), low=max, high=min",
    scworkbench_version = as.character(utils::packageVersion("scworkbench"))
  )

  list(
    outputs = list(
      winners = wb_prim_obs_table(
        table = tbl,
        table_type = "cell_vector_winners",
        entity_kind = "cell",
        meta = meta
      )
    ),
    params = list(
      signal_keys = keys,
      n_keys = length(keys),
      n_cells = length(cells),
      min_winners = min_winners_i,
      tie_method = tie_method,
      winner_method = "argmax",
      confidence_method = "margin * winner_percentile",
      n_winners_kept = length(unique(tbl$winner[tbl$passes_pruning])),
      n_winners_dropped = length(unique(tbl$winner[!tbl$passes_pruning & !is.na(tbl$winner)]))
    )
  )
}

#' Load a score artifact and assign cell winners
#'
#' Convenience wrapper around `wb_art_load(..., expected_kind =
#' "cell_vector_family")` and `wb_op_cell_vector_winners()`.
#'
#' @export
wb_cell_vector_winners_from_artifact <- function(bundle,
                                                artifact_id,
                                                signal_keys = NULL,
                                                min_winners = 10L,
                                                tie_method = "first") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  artifact_id <- as.character(artifact_id)[1]
  signal <- wb_art_load(bundle, artifact_id = artifact_id, expected_kind = "cell_vector_family")
  art <- wb_art_list(bundle)
  hit <- art[as.character(art$artifact_id) == artifact_id, , drop = FALSE]
  wb_op_cell_vector_winners(
    signal = signal,
    signal_keys = signal_keys,
    min_winners = min_winners,
    tie_method = tie_method,
    source_score_artifact_id = artifact_id,
    source_run_id = if (nrow(hit) && "source_run_id" %in% names(hit)) hit$source_run_id[[1]] else NULL,
    source_snapshot_id = if (nrow(hit) && "provenance_snapshot_id" %in% names(hit)) hit$provenance_snapshot_id[[1]] else NULL
  )
}

#' Register winner-derived cell sets
#'
#' Mutates bundle cell-set membership using a winner `obs_table` and returns a
#' manifest `obs_table` primitive. By default, only rows with
#' `passes_pruning == TRUE` are registered.
#'
#' @export
wb_register_winner_cell_sets <- function(bundle,
                                         winners,
                                         source_winner_artifact_id = NULL,
                                         cell_set_prefix = "winner_",
                                         winner_col = "winner",
                                         passes_col = "passes_pruning",
                                         source = "cell_vector_winners",
                                         created_by = NULL,
                                         replace = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  if (is.character(winners) && length(winners) == 1L && nzchar(winners)) {
    source_winner_artifact_id <- source_winner_artifact_id %||% winners
    winners <- wb_art_load(bundle, winners, expected_kind = "obs_table")
  }
  .wb_assert_kind(winners, "obs_table")
  .wb_assert(identical(as.character(winners$table_type), "cell_vector_winners"),
             "winners obs_table must have table_type='cell_vector_winners'.")

  tbl <- winners$table
  .wb_assert(all(c("cell_id", winner_col) %in% names(tbl)),
             "winner table must contain cell_id and winner columns.")
  if (passes_col %in% names(tbl)) {
    keep <- isTRUE(TRUE) & as.logical(tbl[[passes_col]])
    keep[is.na(keep)] <- FALSE
  } else {
    keep <- rep(TRUE, nrow(tbl))
  }

  source_score_artifact_id <- .wb_winner_scalar_chr(winners$meta$source_score_artifact_id)
  source_run_id <- .wb_winner_scalar_chr(winners$meta$source_run_id)
  source_snapshot_id <- .wb_winner_scalar_chr(winners$meta$source_snapshot_id)
  winners_use <- unique(as.character(tbl[[winner_col]][keep]))
  winners_use <- winners_use[!is.na(winners_use) & nzchar(winners_use)]
  winners_use <- sort(winners_use)

  rows <- lapply(winners_use, function(w) {
    ids <- as.character(tbl$cell_id[keep & as.character(tbl[[winner_col]]) == w])
    set_name <- paste0("set:", as.character(cell_set_prefix)[1], .wb_winner_set_token(w))
    desc <- paste0("Winner cells for ", w, " from cell_vector_winners")
    if (isTRUE(replace)) {
      wb_cell_set_replace(
        bundle = bundle,
        cell_set = set_name,
        cell_ids = ids,
        source = source,
        created_by = created_by,
        description = desc,
        strict = TRUE
      )
    } else {
      wb_cell_set_add(
        bundle = bundle,
        cell_set = set_name,
        cell_ids = ids,
        source = source,
        created_by = created_by,
        description = desc
      )
    }
    data.frame(
      cell_set = set_name,
      winner = w,
      n_cells = length(ids),
      selection_rule = paste0(winner_col, " == '", w, "' && ", passes_col, " == TRUE"),
      source_winner_artifact_id = .wb_winner_scalar_chr(source_winner_artifact_id),
      source_score_artifact_id = .wb_winner_scalar_chr(source_score_artifact_id),
      source_run_id = .wb_winner_scalar_chr(source_run_id),
      source_snapshot_id = .wb_winner_scalar_chr(source_snapshot_id),
      stringsAsFactors = FALSE
    )
  })

  manifest <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(
      cell_set = character(0),
      winner = character(0),
      n_cells = integer(0),
      selection_rule = character(0),
      source_winner_artifact_id = character(0),
      source_score_artifact_id = character(0),
      source_run_id = character(0),
      source_snapshot_id = character(0),
      stringsAsFactors = FALSE
    )
  }
  rownames(manifest) <- NULL

  wb_prim_obs_table(
    table = manifest,
    table_type = "winner_cell_set_manifest",
    entity_kind = "cell_set",
    meta = list(
      source_winner_artifact_id = .wb_winner_scalar_chr(source_winner_artifact_id),
      source_score_artifact_id = .wb_winner_scalar_chr(source_score_artifact_id),
      source_run_id = .wb_winner_scalar_chr(source_run_id),
      source_snapshot_id = .wb_winner_scalar_chr(source_snapshot_id),
      cell_set_prefix = as.character(cell_set_prefix)[1],
      winner_col = winner_col,
      passes_col = passes_col,
      replace = isTRUE(replace)
    )
  )
}
