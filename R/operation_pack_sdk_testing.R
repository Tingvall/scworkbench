#' Assemble the SDK's Small Ordered Matrix Fixture
#' @param path New test bundle directory.
#' @return Named list: `bundle` (open assembly), `values` (feature-major
#'   matrix), `cells`, `features`, `selected` (ordered session subset), and
#'   `sums` (unnamed expected numeric sums over selected cells).
#'   Fixture generation is test-only and refuses an existing destination.
#' @export
wb_operation_pack_sdk_fixture <- function(path) {
  cells <- c("cell_2", "cell_10", "cell_1", "cell_3", "cell_7", "cell_4")
  features <- c("gene_2", "gene_10", "gene_1")
  values <- matrix(c(1, 2, 3, 4, 5, 6, 2, 0, 1, 0, 0, 0,
    7, 1, 2, 3, 2, 1), nrow = 3L, dimnames = list(features, cells))
  bundle <- wb_init_bundle(path)
  completed <- FALSE
  on.exit(if (!completed) try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "counts", values, feature_type = "gene")
  selected <- cells[c(1L, 3L, 4L, 5L, 6L)]
  wb_cell_set_replace(bundle, "set:sdk_subset", selected, source = "sdk_fixture")
  completed <- TRUE
  list(bundle = bundle, values = values, cells = cells, features = features,
    selected = selected, sums = unname(colSums(values[, selected, drop = FALSE])))
}

#' Observe Durable State for SDK Rollback Assertions
#' @param bundle Open test bundle.
#' @return Core-owned state fingerprint and payload inventory, excluding mutable
#'   SQLite physical pages, locks and publication timestamps. No SQL handle is returned.
#' @export
wb_operation_pack_sdk_state <- function(bundle) {
  registry <- .wb_manifest_registry_snapshot(bundle$con)$fingerprint
  root <- normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
  relative <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
    no.. = TRUE, include.dirs = FALSE))
  relative <- relative[!grepl("^(db/|manifest[.]json$|[.]writer|[.]manifest)", relative)]
  paths <- file.path(root, relative)
  list(registry = registry, paths = relative,
    sha256 = unname(vapply(paths, .wb_prov_sha256_file, character(1))))
}

