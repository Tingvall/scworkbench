#!/usr/bin/env Rscript
# Reconstruct the accepted Phase 7 root-test inventory from Git, not from the
# edited Phase 8 working tree. Usage: Rscript ... <baseline-inventory.csv>
# <references.csv> <frozen-operation-names.csv> <current-inventory.csv>
# Run from the Phase 8 core worktree with SCWB_PHASE8_REPRESENTATION_SOURCE
# pointing at the clean, pinned Representation test-ownership worktree.
# Add --current-only with the same four paths to refresh current discovery
# from the frozen baseline/reference CSVs without re-reading official packs.
args <- commandArgs(trailingOnly = TRUE)
current_only <- "--current-only" %in% args
args <- setdiff(args, "--current-only")
if (length(args) != 4L) stop("Expected baseline inventory, references, operation names and current inventory CSV paths")
source("inst/dev/phase8_test_ownership_helpers.R")
baseline <- "0aaa68893e595993c2664e104f7e0dc20702f960"
# This is the committed ownership decision, not the current documentation HEAD.
# Using HEAD here would rewrite every ledger row on unrelated later commits.
new_core_commit <- "03f5a5bf699ac36ed44fc0a3cc56a2d750e76f7e"
git <- function(...) {
  out <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0L)
    stop(paste(out, collapse = "\n"))
  out
}
walk <- function(x, fun) {
  if (is.call(x)) {
    fun(x)
    if (length(x) > 1L) for (i in seq.int(2L, length(x)))
      try(walk(x[[i]], fun), silent = TRUE)
  } else if (is.expression(x) || is.pairlist(x) || is.list(x)) {
    for (i in seq_along(x)) try(walk(x[[i]], fun), silent = TRUE)
  }
}
call_text <- function(x) paste(deparse(x, width.cutoff = 500L), collapse = " ")
if (!current_only) {
paths <- git("ls-tree", "-r", "--name-only", baseline, "tests")
representation_owner_commit <- "d0a25aacef000f52b211ee0e138d4c964c68cc77"
paths <- sort(paths[grepl("^tests/test_.*\\.R$", paths)])
stopifnot(length(paths) == 139L)
profile <- jsonlite::read_json("inst/standard_profile/profile.json",
  simplifyVector = FALSE)
pack_root <- Sys.getenv("SCWB_PHASE8_PACK_ROOT",
  unset = "/home/dirk/Projects/operation_packs")
operation_rows <- list()
for (pack in profile$packs) {
  source <- if (identical(pack$package, "scwbRepresentation"))
    Sys.getenv("SCWB_PHASE8_REPRESENTATION_SOURCE",
      unset = file.path(pack_root, pack$package)) else
    file.path(pack_root, pack$package)
  if (!identical(git("-C", source, "rev-parse", "HEAD")[[1L]],
      pack$source_commit)) stop("Pack source does not match Phase 8 pin: ", source)
  manifest <- jsonlite::read_json(file.path(source, "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  if (!identical(length(manifest$operations), as.integer(pack$operation_count)))
    stop("Operation count differs from standard-profile lock: ", source)
  for (operation in manifest$operations)
    operation_rows[[length(operation_rows) + 1L]] <- data.frame(
      package = pack$package, source_commit = pack$source_commit,
      operation_name = operation$name,
      qualified_name = operation$qualified_name)
}
operations <- do.call(rbind, operation_rows)
stopifnot(nrow(operations) == 56L, !anyDuplicated(operations$qualified_name))
write.csv(operations, args[[3L]], row.names = FALSE)
op_names <- unique(c(operations$operation_name, operations$qualified_name))
overrides <- list(
  test_immutable_history_state_machine_closure_contract = c(
    "pinned_composite", "retain_composite",
    "tests/composite/phase8/test_immutable_history_state_machine_closure_contract.R",
    "Real Representation UMAP/model historical lifecycle requires an exact pack."),
  test_durable_session_source_payload_corruption_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_durable_session_source_payload_corruption_contract.R;tests/composite/phase8/test_durable_session_staged_space_registry_binding_contract.R",
    "Generic source/payload checks use synthetic model; real UMAP registry binding is pinned composite."),
  test_public_typed_run_branch_inputs_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_public_typed_run_branch_inputs_contract.R",
    "Generic typed-branch and replay authority use synthetic G1 model fixture."),
  test_strict_operation_input_validation_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_strict_operation_input_validation_contract.R",
    "Generic validation uses retained core metadata operation."),
  test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract = c(
    "pack_method", "move",
    paste("scwbRepresentation/tests/test_knn_sparse_contract.R:test_representation_knn_pseudobulk_zero_neighbor_contract",
      "tests/test_operation_pack_v3_sparse_membership_contract.R:test_operation_pack_v3_pseudobulk_zero_neighbor_grant_contract", sep = ";"),
    "Scientific kNN zero-neighbor behavior moved to Representation; synthetic sparse grant validation stays core."))
