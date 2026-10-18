.publication_fixture <- function() {
  root <- tempfile("scwb_publication_contract_")
  b <- wb_init_bundle(root)
  cells <- c("c3", "c1", "c2")
  wb_define_cells(b, cells)
  values <- stats::setNames(c(3, 1, 2), cells)
  primitives <- list(
    vector = wb_prim_cell_vector(values, "continuous", meta = list(label = "synthetic")),
    family = wb_prim_cell_vector_family(rep(c("B", "A"), each = 3L),
      rep(cells, 2L), rep(unname(values), 2L), value_type = "continuous"))
  runs <- lapply(primitives, function(p) wb_new_run("metadata_cell_vector",
    inputs = list(cell_set = "all", parents = character()), params = list(),
    outputs = list(vector = p), notes = "Synthetic storage conformance; no scientific method executed."))
  ids <- vapply(runs, `[[`, "", "run_id"); names(runs) <- ids
  list(root = root, bundle = b, runs = runs, ids = ids)
}

.publication_cleanup <- function(fixture) {
  try(wb_close_bundle(fixture$bundle), silent = TRUE)
  unlink(fixture$root, recursive = TRUE, force = TRUE)
}

test_engine_promotion_single_publication_and_schema_admission_contract <- function() {
  x <- .publication_fixture(); on.exit(.publication_cleanup(x), add = TRUE)
  published <- 0L; migrations <- 0L
  before <- options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "published") published <<- published + 1L
  }, scworkbench.promotion_schema_counter = function() migrations <<- migrations + 1L)
  on.exit(options(before), add = TRUE)
  ns <- asNamespace("scworkbench")
  trace(".wb_schema_migrate_connection", where = ns, print = FALSE,
    tracer = quote({f <- getOption("scworkbench.promotion_schema_counter"); if (is.function(f)) f()}))
  on.exit(untrace(".wb_schema_migrate_connection", where = ns), add = TRUE)
  result <- wb_promote_analysis(x$bundle, x$runs, head_run_id = x$ids,
    fail_fast = TRUE)
  stopifnot(nrow(result$promoted) == 2L, published == 1L, migrations == 1L,
    is.null(x$bundle$con@ref$wb_promotion_schema_admitted))
  # Explicit public migration is still a full admission, not a cached promise.
  wb_migrate_artifacts(x$bundle)
  stopifnot(migrations == 2L, published == 2L)
  for (id in result$promoted$artifact_id) stopifnot(!is.null(wb_art_load(x$bundle, id)))
  TRUE
}

test_engine_promotion_schema_changes_rollback_contract <- function() {
  for (attack in c("ledger", "temp_shadow")) {
    x <- .publication_fixture()
    before <- options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
      if (event != "after_first_private_terminal_write") return(invisible(NULL))
      if (attack == "ledger") DBI::dbExecute(x$bundle$con,
        "UPDATE bundle_schema_migrations SET migration_id='invalid' WHERE version=1;")
      else DBI::dbExecute(x$bundle$con,
        "CREATE TEMP TABLE artifact_pseudotime(artifact_id TEXT,cell_id TEXT,pseudotime REAL);")
    })
    outcome <- tryCatch(wb_promote_analysis(x$bundle, x$runs,
      head_run_id = x$ids, fail_fast = TRUE), error = identity)
    options(before)
    stopifnot(inherits(outcome, "error"),
      is.null(x$bundle$con@ref$wb_promotion_schema_admitted),
      DBI::dbGetQuery(x$bundle$con, "SELECT COUNT(*) n FROM artifacts;")$n == 0L,
      DBI::dbGetQuery(x$bundle$con, "SELECT COUNT(*) n FROM prov_commits;")$n == 0L,
      DBI::dbGetQuery(x$bundle$con,
        "SELECT COUNT(*) n FROM sqlite_temp_schema WHERE name='artifact_pseudotime';")$n == 0L,
      identical(scworkbench:::.wb_schema_status(x$bundle$con)$status, "current"))
    retry <- wb_promote_analysis(x$bundle, x$runs, head_run_id = x$ids,
      fail_fast = TRUE)
    stopifnot(nrow(retry$promoted) == 2L)
    .publication_cleanup(x)
  }
  TRUE
}

