.sdk_project <- function(package = "scwbSdkTest", namespace = "sdktest")
  wb_operation_pack_scaffold(tempfile("SDK project "), package, namespace,
    "SDK Test Author", "sdk@example.org")

test_operation_pack_sdk_scaffold_safety <- function() {
  before <- wb_list_ops()
  root <- tempfile("SDK safety "); dir.create(root)
  project <- wb_operation_pack_scaffold(file.path(root, "Pack with spaces"),
    "scwbSdkSafe", "sdksafe", "SDK Author", "sdk@example.org")
  stopifnot(wb_operation_pack_check(project$path)$qualified,
    identical(before, wb_list_ops()))
  reject <- function(...) stopifnot(inherits(tryCatch(
    wb_operation_pack_scaffold(...), error = identity), "error"))
  existing <- readLines(file.path(project$path, "DESCRIPTION"))
  reject(project$path, "scwbSdkSafe", "sdksafe", "SDK Author", "sdk@example.org")
  reject(file.path(root, "..", "unsafe"), "scwbSdkSafe", "sdksafe", "SDK Author", "sdk@example.org")
  reject(file.path(root, "bad"), "../unsafe", "sdksafe", "SDK Author", "sdk@example.org")
  reject(file.path(root, "reserved"), "scwbSdkSafe", "core", "SDK Author", "sdk@example.org")
  stopifnot(identical(existing, readLines(file.path(project$path, "DESCRIPTION"))))
  old <- getOption("scworkbench.sdk_scaffold_test_hook")
  on.exit(options(scworkbench.sdk_scaffold_test_hook = old), add = TRUE)
  options(scworkbench.sdk_scaffold_test_hook = function(...) stop("generation fault"))
  reject(file.path(root, "failed"), "scwbSdkSafe", "sdksafe", "SDK Author", "sdk@example.org")
  stopifnot(!file.exists(file.path(root, "failed")),
    !any(grepl("scwb-sdk", list.files(root, all.files = TRUE))))
  TRUE
}

test_operation_pack_sdk_manifest_negatives <- function() {
  project <- .sdk_project()
  source <- readLines(project$manifest)
  manifest <- jsonlite::read_json(project$manifest)
  before <- wb_list_ops()
  mutations <- list(
    reserved = function(x) { x$namespace <- "core";
      x$operations[[1]]$qualified_name <- "core::matrix_cell_sum"; x },
    mismatch = function(x) { x$operations[[1]]$qualified_name <- "other::matrix_cell_sum"; x },
    duplicate_output = function(x) { x$operations[[1]]$outputs[[2]]$name <- "sums"; x },
    duplicate_allocation = function(x) { x$operations[[1]]$outputs[[2]]$allocated_id_key <- "sums_id"; x },
    invalid_params = function(x) { x$operations[[1]]$params_schema$properties$chunk_size$type <- "any"; x },
    dangling_closure = function(x) { x$operations[[1]]$promotion_closure$sums <- list("ghost", "sums"); x },
    wrong_profile = function(x) { x$operations[[1]]$outputs[[1]]$storage_profile <- "space_h5_v1"; x },
    wrong_alignment = function(x) { x$operations[[1]]$inputs[[1]]$alignment <- "not_aligned"; x })
  for (change in mutations) {
    jsonlite::write_json(change(manifest), project$manifest, auto_unbox = TRUE, null = "null")
    failure <- tryCatch(wb_operation_pack_manifest_validate(project$manifest), error = identity)
    stopifnot(inherits(failure, "error"), identical(before, wb_list_ops()))
  }
  writeLines(sub('"namespace":"sdktest"',
    '"namespace":"sdktest","namespace":"sdktest"', source, fixed = TRUE), project$manifest)
  stopifnot(inherits(tryCatch(wb_operation_pack_manifest_validate(project$manifest), error = identity), "error"))
  writeLines(source, project$manifest)
  dcf <- read.dcf(file.path(project$path, "DESCRIPTION"))
  dcf[[1, "Authors@R"]] <- "{ stop('STATIC MUST NOT EXECUTE'); person('Bad', email='x@example.org',role='cre') }"
  write.dcf(dcf, file.path(project$path, "DESCRIPTION"))
  checked <- wb_operation_pack_check(project$path)
  stopifnot(!checked$qualified, grepl("literal person", checked$checks$static$reason),
    inherits(tryCatch(wb_operation_pack_check(project$path, "installed"), error = identity), "error"))
  TRUE
}

