.wb_family_test_bundle <- function(label = "family") {
  root <- tempfile(paste0("scwb_v2_", label, "_"))
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- paste0("cell_", seq_len(6L))
  wb_define_cells(bundle, cells, metadata = data.frame(
    cell_id = cells,
    group = c("b", "a", "b", "a", "c", "c"),
    stringsAsFactors = FALSE
  ), set_name = "core")
  list(root = root, bundle = bundle, cells = cells)
}

.wb_family_test_labels <- function(cells) {
  wb_prim_cell_vector(stats::setNames(
    c("b", "a", "b", "a", "c", "c"), cells),
    value_type = "categorical", meta = list(fixture = "family"))
}

.wb_family_state <- function(bundle) {
  list(
    sets = wb_cell_sets(bundle, include_history = TRUE),
    membership = DBI::dbGetQuery(bundle$con, paste(
      "SELECT cell_set, cell_id, source, description",
      "FROM cell_set_membership ORDER BY cell_set, cell_id;")),
    receipts = wb_operation_pack_registry_receipts(bundle),
    commits = DBI::dbGetQuery(bundle$con,
      "SELECT * FROM prov_commits ORDER BY commit_id;")
  )
}

.wb_family_expect_error <- function(expr, pattern = NULL) {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  invisible(error)
}

test_operation_pack_v2_cell_set_family_identity_fixture_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v2/identities.json",
    simplifyVector = FALSE)$cell_set_family_examples[[1]]
  root <- tempfile("scwb_v2_family_identity_")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  wb_define_cells(bundle,
    as.character(unlist(fixture$cell_order, use.names = FALSE)))
  normalized <- getFromNamespace(
    ".wb_operation_pack_cell_set_family_normalize", "scworkbench")(
      bundle, fixture$input_payload)
  identities <- attributes(normalized)[c(
    "family_identity", "member_identities", "source_identity")]
  for (attribute in names(identities)) attr(normalized, attribute) <- NULL
  canonical <- getFromNamespace(".wb_operation_pack_canonical_json",
    "scworkbench")
  stopifnot(
    identical(canonical(normalized), canonical(fixture$normalized_payload)),
    identical(identities$family_identity, fixture$family_identity),
    identical(identities$member_identities, fixture$member_identities),
    identical(identities$source_identity, fixture$source_identity)
  )
  TRUE
}

test_operation_pack_v2_cell_set_family_normalization_contract <- function() {
  setup <- .wb_family_test_bundle("normalize")
  bundle <- setup$bundle
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  normalize <- getFromNamespace(
    ".wb_operation_pack_cell_set_family_normalize", "scworkbench")
  source <- list(
    label = "fixture", created_by = "contract",
    input_artifact_id = NULL, input_run_id = NULL,
    input_snapshot_id = NULL
  )
  payload <- list(
    kind = "cell_set_family_admission",
    sets = list(
      list(name = "set:z", cells = rev(setup$cells[c(1, 3)]),
        description = "z", selection_rule = "group == 'b'"),
      list(name = "a", cells = rev(setup$cells[c(2, 4)]),
        description = "a", selection_rule = "group == 'a'")
    ), mode = "add", source = source
  )
  normalized <- normalize(bundle, payload)
  permuted <- payload
  permuted$sets <- rev(lapply(payload$sets, function(set) {
    set$cells <- rev(set$cells)
    set
  }))
  normalized_permuted <- normalize(bundle, permuted)
  wrong_order <- normalized
  wrong_order$sets[[1]]$cells <- rev(wrong_order$sets[[1]]$cells)
  for (attribute in c("family_identity", "member_identities",
      "source_identity")) attr(wrong_order, attribute) <- NULL
  changed_value <- normalized
  changed_value$sets[[1]]$description <- "changed scientific request"
  for (attribute in c("family_identity", "member_identities",
      "source_identity")) attr(changed_value, attribute) <- NULL
  identity <- getFromNamespace(".wb_operation_pack_v2_identity_scoped",
    "scworkbench")
  stopifnot(
    identical(vapply(normalized$sets, `[[`, character(1), "name"),
      c("set:a", "set:z")),
    identical(normalized$sets[[1]]$cells, setup$cells[c(2, 4)]),
    identical(normalized$sets[[2]]$cells, setup$cells[c(1, 3)]),
    identical(attr(normalized, "family_identity")$sha256,
      attr(normalized_permuted, "family_identity")$sha256),
    !identical(attr(normalized, "family_identity")$sha256,
      identity("scworkbench.cell_set.family_admission.v1",
        "normalized family payload", wrong_order)$sha256),
    !identical(attr(normalized, "family_identity")$sha256,
      identity("scworkbench.cell_set.family_admission.v1",
        "normalized family payload", changed_value)$sha256),
    identical(normalize(bundle, list(
      kind = "cell_set_family_admission", sets = list(), mode = "add",
      source = source))$sets, list())
  )

  invalid <- list(
    duplicate_name = within(payload, sets[[2]]$name <- "z"),
    duplicate_member = within(payload,
      sets[[1]]$cells <- c(setup$cells[[1]], setup$cells[[1]])),
    invalid_name = within(payload, sets[[1]]$name <- "bad name"),
    foreign_cell = within(payload, sets[[1]]$cells <- "not_a_cell"),
    malformed_mode = within(payload, mode <- "merge"),
    conflicting_provenance = within(payload, {
      source$input_run_id <- "run_x"
      source$input_snapshot_id <- NULL
    })
  )
  for (value in invalid) {
    error <- .wb_family_expect_error(normalize(bundle, value))
    stopifnot(inherits(error, "wb_operation_pack_v2_error"))
  }
  TRUE
}

