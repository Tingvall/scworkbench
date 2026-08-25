args <- commandArgs(trailingOnly = TRUE)
repo <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
devtools::load_all(repo, quiet = TRUE)

expect_pack_error <- function(expr, code, class = "wb_operation_pack_error") {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, class), identical(error$code, code))
  error
}

template_package <- "scworkbenchOperationPackTemplate"
stopifnot(requireNamespace(template_package, quietly = TRUE))
template_manifest <- system.file("scworkbench", "operation-pack.json", package = template_package)
fixture_root <- file.path(repo, "inst", "protocol", "fixtures", "operation-pack-v1")
python_paths <- file.path(fixture_root, "valid", c(
  "python-hyphen.json", "python-underscore.json", "python-dot.json"
))
runtime_valid_path <- file.path(fixture_root, "runtime", "python-valid.json")
runtime_ambiguous_path <- file.path(fixture_root, "runtime", "python-ambiguous-entry-point.json")
runtime_cross_distribution_path <- file.path(fixture_root, "runtime", "python-cross-dist-entry.json")
schema_path <- file.path(repo, "inst", "protocol", "operation-pack-v1.schema.json")
canonical_identity_path <- file.path(fixture_root, "canonical-identities.json")
unknown_backend_path <- file.path(fixture_root, "invalid", "unknown-backend.json")
stopifnot(all(file.exists(c(template_manifest, python_paths, runtime_valid_path,
                             runtime_ambiguous_path, runtime_cross_distribution_path,
                             schema_path, canonical_identity_path, unknown_backend_path))))

# The machine-readable schema and engine freeze the same two-token backend set.
schema <- jsonlite::read_json(schema_path, simplifyVector = FALSE)
canonical <- jsonlite::read_json(canonical_identity_path, simplifyVector = FALSE)
stopifnot(identical(unlist(schema$properties$backend$enum, use.names = FALSE), c("R", "Python")),
          length(schema$allOf) == 2L,
          identical(digest::digest(file = schema_path, algo = "sha256", serialize = FALSE),
                    canonical$authoritative_schema_sha256),
          identical(canonical$invalidated_r_only_schema_sha256,
                    "1ad99dfdbe13fb7693e615f5b1368be3c638d4e9c1cc01d52996a7109ae68767"))
fixture_digest <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
stopifnot(identical(unname(vapply(python_paths, fixture_digest, character(1))), c(
  canonical$python_reference$declared_name_variants[["scworkbench-python-pack"]]$fixture_sha256,
  canonical$python_reference$declared_name_variants[["scworkbench_python_pack"]]$fixture_sha256,
  canonical$python_reference$declared_name_variants[["scworkbench.python.pack"]]$fixture_sha256
)))
runtime_paths <- file.path(fixture_root, "runtime", names(canonical$runtime_fixture_sha256))
invalid_paths <- file.path(fixture_root, "invalid", names(canonical$invalid_fixture_sha256))
stopifnot(
  identical(unname(vapply(runtime_paths, fixture_digest, character(1))),
            unname(unlist(canonical$runtime_fixture_sha256, use.names = FALSE))),
  identical(unname(vapply(invalid_paths, fixture_digest, character(1))),
            unname(unlist(canonical$invalid_fixture_sha256, use.names = FALSE)))
)

# No-pack parity and accepted Phase 1 R identities are immutable.
core_identity_before <- wb_operation_catalog_identity()
stopifnot(identical(core_identity_before$sha256,
                    "80a340f5845968061fdb8d725b5bc83c7111325c224c5afd326ea08e1d1e99ce"),
          !nrow(wb_operation_packs()))
