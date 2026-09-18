contract_test_skip <- function(reason) {
  if (is.null(reason)) reason <- ""
  reason <- as.character(reason)
  if (length(reason) != 1L || is.na(reason) || !nzchar(trimws(reason))) {
    stop("A contract-test skip requires one non-empty reason.", call. = FALSE)
  }
  structure(list(reason = trimws(reason)), class = "scworkbench_contract_skip")
}

contract_test_signature <- function(fn, test_name) {
  if (!is.function(fn)) {
    stop("Declared contract test is not a function: ", test_name, call. = FALSE)
  }

  fml <- formals(fn)
  formal_names <- names(fml)
  if (is.null(formal_names)) formal_names <- character()
  if ("..." %in% formal_names) {
    stop("Unknown contract-test signature for ", test_name,
         ": variadic arguments are not supported.", call. = FALSE)
  }
  if ("bundle_dir" %in% formal_names && !identical(formal_names[[1L]], "bundle_dir")) {
    stop("Unknown contract-test signature for ", test_name,
         ": bundle_dir must be the first argument.", call. = FALSE)
  }

  has_default <- vapply(fml, function(value) nzchar(paste(deparse(value), collapse = "")), logical(1))
  required <- formal_names[!has_default]
  uses_bundle <- length(formal_names) > 0L && identical(formal_names[[1L]], "bundle_dir")
  allowed_required <- if (uses_bundle) "bundle_dir" else character()
  unknown_required <- setdiff(required, allowed_required)
  if (length(unknown_required)) {
    stop("Unknown contract-test signature for ", test_name,
         ": unsupported required argument(s): ",
         paste(unknown_required, collapse = ", "), ".", call. = FALSE)
  }

  list(
    kind = if (uses_bundle) "isolated_bundle" else "self_contained",
    uses_bundle = uses_bundle,
    formals = formal_names
  )
}

contract_test_discover <- function(test_dir, exclusions = character(), parent_env = globalenv(),
                                   files = NULL) {
  test_dir <- normalizePath(test_dir, winslash = "/", mustWork = TRUE)
  available <- sort(list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE))
  if (!is.null(files)) {
    requested <- as.character(files)
    if (!length(requested) || anyNA(requested) || any(!nzchar(requested)) ||
        anyDuplicated(requested)) stop("Selected contract test files must be unique non-empty paths.", call. = FALSE)
    resolved <- vapply(requested, function(path) normalizePath(if (file.exists(path)) path else
      file.path(test_dir, path), winslash = "/", mustWork = FALSE), character(1))
    missing <- requested[!resolved %in% available]
    if (length(missing)) stop("Unknown selected contract test file(s): ",
      paste(missing, collapse = ", "), call. = FALSE)
    files <- resolved
  } else files <- available
  if (!length(files)) stop("No contract test files discovered in ", test_dir, call. = FALSE)

  if (is.null(names(exclusions))) names(exclusions) <- rep("", length(exclusions))
  if (length(exclusions) && (any(!nzchar(names(exclusions))) || any(!nzchar(trimws(exclusions))))) {
    stop("Every intentional exclusion must be named and have a non-empty reason.", call. = FALSE)
  }
  if (anyDuplicated(names(exclusions))) {
    stop("Duplicate intentional exclusion names: ",
         paste(unique(names(exclusions)[duplicated(names(exclusions))]), collapse = ", "),
         call. = FALSE)
  }

  records <- list()
  files_without_tests <- character()
  for (path in files) {
    file_env <- new.env(parent = parent_env)
    sys.source(path, envir = file_env, keep.source = TRUE)
    declared <- sort(ls(file_env, pattern = "^test_", all.names = TRUE))
    if (!length(declared)) {
      files_without_tests <- c(files_without_tests, basename(path))
      next
    }
    for (test_name in declared) {
      fn <- get(test_name, envir = file_env, inherits = FALSE)
      signature <- contract_test_signature(fn, test_name)
      records[[length(records) + 1L]] <- list(
        name = test_name,
        file = normalizePath(path, winslash = "/", mustWork = TRUE),
        fn = fn,
        signature = signature,
        excluded_reason = if (test_name %in% names(exclusions)) unname(exclusions[[test_name]]) else NA_character_
      )
    }
  }

  if (length(files_without_tests)) {
    stop("Contract test file(s) declare no top-level test_* function: ",
         paste(files_without_tests, collapse = ", "), call. = FALSE)
  }

  discovered_names <- vapply(records, `[[`, character(1), "name")
  duplicates <- unique(discovered_names[duplicated(discovered_names)])
  if (length(duplicates)) {
    locations <- vapply(duplicates, function(test_name) {
      paths <- vapply(records[discovered_names == test_name], `[[`, character(1), "file")
      paste0(test_name, " [", paste(basename(paths), collapse = ", "), "]")
    }, character(1))
    stop("Duplicate contract test name(s): ", paste(locations, collapse = "; "), call. = FALSE)
  }

  stale_exclusions <- setdiff(names(exclusions), discovered_names)
  if (length(stale_exclusions)) {
    stop("Stale intentional exclusion(s): ", paste(stale_exclusions, collapse = ", "), call. = FALSE)
  }

  order_index <- order(vapply(records, `[[`, character(1), "file"), discovered_names)
  records <- records[order_index]
  structure(
    list(test_dir = test_dir, files = files, tests = records, exclusions = exclusions),
    class = "scworkbench_contract_inventory"
  )
}