test_operation_pack_v2_cell_set_family_publication_contract <- function() {
  contract_test_activate_core_conformance_pack()
  setup <- .wb_family_test_bundle("publish")
  bundle <- setup$bundle
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  wb_close_bundle(bundle)
  clone_source <- function(label) {
    parent <- tempfile(paste0("scwb_v2_family_", label, "_"))
    dir.create(parent)
    stopifnot(isTRUE(file.copy(setup$root, parent, recursive = TRUE)))
    list(parent = parent, bundle = file.path(parent, basename(setup$root)))
  }
  clones <- lapply(c("success", "wrong_identity", "missing_pack"),
    clone_source)
  on.exit(unlink(vapply(clones, `[[`, character(1), "parent"),
    recursive = TRUE, force = TRUE), add = TRUE)
  clone <- clones[[1]]$bundle
  bundle <- wb_open_bundle(setup$root)
  before <- .wb_family_state(bundle)
  labels <- wb_session_run_op(
    wb_session_new(), bundle, "metadata_cell_vector",
    inputs = list(
      source_column = "group", vector_name = "family_labels",
      value_type = "categorical", missing_policy = "error",
      overwrite = TRUE, cell_set = "all", min_cells = 1L
    )
  )
  result <- wb_session_run_op(
    labels$session, bundle,
    "scwbv2reference::cell_set_family_contract",
    inputs = list(
      labels = wb_ref_run(labels$run$run_id, "vector"),
      mode = "add", prefix = "family_", source_label = "fixture",
      cell_set = "all", min_cells = 1L
    )
  )
  stopifnot(identical(.wb_family_state(bundle), before))
  promotion <- wb_session_promote_current(
    bundle, result$session, outputs = "manifest", created_by = "contract")
  stopifnot(
    all(paste0("set:family_", c("a", "b", "c")) %in%
      wb_cell_sets(bundle)),
    identical(wb_cells(bundle, "set:family_a"), setup$cells[c(2, 4)]),
    identical(wb_cells(bundle, "set:family_b"), setup$cells[c(1, 3)]),
    nrow(wb_operation_pack_registry_receipts(bundle)) == 1L,
    any(promotion$promoted$output == "manifest")
  )
  receipt <- wb_operation_pack_registry_receipts(bundle)
  stopifnot(receipt$n_sets[[1]] == 3L,
    identical(receipt$mode[[1]], "add"),
    identical(receipt$run_id[[1]], result$run$run_id),
    grepl("^[0-9a-f]{64}$", receipt$family_sha256[[1]]),
    dir.exists(file.path(setup$root, "operation_pack_v2",
      receipt$transition_id[[1]])))
  bindings <- DBI::dbGetQuery(bundle$con, paste(
    "SELECT entity_id, relationship_type FROM prov_run_entity_bindings",
    "WHERE run_id = ? AND direction = 'output' AND entity_kind = 'cell_set'",
    "ORDER BY entity_id;"), params = list(result$run$run_id))
  stopifnot(nrow(bindings) == 3L,
    identical(bindings$entity_id,
      paste0("set:family_", c("a", "b", "c"))),
    all(bindings$relationship_type == "MATERIALIZES"))

  artifact_id <- as.character(promotion$promoted$artifact_id[
    promotion$promoted$output == "manifest"][[1]])
  plan <- wb_target_reproduction_plan(bundle,
    paste0("artifact:", artifact_id))
  stopifnot(nrow(plan$registry_requests) == 1L,
    identical(plan$registry_requests$family_sha256[[1]],
      receipt$family_sha256[[1]]))
  replay <- wb_target_execute_plan(plan, clone)
  stopifnot(identical(replay$status, "promoted_and_verified"))
  replayed <- wb_open_bundle(clone, read_only = TRUE)
  stopifnot(nrow(wb_operation_pack_registry_receipts(replayed)) == 1L,
    identical(wb_cells(replayed, "set:family_a"),
      setup$cells[c(2, 4)]))
  wb_close_bundle(replayed)

  wrong <- plan
  wrong$registry_requests$family_sha256[[1]] <- strrep("0", 64L)
  error <- .wb_family_expect_error(
    wb_target_execute_plan(wrong, clones[[2]]$bundle),
    "Strict replay registry-request identity differs")
  unchanged <- wb_open_bundle(clones[[2]]$bundle, read_only = TRUE)
  stopifnot(nrow(wb_operation_pack_registry_receipts(unchanged)) == 0L,
    !any(startsWith(wb_cell_sets(unchanged), "set:family_")))
  wb_close_bundle(unchanged)

  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  saved_pack <- registry$packs$scwbv2reference
  saved_operations <- registry$operations[saved_pack$operation_names]
  detach_pack <- function() {
    for (name in saved_pack$operation_names) registry$operations[[name]] <- NULL
    registry$packs$scwbv2reference <- NULL
  }
  restore_pack <- function() {
    registry$packs$scwbv2reference <- saved_pack
    for (name in names(saved_operations)) {
      registry$operations[[name]] <- saved_operations[[name]]
    }
  }
  on.exit(restore_pack(), add = TRUE)
  detach_pack()
  .wb_family_expect_error(
    wb_target_execute_plan(plan, clones[[3]]$bundle),
    "plan contains an unavailable operation")
  missing <- wb_open_bundle(clones[[3]]$bundle, read_only = TRUE)
  stopifnot(nrow(wb_operation_pack_registry_receipts(missing)) == 0L)
  wb_close_bundle(missing)
  restore_pack()

  wb_finalize_recipient_bundle(bundle)
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(setup$root, read_only = TRUE)
  detach_pack()
  report <- wb_bundle_validation_report(setup$root, level = "recipient")
  if (!isTRUE(report$ok)) {
    stop(paste(utils::capture.output(print(report$diagnostics)),
      collapse = "\n"), call. = FALSE)
  }
  stopifnot(isTRUE(report$ok),
    nrow(wb_operation_pack_registry_receipts(bundle)) == 1L,
    identical(wb_cells(bundle, "set:family_c"), setup$cells[c(5, 6)]))
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(setup$root)
  restore_pack()
  TRUE
}

