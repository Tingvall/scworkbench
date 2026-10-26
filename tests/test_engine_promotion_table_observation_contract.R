.engine_promotion_table_fixture <- function(code) {
  root <- tempfile("promotion_table_observation_"); dir.create(root)
  b <- NULL; stage <- NULL; undos <- list(); ns <- asNamespace("scworkbench")
  previous <- options(scworkbench.promotion_transaction_test_hook = NULL)
  on.exit(tryCatch({
    for (undo in rev(undos)) {
      unlockBinding(undo$name, ns); assign(undo$name, undo$value, ns); lockBinding(undo$name, ns)
    }
    options(previous)
    if (!is.null(stage)) try(wb_close_bundle(stage), silent = TRUE)
    if (!is.null(b)) try(wb_close_bundle(b), silent = TRUE)
  }, finally = unlink(root, recursive = TRUE)), add = TRUE)
  b <- wb_init_bundle(file.path(root, "destination"))
  stage <- wb_init_bundle(file.path(root, "stage"))
  dir.create(file.path(b$dir, "provenance", ".pending"), recursive = TRUE, showWarnings = FALSE)
  prims <- list(
    feature = wb_prim_feature_table(data.frame(feature_id = c("f2", "f1"),
      score = c(-0, sin(1)), selected = c(TRUE, FALSE)), meta = list(label = "plain")),
    observation = wb_prim_obs_table(data.frame(label = c("NA", "é"),
      value = c(NA_real_, 1e-200)), entity_kind = "generic", meta = list(n = 2L)))
  # Historical preimage oracles below deliberately exercise legacy primitives.
  prims <- lapply(prims, function(p) { p$table_storage <- NULL; p })
  runs <- lapply(prims, function(p) wb_new_run("metadata_cell_vector",
    outputs = list(vector = p), notes = "Synthetic table storage; no method execution."))
  names(runs) <- vapply(runs, `[[`, "", "run_id")
  expected <- lapply(prims, function(p) scworkbench:::.wb_prov_payload_identity(stage, p))
  ledger <- setNames(lapply(expected, function(value) list(vector = value)), names(runs))
  attr(stage, "durable_payload_identities") <- ledger
  x <- list(b = b, stage = stage, prims = prims, runs = runs, expected = expected,
    session = list(durable = list(payload_identities = ledger), runs = runs, staging_bundle = stage))
  x$replace <- function(name, factory) {
    value <- get(name, ns); undos[[length(undos) + 1L]] <<- list(name = name, value = value)
    unlockBinding(name, ns); assign(name, factory(value), ns); lockBinding(name, ns)
  }
  x$promote <- function() wb_promote_analysis(b, runs,
    head_run_id = names(runs), outputs = "vector", staging_bundle = stage)
  x$state <- function() list(registry = scworkbench:::.wb_manifest_registry_snapshot(b$con),
    paths = sort(list.files(b$dir, recursive = TRUE, all.files = TRUE,
      no.. = TRUE, include.dirs = TRUE)))
  code(x)
  TRUE
}

# Literal pre-optimization recurrence and scalar-list row encoding. Independent
# of the optimized table fold and its vector row-hash implementation.
.engine_promotion_table_old_content <- function(p) {
  header <- list(identity_version = "scworkbench.payload.table.stream.v1",
    kind = as.character(p$kind), table_type = as.character(p$table_type)[1],
    entity_kind = if (identical(p$kind, "obs_table")) as.character(p$entity_kind)[1] else NULL,
    meta = jsonlite::fromJSON(as.character(jsonlite::toJSON(
      scworkbench:::.wb_json_sanitize(p$meta), auto_unbox = TRUE,
      null = "null")), simplifyVector = TRUE))
  state <- scworkbench:::.wb_prov_sha256_object(header)
  for (i in seq_len(nrow(p$table))) {
    text <- as.character(jsonlite::toJSON(scworkbench:::.wb_json_sanitize(
      as.list(p$table[i, , drop = FALSE])), auto_unbox = TRUE, null = "null"))
    state <- scworkbench:::.wb_prov_sha256_object(list(previous = state,
      row_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE)))
  }
  state
}

