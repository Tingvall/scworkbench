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

n_cells <- 600L
n_features <- 80L
cells <- sprintf("cell_%04d", seq_len(n_cells))
meta <- data.frame(
  cell_id = cells,
  sample = rep(c("sample_A", "sample_B"), each = n_cells / 2L),
  lineage = rep(c("naive", "transition", "effector"), each = n_cells / 3L),
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

feature_ids <- c("Cd3d", "Ms4a1", "Lef1", "Nkg7", "Mki67", "Tcf7",
                 sprintf("Gene_%03d", seq_len(n_features - 6L)))
progress <- seq(0, 1, length.out = n_cells)
set.seed(20260802L)
rates <- outer(seq_len(n_features), progress, function(feature, value) {
  0.5 + (feature %% 7L) * 0.25 +
    3 * abs(sin(pi * value + feature / 9)) +
    ifelse(feature %% 3L == 0L, 4 * value, 4 * (1 - value))
})
counts <- matrix(
  stats::rpois(n_features * n_cells, lambda = as.vector(rates)),
  nrow = n_features,
  dimnames = list(feature_ids, cells)
)

wb_attach_matrix(
  b,
  matrix_id = "RNA_counts",
  mat = counts,
  layer = "counts",
  feature_type = "gene",
  description = "Deterministic RNA count matrix for canonical integration contracts.",
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)

set.seed(20260803L)
branch_sign <- ifelse(progress > 0.35, ifelse(seq_len(n_cells) %% 2L == 0L, 1, -1), 0)
branch_strength <- pmax(progress - 0.35, 0) * 2.5
coords <- data.frame(
  cell_id = cells,
  dim1 = 4 * progress - 2 + stats::rnorm(n_cells, sd = 0.08),
  dim2 = sin(2 * pi * progress) + branch_sign * branch_strength + stats::rnorm(n_cells, sd = 0.08),
  stringsAsFactors = FALSE
)
wb_attach_space(
  b,
  space_id = "umap_golden",
  coords = coords,
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)

latent <- vapply(seq_len(20L), function(dim_index) {
  sin(progress * pi * (1 + dim_index / 4)) +
    cos(progress * pi * (dim_index %% 5L + 1L)) * 0.25 +
    progress * dim_index / 20
}, numeric(n_cells))
latent <- latent + matrix(stats::rnorm(length(latent), sd = 0.08), nrow = nrow(latent))
latent[, 2L] <- latent[, 2L] + branch_sign * branch_strength
latent[, 3L] <- latent[, 3L] - branch_sign * branch_strength * 0.5
colnames(latent) <- paste0("dim", seq_len(ncol(latent)))
rownames(latent) <- cells
wb_attach_space(
  b,
  space_id = "peakvi_space",
  coords = data.frame(cell_id = cells, latent, check.names = FALSE),
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)
wb_attach_space(
  b,
  space_id = "lsi",
  coords = data.frame(
    cell_id = cells,
    sweep(latent, 2L, seq(0.8, 1.2, length.out = ncol(latent)), `*`),
    check.names = FALSE
  ),
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)
wb_attach_space(
  b,
  space_id = "umap.peakvi_space",
  coords = coords,
  source = "golden_bundle",
  created_by = "make_golden_bundle"
)
wb_attach_space(
  b,
  space_id = "umap.atac",
  coords = transform(coords, dim1 = dim1 * 0.8 - dim2 * 0.2, dim2 = dim2 * 0.9 + dim1 * 0.1),
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
wb_cell_set_define(
  b,
  "set:il7",
  cells = tail(cells, 200L),
  description = "Golden late trajectory checkpoint",
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

# Add one promoted artifact so the generated fixture exercises artifact
# registry, primitive load, promotion, and persisted provenance contracts.
cluster_labels <- setNames(
  rep(c("golden_A", "golden_B", "golden_C"), each = n_cells / 3L),
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
  description = "Deterministic cell_vector artifact for cross-repo contract checks.",
  created_by = "make_golden_bundle",
  fail_fast = TRUE
))

wb_refresh_manifest(b)
wb_close_bundle(b)

cat("golden_bundle=", out_dir, "\n", sep = "")