test_operation_pack_v2_cell_set_family_atomic_rollback_contract <- function() {
  contract_test_activate_core_conformance_pack()
  faults <- c(
    "between_family_member_writes",
    "after_sqlite_writes_before_commit",
    "before_registry_receipt_finalization",
    "during_payload_publication"
  )
  for (fault in faults) {
    setup <- .wb_family_test_bundle(paste0("fault_", fault))
    bundle <- setup$bundle
    labels <- wb_session_run_op(
      wb_session_new(), bundle, "metadata_cell_vector",
      inputs = list(
        source_column = "group", vector_name = "family_labels",
        value_type = "categorical", missing_policy = "error",
        overwrite = TRUE, cell_set = "all", min_cells = 1L
      )
    )
    result <- wb_session_run_op(
      labels$session, bundle,
      "scwbv2reference::cell_set_family_contract",
      inputs = list(
        labels = wb_ref_run(labels$run$run_id, "vector"),
        mode = "add", prefix = "fault_", source_label = "fault fixture",
        cell_set = "all", min_cells = 1L
      )
    )
    before <- list(
      state = .wb_family_state(bundle),
      identity = getFromNamespace(".wb_session_source_identity",
        "scworkbench")(bundle)$scientific_state_fingerprint,
      artifacts = wb_art_list(bundle, include_history = TRUE)
    )
    fired <- FALSE
    if (identical(fault, "during_payload_publication")) {
      options(scworkbench.promotion_workspace_publish_hook =
        function(workspace, final_rel) {
          if (!fired && startsWith(final_rel, "operation_pack_v2/")) {
            fired <<- TRUE
            stop("injected during transition publication")
          }
        })
    } else {
      options(scworkbench.operation_pack_registry_test_hook =
        local({
          target <- fault
          function(event, ...) {
            details <- list(...)
            between <- identical(target, "between_family_member_writes") &&
              identical(as.integer(details$member_index), 1L)
            if (!fired && identical(event, target) &&
                (!identical(target, "between_family_member_writes") ||
                  between)) {
              fired <<- TRUE
              stop(paste("injected", target))
            }
          }
        }))
    }
    error <- try(wb_session_promote_current(
      bundle, result$session, outputs = "manifest"), silent = TRUE)
    options(scworkbench.operation_pack_registry_test_hook = NULL,
      scworkbench.promotion_workspace_publish_hook = NULL)
    after <- list(
      state = .wb_family_state(bundle),
      identity = getFromNamespace(".wb_session_source_identity",
        "scworkbench")(bundle)$scientific_state_fingerprint,
      artifacts = wb_art_list(bundle, include_history = TRUE)
    )
    transition_root <- file.path(setup$root, "operation_pack_v2")
    published <- if (dir.exists(transition_root)) {
      setdiff(list.dirs(transition_root, recursive = FALSE,
        full.names = FALSE), ".pending")
    } else character()
    stopifnot(inherits(error, "try-error"), fired,
      identical(before, after), !length(published),
      !any(startsWith(wb_cell_sets(bundle), "set:fault_")),
      nrow(wb_operation_pack_registry_receipts(bundle)) == 0L)

    retry <- wb_session_promote_current(
      bundle, result$session, outputs = "manifest")
    stopifnot(any(retry$promoted$output == "manifest"),
      nrow(wb_operation_pack_registry_receipts(bundle)) == 1L,
      all(paste0("set:fault_", c("a", "b", "c")) %in%
        wb_cell_sets(bundle)))
    wb_close_bundle(bundle)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }
  TRUE
}