r_installed <- wb_operation_pack_validate(template_package)$identity
r_structural <- wb_operation_pack_manifest_validate(template_manifest)$identity
stopifnot(
  identical(r_installed$manifest_sha256,
            "c1e9b1d20dd60566b131212c7e6476fc549257573f60578da42098533378e167"),
  identical(r_installed$operation_definition_sha256[["scwbexample::affine_cell_vector"]],
            "90aa8653e0e489af92988d42f19fa849c4859ffc7e7187922095414466050925"),
  identical(r_installed$pack_sha256,
            "4f9212e127ef49c4386b4411cb786811e10b8cd04861828aedb8abf286ef1192"),
  identical(r_installed, r_structural),
  !"distribution" %in% names(r_installed),
  !"entry_point_group" %in% names(r_installed)
)
r_activated <- wb_operation_pack_activate(template_manifest)
stopifnot(identical(r_activated$identity$pack_sha256, r_installed$pack_sha256),
          "scwbexample::affine_cell_vector" %in% wb_list_ops())
r_contract_interface <- getFromNamespace(
  ".wb_prov_current_contract_interface", "scworkbench")(
    "scwbexample::affine_cell_vector")
stopifnot(wb_operation_pack_unload("scwbexample"), !nrow(wb_operation_packs()))

# Python manifests preserve exact declared names while all PEP 503-equivalent
# spellings resolve to one deterministic normalized distribution name.
python_reports <- lapply(python_paths, wb_operation_pack_manifest_validate)
normalized <- vapply(python_reports, function(x) x$identity$distribution$normalized_name, character(1))
definition_hashes <- vapply(python_reports,
  function(x) x$identity$operation_definition_sha256[["scwbpython::affine_cell_vector"]], character(1))
stopifnot(
  identical(normalized, rep("scworkbench-python-pack", 3L)),
  length(unique(definition_hashes)) == 1L,
  identical(unique(definition_hashes),
            "27da0c9063b4e589e8d2b9c1170286accb3770096bea8765079d48e01acb609a"),
  identical(vapply(python_reports, function(x) x$identity$manifest_sha256, character(1)), c(
    "80648679e249bcf67a5e76619b799797ed85ffbcf2bcd65c814f7040ae721410",
    "df90a65e69e0d0a1db1d77097fd371a46a79b8df93e993d0950c70918a31ccfd",
    "0943da52865b5a170b0b9ca64740d3d16c73ac58b19210c35f3e959ea275e43b"
  )),
  identical(vapply(python_reports, function(x) x$identity$pack_sha256, character(1)), c(
    "0108d2e3efde24763fe20ae785ff1ec8eb08e868c8bc5ff23da17ceaefcf396a",
    "6f54ebfb43d5b28ee47abe15dcd28c729e2c5d9301bbaa289d9c86892237783a",
    "385055c61878ce13ba4fffff2cfc5165f4e23227bb95e94d7ad22ae2e2fbe338"
  )),
  all(vapply(python_reports, function(x) identical(x$backend, "Python") &&
    identical(x$entry_point_contract$group, "scworkbench.operation_packs.v1") &&
    identical(x$entry_point_contract$name, "reference-pack"), logical(1)))
)

# PEP 440-equivalent declared/metadata versions and PEP 503-equivalent names
# are admitted, while discovery never imports the callable target.
runtime_valid <- jsonlite::read_json(runtime_valid_path, simplifyVector = FALSE)
python_with_runtime <- wb_operation_pack_manifest_validate(python_paths[[1]], runtime_valid)
version_key <- getFromNamespace(".wb_operation_pack_python_version_key", "scworkbench")
stopifnot(!python_with_runtime$structural_only,
          identical(python_with_runtime$runtime_identity$distribution$metadata_name,
                    "scworkbench_python_pack"),
          identical(python_with_runtime$runtime_identity$entry_point$value,
                    "scworkbench_python_pack.entrypoint:register"),
          identical(version_key("1.0"), version_key("1.0.0")),
          identical(version_key("1.0RC01"), version_key("1.0rc1")),
          identical(version_key("1.0-post1"), version_key("1.0.post01")))

invisible(expect_pack_error(wb_operation_pack_activate(python_paths[[1]], runtime_valid),
  "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED"))

