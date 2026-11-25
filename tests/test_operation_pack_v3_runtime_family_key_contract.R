test_operation_pack_v3_runtime_family_key_contract <- function() {
  cells <- c("cell_2", "cell_1")
  grant <- list(schema = "scworkbench.operation_pack.runtime_family_key_grant.v1",
    ordered_cells = unname(as.list(cells)), cell_count = 2L,
    cell_order_identity = scworkbench:::.wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    maximum_keys = 2L, maximum_rows = 4L,
    family_outputs = list("deviation_z", "deviation_raw"),
    closure_outputs = list("deviation_z", "deviation_raw", "motif_summary"),
    row_order = "cell_major_then_declared_key_v1")
  grant$grant_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
    grant$schema, "grant excluding grant_identity", grant)
  seal <- scworkbench:::.wb_operation_pack_v3_rfk_seal(grant, cells,
    c("motif_z", "motif_a"))
  family <- wb_prim_cell_vector_family(
    c("motif_z", "motif_a", "motif_z", "motif_a"),
    c("cell_2", "cell_2", "cell_1", "cell_1"),
    c(NA_real_, 1.5, 2.5, NA_real_))
  stopifnot(identical(seal$key_count, 2L),
    identical(seal$row_count, 4L),
    isTRUE(scworkbench:::.wb_operation_pack_v3_rfk_assert_value(
      family, seal, cells)))
  reject <- function(value, pattern) {
    error <- tryCatch(force(value), error = identity)
    stopifnot(inherits(error, "error"),
      grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  reject(scworkbench:::.wb_operation_pack_v3_rfk_seal(grant, cells,
    c("motif_z", "motif_z")), "duplicated")
  reject(scworkbench:::.wb_operation_pack_v3_rfk_seal(grant, cells,
    c("motif_z", "motif_a", "motif_b")), "exceed")
  reordered <- family
  reordered$key[c(1L, 2L)] <- rev(reordered$key[c(1L, 2L)])
  reject(scworkbench:::.wb_operation_pack_v3_rfk_assert_value(reordered,
    seal, cells), "key_order")
  foreign <- family
  foreign$cell_id[[4L]] <- "foreign"
  reject(scworkbench:::.wb_operation_pack_v3_rfk_assert_value(foreign,
    seal, cells), "cell_order")
  short <- family
  short$value <- short$value[-4L]
  reject(scworkbench:::.wb_operation_pack_v3_rfk_assert_value(short,
    seal, cells), "row_count")
  for (value in c(NaN, Inf, -Inf)) {
    invalid <- family
    invalid$value[[1L]] <- value
    reject(scworkbench:::.wb_operation_pack_v3_rfk_assert_value(invalid,
      seal, cells), "nonfinite_values")
  }
  output <- function(name) {
    identity <- scworkbench:::.wb_operation_pack_v2_identity_plain(
      "scworkbench.test.output.v1", list(name = name))
    list(name = name, descriptor = list(
      observed_descriptor_identity = identity, content_identity = identity,
      payload_manifest_identity = identity))
  }
  request <- list(runtime_cell_family_key_grants = list(grant))
  receipt <- list(outputs = lapply(unlist(grant$closure_outputs), output))
  state <- list(runtime_family_key_seal = seal)
  receipt$runtime_cell_family_key_observations <-
    scworkbench:::.wb_operation_pack_v3_rfk_observation(request,
      state, receipt)
  stage <- tempfile("scwb-rfk-receipt-")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  for (name in unlist(grant$family_outputs)) {
    dir.create(file.path(stage, "outputs", name), recursive = TRUE)
    saveRDS(family, file.path(stage, "outputs", name,
      "payload.rds"))
  }
  stopifnot(isTRUE(scworkbench:::.wb_operation_pack_v3_rfk_receipt_audit(
    receipt, request, stage_root = stage)))
  missing <- receipt
  missing$outputs <- missing$outputs[-3L]
  reject(scworkbench:::.wb_operation_pack_v3_rfk_receipt_audit(
    missing, request, stage_root = stage), "omitted")
  self_rehashed <- receipt
  observation <- self_rehashed$runtime_cell_family_key_observations[[1L]]
  observation$seal$ordered_keys <- list("motif_a", "motif_z")
  observation$seal$key_order_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.runtime_family_keys.v1",
      observation$seal$ordered_keys)
  observation$seal$seal_identity <- NULL
  observation$seal$seal_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      observation$seal$schema, "seal excluding seal_identity",
      observation$seal)
  observation$observation_identity <- NULL
  observation$observation_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      observation$schema, "observation excluding observation_identity",
      observation)
  self_rehashed$runtime_cell_family_key_observations <- list(observation)
  reject(scworkbench:::.wb_operation_pack_v3_rfk_receipt_audit(
    self_rehashed, request, stage_root = stage),
    "Complete cell-major family differs")

  # The qualified chromVAR shape is admitted without allocating either
  # complete family.  A larger key set crosses the authenticated ceiling.
  large_cells <- paste0("cell_", seq_len(3730L))
  large_keys <- paste0("motif_", seq_len(2957L))
  large_grant <- grant
  large_grant$ordered_cells <- unname(as.list(large_cells))
  large_grant$cell_count <- length(large_cells)
  large_grant$cell_order_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", large_grant$ordered_cells)
  large_grant$maximum_keys <- 10000L
  large_grant$maximum_rows <- 12000000L
  large_grant$grant_identity <- NULL
  large_grant$grant_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      large_grant$schema, "grant excluding grant_identity", large_grant)
  large_seal <- scworkbench:::.wb_operation_pack_v3_rfk_seal(
    large_grant, large_cells, large_keys)
  stopifnot(identical(large_seal$row_count, 11029610L))
  reject(scworkbench:::.wb_operation_pack_v3_rfk_seal(
    large_grant, large_cells, paste0("motif_", seq_len(3218L))),
    "exceed")

  protocol <- system.file("protocol", package = "scworkbench")
  request_schema <- jsonlite::read_json(file.path(protocol,
    "operation-pack-transition-request-v3.schema.json"),
    simplifyVector = FALSE)
  receipt_schema <- jsonlite::read_json(file.path(protocol,
    "operation-pack-transition-receipt-v3.schema.json"),
    simplifyVector = FALSE)
  corpus <- jsonlite::read_json(file.path(protocol, "fixtures",
    "operation-pack-v3", "phase7-genomic-runtime-family-identities.json"),
    simplifyVector = FALSE)
  cases <- stats::setNames(corpus$cases,
    vapply(corpus$cases, `[[`, character(1), "name"))
  schema_grant <- cases$two_family_one_table_grant$preimage
  schema_grant$maximum_rows <- 12000000L
  schema_grant$grant_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      schema_grant$schema, "grant excluding grant_identity", schema_grant)
  stopifnot(isTRUE(scworkbench:::.wb_json_schema_validate_2020(
    schema_grant, request_schema$`$defs`$runtime_cell_family_key_grant,
    request_schema)$ok))
  oversized_grant <- schema_grant
  oversized_grant$maximum_rows <- 12000001L
  oversized_grant$grant_identity <- NULL
  oversized_grant$grant_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      oversized_grant$schema, "grant excluding grant_identity",
      oversized_grant)
  stopifnot(!isTRUE(scworkbench:::.wb_json_schema_validate_2020(
    oversized_grant,
    request_schema$`$defs`$runtime_cell_family_key_grant,
    request_schema)$ok))
  schema_seal <- cases$nonlexical_runtime_key_seal$preimage
  schema_seal$row_count <- 12000000L
  schema_seal$seal_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      schema_seal$schema, "seal excluding seal_identity", schema_seal)
  stopifnot(isTRUE(scworkbench:::.wb_json_schema_validate_2020(
    schema_seal, receipt_schema$`$defs`$runtime_cell_family_key_seal,
    receipt_schema)$ok))
  oversized_seal <- schema_seal
  oversized_seal$row_count <- 12000001L
  oversized_seal$seal_identity <- NULL
  oversized_seal$seal_identity <-
    scworkbench:::.wb_operation_pack_v2_identity_scoped(
      oversized_seal$schema, "seal excluding seal_identity",
      oversized_seal)
  stopifnot(!isTRUE(scworkbench:::.wb_json_schema_validate_2020(
    oversized_seal,
    receipt_schema$`$defs`$runtime_cell_family_key_seal,
    receipt_schema)$ok))

  # Transition receipts retain the legacy identity for ordinary tables, but
  # use the durable typed-row identity when canonical JSON v1 cannot represent
  # a finite subnormal p-value.
  ordinary <- wb_prim_obs_table(data.frame(p_value = 1e-300),
    table_type = "p_value_test")
  ordinary_identity <-
    scworkbench:::.wb_operation_pack_v2_output_content_identity(
      ordinary, "obs_table")
  stopifnot(identical(ordinary_identity$scheme,
    "scworkbench.obs_table.content.v1"))
  subnormal <- wb_prim_obs_table(data.frame(
    p_value = c(.Machine$double.xmin, 5e-324)),
    table_type = "p_value_test")
  subnormal_identity <-
    scworkbench:::.wb_operation_pack_v2_output_content_identity(
      subnormal, "obs_table")
  descriptor <- list(kind = "obs_table",
    content_identity = subnormal_identity)
  payload <- tempfile("scwb-subnormal-table-", fileext = ".rds")
  on.exit(unlink(payload, force = TRUE), add = TRUE)
  saveRDS(subnormal, payload, version = 3L, compress = FALSE)
  grant <- list(name = "motif_summary", descriptor = list(
    category = "terminal_artifact", kind = "obs_table",
    storage_profile = "terminal_primitive_v1",
    writer = "write_terminal_primitive",
    grant_identity = scworkbench:::.wb_operation_pack_v2_identity_plain(
      "test.grant.v1", list(name = "motif_summary")),
    expected_dimensions = c(0L, 0L), expected_alignment = "none",
    expected_ancestry_identity =
      scworkbench:::.wb_operation_pack_v2_identity_plain(
        "test.ancestry.v1", list()),
    expected_model_linkage = list(mode = "none"),
    semantic_constraints = list()))
  observed <- scworkbench:::.wb_operation_pack_v2_observed_descriptor(
    grant, list(value = subnormal, payload = payload,
      semantic_metadata = list()))
  reopened <- readRDS(payload)
  stopifnot(identical(subnormal_identity$scheme,
      "scworkbench.content.table.typed-row-json-fold.v1"),
    identical(observed$content_identity, subnormal_identity),
    identical(subnormal_identity$sha256,
      scworkbench:::.wb_operation_pack_v2_output_content_sha(
        reopened, descriptor)),
    identical(subnormal$table$p_value,
      c(.Machine$double.xmin, 5e-324)),
    identical(writeBin(reopened$table$p_value, raw(), size = 8L),
      writeBin(subnormal$table$p_value, raw(), size = 8L)))
  TRUE
}
