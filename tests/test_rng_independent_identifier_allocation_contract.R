.identifier_rng_state <- function() {
  if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    serialize(get(".Random.seed", envir = .GlobalEnv, inherits = FALSE), NULL)
  } else NULL
}

.identifier_expect_error <- function(expr, code) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "scworkbench_identifier_error"),
            identical(as.character(error$code), code))
  invisible(error)
}

test_rng_independent_identifier_allocation_contract <- function() {
  classes <- list(
    run = function() .wb_allocate_identifier("run_", 12L, purpose = "run"),
    session = function() .wb_allocate_identifier("session_", 12L, purpose = "session"),
    snapshot = function() .wb_prov_new_snapshot_id(),
    commit = function() .wb_promotion_commit_id(),
    artifact = function() .wb_new_artifact_id("artifact"),
    fragment = function() .wb_new_fragment_id("RNA"),
    event = function() .wb_allocate_identifier("registry_event_", 12L, purpose = "registry event"),
    replay = function() .wb_allocate_identifier("replayeq_", 8L, purpose = "replay result"),
    payload = function() .wb_allocate_identifier("space_", 24L, purpose = "payload"),
    lock = .wb_writer_lock_token,
    savepoint = function() .wb_allocate_identifier("scwb_fragment_", 12L, purpose = "savepoint"),
    temporary = function() .wb_allocate_identifier("__wb_stage_", 12L, purpose = "temporary table"),
    workspace = function() .wb_allocate_identifier(".scworkbench-publication-", 12L, purpose = "workspace"),
    pending = function() .wb_allocate_identifier(".manifest.json.staging-", 16L, purpose = "pending publication")
  )

  if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    rm(".Random.seed", envir = .GlobalEnv)
  }
  absent_values <- vapply(classes, function(fn) fn(), character(1))
  stopifnot(!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE),
            !anyDuplicated(absent_values))

  set.seed(314159L)
  before <- .identifier_rng_state()
  present_values <- vapply(classes, function(fn) fn(), character(1))
  after <- .identifier_rng_state()
  stopifnot(identical(before, after), !anyDuplicated(present_values))

  # A forced first collision retries without touching scientific RNG.
  calls <- 0L
  hook <- function(n, purpose) {
    calls <<- calls + 1L
    if (calls <= 2L) "aaaaaaaaaaaa" else "bbbbbbbbbbbb"
  }
  old <- getOption("scworkbench.identifier_entropy_test_hook")
  on.exit(options(scworkbench.identifier_entropy_test_hook = old), add = TRUE)
  options(scworkbench.identifier_entropy_test_hook = hook)
  first <- .wb_allocate_identifier("collision_", 12L, purpose = "collision retry")
  second <- .wb_allocate_identifier("collision_", 12L, purpose = "collision retry")
  stopifnot(!identical(first, second), calls >= 3L)

  options(scworkbench.identifier_entropy_test_hook = function(n, purpose) "cccccccccccc")
  .wb_allocate_identifier("exhaust_", 12L, purpose = "collision exhaustion")
  .identifier_expect_error(
    .wb_allocate_identifier("exhaust_", 12L, purpose = "collision exhaustion", max_attempts = 3L),
    "SCWORKBENCH_IDENTIFIER_COLLISION_EXHAUSTED"
  )
  options(scworkbench.identifier_entropy_test_hook = function(n, purpose) stop("injected entropy failure"))
  .identifier_expect_error(
    .wb_allocate_identifier("entropy_", 12L, purpose = "entropy failure"),
    "SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE"
  )
  TRUE
}

