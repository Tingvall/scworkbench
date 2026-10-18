.engine_recipient_file_fixture <- function(n = 2L) {
  root <- tempfile("recipient_file_observation_"); b <- wb_init_bundle(root)
  closed <- FALSE
  on.exit(if (!closed) wb_close_bundle(b), add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1")
  wb_define_cells(b, cells)
  wb_add_space(b, "fixture.source", matrix(seq_len(9L), 3L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))), source = "contract fixture")
  tree <- file.path(root, "models", "fixture_tree")
  dir.create(tree, recursive = TRUE)
  for (i in seq_len(n)) writeBin(as.raw(c(i %% 256L, 0L, 255L, 13L, 10L)),
    file.path(tree, sprintf("file_%03d.bin", i)))
  prim <- wb_prim_model_ref("fixture.source", "fixture.source", engine = "contract")
  prim$model_path <- tree
  # Controlled advanced run construction exercises storage, not scientific
  # execution. Use an actual declared model terminal rather than inventing a
  # model output on metadata_cell_vector (whose terminal is vector).
  stopifnot("model" %in% names(wb_op_interface("slingshot_adopt")$produces))
  run <- wb_new_run("slingshot_adopt", outputs = list(model = prim),
    inputs = list(user_inputs = list(fit_space = wb_prim_space("fixture.source"))),
    notes = paste("Synthetic model-file storage fixture using the declared model terminal;",
      "no Slingshot adoption, fitting or method execution."))
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "model")
  id <- promoted$promoted$artifact_id[[1L]]
  relative <- DBI::dbGetQuery(b$con, "SELECT model_path FROM artifact_model_ref WHERE artifact_id=?",
    params = list(id))$model_path[[1L]]
  target <- file.path(root, relative)
  files <- sort(list.files(target, recursive = TRUE, full.names = TRUE))
  stopifnot(length(files) == n, wb_finalize_recipient_bundle(b)$ready)
  db <- DBI::dbGetQuery(b$con, "PRAGMA database_list")$file[[1L]]
  wb_close_bundle(b); closed <- TRUE
  list(root = root, tree = target, files = files, id = id, db = db)
}

.engine_recipient_file_spy <- function() {
  ns <- asNamespace("scworkbench"); original <- get(".wb_prov_sha256_file", ns)
  state <- new.env(parent = emptyenv()); state$paths <- character(); state$sha256 <- character()
  spy <- function(path) {
    sha <- original(path)
    state$paths <- c(state$paths, normalizePath(path, winslash = "/", mustWork = TRUE))
    state$sha256 <- c(state$sha256, sha)
    sha
  }
  unlockBinding(".wb_prov_sha256_file", ns); assign(".wb_prov_sha256_file", spy, ns)
  lockBinding(".wb_prov_sha256_file", ns)
  list(state = state, close = function() {
    unlockBinding(".wb_prov_sha256_file", ns); assign(".wb_prov_sha256_file", original, ns)
    lockBinding(".wb_prov_sha256_file", ns)
  })
}

.engine_recipient_file_fingerprint <- function(root) {
  files <- sort(as.character(fs::dir_ls(root, recurse = TRUE, type = "file", all = TRUE, follow = FALSE)))
  files <- files[vapply(files, function(path) isTRUE(scworkbench:::.wb_path_status(root,
    substring(path, nchar(root) + 2L), must_exist = TRUE)$ok), logical(1))]
  info <- file.info(files)
  digest::digest(jsonlite::serializeJSON(list(paths = substring(files, nchar(root) + 2L),
    size = as.numeric(info$size), mode = as.character(info$mode),
    sha256 = vapply(files, function(path) digest::digest(file = path, algo = "sha256"),
      character(1))), digits = NA), algo = "sha256", serialize = FALSE)
}

test_engine_recipient_file_initial_and_final_full_hash_contract <- function() {
  f <- .engine_recipient_file_fixture()
  expected <- .engine_recipient_file_fingerprint(f$root)
  spy <- .engine_recipient_file_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  saw <- FALSE
  inspect <- function(event) {
    for (frame in sys.frames()) if (exists("file_observations", frame, inherits = FALSE)) {
      observations <- get("file_observations", frame, inherits = FALSE)
      stopifnot(as.numeric(object.size(observations)) <= 65536)
      if (length(observations)) {
        saw <<- TRUE
        stopifnot(all(vapply(observations, function(entry)
          identical(names(entry), c("sha256", "bytes")) &&
          grepl("^[0-9a-f]{64}$", entry$sha256), logical(1))))
      }
    }
  }
  report <- wb_bundle_validation_report(f$root, level = "recipient", progress = inspect)
  stopifnot(isTRUE(report$ok), saw, identical(report$pre_validation_fingerprint, expected),
    identical(report$post_validation_fingerprint, expected))
  for (path in f$files) stopifnot(sum(spy$state$paths == path) == 2L)
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(report$ok)
  for (path in f$files) stopifnot(sum(spy$state$paths == path) == 4L)
  spy$state$paths <- character(); spy$state$sha256 <- character()
  report <- wb_bundle_validation_report(f$root, level = "content")
  stopifnot(report$ok)
  for (path in f$files) stopifnot(sum(spy$state$paths == path) >= 3L)
  TRUE
}

