test_op_pathway_enrich_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) > 0)
  mid <- as.character(mats$matrix_id[1])

  feats <- wb_feature_ids(b, matrix_id = mid)
  # The generated golden bundle is intentionally tiny. Attach a test-local
  # feature universe when needed so pathway overlap behavior is still tested.
  if (length(feats) < 120L) {
    mid <- "pathway_enrich_contract_counts"
    feats <- paste0("pathway_gene_", seq_len(120L))
    if (!mid %in% as.character(wb_matrices(b)$matrix_id)) {
      cells <- wb_cells(b, cell_set = "all")
      mat <- Matrix::Matrix(
        matrix(0, nrow = length(feats), ncol = length(cells),
               dimnames = list(feats, cells)),
        sparse = TRUE
      )
      wb_attach_matrix(
        b,
        matrix_id = mid,
        mat = mat,
        layer = "counts",
        feature_type = "gene",
        source = "test_op_pathway_enrich_contract",
        created_by = "test"
      )
    }
    feats <- wb_feature_ids(b, matrix_id = mid)
  }
  stopifnot(length(feats) >= 120L)

  # Create two feature sets in one namespace; op should test both.
  ns <- "test_pathway_ns"
  fs1 <- "set_alpha"
  fs2 <- "set_beta"
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs1,
    matrix_id = mid,
    feature_ids = feats[1:20],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs2,
    matrix_id = mid,
    feature_ids = feats[21:40],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )

  # Query overlaps both sets
  qtab <- data.frame(
    feature_id = c(feats[1:8], feats[21:28], feats[100:110]),
    p_val_adj = c(rep(1e-4, 16), rep(0.2, 11)),
    avg_log1p_fc = c(rep(0.8, 8), rep(-0.9, 8), rep(0.1, 11)),
    stringsAsFactors = FALSE
  )
  ft <- wb_prim_feature_table(qtab, table_type = "de_wilcox")

  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "pathway_enrich",
    inputs = list(
      matrix = mid,
      feature_table = ft,
      namespace = ns,
      p_adj_max = 0.05,
      min_set_size = 5,
      direction = "any",
      lfc_min_abs = 0
    )
  )

  run <- rr$run
  stopifnot("pathways" %in% names(run$outputs))
  out <- run$outputs$pathways
  stopifnot(identical(out$kind, "obs_table"))
  stopifnot(identical(out$table_type, "pathway_enrich"))
  stopifnot(identical(out$entity_kind, "pathway"))
  stopifnot(is.data.frame(out$table), nrow(out$table) >= 2)
  stopifnot(all(c("pathway", "namespace", "p_val", "p_val_adj", "overlap") %in% colnames(out$table)))
  stopifnot(all(as.character(out$table$namespace) == ns))
  stopifnot(all(c(fs1, fs2) %in% as.character(out$table$pathway)))

  TRUE
}
