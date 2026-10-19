args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
mode <- args[[1L]]; root <- args[[2L]]; library <- args[[3L]]; expected_dll <- args[[4L]]
.libPaths(c(file.path(root, "packs"), library, .libPaths()))
suppressPackageStartupMessages(library(scworkbench, lib.loc = library))
stopifnot(identical(normalizePath(find.package("scworkbench")), normalizePath(file.path(library, "scworkbench"))),
  identical(digest::digest(file = getLoadedDLLs()[["scworkbench"]][["path"]], algo = "sha256"), expected_dll),
  as.numeric(getOption("scworkbench.max_dense_materialize_mb", 256)) == 256)
cat("ACTUAL_GRAPH_RECOVERY_CHILD", mode, expected_dll, "\n")
if (mode != "loader") {
  wb_operation_pack_load("scwbGraphFixture", lib.loc = file.path(root, "packs"))
} else {
  stopifnot(nrow(wb_operation_packs()) == 0L)
}
literal <- paste0('{"attributes":{"edge":[],"graph":[],"incidence":[],"node":[]},',
  '"direction_mode":"undirected","edges":[],"incidences":[],"nodes":[{"node_id":"c2"},{"node_id":"c1"}],',
  '"schema":"scworkbench.graph.content.v1"}')
expected <- list(scheme = "scworkbench.graph.content.canonical-json.v1",
  sha256 = digest::digest(charToRaw(literal), algo = "sha256", serialize = FALSE))
checkpoint_files <- function(workspace) {
  pointer <- file.path(workspace, "CURRENT.json")
  generation <- jsonlite::read_json(pointer, simplifyVector = FALSE)$generation
  c(pointer, file.path(workspace, "checkpoints", generation, c("session.json", "session.rds")))
}
checkpoint_hashes <- function(workspace) {
  files <- checkpoint_files(workspace)
  stats::setNames(vapply(files, function(path) digest::digest(file = path, algo = "sha256"), ""), files)
}
tree <- function(path) {
  paths <- sort(c(path, as.character(fs::dir_ls(path, recurse = TRUE, all = TRUE))))
  links <- Sys.readlink(paths)
  type <- ifelse(nzchar(links), "symlink", ifelse(dir.exists(paths), "directory", "file"))
  info <- file.info(paths)
  data.frame(path = substring(paths, nchar(path) + 1L), type = type,
    bytes = unname(info$size), mode = as.character(info$mode), link = links,
    sha256 = vapply(seq_along(paths), function(i) if (type[[i]] == "file")
      digest::digest(file = paths[[i]], algo = "sha256") else if (type[[i]] == "symlink")
        digest::digest(charToRaw(links[[i]]), algo = "sha256", serialize = FALSE) else NA_character_, ""))
}
literal_graph_identity <- wb_graph_identity(wb_prim_graph(
  list(list(node_id = "c2"), list(node_id = "c1")), list(), list(),
  direction_mode = "undirected"))