# Every runtime/discovery rejection is typed and leaves process registry and
# committed scientific state byte-identical.
bundle_root <- tempfile("operation_pack_backend_bundle_")
on.exit(unlink(bundle_root, recursive = TRUE, force = TRUE), add = TRUE)
bundle <- wb_init_bundle(bundle_root, overwrite = TRUE)
wb_define_cells(bundle, c("c1", "c2"))
state_identity <- getFromNamespace(".wb_session_source_identity", "scworkbench")
state_before <- state_identity(bundle)$scientific_state_fingerprint
registry_before <- wb_operation_packs()
catalog_before <- wb_operation_catalog_identity()
check_unchanged <- function() {
  stopifnot(identical(state_before, state_identity(bundle)$scientific_state_fingerprint),
            identical(registry_before, wb_operation_packs()),
            identical(catalog_before, wb_operation_catalog_identity()))
}

invisible(expect_pack_error(wb_operation_pack_activate(
  python_paths[[1]], python = file.path(tempdir(), "absent-python")),
  "OPERATION_PACK_RUNTIME_UNAVAILABLE", "wb_operation_pack_runtime_unavailable"))
check_unchanged()

unknown <- jsonlite::read_json(unknown_backend_path, simplifyVector = FALSE)
invisible(expect_pack_error(wb_operation_pack_manifest_validate(unknown),
                            "OPERATION_PACK_BACKEND_UNSUPPORTED"))
check_unchanged()

missing_distribution <- runtime_valid
missing_distribution$distribution <- NULL
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], missing_distribution),
  "OPERATION_PACK_DISTRIBUTION_UNAVAILABLE", "wb_operation_pack_runtime_unavailable"))
check_unchanged()

wrong_name <- runtime_valid
wrong_name$distribution$name <- "unrelated-distribution"
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], wrong_name),
  "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH"))
check_unchanged()

wrong_version <- runtime_valid
wrong_version$distribution$version <- "2.0.0"
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], wrong_version),
  "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH"))
check_unchanged()

missing_entry_point <- runtime_valid
missing_entry_point$entry_points <- list()
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], missing_entry_point),
  "OPERATION_PACK_ENTRY_POINT_UNAVAILABLE", "wb_operation_pack_runtime_unavailable"))
check_unchanged()

ambiguous_entry_point <- jsonlite::read_json(runtime_ambiguous_path, simplifyVector = FALSE)
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], ambiguous_entry_point),
  "OPERATION_PACK_ENTRY_POINT_AMBIGUOUS"))
check_unchanged()

cross_distribution_entry_point <- jsonlite::read_json(runtime_cross_distribution_path, simplifyVector = FALSE)
cross_distribution_report <- wb_operation_pack_manifest_validate(
  python_paths[[1]], cross_distribution_entry_point)
stopifnot(identical(cross_distribution_report$runtime_identity$entry_point$value,
                    "scworkbench_python_pack.entrypoint:register"))
invisible(expect_pack_error(
  wb_operation_pack_activate(python_paths[[1]], cross_distribution_entry_point),
  "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED"))
check_unchanged()

wrong_entry_distribution <- runtime_valid
wrong_entry_distribution$entry_points[[1]]$distribution$name <- "other-pack"
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], wrong_entry_distribution),
  "OPERATION_PACK_ENTRY_POINT_UNAVAILABLE", "wb_operation_pack_runtime_unavailable"))
check_unchanged()

backend_mismatch <- runtime_valid
backend_mismatch$backend <- "R"
invisible(expect_pack_error(wb_operation_pack_manifest_validate(python_paths[[1]], backend_mismatch),
  "OPERATION_PACK_BACKEND_MISMATCH"))
check_unchanged()

# An R/Python substitution can retain the same operation-definition bytes, but
# never the same manifest/pack/contract identity because backend participates
# in source_pack and pack_sha256.
r_manifest <- jsonlite::read_json(template_manifest, simplifyVector = FALSE)
r_as_python <- r_manifest
r_as_python$backend <- "Python"
r_as_python$package$name <- "scworkbenchOperationPackTemplate"
r_as_python$entry_point <- "register-scworkbench-operation-pack"
r_as_python_report <- wb_operation_pack_manifest_validate(r_as_python)
stopifnot(
  identical(r_as_python_report$identity$operation_definition_sha256,
            r_structural$operation_definition_sha256),
  !identical(r_as_python_report$identity$pack_sha256, r_structural$pack_sha256),
  !identical(r_as_python_report$identity$backend, r_structural$backend)
)
python_contract_interface <- r_contract_interface
python_contract_interface$source_pack <- r_as_python_report$identity
python_contract_interface$operation_definition_sha256 <-
  r_as_python_report$identity$operation_definition_sha256[[
    "scwbexample::affine_cell_vector"]]
