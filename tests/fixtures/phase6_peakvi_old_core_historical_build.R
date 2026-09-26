args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Expected accepted old-core source and destination bundle paths.")
source <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
destination <- args[[2L]]
revision <- trimws(system2("git", c("-C", shQuote(source), "rev-parse", "HEAD"),
  stdout = TRUE))
if (!identical(revision, "d624cfd0cc1b84440681967fc30a214004e2c591"))
  stop("Historical fixture builder requires the exact accepted pilot core.")
pkgload::load_all(source, quiet = TRUE)
b <- scworkbench::wb_init_bundle(destination)
cells <- c("c2", "c1")
scworkbench::wb_define_cells(b, cells)
scworkbench::wb_attach_space(b, "historical_peakvi_space",
  data.frame(cell_id = cells, z1 = c(1, 2), z2 = c(3, 4)),
  source = "historical inspection fixture")
model_dir <- file.path(destination, "artifact_models", "historical_peakvi")
dir.create(model_dir, recursive = TRUE)
writeLines("retained model fixture", file.path(model_dir, "model.txt"))
model <- scworkbench::wb_prim_model_ref("historical_peakvi_space",
  "historical_peakvi_space", engine = "peakvi")
model$model_path <- model_dir
model$model_type <- "peakvi"
run <- scworkbench::wb_new_run("peakvi_fit", inputs = list(cell_set = "all",
  parents = character()), outputs = list(model = model))
session <- scworkbench::wb_session_add_run(scworkbench::wb_session_new(), run)
scworkbench::wb_session_promote_current(b, session, outputs = "model",
  created_by = "accepted-old-core-fixture")
scworkbench::wb_finalize_recipient_bundle(b)
scworkbench::wb_close_bundle(b)
