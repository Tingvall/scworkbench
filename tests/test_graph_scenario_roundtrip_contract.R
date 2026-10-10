test_graph_normative_scenario_public_lifecycle_contract <- function() {
  stopifnot(requireNamespace("igraph", quietly = TRUE))
  corpus_file <- system.file("protocol/fixtures/graph-v1/scenario-roundtrip-vectors.json",
    package = "scworkbench")
  corpus <- jsonlite::read_json(corpus_file, simplifyVector = FALSE)
  stopifnot(length(corpus$cases) == 23L,
    corpus$accepted_design_commit == "fa929601c7b8c67c2947b400341bfd90bd80d925",
    digest::digest(file = corpus_file, algo = "sha256", serialize = FALSE) ==
      "90d6cbc098acee167ede37bfc658e31b7b2cf9681bd840554fe6ed6b0762bb38")
  root <- tempfile("graph_scenarios_"); dir.create(root)
  lib <- file.path(root, "library"); dir.create(lib)
  old <- .libPaths(); bundle <- NULL; session <- NULL
  on.exit({
    if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    try(wb_operation_pack_unload("graphscenariofixture"), silent = TRUE)
    if ("scwbGraphScenarioFixture" %in% loadedNamespaces())
      try(unloadNamespace("scwbGraphScenarioFixture"), silent = TRUE)
    .libPaths(old); unlink(root, recursive = TRUE)
  }, add = TRUE)
  pack <- wb_operation_pack_scaffold(file.path(root, "pack"), "scwbGraphScenarioFixture",
    "graphscenariofixture", "Graph Fixture Author", "fixture@example.org", template = "graph")
  manifest <- jsonlite::read_json(pack$manifest, simplifyVector = FALSE)
  op <- manifest$operations[[1L]]
  op$name <- op$title <- "emit_scenario"; op$qualified_name <- "graphscenariofixture::emit_scenario"
  op$runner <- ".emit_scenario"
  op$params_schema$properties <- list(case = list(type = "string",
    enum = as.list(vapply(corpus$cases, `[[`, character(1), "id"))))
  op$params_schema$required <- list("case")
  manifest$operations <- list(op)
  jsonlite::write_json(manifest, pack$manifest, auto_unbox = TRUE, pretty = TRUE,
    null = "null", digits = NA)
  stopifnot(file.copy("tests/fixtures/graph_scenario_pack_register.R",
    file.path(pack$path, "R", "register.R"), overwrite = TRUE),
    file.copy(corpus_file, file.path(pack$path, "inst", "scenarios.json")))
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(pack$path)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, old))
  wb_operation_pack_load("scwbGraphScenarioFixture")
  bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  wb_define_cells(bundle, "fixture_cell")
  wb_attach_matrix(bundle, "fixture", Matrix::Matrix(matrix(1L, 1L, 1L,
    dimnames = list("fixture_feature", "fixture_cell")), sparse = TRUE))
  records <- list()
  json <- scworkbench:::.wb_operation_pack_canonical_json
  for (case in corpus$cases) {
    content <- case$content; attrs <- content$attributes
    graph <- wb_prim_graph(content$nodes, content$edges, content$incidences,
      attrs$graph, attrs$node, attrs$edge, attrs$incidence,
      direction_mode = content$direction_mode)
    identity <- wb_graph_identity(graph)
    for (field in c("content_identity", "binding_identity", "descriptor_identity"))
      stopifnot(identical(json(identity[[field]]), json(case$expected[[field]])))
    if (isTRUE(case$expected$igraph_eligible)) {
      restored <- wb_graph_from_igraph(wb_graph_to_igraph(graph))
      stopifnot(identical(json(restored$content), json(content)),
        identical(wb_graph_identity(restored), identity))
    } else {
      error <- tryCatch(wb_graph_to_igraph(graph), error = base::identity)
      stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_ADAPTER_UNSUPPORTED")
    }
    result <- wb_session_run_op(wb_session_new(), bundle,
      "graphscenariofixture::emit_scenario", inputs = list(matrix = "fixture",
        cell_set = "all", min_cells = 1L, case = case$id))
    session <- result$session
    promoted <- wb_session_promote_current(bundle, session, outputs = "result")
    artifact <- as.character(promoted$promoted$artifact_id[[1L]])
    info <- wb_art_graph_info(bundle, artifact)
    for (field in c("content_identity", "binding_identity", "descriptor_identity"))
      stopifnot(identical(json(info[[field]]), json(case$expected[[field]])))
    stopifnot(info$canonical_bytes == case$expected$canonical_content_bytes)
    rows <- lapply(names(info$component_counts), function(component)
      wb_art_graph_slice(bundle, artifact, component))
    names(rows) <- names(info$component_counts)
    restored <- scworkbench:::.wb_graph_records_to_primitive(content$direction_mode, rows)
    stopifnot(identical(json(restored$content), json(content)))
    for (component in names(case$expected$component_counts))
      stopifnot(info$component_counts[[component]] == case$expected$component_counts[[component]])
    records[[case$id]] <- list(artifact_id = artifact, expected = case$expected, rows = rows)
    wb_session_discard(session); session <- NULL
    cat("GRAPH_SCENARIO ", case$id, " independent_R_roots=PASS public_writer_promote=PASS components=PASS igraph=",
      if (case$expected$igraph_eligible) "lossless" else "explicit_rejection", "\n", sep = "")
  }
  stopifnot(wb_finalize_recipient_bundle(bundle)$ready)
  wb_close_bundle(bundle); bundle <- NULL
  relocated <- file.path(root, "relocated.bundle")
  stopifnot(file.rename(file.path(root, "source.bundle"), relocated))
  record_file <- file.path(root, "records.rds"); saveRDS(records, record_file)
  child <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote("tests/fixtures/graph_scenario_recipient_process.R"), shQuote(normalizePath(".")),
    shQuote(relocated), shQuote(record_file)), stdout = TRUE, stderr = TRUE)
  cat(paste(child, collapse = "\n"), "\n")
  stopifnot(is.null(attr(child, "status")),
    any(grepl("GRAPH_SCENARIOS_RECIPIENT cases=23", child, fixed = TRUE)))
  TRUE
}