#' Run a Registered Pack Through Public Dispatch in an SDK Test
#'
#' Fault injection is scoped to this call and restored on every exit. The
#' `after_first_terminal` fault delegates a genuine writer first, then fails;
#' publication faults use the engine's existing test seam. This facility is
#' exclusively for isolated tests; it supplies no production runner authority.
#' @param bundle Open isolated test bundle.
#' @param operation Activated qualified operation name.
#' @param inputs Normal public dispatcher inputs.
#' @param fault Optional `"after_first_terminal"`, `"before_publication"`, or
#'   `"published"` failure point; invalid schedules `"skip_partition"`,
#'   `"repeat_partition"`, `"reversed_partition"`, `"oversized_partition"`,
#'   `"foreign_partition"`; or `"missing_terminal"`, `"reordered_output"`.
#' @return Captured result/error, before/after source state, actual audited
#'   `read_observations`, and unchanged indicator. Failed calls additionally
#'   require unchanged private staging state, which is then discarded.
#' @export
wb_operation_pack_sdk_run <- function(bundle, operation, inputs, fault = NULL) {
  runner_faults <- c("after_first_terminal", "skip_partition", "repeat_partition",
    "reversed_partition", "oversized_partition", "foreign_partition",
    "missing_terminal", "reordered_output")
  if (!is.null(fault) && !fault %in% c(runner_faults, "before_publication", "published"))
    stop("Unsupported SDK fault point.", call. = FALSE)
  before <- wb_operation_pack_sdk_state(bundle)
  old_hook <- getOption("scworkbench.operation_pack_v2_test_hook", NULL)
  on.exit(options(scworkbench.operation_pack_v2_test_hook = old_hook), add = TRUE)
  if (!is.null(fault) && fault %in% runner_faults) {
    record <- .wb_operation_pack_registry$operations[[operation]]
    if (is.null(record)) stop("Activate the operation before injecting writer faults.", call. = FALSE)
    pack <- .wb_operation_pack_registry$packs[[record$namespace]]
    original <- pack$registration$runners[[operation]]
    on.exit({
      current <- .wb_operation_pack_registry$packs[[record$namespace]]
      current$registration$runners[[operation]] <- original
      .wb_operation_pack_registry$packs[[record$namespace]] <- current
    }, add = TRUE)
    pack$registration$runners[[operation]] <- function(readers, writers, params, context) {
      if (fault %in% c("skip_partition", "repeat_partition", "reversed_partition",
          "oversized_partition", "foreign_partition")) {
        name <- names(context$typed_slice_reads)[[1L]]
        grant <- context$typed_slice_reads[[name]]
        cells <- as.character(grant$cells); features <- as.character(grant$features)
        chunks <- wb_partition_axis(cells, grant$requested_chunk_size)
        selected <- switch(fault, skip_partition = chunks[[2L]],
          repeat_partition = chunks[[1L]], reversed_partition = rev(chunks[[1L]]),
          oversized_partition = head(cells, grant$requested_chunk_size + 1L),
          foreign_partition = "sdk_foreign_cell")
        readers[[name]](features = features, cells = selected)
        if (fault == "repeat_partition") readers[[name]](features = features, cells = selected)
        stop("SDK invalid reader schedule unexpectedly admitted.")
      }
      delegated <- writers$write_terminal_primitive
      count <- 0L
      writers$write_terminal_primitive <- function(...) {
        args <- list(...); count <<- count + 1L
        if (fault == "missing_terminal" && count > 1L) return(invisible(NULL))
        if (fault == "reordered_output" && count == 1L)
          args[[2L]]$cell_id <- rev(args[[2L]]$cell_id)
        value <- do.call(delegated, args)
        if (fault == "after_first_terminal" && count == 1L)
          stop("SDK injected failure after first terminal.", call. = FALSE)
        value
      }
      original(readers, writers, params, context)
    }
    .wb_operation_pack_registry$packs[[record$namespace]] <- pack
  } else if (!is.null(fault)) {
    options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
      if (identical(event, fault)) stop("SDK injected publication failure.", call. = FALSE)
      if (is.function(old_hook)) old_hook(event = event, ...)
    })
  }
  # Keep the existing engine's staging handle even when public dispatch throws,
  # so an isolated negative test can inspect and discard its own workspace.
  staged <- .wb_session_stage_bundle(bundle, wb_session_new())
  stage_before <- wb_operation_pack_sdk_state(staged$bundle)
  value <- tryCatch(wb_session_run_op(staged$session, bundle, operation,
    inputs = inputs), error = identity)
  after <- wb_operation_pack_sdk_state(bundle)
  stage_unchanged <- if (inherits(value, "error")) identical(stage_before,
    wb_operation_pack_sdk_state(staged$bundle)) else FALSE
  if (inherits(value, "error")) wb_session_discard(staged$session)
  observations <- NULL
  if (!inherits(value, "error")) {
    id <- value$run$operation_pack_transition$transition_id
    record <- .wb_operation_pack_v2_record_validate(file.path(
      .wb_operation_pack_v2_store(value$session$staging_bundle), id), load_payloads = FALSE)
    if (!isTRUE(record$ok)) stop("SDK cannot inspect the audited transition.")
    observations <- record$receipt$typed_slice_usage
  }
  list(ok = !inherits(value, "error"), result = if (!inherits(value, "error")) value else NULL,
    error = if (inherits(value, "error")) value else NULL,
    before = before, after = after, unchanged = identical(before, after) &&
      (!inherits(value, "error") || stage_unchanged),
    staging_unchanged = stage_unchanged,
    read_observations = observations)
}

#' Assert SDK Execution Values, Parameters or Rollback
#' @param result Result from [wb_operation_pack_sdk_run()].
#' @param outputs Named list of expected primitive fields for each output.
#' @param params Named expected retained parameter fields.
#' @param error Optional substring required in a captured error.
#' @param unchanged Require identical durable state.
#' @param tolerance Explicit numeric comparison tolerance, default exact values.
#' @return `TRUE`, or an assertion error.
#' @export
wb_operation_pack_sdk_assert <- function(result, outputs = list(), params = list(),
                                         error = NULL, unchanged = FALSE, tolerance = 0) {
  if (!is.null(error)) {
    if (isTRUE(result$ok) || !grepl(error, conditionMessage(result$error), fixed = TRUE))
      stop("Expected execution error: ", error, call. = FALSE)
  } else {
    if (!isTRUE(result$ok)) stop(result$error)
    for (name in names(outputs)) for (field in names(outputs[[name]])) {
      actual <- result$result$run$outputs[[name]][[field]]
      expected <- outputs[[name]][[field]]
      equal <- if (is.numeric(actual) && is.numeric(expected))
        isTRUE(all.equal(actual, expected, tolerance = tolerance, check.attributes = TRUE)) else
        identical(actual, expected)
      if (!equal) stop("Output differs: ", name, "$", field, call. = FALSE)
    }
    for (name in names(params)) if (!isTRUE(all.equal(
      result$result$run$params[[name]], params[[name]], tolerance = tolerance)))
      stop("Retained parameter differs: ", name, call. = FALSE)
  }
  if (isTRUE(unchanged) && !isTRUE(result$unchanged))
    stop("Execution left durable residue.", call. = FALSE)
  TRUE
}

