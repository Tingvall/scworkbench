test_graph_no_axis_public_lifecycle_contract <- function() {
  root <- tempfile("graph_only_public_"); dir.create(root)
  lib <- file.path(root, "library"); dir.create(lib)
  old <- .libPaths(); bundle <- NULL; session <- NULL
  on.exit({
    if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    try(wb_operation_pack_unload("graphonlyfixture"), silent = TRUE)
    if ("scwbGraphOnlyFixture" %in% loadedNamespaces()) try(unloadNamespace("scwbGraphOnlyFixture"), silent = TRUE)
    .libPaths(old); unlink(root, recursive = TRUE)
  }, add = TRUE)
  pack <- wb_operation_pack_scaffold(file.path(root, "pack"), "scwbGraphOnlyFixture",
    "graphonlyfixture", "Graph Fixture Author", "fixture@example.org", template = "graph")
  manifest <- jsonlite::read_json(pack$manifest, simplifyVector = FALSE)
  operation <- manifest$operations[[1L]]
  operation$name <- operation$title <- "emit_graph"
  operation$qualified_name <- "graphonlyfixture::emit_graph"
  operation$runner <- ".emit_graph"; operation$inputs <- list()
  operation$outputs[[1L]]$binding_policy <- "forbidden"
  manifest$operations <- list(operation)
  jsonlite::write_json(manifest, pack$manifest, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  stopifnot(file.copy("tests/fixtures/graph_only_pack_register.R",
    file.path(pack$path, "R", "register.R"), overwrite = TRUE))
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(pack$path)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, old)); wb_operation_pack_load("scwbGraphOnlyFixture")
  bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  stopifnot(length(wb_cells(bundle, "all")) == 0L, nrow(wb_matrices(bundle)) == 0L)
  result <- wb_session_run_op(wb_session_new(), bundle, "graphonlyfixture::emit_graph", inputs = list())
  session <- result$session
  promoted <- wb_session_promote_current(bundle, session, outputs = "result")
  id <- as.character(promoted$promoted$artifact_id[[1L]])
  info <- wb_art_graph_info(bundle, id)
  stopifnot(info$component_counts$nodes == "3", info$component_counts$bindings == "0",
    length(wb_cells(bundle, "all")) == 0L, nrow(wb_matrices(bundle)) == 0L,
    wb_finalize_recipient_bundle(bundle)$ready)
  wb_session_discard(session); session <- NULL
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- file.path(root, "relocated.bundle")
  stopifnot(file.rename(file.path(root, "source.bundle"), relocated))
  child <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote("tests/fixtures/graph_only_recipient_process.R"), shQuote(system.file(package = "scworkbench")),
    shQuote(relocated), shQuote(id), shQuote(info$content_identity$sha256),
    shQuote(info$descriptor_identity$sha256)), stdout = TRUE, stderr = TRUE)
  cat(paste(child, collapse = "\n"), "\n")
  stopifnot(is.null(attr(child, "status")), any(grepl("GRAPH_ONLY_RECIPIENT cells=0 matrices=0", child, fixed = TRUE)))
  TRUE
}
