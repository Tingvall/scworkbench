test_graph_native_matrix_public_promotion_first_lifecycle_contract <- function() {
  library_dir <- tempfile("graph_native_public_library_"); dir.create(library_dir)
  root <- tempfile("graph_native_public_bundle_"); bundle <- NULL
  old <- .libPaths(); sessions <- list()
  namespaces_before <- loadedNamespaces()
  registry <- scworkbench:::.wb_operation_pack_registry
  registry_before <- as.list.environment(registry, all.names = TRUE)
  source("tests/fixtures/graph_native_rna_namespace_support.R", local = TRUE)
  on.exit({
    for (namespace in c("scwbnativegraphfixture", "scwbrna"))
      try(wb_operation_pack_unload(namespace), silent = TRUE)
    for (session in sessions) try(wb_session_discard(session), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    for (binding in setdiff(ls(registry, all.names = TRUE), names(registry_before)))
      rm(list = binding, envir = registry)
    for (binding in names(registry_before)) assign(binding, registry_before[[binding]], envir = registry)
    if (!"scwbRNA" %in% namespaces_before && "scwbRNA" %in% loadedNamespaces())
      try(unloadNamespace("scwbRNA"), silent = TRUE)
    if (!"scwbNativeGraphFixture" %in% namespaces_before && "scwbNativeGraphFixture" %in% loadedNamespaces())
      try(unloadNamespace("scwbNativeGraphFixture"), silent = TRUE)
    .libPaths(old); unlink(c(library_dir, root), recursive = TRUE)
  }, add = TRUE)
  rna <- "/home/dirk/Projects/operation_packs/scwbRNA"
  stopifnot(identical(system2("git", c("-C", rna, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    "151dd29211b219343dce6247c5e48fc932b4c83d"))
  for (source in c(rna, file.path(normalizePath("."), "tests", "fixtures", "operation-pack-v4-native-matrix"))) {
    log <- tempfile("native_graph_fixture_install_")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(library_dir)), shQuote(source)), stdout = log, stderr = log)
    if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  }
  .libPaths(c(library_dir, old))
  wb_operation_pack_load("scwbRNA", lib.loc =
    graph_native_rna_fixture_library(library_dir, namespaces_before))
  wb_operation_pack_load("scwbNativeGraphFixture", lib.loc = library_dir)
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c3"); features <- c("g2", "g1")
  wb_define_cells(bundle, cells)
  wb_set_create(bundle, "selected", cells[1:2], source = "assembly")
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(1:6, 2L,
    dimnames = list(features, cells)), sparse = TRUE))
  normalized <- wb_session_run_op(wb_session_new(), bundle, "scwbrna::matrix_log_normalize",
    inputs = list(matrix = "RNA", output_matrix_id = "RNA_log", min_cells = 1L, chunk_size = 2L))
  sessions[[length(sessions) + 1L]] <- normalized$session
  stopifnot("RNA_log" %in% wb_matrices(normalized$session$staging_bundle)$matrix_id,
    !"RNA_log" %in% wb_matrices(bundle)$matrix_id)
  fingerprint <- function(path) {
    paths <- sort(list.files(path, recursive = TRUE, all.files = TRUE, full.names = TRUE,
      no.. = TRUE), method = "radix")
    paths <- paths[!file.info(paths)$isdir]
    stats::setNames(vapply(paths, function(file) digest::digest(file = file,
      algo = "sha256", serialize = FALSE), character(1)), substring(paths, nchar(path) + 2L))
  }
  source_before <- fingerprint(root)
  stage_before <- fingerprint(normalized$session$staging_bundle$dir)
  private_before <- sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))
  opened <- 0L
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state)
    if (event == "connected") opened <<- opened + 1L)
  on.exit(options(hook), add = TRUE)
  error <- tryCatch(wb_session_run_op(normalized$session, bundle,
    "scwbnativegraphfixture::matrix_to_bound_graph", inputs = list(
      matrix = wb_ref_run(normalized$run$run_id, "matrix"), cell_set = "set:selected", min_cells = 1L)),
    error = identity)
  options(hook)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_SOURCE_AUTHORITY_REQUIRED", opened == 0L,
    identical(source_before, fingerprint(root)),
    identical(stage_before, fingerprint(normalized$session$staging_bundle$dir)),
    identical(private_before, sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))))
  promoted_matrix <- wb_session_promote_current(bundle, normalized$session, outputs = "summary")
  stopifnot("RNA_log" %in% wb_matrices(bundle)$matrix_id)
  # The original point-in-time session overlay has no newly retained producer
  # head. Its existing durable source handle authenticates promotion, while its
  # own complete native payload and axes are independently compared.
  reused <- wb_session_run_op(normalized$session, bundle,
    "scwbnativegraphfixture::matrix_to_bound_graph", inputs = list(
      matrix = wb_ref_run(normalized$run$run_id, "matrix"), cell_set = "set:selected", min_cells = 1L))
  sessions[[length(sessions) + 1L]] <- reused$session
  stopifnot(identical(reused$run$outputs$result$kind, "graph"))
  reused_promotion <- wb_session_promote_current(bundle, reused$session, outputs = "result")
  stopifnot(sum(reused_promotion$promoted$output == "result",na.rm=TRUE) == 1L)
  reused_id <- reused_promotion$promoted$artifact_id[reused_promotion$promoted$output == "result"][[1L]]
  stopifnot(wb_art_graph_info(bundle,reused_id)$source_authority$status == "verified")
  bound <- wb_session_run_op(wb_session_new(), bundle,
    "scwbnativegraphfixture::matrix_to_bound_graph", inputs = list(
      matrix = "RNA_log", cell_set = "set:selected", min_cells = 1L))
  sessions[[length(sessions) + 1L]] <- bound$session
  sample_dir <- Sys.getenv("SCWB_NATIVE_GRAPH_SAMPLE_DIR", "")
  save_sample <- function(result, prefix) {
    if (!nzchar(sample_dir)) return(invisible(NULL))
    dir.create(sample_dir, recursive = TRUE, showWarnings = FALSE)
    transition <- file.path(result$session$staging_bundle$dir, "operation_pack_v2",
      result$run$operation_pack_transition$transition_id)
    for (file in c("request.json", "receipt.json")) {
      destination <- file.path(sample_dir, paste0(prefix, "_", file))
      stopifnot(!file.exists(destination), file.copy(file.path(transition, file), destination))
    }
  }
  save_sample(bound, "direct_matrix")
  counts <- function() vapply(c("artifacts","artifact_graph_meta","artifact_graph_rows",
    "prov_commits","prov_runs","prov_run_outputs","prov_run_entity_bindings","matrix_fragments"),
    function(table)as.numeric(DBI::dbGetQuery(bundle$con,paste0("SELECT COUNT(*) n FROM ",table))$n[[1L]]),numeric(1))
  before <- counts()
  before_payloads <- list.files(root,recursive=TRUE,all.files=TRUE,no..=TRUE)
  for(boundary in c("graph_component_rows","after_first_private_terminal_write",
      "after_payload_move_before_database_commit")) {
    promotion_hook <- options(scworkbench.promotion_transaction_test_hook=local({
      selected <- boundary
      function(event,...)if(event==selected)stop(paste0("native-graph-promotion-fault-",selected))
    }))
    on.exit(options(promotion_hook),add=TRUE)
    failed <- tryCatch(wb_session_promote_current(bundle,bound$session,outputs="result"),error=identity)
    options(promotion_hook)
    stopifnot(inherits(failed,"error"),grepl(paste0("native-graph-promotion-fault-",boundary),conditionMessage(failed),fixed=TRUE),
      identical(before,counts()),identical(before_payloads,list.files(root,recursive=TRUE,all.files=TRUE,no..=TRUE)))
  }
  # Change the actual durable source after issuance; an unchanged cloned input
  # and correctly hashed request cannot bypass independent source revalidation.
  fragment <- DBI::dbGetQuery(bundle$con,
    "SELECT fragment_id,description FROM matrix_fragments WHERE matrix_id='RNA_log' ORDER BY rowid LIMIT 1;")
  private_before <- sort(list.dirs(scworkbench:::.wb_session_stage_root(),recursive=FALSE))
  changed <- FALSE
  source_hook <- options(scworkbench.operation_pack_v2_test_hook=function(event,...) {
    if(event=="before_dispatch") {
      DBI::dbExecute(bundle$con,"UPDATE matrix_fragments SET description=? WHERE fragment_id=?;",
        params=list("changed-after-native-source-admission",fragment$fragment_id[[1L]]))
      changed <<- TRUE
    }
  })
  on.exit(options(source_hook),add=TRUE)
  failed <- tryCatch(wb_session_run_op(wb_session_new(),bundle,
    "scwbnativegraphfixture::matrix_to_bound_graph",inputs=list(matrix="RNA_log",cell_set="set:selected",min_cells=1L)),error=identity)
  options(source_hook)
  DBI::dbExecute(bundle$con,"UPDATE matrix_fragments SET description=? WHERE fragment_id=?;",
    params=list(fragment$description[[1L]],fragment$fragment_id[[1L]]))
  stopifnot(changed,inherits(failed,"error"),grepl("GRAPH_SOURCE_AUTHORITY_INVALID",conditionMessage(failed),fixed=TRUE),
    identical(before,counts()),identical(private_before,sort(list.dirs(scworkbench:::.wb_session_stage_root(),recursive=FALSE))))
  # Generic execution failures at each lifecycle boundary release a fresh
  # owned session clone and leave the durable source/provenance closure intact.
  for(boundary in c("before_dispatch","receipt_received","audited","before_publication","published","reopened")) {
    private_before <- sort(list.dirs(scworkbench:::.wb_session_stage_root(),recursive=FALSE))
    execution_hook <- options(scworkbench.operation_pack_v2_test_hook=local({
      selected <- boundary
      function(event,...)if(event==selected)stop(paste0("native-graph-execution-fault-",selected))
    }))
    on.exit(options(execution_hook),add=TRUE)
    failed <- tryCatch(wb_session_run_op(wb_session_new(),bundle,
      "scwbnativegraphfixture::matrix_to_bound_graph",inputs=list(matrix="RNA_log",cell_set="set:selected",min_cells=1L)),error=identity)
    options(execution_hook)
    stopifnot(inherits(failed,"error"),grepl(paste0("native-graph-execution-fault-",boundary),conditionMessage(failed),fixed=TRUE),
      identical(before,counts()),identical(private_before,sort(list.dirs(scworkbench:::.wb_session_stage_root(),recursive=FALSE))))
  }
  promoted <- wb_session_promote_current(bundle, bound$session, outputs = "result")
  id <- promoted$promoted$artifact_id[promoted$promoted$output == "result"][[1L]]
  policy <- list(memory_bytes = "8388608", sqlite_cache_kib = 2048L, partition_bytes = 262144L,
    partition_rows = 256L, collect_bytes = 4194304L)
  info <- wb_art_graph_info(bundle, id, policy)
  stopifnot(info$source_authority$status == "verified", info$component_counts$bindings == "2",
    info$component_counts$nodes == "3", info$component_counts$binding_mappings == "3")
  bindings <- wb_art_graph_slice(bundle, id, "bindings")
  stopifnot(identical(vapply(bindings, function(binding) binding$source_ref$source_id, character(1)),
    rep("RNA_log", 2L)))
  request_path <- file.path(bound$session$staging_bundle$dir, "operation_pack_v2",
    bound$run$operation_pack_transition$transition_id, "request.json")
  request <- jsonlite::fromJSON(request_path, simplifyVector = FALSE)
  authorities <- request$graph_write_grants[[1L]]$authorized_source_axes
  stopifnot(identical(vapply(authorities, `[[`, character(1), "axis_count"), c("3", "2")),
    all(vapply(authorities, function(axis) axis$source_payload_closure_identity$scheme ==
      "scworkbench.content.matrix.fragment-tree.v2", logical(1))))
  read_identity_budgets <- list()
  read_budget_hook <- options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(identical(event,"identity_budget"))
      read_identity_budgets[[length(read_identity_budgets)+1L]] <<- state$budgets
  })
  on.exit(options(read_budget_hook),add=TRUE)
  read <- wb_session_run_op(wb_session_new(), bundle, "scwbnativegraphfixture::read_bound_graph",
    inputs = list(source = wb_ref_artifact(id, "result"), min_cells = 1L))
  options(read_budget_hook)
  cat("NATIVE_GRAPH_READ_IDENTITY_BUDGETS",paste(unique(vapply(read_identity_budgets,
    function(budget)paste(budget$memory_bytes,budget$partition_bytes,budget$partition_rows,sep="/"),
    character(1))),collapse=","),"\n")
  stopifnot(length(read_identity_budgets)>0L,
    all(vapply(read_identity_budgets,function(budget)
      as.numeric(budget$memory_bytes)<=8388608 && budget$partition_bytes<=262144 &&
      budget$partition_rows<=256,logical(1))))
  read_request <- jsonlite::fromJSON(file.path(read$session$staging_bundle$dir,
    "operation_pack_v2",read$run$operation_pack_transition$transition_id,"request.json"),
    simplifyVector=FALSE)
  stopifnot(identical(read_request$graph_read_grants[[1L]]$partition_limits,
    list(max_rows="256",max_decoded_bytes="262144")))
  sessions[[length(sessions) + 1L]] <- read$session
  save_sample(read, "selected_graph")
  next_promotion <- wb_session_promote_current(bundle, read$session, outputs = "result")
  next_id <- next_promotion$promoted$artifact_id[next_promotion$promoted$output == "result"][[1L]]
  next_info <- wb_art_graph_info(bundle, next_id, policy)
  stopifnot(identical(info$descriptor_identity, next_info$descriptor_identity),
    next_info$source_authority$status == "verified", isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  descriptor <- next_info$descriptor_identity$sha256
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- tempfile("graph_native_public_relocated_")
  on.exit(unlink(relocated, recursive = TRUE), add = TRUE)
  fs::dir_copy(root, relocated)
  recipient_log <- tempfile("graph_native_recipient_")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(
    shQuote(file.path(normalizePath("."), "tests", "fixtures", "graph_native_matrix_recipient_process.R")),
    shQuote(system.file(package = "scworkbench")), shQuote(relocated), shQuote(next_id), shQuote(descriptor)),
    stdout = recipient_log, stderr = recipient_log)
  cat(paste(readLines(recipient_log, warn = FALSE), collapse = "\n"), "\n")
  stopifnot(status == 0L)
  cat("GRAPH_NATIVE_PUBLIC_G2 normalized=TRUE unpromoted_pre_stage_rejected=TRUE no_residue=TRUE",
    " promoted_matrix=TRUE direct_binding=TRUE selected_mappings_cells=2 features=1",
    " complete_source_cells=3 features=2 promotion_faults=3 execution_faults=6 source_tamper_rejected=TRUE",
    " graph_read_run=TRUE graph_promote=TRUE recipient=PASS\n")
  TRUE
}
