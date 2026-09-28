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
  TRUE
}
