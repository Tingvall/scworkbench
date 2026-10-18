.engine_broker_get <- function(name) {
  value <- get0(name, environment(.engine_broker_get), inherits = TRUE)
  if (is.null(value)) value <- get(name, asNamespace("scworkbench"))
  value
}

.engine_broker_fixture <- function() {
  root <- tempfile("engine_broker_")
  b <- wb_init_bundle(file.path(root, "source.bundle"))
  cells <- paste0("cell_", c(2L, 10L, 1L, setdiff(seq_len(64L), c(1L, 2L, 10L))))
  features <- paste0("feature_", c(2L, 10L, 1L, setdiff(seq_len(16L), c(1L, 2L, 10L))))
  values <- matrix(as.double(seq_len(16L * 64L) %% 7L), 16L,
    dimnames = list(features, cells))
  values[, 3L] <- 0
  wb_define_cells(b, cells)
  wb_attach_matrix(b, "counts", values, layer = "counts", feature_type = "gene")
  staged <- scworkbench:::.wb_session_stage_bundle(b, wb_session_new())
  stage <- file.path(root, "transport")
  dir.create(stage)
  list(root = root, bundle = b, staged = staged, stage = stage,
    features = features, cells = cells, values = values)
}

.engine_broker_close <- function(fixture) {
  try(wb_session_discard(fixture$staged$session), silent = TRUE)
  try(wb_close_bundle(fixture$bundle), silent = TRUE)
  unlink(fixture$root, recursive = TRUE)
}

.engine_broker_grant <- function(fixture, matrix_id = "counts", private = FALSE,
                                 name = "chunks", chunk_size = 8L,
                                 chunk_axis = "cells") {
  b <- fixture$staged$bundle
  input <- structure(list(kind = "matrix", matrix_id = matrix_id,
    feature_id = fixture$features, cell_id = fixture$cells), class = "wb_primitive")
  if (private) input$values <- fixture$values
  identity <- if (private) scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
    input$values, input$feature_id, input$cell_id) else {
      observed <- scworkbench:::.wb_operation_pack_v3_matrix_consumed_identity(b, matrix_id)
      list(scheme = observed$content_identity_scheme, sha256 = observed$content_sha256)
    }
  descriptor <- list(descriptor_identity = list(scheme = "fixture",
    sha256 = paste(rep("a", 64L), collapse = "")), content_identity = identity)
  declaration <- list(name = name, input = "matrix", supported_axes = list("cells", "features"),
    chunk_axis = chunk_axis, chunk_size_parameter = "chunk_size",
    call_discipline = "ordered_partition_exactly_once",
    empty_selection_policy = "reject", selection = list(
      cells = list(policy = "effective_input_axis_v1"),
      features = list(policy = "effective_input_axis_v1")))
  state <- scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.scientific_state.v1",
    scworkbench:::.wb_manifest_registry_snapshot(b$con))
  grant <- scworkbench:::.wb_operation_pack_v3_typed_slice_grant(b, declaration,
    input, descriptor, list(chunk_size = chunk_size), fixture$cells, state, fixture$stage)
  list(grant = grant, axes = list(features = fixture$features, cells = fixture$cells))
}

.engine_broker_context <- function() {
  reader <- .engine_broker_get(".wb_operation_pack_v3_broker_reader")
  e <- new.env(parent = environment(reader))
  e$full <- 0L; e$private <- 0L; e$roots <- character(); e$spills <- character()
  original_assert <- .engine_broker_get(".wb_operation_pack_v3_typed_slice_grant_assert_current")
  original_private <- .engine_broker_get(".wb_operation_pack_v3_private_source_validate")
  environment(original_private) <- e
  private_open <- .engine_broker_get(".wb_operation_pack_v3_private_stream_open")
  environment(private_open) <- e
  e$.wb_operation_pack_v3_private_stream_open <- function(...) {
    answer <- private_open(...)
    e$spills <- c(e$spills, answer$spill_root)
    answer
  }
  original_plan <- .engine_broker_get(".wb_matrix_stream_reader")
  e$.wb_operation_pack_v3_typed_slice_grant_assert_current <- function(...) {
    e$full <- e$full + 1L; original_assert(...)
  }
  e$.wb_operation_pack_v3_private_source_validate <- function(...) {
    e$private <- e$private + 1L; original_private(...)
  }
  e$.wb_matrix_stream_reader <- function(...) {
    plan <- original_plan(...); e$roots <- c(e$roots, plan$root); plan
  }
  environment(reader) <- e
  e$.wb_operation_pack_v3_broker_reader <- reader
  e
}