#' Mark an SDK Case Explicitly Skipped
#' @param reason Nonempty reason; a skip makes the tier unqualified.
#' @return Raises an SDK skip condition for the case driver.
#' @export
wb_operation_pack_sdk_skip <- function(reason) {
  stop(structure(list(message = .wb_sdk_text(reason, "reason"), call = NULL),
    class = c("wb_sdk_skip", "error", "condition")))
}

#' Account for Named SDK Author Tests
#' @param cases Named list of zero-argument test functions.
#' @return Report with individual cases, counts and actual runtime/pack identities.
#' @export
wb_operation_pack_sdk_cases <- function(cases) {
  if (!is.list(cases) || !length(cases) || is.null(names(cases)) ||
      any(!nzchar(names(cases))) || anyDuplicated(names(cases)) ||
      !all(vapply(cases, is.function, logical(1)))) stop("Named test functions are required.")
  rows <- lapply(names(cases), function(name) {
    start <- proc.time()[["elapsed"]]
    value <- tryCatch({ cases[[name]](); NULL }, error = identity)
    status <- if (inherits(value, "wb_sdk_skip")) "skipped" else
      if (inherits(value, "error")) "failed" else "passed"
    reason <- if (inherits(value, "error")) conditionMessage(value) else ""
    cat(toupper(status), name, if (nzchar(reason)) paste("--", reason) else "", "\n")
    list(name = name, status = status, reason = reason,
      elapsed_seconds = proc.time()[["elapsed"]] - start)
  })
  statuses <- vapply(rows, `[[`, character(1), "status")
  counts <- list(discovered = length(cases), executed = length(rows),
    passed = sum(statuses == "passed"), skipped = sum(statuses == "skipped"),
    failed = sum(statuses == "failed"))
  cat(sprintf("SDK_CASE_SUMMARY discovered=%d executed=%d passed=%d skipped=%d failed=%d\n",
    counts$discovered, counts$executed, counts$passed, counts$skipped, counts$failed))
  list(sdk_version = "1.0.0", counts = counts, cases = rows,
    identities = list(scworkbench = as.character(utils::packageVersion("scworkbench")),
      R = as.character(getRversion()), packs = wb_operation_packs()),
    qualified = counts$failed == 0L && counts$skipped == 0L)
}

#' Finalize, Relocate and Inspect an SDK Recipient in a Fresh Process
#' @param bundle Open test bundle after promotion. This helper closes it.
#' @param destination New recipient directory.
#' @param operation Qualified operation whose absence must reject execution.
#' @return Recipient path and complete fresh-process audit log/exit.
#' @export
wb_operation_pack_sdk_recipient <- function(bundle, destination, operation) {
  if (file.exists(destination)) stop("Recipient destination exists.", call. = FALSE)
  source <- bundle$dir
  wb_finalize_recipient_bundle(bundle); wb_close_bundle(bundle)
  dir.create(destination, recursive = FALSE)
  files <- list.files(source, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  if (!all(file.copy(files, destination, recursive = TRUE))) stop("Recipient copy failed.")
  log <- tempfile("sdk-recipient-", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote(.wb_sdk_asset("scripts", "recipient.R")),
    shQuote(normalizePath(destination, mustWork = TRUE)), shQuote(operation)),
    env = paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = .Platform$path.sep))),
    stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log, warn = FALSE), collapse = "\n"), call. = FALSE)
  list(path = normalizePath(destination, mustWork = TRUE), exit = as.integer(status),
    log = log, evidence = readLines(log, warn = FALSE))
}
