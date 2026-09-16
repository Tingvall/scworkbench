test_operation_pack_v2_feature_set_registry_gap_contract <- function() {
  schema <- jsonlite::read_json(
    "inst/protocol/operation-pack-v2.schema.json",
    simplifyVector = FALSE
  )
  validate <- getFromNamespace(".wb_json_schema_validate_2020", "scworkbench")

  # The frozen GenePrograms methods consume a core feature-set namespace, but
  # their public primitive inputs do not carry that registry snapshot.
  catalog <- getFromNamespace(".wb_op_catalog", "scworkbench")()
  pathway <- catalog$pathway_enrich
  overlap <- catalog$feature_set_overlap_qc
  stopifnot(
    identical(names(pathway$inputs), c("matrix", "feature_table")),
    identical(names(overlap$inputs), "matrix")
  )

  pathway_body <- paste(deparse(body(wb_op_pathway_enrich)), collapse = "\n")
  overlap_body <- paste(deparse(body(wb_op_feature_set_overlap_qc)), collapse = "\n")
  stopifnot(
    grepl("wb_feature_sets", pathway_body, fixed = TRUE),
    grepl("wb_feature_set_get", pathway_body, fixed = TRUE),
    grepl("wb_feature_sets", overlap_body, fixed = TRUE),
    grepl("wb_feature_set_get", overlap_body, fixed = TRUE)
  )

  # ABI v2 cannot declare an authenticated registry snapshot input. This is a
  # protocol rejection, not an implementation convention.
  proposed <- list(
    name = "feature_sets",
    kind = "feature_set_registry",
    required = TRUE,
    alignment = "feature_ordered"
  )
  result <- validate(proposed, schema[["$defs"]]$input, schema)
  stopifnot(!isTRUE(result$ok))

  # The live R adapter exposes exactly the declared readers. A matrix input
  # does not silently acquire registry authority or registry payload.
  matrix_input <- structure(list(
    kind = "matrix",
    matrix_id = "matrix_fixture",
    values = matrix(1, nrow = 1L, ncol = 1L,
      dimnames = list("feature_1", "cell_1")),
    dimensions = c(1L, 1L),
    feature_id = "feature_1",
    cell_id = "cell_1",
    storage_profile = "matrix_ordinary_v1",
    meta = list()
  ), class = "wb_primitive")
  stage <- tempfile("scwb_feature_set_reader_gap_")
  dir.create(stage, recursive = TRUE)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  adapter <- getFromNamespace(
    ".wb_operation_pack_v2_capability_adapter", "scworkbench"
  )(
    request = list(outputs = list()),
    operation = list(outputs = list()),
    inputs = list(matrix = matrix_input),
    stage_root = stage,
    bundle = NULL
  )
  stopifnot(
    identical(names(adapter$readers), "matrix"),
    is.null(adapter$readers$feature_sets),
    is.null(adapter$readers$feature_set_get),
    is.null(matrix_input$feature_sets),
    is.null(matrix_input$feature_set_membership)
  )

  fixture <- jsonlite::read_json(
    "tests/fixtures/operation-pack-v2-feature-set-registry-capability-gap.json",
    simplifyVector = FALSE
  )
  allowed <- unique(vapply(
    schema[["$defs"]]$input$oneOf,
    function(branch) as.character(branch$properties$kind$const),
    character(1)
  ))
  stopifnot(
    identical(sort(allowed, method = "radix"),
      sort(as.character(unlist(fixture$current_input_kinds)), method = "radix")),
    identical(as.character(fixture$blocked_operations),
      c("pathway_enrich", "feature_set_overlap_qc"))
  )

  message(
    "CAPABILITY GAP feature_set_registry schema_admitted=false ",
    "declared_readers=matrix frozen_operations=pathway_enrich,feature_set_overlap_qc"
  )
  TRUE
}