.engine_promotion_table_old_stored <- function(con, id) {
  h <- DBI::dbGetQuery(con, paste0("SELECT a.type,t.table_type,t.entity_kind,t.meta_json ",
    "FROM artifacts a JOIN artifact_tables t ON t.artifact_id=a.artifact_id WHERE a.artifact_id=?"), params = list(id))
  stopifnot(nrow(h) == 1L)
  state <- scworkbench:::.wb_prov_sha256_object(list(
    identity_version = "scworkbench.payload.table.stream.v1", kind = h$type[[1]],
    table_type = h$table_type[[1]],
    entity_kind = if (h$type[[1]] == "obs_table") h$entity_kind[[1]] else NULL,
    meta = jsonlite::fromJSON(h$meta_json[[1]], simplifyVector = TRUE)))
  rows <- DBI::dbGetQuery(con,
    "SELECT row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx", params = list(id))
  for (text in rows$row_json) state <- scworkbench:::.wb_prov_sha256_object(list(
    previous = state, row_sha256 = digest::digest(text, algo = "sha256", serialize = FALSE)))
  state
}

# Literal old INPUT -> scalar-row JSON -> old parser/NULL normalization/base
# dataframe assembly. No candidate getter, stored rows, or bulk-DF na policy.
.engine_promotion_table_old_projection <- function(table) {
  if (!nrow(table)) return(data.frame(stringsAsFactors = FALSE))
  row_json <- vapply(seq_len(nrow(table)), function(i) as.character(
    jsonlite::toJSON(scworkbench:::.wb_json_sanitize(as.list(table[i, , drop = FALSE])),
      auto_unbox = TRUE, null = "null")), character(1))
  rr <- lapply(row_json, jsonlite::fromJSON, simplifyVector = FALSE)
  rr <- lapply(rr, function(x) {
    if (is.list(x) && length(x)) {
      is_null <- vapply(x, is.null, logical(1))
      if (any(is_null)) for (nm in names(x)[is_null]) x[[nm]] <- NA
    }
    x
  })
  rr <- lapply(rr, as.data.frame, stringsAsFactors = FALSE)
  out <- do.call(rbind, rr)
  rownames(out) <- NULL
  out
}

test_engine_promotion_table_default_and_actual_observation_contract <- function() {
  .engine_promotion_table_fixture(function(x) {
    calls <- 0L
    x$replace(".wb_prov_table_content_sha256", function(original) function(prim) {
      calls <<- calls + 1L; original(prim)
    })
    result <- withVisible(scworkbench:::.wb_session_validate_payloads(x$session))
    stopifnot(identical(result$value, TRUE), !result$visible, calls == 2L)
    observed <- scworkbench:::.wb_session_validate_payloads(x$session, .collect_tables = TRUE)
    stopifnot(calls == 4L, length(observed) == 2L)
    for (i in seq_along(x$runs)) {
      p <- x$runs[[i]]$outputs$vector
      entry <- observed[[names(x$runs)[i]]]$vector
      stopifnot(identical(entry$identity, x$expected[[i]]),
        identical(entry$identity$content_sha256, .engine_promotion_table_old_content(p)),
        identical(scworkbench:::.wb_promotion_table_observed_identity(entry, p), x$expected[[i]]))
    }
    bad <- x$session
    bad$durable$payload_identities[[1]]$vector$content_sha256 <- paste(rep("0", 64), collapse = "")
    failure <- try(scworkbench:::.wb_session_validate_payloads(bad, .collect_tables = TRUE), silent = TRUE)
    stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failure))
    # Outer runs/outputs need not themselves be ordinary primitives. Preserve
    # the original single extraction and its DURABLE error wrapper in BOTH modes.
    ns <- .GlobalEnv
    methods <- c("$.promotion_table_run", "[[.promotion_table_outputs")
    existed <- vapply(methods, exists, logical(1), envir = ns, inherits = FALSE)
    previous <- lapply(seq_along(methods), function(i) if (existed[i]) get(methods[i], ns) else NULL)
    on.exit(for (i in seq_along(methods)) {
      if (existed[i]) assign(methods[i], previous[[i]], ns) else rm(list = methods[i], envir = ns)
    }, add = TRUE)
    run_reads <- 0L; output_reads <- 0L; extraction_error <- FALSE
    assign(methods[1], function(x, name) {
      if (name == "outputs") run_reads <<- run_reads + 1L
      unclass(x)[[name]]
    }, ns)
    assign(methods[2], function(x, ...) {
      output_reads <<- output_reads + 1L
      if (extraction_error) stop("custom output extraction fault")
      unclass(x)[[...]]
    }, ns)
    custom <- x$session
    for (i in seq_along(custom$runs)) {
      class(custom$runs[[i]]$outputs) <- "promotion_table_outputs"
      class(custom$runs[[i]]) <- c("promotion_table_run", class(custom$runs[[i]]))
    }
    for (collect in c(FALSE, TRUE)) {
      run_reads <- 0L; output_reads <- 0L
      scworkbench:::.wb_session_validate_payloads(custom, .collect_tables = collect)
      stopifnot(run_reads == 2L, output_reads == 2L)
      extraction_error <- TRUE; run_reads <- 0L; output_reads <- 0L
      failed <- try(scworkbench:::.wb_session_validate_payloads(custom, .collect_tables = collect), silent = TRUE)
      stopifnot(inherits(failed, "try-error"), grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failed),
        !grepl("custom output extraction fault", failed), run_reads == 1L, output_reads == 1L)
      extraction_error <- FALSE
    }
  })
}

