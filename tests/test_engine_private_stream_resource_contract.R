# Additional tiny adversarial/resource contracts. No external Python dispatch or
# performance claim; actual installed candidate qualification remains required.
.engine_private_support <- function() {
  env <- environment(.engine_private_support)
  if (!exists('.engine_broker_fixture', env, inherits = FALSE))
    sys.source('tests/test_engine_broker_streaming_contract.R', env)
  invisible(env)
}

.engine_private_get <- function(name) {
  env <- environment(.engine_private_get)
  value <- get0(name, env, inherits = TRUE)
  if (is.null(value)) value <- get(name, asNamespace('scworkbench'))
  value
}

.engine_private_context <- function() {
  .engine_private_support()
  ctx <- .engine_broker_context()
  open <- .engine_private_get('.wb_operation_pack_v3_private_stream_open')
  environment(open) <- ctx
  info <- .engine_private_get('.wb_operation_pack_v3_private_source_info')
  projection <- .engine_private_get('.wb_operation_pack_v3_private_projection_assert')
  ctx$info_checks <- 0L; ctx$projection_checks <- 0L
  ctx$.wb_operation_pack_v3_private_source_info <- function(...) {
    ctx$info_checks <- ctx$info_checks + 1L; info(...)
  }
  ctx$.wb_operation_pack_v3_private_projection_assert <- function(...) {
    ctx$projection_checks <- ctx$projection_checks + 1L; projection(...)
  }
  ctx$.wb_operation_pack_v3_private_stream_open <- function(...) {
    answer <- open(...); ctx$spills <- c(ctx$spills, answer$spill_root); answer
  }
  ctx
}

.engine_private_budget <- function(fixture, spill = TRUE) {
  budget <- .engine_private_get('.wb_operation_pack_v3_broker_projection_budget')(fixture$staged$bundle)
  if (spill) budget$limit <- 0
  budget
}

.engine_private_reader <- function(ctx, fixture, bound, budget) {
  ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes, budget)
}

.engine_private_roots <- function() sort(list.files(tempdir(),
  '^scwb_broker_projection_', full.names = TRUE))

test_engine_private_active_policy_intersection_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  con <- fixture$staged$bundle$con
  before <- con@ref$wb_graph_policy
  on.exit(con@ref$wb_graph_policy <- before, add = TRUE)
  declared <- scworkbench:::.wb_graph_budgets()
  active <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "33554432",
    token_bytes = "134217728"))
  con@ref$wb_graph_policy <- active
  budget <- .engine_private_get('.wb_operation_pack_v3_broker_projection_budget')(
    fixture$staged$bundle, declared)
  stopifnot(identical(budget$policy$memory_bytes, active$memory_bytes),
    identical(budget$policy$token_bytes, active$token_bytes),
    budget$memory < as.numeric(active$memory_bytes),
    identical(con@ref$wb_graph_policy, active))
  implicit <- .engine_private_get('.wb_operation_pack_v3_broker_projection_budget')(fixture$staged$bundle)
  stopifnot(identical(implicit$memory, budget$memory),
    identical(implicit$policy, budget$policy))
  TRUE
}