test_engine_broker_constant_scan_and_stage_source_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  stage <- fixture$staged$bundle
  wb_attach_matrix(stage, "stage_only", fixture$values + 7,
    layer = "counts", feature_type = "gene")
  for (matrix_id in c("counts", "stage_only")) {
    expected <- if (matrix_id == "counts") fixture$values else fixture$values + 7
    for (parts in c(8L, 32L)) {
      bound <- .engine_broker_grant(fixture, matrix_id, chunk_size = 64L / parts)
      ctx <- .engine_broker_context()
      reader <- ctx$.wb_operation_pack_v3_broker_reader(stage, fixture$stage,
        bound$grant, bound$axes)
      tryCatch({
        for (cells in wb_partition_axis(fixture$cells, 64L / parts)) {
          actual <- reader$read(fixture$features, cells)
          stopifnot(identical(actual, expected[, cells, drop = FALSE]),
            identical(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
              actual, fixture$features, cells),
              scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
                expected[, cells, drop = FALSE], fixture$features, cells)))
        }
        stopifnot(ctx$full == 1L)
      }, finally = reader$close())
      stopifnot(length(ctx$roots) == 1L, !any(dir.exists(ctx$roots)))
    }
  }
  TRUE
}

test_engine_broker_mutation_and_fresh_oneoff_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  stage <- fixture$staged$bundle
  for (kind in c("registry", "added", "removed", "retargeted", "same_size")) {
    bound <- .engine_broker_grant(fixture)
    ctx <- .engine_broker_context()
    reader <- ctx$.wb_operation_pack_v3_broker_reader(stage, fixture$stage,
      bound$grant, bound$axes)
    actual <- reader$read(fixture$features, fixture$cells[1:8])
    stopifnot(identical(actual, fixture$values[, 1:8, drop = FALSE]))
    fragment <- wb_matrix_fragments(stage, "counts")$path[[1L]]
    directory <- file.path(stage$dir, fragment)
    if (kind == "registry") {
      old <- DBI::dbGetQuery(stage$con, "SELECT description FROM matrices WHERE matrix_id='counts';")$description
      DBI::dbExecute(stage$con, "UPDATE matrices SET description='changed' WHERE matrix_id='counts';")
      restore <- function() DBI::dbExecute(stage$con,
        "UPDATE matrices SET description=? WHERE matrix_id='counts';", params = list(old))
    } else if (kind == "added") {
      path <- file.path(directory, "unexpected_payload")
      writeBin(charToRaw("new file"), path)
      restore <- function() unlink(path)
    } else {
      candidates <- list.files(directory, full.names = TRUE)
      linked <- candidates[nzchar(Sys.readlink(candidates))]
      stopifnot(length(linked) > 0L)
      path <- linked[[1L]]; target <- Sys.readlink(path)
      unlink(path)
      if (kind == "retargeted") stopifnot(file.symlink(linked[[2L]], path))
      if (kind == "same_size") {
        bytes <- readBin(target, "raw", n = file.info(target)$size)
        stopifnot(length(bytes) > 0L)
        bytes[[1L]] <- as.raw(bitwXor(as.integer(bytes[[1L]]), 1L))
        writeBin(bytes, path)
      }
      restore <- function() { unlink(path); stopifnot(file.symlink(target, path)) }
    }
    rejection <- tryCatch(reader$read(fixture$features, fixture$cells[9:16]),
      error = identity)
    stopifnot(inherits(rejection, "error"), !any(dir.exists(ctx$roots)))
    # Persistent mutation must also fail the independent full publication gate.
    failure <- tryCatch(scworkbench:::.wb_operation_pack_v3_typed_slice_grant_assert_current(
      stage, bound$grant), error = identity)
    stopifnot(inherits(failure, "error"))
    restore()
    # A one-off call authenticates again, rather than inheriting the reader.
    oneoff <- .engine_broker_get(".wb_operation_pack_v3_broker_source")
    stopifnot(identical(oneoff(stage, fixture$stage, bound$grant,
      fixture$features, fixture$cells[1:8]), fixture$values[, 1:8, drop = FALSE]))
  }
  TRUE
}

