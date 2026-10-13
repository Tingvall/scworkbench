# Small fixtures force bounded storage infrastructure; large physical stress is deferred.
test_graph_small_forced_out_of_core_public_lifecycle_contract <- function() {
  registry <- scworkbench:::.wb_operation_pack_registry
  registry_preimage <- as.list(registry, all.names = TRUE)
  namespaces_preimage <- loadedNamespaces()
  source("tests/fixtures/graph_small_out_of_core_support.R", local = TRUE)
  source("tests/fixtures/graph_native_rna_namespace_support.R", local = TRUE)
  fixture_file <- "tests/fixtures/graph_small_out_of_core_case.json"
  stopifnot(digest::digest(file = fixture_file, algo = "sha256", serialize = FALSE) ==
    "60741a7915721fb6c8872ad58a656dce3fb1c1de42bad52ab756cacd4ea703d2")
  fixture <- jsonlite::read_json(fixture_file, simplifyVector = FALSE)
  policy <- fixture$budgets
  policy$sqlite_cache_kib <- as.integer(policy$sqlite_cache_kib)
  policy$partition_rows <- as.integer(policy$partition_rows)
  policy$partition_bytes <- as.integer(policy$partition_bytes)
  policy$collect_bytes <- as.integer(policy$collect_bytes)
  root <- tempfile("graph_small_gate_"); dir.create(root)
  lib <- file.path(root, "library"); dir.create(lib)
  bundle <- NULL; sessions <- list(); old_lib <- .libPaths()
  old_options <- options("scworkbench.graph_storage_test_hook", "scworkbench.promotion_transaction_test_hook",
    "scworkbench.operation_pack_v2_test_hook")
  on.exit({
    options(old_options)
    for (session in sessions) try(wb_session_discard(session), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    extra_bindings <- setdiff(ls(registry, all.names = TRUE), names(registry_preimage))
    if (length(extra_bindings)) rm(list = extra_bindings, envir = registry)
    list2env(registry_preimage, envir = registry)
    for (package in c("scwbGraphSmallFixture", "scwbRNA"))
      if (!package %in% namespaces_preimage && package %in% loadedNamespaces())
        try(unloadNamespace(package), silent = TRUE)
    .libPaths(old_lib); unlink(root, recursive = TRUE)
  }, add = TRUE)
  pack <- wb_operation_pack_scaffold(file.path(root, "pack"), "scwbGraphSmallFixture",
    "graphsmallfixture", "Infrastructure Fixture", "fixture@example.org", template = "graph")
  stopifnot(file.copy("tests/fixtures/graph_small_out_of_core_pack_register.R",
    file.path(pack$path, "R", "register.R"), overwrite = TRUE),
    file.copy("tests/fixtures/graph_small_out_of_core_manifest.json", pack$manifest, overwrite = TRUE),
    file.copy(fixture_file, file.path(pack$path, "inst", "small.json")))
  stopifnot(wb_operation_pack_check(pack$path)$qualified)
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(pack$path)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  # Reuse the accepted native producer without changing its pack or authority.
  rna <- graph_native_rna_fixture_source()
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(rna)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, old_lib)); wb_operation_pack_load("scwbGraphSmallFixture", lib.loc = lib)
  rna_files <- c("R/scwbRNA.rdb", "R/scwbRNA.rdx", "NAMESPACE",
    "scworkbench/operation-pack.json")
  rna_hashes <- function(package_root) stats::setNames(vapply(rna_files, function(file) {
    path <- file.path(package_root, file)
    stopifnot(file.exists(path), !dir.exists(path))
    digest::digest(file = path, algo = "sha256", serialize = FALSE)
  }, character(1)), rna_files)
  rna_installed_root <- normalizePath(file.path(lib, "scwbRNA"), mustWork = TRUE)
  rna_runtime_root <- rna_installed_root
  rna_library <- lib
  rna_installed_hashes <- rna_hashes(rna_installed_root)
  if ("scwbRNA" %in% namespaces_preimage) {
    # Preserve an existing live namespace. Its code and manifest must exactly
    # match the distribution freshly installed from the pinned source above.
    rna_runtime_root <- normalizePath(getNamespaceInfo(asNamespace("scwbRNA"), "path"),
      mustWork = TRUE)
    stopifnot(identical(rna_installed_hashes, rna_hashes(rna_runtime_root)))
    rna_library <- dirname(rna_runtime_root)
    stopifnot(identical(normalizePath(system.file(package = "scwbRNA", lib.loc = rna_library),
      mustWork = TRUE), rna_runtime_root))
  }
  rna_distribution <- list(choice = if ("scwbRNA" %in% namespaces_preimage)
    "byte_identical_preexisting_namespace" else "fresh_pinned_install",
    freshly_installed_path = rna_installed_root, runtime_path = rna_runtime_root,
    source_commit = "151dd29211b219343dce6247c5e48fc932b4c83d",
    installed_source_bytes_sha256 = as.list(rna_installed_hashes))
  cat("GRAPH_SMALL_RNA_DISTRIBUTION choice=", rna_distribution$choice,
    " exact_code_manifest_comparison=PASS\n", sep = "")
  wb_operation_pack_load("scwbRNA", lib.loc = rna_library)
  bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  plan <- fixture$source_plan
  cells <- unlist(plan$cell_ids, use.names = FALSE); features <- unlist(plan$feature_ids, use.names = FALSE)
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "seed", Matrix::Matrix(matrix(unlist(plan$values_column_major), 2L,
    dimnames = list(features, cells)), sparse = TRUE))
  # source_plan describes the seed. The promoted source is the actual producer's
  # log1p(seed / column sum * 10000), authenticated independently by core.
  native <- wb_session_run_op(wb_session_new(), bundle, "scwbrna::matrix_log_normalize",
    inputs = list(matrix = "seed", output_matrix_id = "small_native", cell_set = "all",
      min_cells = 1L, chunk_size = 2L))
  sessions[[length(sessions) + 1L]] <- native$session
  wb_session_promote_current(bundle, native$session, outputs = "summary")
  native_id <- native$run$outputs$matrix$matrix_id
  stopifnot(native_id %in% wb_matrices(bundle)$matrix_id)
  # This snapshot includes loaded R/packages and native-source setup. Framework
  # admission remains a separate policy; these observations imply no RSS delta.
  process_status <- readLines("/proc/self/status", warn = FALSE)
  process_bytes <- function(field) {
    line <- process_status[startsWith(process_status, paste0(field, ":"))]
    stopifnot(length(line) == 1L)
    as.numeric(strsplit(trimws(sub(paste0("^", field, ":"), "", line)),
      "[[:space:]]+")[[1L]][[1L]]) * 1024
  }
  packages <- sort(loadedNamespaces(), method = "radix")
  runtime_baseline <- list(stage = "after_native_promotion_before_graph_emit",
    pid = Sys.getpid(), rss_bytes = process_bytes("VmRSS"),
    high_water_mark_bytes = process_bytes("VmHWM"),
    loaded_packages = stats::setNames(lapply(packages, function(package)
      as.character(utils::packageVersion(package))), packages))
  cat("GRAPH_SMALL_RUNTIME_BASELINE stage=", runtime_baseline$stage,
    " rss_bytes=", runtime_baseline$rss_bytes, " hwm_bytes=", runtime_baseline$high_water_mark_bytes,
    " framework_working_policy_bytes=1048576 rss_delta_claim=NONE\n", sep = "")
  source_state <- function() list(
    cache = DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(bundle$con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = bundle$con@ref$wb_graph_policy, cap = bundle$con@ref$wb_graph_cache_kib)
  source_initial <- source_state()
  token_paths <- character(); canonical_token_peak <- 0
  assert_restored <- function() stopifnot(identical(source_initial, source_state()),
    !any(file.exists(token_paths)))
  paths <- character(); stages <- list(); cache_reservations <- numeric(); aggregate_cache <- numeric(); identities <- 0L; disk_peak <- 0
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "connected") paths <<- c(paths, state$path)
    if (event == "canonical_tokens" && identical(state$budgets$memory_bytes, "1048576")) {
      stopifnot(file.exists(state$path), file.info(state$path)$size > 0,
        state$canonical_bytes == "22564", file.info(state$path)$size == 22564)
      token_paths <<- c(token_paths, state$path)
      canonical_token_peak <<- max(canonical_token_peak, file.info(state$path)$size)
    }
    if (event %in% c("configured", "identity_budget") && state$budgets$memory_bytes == "1048576") {
      stopifnot(state$budgets$partition_rows <= 2L, state$budgets$partition_bytes <= 4096L)
      # Core test instrumentation; author code cannot inspect storage or connections.
      usage <- scworkbench:::.wb_graph_transient_usage(budgets = state$budgets)
      disk_peak <<- max(disk_peak, usage$owned_spill_bytes)
      if (event == "configured") {
        stopifnot(file.exists(state$path))
        stages[[length(stages) + 1L]] <<- state
        stage_connections <- lapply(Filter(function(stage) !stage$closed, stages), function(stage) stage$con)
        connections <- list()
        for (frame in sys.frames()) if (exists("bundle", envir = frame, inherits = FALSE)) {
          candidate <- get("bundle", envir = frame, inherits = FALSE)
          if (inherits(candidate, "scworkbench_bundle"))
            connections <- c(connections, scworkbench:::.wb_graph_bundle_connections(candidate))
        }
        connections <- Filter(function(con) DBI::dbIsValid(con) &&
          identical(con@ref$wb_graph_policy$memory_bytes, "1048576"), connections)
        connections <- c(Filter(DBI::dbIsValid, stage_connections), connections)
        connections <- connections[!duplicated(vapply(connections, function(con) format(con@ref), character(1)))]
        reserved <- sum(vapply(connections, function(con)
          -DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]], numeric(1))) + 128
        if (reserved > 256) message("SMALL_AGGREGATE_ADMISSION_GAP cache_kib=", reserved,
          " live_connections=", length(connections), " caller=",
          paste(vapply(sys.calls(), function(call) paste(deparse(call), collapse = " "), character(1)), collapse = " -> "))
        stopifnot(reserved <= 256, reserved * 1024 + 8 * 4096 <= 1048576)
        aggregate_cache <<- c(aggregate_cache, reserved)
        cache <- -DBI::dbGetQuery(state$con, "PRAGMA cache_size;")[[1L]][[1L]]
        stopifnot(cache <= 256L); cache_reservations <<- c(cache_reservations, cache)
      }
      if (event == "identity_budget") identities <<- identities + 1L
    }
  })
  before <- graph_small_fingerprint(bundle$dir)
  emit_inputs <- list(matrix = native_id, cell_set = "all", min_cells = 1L)
  emitted <- wb_session_run_op(wb_session_new(), bundle, "graphsmallfixture::emit_small", inputs = emit_inputs)
  sessions[[length(sessions) + 1L]] <- emitted$session
  assert_restored()
  retained_stage <- attr(emitted$run$outputs$result, "graph_stage", exact = TRUE)
  stopifnot(is.environment(retained_stage), file.exists(retained_stage$path),
    identical(before, graph_small_fingerprint(bundle$dir)),
    !any(file.exists(setdiff(paths, retained_stage$path))))
  request <- jsonlite::read_json(file.path(emitted$session$staging_bundle$dir, "operation_pack_v2",
    emitted$run$operation_pack_transition$transition_id, "request.json"), simplifyVector = FALSE)
  transition <- file.path(emitted$session$staging_bundle$dir, "operation_pack_v2",
    emitted$run$operation_pack_transition$transition_id)
  token <- file.path(transition, "outputs", "result", "graph.parts.ndjson")
  stopifnot(file.exists(token), file.info(token)$size > 8192, file.info(token)$size <= 16777216)
  partitions <- lapply(readLines(token, warn = FALSE, encoding = "UTF-8"),
    function(line) jsonlite::fromJSON(line, simplifyVector = FALSE))
  stopifnot(all(vapply(partitions, function(part) as.numeric(part$row_count) <= 2, logical(1))))
  token_bytes <- file.info(token)$size
  max_part_bytes <- max(nchar(readLines(token, warn = FALSE, encoding = "UTF-8"), type = "bytes"))
  stopifnot(max_part_bytes <= 4096)
  axes <- request$graph_write_grants[[1L]]$authorized_source_axes
  axis_fields <- c("input_name", "source_binding_id", "axis_kind", "source_ref", "source_snapshot_identity",
    "axis_content_identity", "axis_order_identity", "axis_count")
  bindings <- lapply(plan$bindings, function(binding) {
    axis <- Filter(function(axis) axis$axis_kind == binding$axis_kind, axes)[[1L]]
    stopifnot(axis$axis_count == if (binding$axis_kind == "cell") "32" else "2",
      axis$source_payload_closure_identity$scheme == "scworkbench.content.matrix.fragment-tree.v2")
    wb_graph_binding_from_source(axis[axis_fields], binding$binding_id, binding$mapping)
  })
  content <- fixture$content; attrs <- content$attributes
  expected <- wb_prim_graph(content$nodes, content$edges, content$incidences,
    attrs$graph, attrs$node, attrs$edge, attrs$incidence, associations = bindings, direction_mode = "mixed")
  stopifnot(wb_graph_identity(expected)$content_identity$sha256 ==
    "d98d32aaceec530597ec03aabb2eeb3aa6697639852cfba754c9165f95735e24")
  evidence_dir <- Sys.getenv("SCWB_GRAPH_SMALL_EVIDENCE_DIR", "")
  if (nzchar(evidence_dir)) {
    dir.create(evidence_dir, recursive = TRUE, showWarnings = FALSE)
    for (file in c("request.json", "receipt.json"))
      stopifnot(file.copy(file.path(transition, file), file.path(evidence_dir, paste0("R_small_", file)), overwrite = FALSE))
    jsonlite::write_json(list(fixture_sha256 = digest::digest(file = fixture_file, algo = "sha256", serialize = FALSE),
      identity = wb_graph_identity(expected), content = expected$content, bindings = expected$associations,
      axes = axes, policy = policy, runtime_baseline = runtime_baseline,
      rna_distribution = rna_distribution,
      source_producer = list(operation = "scwbrna::matrix_log_normalize",
        pack_commit = "151dd29211b219343dce6247c5e48fc932b4c83d", seed_values_column_major = plan$values_column_major,
        transform = "log1p(seed / column_sum * 10000)", effective_params = native$run$params)), file.path(evidence_dir, "R_small_authenticated_expected.json"),
      auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
  }
  tables <- c("artifacts", "artifact_graph_meta", "artifact_graph_rows", "prov_commits", "prov_runs",
    "prov_run_outputs", "prov_run_entity_bindings")
  counts <- function() stats::setNames(vapply(tables, function(table)
    as.numeric(DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) n FROM ", table))$n[[1L]]), numeric(1)), tables)
  baseline <- counts(); filenames <- list.files(bundle$dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  for (boundary in c("graph_component_rows", "after_first_private_terminal_write", "after_payload_move_before_database_commit")) {
    options(scworkbench.promotion_transaction_test_hook = local({ selected <- boundary
      function(event, ...) if (event == selected) stop(paste0("small-promotion-fault-", selected)) }))
    failed <- tryCatch(wb_session_promote_current(bundle, emitted$session, outputs = "result"), error = identity)
    options(scworkbench.promotion_transaction_test_hook = NULL)
    assert_restored()
    stopifnot(inherits(failed, "error"), grepl(paste0("small-promotion-fault-", boundary), conditionMessage(failed), fixed = TRUE),
      identical(baseline, counts()), identical(filenames, list.files(bundle$dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)),
      file.exists(retained_stage$path), !any(file.exists(setdiff(paths, retained_stage$path))))
  }
  promotion <- wb_session_promote_current(bundle, emitted$session, outputs = "result")
  assert_restored()
  stopifnot(nrow(promotion$promoted) == 2L)
  artifact <- promotion$promoted$artifact_id[promotion$promoted$output == "result"][[1L]]
  graph_small_assert(bundle, artifact, expected, policy)
  emitted$session <- wb_session_discard(emitted$session)
  sessions[[2L]] <- emitted$session
  stopifnot(!any(file.exists(paths)))
  read_inputs <- list(source = wb_ref_artifact(artifact, "result"), min_cells = 1L)
  for (boundary in c("before_dispatch", "receipt_received", "audited", "before_publication", "published", "reopened")) {
    scratch <- sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))
    before <- graph_small_fingerprint(bundle$dir)
    options(scworkbench.operation_pack_v2_test_hook = local({ selected <- boundary
      function(event, ...) if (event == selected) stop(paste0("small-execution-fault-", selected)) }))
    failed <- tryCatch(wb_session_run_op(wb_session_new(), bundle, "graphsmallfixture::copy_small", inputs = read_inputs), error = identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    assert_restored()
    stopifnot(inherits(failed, "error"), grepl(paste0("small-execution-fault-", boundary), conditionMessage(failed), fixed = TRUE),
      identical(before, graph_small_fingerprint(bundle$dir)),
      identical(scratch, sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))), !any(file.exists(paths)))
  }
  before <- graph_small_fingerprint(bundle$dir)
  scratch <- sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))
  rejected <- tryCatch(wb_session_run_op(wb_session_new(), bundle, "graphsmallfixture::collect_small", inputs = read_inputs), error = identity)
  assert_restored()
  stopifnot(inherits(rejected, "error"), grepl("GRAPH_RESOURCE_EXCEEDED|Whole-graph materialization", conditionMessage(rejected)),
    identical(before, graph_small_fingerprint(bundle$dir)),
    identical(scratch, sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))), !any(file.exists(paths)))
  copied <- wb_session_run_op(wb_session_new(), bundle, "graphsmallfixture::copy_small", inputs = read_inputs)
  sessions[[length(sessions) + 1L]] <- copied$session
  assert_restored()
  stopifnot(identical(before, graph_small_fingerprint(bundle$dir)))
  copied_promotion <- wb_session_promote_current(bundle, copied$session, outputs = "result")
  assert_restored()
  stopifnot(nrow(copied_promotion$promoted) == 2L)
  copied_id <- copied_promotion$promoted$artifact_id[copied_promotion$promoted$output == "result"][[1L]]
  info <- graph_small_assert(bundle, copied_id, expected, policy)
  if (nzchar(evidence_dir)) {
    copy_transition <- file.path(copied$session$staging_bundle$dir, "operation_pack_v2",
      copied$run$operation_pack_transition$transition_id)
    for (file in c("request.json", "receipt.json"))
      stopifnot(file.copy(file.path(copy_transition, file),
        file.path(evidence_dir, paste0("R_small_copy_", file)), overwrite = FALSE))
  }
  copied$session <- wb_session_discard(copied$session)
  sessions[[3L]] <- copied$session
  assert_restored()
  stopifnot(length(token_paths) > 0L, canonical_token_peak == 22564, identities > 0L, length(paths) > 0L, length(cache_reservations) > 0L, length(aggregate_cache) > 0L,
    disk_peak > 0, !any(file.exists(paths)), wb_finalize_recipient_bundle(bundle)$ready)
  for (session in sessions) wb_session_discard(session)
  sessions <- list()
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- file.path(root, "relocated.bundle")
  stopifnot(file.rename(file.path(root, "source.bundle"), relocated))
  record_file <- file.path(root, "expected.rds")
  saveRDS(list(artifacts = c(artifact, copied_id), expected = expected, policy = policy), record_file)
  recipient_log <- file.path(root, "recipient.log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote(normalizePath("tests/fixtures/graph_small_out_of_core_recipient.R")),
    shQuote(system.file(package = "scworkbench")), shQuote(relocated), shQuote(record_file),
    shQuote(normalizePath("tests/fixtures/graph_small_out_of_core_support.R"))), stdout = recipient_log, stderr = recipient_log)
  cat(paste(readLines(recipient_log, warn = FALSE), collapse = "\n"), "\n")
  stopifnot(status == 0L)
  cat("GRAPH_SMALL_GATE content=", info$content_identity$sha256,
    " binding=", info$binding_identity$sha256, " descriptor=", info$descriptor_identity$sha256,
    " max_token_partition_bytes=", max_part_bytes, " token_bytes=", token_bytes,
    " max_canonical_token_bytes=", canonical_token_peak, " canonical_token_files=", length(token_paths),
    " disk_peak_observed=", disk_peak, " stage_count=", length(paths), " max_stage_cache_kib=", max(cache_reservations),
    " max_observed_aggregate_cache_kib=", max(aggregate_cache),
    " runtime_baseline_rss_bytes=", runtime_baseline$rss_bytes,
    " runtime_baseline_hwm_bytes=", runtime_baseline$high_water_mark_bytes,
    " runtime_baseline_stage=after_native_promotion_before_graph_emit rss_delta_claim=NONE",
    " rna_distribution=", rna_distribution$choice,
    " working_policy=1048576 aggregate_cache_policy=262144 partitions=4096/2 collect_rejected=8192",
    " mixed_promotion=TRUE rollback_retry=TRUE cleanup=TRUE source_purity=TRUE large_physical_stress=DEFERRED\n", sep = "")
  TRUE
}