test_engine_promotion_table_strict_mutation_fallback_contract <- function() {
  .engine_promotion_table_fixture(function(x) {
    p <- x$prims$feature
    entry <- list(primitive = p, identity = x$expected$feature)
    variants <- list(p, p, p, p, p, p, p, p)
    variants[[1]]$table$score[1] <- 0 # Signed-zero comparison is intentionally strict.
    variants[[2]]$table$score[2] <- 5
    variants[[3]]$meta$label <- "changed"
    variants[[4]]$table <- variants[[4]]$table[2:1, , drop = FALSE]
    variants[[5]]$table <- variants[[5]]$table[c("score", "feature_id", "selected")]
    variants[[6]]$table_type <- "other"
    attr(variants[[7]]$table, "extra") <- TRUE
    attributes(variants[[8]]$table) <- rev(attributes(variants[[8]]$table))
    for (changed in variants) {
      stopifnot(is.null(scworkbench:::.wb_promotion_table_observed_identity(entry, changed)))
      actual <- scworkbench:::.wb_prov_payload_identity(x$stage, changed)
      stopifnot(identical(actual$content_sha256, .engine_promotion_table_old_content(changed)))
    }
    observed <- scworkbench:::.wb_session_validate_payloads(x$session, .collect_tables = TRUE)
    calls <- 0L
    # Exercise the consumer seam with changed current output, not a modified
    # persisted claim. All original snapshot work still runs on that value.
    x$replace(".wb_prov_write_snapshot", function(original) function(...) {
      args <- list(...)
      args$runs[[1]]$outputs$vector$table$score[2] <- 7
      do.call(original, args)
    })
    x$replace(".wb_prov_table_content_sha256", function(original) function(prim) {
      calls <<- calls + 1L; original(prim)
    })
    x$promote()
    stopifnot(calls == 3L) # Both actual validators plus only changed snapshot output.
  })
}