test_engine_private_forced_spill_no_readmm_constant_auth_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  fixture$features[1:2] <- c('feature\nline', 'feature\rreturn')
  fixture$cells[1:2] <- c('cell\nline', 'cell\rreturn')
  dimnames(fixture$values) <- list(fixture$features, fixture$cells)
  fixture$values[,] <- 0
  fixture$values[1L, 1:8] <- c(-0, 0, -1.25, .125, 1e-15,
    1.23456789012345, -123456789012345, pi)
  # Preserve the existing 15-significant-digit Matrix Market representation,
  # not an invented full-precision guarantee for pi after decimal transport.
  expected <- matrix(as.numeric(trimws(formatC(as.numeric(fixture$values),
    digits = 15L, format = 'g', flag = ''))), nrow(fixture$values),
    dimnames = dimnames(fixture$values))
  trace('readMM', where = asNamespace('Matrix'), print = FALSE,
    tracer = quote(stop('Forbidden whole-source Matrix::readMM in forced-spill path')))
  on.exit(untrace('readMM', where = asNamespace('Matrix')), add = TRUE)
  for (parts in c(8L, 32L)) {
    bound <- .engine_broker_grant(fixture, private = TRUE,
      name = paste0('forced_', parts), chunk_size = 64L / parts)
    ctx <- .engine_private_context(); budget <- .engine_private_budget(fixture)
    reader <- .engine_private_reader(ctx, fixture, bound, budget)
    tryCatch({
      stopifnot(reader$mode == 'spilled_projection', ctx$info_checks == 1L,
        ctx$projection_checks == 1L)
      for (ids in wb_partition_axis(fixture$cells, 64L / parts)) {
        actual <- as.matrix(reader$read(fixture$features, ids))
        stopifnot(identical(unname(actual), unname(expected[, ids, drop = FALSE])))
        # Omitted physical BPCells names must not change authenticated axes.
        stopifnot(identical(.engine_private_get('.wb_operation_pack_v3_matrix_slice_content')(
          actual, fixture$features, ids),
          .engine_private_get('.wb_operation_pack_v3_matrix_slice_content')(
            expected[, ids, drop = FALSE], fixture$features, ids)))
      }
      stopifnot(ctx$info_checks == 1L, ctx$projection_checks == 1L)
    }, finally = reader$close())
    stopifnot(budget$used == 0, budget$disk == 0, !dir.exists(reader$spill_root))
  }
  # Nonempty axes with no coordinates are a supported zero-NNZ source.
  fixture$values[,] <- 0
  bound <- .engine_broker_grant(fixture, private = TRUE, name = 'zero_nnz')
  ctx <- .engine_private_context(); budget <- .engine_private_budget(fixture)
  reader <- .engine_private_reader(ctx, fixture, bound, budget)
  tryCatch(stopifnot(all(as.matrix(reader$read(fixture$features, fixture$cells)) == 0)),
    finally = reader$close())
  stopifnot(budget$used == 0, budget$disk == 0)
  # Empty delivery remains rejected by the existing broker axis contract; do
  # not invent an empty grant or pass unsafe zero-dimension files to BPCells.
  before <- .engine_private_roots()
  for (axis in c('feature', 'cell')) {
    error <- tryCatch(.engine_private_get('.wb_operation_pack_v3_broker_validate_axis')(
      character(), if (axis == 'feature') fixture$features else fixture$cells, axis), error = identity)
    stopifnot(inherits(error, 'error'), grepl('empty', conditionMessage(error)),
      identical(before, .engine_private_roots()))
  }
  TRUE
}

test_engine_private_header_preadmission_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  # Only header text is modified. Invalid coordinates are never sent to native
  # code. The byte seal is recomputed solely to reach the header admission gate.
  state <- new.env(parent = emptyenv()); state$imports <- 0L
  options(scworkbench.private_header_probe = state)
  on.exit(options(scworkbench.private_header_probe = NULL), add = TRUE)
  trace('import_matrix_market', where = asNamespace('BPCells'), print = FALSE,
    tracer = quote({getOption('scworkbench.private_header_probe')$imports <-
      getOption('scworkbench.private_header_probe')$imports + 1L
      stop('Native importer must not see inadmissible headers')}))
  on.exit(untrace('import_matrix_market', where = asNamespace('BPCells')), add = TRUE)
  before <- .engine_private_roots()
  for (header in c('16 64 2147483648', '16 64 1025', '2147483648 64 0', '16 64 -1',
      '16 64 1.5', '16 64 9007199254740993', '16 63 0')) {
    bound <- .engine_broker_grant(fixture, private = TRUE,
      name = paste0('header_', length(list.files(fixture$stage))))
    path <- file.path(fixture$stage, 'typed_slice_sources', bound$grant$name, 'matrix.mtx')
    writeLines(c('%%MatrixMarket matrix coordinate real general', header), path, useBytes = TRUE)
    relative <- sub('^private_projection:', 'typed_slice_sources/',
      paste0(bound$grant$source_reference$input_reference, '/matrix.mtx'))
    bound$grant$source_reference$private_source_payload_identity <-
      .engine_private_get('.wb_operation_pack_v2_identity_scoped')(
        'scworkbench.operation_pack.payload_manifest.v2', 'registry read payload manifest',
        list(path = relative, size = as.numeric(file.info(path)$size),
          sha256 = .engine_private_get('.wb_operation_pack_v2_file_sha256')(path)))
    ctx <- .engine_private_context(); budget <- .engine_private_budget(fixture)
    error <- tryCatch(.engine_private_reader(ctx, fixture, bound, budget), error = identity)
    cat('HEADER_PREADMISSION ', header, ' imports=', state$imports, ' error=',
      if (inherits(error, 'error'))conditionMessage(error) else 'NO_ERROR', '\n', sep = '')
    stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_INPUT_IDENTITY_MISMATCH'),
      state$imports == 0L, budget$used == 0, budget$disk == 0,
      identical(before, .engine_private_roots()))
  }
  TRUE
}