rows <- list(); refs <- list()
for (path in paths) {
  parsed <- parse(text = git("show", paste0(baseline, ":", path)))
  for (expr in parsed) {
    if (!is.call(expr) || !identical(expr[[1L]], as.name("<-")) ||
        !is.symbol(expr[[2L]]) || !startsWith(as.character(expr[[2L]]), "test_") ||
        !is.call(expr[[3L]]) || !identical(expr[[3L]][[1L]], as.name("function"))) next
    name <- as.character(expr[[2L]])
    body <- expr[[3L]][[3L]]
    assertions <- character(); strings <- character()
    walk(body, function(node) {
      if (identical(node[[1L]], as.name("stopifnot")))
        assertions <<- c(assertions, call_text(node))
      if (length(node) > 1L) for (i in seq.int(2L, length(node)))
        try(if (is.character(node[[i]])) strings <<- c(strings, node[[i]]),
          silent = TRUE)
    })
    if (!length(assertions)) walk(body, function(node) {
      head <- as.character(node[[1L]])
      if (length(head) == 1L && grepl("(expect|assert)", head))
        assertions <<- c(assertions, call_text(node))
    })
    stopifnot(length(assertions) > 0L)
    strings <- unique(strings)
    fixtures <- strings[grepl("(fixtures/|\\.bundle$|\\.rds$|\\.h5$|\\.h5ad$|\\.json$)", strings)]
    found <- unique(op_names[op_names %in% strings])
    override <- overrides[[name]]
    if (is.null(override)) override <- c("core_engine", "retain_core", path,
      "Engine authority, catalog, schema, security, provenance, or historical inspection assertion.")
    rows[[length(rows) + 1L]] <- data.frame(
      baseline_commit = baseline, test_identity = name, source_path = path,
      assertion_count = length(assertions), key_assertions = paste(assertions, collapse = " || "),
      fixtures = paste(fixtures, collapse = " | "),
      owner = override[[1L]], disposition = override[[2L]],
      destination = override[[3L]], justification = override[[4L]],
      migrated_operation_references = paste(found, collapse = " | "),
      old_owner_commit = baseline,
      new_owner_commit = if (identical(override[[1L]], "pack_method"))
        representation_owner_commit else new_core_commit)
    for (op in found) refs[[length(refs) + 1L]] <- data.frame(
      baseline_commit = baseline, source_path = path, test_identity = name,
      migrated_operation = op, owner = override[[1L]],
      disposition = override[[2L]], destination = override[[3L]],
      justification = override[[4L]], old_owner_commit = baseline,
      new_owner_commit = if (identical(override[[1L]], "pack_method"))
        representation_owner_commit else new_core_commit)
  }
}
inventory <- do.call(rbind, rows)
stopifnot(nrow(inventory) == 242L, !anyDuplicated(inventory$test_identity),
  !anyNA(inventory$owner), !anyNA(inventory$disposition))
write.csv(inventory, args[[1L]], row.names = FALSE, na = "")
references <- do.call(rbind, refs)
write.csv(references, args[[2L]], row.names = FALSE, na = "")
} else {
  # Later core additions must not regenerate frozen historical ownership or
  # inspect/change current official-pack trees merely to refresh discovery.
  inventory <- utils::read.csv(args[[1L]], stringsAsFactors = FALSE)
  references <- utils::read.csv(args[[2L]], stringsAsFactors = FALSE)
}
current_paths <- sort(list.files("tests", pattern = "^test_.*\\.R$", full.names = TRUE))
current_rows <- list()
introduced <- list(
  test_operation_pack_v3_pseudobulk_zero_neighbor_grant_contract = c(
    "test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract",
    "Generic sparse output-cardinality grant conformance replaces a method-owned kNN assertion."),
  test_phase8_no_pack_core_surface_contract = c("",
    "Phase 8 no-pack catalog and dependency boundary regression."),
  test_phase8_primitive_exchange_inventory_contract = c("",
    "Phase 8 built-in primitive boundary and evidence regression."),
  test_phase8_test_ownership_inventory_contract = c("",
    "Phase 8 test-ownership and discovery accounting regression."))
sdk_tests <- c("scaffold_safety", "manifest_negatives", "catalog_coverage",
  "case_accounting", "installed_contract", "installed_tutorial", "activation_negatives")
sdk_tests <- paste0("test_operation_pack_sdk_", sdk_tests)
for (name in sdk_tests) introduced[[name]] <- c("",
  "Core-owned installed SDK authoring, admission, capability or lifecycle conformance; synthetic method assertions ship in the author template.")
# Additions are explicit ownership decisions, separate from the frozen Phase 8
# baseline. Discovery may validate this ledger but never classify future tests.
additions <- utils::read.csv("inst/phase8/graph_and_core_test_additions.csv",
  stringsAsFactors = FALSE)
