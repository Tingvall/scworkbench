# Isolated SDK conformance process: only disposable scaffold installations.
library(scworkbench)
root <- tempfile("sdk-activation-"); dir.create(root)
lib <- file.path(root, "library"); dir.create(lib); .libPaths(c(lib, .libPaths()))
install <- function(project) {
  log <- file.path(root, paste0(project$package, ".log"))
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(project$path)), stdout = log, stderr = log)
  stopifnot(status == 0L)
  system.file("scworkbench", "operation-pack.json", package = project$package, lib.loc = lib)
}
make <- function(package, namespace) wb_operation_pack_scaffold(file.path(root, package),
  package, namespace, "SDK Author", "sdk@example.org")
before <- wb_list_ops()
first <- make("scwbSdkActivation", "sdkactivation")
manifest <- install(first)
loadNamespace(first$package)
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_validate(first$package)
stopifnot(identical(before, wb_list_ops()))
wb_operation_pack_activate(manifest)
after <- wb_list_ops()
reject <- function(FUN, substring) {
  state <- wb_list_ops()
  error <- tryCatch({FUN(); NULL}, error = identity)
  if (inherits(error, "error")) cat("OBSERVED ", paste(error$code, conditionMessage(error)), "\n", sep = "")
  stopifnot(inherits(error, "error"), grepl(substring, paste(error$code, conditionMessage(error))),
    identical(state, wb_list_ops()))
  cat("REJECTED ", conditionMessage(error), "\n", sep = "")
}
# A caller-supplied source copy/pin is not the installed authenticated manifest.
reject(function() wb_operation_pack_activate(first$manifest), "MANIFEST")
collision <- make("scwbSdkCollision", "sdkactivation")
install(collision)
reject(function() wb_operation_pack_load(collision$package), "NAMESPACE_DUPLICATE")
abi <- make("scwbSdkAbiMismatch", "sdkabimismatch")
value <- jsonlite::read_json(abi$manifest)
value$compatibility$pack_abi <- list(minimum = "2", maximum = "2")
jsonlite::write_json(value, abi$manifest, auto_unbox = TRUE)
install(abi)
reject(function() wb_operation_pack_load(abi$package), "(PROTOCOL_INCOMPATIBLE|ABI interval|validation)")
dependency <- make("scwbSdkDependency", "sdkdependency")
value <- jsonlite::read_json(dependency$manifest)
value$operations[[1]]$dependencies <- list(list(requirement_id = "missing",
  kind = "r_package", name = "scwbSdkImpossibleDependency987654", disposition = "required",
  version = list(scheme = "r_package_version_constraint_v1", specifier = ">=0.1.0"),
  import_probe = "scwbSdkImpossibleDependency987654"))
jsonlite::write_json(value, dependency$manifest, auto_unbox = TRUE)
install(dependency)
wb_operation_pack_load(dependency$package)
fixture <- wb_operation_pack_sdk_fixture(file.path(root, "source.bundle"))
state <- wb_operation_pack_sdk_state(fixture$bundle)
result <- wb_operation_pack_sdk_run(fixture$bundle, "sdkdependency::matrix_cell_sum",
  list(matrix = "counts", cell_set = "all", min_cells = 1L))
stopifnot(!result$ok, result$unchanged, identical(state,
  wb_operation_pack_sdk_state(fixture$bundle)),
  grepl("DEPENDENCY", paste(result$error$code, conditionMessage(result$error))))
wb_close_bundle(fixture$bundle)
cat("SDK_ACTIVATION_NEGATIVES_OK inert=TRUE wrong_manifest=reject collision=reject abi=reject missing_dependency=reject unchanged=TRUE\n")