test_engine_private_tamper_and_aggregate_credit_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture, private = TRUE, name = 'tamper_source')
  path <- file.path(fixture$stage, 'typed_slice_sources', 'tamper_source', 'matrix.mtx')
  axis <- file.path(fixture$stage, bound$grant$features_axis$relative_path)
  original <- readBin(path, 'raw', n = file.info(path)$size)
  axes <- readBin(axis, 'raw', n = file.info(axis)$size)
  before <- .engine_private_roots()
  # Checksum rejects before any reader is exposed.
  con <- file(path, 'ab'); writeBin(charToRaw('changed'), con); close(con)
  budget <- .engine_private_budget(fixture); ctx <- .engine_private_context()
  error <- tryCatch(.engine_private_reader(ctx, fixture, bound, budget), error = identity)
  stopifnot(inherits(error, 'error'), budget$used == 0, budget$disk == 0,
    identical(before, .engine_private_roots()))
  writeBin(original, path)
  # A live spill must retire and refund all credit on axis/payload mutation.
  for (target in c('axis', 'payload')) {
    ctx <- .engine_private_context(); budget <- .engine_private_budget(fixture)
    reader <- .engine_private_reader(ctx, fixture, bound, budget)
    tamper <- if (target == 'axis') axis else path
    con <- file(tamper, 'ab'); writeBin(charToRaw('changed'), con); close(con)
    error <- tryCatch(reader$read(fixture$features, fixture$cells[1:2]), error = identity)
    stopifnot(inherits(error, 'error'), !dir.exists(reader$spill_root),
      budget$used == 0, budget$disk == 0)
    writeBin(if (target == 'axis') axes else original, tamper)
  }
  # Distinct grants share one retained cache/disk account; closing one cannot
  # refund another's still-live allocation.
  bounds <- lapply(seq_len(3L), function(i).engine_broker_grant(fixture,
    private = TRUE, name = paste0('aggregate_', i)))
  budget <- .engine_private_budget(fixture, FALSE)
  budget$limit <- 400000
  ctx <- .engine_private_context(); readers <- list()
  on.exit(for (reader in readers) reader$close(), add = TRUE)
  readers[[1L]] <- .engine_private_reader(ctx, fixture, bounds[[1L]], budget)
  stopifnot(readers[[1L]]$mode == 'cached_projection')
  cached <- budget$used; budget$limit <- cached
  for (i in 2:3) readers[[i]] <- .engine_private_reader(ctx, fixture, bounds[[i]], budget)
  stopifnot(all(vapply(readers[2:3], function(x)x$mode == 'spilled_projection', logical(1))),
    budget$used > cached, budget$disk > 0)
  charged <- budget$used; disk <- budget$disk
  readers[[2L]]$close(); stopifnot(budget$used < charged, budget$used > cached,
    budget$disk < disk, budget$disk > 0)
  stopifnot(identical(unname(as.matrix(readers[[3L]]$read(fixture$features, fixture$cells[1:8]))),
    unname(fixture$values[, 1:8, drop = FALSE])))
  readers[[1L]]$close(); stopifnot(budget$used > 0, budget$disk > 0)
  readers[[3L]]$close(); stopifnot(budget$used == 0, budget$disk == 0,
    identical(before, .engine_private_roots()))
  TRUE
}

