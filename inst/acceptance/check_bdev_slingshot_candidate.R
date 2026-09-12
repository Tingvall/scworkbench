#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: check_bdev_slingshot_candidate.R CANDIDATE_RDS OUTPUT_BUNDLE", call. = FALSE)
}

candidate <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
bundle_dir <- normalizePath(args[[2L]], winslash = "/", mustWork = FALSE)
if (file.exists(bundle_dir) || dir.exists(bundle_dir)) {
  stop("OUTPUT_BUNDLE already exists: ", bundle_dir, call. = FALSE)
}

expected_sha256 <- "d536c8953b825d85689a0ee76367a8bd8569addd68a7e77ac9095a76b93c62ed"
expected_cells <- 23867L
expected_lineages <- 7L
expected_outputs <- 5L

actual_sha256 <- scworkbench::wb_source_sha256(candidate)
stopifnot(identical(actual_sha256, expected_sha256))
sds <- readRDS(candidate)
stopifnot(inherits(sds, "SlingshotDataSet"))

fit_coordinates <- as.matrix(methods::slot(sds, "reducedDim"))
stopifnot(
  nrow(fit_coordinates) == expected_cells,
  !is.null(rownames(fit_coordinates)),
  !anyDuplicated(rownames(fit_coordinates)),
  ncol(fit_coordinates) >= 2L
)

# Build a source-derived carrier with no analytical assay. It exists only to
# import the exact candidate cell universe and fitted coordinates through the
# public SCE ingestion/source-identity path.
carrier <- SingleCellExperiment::SingleCellExperiment(
  colData = S4Vectors::DataFrame(row.names = rownames(fit_coordinates))
)
SingleCellExperiment::reducedDim(carrier, "fit_space") <- fit_coordinates
source_id <- "bdev_slingshot_standalone_candidate"
source_identity <- list(
  source_type = "SlingshotDataSet",
  inputs = list(scworkbench::wb_source_input(
    path = candidate,
    source_id = source_id,
    accession = basename(candidate),
    role = "standalone_slingshot_fit_candidate",
    format = "rds",
    scope = "external_file"
  ))
)

b <- scworkbench::wb_bundle_from_sce(
  carrier,
  bundle_dir = bundle_dir,
  assays = character(0),
  reduced_dims = "fit_space",
  create_cell_sets = FALSE,
  overwrite = FALSE,
  created_by = "Forge bounded candidate acceptance",
  source_identity = source_identity
)
on.exit(try(scworkbench::wb_close_bundle(b), silent = TRUE), add = TRUE)

model <- scworkbench::wb_slingshot_adoption_model(
  bundle = b,
  sds = sds,
  fit_space_id = "fit_space",
  source_sha256 = actual_sha256,
  coordinate_tolerance = 0
)
stopifnot(
  model$n_lineages == expected_lineages,
  identical(model$coordinate_match_max_abs_difference, 0)
)

adopted <- scworkbench::wb_session_run_op(
  scworkbench::wb_session_new(), b, "slingshot_adopt",
  inputs = list(
    model = model,
    source = scworkbench::wb_ref_entity("external_source", source_id),
    cell_set = "all",
    min_cells = 1L
  ),
  notes = "Bounded technical adoption of explicitly supplied standalone Slingshot candidate"
)
stopifnot(length(adopted$run$outputs) == expected_outputs)
identities_before <- lapply(
  adopted$run$outputs[c("pseudotime", "lineage_weights", "curves")],
  function(x) scworkbench:::.wb_prov_payload_identity(b, x)$content_sha256
)

promoted <- scworkbench::wb_session_promote_current(
  b,
  adopted$session,
  outputs = names(adopted$run$outputs),
  name_prefix = "Bdev standalone Slingshot candidate",
  created_by = "Forge bounded candidate acceptance"
)
stopifnot(
  nrow(promoted$promoted) == expected_outputs,
  all(promoted$promoted$status == "ok")
)
artifact_ids <- stats::setNames(
  as.character(promoted$promoted$artifact_id),
  as.character(promoted$promoted$output)
)

finalized <- scworkbench::wb_finalize_recipient_bundle(b)
stopifnot(isTRUE(finalized$ready))
scworkbench::wb_close_bundle(b)
b <- NULL
stopifnot(isTRUE(scworkbench::wb_validate_bundle(bundle_dir, read_only = TRUE)))

read_only <- scworkbench::wb_open_bundle(bundle_dir, read_only = TRUE, validate = TRUE)
on.exit(try(scworkbench::wb_close_bundle(read_only), silent = TRUE), add = TRUE)
loaded <- lapply(artifact_ids, function(id) {
  scworkbench::wb_art_load(read_only, id)
})
identities_after <- lapply(
  loaded[c("pseudotime", "lineage_weights", "curves")],
  function(x) scworkbench:::.wb_prov_payload_identity(read_only, x)$content_sha256
)
stopifnot(
  identical(identities_after, identities_before),
  length(unique(c(
    loaded$pseudotime$meta$trajectory_fit_id,
    loaded$lineage_weights$meta$trajectory_fit_id,
    loaded$curves$meta$trajectory_fit_id,
    loaded$model$trajectory_fit_id
  ))) == 1L
)

cat("candidate_sha256=", actual_sha256, "\n", sep = "")
cat("cells=", nrow(fit_coordinates), "\n", sep = "")
cat("lineages=", model$n_lineages, "\n", sep = "")
cat("adopted_outputs=", length(adopted$run$outputs), "\n", sep = "")
cat("maximum_fit_space_coordinate_difference=", model$coordinate_match_max_abs_difference, "\n", sep = "")
cat("trajectory_fit_id=", model$trajectory_fit_id, "\n", sep = "")
cat("recipient_validation=PASS\n")