test_engine_promotion_table_unsupported_and_bounded_metadata_contract <- function() {
  .engine_promotion_table_fixture(function(x) {
    p <- x$prims$feature
    stopifnot(scworkbench:::.wb_promotion_table_observable(p))
    variants <- replicate(9L, p, simplify = FALSE)
    variants[[1]]$table$score <- structure(c(1, 2), class = "promotion_opaque")
    variants[[2]]$meta$ref <- new.env(parent = emptyenv())
    variants[[3]]$table$score <- list(1, 2)
    variants[[4]]$table$deferred <- seq_len(2L)
    class(variants[[5]]$table) <- c("promotion_opaque", "data.frame")
    attr(variants[[6]], "extra") <- TRUE
    variants[[7]]$meta <- as.list(rep("x", 257L))
    deep <- "x"; for (i in 1:10) deep <- list(deep)
    variants[[8]]$meta <- deep
    variants[[9]]$meta$long <- paste(rep("x", 257L), collapse = "")
    calls <- 0L; ns <- .GlobalEnv
    name <- "length.promotion_opaque"; existed <- exists(name, ns, inherits = FALSE)
    previous <- if (existed) get(name, ns) else NULL
    on.exit(if (existed) assign(name, previous, ns) else rm(list = name, envir = ns), add = TRUE)
    assign(name, function(x) { calls <<- calls + 1L; stop("opaque dispatch") }, ns)
    stopifnot(inherits(try(length(structure(1, class = "promotion_opaque")), silent = TRUE), "try-error"), calls == 1L)
    calls <- 0L
    for (v in variants) stopifnot(!scworkbench:::.wb_promotion_table_observable(v))
    stopifnot(calls == 0L)
    bad <- x$session
    bad$runs[[1]]$outputs$vector <- variants[[6]]
    bad$durable$payload_identities[[1]]$vector <- scworkbench:::.wb_prov_payload_identity(x$stage, variants[[6]])
    observed <- scworkbench:::.wb_session_validate_payloads(bad, .collect_tables = TRUE)
    stopifnot(is.null(observed[[names(bad$runs)[1]]]), length(observed) == 1L)
    # Cheap copied-validator probe for finite map capacity: only the expensive
    # actual hash is substituted, with a fixed genuine core identity result.
    validator <- scworkbench:::.wb_session_validate_payloads
    local <- new.env(parent = environment(validator)); calls <- 0L
    local$.wb_prov_payload_identity <- function(...) {calls <<- calls + 1L; x$expected$feature}
    environment(validator) <- local
    many <- x$session
    many$runs <- setNames(rep(list(x$runs[[1]]), 65L), paste0("run", 1:65))
    many$durable$payload_identities <- setNames(rep(list(list(vector = x$expected$feature)), 65L), names(many$runs))
    observed <- validator(many, .collect_tables = TRUE)
    stopifnot(calls == 65L, length(observed) <= 64L, length(observed) > 0L)
    large_identity <- x$expected$feature
    large_identity$verification_status <- paste(rep("x", 70000L), collapse = "")
    local$.wb_prov_payload_identity <- function(...) {calls <<- calls + 1L; large_identity}
    calls <- 0L
    observed <- validator(many, .collect_tables = TRUE)
    stopifnot(calls == 65L, length(observed) == 0L)
  })
}