stopifnot(identical(literal_graph_identity$content_identity, expected))
assert_unpromoted_read_rejected <- function(session, bundle, run_id) {
  scratch <- function() sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))
  logical_session <- function(s) {
    runs <- lapply(s$runs, function(run) {
      run$outputs <- lapply(run$outputs, function(value) {
        attr(value, "graph_stage") <- NULL
        value
      })
      run
    })
    list(runs = runs, head = s$head_run_id, active = s$active)
  }
  stage <- wb_session_view(session)
  before <- list(checkpoint = checkpoint_hashes(session$durable$workspace),
    session = logical_session(session), scratch = scratch(),
    source_registry = scworkbench:::.wb_manifest_registry_snapshot(bundle$con),
    stage_registry = scworkbench:::.wb_manifest_registry_snapshot(stage$con))
  failure <- tryCatch(wb_session_run_op(session, bundle, "scwbgraphfixture::graph_to_table",
    inputs = list(source = wb_ref_run(run_id, "result"), cell_set = "all", min_cells = 1L)),
    error = identity)
  stopifnot(inherits(failure, "error"), identical(failure$code, "GRAPH_SOURCE_AUTHORITY_REQUIRED"),
    startsWith(conditionMessage(failure), "GRAPH_SOURCE_AUTHORITY_REQUIRED:"),
    identical(before$checkpoint, checkpoint_hashes(session$durable$workspace)),
    identical(before$session, logical_session(session)), identical(before$scratch, scratch()),
    identical(before$source_registry, scworkbench:::.wb_manifest_registry_snapshot(bundle$con)),
    identical(before$stage_registry, scworkbench:::.wb_manifest_registry_snapshot(stage$con)))
  cat("UNCHANGED_UNPROMOTED_GRAPH_READ_REJECTION", conditionMessage(failure), "\n")
}
if (mode %in% c("writer", "writer_two")) {
  b <- wb_init_bundle(file.path(root, "source.bundle"))
  wb_define_cells(b, c("c2", "c1"))
  wb_attach_matrix(b, "RNA", Matrix::Matrix(matrix(c(1, 2, 3, 4), 2L,
    dimnames = list(c("g2", "g1"), c("c2", "c1"))), sparse = TRUE))
  s <- wb_session_create(b, file.path(root, "sessions"), "replacement")
  answer <- wb_session_run_op(s, b, "scwbgraphfixture::matrix_to_graph",
    inputs = list(matrix = "RNA", cell_set = "all", min_cells = 1L))
  assert_unpromoted_read_rejected(answer$session, b, answer$run$run_id)
  if (mode == "writer_two") answer <- wb_session_run_op(answer$session, b,
    "scwbgraphfixture::matrix_to_graph", inputs = list(matrix = "RNA", cell_set = "all", min_cells = 1L))
  stopifnot(identical(answer$run$outputs$result$content_identity, expected))
  stage <- wb_session_view(answer$session)
  jsonlite::write_json(list(source = normalizePath(b$dir), workspace = answer$session$durable$workspace,
    stage = normalizePath(stage$dir), run_id = answer$run$run_id,
    transition_id = answer$run$operation_pack_transition$transition_id),
    file.path(root, "paths.json"), auto_unbox = TRUE)
  wb_close_bundle(stage); wb_close_bundle(b)
} else {
  p <- jsonlite::read_json(file.path(root, "paths.json"), simplifyVector = FALSE)
  if (mode == "loader") {
    stage_before <- tree(p$stage); source_before <- tree(p$source)
    b <- wb_open_bundle(p$stage, read_only = TRUE)
    listed <- wb_operation_pack_transition_outputs(b, p$transition_id)
    stopifnot(identical(listed$name, "result"), identical(listed$category, "terminal_artifact"))
    value <- wb_operation_pack_transition_load(b, p$transition_id, "result")
    stopifnot(identical(value$content_identity, expected))
    wb_close_bundle(b)
    stopifnot(identical(stage_before, tree(p$stage)), identical(source_before, tree(p$source)))
  } else if (mode == "resume") {
    b <- wb_open_bundle(p$source)
    checkpoint_before <- checkpoint_hashes(p$workspace)
    first <- wb_session_resume(b, p$workspace)
    second <- wb_session_resume(b, p$workspace)
    stopifnot(identical(first$durable$checkpoint_generation, second$durable$checkpoint_generation),
      identical(first$runs[[p$run_id]]$outputs$result$content_identity, expected),
      identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    for (mutation in c("run", "head", "active")) {
      bad <- first
      if (mutation == "run") bad$runs[[p$run_id]]$params <- list(forged = TRUE)
      if (mutation == "head") bad$head_run_id <- "forged"
      if (mutation == "active") bad$active <- list(forged = list(kind = "run", run_id = p$run_id))
      failure <- try(wb_session_promote_current(b, bad, outputs = "result"), silent = TRUE)
      stopifnot(inherits(failure, "try-error"), grepl("UNCHECKPOINTED_STATE", as.character(failure), fixed = TRUE))
    }
    assert_unpromoted_read_rejected(first, b, p$run_id)
    promoted <- wb_session_promote_current(b, first,
      outputs = list(wb_ref_run(p$run_id, "result")))
    artifact <- promoted$promoted$artifact_id[promoted$promoted$output == "result"][[1L]]
    info <- wb_art_graph_info(b, artifact)
    stopifnot(identical(info$content_identity, expected),
      identical(info$binding_identity, literal_graph_identity$binding_identity),
      identical(info$descriptor_identity, literal_graph_identity$descriptor_identity),
      identical(vapply(wb_art_graph_slice(b, artifact, "nodes"), `[[`, "", "node_id"), c("c2", "c1")))
    # Reject the stale owner before the new session adds unrelated source runs.
    stale <- try(wb_session_promote_current(b, second, outputs = "result"), silent = TRUE)
    stopifnot(inherits(stale, "try-error"), grepl("STALE_GENERATION", as.character(stale), fixed = TRUE))
    continued <- wb_session_create(b, file.path(root, "sessions"), "retained_graph_continuation")
    generation <- continued$durable$checkpoint_generation
    consumed <- wb_session_run_op(continued, b, "scwbgraphfixture::graph_to_table",
      inputs = list(source = wb_ref_artifact(artifact, "result"), cell_set = "all", min_cells = 1L))
    stopifnot(identical(consumed$run$outputs$summary$table$value, 2L),
      !identical(consumed$session$durable$checkpoint_generation, generation))
    summary_promotion <- wb_session_promote_current(b, consumed$session, outputs = "summary")
    summary_artifact <- summary_promotion$promoted$artifact_id[
      summary_promotion$promoted$output == "summary"][[1L]]
    wb_finalize_recipient_bundle(b); wb_close_bundle(b)
    b <- wb_open_bundle(p$source, read_only = TRUE)
    info <- wb_art_graph_info(b, artifact)
    stopifnot(identical(info$content_identity, expected),
      identical(info$binding_identity, literal_graph_identity$binding_identity),
      identical(info$descriptor_identity, literal_graph_identity$descriptor_identity),
      identical(vapply(wb_art_graph_slice(b, artifact, "nodes"), `[[`, "", "node_id"), c("c2", "c1")),
      identical(wb_art_load(b, summary_artifact)$table$value, 2L))
    wb_close_bundle(b)
  } else if (mode == "multi_failure") {
    b <- wb_open_bundle(p$source)
    checkpoint_before <- checkpoint_hashes(p$workspace)
    parts <- file.path(p$stage, "operation_pack_v2", p$transition_id, "outputs", "result", "graph.parts.ndjson")
    original <- readBin(parts, "raw", n = file.info(parts)$size)
    scratch <- function() sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))
    before <- scratch()
    writeBin(c(original, charToRaw("malformed")), parts)
    failure <- try(wb_session_resume(b, p$workspace), silent = TRUE)
    stopifnot(inherits(failure, "try-error"), identical(before, scratch()), dir.exists(p$workspace),
      identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    writeBin(original, parts)
    restored <- wb_session_resume(b, p$workspace)
    stopifnot(length(restored$runs) == 2L,
      all(vapply(restored$runs, function(run) identical(run$outputs$result$content_identity, expected), logical(1))))
    wb_close_bundle(b)
  } else if (mode == "source_failure") {
    b <- wb_open_bundle(p$source)
    checkpoint_before <- checkpoint_hashes(p$workspace)
    writer <- DBI::dbConnect(RSQLite::SQLite(), file.path(p$source, "db", "app.sqlite"))
    scratch <- function() sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))
    before <- scratch()
    old_cell <- DBI::dbGetQuery(writer, "SELECT cell_id FROM cells ORDER BY rowid LIMIT 1;")$cell_id[[1L]]
    DBI::dbExecute(writer, "UPDATE cells SET cell_id='foreign_recovery_cell' WHERE rowid=(SELECT MIN(rowid) FROM cells);")
    failure <- try(wb_session_resume(b, p$workspace), silent = TRUE)
    stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_SOURCE_CHANGED", as.character(failure), fixed = TRUE),
      identical(before, scratch()), identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    DBI::dbExecute(writer, "UPDATE cells SET cell_id=? WHERE cell_id='foreign_recovery_cell';", params = list(old_cell))
    DBI::dbDisconnect(writer)
    resumed <- wb_session_resume(b, p$workspace)
    stopifnot(identical(resumed$runs[[p$run_id]]$outputs$result$content_identity, expected),
      identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    wb_close_bundle(b)
  } else {
    stopifnot(mode == "attacks")
    b <- wb_open_bundle(p$source)
    pointer_path <- file.path(p$workspace, "current.json")
    # Use actual public checkpoint pointer filename, not an assumed API layout.
    candidates <- list.files(p$workspace, pattern = "\\.json$", full.names = TRUE)
    pointers <- Filter(function(path) {
      x <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = function(e) NULL)
      identical(x$schema, "scworkbench.durable_session.pointer.v2")
    }, candidates)
    stopifnot(length(pointers) == 1L); pointer_path <- pointers[[1L]]
    pointer <- jsonlite::read_json(pointer_path, simplifyVector = FALSE)
    directory <- file.path(p$workspace, "checkpoints", pointer$generation)
    files <- c(pointer_path, file.path(directory, "session.json"), file.path(directory, "session.rds"))
    stopifnot(all(file.info(files)$size <= 8 * 1024^2))
    saved <- lapply(files, function(path) readBin(path, "raw", n = file.info(path)$size))
    checkpoint_before <- checkpoint_hashes(p$workspace)
    restore <- function() for (i in seq_along(files)) writeBin(saved[[i]], files[[i]])
    scratch <- function() sort(list.files(tempdir(), pattern = "^scwb_graph_stage_", full.names = TRUE))
    before <- scratch()
    session <- readRDS(files[[3L]])
    session$runs[[p$run_id]]$outputs$result$content_identity$sha256 <- strrep("0", 64L)
    # Deliberately self-rehash the checkpoint's byte/state/metadata bindings.
    # The retained actual graph/receipt and original payload ledger MUST reject it.
    session$durable$checkpoint_state_sha <- scworkbench:::.wb_session_checkpoint_state_sha(session)
    saveRDS(session, files[[3L]], version = 3)
    meta <- jsonlite::read_json(files[[2L]], simplifyVector = FALSE)
    meta$checkpoint_sha256 <- digest::digest(file = files[[3L]], algo = "sha256")
    meta$checkpoint_state_sha256 <- session$durable$checkpoint_state_sha
    jsonlite::write_json(meta, files[[2L]], auto_unbox = TRUE, null = "null")
    pointer$metadata_sha256 <- digest::digest(file = files[[2L]], algo = "sha256")
    jsonlite::write_json(pointer, files[[1L]], auto_unbox = TRUE, null = "null")
    failure <- try(wb_session_resume(b, p$workspace), silent = TRUE)
    stopifnot(inherits(failure, "try-error"), grepl("PAYLOAD_CORRUPT", as.character(failure), fixed = TRUE), identical(before, scratch()))
    restore()
    stopifnot(identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    parts <- file.path(p$stage, "operation_pack_v2", p$transition_id, "outputs", "result", "graph.parts.ndjson")
    original <- readBin(parts, "raw", n = file.info(parts)$size)
    writeBin(c(original, charToRaw("malformed")), parts)
    failed_load <- try({stage <- wb_open_bundle(p$stage, read_only = TRUE)
      tryCatch(wb_operation_pack_transition_load(stage, p$transition_id, "result"), finally = wb_close_bundle(stage))}, silent = TRUE)
    stopifnot(inherits(failed_load, "try-error"), identical(before, scratch()))
    writeBin(original, parts)
    resumed <- wb_session_resume(b, p$workspace)
    stopifnot(identical(resumed$runs[[p$run_id]]$outputs$result$content_identity, expected),
      identical(checkpoint_before, checkpoint_hashes(p$workspace)))
    wb_close_bundle(b)
  }
}
cat(paste("GRAPH_DURABLE_PROCESS_OK", mode), "\n", sep = "")