test_rng_independent_run_collision_rollback_contract <- function() {
  root <- tempfile("scwb_identifier_collision_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", 1:12)
  wb_ingest_apply(
    b, set_name = "core", cell_ids = cells,
    matrices = list(RNA = matrix(seq_len(60), nrow = 5,
      dimnames = list(paste0("g", 1:5), cells))), source = "identifier-test"
  )
  s <- wb_session_new()
  old_hook <- getOption("scworkbench.identifier_entropy_test_hook")
  on.exit(options(scworkbench.identifier_entropy_test_hook = old_hook), add = TRUE)

  # A conflicting preallocated run is rejected by the in-memory boundary.
  fixed <- wb_new_run("manual", run_id = "run_preallocated")
  s <- wb_session_add_run(s, fixed)
  conflict <- wb_new_run("different", run_id = "run_preallocated")
  .identifier_expect_error(
    wb_session_add_run(s, conflict), "SCWORKBENCH_IDENTIFIER_CONFLICT"
  )

  before_files <- sort(list.files(root, recursive = TRUE, all.files = TRUE))
  options(scworkbench.identifier_entropy_test_hook = function(n, purpose) "dddddddddddd")
  .wb_allocate_identifier("run_", 12L, purpose = "occupy candidate")
  error <- .identifier_expect_error(
    wb_session_run_op(
      wb_session_new(), b, "hvg_select",
      inputs = list(matrix = "RNA", n_features = 3L, min_cells = 2L)
    ),
    "SCWORKBENCH_IDENTIFIER_COLLISION_EXHAUSTED"
  )
  stopifnot(identical(before_files, sort(list.files(root, recursive = TRUE, all.files = TRUE))),
            nrow(DBI::dbGetQuery(b$con, "SELECT * FROM prov_runs WHERE run_id = 'run_dddddddddddd';")) == 0L)
  TRUE
}

test_rng_independent_scientific_chain_contract <- function() {
  required <- c("BPCells", "irlba", "uwot")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE))) {
    return(contract_test_skip("BPCells, irlba, and uwot are required."))
  }
  root <- tempfile("scwb_identifier_science_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  set.seed(7L)
  cells <- paste0("c", 1:40); features <- paste0("g", 1:30)
  counts <- matrix(stats::rpois(1200, 4), nrow = 30,
                   dimnames = list(features, cells))
  wb_ingest_apply(b, "core", cells, matrices = list(RNA = counts), source = "pbmc3k-pattern")

  run_branch <- function(label, n_features) {
    s <- wb_session_new()
    set.seed(1L)
    hvg <- wb_session_run_op(s, b, "hvg_select", inputs = list(
      matrix = "RNA", n_features = n_features, method = "vst", seed = 1L,
      min_cells = 10L)); s <- hvg$session
    set.seed(1L)
    pca <- wb_session_run_op(s, b, "pca_fit", inputs = list(
      matrix = "RNA", features = wb_ref_run(hvg$run$run_id, "selected_features"),
      n_components = 5L, space_id_out = paste0("pca_", label), seed = 1L,
      min_cells = 10L)); s <- pca$session
    set.seed(1L)
    umap <- wb_session_run_op(s, b, "umap_fit", inputs = list(
      space = paste0("pca_", label), space_id_out = paste0("umap_", label),
      dims = 1:5, n_neighbors = 5L, nn_method = "annoy", seed = 1L,
      min_cells = 10L)); s <- umap$session
    promoted <- wb_session_promote_current(
      b, s, outputs = c("selected_features", "space_2d"),
      name_prefix = label, created_by = "identifier-test"
    )
    snapshot <- as.character(promoted$provenance_snapshot_id)[1]
    commit <- DBI::dbGetQuery(
      b$con, "SELECT commit_id FROM prov_heads WHERE snapshot_id = ?;",
      params = list(snapshot)
    )$commit_id[[1L]]
    payload <- DBI::dbGetQuery(
      b$con, "SELECT path FROM space_payloads WHERE space_id IN (?, ?) ORDER BY space_id;",
      params = list(paste0("pca_", label), paste0("umap_", label))
    )$path
    list(run_ids = c(hvg$run$run_id, pca$run$run_id, umap$run$run_id),
         hvg = hvg$run$outputs$selected_features,
         pca = pca$run$outputs$space,
         umap = umap$run$outputs$space_2d,
         artifact_ids = {
           ids <- as.character(promoted$promoted$artifact_id)
           ids[!is.na(ids) & nzchar(ids)]
         },
         snapshot_id = snapshot, commit_id = as.character(commit),
         payload_paths = as.character(payload), promoted = promoted)
  }
  branch2000 <- run_branch("hvg2000", 20L)
  branch1000 <- run_branch("hvg1000", 10L)
  set.seed(1L)
  event1 <- .wb_allocate_identifier("registry_event_", 12L, purpose = "registry event")
  fragment1 <- .wb_new_fragment_id("RNA", b$con)
  set.seed(1L)
  event2 <- .wb_allocate_identifier("registry_event_", 12L, purpose = "registry event")
  fragment2 <- .wb_new_fragment_id("RNA", b$con)
  stopifnot(!anyDuplicated(c(branch2000$run_ids, branch1000$run_ids)),
            !length(intersect(unique(branch2000$artifact_ids), unique(branch1000$artifact_ids))),
            !anyDuplicated(c(branch2000$snapshot_id, branch1000$snapshot_id)),
            !anyDuplicated(c(branch2000$commit_id, branch1000$commit_id)),
            !anyDuplicated(c(branch2000$payload_paths, branch1000$payload_paths)),
            !identical(event1, event2), !identical(fragment1, fragment2),
            all(c("pca_hvg2000", "umap_hvg2000", "pca_hvg1000", "umap_hvg1000") %in% wb_spaces(b)$space_id),
            sum(branch2000$promoted$promoted$status == "ok") == 2L,
            sum(branch1000$promoted$promoted$status == "ok") == 2L)
  # Same scientific parameters and seed reproduce numerical results while
  # administrative IDs remain distinct.
  set.seed(1L)
  repeat_hvg <- wb_session_run_op(wb_session_new(), b, "hvg_select", inputs = list(
    matrix = "RNA", n_features = 20L, method = "vst", seed = 1L,
    min_cells = 10L))
  stopifnot(identical(branch2000$hvg$feature_id,
                      repeat_hvg$run$outputs$selected_features$feature_id),
            !repeat_hvg$run$run_id %in% c(branch2000$run_ids, branch1000$run_ids),
            all(vapply(c(branch2000$run_ids, branch1000$run_ids), nzchar, logical(1))))
  TRUE
}

