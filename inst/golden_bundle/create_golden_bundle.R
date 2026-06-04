#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x

out_dir <- if (length(args) >= 1L) args[[1L]] else file.path(
  normalizePath(file.path(getwd(), ".."), mustWork = FALSE),
  "fixtures",
  "golden_bundle",
  "scwb_golden"
)

cmd <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else "inst/golden_bundle/create_golden_bundle.R"
repo <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = FALSE)
if (!file.exists(file.path(repo, "DESCRIPTION"))) {
  repo <- normalizePath(file.path(getwd(), "scworkbench"), mustWork = FALSE)
}

load_engine <- function(repo_dir) {
  if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(repo_dir, quiet = TRUE)
    return(invisible(TRUE))
  }
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(repo_dir, quiet = TRUE)
    return(invisible(TRUE))
  }
  stop("Install devtools or pkgload to generate the golden bundle.", call. = FALSE)
}

load_engine(repo)

out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
dir.create(dirname(out_dir), recursive = TRUE, showWarnings = FALSE)

b <- wb_init_bundle(
  out_dir = out_dir,
  bundle_id = "scwb_golden",
  bundle_name = "scworkbench Golden Contract Bundle",
  overwrite = TRUE
)
on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)

cells <- sprintf("cell_%02d", seq_len(12))
meta <- data.frame(
  cell_id = cells,
  sample = rep(c("sample_A", "sample_B"), each = 6),
  lineage = rep(c("naive", "transition", "effector"), each = 4),
  batch = rep(c("batch_1", "batch_2", "batch_3"), length.out = length(cells)),
  stringsAsFactors = FALSE
)

wb_define_cells(
  b,
  cell_ids = cells,
  metadata = meta,
  dataset_id = meta$sample,
  set_name = "core",
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)

counts <- matrix(
  c(
    4, 3, 0, 1, 2, 2, 0, 0, 1, 3, 4, 5,
    0, 1, 4, 3, 2, 1, 0, 1, 2, 3, 2, 1,
    5, 4, 3, 2, 1, 0, 0, 1, 1, 2, 3, 4,
    0, 0, 1, 2, 5, 6, 5, 4, 2, 1, 0, 0,
    1, 1, 1, 1, 2, 3, 4, 5, 4, 3, 2, 1,
    2, 3, 5, 4, 3, 2, 1, 0, 1, 2, 4, 6
  ),
  nrow = 6,
  byrow = TRUE,
  dimnames = list(
    c("Cd3d", "Ms4a1", "Lef1", "Nkg7", "Mki67", "Tcf7"),
    cells
  )
)

wb_attach_matrix(
  b,
  matrix_id = "RNA_counts",
  mat = counts,
  layer = "counts",
  feature_type = "gene",
  description = "Tiny RNA count matrix for cross-repo contract checks.",
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)

coords <- data.frame(
  cell_id = cells,
  dim1 = c(-2.0, -1.6, -1.2, -0.8, -0.3, 0.0, 0.4, 0.8, 1.1, 1.4, 1.7, 2.0),
  dim2 = c(0.1, 0.4, 0.2, 0.7, 1.0, 0.8, 0.6, 0.2, -0.1, -0.4, -0.2, -0.5),
  stringsAsFactors = FALSE
)
wb_attach_space(
  b,
  space_id = "umap_golden",
  coords = coords,
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)

wb_cell_set_define(
  b,
  "set:sample_A",
  cells = cells[meta$sample == "sample_A"],
  description = "Golden sample A cells",
  created_by = "make_golden_bundle"
)
wb_cell_set_define(
  b,
  "set:effector",
  cells = cells[meta$lineage == "effector"],
  description = "Golden effector cells",
  created_by = "make_golden_bundle"
)

wb_feature_set_replace(
  b,
  feature_set = "golden_t_cell",
  matrix_id = "RNA_counts",
  feature_ids = c("Cd3d", "Lef1", "Tcf7"),
  namespace = "golden",
  organism = "mouse",
  origin = "fixture",
  description = "Tiny T-cell feature set for contract checks.",
  created_by = "make_golden_bundle"
)
wb_feature_set_replace(
  b,
  feature_set = "golden_activation",
  matrix_id = "RNA_counts",
  feature_ids = c("Nkg7", "Mki67"),
  namespace = "golden",
  organism = "mouse",
  origin = "fixture",
  description = "Tiny activation feature set for contract checks.",
  created_by = "make_golden_bundle"
)

# Add one tiny promoted artifact so the generated fixture exercises artifact
# registry, primitive load, promotion, and persisted provenance contracts.
cluster_labels <- setNames(
  rep(c("golden_A", "golden_B", "golden_C"), each = 4),
  cells
)
cluster_run <- wb_new_run(
  op_name = "leiden",
  inputs = list(
    cell_set = "core",
    effective_n = length(cells),
    parents = character(0),
    provenance_refs = list(),
    user_inputs = list(space_id = "umap_golden")
  ),
  params = list(
    space_id = "umap_golden",
    resolution = 0.10,
    fixture = TRUE
  ),
  outputs = list(
    clusters = wb_prim_cell_vector(cluster_labels, value_type = "categorical")
  ),
  notes = "golden bundle promoted artifact fixture"
)
runs <- list()
runs[[cluster_run$run_id]] <- cluster_run
invisible(wb_promote_analysis(
  bundle = b,
  runs = runs,
  head_run_id = cluster_run$run_id,
  name_prefix = "golden_fixture",
  description = "Tiny deterministic cell_vector artifact for cross-repo contract checks.",
  created_by = "make_golden_bundle",
  fail_fast = TRUE
))

wb_refresh_manifest(b)

cat("golden_bundle=", out_dir, "\n", sep = "")