test_engine_broker_unrelated_registry_boundary_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture)
  ctx <- .engine_broker_context()
  reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes)
  on.exit(reader$close(), add = TRUE)
  stopifnot(identical(reader$read(fixture$features, fixture$cells[1:8]),
    fixture$values[, 1:8, drop = FALSE]))
  # Scoped block guards deliberately do not rescan unrelated registry tables.
  # The independently executed full publication check remains authoritative.
  DBI::dbExecute(fixture$staged$bundle$con,
    "UPDATE cells SET dataset_id='unrelated_change' WHERE cell_id=?;",
    params = list(fixture$cells[[1L]]))
  stopifnot(identical(reader$read(fixture$features, fixture$cells[9:16]),
    fixture$values[, 9:16, drop = FALSE]), ctx$full == 1L)
  failure <- tryCatch(scworkbench:::.wb_operation_pack_v3_typed_slice_grant_assert_current(
    fixture$staged$bundle, bound$grant), error = identity)
  stopifnot(inherits(failure, "error"))
  TRUE
}

test_engine_broker_private_cache_budget_and_guard_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture, private = TRUE)
  ctx <- .engine_broker_context()
  budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")(
    fixture$staged$bundle)
  reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes, budget)
  stopifnot(reader$mode == "cached_projection", budget$used > 0)
  for (cells in wb_partition_axis(fixture$cells, 2L)) stopifnot(identical(
    unname(as.matrix(reader$read(fixture$features, cells))),
    unname(fixture$values[, cells, drop = FALSE])))
  stopifnot(ctx$private == 1L)
  reader$close()
  stopifnot(budget$used == 0)
  for (kind in c("matrix", "axis")) {
    reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
      fixture$stage, bound$grant, bound$axes, budget)
    path <- if (kind == "matrix") file.path(fixture$stage,
      "typed_slice_sources", "chunks", "matrix.mtx") else
        file.path(fixture$stage, bound$grant$features_axis$relative_path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    con <- file(path, "ab"); writeBin(charToRaw("changed"), con); close(con)
    failure <- tryCatch(reader$read(fixture$features, fixture$cells[1:2]),
      error = identity)
    stopifnot(inherits(failure, "error"), budget$used == 0)
    writeBin(bytes, path)
  }
  TRUE
}

test_engine_broker_timeout_reader_cleanup_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture)
  id <- list(scheme = "fixture", sha256 = paste(rep("a", 64L), collapse = ""))
  request <- list(pack_abi_version = "3", request_identity = id,
    typed_slice_grants = list(bound$grant))
  jsonlite::write_json(request, file.path(fixture$stage, "request.json"),
    auto_unbox = TRUE, null = "null")
  spool <- file.path(fixture$stage, "broker"); dir.create(spool)
  token <- paste(rep("f", 64L), collapse = "")
  control <- list(schema = "scworkbench.operation_pack.typed_slice_control_request.v1",
    request_identity = id, grant_identity = bound$grant$grant_identity,
    ordinal = 1L, features = as.list(fixture$features),
    cells = as.list(fixture$cells[1:8]), authorization_token = token)
  control$control_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
    control$schema, "control excluding control_identity", control)
  scworkbench:::.wb_operation_pack_v3_atomic_canonical_json(control,
    file.path(spool, "request.json"))
  old <- Sys.getenv(c("PYBENCH_OPERATION_PACK_BROKER_TOKEN",
    "PYBENCH_OPERATION_PACK_BROKER_TIMEOUT"), unset = NA_character_)
  on.exit({for (name in names(old)) if (is.na(old[[name]])) Sys.unsetenv(name) else
    do.call(Sys.setenv, setNames(list(old[[name]]), name))}, add = TRUE)
  Sys.setenv(PYBENCH_OPERATION_PACK_BROKER_TOKEN = token,
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT = "0.01")
  ctx <- .engine_broker_context()
  main <- .engine_broker_get(".wb_operation_pack_v3_broker_main")
  environment(main) <- ctx
  failure <- tryCatch(main(fixture$stage, fixture$staged$bundle$dir,
    fixture$bundle$dir), error = identity)
  stopifnot(inherits(failure, "error"),
    grepl("acknowledgement", conditionMessage(failure)),
    length(ctx$roots) == 1L, !any(dir.exists(ctx$roots)),
    file.exists(file.path(fixture$stage, "broker-error.json")),
    !file.exists(file.path(fixture$stage, "broker-observations.json")))
  TRUE
}