test_operation_pack_v2_cell_set_family_modes_and_empty_contract <- function() {
  contract_test_activate_core_conformance_pack()
  run_family <- function(bundle, cells, values, mode = "add",
      prefix = "family_") {
    labels <- wb_prim_cell_vector(stats::setNames(values, cells),
      value_type = "categorical")
    wb_session_run_op(
      wb_session_new(), bundle,
      "scwbv2reference::cell_set_family_contract",
      inputs = list(
        labels = labels, mode = mode, prefix = prefix,
        source_label = "mode fixture", cell_set = "all", min_cells = 1L
      )
    )
  }

  for (case in list(
      list(label = "empty", values = rep(NA_character_, 6L), n = 0L),
      list(label = "one", values = rep("x", 6L), n = 1L))) {
    setup <- .wb_family_test_bundle(case$label)
    bundle <- setup$bundle
    result <- run_family(bundle, setup$cells, case$values,
      mode = if (case$label == "one") "replace" else "add",
      prefix = paste0(case$label, "_"))
    promotion <- wb_session_promote_current(
      bundle, result$session, outputs = "manifest")
    receipt <- wb_operation_pack_registry_receipts(bundle)
    stopifnot(any(promotion$promoted$output == "manifest"),
      nrow(receipt) == 1L, receipt$n_sets[[1]] == case$n)
    if (case$n == 0L) {
      stopifnot(!any(startsWith(wb_cell_sets(bundle), "set:empty_")))
    } else {
      stopifnot(identical(wb_cells(bundle, "set:one_x"), setup$cells))
    }
    wb_close_bundle(bundle)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }

  for (mode in c("add", "replace")) {
    setup <- .wb_family_test_bundle(paste0("mode_", mode))
    bundle <- setup$bundle
    wb_cell_set_add(bundle, "set:family_a", setup$cells[[6]],
      source = "preexisting", description = "unbound fixture")
    result <- run_family(bundle, setup$cells,
      c("b", "a", "b", "a", "c", "c"), mode = mode)
    promotion <- wb_session_promote_current(
      bundle, result$session, outputs = "manifest")
    expected <- if (mode == "add") setup$cells[c(2, 4, 6)] else
      setup$cells[c(2, 4)]
    stopifnot(any(promotion$promoted$output == "manifest"),
      identical(wb_cells(bundle, "set:family_a"), expected))
    if (mode == "add") {
      replacement <- run_family(bundle, setup$cells,
        c("b", "a", "b", "a", "c", "c"), mode = "replace")
      failed <- try(wb_session_promote_current(
        bundle, replacement$session, outputs = "manifest"), silent = TRUE)
      stopifnot(inherits(failed, "try-error"),
        identical(wb_cells(bundle, "set:family_a"), expected),
        nrow(wb_operation_pack_registry_receipts(bundle)) == 1L)
    }
    wb_close_bundle(bundle)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }
  TRUE
}

