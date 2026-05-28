test_artifact_naming_contract <- function(bundle_dir) {
  tmp <- file.path(tempdir(), paste0("scwb_artifact_names_", as.integer(Sys.time())))
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  r1 <- wb_new_run(
    op_name = "de_wilcox",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = character(0),
      user_inputs = list(
        matrix = "RNA_counts",
        group_a = "set:case",
        group_b = "set:control"
      )
    ),
    params = list(
      matrix_id = "RNA_counts",
      min_pct = 0,
      p_adjust_method = "BH"
    ),
    outputs = list(
      de_table = wb_prim_feature_table(
        table = data.frame(
          feature_id = c("g1", "g2"),
          score = c(1.2, 0.4),
          stringsAsFactors = FALSE
        ),
        table_type = "de_wilcox"
      )
    ),
    notes = "synthetic de"
  )

  r2 <- wb_new_run(
    op_name = "pathway_enrich",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = c(r1$run_id),
      user_inputs = list(
        feature_table = wb_ref_run(r1$run_id, "de_table"),
        namespace = "bcell_gsea",
        direction = "up"
      )
    ),
    params = list(
      namespace = "bcell_gsea",
      direction = "up",
      n_pathways = 12L
    ),
    outputs = list(
      pathways = wb_prim_obs_table(
        table = data.frame(
          pathway = c("p1", "p2"),
          p_adj = c(0.01, 0.02),
          stringsAsFactors = FALSE
        ),
        table_type = "pathway_enrich",
        entity_kind = "pathway"
      )
    ),
    notes = "synthetic pathways"
  )

  runs <- list()
  runs[[r1$run_id]] <- r1
  runs[[r2$run_id]] <- r2

  prom <- wb_promote_analysis(
    bundle = b,
    runs = runs,
    head_run_id = r2$run_id,
    name_prefix = "Usecase 1",
    fail_fast = TRUE
  )

  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 2)

  arts <- wb_art_list(b)
  stopifnot(is.data.frame(arts), nrow(arts) >= 2)

  de_art <- arts[arts$source_op == "de_wilcox", , drop = FALSE]
  pw_art <- arts[arts$source_op == "pathway_enrich", , drop = FALSE]
  stopifnot(nrow(de_art) >= 1, nrow(pw_art) >= 1)

  de_name <- as.character(de_art$name[1])
  pw_name <- as.character(pw_art$name[1])

  stopifnot(grepl("Usecase 1 - DE:", de_name, fixed = TRUE))
  stopifnot(grepl("set:case vs set:control", de_name, fixed = TRUE))
  stopifnot(grepl("RNA_counts", de_name, fixed = TRUE))
  stopifnot(!grepl("__de_wilcox__", de_name, fixed = TRUE))

  stopifnot(grepl("Usecase 1 - Pathway Enrichment:", pw_name, fixed = TRUE))
  stopifnot(grepl("bcell_gsea", pw_name, fixed = TRUE))
  stopifnot(grepl("(up)", pw_name, fixed = TRUE))
  stopifnot(!grepl("__pathway_enrich__", pw_name, fixed = TRUE))

  TRUE
}