test_engine_broker_private_spill_identity_and_cleanup_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  fixture$values[1L, 1:8] <- c(-0, 0, -1.25, .125, 1e-307, 1e308,
    .Machine$integer.max, pi)
  for (axis in c("cells", "features")) {
    bound <- .engine_broker_grant(fixture, private = TRUE,
      name = paste0("projection_", axis), chunk_axis = axis, chunk_size = 8L)
    expected <- scworkbench:::.wb_operation_pack_v3_private_source_validate(
      fixture$stage, bound$grant)
    ctx <- .engine_broker_context()
    make_budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")
    budget <- make_budget(fixture$staged$bundle); budget$limit <- 0
    reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
      fixture$stage, bound$grant, bound$axes, budget)
    tryCatch({
      stopifnot(reader$mode == "spilled_projection", dir.exists(reader$spill_root))
      for (chunk in wb_partition_axis(bound$axes[[axis]], 8L)) {
        features <- if (axis == "features") chunk else fixture$features
        cells <- if (axis == "cells") chunk else fixture$cells
        actual <- as.matrix(reader$read(features, cells))
        reference <- expected[match(features, fixture$features),
          match(cells, fixture$cells), drop = FALSE]
        stopifnot(identical(unname(actual), unname(as.matrix(reference))))
        # Response serialization resets explicit dimnames. Compare complete
        # returned response records, not just a numerical tolerance.
        request <- list(request_identity = list(scheme = "fixture",
          sha256 = paste(rep("a", 64L), collapse = "")))
        old_spool <- tempfile("old_wire_", tmpdir = fixture$root)
        new_spool <- tempfile("new_wire_", tmpdir = fixture$root)
        dir.create(old_spool); dir.create(new_spool)
        publish <- .engine_broker_get(".wb_operation_pack_v3_broker_publish_response")
        old <- publish(old_spool, bound$grant, request, 1L, features, cells, reference)
        new <- publish(new_spool, bound$grant, request, 1L, features, cells, actual)
        files <- list.files(file.path(old_spool, "response"))
        stopifnot(identical(old, new), all(vapply(files, function(file) identical(
          readBin(file.path(old_spool, "response", file), "raw", n = 1e7),
          readBin(file.path(new_spool, "response", file), "raw", n = 1e7)), logical(1))))
        unlink(c(old_spool, new_spool), recursive = TRUE)
      }
      features <- rev(fixture$features[c(1L, 7L, 13L)])
      cells <- rev(fixture$cells[c(1L, 8L, 21L)])
      stopifnot(identical(unname(as.matrix(reader$read(features, cells))),
        unname(as.matrix(expected[match(features, fixture$features),
          match(cells, fixture$cells), drop = FALSE]))), ctx$private == 1L)
    }, finally = reader$close())
    stopifnot(!dir.exists(reader$spill_root), budget$disk == 0, budget$used == 0)
  }
  TRUE
}

