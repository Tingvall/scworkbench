test_op_feature_set_import_qc_contract <- function(bundle_dir) {
  iface_import <- wb_op_interface("feature_set_import")
  stopifnot(is.list(iface_import))
  stopifnot(identical(as.character(iface_import$produces$import_manifest$kind), "obs_table"))
  stopifnot("feature_set_import" %in% wb_list_ops())

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(nrow(mats) > 0L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- wb_feature_ids(b, matrix_id = matrix_id)
  stopifnot(length(feats) >= 6L)

  ns <- paste0("test_feature_import_", as.integer(Sys.time()))
  src <- tempfile("feature_sets_", fileext = ".rds")
  wide <- data.frame(
    TEST_A = c(feats[1:3], ".__missing_feature__."),
    TEST_B = c(feats[2:4], NA_character_),
    TEST_EMPTY = rep(".__missing_only__.", 4L),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  saveRDS(wide, src)

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "feature_set_import",
    inputs = list(
      matrix = wb_prim_matrix(matrix_id),
      source_path = src,
      source_format = "rds",
      namespace = ns,
      species = "mouse",
      gene_id_type = "gene_symbol",
      overwrite = TRUE,
      strict = FALSE,
      source_id = "test_wide_rds",
      source_version = "vtest",
      created_by = "test"
    ),
    notes = "test feature-set import"
  )
  s <- r1$session
  manifest <- r1$run$outputs$import_manifest
  stopifnot(inherits(manifest, "wb_primitive"))
  stopifnot(identical(as.character(manifest$table_type), "feature_set_import_manifest"))
  stopifnot(all(c("namespace", "feature_set", "n_genes_raw", "n_genes_mapped_to_bundle", "status") %in% colnames(manifest$table)))
  stopifnot(sum(as.character(manifest$table$status) == "imported") == 2L)
  stopifnot(sum(as.character(manifest$table$status) == "rejected") == 1L)

  fs <- wb_feature_sets(wb_session_view(s), matrix_id = matrix_id, namespace = ns)
  stopifnot(is.data.frame(fs), nrow(fs) == 2L)
  stopifnot(setequal(as.character(fs$feature_set), c("TEST_A", "TEST_B")))

  # Registry-mutating import remains core-owned.
  prom1 <- wb_session_promote_current(
    bundle = b,
    session = s,
    name_prefix = "Feature Set Import Test",
    fail_fast = TRUE,
    outputs = c("import_summary", "import_manifest", "rejected_sets")
  )
  stopifnot(is.data.frame(prom1$promoted), nrow(prom1$promoted) >= 3L)
  manifest_artifact_id <- as.character(prom1$promoted$artifact_id[
    as.character(prom1$promoted$output) == "import_manifest"
  ][1])
  stopifnot(nzchar(manifest_artifact_id))
  loaded_manifest <- wb_art_load(b, manifest_artifact_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_manifest$table_type), "feature_set_import_manifest"))

  dag <- wb_prov_bundle_dag(b)
  stopifnot(is.list(dag), is.data.frame(dag$edges))
  mut <- dag$edges[
    as.character(dag$edges$artifact_id) == manifest_artifact_id &
      as.character(dag$edges$edge_type) == "MUTATES_REGISTRY",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(mut) >= 2L)
  stopifnot(any(grepl(paste0("^feature_set:", ns, ":"), as.character(mut$to))))

  wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(wb_validate_bundle(bundle_dir)))

  TRUE
}
