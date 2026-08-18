suppressPackageStartupMessages(library(scworkbench))

root <- tempfile("scwb_installed_metadata_import_")
source_dir <- tempfile("scwb_installed_metadata_source_")
dir.create(source_dir)
on.exit(unlink(c(root, source_dir), recursive = TRUE, force = TRUE), add = TRUE)

bundle <- wb_init_bundle(root, overwrite = TRUE)
on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
wb_define_cells(bundle, c("c1", "c2", "c3"))
path <- file.path(source_dir, "metadata.csv")
writeLines(c("score,cell_id", "0.2,c1", "0.8,c3"), path)
source <- wb_source_input(
  path = path, source_id = "installed_smoke_metadata", accession = "installed-smoke",
  role = "cell_metadata", format = "csv", scope = "external_file"
)
plan <- wb_metadata_import(
  bundle, path, "cell_id", source, validate_only = TRUE
)
stopifnot(plan$valid, plan$counts$matched == 2L, plan$counts$unsupplied_known == 1L)
result <- wb_metadata_import(bundle, path, "cell_id", source)
stopifnot(nrow(result$fields) == 1L, result$fields$source_name == "score")
evidence <- wb_art_load(bundle, result$report_artifact_id, expected_kind = "obs_table")
stopifnot(evidence$table_type == "cell_metadata_import_evidence")
wb_close_bundle(bundle); bundle <- NULL
bundle <- wb_open_bundle(root)
stopifnot(nrow(wb_metadata_fields(bundle, include_core = FALSE)) == 1L)
cat("installed public metadata import smoke: OK\n")