test_engine_promotion_table_durable_session_rollback_retry_contract <- function() {
  root <- tempfile("promotion_table_durable_"); dir.create(root)
  b <- NULL; s <- NULL; oldlib <- .libPaths()
  oldhook <- options(scworkbench.promotion_transaction_test_hook = NULL)
  on.exit(tryCatch({
    options(oldhook)
    if (!is.null(s)) try(wb_session_discard(s), silent = TRUE)
    if (!is.null(b)) try(wb_close_bundle(b), silent = TRUE)
    try(wb_operation_pack_unload("scwbv2reference"), silent = TRUE)
    if ("scwbV2Reference" %in% loadedNamespaces()) try(unloadNamespace("scwbV2Reference"), silent = TRUE)
    .libPaths(oldlib)
  }, finally = unlink(root, recursive = TRUE)), add = TRUE)
  lib <- file.path(root, "lib"); dir.create(lib)
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(normalizePath(
      "tests/fixtures/operation-pack-v2-reference"))), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, oldlib))
  wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
    package = "scwbV2Reference", lib.loc = lib), lib.loc = lib)
  b <- wb_init_bundle(file.path(root, "bundle"))
  dir.create(file.path(b$dir, "provenance", ".pending"), recursive = TRUE, showWarnings = FALSE)
  wb_define_cells(b, c("c2", "c1"), metadata = data.frame(cell_id = c("c2", "c1"), group = c("x", "y")))
  s <- wb_session_create(b, file.path(root, "sessions"), "table_once")
  first <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(
    source_column = "group", vector_name = "group", value_type = "categorical",
    missing_policy = "error", cell_set = "all", min_cells = 1L)); s <- first$session
  # This case checks the literal v1 table oracle, like the legacy primitives
  # in .engine_promotion_table_fixture. Freeze only the synthetic pair's
  # constructor at that boundary; ordinary typed table tests keep the default.
  legacy_pair <- function() {
    ns <- asNamespace("scworkbench")
    constructor <- get("wb_prim_obs_table", ns)
    on.exit({
      unlockBinding("wb_prim_obs_table", ns)
      assign("wb_prim_obs_table", constructor, ns)
      lockBinding("wb_prim_obs_table", ns)
    }, add = TRUE)
    unlockBinding("wb_prim_obs_table", ns)
    assign("wb_prim_obs_table", function(...) {
      primitive <- constructor(...)
      primitive$table_storage <- NULL
      primitive
    }, ns)
    lockBinding("wb_prim_obs_table", ns)
    wb_session_run_op(s, b, "scwbv2reference::two_table_terminal", inputs = list(
      a = wb_ref_run(first$run$run_id, "vector"), b = wb_ref_run(first$run$run_id, "vector"),
      cell_set = "all", min_cells = 1L))
  }
  paired <- legacy_pair(); s <- paired$session
  checkpoint <- scworkbench:::.wb_session_checkpoint_file(s)
  checkpoint_sha <- digest::digest(file = checkpoint, algo = "sha256")
  before <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  paths <- sort(list.files(b$dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
    if (event == "after_first_private_terminal_write") stop("durable table rollback fault")
  })
  failed <- try(wb_session_promote_current(b, s, outputs = c("summary", "detail")), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), grepl("durable table rollback fault", failed),
    identical(before, scworkbench:::.wb_manifest_registry_snapshot(b$con)),
    identical(paths, sort(list.files(b$dir, recursive = TRUE, all.files = TRUE, no.. = TRUE))),
    identical(checkpoint_sha, digest::digest(file = checkpoint, algo = "sha256")))
  options(scworkbench.promotion_transaction_test_hook = NULL)
  promoted <- wb_session_promote_current(b, s, outputs = c("summary", "detail")); s <- promoted$session
  rows <- promoted$promoted
  head_rows <- rows[rows$run_id == paired$run$run_id, , drop = FALSE]
  ancestors <- rows[rows$run_id != paired$run$run_id, , drop = FALSE]
  # The source metadata-vector run remains a provenance ancestor, not a
  # requested public terminal. The existing promoter reports it as skipped.
  stopifnot(nrow(head_rows) == 2L, !anyDuplicated(head_rows$output),
    setequal(head_rows$output, c("summary", "detail")), all(head_rows$status == "ok"),
    all(!is.na(head_rows$artifact_id) & nzchar(head_rows$artifact_id)),
    !anyDuplicated(head_rows$artifact_id), !any(rows$status == "error"),
    nrow(ancestors) == 1L, identical(ancestors$run_id, first$run$run_id),
    identical(ancestors$status, "skipped"), identical(ancestors$output, ""),
    all(is.na(ancestors$artifact_id)))
  edges <- DBI::dbGetQuery(b$con,
    "SELECT parent_run_id FROM prov_run_edges WHERE parent_run_id=? AND child_run_id=?",
    params = list(first$run$run_id, paired$run$run_id))
  stopifnot(nrow(edges) >= 1L)
  for (name in c("summary", "detail")) {
    id <- head_rows$artifact_id[head_rows$output == name]
    binding <- DBI::dbGetQuery(b$con, paste0(
      "SELECT artifact_id,materialization_class,content_sha256 FROM prov_run_outputs ",
      "WHERE run_id=? AND output_name=?"), params = list(paired$run$run_id, name))
    stopifnot(nrow(binding) == 1L, identical(binding$artifact_id, id),
      identical(binding$materialization_class, "public_artifact"),
      identical(binding$content_sha256, .engine_promotion_table_old_content(paired$run$outputs[[name]])))
    expected <- .engine_promotion_table_old_projection(paired$run$outputs[[name]]$table)
    stopifnot(length(id) == 1L, identical(wb_art_load(b, id)$table, expected))
  }
  TRUE
}