contract_issue <- getFromNamespace(
  ".wb_prov_operation_contract_incompatibility", "scworkbench")
r_to_python <- contract_issue(r_contract_interface, python_contract_interface,
                              "scwbexample::affine_cell_vector")
python_to_r <- contract_issue(python_contract_interface, r_contract_interface,
                              "scwbexample::affine_cell_vector")
stopifnot(identical(r_to_python$code, "OPERATION_CONTRACT_INCOMPATIBLE"),
          identical(python_to_r$code, "OPERATION_CONTRACT_INCOMPATIBLE"))
registration <- getFromNamespace(".wb_operation_pack_registration", "scworkbench")
dummy_runners <- stats::setNames(list(function(bundle, resolved, effective_cells, inputs, ...) NULL),
                                 names(r_as_python_report$identity$operation_definition_sha256))
invisible(expect_pack_error(registration(r_as_python_report$manifest, dummy_runners),
  "OPERATION_PACK_RUNTIME_UNAVAILABLE", "wb_operation_pack_runtime_unavailable"))
check_unchanged()

python_as_r <- jsonlite::read_json(python_paths[[1]], simplifyVector = FALSE)
python_as_r$backend <- "R"
python_as_r$package <- list(name = "scworkbenchPythonPack", version = "1.0.0")
python_as_r$entry_point <- "reference.pack"
python_as_r_report <- wb_operation_pack_manifest_validate(python_as_r)
stopifnot(
  identical(python_as_r_report$identity$operation_definition_sha256,
            python_reports[[1]]$identity$operation_definition_sha256),
  !identical(python_as_r_report$identity$pack_sha256,
             python_reports[[1]]$identity$pack_sha256),
  !identical(python_as_r_report$identity$backend,
             python_reports[[1]]$identity$backend)
)
check_unchanged()

# Cross-process and R/Python structural admission identity is independent of
# validation order. Structural validation alone leaves Python absent from the
# runtime catalog.
identity_script <- tempfile("operation_pack_backend_identity_", fileext = ".R")
on.exit(unlink(identity_script), add = TRUE)
writeLines(c(
  "args <- commandArgs(trailingOnly=TRUE)",
  "devtools::load_all(args[[1]],quiet=TRUE)",
  "paths <- strsplit(args[[2]],'|',fixed=TRUE)[[1]]",
  "reports <- lapply(paths,wb_operation_pack_manifest_validate)",
  "ids <- lapply(reports,function(x)x$identity)",
  "names(ids) <- vapply(ids,function(x)x$namespace,character(1))",
  "ids <- ids[order(names(ids),vapply(ids,function(x)x$backend,character(1)),method='radix')]",
  "sha <- getFromNamespace('.wb_operation_pack_sha256','scworkbench')",
  "cat(sha(ids),'\\n')",
  "for(x in ids) cat(x$manifest_sha256,x$pack_sha256,'\\n')"
), identity_script)
run_identity <- function(paths) {
  output <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(identity_script), shQuote(repo), shQuote(paste(paths, collapse = "|"))),
    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  stopifnot(identical(status, 0L))
  grep("[0-9a-f]{64}", output, value = TRUE)
}
forward <- run_identity(c(template_manifest, python_paths[[1]]))
reverse <- run_identity(c(python_paths[[1]], template_manifest))
stopifnot(identical(forward, reverse), length(forward) == 3L,
          grepl(canonical$r_python_structural_set_sha256, forward[[1]], fixed = TRUE),
          identical(core_identity_before, wb_operation_catalog_identity()),
          !nrow(wb_operation_packs()))

wb_close_bundle(bundle)
cat("OPERATION_PACK_V1_BACKEND_ADMISSION_OK\n")