test_engine_promotion_manifest_failure_propagates_contract <- function() {
  x <- .publication_fixture(); on.exit(.publication_cleanup(x), add = TRUE)
  path <- file.path(x$root, "manifest.json")
  before_bytes <- readBin(path, "raw", file.info(path)$size)
  old <- options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "before_publish") stop("publication fault", call. = FALSE)
  })
  outcome <- tryCatch(wb_promote_analysis(x$bundle, x$runs,
    head_run_id = x$ids, fail_fast = TRUE), error = identity)
  options(old)
  stopifnot(inherits(outcome, "error"), grepl("publication fault", conditionMessage(outcome)),
    identical(before_bytes, readBin(path, "raw", file.info(path)$size)),
    is.null(x$bundle$con@ref$wb_promotion_schema_admitted))
  # Existing commit/publication boundary: SQL already committed, but no success
  # escapes. Explicit guarded manifest retry must reconstruct that actual state.
  wb_refresh_manifest(x$bundle)
  manifest <- jsonlite::read_json(path)
  stopifnot(DBI::dbGetQuery(x$bundle$con, "SELECT COUNT(*) n FROM artifacts;")$n == 2L,
    !identical(before_bytes, readBin(path, "raw", file.info(path)$size)),
    identical(manifest$current_state$fingerprint,
      scworkbench:::.wb_manifest_registry_snapshot(x$bundle$con)$fingerprint))
  TRUE
}

test_engine_ordered_character_key_equality_contract <- function() {
  equal <- scworkbench:::.wb_object_row_keys_identical
  old <- function(a, b) identical(scworkbench:::.wb_object_row_key_tokens(a),
    scworkbench:::.wb_object_row_key_tokens(b))
  cases <- list(data.frame(cell_id = c("c2", "c1", NA, "é\n\\\"")),
    data.frame(key = c("B", "A", "B"), cell_id = c("c2", "c1", "c2")),
    data.frame(cell_id = factor(c("c1", "c2"), levels = c("c2", "c1"))),
    data.frame(point = c(1L, 2L)), data.frame(cell_id = character()))
  for (a in cases) for (b in cases) stopifnot(identical(equal(a, b), old(a, b)))
  a <- cases[[2L]]
  for (b in list(a, a[3:1, ], a[-1L, ], transform(a, key = c("A", "A", "B"))))
    stopifnot(identical(equal(a, b), old(a, b)))
  different_rownames <- a; rownames(different_rownames) <- c("r3", "r1", "r2")
  stopifnot(equal(a, different_rownames), old(a, different_rownames))
  # This optimization never changes identity-bearing row tokens.
  stopifnot(identical(scworkbench:::.wb_object_row_key_tokens(a),
    vapply(seq_len(nrow(a)), function(i)
      jsonlite::serializeJSON(as.list(a[i, , drop = FALSE]), digits = NA), "")))
  TRUE
}

test_engine_target_reproduction_single_publication_contract <- function() {
  root <- tempfile("scwb_target_publication_")
  parent <- tempfile("scwb_target_publication_clone_")
  dir.create(parent)
  b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE)
    unlink(c(root, parent), recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- c("c3", "c1", "c2")
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells,
    group = c("A", "B", "A")))
  wb_close_bundle(b)
  stopifnot(file.copy(root, parent, recursive = TRUE))
  clone <- file.path(parent, basename(root))
  b <- wb_open_bundle(root)
  result <- wb_session_run_op(wb_session_new(), b, "metadata_cell_vector",
    inputs = list(source_column = "group", vector_name = "group",
      value_type = "categorical", missing_policy = "error",
      cell_set = "all", min_cells = 1L, overwrite = FALSE))
  promoted <- wb_session_promote_current(b, result$session, outputs = "vector")
  plan <- wb_target_reproduction_plan(b,
    paste0("artifact:", promoted$promoted$artifact_id[[1L]]))
  sealed <- FALSE; published <- 0L
  old <- options(scworkbench.target_reproduction_atomicity_test_hook =
    function(event, ...) {
      if (event == "before_first_receipt_insertion") sealed <<- TRUE
    }, scworkbench.manifest_test_hook = function(event, final, ...) {
      if (sealed && event == "published" &&
          identical(normalizePath(dirname(final)), normalizePath(clone)))
        published <<- published + 1L
    })
  on.exit(options(old), add = TRUE)
  replay <- wb_target_execute_plan(plan, clone)
  stopifnot(identical(replay$status, "promoted_and_verified"), sealed,
    published == 1L, nrow(replay$verification) == 1L)
  TRUE
}