test_engine_promotion_table_public_counts_rollback_and_retry_contract <- function() {
  .engine_promotion_table_fixture(function(x) {
    in_memory <- 0L; stored <- 0L
    x$replace(".wb_prov_table_content_sha256", function(original) function(prim) {
      in_memory <<- in_memory + 1L; original(prim)
    })
    x$replace(".wb_prov_stored_table_content_sha256", function(original) function(...) {
      stored <<- stored + 1L; original(...)
    })
    before <- x$state()
    options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
      if (event == "after_first_private_terminal_write") stop("table rollback fault")
    })
    failure <- try(x$promote(), silent = TRUE)
    stopifnot(inherits(failure, "try-error"), grepl("table rollback fault", failure),
      identical(x$state(), before))
    options(scworkbench.promotion_transaction_test_hook = NULL)
    in_memory <- 0L; stored <- 0L
    promoted <- x$promote()
    stopifnot(in_memory == 2L, all(promoted$promoted$status == "ok"))
    observed <- DBI::dbGetQuery(x$b$con,
      "SELECT run_id,content_sha256,content_identity_scheme FROM prov_run_outputs ORDER BY run_id;")
    for (i in seq_along(x$runs)) {
      row <- observed[observed$run_id == names(x$runs)[i], , drop = FALSE]
      stopifnot(nrow(row) == 1L, identical(row$content_sha256, x$expected[[i]]$content_sha256),
        identical(row$content_identity_scheme, x$expected[[i]]$content_identity_scheme))
      id <- promoted$promoted$artifact_id[promoted$promoted$run_id == names(x$runs)[i]]
      projection <- .engine_promotion_table_old_projection(x$prims[[i]]$table)
      stopifnot(identical(wb_art_load(x$b, id)$table, projection))
      if (i == 1L) stopifnot(identical(projection$feature_id, c("f2", "f1")),
        identical(projection$selected, c(TRUE, FALSE)), typeof(projection$score) == "double")
      if (i == 2L) stopifnot(identical(projection$label, c("NA", "é")),
        identical(projection$value[[1L]], "NA"), typeof(projection$value) == "character",
        identical(projection$value[[2L]], as.character(x$prims[[i]]$table$value[[2L]])))
      actual <- scworkbench:::.wb_prov_stored_table_content_sha256(x$b$con, id)
      stopifnot(identical(actual, .engine_promotion_table_old_stored(x$b$con, id)))
      DBI::dbBegin(x$b$con)
      tryCatch({
        DBI::dbExecute(x$b$con,
          "UPDATE artifact_table_rows SET row_json='{}' WHERE artifact_id=? AND row_idx=(SELECT MIN(row_idx) FROM artifact_table_rows WHERE artifact_id=?)",
          params = list(id, id))
        stopifnot(!identical(actual, scworkbench:::.wb_prov_stored_table_content_sha256(x$b$con, id)))
      }, finally = DBI::dbRollback(x$b$con))
      stopifnot(identical(actual, scworkbench:::.wb_prov_stored_table_content_sha256(x$b$con, id)))
    }
    stopifnot(stored >= 2L)
    nullable <- .engine_promotion_table_old_projection(data.frame(
      logical_value = c(TRUE, NA), character_value = c(NA_character_, "x")))
    stopifnot(identical(nullable$logical_value, c(TRUE, NA)),
      identical(nullable$character_value, c(NA_character_, "x")))
  })
}
