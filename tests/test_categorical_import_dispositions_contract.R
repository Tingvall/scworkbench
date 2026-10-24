test_categorical_import_dispositions_contract <- function() {
  n <- 187L
  counts <- Matrix::sparseMatrix(i = rep(1:2, length.out = n), j = seq_len(n), x = 1,
    dims = c(2L, n), dimnames = list(c("g1", "g2"), paste0("c", seq_len(n))))
  md <- S4Vectors::DataFrame(
    perturbation = paste0("p", seq_len(n)), small = rep(c("a", "b"), length.out = n),
    empty = rep(NA_character_, n))
  sce <- SingleCellExperiment::SingleCellExperiment(assays = list(counts = counts), colData = md)
  roots <- character(); on.exit(unlink(roots, recursive = TRUE), add = TRUE)
  run <- function(enabled, metadata_cols = NULL) {
    root <- tempfile("categorical_dispositions_"); roots <<- c(roots, root)
    b <- wb_bundle_from_sce(sce, root, categorical_cols = c("perturbation", "small", "empty", "absent", "cell_id"),
      create_cell_sets = enabled, metadata_cols = metadata_cols)
    wb_close_bundle(b)
    b <- wb_open_bundle(root, read_only = TRUE)
    on.exit(wb_close_bundle(b), add = TRUE)
    arts <- wb_art_list(b)
    tab <- wb_art_load(b, arts$artifact_id[arts$name == "container_ingest_report"], expected_kind = "obs_table")$table
    d <- jsonlite::fromJSON(tab$categorical_dispositions_json[[1]], simplifyVector = FALSE)
    stopifnot(length(d) == 5L)
    names(d) <- vapply(d, `[[`, "", "column")
    stopifnot(d$absent$status == "rejected", d$absent$reason == "column_missing_or_not_imported",
      d$cell_id$reason == "reserved_identity_column")
    retained <- wb_meta(b)
    if (is.null(metadata_cols)) {
      stopifnot(identical(retained$perturbation, as.character(md$perturbation)),
        identical(retained$small, as.character(md$small)), all(is.na(retained$empty)))
      stopifnot(d$perturbation$n_levels == 187L, d$perturbation$max_levels == 50L)
      if (enabled) {
        stopifnot(d$small$status == "created", length(d$small$set_ids) == 2L,
          d$perturbation$status == "skipped", d$perturbation$reason == "cardinality_exceeds_limit",
          d$empty$reason == "no_nonempty_labels",
          all(c("set:sce_small__a", "set:sce_small__b") %in% wb_cell_sets(b)))
      } else {
        stopifnot(all(vapply(d[c("small", "perturbation", "empty")], `[[`, "", "reason") == "cell_set_creation_disabled"),
          !any(grepl("^set:sce_", wb_cell_sets(b))))
      }
    } else stopifnot(d$perturbation$status == "rejected", !"perturbation" %in% names(retained))
  }
  run(TRUE); run(FALSE); run(TRUE, "small")
  TRUE
}