contract_test_copy_bundle <- function(baseline_bundle_dir, root, test_name, index) {
  parent <- file.path(root, sprintf("%03d_%s", index, gsub("[^A-Za-z0-9_.-]+", "_", test_name)))
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(baseline_bundle_dir, parent, recursive = TRUE)
  if (!isTRUE(ok)) stop("Failed to copy baseline bundle for test: ", test_name, call. = FALSE)
  normalizePath(file.path(parent, basename(baseline_bundle_dir)), winslash = "/", mustWork = TRUE)
}

.contract_test_statistics_state <- new.env(parent = emptyenv())

contract_test_activate_statistics_pack <- function() {
  source <- Sys.getenv("SCWBSTATISTICS_SOURCE", unset = "")
  if (!nzchar(source) || !dir.exists(source)) {
    stop("Set SCWBSTATISTICS_SOURCE to the scwbStatistics source repository for migration contracts.",
      call. = FALSE)
  }
  if (is.null(.contract_test_statistics_state$library)) {
    library <- tempfile("scwbStatistics-contract-library-", tmpdir = "/tmp")
    dir.create(library, recursive = TRUE)
    log <- tempfile("scwbStatistics-contract-install-", fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(library)), shQuote(normalizePath(source))),
      stdout = log, stderr = log)
    if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"),
      call. = FALSE)
    .contract_test_statistics_state$library <- library
    .libPaths(c(library, .libPaths()))
    existing <- Sys.getenv("R_LIBS", unset = "")
    Sys.setenv(R_LIBS = paste(c(library, if (nzchar(existing)) existing else character()),
      collapse = .Platform$path.sep))
  }
  wb_operation_pack_load("scwbStatistics",
    lib.loc = .contract_test_statistics_state$library)
  invisible(TRUE)
}

.contract_test_geneprograms_state <- new.env(parent = emptyenv())

contract_test_activate_geneprograms_pack <- function() {
  source <- Sys.getenv("SCWBGENEPROGRAMS_SOURCE", unset = "")
  if (!nzchar(source) || !dir.exists(source)) {
    stop("Set SCWBGENEPROGRAMS_SOURCE to the scwbGenePrograms source repository.",
      call. = FALSE)
  }
  if (is.null(.contract_test_geneprograms_state$library)) {
    library <- tempfile("scwbGenePrograms-contract-library-", tmpdir = "/tmp")
    dir.create(library, recursive = TRUE)
    log <- tempfile("scwbGenePrograms-contract-install-", fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(library)), shQuote(normalizePath(source))),
      stdout = log, stderr = log)
    if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"),
      call. = FALSE)
    .contract_test_geneprograms_state$library <- library
    .libPaths(c(library, .libPaths()))
  }
  wb_operation_pack_load("scwbGenePrograms",
    lib.loc = .contract_test_geneprograms_state$library)
  invisible(TRUE)
}

.contract_test_representation_state <- new.env(parent = emptyenv())