test_engine_broker_private_spill_fault_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture, private = TRUE)
  make_budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")
  roots <- function() sort(list.files(tempdir(), "^scwb_broker_projection_", full.names = TRUE))
  before <- roots()
  for (available in c(0, NA_real_)) {
    ctx <- .engine_broker_context()
    ctx$.wb_operation_pack_v3_broker_free_bytes <- function(path) available
    budget <- make_budget(fixture$staged$bundle); budget$limit <- 0
    failure <- tryCatch(ctx$.wb_operation_pack_v3_broker_reader(
      fixture$staged$bundle, fixture$stage, bound$grant, bound$axes, budget), error = identity)
    stopifnot(inherits(failure, "error"), ctx$private == 1L,
      budget$disk == 0, budget$used == 0, identical(before, roots()))
  }
  ctx <- .engine_broker_context()
  old_hook <- getOption("scworkbench.operation_pack_v2_test_hook")
  on.exit(options(scworkbench.operation_pack_v2_test_hook = old_hook), add = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (event == "private_matrix_after_import") stop("injected disk-full write")
  })
  budget <- make_budget(fixture$staged$bundle); budget$limit <- 0
  failure <- tryCatch(ctx$.wb_operation_pack_v3_broker_reader(
    fixture$staged$bundle, fixture$stage, bound$grant, bound$axes, budget), error = identity)
  stopifnot(inherits(failure, "error"), budget$disk == 0,
    budget$used == 0, identical(before, roots()))
  options(scworkbench.operation_pack_v2_test_hook = old_hook)
  for (kind in c("tamper", "missing")) {
    ctx <- .engine_broker_context()
    budget <- make_budget(fixture$staged$bundle); budget$limit <- 0
    reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
      fixture$stage, bound$grant, bound$axes, budget)
    files <- list.files(reader$spill_root, recursive = TRUE, full.names = TRUE)
    stopifnot(length(files) > 0L)
    if (kind == "missing") unlink(files[[1L]]) else {
      con <- file(files[[1L]], "ab"); writeBin(charToRaw("tamper"), con); close(con)
    }
    failure <- tryCatch(reader$read(fixture$features, fixture$cells[1:8]), error = identity)
    stopifnot(inherits(failure, "error"), !dir.exists(reader$spill_root), budget$disk == 0)
  }
  TRUE
}

test_engine_broker_private_aggregate_admission_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  bound <- .engine_broker_grant(fixture, private = TRUE)
  ctx <- .engine_broker_context()
  make_budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")
  budget <- make_budget(fixture$staged$bundle)
  path <- file.path(fixture$stage, "typed_slice_sources", "chunks", "matrix.mtx")
  metadata <- 128 * (length(fixture$features) + length(fixture$cells)) +
    16 * sum(nchar(c(fixture$features, fixture$cells), type = "bytes")) + 65536
  retained <- metadata + 4194304
  exact <- 128 * sum(fixture$values != 0) + 4 * file.info(path)$size + metadata
  budget$limit <- exact
  first <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes, budget)
  on.exit(first$close(), add = TRUE)
  stopifnot(first$mode == "cached_projection", budget$used == exact)
  second <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes, budget)
  on.exit(second$close(), add = TRUE)
  stopifnot(second$mode == "spilled_projection", budget$used == exact + retained,
    is.null(get("matrix", envir = environment(second$read))),
    identical(unname(as.matrix(first$read(fixture$features, fixture$cells[1:8]))),
      unname(as.matrix(second$read(fixture$features, fixture$cells[1:8])))))
  first$close(); second$close()
  stopifnot(budget$used == 0, budget$disk == 0)
  budget$limit <- exact - 1
  third <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
    fixture$stage, bound$grant, bound$axes, budget)
  on.exit(third$close(), add = TRUE)
  stopifnot(third$mode == "spilled_projection", budget$used == retained)
  third$close()
  stopifnot(budget$disk == 0)
  TRUE
}