test_operation_pack_v2_cell_set_family_writer_fail_closed_contract <- function() {
  contract_test_activate_core_conformance_pack()
  setup <- .wb_family_test_bundle("writer")
  bundle <- setup$bundle
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  op_name <- "scwbv2reference::cell_set_family_contract"
  original <- registry$packs$scwbv2reference$registration$runners[[op_name]]
  set_runner <- function(runner) {
    pack <- registry$packs$scwbv2reference
    pack$registration$runners[[op_name]] <- runner
    registry$packs$scwbv2reference <- pack
  }
  on.exit(set_runner(original), add = TRUE)
  manifest <- function(writers) writers$write_terminal_primitive(
    "manifest", wb_prim_obs_table(
      data.frame(status = "fixture", stringsAsFactors = FALSE),
      table_type = "cell_set_family_manifest"))
  payload <- function(duplicate = FALSE) list(
    kind = "cell_set_family_admission",
    sets = list(list(
      name = "set:writer", cells = if (duplicate) {
        rep(setup$cells[[1]], 2L)
      } else setup$cells[[1]],
      description = "writer", selection_rule = "fixture")),
    mode = "add",
    source = list(label = "writer", created_by = NULL,
      input_artifact_id = NULL, input_run_id = NULL,
      input_snapshot_id = NULL))
  variants <- list(
    missing = function(readers, writers, params, context) {
      manifest(writers)
      invisible(list(status = "missing"))
    },
    duplicate = function(readers, writers, params, context) {
      manifest(writers)
      writers$request_cell_set_family_admission("cell_set_family", payload())
      writers$request_cell_set_family_admission("cell_set_family", payload())
    },
    extra = function(readers, writers, params, context) {
      manifest(writers)
      writers$request_cell_set_family_admission("extra_family", payload())
    },
    malformed = function(readers, writers, params, context) {
      manifest(writers)
      writers$request_cell_set_family_admission("cell_set_family",
        payload(duplicate = TRUE))
    }
  )
  execute <- getFromNamespace(".wb_operation_pack_v2_execute",
    "scworkbench")
  before <- .wb_family_state(bundle)
  for (runner in variants) {
    set_runner(runner)
    error <- try(execute(
      bundle, op_name,
      list(labels = .wb_family_test_labels(setup$cells)), list()),
      silent = TRUE)
    transitions <- file.path(setup$root, "operation_pack_v2")
    published <- if (dir.exists(transitions)) {
      setdiff(list.dirs(transitions, recursive = FALSE,
        full.names = FALSE), ".pending")
    } else character()
    stopifnot(inherits(error, "try-error"),
      identical(.wb_family_state(bundle), before), !length(published))
  }
  TRUE
}