contract_test_activate_representation_pack <- function() {
  source <- Sys.getenv("SCWBREPRESENTATION_SOURCE", unset = "")
  if (!nzchar(source) || !dir.exists(source)) {
    stop("Set SCWBREPRESENTATION_SOURCE to the provisional scwbRepresentation source repository.",
      call. = FALSE)
  }
  if (is.null(.contract_test_representation_state$library)) {
    library <- tempfile("scwbRepresentation-contract-library-", tmpdir = "/tmp")
    dir.create(library, recursive = TRUE)
    log <- tempfile("scwbRepresentation-contract-install-", fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(library)), shQuote(normalizePath(source))),
      stdout = log, stderr = log)
    if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"),
      call. = FALSE)
    .contract_test_representation_state$library <- library
    .libPaths(c(library, .libPaths()))
  }
  wb_operation_pack_load("scwbRepresentation",
    lib.loc = .contract_test_representation_state$library)
  invisible(TRUE)
}

.contract_test_core_conformance_state <- new.env(parent = emptyenv())

contract_test_activate_core_conformance_pack <- function() {
  if (is.null(.contract_test_core_conformance_state$library)) {
    source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
      "tests", "fixtures", "operation-pack-v2-reference")
    library <- tempfile("scwb-core-conformance-library-", tmpdir = "/tmp")
    dir.create(library, recursive = TRUE)
    log <- tempfile("scwb-core-conformance-install-", fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(library)), shQuote(source)),
      stdout = log, stderr = log)
    if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"),
      call. = FALSE)
    .contract_test_core_conformance_state$library <- library
    .libPaths(c(library, .libPaths()))
    existing <- Sys.getenv("R_LIBS", unset = "")
    Sys.setenv(R_LIBS = paste(c(library, if (nzchar(existing)) existing else character()),
      collapse = .Platform$path.sep))
  }
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV2Reference", lib.loc = .contract_test_core_conformance_state$library)
  wb_operation_pack_activate(manifest,
    lib.loc = .contract_test_core_conformance_state$library)
  invisible(TRUE)
}

# Engine-owned trajectory and wrangler contracts need a deterministic,
# provenance-valid categorical primitive, not a dependency on a clustering
# pack. The golden fixture's lineage metadata supplies that state through the
# real core operation and therefore remains replayable after promotion.
contract_test_add_core_metadata_labels <- function(session, bundle, cells,
                                                   source_column = "lineage",
                                                   notes = NULL) {
  cells <- as.character(cells)
  if (length(cells) < 2L || anyNA(cells) || any(!nzchar(cells)) || anyDuplicated(cells)) {
    stop("Core metadata labels require at least two unique, non-empty cell IDs.",
      call. = FALSE)
  }
  result <- wb_session_run_op(
    session = session,
    bundle = bundle,
    op_name = "metadata_cell_vector",
    inputs = list(
      source_column = source_column,
      vector_name = "core_test_lineage_labels",
      value_type = "categorical",
      missing_policy = "error",
      cell_set = "all",
      cell_ids = cells,
      min_cells = 2L
    ),
    notes = notes %||% "core metadata categorical-label fixture"
  )
  vector <- result$run$outputs$vector
  stopifnot(
    identical(vector$cell_id, cells),
    identical(vector$value_type, "categorical"),
    length(unique(as.character(vector$value))) >= 2L
  )
  result
}