test_engine_private_graph_reservation_restore_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bundle <- fixture$staged$bundle; bundle$staging_source_bundle <- fixture$bundle
  connections <- list(bundle$con, fixture$bundle$con)
  observe <- function()lapply(connections, function(con)list(
    cache = DBI::dbGetQuery(con, 'PRAGMA cache_size')[[1L]],
    temp = DBI::dbGetQuery(con, 'PRAGMA temp_store')[[1L]],
    policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib,
    copy = con@ref$wb_graph_session_copy_bytes))
  policy <- .engine_private_get('.wb_graph_budgets')()
  bundle$con@ref$wb_graph_session_copy_bytes <- 131072
  before <- observe(); roots <- .engine_private_roots()
  changes <- lapply(connections, function(con)DBI::dbGetQuery(con, 'SELECT total_changes() n'))
  budget <- .engine_private_budget(fixture); budget$used <- 1048576; budget$disk <- 2097152
  reserve <- .engine_private_get('.wb_operation_pack_v3_broker_graph_reservation')
  for (fail in c(FALSE, TRUE)) {
    error <- tryCatch({
      restore <- reserve(bundle, budget, policy)
      tryCatch({
        for (con in connections)stopifnot(
          identical(con@ref$wb_graph_policy$memory_bytes, as.character(as.numeric(policy$memory_bytes) - budget$used)),
          identical(con@ref$wb_graph_policy$token_bytes, as.character(as.numeric(policy$token_bytes) - budget$disk)))
        stopifnot(.engine_private_get('.wb_graph_session_copy_reservation')(bundle$con@ref$wb_graph_policy) >= 131072)
        if (fail)stop('injected inside lower graph policy')
      }, finally = restore())
    }, error = identity)
    stopifnot(identical(observe(), before), identical(roots, .engine_private_roots()),
      identical(changes, lapply(connections, function(con)DBI::dbGetQuery(con, 'SELECT total_changes() n'))),
      if (fail)inherits(error, 'error') else !inherits(error, 'error'))
  }
  budget$used <- as.numeric(policy$memory_bytes)
  error <- tryCatch(reserve(bundle, budget, policy), error = identity)
  stopifnot(inherits(error, 'error'), identical(observe(), before), identical(roots, .engine_private_roots()))
  budget$used <- 0; budget$disk <- as.numeric(policy$token_bytes)
  error <- tryCatch(reserve(bundle, budget, policy), error = identity)
  stopifnot(inherits(error, 'error'), identical(observe(), before), identical(roots, .engine_private_roots()))
  TRUE
}

.engine_private_main_copy_case <- function(fixture, raw_copy, staged = TRUE) {
  transport <- tempfile('copy_transport_', tmpdir = fixture$root); dir.create(transport)
  id <- list(scheme = 'fixture', sha256 = paste(rep('a', 64L), collapse = ''))
  request <- list(pack_abi_version = '4', request_identity = id,
    typed_slice_grants = list(), graph_read_grants = list(list(input_name = 'graph')))
  jsonlite::write_json(request, file.path(transport, 'request.json'), auto_unbox = TRUE, null = 'null')
  dir.create(file.path(transport, 'broker')); file.create(file.path(transport, 'broker', 'stop.json'))
  names <- c('PYBENCH_OPERATION_PACK_BROKER_TOKEN', 'PYBENCH_OPERATION_PACK_BROKER_TIMEOUT',
    'PYBENCH_OPERATION_PACK_BROKER_SESSION_COPY_BYTES')
  previous <- Sys.getenv(names, unset = NA_character_)
  on.exit(for (name in names) if (is.na(previous[[name]])) Sys.unsetenv(name) else
    do.call(Sys.setenv, setNames(list(previous[[name]]), name)), add = TRUE)
  Sys.setenv(PYBENCH_OPERATION_PACK_BROKER_TOKEN = paste(rep('f', 64L), collapse = ''),
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT = '1')
  if (is.na(raw_copy)) Sys.unsetenv('PYBENCH_OPERATION_PACK_BROKER_SESSION_COPY_BYTES') else
    Sys.setenv(PYBENCH_OPERATION_PACK_BROKER_SESSION_COPY_BYTES = raw_copy)
  ctx <- new.env(parent = environment(.engine_private_get('.wb_operation_pack_v3_broker_main')))
  ctx$copy <- NULL; ctx$policy <- NULL; ctx$con <- NULL
  original_budget <- .engine_private_get('.wb_operation_pack_v3_broker_projection_budget')
  ctx$.wb_operation_pack_v3_broker_projection_budget <- function(bundle, policy = NULL) {
    ctx$copy <- bundle$con@ref$wb_graph_session_copy_bytes
    ctx$policy <- policy; ctx$con <- bundle$con
    original_budget(bundle, policy)
  }
  # Empty cursor is a main-loop/resource routing stand-in only. The test uses
  # the actual graph cache/temp/session-copy helpers, not forged graph authority.
  ctx$.wb_operation_pack_v4_graph_cursor <- function(...)list(usage = function()list())
  main <- .engine_private_get('.wb_operation_pack_v3_broker_main'); environment(main) <- ctx
  source <- fixture$bundle$dir
  visible <- if (staged) fixture$staged$bundle$dir else source
  result <- tryCatch(main(transport, visible, source), error = identity)
  if (!is.null(ctx$con)) stopifnot(!DBI::dbIsValid(ctx$con))
  list(result = result, copy = ctx$copy, policy = ctx$policy, stage = transport)
}

