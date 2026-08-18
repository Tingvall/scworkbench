#!/usr/bin/env Rscript

library(scworkbench)

root <- tempfile("installed_capsule_bundle_")
work <- tempfile("installed_capsule_work_")
export <- tempfile("installed_capsule_export_")
scaffold <- tempfile("installed_capsule_scaffold_")
dir.create(work)
on.exit(unlink(c(root, work, export, scaffold), recursive = TRUE, force = TRUE), add = TRUE)

b <- wb_init_bundle(root, overwrite = TRUE)
wb_define_cells(b, c("cell_a", "cell_b"))
script <- file.path(work, "terminal.R")
output <- file.path(work, "terminal.md")
writeLines("# researcher-owned terminal analysis", script)
writeLines("# Registered terminal evidence", output)

cap <- wb_capsule_register(
  b, "installed public capsule smoke",
  inputs = list(cells = wb_ref_metadata_field("core:cell_id")),
  script = script,
  outputs = list(report = list(path = output, role = "report", media_type = "text/markdown")),
  purpose = "dataset_specific_reporting",
  rationale = "Installed-package smoke for a question-specific terminal report.",
  catalog_review = list(
    catalog_identity = "scworkbench.operation_catalog",
    catalog_version = as.character(packageVersion("scworkbench")),
    reviewed_at = "2026-08-17T00:00:00Z",
    candidate_op_names = character(), decision = "retain_as_capsule"
  )
)
wb_finalize_recipient_bundle(b)
wb_close_bundle(b)

ro <- wb_open_bundle(root, read_only = TRUE)
wb_capsule_scaffold(
  ro, "installed scaffold smoke",
  inputs = list(cells = wb_ref_metadata_field("core:cell_id")),
  outputs = list(report = list(role = "report", media_type = "text/markdown", extension = ".md")),
  language = "R", out_dir = scaffold,
  purpose = "dataset_specific_reporting",
  rationale = "Installed-package portable scaffold contract."
)
scaffold_status <- system2(file.path(R.home("bin"), "Rscript"),
                           c("--vanilla", file.path(scaffold, "analysis.R"), root, scaffold))
stopifnot(
  identical(as.integer(scaffold_status), 0L),
  nrow(wb_capsules(ro)) == 1L,
  identical(wb_capsule(ro, cap$capsule_id)$replay_status, "not_verified"),
  file.exists(wb_capsule_script_path(ro, cap$capsule_id)),
  file.exists(wb_capsule_output_path(ro, cap$capsule_id, "report")),
  wb_entity_certificate(ro, "capsule", cap$capsule_id)$details$assurance_level == "content_registered"
)
wb_capsule_emit_reproduction(ro, cap$capsule_id, export)
status <- system2(file.path(R.home("bin"), "Rscript"),
                  c("--vanilla", file.path(export, "inspect.R"), root))
stopifnot(identical(as.integer(status), 0L))
wb_close_bundle(ro)
cat("installed public capsule smoke: OK\n")
