.wb_rf_install <- function() {
  library <- tempfile('scwb-rf-lib-'); dir.create(library)
  log <- tempfile('scwb-rf-install-', fileext = '.log')
  source <- file.path(normalizePath('.', mustWork = TRUE), 'tests',
    'fixtures', 'operation-pack-v3-phase5')
  status <- system2(file.path(R.home('bin'), 'R'), c('CMD', 'INSTALL',
    paste0('--library=', shQuote(library)), shQuote(source)),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = '\n'), call. = FALSE)
  old <- .libPaths(); .libPaths(c(library, old))
  manifest <- system.file('scworkbench', 'operation-pack.json',
    package = 'scwbV3Phase5', lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  list(library = library, old = old)
}

.wb_rf_cleanup <- function(fixture) {
  try(wb_operation_pack_unload('scwbv3phase5'), silent = TRUE)
  if ('scwbV3Phase5' %in% loadedNamespaces())
    try(unloadNamespace('scwbV3Phase5'), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_rf_bundle <- function() {
  root <- tempfile('scwb-rf-bundle-'); bundle <- wb_init_bundle(root)
  cells <- c('cell|z', 'cell:a', sprintf('cell_%03d', 3:24))
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, 'pca', matrix(seq_len(72), nrow = 24L,
    dimnames = list(cells, c('PC1', 'PC2', 'PC3'))))
  list(root = root, bundle = bundle, cells = cells)
}

.wb_rf_pairs <- function(cells) list(
  list(key = 'lineage|z', cell_id = cells[[3L]]),
  list(key = 'lineage:a', cell_id = cells[[2L]]),
  list(key = 'lineage|z', cell_id = cells[[1L]]),
  list(key = 'lineage:a', cell_id = cells[[4L]]))

.wb_rf_run <- function(state, mode = 'normal', keys = c('lineage|z',
    'lineage:a'), pairs = .wb_rf_pairs(state$cells))
  wb_session_run_op(wb_session_new(), state$bundle,
    'scwbv3phase5::sealed_relation_family', inputs = list(source = 'pca',
      keys = keys, pairs = pairs, mode = mode, cell_set = 'all',
      min_cells = 1L))

.wb_rf_records <- function(run) {
  root <- file.path(.wb_operation_pack_v2_store(run$session$staging_bundle),
    run$run$operation_pack_transition$transition_id)
  list(root = root,
    request = jsonlite::read_json(file.path(root, 'request.json'),
      simplifyVector = FALSE),
    receipt = jsonlite::read_json(file.path(root, 'receipt.json'),
      simplifyVector = FALSE))
}

.wb_rf_expect <- function(expr, codes) {
  error <- tryCatch(force(expr), error = identity)
  if (!inherits(error, c('wb_operation_pack_v3_error',
      'wb_operation_pack_v2_error'))) stop('Expected pack contract error: ',
        deparse(substitute(expr)), '; observed ', paste(class(error),
          collapse = '/'), if (inherits(error, 'error')) paste0(': ',
          conditionMessage(error)) else '', call. = FALSE)
  if (!as.character(error$code) %in% codes) stop('Unexpected code ',
    as.character(error$code), ': ', conditionMessage(error), call. = FALSE)
  invisible(error)
}

.wb_rf_rehash <- function(value, field) {
  identity <- value[[field]]
  value[[field]] <- NULL
  value[[field]] <- if (is.null(identity$scope))
    .wb_operation_pack_v2_identity_plain(identity$scheme, value) else
    .wb_operation_pack_v2_identity_scoped(identity$scheme,
      identity$scope, value)
  value
}

.wb_rf_durable_state <- function(bundle) {
  tables <- DBI::dbGetQuery(bundle$con,
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")$name
  list(fingerprint = .wb_manifest_registry_snapshot(bundle$con)$fingerprint,
    counts = stats::setNames(vapply(tables, function(table)
      as.integer(DBI::dbGetQuery(bundle$con, paste0('SELECT COUNT(*) AS n FROM ',
        DBI::dbQuoteIdentifier(bundle$con, table)))$n[[1L]]),
      integer(1)), tables))
}

test_operation_pack_v3_relation_family_identity_fixture_contract <-
    function() {
  fixture <- jsonlite::read_json(file.path('inst', 'protocol',
    'fixtures', 'operation-pack-v3',
    'relation-family-identities.json'), simplifyVector = FALSE)
  stopifnot(length(fixture$cases) == 14L)
  cases <- stats::setNames(fixture$cases, vapply(fixture$cases,
    `[[`, character(1), 'name'))
  for (item in cases)
    stopifnot(identical(.wb_operation_pack_sha256(item$preimage),
      item$identity$sha256))
  stopifnot(!identical(cases$relation_key_axis$identity$sha256,
      cases$relation_swapped_key_axis$identity$sha256),
    !identical(cases$relation_structured_pair_axis$identity$sha256,
      cases$relation_swapped_pair_axis$identity$sha256),
    !identical(cases$relation_separator_left$identity$sha256,
      cases$relation_separator_right$identity$sha256))
  request_schema <- jsonlite::read_json(file.path('inst', 'protocol',
    'operation-pack-transition-request-v3.schema.json'),
    simplifyVector = FALSE)
  receipt_schema <- jsonlite::read_json(file.path('inst', 'protocol',
    'operation-pack-transition-receipt-v3.schema.json'),
    simplifyVector = FALSE)
  for (entry in list(
      list(cases$relation_provisional_grant$value, request_schema,
        'sealed_relation_family_grant'),
      list(cases$relation_declaration$value, receipt_schema,
        'sealed_relation_declaration'),
      list(cases$relation_seal$value, receipt_schema,
        'sealed_relation_seal'),
      list(cases$relation_sealed_writer$value, receipt_schema,
        'sealed_relation_writer'),
      list(cases$relation_observation$value, receipt_schema,
        'sealed_relation_family_observation')))
    stopifnot(isTRUE(.wb_json_schema_validate_2020(entry[[1L]],
      entry[[2L]]$`$defs`[[entry[[3L]]]], entry[[2L]])$ok))
  stopifnot(isTRUE(.wb_json_schema_validate_2020(
      cases$relation_success_request$value, request_schema)$ok),
    isTRUE(.wb_json_schema_validate_2020(
      cases$relation_success_receipt$value, receipt_schema)$ok),
    isTRUE(.wb_operation_pack_v3_rf_receipt_audit(
      cases$relation_success_receipt$value,
      cases$relation_success_request$value)))
  TRUE
}

test_operation_pack_v3_relation_family_typed_lifecycle_contract <-
    function() {
  fixture <- .wb_rf_install(); state <- .wb_rf_bundle()
  on.exit({
    if (!is.null(state$bundle)) try(wb_close_bundle(state$bundle),
      silent = TRUE)
    .wb_rf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  run <- .wb_rf_run(state); record <- .wb_rf_records(run)
  grant <- record$request$sealed_relation_family_grants[[1L]]
  obs <- record$receipt$sealed_relation_family_observations[[1L]]
  pairs <- .wb_rf_pairs(state$cells)
  stopifnot(identical(grant$source_selector$source, 'typed_input_v1'),
    identical(unlist(grant$known_source_axis$ordered_cells,
      use.names = FALSE), state$cells),
    identical(unlist(obs$declaration$ordered_keys,
      use.names = FALSE), c('lineage|z', 'lineage:a')),
    identical(obs$seal$ordered_pair_axis_identity,
      .wb_operation_pack_v2_identity_plain('scworkbench.row_order.v1',
        pairs)),
    isTRUE(.wb_operation_pack_v2_record_validate(record$root,
      load_payloads = TRUE)$ok))
  registration <- .wb_operation_pack_registry$packs[['scwbv3phase5']]$
    registration
  operation <- Filter(function(x) identical(x$name,
    'sealed_relation_family'), registration$manifest$operations)[[1L]]
  forged_operation <- .wb_operation_pack_v2_deep_copy(operation)
  forged_policy <- forged_operation$dimension_policies[[1L]]
  forged_policy$maximum_rows <- 100L
  forged_policy <- .wb_rf_rehash(forged_policy, 'policy_identity')
  forged_operation$dimension_policies[[1L]] <- forged_policy
  forged_request <- .wb_operation_pack_v2_deep_copy(record$request)
  forged_grant <- forged_request$sealed_relation_family_grants[[1L]]
  forged_grant$manifest_policy_identity <-
    .wb_operation_pack_v3_unscoped_identity(
      forged_policy$policy_identity)
  forged_grant$limits$maximum_rows <- 101L
  forged_grant <- .wb_rf_rehash(forged_grant, 'grant_identity')
  forged_request$sealed_relation_family_grants[[1L]] <- forged_grant
  forged_request$outputs[[1L]]$descriptor$
    sealed_relation_family_provisional_grant <- forged_grant
  forged_request$outputs[[1L]]$descriptor <- .wb_rf_rehash(
    forged_request$outputs[[1L]]$descriptor, 'grant_identity')
  forged_request$execution_capability$
    sealed_relation_family_grant_identities <- list(
      .wb_operation_pack_v3_unscoped_identity(
        forged_grant$grant_identity))
  forged_request$execution_capability <- .wb_rf_rehash(
    forged_request$execution_capability, 'capability_identity')
  forged_request <- .wb_rf_rehash(forged_request, 'request_identity')
  bound_source <- .wb_operation_pack_v2_bind_inputs(
    run$session$staging_bundle, list(source = wb_prim_space('pca')),
    state$cells)
  .wb_rf_expect(.wb_operation_pack_v3_rf_request_audit(
    forged_request, forged_operation, run$session$staging_bundle,
    bound_source), 'PYBENCH_CAPABILITY_MISMATCH')
  value <- wb_operation_pack_transition_load(run$session$staging_bundle,
    run$run$operation_pack_transition$transition_id, 'relation')
  stopifnot(identical(value$key, vapply(pairs, `[[`, character(1),
      'key')),
    identical(value$cell_id, vapply(pairs, `[[`, character(1),
      'cell_id')),
    identical(value$weight, as.numeric(seq_along(pairs))))
  tampered <- .wb_operation_pack_v2_deep_copy(record$receipt)
  declaration <- tampered$sealed_relation_family_observations[[1L]]$
    declaration
  declaration$ordered_pairs <- rev(declaration$ordered_pairs)
  declaration <- .wb_rf_rehash(declaration, 'declaration_identity')
  tampered$sealed_relation_family_observations[[1L]]$declaration <-
    declaration
  seal <- tampered$sealed_relation_family_observations[[1L]]$seal
  seal$declaration_identity <- .wb_operation_pack_v3_unscoped_identity(
    declaration$declaration_identity)
  seal$ordered_pair_axis_identity <- .wb_operation_pack_v2_identity_plain(
    'scworkbench.row_order.v1', declaration$ordered_pairs)
  seal <- .wb_rf_rehash(seal, 'seal_identity')
  tampered$sealed_relation_family_observations[[1L]]$seal <- seal
  tampered$sealed_relation_family_observations[[1L]] <-
    .wb_rf_rehash(tampered$sealed_relation_family_observations[[1L]],
      'observation_identity')
  .wb_rf_expect(.wb_operation_pack_v3_rf_receipt_audit(tampered,
    record$request), 'PYBENCH_RECEIPT_MISMATCH')
  payload <- file.path(record$root, 'outputs', 'relation', 'payload.rds')
  original <- readBin(payload, what = 'raw', n = file.info(payload)$size)
  altered <- readRDS(payload); altered$key <- rev(altered$key)
  saveRDS(altered, payload)
  stopifnot(!isTRUE(.wb_operation_pack_v2_record_validate(record$root,
    load_payloads = TRUE)$ok))
  writeBin(original, payload)
  stopifnot(isTRUE(.wb_operation_pack_v2_record_validate(record$root,
    load_payloads = TRUE)$ok))
  promoted <- wb_session_promote_current(state$bundle, run$session,
    outputs = 'relation', created_by = 'relation-contract')
  try(wb_session_discard(run$session), silent = TRUE)
  stopifnot(nrow(promoted$promoted) == 1L,
    identical(promoted$promoted$status[[1L]], 'ok'))
  artifact_id <- promoted$promoted$artifact_id[[1L]]
  loaded <- wb_art_load(state$bundle, artifact_id,
    expected_kind = 'relation_family')
  stopifnot(identical(loaded$key, value$key),
    identical(loaded$cell_id, value$cell_id),
    identical(loaded$weight, value$weight))
  DBI::dbBegin(state$bundle$con)
  DBI::dbExecute(state$bundle$con,
    'UPDATE artifact_relation_rows SET weight = weight + 1 WHERE artifact_id = ?',
    params = list(artifact_id))
  altered_sql <- try(wb_art_load(state$bundle, artifact_id,
    expected_kind = 'relation_family'), silent = TRUE)
  DBI::dbRollback(state$bundle$con)
  stopifnot(inherits(altered_sql, 'try-error'))
  descriptor_row <- DBI::dbGetQuery(state$bundle$con,
    'SELECT provenance_json FROM artifacts WHERE artifact_id = ?',
    params = list(artifact_id))$provenance_json[[1L]]
  descriptor <- jsonlite::fromJSON(descriptor_row,
    simplifyVector = FALSE)
  descriptor$primitive_payload$content_identity$sha256 <-
    paste(rep('f', 64L), collapse = '')
  DBI::dbBegin(state$bundle$con)
  DBI::dbExecute(state$bundle$con,
    'UPDATE artifacts SET provenance_json = ? WHERE artifact_id = ?',
    params = list(jsonlite::toJSON(descriptor, auto_unbox = TRUE,
      null = 'null'), artifact_id))
  altered_descriptor <- try(wb_art_load(state$bundle, artifact_id,
    expected_kind = 'relation_family'), silent = TRUE)
  DBI::dbRollback(state$bundle$con)
  stopifnot(inherits(altered_descriptor, 'try-error'),
    isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle); state$bundle <- NULL
  state$bundle <- wb_open_bundle(state$root, read_only = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(state$root,
      level = 'recipient')$ok),
    identical(wb_art_load(state$bundle, artifact_id,
      expected_kind = 'relation_family')$cell_id, value$cell_id))
  relocated_root <- tempfile('scwb-rf-relocated-')
  fs::dir_copy(state$root, relocated_root)
  on.exit(unlink(relocated_root, recursive = TRUE, force = TRUE),
    add = TRUE)
  relocated <- wb_open_bundle(relocated_root, read_only = TRUE)
  on.exit(wb_close_bundle(relocated), add = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(relocated_root,
      level = 'recipient')$ok),
    identical(wb_art_load(relocated, artifact_id,
      expected_kind = 'relation_family')$key, value$key))
  TRUE
}

test_operation_pack_v3_relation_family_negative_and_rollback_contract <-
    function() {
  fixture <- .wb_rf_install(); state <- .wb_rf_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    options(scworkbench.test_relation_shadowed_pair = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_rf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  store <- .wb_operation_pack_v2_store(state$bundle)
  before <- sort(list.files(store, all.files = TRUE, no.. = TRUE))
  fingerprint <- .wb_manifest_registry_snapshot(state$bundle$con)$fingerprint
  durable <- .wb_rf_durable_state(state$bundle)
  for (mode in c('omit', 'repeat', 'write_before_declare',
      'swap_rows', 'non_finite')) {
    .wb_rf_expect(.wb_rf_run(state, mode = mode), c(
      'PYBENCH_CAPABILITY_MISMATCH', 'PYBENCH_OUTPUT_INVALID',
      'PYBENCH_RECEIPT_MISMATCH', 'PYBENCH_PROCESS_FAILED'))
    stopifnot(identical(sort(list.files(store, all.files = TRUE,
      no.. = TRUE)), before),
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$
        fingerprint, fingerprint),
      identical(.wb_rf_durable_state(state$bundle), durable),
      nrow(wb_art_list(state$bundle)) == 0L)
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, 'relation_family_sealed'))
      stop('caught relation seal fault'))
  .wb_rf_expect(.wb_rf_run(state, mode = 'caught_seal_fault'),
    c('PYBENCH_CAPABILITY_MISMATCH', 'PYBENCH_PROCESS_FAILED'))
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  invalid <- .wb_rf_pairs(state$cells)
  invalid[[1L]]$cell_id <- 'foreign'
  .wb_rf_expect(.wb_rf_run(state, pairs = invalid),
    c('PYBENCH_OUTPUT_INVALID', 'PYBENCH_PROCESS_FAILED'))
  invalid <- .wb_rf_pairs(state$cells)
  invalid[[4L]] <- invalid[[2L]]
  .wb_rf_expect(.wb_rf_run(state, pairs = invalid),
    c('PYBENCH_OUTPUT_INVALID', 'PYBENCH_PROCESS_FAILED'))
  for (attack in list(
      list(index = 1L, field = 'cell_id', value = 'foreign'),
      list(index = 1L, field = 'key', value = 'unknown'),
      list(index = 3L, field = 'cell_id', value = 'foreign',
        split_chunks = TRUE))) {
    options(scworkbench.test_relation_shadowed_pair = attack)
    .wb_rf_expect(.wb_rf_run(state), c('PYBENCH_CAPABILITY_MISMATCH',
      'PYBENCH_PROCESS_FAILED'))
    options(scworkbench.test_relation_shadowed_pair = NULL)
    stopifnot(identical(sort(list.files(store, all.files = TRUE,
        no.. = TRUE)), before),
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$
        fingerprint, fingerprint),
      identical(.wb_rf_durable_state(state$bundle), durable),
      nrow(wb_art_list(state$bundle)) == 0L)
  }
  .wb_rf_expect(.wb_rf_run(state, keys = rev(c('lineage|z',
    'lineage:a'))), c('PYBENCH_CAPABILITY_MISMATCH',
      'PYBENCH_PROCESS_FAILED'))
  for (event in c('before_publication', 'published',
      'before_reopened')) {
    options(scworkbench.operation_pack_v2_test_hook = local({
      selected <- event
      function(event, ...) if (identical(event, selected))
        stop('relation publication fault')
    }))
    .wb_rf_expect(.wb_rf_run(state), if (identical(event,
      'before_reopened')) 'PYBENCH_REOPEN_VALIDATION_FAILED' else
        'PYBENCH_PUBLICATION_FAILED')
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(identical(sort(list.files(store, all.files = TRUE,
      no.. = TRUE)), before),
      identical(.wb_manifest_registry_snapshot(state$bundle$con)$
        fingerprint, fingerprint),
      identical(.wb_rf_durable_state(state$bundle), durable),
      nrow(wb_art_list(state$bundle)) == 0L)
  }
  stopifnot(identical(sort(list.files(store, all.files = TRUE,
      no.. = TRUE)), before),
    identical(.wb_manifest_registry_snapshot(state$bundle$con)$
      fingerprint, fingerprint),
    identical(.wb_rf_durable_state(state$bundle), durable),
    nrow(wb_art_list(state$bundle)) == 0L)
  TRUE
}