test_engine_broker_physical_plan_preadmission_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  get <- .engine_broker_get
  for (axis in c("cells", "features")) {
    budget <- get(".wb_operation_pack_v3_broker_projection_budget")(fixture$staged$bundle)
    budget$memory <- 1048576
    count <- new.env(parent = emptyenv()); count$decodes <- 0L
    options(scwb.physical_admission_probe = count)
    trace("fromJSON", where = asNamespace("jsonlite"), print = FALSE,
      tracer = quote({getOption("scwb.physical_admission_probe")$decodes <-
        getOption("scwb.physical_admission_probe")$decodes + 1L}))
    result <- tryCatch(get(".wb_matrix_stream_reader")(fixture$staged$bundle,
      "counts", axis, features = fixture$features, cells = fixture$cells,
      plan_admit = function(fragments) get(".wb_operation_pack_v3_broker_plan_admit")(
        fragments, list(features = fixture$features, cells = fixture$cells), budget)),
      error = identity)
    untrace("fromJSON", where = asNamespace("jsonlite"))
    options(scwb.physical_admission_probe = NULL)
    stopifnot(inherits(result, "error"), count$decodes == 0L,
      budget$used == 0, budget$disk == 0)
  }
  budget <- get(".wb_operation_pack_v3_broker_projection_budget")(fixture$staged$bundle)
  fragments <- wb_matrix_fragments(fixture$staged$bundle, "counts")
  fragments$n_features <- 2000000L
  # A tiny selected axis cannot hide original-axis reverse maps/metadata.
  result <- tryCatch(get(".wb_operation_pack_v3_broker_plan_admit")(
    fragments, list(features = fixture$features[1L], cells = fixture$cells[1L]), budget),
    error = identity)
  stopifnot(inherits(result, "error"), budget$used == 0, budget$disk == 0)
  roots <- list.files(tempdir(), "^scwb_matrix_reader_", full.names = TRUE)
  result <- tryCatch(get(".wb_matrix_stream_reader")(fixture$staged$bundle,
    "counts", "features", features = fixture$features, cells = fixture$cells,
    plan_admit = function(fragments) get(".wb_operation_pack_v3_broker_plan_admit")(
      fragments, list(features = fixture$features, cells = fixture$cells), budget),
    index_admit = function(...) {
      admitted <- get(".wb_operation_pack_v3_broker_index_admit")(..., budget = budget)
      admitted$verify <- function(...) stop("injected selected index verification failure")
      admitted
    }), error = identity)
  stopifnot(inherits(result, "error"),
    grepl("injected selected index verification failure", conditionMessage(result), fixed = TRUE),
    budget$used == 0, budget$disk == 0,
    identical(list.files(tempdir(), "^scwb_matrix_reader_", full.names = TRUE), roots))
  TRUE
}

test_engine_broker_mixed_feature_index_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  for (parts in c(4L, 8L)) {
    bound <- .engine_broker_grant(fixture, chunk_axis = "features", chunk_size = 16L / parts)
    ctx <- .engine_broker_context()
    ctx$indexes <- 0L
    original <- .engine_broker_get(".wb_operation_pack_v3_broker_index_admit")
    ctx$.wb_operation_pack_v3_broker_index_admit <- function(...) {
      ctx$indexes <- ctx$indexes + 1L
      original(...)
    }
    policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "67108864"))
    budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")(
      fixture$staged$bundle, policy)
    budget$mixed_graph <- TRUE
    reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
      fixture$stage, bound$grant, bound$axes, budget)
    stopifnot(ctx$full == 1L, ctx$indexes == 1L, length(ctx$roots) == 1L,
      budget$used > 0, budget$disk > 0,
      identical(BPCells::storage_order(scworkbench:::.wb_bp_open_matrix_dir(
        file.path(ctx$roots[[1L]], "fragment_1"))), "row"))
    for (features in wb_partition_axis(fixture$features, 16L / parts)) {
      actual <- reader$read(features, fixture$cells)
      stopifnot(identical(actual, fixture$values[features, , drop = FALSE]))
    }
    stopifnot(ctx$full == 1L, ctx$indexes == 1L)
    reader$close(); reader$close()
    stopifnot(budget$used == 0, budget$disk == 0, !any(dir.exists(ctx$roots)))
  }
  TRUE
}