test_engine_private_session_copy_environment_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  before <- .engine_private_roots()
  for (staged in c(FALSE, TRUE)) {
    # Missing transport falls back to actual owned-copy measurement for a
    # stage, and zero reservation when there is no source copy.
    result <- .engine_private_main_copy_case(fixture, NA_character_, staged)
    stopifnot(!inherits(result$result, 'error'),
      if (staged)result$copy > 0 else identical(result$copy, 0),
      file.exists(file.path(result$stage, 'broker-observations.json')))
    for (raw in c('-1', '1.5', '9007199254740992', '99999999999999999999999999999999999999')) {
      result <- .engine_private_main_copy_case(fixture, raw, staged)
      stopifnot(inherits(result$result, 'error'),
        grepl('Invalid broker session-copy', conditionMessage(result$result)),
        !file.exists(file.path(result$stage, 'broker-observations.json')),
        identical(before, .engine_private_roots()))
    }
    result <- .engine_private_main_copy_case(fixture, '0', staged)
    if (staged) stopifnot(inherits(result$result, 'error'),
      grepl('below its stage database', conditionMessage(result$result))) else
      stopifnot(!inherits(result$result, 'error'), identical(result$copy, 0))
  }
  policy <- .engine_private_get('.wb_graph_budgets')()
  copy <- .engine_private_get('.wb_session_graph_copy_bytes')(fixture$staged$bundle, policy)
  result <- .engine_private_main_copy_case(fixture, format(copy, scientific = FALSE), TRUE)
  stopifnot(!inherits(result$result, 'error'), identical(result$copy, copy))
  # A stage database which grew beyond a previously transported reservation
  # cannot be admitted under the stale resource count.
  DBI::dbExecute(fixture$staged$bundle$con, 'CREATE TABLE engine_private_copy_growth(value BLOB);')
  DBI::dbExecute(fixture$staged$bundle$con, 'INSERT INTO engine_private_copy_growth VALUES(zeroblob(262144));')
  result <- .engine_private_main_copy_case(fixture, format(copy, scientific = FALSE), TRUE)
  stopifnot(inherits(result$result, 'error'),
    grepl('below its stage database', conditionMessage(result$result)),
    !file.exists(file.path(result$stage, 'broker-observations.json')),
    identical(before, .engine_private_roots()))
  TRUE
}