test_operation_pack_v3_relation_family_layout_and_delayed_axis_contract <-
    function() {
  identity <- function(scheme) list(scheme = scheme,
    sha256 = paste(rep('a', 64L), collapse = ''))
  source <- list(ordered_cells = list('c|1', 'c:2'),
    source_axis_identity = identity('source'))
  limits <- list(maximum_axis_cells = 1000000L,
    maximum_keys = 1024L, maximum_rows = 1000000L,
    maximum_id_bytes = 1024L, maximum_control_bytes = 67108864L,
    maximum_chunk_pairs = 8192L)
  grant <- list(grant_identity = identity('grant'), limits = limits)
  fields <- c(weight = TRUE, value = FALSE, distance = FALSE)
  pairs <- list(list(key = 'a|b', cell_id = 'c|1'),
    list(key = 'a', cell_id = 'c:2'),
    list(key = 'a|b', cell_id = 'c:2'))
  first <- .wb_operation_pack_v3_rf_layout(grant, source, 'relation',
    c('a|b', 'a'), list(pairs[1:2], pairs[3]), fields)
  second <- .wb_operation_pack_v3_rf_layout(grant, source, 'relation',
    c('a|b', 'a'), list(pairs), fields)
  stopifnot(identical(first$seal$ordered_pair_axis_identity,
    second$seal$ordered_pair_axis_identity),
    identical(first$seal$ordered_key_axis_identity,
      second$seal$ordered_key_axis_identity))
  swapped <- .wb_operation_pack_v3_rf_layout(grant, source, 'relation',
    c('a|b', 'a'), list(pairs[c(1, 3, 2)]), fields)
  stopifnot(!identical(first$seal$ordered_pair_axis_identity,
    swapped$seal$ordered_pair_axis_identity))
  optional <- .wb_operation_pack_v3_rf_layout(grant, source,
    'relation', c('a|b', 'a'), list(pairs),
    c(weight = FALSE, value = TRUE, distance = TRUE))
  relation <- wb_prim_relation_family(
    vapply(pairs, `[[`, character(1), 'key'),
    vapply(pairs, `[[`, character(1), 'cell_id'),
    value = c(0.1, 0.2, 0.3), distance = c(1, 2, 3))
  stopifnot(isTRUE(.wb_operation_pack_v3_rf_assert_value(relation,
    optional)))
  extra <- relation; extra$weight <- c(1, 2, 3)
  .wb_rf_expect(.wb_operation_pack_v3_rf_assert_value(extra,
    optional), 'PYBENCH_OUTPUT_INVALID')
  nonfinite <- relation; nonfinite$distance[[1L]] <- Inf
  .wb_rf_expect(.wb_operation_pack_v3_rf_assert_value(nonfinite,
    optional), 'PYBENCH_OUTPUT_INVALID')
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, source,
    'relation', c('a|b', 'a'), list(pairs[1:2], pairs[1]), fields),
    'PYBENCH_OUTPUT_INVALID')
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, source,
    'relation', c('a|b', 'a'), list(c(pairs[1:2], list(
      list(key = 'a|b', cell_id = 'foreign')))), fields),
    'PYBENCH_OUTPUT_INVALID')
  for (shadowed in list(
      list(key = 'a|b', cell_id = 'c|1', cell_id = 'foreign'),
      list(key = 'a|b', cell_id = 'c|1', key = 'unknown'))) {
    .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, source,
      'relation', c('a|b', 'a'), list(c(list(shadowed), pairs[2:3])),
      fields), 'PYBENCH_CAPABILITY_MISMATCH')
    .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, source,
      'relation', c('a|b', 'a'), list(pairs[1:2], list(shadowed)),
      fields), 'PYBENCH_CAPABILITY_MISMATCH')
  }
  narrow <- grant; narrow$limits$maximum_id_bytes <- 2L
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(narrow, source,
    'relation', c('éé', 'a'), list(pairs), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  long_key <- paste(rep('é', 512L), collapse = '')
  exact <- .wb_operation_pack_v3_rf_layout(grant, source, 'relation',
    long_key, list(list(list(key = long_key, cell_id = 'c|1'))),
    fields)
  stopifnot(identical(as.integer(exact$seal$row_count), 1L))
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, source,
    'relation', paste0(long_key, 'é'), list(list(list(
      key = paste0(long_key, 'é'), cell_id = 'c|1'))), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  escaped <- list(ordered_cells = list('c\n'))
  escaped_pairs <- list(list(key = 'k\t', cell_id = 'c\n'))
  escaped_budget <- .wb_operation_pack_v3_rf_bytes('c\n') +
    .wb_operation_pack_v3_rf_bytes('k\t') +
    .wb_operation_pack_v3_rf_bytes('k\t') +
    .wb_operation_pack_v3_rf_bytes('c\n')
  narrow <- grant; narrow$limits$maximum_control_bytes <-
    as.integer(escaped_budget)
  stopifnot(.wb_operation_pack_v3_rf_layout(narrow, escaped,
    'relation', 'k\t', list(escaped_pairs), fields)$seal$row_count == 1L)
  narrow$limits$maximum_control_bytes <- as.integer(escaped_budget - 1)
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(narrow, escaped,
    'relation', 'k\t', list(escaped_pairs), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  narrow <- grant; narrow$limits$maximum_control_bytes <- 19L
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(narrow, source,
    'relation', c('a|b', 'a'), list(pairs), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  narrow <- grant; narrow$limits$maximum_chunk_pairs <- 2L
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(narrow, source,
    'relation', c('a|b', 'a'), list(pairs), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  many_cells <- sprintf('c%04d', seq_len(8193L))
  many_source <- list(ordered_cells = as.list(many_cells))
  many_pairs <- lapply(many_cells, function(cell_id)
    list(key = 'k', cell_id = cell_id))
  stopifnot(.wb_operation_pack_v3_rf_layout(grant, many_source,
    'relation', 'k', list(many_pairs[seq_len(8192L)]),
    fields)$seal$row_count == 8192L)
  .wb_rf_expect(.wb_operation_pack_v3_rf_layout(grant, many_source,
    'relation', 'k', list(many_pairs), fields),
    'PYBENCH_CAPABILITY_MISMATCH')
  g2_id <- identity('g2'); parent_id <- identity('parent')
  delayed <- grant
  delayed$source_selector <- list(source = 'g2_derived_fitted_axis_v1',
    model_output = 'model', g2_grant_identity = g2_id,
    parent_snapshot_identity = parent_id)
  request <- list(derived_fitted_axis_grants = list(list(
    grant_identity = g2_id,
    parent_snapshot = list(parent_snapshot_identity = parent_id))))
  .wb_rf_expect(.wb_operation_pack_v3_rf_axis(delayed, request),
    'PYBENCH_CAPABILITY_MISMATCH')
  cells <- c('c|1', 'c:2')
  seal <- list(provisional_grant_identity = g2_id,
    fitted_cell_ids = as.list(cells),
    fitted_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      'scworkbench.cell_order.v1', as.list(cells)),
    seal_identity = identity('seal'))
  projected <- .wb_operation_pack_v3_rf_axis(delayed, request,
    derived_state = list(seal = seal))
  stopifnot(identical(unlist(projected$ordered_cells,
    use.names = FALSE), cells))
  delayed$limits$maximum_id_bytes <- 2L
  .wb_rf_expect(.wb_operation_pack_v3_rf_axis(delayed, request,
    derived_state = list(seal = seal)),
    'PYBENCH_CAPABILITY_MISMATCH')
  TRUE
}

test_operation_pack_v3_relation_family_g2_lifecycle_contract <- function() {
  fixture <- .wb_rf_install(); state <- .wb_rf_bundle()
  on.exit({
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_rf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  fitted <- state$cells[c(1L, 2L, 4L)]
  run <- wb_session_run_op(wb_session_new(), state$bundle,
    'scwbv3phase5::fit_derived_axis_relation', inputs = list(
      source = 'pca', dims = c(1L, 3L), fitted_cells = fitted,
      cell_set = 'all', min_cells = 1L))
  record <- .wb_rf_records(run)
  grant <- record$request$sealed_relation_family_grants[[1L]]
  observation <- record$receipt$sealed_relation_family_observations[[1L]]
  stopifnot(identical(grant$source_selector$source,
      'g2_derived_fitted_axis_v1'),
    is.null(grant$known_source_axis),
    identical(unlist(observation$seal$source_axis$ordered_cells,
      use.names = FALSE), fitted),
    identical(as.integer(observation$observed_row_count), 3L),
    isTRUE(.wb_operation_pack_v2_record_validate(record$root,
      load_payloads = TRUE)$ok))
  promoted <- wb_session_promote_current(state$bundle, run$session,
    outputs = c('embedding', 'model', 'relation', 'weights'),
    created_by = 'relation-g2-contract')
  try(wb_session_discard(run$session), silent = TRUE)
  stopifnot(identical(sort(promoted$promoted$output,
      method = 'radix'), c('embedding', 'model', 'relation', 'weights')),
    all(promoted$promoted$status == 'ok'))
  relation_id <- promoted$promoted$artifact_id[match('relation',
    promoted$promoted$output)]
  value <- wb_art_load(state$bundle, relation_id,
    expected_kind = 'relation_family')
  stopifnot(identical(value$cell_id, fitted[c(2L, 1L, 1L)]),
    identical(value$key, c('branch|z', 'branch:a', 'branch|z')),
    identical(value$weight, c(0.25, 0.5, 0.75)))
  model_id <- promoted$promoted$artifact_id[match('model',
    promoted$promoted$output)]
  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle); state$bundle <- NULL
  state$bundle <- wb_open_bundle(state$root, read_only = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(state$root,
      level = 'recipient')$ok),
    identical(wb_art_load(state$bundle, relation_id,
      expected_kind = 'relation_family')$cell_id, value$cell_id),
    identical(wb_art_load(state$bundle, model_id,
      expected_kind = 'model_ref')$model_type, 'derived_axis_model'))
  relocated_root <- tempfile('scwb-rf-g2-relocated-')
  fs::dir_copy(state$root, relocated_root)
  on.exit(unlink(relocated_root, recursive = TRUE, force = TRUE),
    add = TRUE)
  relocated <- wb_open_bundle(relocated_root, read_only = TRUE)
  on.exit(wb_close_bundle(relocated), add = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(relocated_root,
      level = 'recipient')$ok),
    identical(wb_art_load(relocated, relation_id,
      expected_kind = 'relation_family')$weight, value$weight))
  TRUE
}

test_operation_pack_v3_relation_family_promoted_sql_fault_contract <-
    function() {
  fixture <- .wb_rf_install(); state <- .wb_rf_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_rf_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  run <- .wb_rf_run(state)
  before <- .wb_rf_durable_state(state$bundle)
  options(scworkbench.operation_pack_v2_test_hook = function(event,
      artifact_id = NULL, ...) {
    if (identical(event, 'relation_family_promoted'))
      DBI::dbExecute(state$bundle$con,
        'UPDATE artifact_relation_rows SET weight = weight + 1 WHERE artifact_id = ?',
        params = list(artifact_id))
  })
  error <- tryCatch(wb_session_promote_current(state$bundle,
    run$session, outputs = 'relation', created_by = 'relation-fault'),
    error = identity)
  try(wb_session_discard(run$session), silent = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(inherits(error, 'error'),
    nrow(wb_art_list(state$bundle)) == 0L,
    identical(.wb_rf_durable_state(state$bundle), before),
    nrow(DBI::dbGetQuery(state$bundle$con,
      'SELECT artifact_id FROM artifact_relation_rows')) == 0L)
  TRUE
}