test_engine_broker_mixed_constant_scan_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  for (private in c(FALSE, TRUE)) for (parts in c(8L, 32L)) {
    bound <- .engine_broker_grant(fixture, private = private, chunk_size = 64L / parts)
    ctx <- .engine_broker_context()
    budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")(
      fixture$staged$bundle)
    budget$limit <- 0; budget$mixed_graph <- TRUE
    if (!private) ctx$.wb_operation_pack_v3_broker_free_bytes <-
      function(...) stop("Mixed backed path must not probe spill capacity")
    reader <- ctx$.wb_operation_pack_v3_broker_reader(fixture$staged$bundle,
      fixture$stage, bound$grant, bound$axes, budget)
    stopifnot(reader$mode == if (private) "spilled_projection" else "bundle_stream",
      ctx$full == if (private) 0L else 1L, ctx$private == if (private) 1L else 0L)
    for (cells in wb_partition_axis(fixture$cells, 64L / parts)) {
      actual <- as.matrix(reader$read(fixture$features, cells))
      expected <- fixture$values[, cells, drop = FALSE]
      stopifnot(identical(unname(actual), unname(expected)),
        identical(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
          actual, fixture$features, cells),
          scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
            expected, fixture$features, cells)))
    }
    stopifnot(if (private) ctx$private == 1L else ctx$full == 1L,
      length(ctx$roots) == if (private) 0L else 1L)
    if (private) {
      path <- file.path(fixture$stage, "typed_slice_sources", "chunks", "matrix.mtx")
      bytes <- readBin(path, "raw", n = file.info(path)$size)
      con <- file(path, "ab"); writeBin(charToRaw("changed"), con); close(con)
      restore <- function() writeBin(bytes, path)
    } else {
      old <- DBI::dbGetQuery(fixture$staged$bundle$con,
        "SELECT description FROM matrices WHERE matrix_id='counts';")$description
      DBI::dbExecute(fixture$staged$bundle$con,
        "UPDATE matrices SET description='changed' WHERE matrix_id='counts';")
      restore <- function() DBI::dbExecute(fixture$staged$bundle$con,
        "UPDATE matrices SET description=? WHERE matrix_id='counts';", params = list(old))
    }
    failure <- tryCatch(reader$read(fixture$features, fixture$cells[17:24]), error = identity)
    stopifnot(inherits(failure, "error"), budget$used == 0, budget$disk == 0,
      !any(dir.exists(ctx$spills)))
    final <- tryCatch(if (private)
      scworkbench:::.wb_operation_pack_v3_private_source_validate(fixture$stage,
        bound$grant, bounded = TRUE) else
      scworkbench:::.wb_operation_pack_v3_typed_slice_grant_assert_current(
        fixture$staged$bundle, bound$grant), error = identity)
    stopifnot(inherits(final, "error"))
    restore(); reader$close()
  }
  TRUE
}