test_engine_private_axis_preadmission_contract <- function() {
  .engine_private_support(); fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture, private = TRUE, name = 'axis_admission')
  descriptor <- bound$grant$features_axis
  decode <- .engine_private_get('.wb_operation_pack_v3_broker_axis_ids')
  admit <- .engine_private_get('.wb_operation_pack_v3_broker_axis_admission')
  path <- file.path(fixture$stage, descriptor$relative_path)
  original <- readBin(path, 'raw', n = file.info(path)$size)
  state <- new.env(parent = emptyenv()); state$paths <- path
  state$reads <- 0L; state$forbid <- FALSE
  old_probe <- getOption('scworkbench.private_axis_probe')
  options(scworkbench.private_axis_probe = state)
  on.exit(options(scworkbench.private_axis_probe = old_probe), add = TRUE)
  trace('read_json', where = asNamespace('jsonlite'), print = FALSE,
    tracer = quote({
      probe <- getOption('scworkbench.private_axis_probe')
      if (!is.null(probe) && is.character(path) && length(path) == 1L && path %in% probe$paths) {
        probe$reads <- probe$reads + 1L
        if (probe$forbid) stop('Axis JSON decode occurred before resource admission')
      }
    }))
  on.exit(untrace('read_json', where = asNamespace('jsonlite')), add = TRUE)
  # Ordinary current manifest and its exact pre-admitted cap remain unchanged.
  cap <- admit(fixture$stage, descriptor)$estimate
  stopifnot(identical(decode(fixture$stage, descriptor), fixture$features),
    identical(decode(fixture$stage, descriptor, maximum_bytes = cap), fixture$features),
    state$reads == 2L)
  state$forbid <- TRUE; state$reads <- 0L
  huge <- descriptor; huge$count <- 2147483647
  error <- tryCatch(decode(fixture$stage, huge), error = identity)
  stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_CAPABILITY_MISMATCH'),
    state$reads == 0L)
  for (count in list(NULL, -1, 1.5, NA_real_, Inf, 'not_a_count', c(1, 2))) {
    bad <- descriptor; bad$count <- count
    error <- tryCatch(decode(fixture$stage, bad), error = identity)
    stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_CAPABILITY_MISMATCH'),
      state$reads == 0L)
  }
  # Growth between pre-estimate and read must reject at the new stat, even
  # though both versions are far below the ordinary global allowance.
  con <- file(path, 'ab'); writeBin(charToRaw(' '), con); close(con)
  error <- tryCatch(decode(fixture$stage, descriptor, maximum_bytes = cap), error = identity)
  stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_CAPABILITY_MISMATCH'),
    state$reads == 0L)
  writeBin(original, path)
  # A small metadata count inconsistency is admitted for decoding but then
  # fails the authenticated descriptor/count comparison, never returning IDs.
  mismatch <- descriptor; mismatch$count <- descriptor$count + 1L
  state$forbid <- FALSE
  error <- tryCatch(decode(fixture$stage, mismatch), error = identity)
  stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_CAPABILITY_MISMATCH'),
    state$reads == 1L)
  state$reads <- 0L; state$forbid <- TRUE
  second <- .engine_broker_grant(fixture, private = TRUE, name = 'axis_second')
  grants <- list(bound$grant, second$grant)
  # Only authenticated-descriptor metadata sizes are probed here. The tiny
  # files intentionally do not contain these large counts: no big JSON fixture
  # or allocation is needed to prove aggregate admission precedes all decoding.
  for (i in seq_along(grants)) {
    grants[[i]]$features_axis$count <- 200000L
    grants[[i]]$cells_axis$count <- 200000L
  }
  descriptors <- unlist(lapply(grants, function(g)list(g$features_axis, g$cells_axis)), recursive = FALSE)
  state$paths <- vapply(descriptors, function(d)file.path(fixture$stage, d$relative_path), '')
  policy <- .engine_private_get('.wb_graph_budgets')()
  budget <- .engine_private_get('.wb_operation_pack_v3_broker_projection_budget')(
    fixture$staged$bundle, policy)
  estimates <- vapply(descriptors, function(d)admit(fixture$stage, d)$estimate, 0)
  stopifnot(all(estimates < budget$memory), sum(estimates) > budget$memory)
  transport <- fixture$stage
  id <- list(scheme = 'fixture', sha256 = paste(rep('a', 64L), collapse = ''))
  request <- list(pack_abi_version = '4', request_identity = id, typed_slice_grants = grants,
    graph_read_grants = list(list(input_name = 'graph')))
  jsonlite::write_json(request, file.path(transport, 'request.json'), auto_unbox = TRUE, null = 'null')
  dir.create(file.path(transport, 'broker'), showWarnings = FALSE)
  file.create(file.path(transport, 'broker', 'stop.json'))
  names <- c('PYBENCH_OPERATION_PACK_BROKER_TOKEN', 'PYBENCH_OPERATION_PACK_BROKER_TIMEOUT',
    'PYBENCH_OPERATION_PACK_BROKER_SESSION_COPY_BYTES')
  previous <- Sys.getenv(names, unset = NA_character_)
  on.exit(for (name in names) if (is.na(previous[[name]])) Sys.unsetenv(name) else
    do.call(Sys.setenv, setNames(list(previous[[name]]), name)), add = TRUE)
  Sys.setenv(PYBENCH_OPERATION_PACK_BROKER_TOKEN = paste(rep('f', 64L), collapse = ''),
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT = '1')
  Sys.unsetenv('PYBENCH_OPERATION_PACK_BROKER_SESSION_COPY_BYTES')
  main <- .engine_private_get('.wb_operation_pack_v3_broker_main')
  ctx <- new.env(parent = environment(main)); environment(main) <- ctx
  ctx$readers <- 0L; ctx$cursors <- 0L
  ctx$.wb_operation_pack_v3_broker_reader <- function(...) {
    ctx$readers <- ctx$readers + 1L; stop('Reader construction before aggregate axis admission')
  }
  ctx$.wb_operation_pack_v4_graph_cursor <- function(...) {
    ctx$cursors <- ctx$cursors + 1L; stop('Cursor construction before aggregate axis admission')
  }
  error <- tryCatch(main(transport, fixture$staged$bundle$dir, fixture$bundle$dir), error = identity)
  stopifnot(inherits(error, 'error'), identical(error$code, 'PYBENCH_CAPABILITY_MISMATCH'),
    grepl('Combined typed axes', conditionMessage(error)), state$reads == 0L,
    ctx$readers == 0L, ctx$cursors == 0L,
    !file.exists(file.path(transport, 'broker-observations.json')))
  TRUE
}
