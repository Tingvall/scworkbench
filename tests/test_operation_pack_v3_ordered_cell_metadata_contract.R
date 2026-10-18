test_operation_pack_v3_ordered_cell_metadata_protocol_fixture_contract <- function() {
  path <- file.path("inst", "protocol", "fixtures", "operation-pack-v3",
    "phase6-ordered-cell-metadata-identities.json")
  raw <- paste(readLines(path, warn = FALSE), collapse = "")
  value <- .wb_operation_pack_parse_canonical_json(raw)
  stopifnot(identical(raw, .wb_operation_pack_canonical_json(value)))
  identities <- .wb_operation_pack_v3_registry_snapshot_identities(
    value$snapshot, "ordered_cell_metadata")
  stopifnot(identical(value$content_identity, identities$content),
    identical(value$source_identity, identities$source),
    identical(value$snapshot$fields[[1]]$values[[1]], "b"),
    is.null(value$snapshot$fields[[1]]$values[[2]]),
    identical(as.character(unlist(value$snapshot$cell_id)),
      c("cell_2", "cell_10")))
  altered <- value$snapshot
  altered$fields[[1]]$values[[2]] <- "a"
  stopifnot(!identical(.wb_operation_pack_v3_registry_snapshot_identities(
    altered, "ordered_cell_metadata")$content, identities$content))
  TRUE
}

test_operation_pack_v3_ordered_cell_metadata_resolution_contract <- function() {
  root <- tempfile("scwb-ordered-meta-")
  bundle <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE);
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1")
  metadata <- data.frame(cell_id = cells,
    batch = c("b", NA, "a"),
    quality = c(1.5, 2.25, NA_real_), stringsAsFactors = FALSE)
  wb_define_cells(bundle, cells, metadata = metadata)
  values <- matrix(seq_len(9L), nrow = 3L,
    dimnames = list(c("gene_2", "gene_1", "gene_3"), cells))
  wb_attach_matrix(bundle, "RNA_counts", Matrix::Matrix(values,
    sparse = TRUE), layer = "counts", feature_type = "gene")
  input <- list(kind = "matrix", matrix_id = "RNA_counts",
    cell_id = cells, feature_id = rownames(values))
  record <- list(descriptor_identity = list(scheme =
    "scworkbench.operation_pack.input_descriptor.v2",
    sha256 = strrep("a", 64L)), content_identity = list(scheme =
    "scworkbench.matrix.content.v1", sha256 = strrep("b", 64L)))
  declaration <- list(matrix_input = "matrix", field_parameters = list(
    list(parameter = "batch_key", role = "categorical",
      cardinality = "zero_or_one"),
    list(parameter = "continuous_covariates", role = "continuous",
      cardinality = "zero_or_more")))
  params <- list(batch_key = "batch", continuous_covariates = "quality")
  snapshot <- .wb_operation_pack_v3_cell_metadata_snapshot(bundle,
    declaration, list(matrix = input), list(matrix = record), params, cells)
  .wb_operation_pack_v3_registry_snapshot_validate(snapshot,
    "ordered_cell_metadata")
  stopifnot(identical(as.character(unlist(snapshot$cell_id)), cells),
    identical(vapply(snapshot$fields, `[[`, character(1), "name"),
      c("batch", "quality")),
    identical(snapshot$fields[[1]]$values[[1]], "b"),
    is.null(snapshot$fields[[1]]$values[[2]]),
    identical(snapshot$fields[[2]]$values[[1]], 1.5),
    is.null(snapshot$fields[[2]]$values[[3]]))
  reject <- function(input = input, params = params, cells = cells) {
    inherits(try(.wb_operation_pack_v3_cell_metadata_snapshot(bundle,
      declaration, list(matrix = input), list(matrix = record), params,
      cells), silent = TRUE), "try-error")
  }
  reordered <- input; reordered$cell_id <- rev(cells)
  stopifnot(reject(input = reordered),
    reject(cells = c("cell_2", "foreign", "cell_1")),
    reject(params = list(batch_key = "missing_field",
      continuous_covariates = "quality")),
    reject(params = list(batch_key = "batch",
      continuous_covariates = "batch")))
  declaration$name <- "cell_metadata"
  declaration$kind <- "ordered_cell_metadata"
  declaration$category <- "authenticated_core_registry_snapshot"
  declaration$reader <- "read_ordered_cell_metadata"
  declaration$row_order <- "matrix_effective_cell_order_v1"
  declaration$missing_value_policy <- "preserve_null_v1"
  declaration$call_discipline <- "single_use"
  stage <- tempfile("ordered-meta-stage-")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  operation <- list(registry_reads = list(declaration))
  issued <- .wb_operation_pack_v3_registry_read_records(bundle,
    operation, list(matrix = input), list(matrix = record), params,
    stage, cells, "session", "run", "generation",
    list(scheme = "scworkbench.scientific_state.v1",
      sha256 = strrep("c", 64L)))
  request <- list(registry_reads = issued$records,
    inputs = list(list(name = "matrix", descriptor = record)),
    execution_capability = list(source_state_identity = list(scheme =
      "scworkbench.scientific_state.v1", sha256 = strrep("c", 64L))))
  .wb_operation_pack_v3_registry_reads_assert_current(bundle, operation,
    list(matrix = input), params, request, cells, "session", "run",
    "generation")
  attr(request, "operation_pack_v3_registry_observations") <- issued$observations
  .wb_operation_pack_v3_registry_reads_assert_current(bundle, operation,
    list(matrix = input), params, request, cells, "session", "run",
    "generation")
  DBI::dbExecute(bundle$con,
    "UPDATE cells SET batch='tampered' WHERE cell_id='cell_2';")
  changed <- try(.wb_operation_pack_v3_registry_reads_assert_current(bundle,
    operation, list(matrix = input), params, request, cells, "session",
    "run", "generation"), silent = TRUE)
  stopifnot(inherits(changed, "try-error"), grepl(
    "Authenticated core snapshot changed", as.character(changed),
    fixed = TRUE))
  TRUE
}