contract_test_execute <- function(inventory, baseline_bundle_dir = NULL, reporter = TRUE) {
  if (!inherits(inventory, "scworkbench_contract_inventory")) {
    stop("inventory must come from contract_test_discover().", call. = FALSE)
  }
  bundle_tests <- vapply(inventory$tests, function(record) record$signature$uses_bundle, logical(1))
  if (any(bundle_tests)) {
    if (is.null(baseline_bundle_dir)) {
      stop("A baseline bundle is required by discovered bundle_dir tests.", call. = FALSE)
    }
    baseline_bundle_dir <- normalizePath(baseline_bundle_dir, winslash = "/", mustWork = TRUE)
  }

  bundle_root <- tempfile("scworkbench_contract_bundles_", tmpdir = "/tmp")
  dir.create(bundle_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(bundle_root, recursive = TRUE, force = TRUE), add = TRUE)

  results <- vector("list", length(inventory$tests))
  for (index in seq_along(inventory$tests)) {
    record <- inventory$tests[[index]]
    if (!is.na(record$excluded_reason)) {
      results[[index]] <- data.frame(
        name = record$name, file = basename(record$file), signature = record$signature$kind,
        status = "excluded", reason = record$excluded_reason, elapsed_seconds = 0,
        stringsAsFactors = FALSE
      )
      if (reporter) cat("EXCLUDED ", record$name, " -- ", record$excluded_reason, "\n", sep = "")
      next
    }

    isolated_parent <- NULL
    args <- list()
    if (record$signature$uses_bundle) {
      isolated_bundle <- contract_test_copy_bundle(baseline_bundle_dir, bundle_root, record$name, index)
      isolated_parent <- dirname(isolated_bundle)
      args$bundle_dir <- isolated_bundle
    }
    if (reporter) {
      cat("RUN ", record$name, " [", basename(record$file), "; ", record$signature$kind, "]\n", sep = "")
    }

    registry <- tryCatch(getFromNamespace(".wb_operation_pack_registry", "scworkbench"),
      error = function(error) NULL)
    registry_preimage <- if (is.null(registry)) NULL else unserialize(serialize(list(
      packs = registry$packs, operations = registry$operations,
      registration_context = registry$registration_context), NULL, version = 3L))
    conformance_namespace_loaded <- "scwbV2Reference" %in% loadedNamespaces()
    started <- proc.time()[["elapsed"]]
    value <- tryCatch(
      do.call(record$fn, args),
      error = function(error) structure(list(message = conditionMessage(error)), class = "scworkbench_contract_failure")
    )
    if (!is.null(registry_preimage)) {
      registry$packs <- registry_preimage$packs
      registry$operations <- registry_preimage$operations
      registry$registration_context <- registry_preimage$registration_context
    }
    if (!conformance_namespace_loaded && "scwbV2Reference" %in% loadedNamespaces()) {
      try(unloadNamespace("scwbV2Reference"), silent = TRUE)
    }
    elapsed <- proc.time()[["elapsed"]] - started
    if (!is.null(isolated_parent)) unlink(isolated_parent, recursive = TRUE, force = TRUE)

    if (inherits(value, "scworkbench_contract_skip")) {
      status <- "skipped"
      reason <- value$reason
      if (reporter) cat("SKIP ", record$name, " -- ", reason, "\n", sep = "")
    } else if (inherits(value, "scworkbench_contract_failure")) {
      status <- "failed"
      reason <- value$message
      if (reporter) cat("FAIL ", record$name, " -- ", reason, "\n", sep = "")
    } else if (!isTRUE(value)) {
      status <- "failed"
      reason <- "contract did not return TRUE"
      if (reporter) cat("FAIL ", record$name, " -- ", reason, "\n", sep = "")
    } else {
      status <- "passed"
      reason <- ""
      if (reporter) cat("PASS ", record$name, sprintf(" (%.3fs)\n", elapsed), sep = "")
    }
    results[[index]] <- data.frame(
      name = record$name, file = basename(record$file), signature = record$signature$kind,
      status = status, reason = reason, elapsed_seconds = elapsed,
      stringsAsFactors = FALSE
    )
  }

  result <- do.call(rbind, results)
  rownames(result) <- NULL
  discovered <- length(inventory$tests)
  excluded <- sum(result$status == "excluded")
  executed <- discovered - excluded
  passed <- sum(result$status == "passed")
  skipped <- sum(result$status == "skipped")
  failed <- sum(result$status == "failed")
  accounted <- passed + skipped + failed + excluded
  if (!identical(accounted, discovered) || !identical(executed, passed + skipped + failed)) {
    stop("Internal contract-runner accounting mismatch.", call. = FALSE)
  }
  if (anyDuplicated(result$name) || !setequal(result$name, vapply(inventory$tests, `[[`, character(1), "name"))) {
    stop("Internal contract-runner execution inventory mismatch.", call. = FALSE)
  }

  summary <- c(
    files = length(inventory$files), discovered = discovered, executed = executed,
    passed = passed, skipped = skipped, failed = failed, excluded = excluded,
    accounted = accounted
  )
  if (reporter) {
    cat("CONTRACT TEST SUMMARY ",
        paste(names(summary), summary, sep = "=", collapse = " "), "\n", sep = "")
  }
  structure(list(results = result, summary = summary), class = "scworkbench_contract_run")
}

contract_test_assert_success <- function(run) {
  failed <- run$results[run$results$status == "failed", , drop = FALSE]
  if (nrow(failed)) {
    details <- paste0(failed$name, " [", failed$file, "]: ", failed$reason)
    stop("Contract suite failed:\n- ", paste(details, collapse = "\n- "), call. = FALSE)
  }
  invisible(TRUE)
}
