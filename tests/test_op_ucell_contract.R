test_op_ucell_contract <- function() {
  if (!requireNamespace("UCell", quietly = TRUE)) {
    return(contract_test_skip("UCell is not installed."))
  }

  tmp <- tempfile("scwb_ucell_contract_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- c("c1", "c2", "c3", "c4")
  wb_define_cells(b, cells)

  mat <- Matrix::Matrix(
    matrix(
      c(
        5, 1, 0, 0,
        4, 1, 0, 0,
        0, 4, 5, 1,
        0, 3, 4, 2
      ),
      nrow = 4,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3", "g4"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  iface <- wb_op_interface("ucell", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "ucell"))
  stopifnot(identical(as.character(iface$produces$signature_scores$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$signature_summary$kind), "obs_table"))
  stopifnot("ncores" %in% vapply(iface$params, `[[`, character(1), "name"))
  stopifnot("parallel_backend" %in% vapply(iface$params, `[[`, character(1), "name"))
  stopifnot("ucell" %in% wb_list_ops())

  permuted <- data.frame(sig_a = c(3, 1, 4, 2), row.names = c("c3", "c1", "c4", "c2"))
  aligned <- .wb_ucell_align_score_rows(permuted, cells)
  stopifnot(identical(rownames(aligned), cells), identical(as.numeric(aligned$sig_a), c(1, 2, 3, 4)))
  stopifnot(inherits(try(.wb_ucell_align_score_rows(permuted[c(1, 2, 4), , drop = FALSE], cells), silent = TRUE), "try-error"))
  unexpected <- rbind(permuted, data.frame(sig_a = 5, row.names = "not_requested"))
  stopifnot(inherits(try(.wb_ucell_align_score_rows(unexpected, cells), silent = TRUE), "try-error"))
  duplicated <- permuted
  attr(duplicated, "row.names") <- c("c3", "c1", "c4", "c4")
  stopifnot(inherits(try(.wb_ucell_align_score_rows(duplicated, cells), silent = TRUE), "try-error"))

  raw <- wb_op_ucell(
    bundle = b,
    matrix_id = "RNA_counts",
    features = list(
      sig_a = c("g1", "g2", "g_missing"),
      sig_b = c("g3", "g4")
    ),
    cells = cells,
    max_rank = 100L,
    ncores = 1L,
    parallel_backend = "serial",
    missing_features_policy = "drop"
  )

  stopifnot(is.list(raw), is.list(raw$outputs))
  stopifnot(all(c("signature_scores", "signature_summary") %in% names(raw$outputs)))

  sc <- raw$outputs$signature_scores
  sm <- raw$outputs$signature_summary

  stopifnot(inherits(sc, "wb_primitive"), identical(as.character(sc$kind), "cell_vector_family"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(sm$table_type), "ucell_signature_summary"))
  stopifnot(identical(as.character(sm$entity_kind), "signature"))
  stopifnot(identical(sort(unique(as.character(sc$key))), c("sig_a", "sig_b")))
  stopifnot(length(sc$value) == length(cells) * 2L)

  expect_cols <- c(
    "entity_id", "signature", "n_features_input", "n_features_matched",
    "n_features_missing", "matched_features", "missing_features",
    "score_min", "score_q25", "score_median", "score_mean", "score_q75",
    "score_max", "n_cells"
  )
  stopifnot(all(expect_cols %in% colnames(sm$table)))

  sm_a <- sm$table[sm$table$entity_id == "sig_a", , drop = FALSE]
  stopifnot(nrow(sm_a) == 1L)
  stopifnot(identical(as.integer(sm_a$n_features_input), 3L))
  stopifnot(identical(as.integer(sm_a$n_features_matched), 2L))
  stopifnot(identical(as.integer(sm_a$n_features_missing), 1L))
  stopifnot(grepl("g_missing", as.character(sm_a$missing_features), fixed = TRUE))

  raw_chunked <- wb_op_ucell(
    bundle = b,
    matrix_id = "RNA_counts",
    features = list(
      sig_a = c("g1", "g2", "g_missing"),
      sig_b = c("g3", "g4")
    ),
    cells = cells,
    max_rank = 100L,
    ncores = 1L,
    parallel_backend = "serial",
    chunk_size = 2L,
    missing_features_policy = "drop"
  )
  stopifnot(is.list(raw_chunked$params$chunking))
  stopifnot(isTRUE(raw_chunked$params$chunking$enabled))
  stopifnot(identical(as.character(raw_chunked$params$chunking$axis), "cells"))
  stopifnot(identical(as.integer(raw_chunked$params$chunking$chunk_size), 2L))

  sc0 <- wb_primitive_to_table(raw$outputs$signature_scores, include_context = FALSE)
  sc1 <- wb_primitive_to_table(raw_chunked$outputs$signature_scores, include_context = FALSE)
  sc0 <- sc0[order(sc0$key, sc0$cell_id), , drop = FALSE]
  sc1 <- sc1[order(sc1$key, sc1$cell_id), , drop = FALSE]
  rownames(sc0) <- NULL
  rownames(sc1) <- NULL
  stopifnot(identical(as.character(sc0$key), as.character(sc1$key)))
  stopifnot(identical(as.character(sc0$cell_id), as.character(sc1$cell_id)))
  stopifnot(isTRUE(all.equal(as.numeric(sc0$value), as.numeric(sc1$value), tolerance = 1e-12)))

  raw_err <- try(
    wb_op_ucell(
      bundle = b,
      matrix_id = "RNA_counts",
      features = list(sig_bad = c("g_missing_only")),
      cells = cells,
      ncores = 1L,
      parallel_backend = "serial",
      missing_features_policy = "error"
    ),
    silent = TRUE
  )
  stopifnot(inherits(raw_err, "try-error"))

  TRUE
}