test_rng_independent_process_replacement_concurrency_contract <- function() {
  root <- tempfile("scwb_identifier_process_")
  workspace_root <- tempfile("scwb_identifier_workspaces_")
  dir.create(workspace_root, recursive = TRUE)
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(c(root, workspace_root), recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", 1:20); features <- paste0("g", 1:10)
  wb_ingest_apply(
    b, "core", cells,
    matrices = list(RNA = matrix(seq_len(200), nrow = 10,
      dimnames = list(features, cells))), source = "process-replacement"
  )

  s <- wb_session_create(b, workspace_root)
  set.seed(1L)
  first <- wb_session_run_op(s, b, "hvg_select", inputs = list(
    matrix = "RNA", n_features = 5L, seed = 1L, min_cells = 2L))
  workspace <- first$session$durable$workspace
  first_id <- first$run$run_id
  wb_close_bundle(first$session$staging_bundle)
  wb_close_bundle(b)

  script <- tempfile("scwb_identifier_child_", fileext = ".R")
  r_string <- function(x) encodeString(as.character(x)[1], quote = "\"")
  writeLines(c(
    sprintf("devtools::load_all(%s, quiet=TRUE)", r_string(normalizePath(".", winslash = "/"))),
    sprintf("b <- wb_open_bundle(%s)", r_string(root)),
    sprintf("s <- wb_session_resume(b, %s)", r_string(workspace)),
    "set.seed(1L)",
    "rr <- wb_session_run_op(s, b, 'hvg_select', inputs=list(matrix='RNA', n_features=4L, seed=1L, min_cells=2L))",
    "wb_close_bundle(rr$session$staging_bundle)",
    "wb_close_bundle(b)"
  ), script)
  on.exit(unlink(script, force = TRUE), add = TRUE)
  child <- system2(file.path(R.home("bin"), "Rscript"), script, stdout = TRUE, stderr = TRUE)
  status <- attr(child, "status") %||% 0L
  if (!identical(status, 0L)) stop("process-replacement child failed:\n", paste(child, collapse = "\n"))
  b <- wb_open_bundle(root)
  resumed <- wb_session_resume(b, workspace)
  stopifnot(length(resumed$runs) == 2L, first_id %in% names(resumed$runs),
            !anyDuplicated(names(resumed$runs)))
  wb_close_bundle(resumed$staging_bundle)
  wb_close_bundle(b)

  # Independent processes allocate durable session/workspace/ownership tokens
  # while coordinating against the same source bundle.
  workers <- parallel::mclapply(seq_len(4L), function(i) {
    child_bundle <- wb_open_bundle(root)
    on.exit(wb_close_bundle(child_bundle), add = TRUE)
    child_session <- wb_session_create(child_bundle, workspace_root)
    id <- child_session$session_id
    wb_close_bundle(child_session$staging_bundle)
    id
  }, mc.cores = 4L)
  ids <- unlist(workers, use.names = FALSE)
  b <- wb_open_bundle(root)
  integrity <- DBI::dbGetQuery(b$con, "PRAGMA integrity_check;")[[1L]]
  stopifnot(length(ids) == 4L, !anyDuplicated(ids),
            all(dir.exists(file.path(workspace_root, ids))),
            identical(as.character(integrity), "ok"),
            "RNA" %in% wb_matrices(b)$matrix_id)
  TRUE
}

test_rng_independent_ownership_token_collision_contract <- function() {
  old <- getOption("scworkbench.identifier_entropy_test_hook")
  on.exit(options(scworkbench.identifier_entropy_test_hook = old), add = TRUE)
  options(scworkbench.identifier_entropy_test_hook = function(n, purpose) "eeeeeeeeeeeeeeeeeeeeeeee")
  allocators <- list(
    lock = function() .wb_allocate_identifier("lock_", 24L, purpose = "writer lock", max_attempts = 2L),
    savepoint = function() .wb_allocate_identifier("savepoint_", 12L, purpose = "savepoint", max_attempts = 2L),
    temporary = function() .wb_allocate_identifier("temporary_", 12L, purpose = "temporary table", max_attempts = 2L),
    workspace = function() .wb_allocate_identifier("workspace_", 12L, purpose = "workspace", max_attempts = 2L),
    pending = function() .wb_allocate_identifier("pending_", 12L, purpose = "pending publication", max_attempts = 2L)
  )
  tokens <- lapply(allocators, function(fn) fn())
  for (name in names(allocators)) {
    .identifier_expect_error(
      allocators[[name]](),
      "SCWORKBENCH_IDENTIFIER_COLLISION_EXHAUSTED"
    )
  }
  stopifnot(!anyDuplicated(unlist(tokens, use.names = FALSE)))
  TRUE
}

test_administrative_rng_static_allowlist_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  files <- sort(list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE))
  allowed <- c(
    "op_addmodulescore.R", "op_hvg_pca.R", "op_trajectory_smooth.R",
    "op_umap_fit.R", "ops.R", "ops_geometry.R"
  )
  pattern <- paste0("\\b(sample|sample", "[.]int|set", "[.]seed)\\s*\\(")
  offenders <- character()
  for (path in files) {
    lines <- readLines(path, warn = FALSE)
    hits <- grep(pattern, lines, perl = TRUE)
    if (length(hits) && !basename(path) %in% allowed) {
      offenders <- c(offenders, paste0(basename(path), ":", hits))
    }
  }
  if (length(offenders)) stop("unreviewed administrative RNG calls: ", paste(offenders, collapse = ", "))
  TRUE
}