.engine_broker_mixed_main_case <- function(fixture, private, graph_kind,
                                          inject_fault = FALSE) {
  fixture$stage <- tempfile("mixed_transport_", tmpdir = fixture$root)
  dir.create(fixture$stage)
  bound <- .engine_broker_grant(fixture, private = private)
  ctx <- .engine_broker_context()
  ctx$modes <- character()
  create <- ctx$.wb_operation_pack_v3_broker_reader
  ctx$.wb_operation_pack_v3_broker_reader <- function(...) {
    reader <- create(...); ctx$modes <- c(ctx$modes, reader$mode); reader
  }
  make_budget <- .engine_broker_get(".wb_operation_pack_v3_broker_projection_budget")
  ctx$.wb_operation_pack_v3_broker_projection_budget <- function(...) {
    budget <- make_budget(...); budget$limit <- 0; budget
  }
  # This is a routing test of the actual matrix broker main, not a substitute
  # for authenticating graph payloads or a live Python ABI4 publication gate.
  ctx$.wb_operation_pack_v4_graph_cursor <- function(...) list(usage = function() list())
  id <- list(scheme = "fixture", sha256 = paste(rep("a", 64L), collapse = ""))
  request <- list(pack_abi_version = "4", request_identity = id,
    typed_slice_grants = list(bound$grant))
  if (graph_kind == "read") request$graph_read_grants <- list(list(input_name = "graph")) else
    request$graph_write_grants <- list(list(output_name = "graph", resource_budgets = list(
      max_spill_bytes = "8589934592", max_published_bytes = "8589934592",
      max_wal_bytes = "8589934592", max_memory_bytes = "67108864",
      max_collect_bytes = 16777216, partition_limits = list(max_decoded_bytes = 1048576,
        max_rows = 512L))))
  jsonlite::write_json(request, file.path(fixture$stage, "request.json"),
    auto_unbox = TRUE, null = "null")
  spool <- file.path(fixture$stage, "broker"); dir.create(spool)
  token <- paste(rep("f", 64L), collapse = "")
  old <- Sys.getenv(c("PYBENCH_OPERATION_PACK_BROKER_TOKEN",
    "PYBENCH_OPERATION_PACK_BROKER_TIMEOUT"), unset = NA_character_)
  on.exit({for (name in names(old)) if (is.na(old[[name]])) Sys.unsetenv(name) else
    do.call(Sys.setenv, setNames(list(old[[name]]), name))}, add = TRUE)
  Sys.setenv(PYBENCH_OPERATION_PACK_BROKER_TOKEN = token,
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT = "0.01")
  if (!inject_fault) file.create(file.path(spool, "stop.json")) else {
    control <- list(schema = "scworkbench.operation_pack.typed_slice_control_request.v1",
      request_identity = id, grant_identity = bound$grant$grant_identity,
      ordinal = 1L, features = as.list(fixture$features),
      cells = as.list(fixture$cells[1:8]), authorization_token = token)
    control$control_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
      control$schema, "control excluding control_identity", control)
    scworkbench:::.wb_operation_pack_v3_atomic_canonical_json(control,
      file.path(spool, "request.json"))
    publish <- .engine_broker_get(".wb_operation_pack_v3_broker_publish_response")
    ctx$.wb_operation_pack_v3_broker_publish_response <- function(...) {
      answer <- publish(...)
      scworkbench:::.wb_operation_pack_v2_fault("before_publication")
      answer
    }
  }
  main <- .engine_broker_get(".wb_operation_pack_v3_broker_main")
  environment(main) <- ctx
  result <- tryCatch(main(fixture$stage, fixture$staged$bundle$dir,
    fixture$bundle$dir), error = identity)
  stopifnot(identical(ctx$modes, if (private) "spilled_projection" else "bundle_stream"),
    length(ctx$roots) == if (private) 0L else 1L,
    !any(dir.exists(ctx$roots)), !any(dir.exists(ctx$spills)))
  list(result = result, stage = fixture$stage, full = ctx$full, private = ctx$private)
}

test_engine_broker_mixed_main_routing_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  for (private in c(FALSE, TRUE)) for (kind in c("read", "write")) {
    result <- .engine_broker_mixed_main_case(fixture, private, kind)
    stopifnot(!inherits(result$result, "error"), result$full == if (private) 0L else 1L,
      result$private == if (private) 1L else 0L,
      file.exists(file.path(result$stage, "broker-observations.json")))
  }
  TRUE
}

test_engine_broker_mixed_fault_source_only_contract <- function() {
  fixture <- .engine_broker_fixture()
  on.exit(.engine_broker_close(fixture), add = TRUE)
  count <- function() vapply(c("artifacts", "prov_runs", "prov_run_outputs",
    "prov_materializations", "spaces"), function(table) nrow(DBI::dbGetQuery(
      fixture$bundle$con, paste0("SELECT * FROM ", table, ";"))), integer(1))
  before <- count()
  old <- getOption("scworkbench.operation_pack_v2_test_hook")
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (event == "before_publication") stop("injected mixed publication failure")
  })
  on.exit(options(scworkbench.operation_pack_v2_test_hook = old), add = TRUE)
  for (private in c(FALSE, TRUE)) {
    result <- .engine_broker_mixed_main_case(fixture, private, "read", inject_fault = TRUE)
    stopifnot(inherits(result$result, "error"), identical(count(), before),
      grepl("injected mixed publication failure", conditionMessage(result$result)),
      !file.exists(file.path(result$stage, "broker-observations.json")),
      file.exists(file.path(result$stage, "broker-error.json")),
      identical(DBI::dbGetQuery(fixture$bundle$con, "PRAGMA quick_check;")[[1L]], "ok"))
  }
  TRUE
}