test_engine_recipient_file_independent_claim_and_mutation_contract <- function() {
  f <- .engine_recipient_file_fixture()
  con <- DBI::dbConnect(RSQLite::SQLite(), f$db)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  expected <- DBI::dbGetQuery(con, "SELECT content_sha256 FROM prov_run_outputs WHERE artifact_id=?",
    params = list(f$id))$content_sha256[[1L]]
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET content_sha256=? WHERE artifact_id=?",
    params = list(strrep("a", 64L), f$id))
  DBI::dbDisconnect(con)
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(!report$ok, "ARTIFACT_CONTENT_IDENTITY_MISMATCH" %in% report$diagnostics$code)
  con <- DBI::dbConnect(RSQLite::SQLite(), f$db)
  DBI::dbExecute(con, "UPDATE prov_run_outputs SET content_sha256=? WHERE artifact_id=?",
    params = list(expected, f$id))
  DBI::dbDisconnect(con)
  original <- readBin(f$files[[1L]], "raw", n = 100L)
  changed <- FALSE
  mutate <- function(event) {
    if (!changed && event$event == "complete" &&
        event$check_class == "recipient_fingerprint_before") {
      changed <<- TRUE
      writeBin(as.raw(c(99L, 0L, 255L, 13L, 10L)), f$files[[1L]])
    }
  }
  spy <- .engine_recipient_file_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  report <- wb_bundle_validation_report(f$root, level = "recipient", progress = mutate)
  at <- which(spy$state$paths == f$files[[1L]])
  stopifnot(changed, !report$ok, "VALIDATION_MUTATED_BUNDLE" %in% report$diagnostics$code,
    length(at) == 2L, !identical(spy$state$sha256[[at[[1L]]]], spy$state$sha256[[at[[2L]]]]))
  writeBin(original, f$files[[1L]])
  stopifnot(wb_bundle_validation_report(f$root, level = "recipient")$ok)
  TRUE
}

test_engine_recipient_file_tree_inventory_remains_fresh_contract <- function() {
  for (mode in c("add", "remove")) {
    f <- .engine_recipient_file_fixture(); changed <- FALSE
    extra <- file.path(f$tree, "new_file.bin")
    mutate <- function(event) {
      if (!changed && event$event == "complete" &&
          event$check_class == "recipient_fingerprint_before") {
        changed <<- TRUE
        if (mode == "add") writeBin(as.raw(c(1L, 255L)), extra) else unlink(f$files[[1L]])
      }
    }
    report <- wb_bundle_validation_report(f$root, level = "recipient", progress = mutate)
    stopifnot(changed, !report$ok,
      all(c("ARTIFACT_CONTENT_IDENTITY_MISMATCH", "VALIDATION_MUTATED_BUNDLE") %in%
        report$diagnostics$code))
  }
  TRUE
}

test_engine_recipient_file_ledger_cap_and_miss_fallback_contract <- function() {
  f <- .engine_recipient_file_fixture(220L)
  spy <- .engine_recipient_file_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  saw <- FALSE
  inspect <- function(event) {
    for (frame in sys.frames()) if (exists("file_observations", frame, inherits = FALSE)) {
      observations <- get("file_observations", frame, inherits = FALSE)
      stopifnot(as.numeric(object.size(observations)) <= 65536)
      if (length(observations)) saw <<- TRUE
    }
  }
  report <- wb_bundle_validation_report(f$root, level = "recipient", progress = inspect)
  counts <- vapply(f$files, function(path) sum(spy$state$paths == path), integer(1))
  stopifnot(report$ok, saw, all(counts >= 2L), any(counts > 2L), any(counts == 2L))
  TRUE
}

test_engine_recipient_file_private_plumbing_and_escape_contract <- function() {
  f <- .engine_recipient_file_fixture()
  calls <- character()
  observe <- function(path) {
    calls <<- c(calls, path)
    scworkbench:::.wb_prov_sha256_file(path)
  }
  plain <- scworkbench:::.wb_prov_path_identity(f$tree)
  hooked <- scworkbench:::.wb_prov_path_identity(f$tree, .file_sha256 = observe)
  stopifnot(identical(plain, hooked), identical(sort(calls), sort(f$files)))
  outside <- tempfile("recipient_outside_"); writeBin(as.raw(c(17L, 23L)), outside)
  on.exit(unlink(outside), add = TRUE)
  changed <- FALSE
  mutate <- function(event) {
    if (!changed && event$event == "complete" &&
        event$check_class == "recipient_fingerprint_before") {
      changed <<- TRUE
      stopifnot(file.symlink(outside, file.path(f$tree, "unsafe_link")))
    }
  }
  spy <- .engine_recipient_file_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  report <- wb_bundle_validation_report(f$root, level = "recipient", progress = mutate)
  stopifnot(changed, !report$ok,
    any(grepl("PATH_SYMLINK_ESCAPE|PAYLOAD", report$diagnostics$code)),
    !normalizePath(outside, winslash = "/", mustWork = TRUE) %in% spy$state$paths)
  TRUE
}
