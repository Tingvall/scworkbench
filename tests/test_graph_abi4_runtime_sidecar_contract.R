test_graph_abi4_runtime_sidecar_scheme_contract <- function() {
  ns <- asNamespace("scworkbench")
  scoped <- get(".wb_operation_pack_v2_identity_scoped", ns)
  digest <- paste(rep("a", 64L), collapse = "")
  make_identity <- function(scheme, scope = NULL) {
    result <- list(scheme = scheme, sha256 = digest)
    if (!is.null(scope)) result$scope <- scope
    result
  }
  python <- file.path(R.home("bin"), "R")
  distribution <- make_identity("scworkbench.operation_pack.content.v1")
  request <- list(pack_abi_version = "4",
    request_identity = make_identity("scworkbench.operation_pack.transition_request.v4",
      "request excluding request_identity"),
    execution_capability = list(capability_identity = make_identity(
      "scworkbench.operation_pack.capability.v4", "capability excluding capability_identity")),
    operation_authentication = list(operation_definition_identity = make_identity(
      "scworkbench.operation_pack.definition.v4")))
  registration <- list(identity = list(distribution_identity = distribution),
    runtime_config = list(python = python))
  value <- list(schema = "pybench.operation_pack.python_runtime.v4", backend = "Python",
    distribution_identity = distribution, request_identity = request$request_identity,
    capability_identity = request$execution_capability$capability_identity,
    operation_definition_identity = request$operation_authentication$operation_definition_identity,
    interpreter = list(implementation = "CPython", version = "fixture", abi = "fixture",
      platform = "fixture", executable_sha256 = get(".wb_operation_pack_v2_file_sha256", ns)(python)),
    seed = list(status = "not_declared", value = NULL),
    device = list(type = "cpu", descriptor = "fixture"))
  rehash <- function(value) {
    value$runtime_identity <- NULL
    value$runtime_identity <- scoped("pybench.operation_pack.python_runtime.v4",
      "python runtime sidecar excluding runtime_identity", value)
    value
  }
  value <- rehash(value)
  audit <- get(".wb_operation_pack_v3_python_sidecar_audit", ns)
  stopifnot(isTRUE(audit(value, registration, request)))
  for (field in c("schema", "runtime_identity", "request_identity", "interpreter", "seed")) {
    altered <- value
    if (field == "schema") altered$schema <- "pybench.operation_pack.python_runtime.v5"
    if (field == "request_identity") {
      altered$request_identity$scheme <- "unknown.scheme"
      # Matching a pack-supplied request does not authenticate an unknown scheme.
      request$request_identity <- altered$request_identity
    }
    if (field == "interpreter") altered$interpreter$undeclared <- "host-path"
    if (field == "seed") altered$seed$value <- "not_an_integer"
    altered <- rehash(altered)
    if (field == "runtime_identity") altered$runtime_identity$scheme <- "unknown.scheme"
    rejected <- tryCatch(audit(altered, registration, request), error = identity)
    if (!inherits(rejected, "error")) stop(paste("Sidecar attack was accepted:", field))
    request$request_identity <- value$request_identity
  }
  TRUE
}