stopifnot(nrow(additions) == 85L, !anyDuplicated(additions$test_identity),
  !any(additions$test_identity %in% c(inventory$test_identity, names(introduced))),
  all(additions$owner == "core_engine"), all(additions$disposition == "retain_core"),
  all(nzchar(additions$justification)),
  all(grepl("^[0-9a-f]{40}$", additions$ownership_decision_commit)),
  all(grepl("^[0-9a-f]{40}$", additions$source_checkpoint_commit)))
for (i in seq_len(nrow(additions))) introduced[[additions$test_identity[[i]]]] <-
  c("", additions$justification[[i]])
engine_additions <- utils::read.csv("inst/phase8/engine_execution_test_additions_v1.csv",
  stringsAsFactors = FALSE)
.phase8_validate_engine_additions(engine_additions,
  c(inventory$test_identity, names(introduced)))
for (i in seq_len(nrow(engine_additions))) introduced[[engine_additions$test_identity[[i]]]] <-
  c("", engine_additions$justification[[i]])
declared_additions <- rbind(additions, engine_additions[, names(additions)])
for (path in current_paths) {
  parsed <- parse(path)
  for (expr in parsed) {
    if (!is.call(expr) || !identical(expr[[1L]], as.name("<-")) ||
        !is.symbol(expr[[2L]]) || !startsWith(as.character(expr[[2L]]), "test_") ||
        !is.call(expr[[3L]]) || !identical(expr[[3L]][[1L]], as.name("function"))) next
    name <- as.character(expr[[2L]])
    assertions <- character(); strings <- character()
    walk(expr[[3L]][[3L]], function(node) {
      if (identical(node[[1L]], as.name("stopifnot")))
        assertions <<- c(assertions, call_text(node))
      if (length(node) > 1L) for (i in seq.int(2L, length(node)))
        try(if (is.character(node[[i]])) strings <<- c(strings, node[[i]]),
          silent = TRUE)
    })
    if (!length(assertions)) walk(expr[[3L]][[3L]], function(node) {
      head <- as.character(node[[1L]])
      if (length(head) == 1L && grepl("(expect|assert)", head))
        assertions <<- c(assertions, call_text(node))
    })
    stopifnot(length(assertions) > 0L)
    prior <- inventory[inventory$test_identity == name, , drop = FALSE]
    addition <- introduced[[name]]
    if (!nrow(prior) && is.null(addition)) stop("Unclassified current test: ", name)
    declared_addition <- declared_additions[declared_additions$test_identity == name, , drop = FALSE]
    if (nrow(declared_addition) && !identical(path, declared_addition$source_path))
      stop("Current addition source differs from ownership ledger: ", name)
    current_rows[[length(current_rows) + 1L]] <- data.frame(
      test_identity = name, source_path = path,
      assertion_count = length(assertions),
      key_assertions = paste(assertions, collapse = " || "),
      fixtures = paste(unique(strings[grepl(
        "(fixtures/|\\.bundle$|\\.rds$|\\.h5$|\\.h5ad$|\\.json$)",
        strings)]), collapse = " | "),
      owner = "core_engine", disposition = "retain_core",
      destination = path,
      origin_baseline_test_identity = if (nrow(prior)) name else addition[[1L]],
      justification = if (nrow(prior)) prior$justification else addition[[2L]],
      old_owner_commit = if (nrow(prior) || nzchar(addition[[1L]])) baseline else "",
      new_owner_commit = if (name %in% sdk_tests)
        "baf5cb40650a6a6a0e5219b03785e5bed0c4d2b3" else if (nrow(declared_addition))
        declared_addition$ownership_decision_commit else new_core_commit)
  }
}
current <- do.call(rbind, current_rows)
expected_current <- c(setdiff(inventory$test_identity,
  c("test_immutable_history_state_machine_closure_contract",
    "test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract")), names(introduced))
.phase8_assert_classified_discovery(current$test_identity, expected_current)
stopifnot(nrow(current) == length(expected_current), !anyDuplicated(current$test_identity),
  identical(sort(setdiff(current$test_identity, inventory$test_identity)),
    sort(names(introduced))),
  identical(sort(setdiff(inventory$test_identity, current$test_identity)),
    sort(c("test_immutable_history_state_machine_closure_contract",
      "test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract"))))
write.csv(current, args[[4L]], row.names = FALSE, na = "")
cat(sprintf("PHASE8_TEST_INVENTORY tests=%d files=%d migrated_reference_rows=%d\n",
  nrow(inventory), length(unique(inventory$source_path)), nrow(references)))
cat(sprintf("PHASE8_CURRENT_TEST_INVENTORY tests=%d files=%d introduced=%d moved=%d\n",
  nrow(current), length(unique(current$source_path)),
  length(setdiff(current$test_identity, inventory$test_identity)),
  length(setdiff(inventory$test_identity, current$test_identity))))