test_operation_pack_sdk_catalog_coverage <- function() {
  catalog <- wb_operation_pack_capabilities()
  schema <- jsonlite::read_json(system.file("protocol", "operation-pack-v3.schema.json", package = "scworkbench"))
  stopifnot(identical(unlist(catalog$primitive_kinds, use.names = FALSE),
    unlist(schema[["$defs"]]$primitive_kind$enum, use.names = FALSE)),
    identical(unlist(catalog$storage_profiles, use.names = FALSE),
      unlist(schema[["$defs"]]$storage_profile$enum, use.names = FALSE)),
    identical(unlist(catalog$operation_declaration_fields, use.names = FALSE),
      names(schema[["$defs"]]$operation$properties)),
    length(catalog$callbacks_and_context$context) == 13L,
    all(vapply(catalog$declaration_branches, function(x) x$capability_id %in%
      vapply(catalog$capabilities, `[[`, character(1), "id"), logical(1))),
    length(catalog$Python_policy_support$capabilities) >= 30L)
  result <- scworkbench:::.wb_json_schema_validate_2020(catalog,
    jsonlite::read_json(system.file("sdk", "operation-packs", "capabilities.schema.json", package = "scworkbench")))
  stopifnot(isTRUE(result$ok))
  for (recipe in catalog$declaration_recipes)
    wb_operation_pack_manifest_validate(system.file("sdk", "operation-packs", recipe$path, package = "scworkbench"))
  branch_owners <- vapply(catalog$declaration_branches, `[[`, character(1), "capability_id")
  stopifnot(all(c("G3", "G4", "G5", "G6", "G7", "models", "typed_spaces", "matrix_fragments") %in% branch_owners))
  root <- system.file("sdk", "operation-packs", "templates", "R", package = "scworkbench")
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  text <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
  stopifnot(!grepl(":::|DBI::|SELECT |payload[.]rds|[.]wb_", text),
    !any(grepl("sdk.*::matrix_cell_sum", wb_list_ops())))
  TRUE
}

test_operation_pack_sdk_case_accounting <- function() {
  report <- wb_operation_pack_sdk_cases(list(passes = function() TRUE,
    skips = function() wb_operation_pack_sdk_skip("fixture deliberately absent"),
    fails = function() stop("deliberate assertion")))
  stopifnot(!report$qualified, report$counts$discovered == 3L,
    report$counts$executed == 3L, report$counts$passed == 1L,
    report$counts$skipped == 1L, report$counts$failed == 1L,
    nzchar(report$cases[[2]]$reason), nzchar(report$cases[[3]]$reason))
  TRUE
}

.sdk_installed_library <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) return(cached)
    lib <- tempfile("SDK clean core library "); dir.create(lib)
    log <- tempfile("sdk-core-install-", fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(lib)), shQuote(normalizePath("."))), stdout = log, stderr = log)
    if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
    cached <<- lib
    lib
  }
})

test_operation_pack_sdk_installed_contract <- function() {
  lib <- .sdk_installed_library()
  log <- tempfile("sdk-installed-contract-", fileext = ".log")
  script <- tempfile(fileext = ".R")
  writeLines(c("library(scworkbench)",
    "p <- wb_operation_pack_scaffold(tempfile('SDK installed project '), 'scwbSdkAcceptance', 'sdkacceptance', 'SDK Author', 'sdk@example.org')",
    "r <- wb_operation_pack_check(p$path, 'contract', trusted=TRUE)",
    "for (path in r$logs) cat(readLines(path), sep='\\n')",
    "stopifnot(r$qualified, r$tests$discovered == 17L, r$tests$passed == 17L, r$tests$skipped == 0L, r$tests$failed == 0L)"), script)
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
    env = paste0("R_LIBS=", shQuote(paste(c(lib, .libPaths()), collapse = .Platform$path.sep))),
    stdout = log, stderr = log)
  cat(readLines(log), sep = "\n")
  stopifnot(status == 0L)
  TRUE
}

test_operation_pack_sdk_installed_tutorial <- function() {
  lib <- .sdk_installed_library()
  script <- file.path(lib, "scworkbench", "sdk", "operation-packs", "scripts", "tutorial.R")
  log <- tempfile("sdk-installed-tutorial-", fileext = ".log")
  old <- setwd(tempdir()); on.exit(setwd(old), add = TRUE)
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
    env = paste0("R_LIBS=", shQuote(paste(c(lib, .libPaths()), collapse = .Platform$path.sep))),
    stdout = log, stderr = log)
  cat(readLines(log), sep = "\n")
  stopifnot(status == 0L, any(grepl("SDK_INSTALLED_TUTORIAL_OK", readLines(log))))
  TRUE
}

test_operation_pack_sdk_activation_negatives <- function() {
  lib <- .sdk_installed_library()
  log <- tempfile("sdk-activation-negatives-", fileext = ".log")
  script <- file.path(lib, "scworkbench", "sdk", "operation-packs", "scripts", "activation_negatives.R")
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", shQuote(script)),
    env = paste0("R_LIBS=", shQuote(paste(c(lib, .libPaths()), collapse = .Platform$path.sep))),
    stdout = log, stderr = log)
  cat(readLines(log), sep = "\n")
  stopifnot(status == 0L)
  TRUE
}
