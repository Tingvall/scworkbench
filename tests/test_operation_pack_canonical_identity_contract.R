test_operation_pack_canonical_json_v1_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture_path <- file.path(root, "inst", "protocol", "fixtures",
    "operation-pack-canonical-json-v1", "cases.json")
  fixture <- jsonlite::read_json(fixture_path, simplifyVector = FALSE)
  identities_path <- file.path(root, "inst", "protocol", "fixtures",
    "operation-pack-v1", "canonical-identities.json")
  identities <- jsonlite::read_json(identities_path, simplifyVector = FALSE)
  digest_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
  stopifnot(
    identical(digest_file(file.path(root, "inst", "protocol", "operation-pack-v1.schema.json")),
      identities$authoritative_schema_sha256),
    identical(digest_file(file.path(root, "inst", "protocol", "operation-pack-canonical-json-v1.md")),
      identities$identity_scheme_spec_sha256),
    identical(digest_file(fixture_path), identities$canonical_fixture_corpus_sha256)
  )
  parse <- getFromNamespace(".wb_operation_pack_parse_canonical_json", "scworkbench")
  canonical <- getFromNamespace(".wb_operation_pack_canonical_json", "scworkbench")
  scheme <- getFromNamespace(".wb_operation_pack_identity_scheme", "scworkbench")()
  stopifnot(identical(fixture$identity_scheme, scheme))

  for (case in fixture$valid) {
    observed <- canonical(parse(case$input_json))
    if (!identical(observed, case$canonical_json)) {
      stop(case$name, ": expected ", case$canonical_json, "; observed ", observed,
        call. = FALSE)
    }
  }
  stopifnot(identical(
    canonical(parse(fixture$valid[[1]]$input_json)),
    "{\"a\":1e0,\"b\":1e0,\"c\":1e0,\"z\":1e0}"
  ))
  for (case in fixture$invalid) {
    error <- tryCatch({ canonical(parse(case$input_json)); NULL }, error = identity)
    stopifnot(inherits(error, "wb_operation_pack_error"),
      identical(as.character(error$code), case$code))
  }

  manifest_path <- file.path(root, "inst", "protocol", "fixtures",
    "operation-pack-v1", "valid", "python-hyphen.json")
  integer_identity <- wb_operation_pack_manifest_validate(manifest_path)$identity
  expected <- identities$python_reference$declared_name_variants[["scworkbench-python-pack"]]
  stopifnot(
    identical(integer_identity$manifest_sha256, expected$manifest_sha256),
    identical(integer_identity$operation_definition_sha256[["scwbpython::affine_cell_vector"]],
      identities$python_reference$operation_definition_sha256),
    identical(integer_identity$pack_sha256, expected$pack_sha256)
  )
  text <- paste(readLines(manifest_path, warn = FALSE), collapse = "\n")
  float_text <- sub('"default": 1,', '"default": 1.0,', text, fixed = TRUE)
  float_text <- sub('"min": -1000000,', '"min": -1e6,', float_text, fixed = TRUE)
  float_text <- sub('"max": 1000000,', '"max": 1000000.0,', float_text, fixed = TRUE)
  float_path <- tempfile("operation_pack_numeric_spelling_", fileext = ".json")
  on.exit(unlink(float_path, force = TRUE), add = TRUE)
  writeLines(float_text, float_path, useBytes = TRUE)
  float_identity <- wb_operation_pack_manifest_validate(float_path)$identity
  stopifnot(identical(integer_identity, float_identity),
    identical(integer_identity$identity_scheme, scheme))

  wrong <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  wrong$identity_scheme <- "scworkbench.operation_pack.canonical_json.v999"
  error <- tryCatch(wb_operation_pack_manifest_validate(wrong), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_identity_error"),
    identical(error$code, "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH"))

  accepted <- list(
    kestrel_r_8fc9bb283a7b73c16e8e91f49640bf817cd82be5 =
      Sys.getenv("SCWORKBENCH_KESTREL_PACK_MANIFEST", unset = ""),
    asterion_python_6d46fa9679105f8968bdb2a4a0adf6b51acb14fa =
      Sys.getenv("SCWORKBENCH_ASTERION_PACK_MANIFEST", unset = "")
  )
  for (name in names(accepted)) if (file.exists(accepted[[name]])) {
    observed <- wb_operation_pack_manifest_validate(accepted[[name]])$identity
    expected <- identities$accepted_pack_observations[[name]]
    stopifnot(
      identical(observed$manifest_sha256, expected$manifest_sha256),
      identical(unname(unlist(observed$operation_definition_sha256)),
        expected$operation_definition_sha256),
      identical(observed$pack_sha256, expected$pack_sha256)
    )
  }
  TRUE
}

test_operation_pack_python_original_manifest_authentication_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  source_path <- file.path(root, "inst", "protocol", "fixtures",
    "operation-pack-v1", "valid", "python-hyphen.json")
  work <- tempfile("operation_pack_original_manifest_")
  dir.create(work, recursive = TRUE)
  on.exit(unlink(work, recursive = TRUE, force = TRUE), add = TRUE)
  manifest_path <- file.path(work, "installed-operation-pack.json")
  stopifnot(file.copy(source_path, manifest_path))
  identity <- wb_operation_pack_manifest_validate(manifest_path)$identity
  canonical <- getFromNamespace(".wb_operation_pack_canonical_json", "scworkbench")
  sha256 <- getFromNamespace(".wb_operation_pack_sha256", "scworkbench")
  protocol <- getFromNamespace(".wb_pyproto_version", "scworkbench")()
  artifact <- list(kind = "installed_distribution", scheme =
    "python-installed-distribution-tree-sha256-v1", sha256 = paste(rep("a", 64L), collapse = ""))
  manifest_source <- list(
    scheme = "python-installed-operation-pack-manifest-v1",
    distribution_relative_path = "scworkbench_python_pack/operation-pack.json",
    bytes_sha256 = digest::digest(file = manifest_path, algo = "sha256", serialize = FALSE),
    manifest_sha256 = identity$manifest_sha256
  )
  distribution <- list(
    declared_name = "scworkbench-python-pack",
    normalized_name = "scworkbench-python-pack", version = "1.0.0rc1",
    metadata_name = "scworkbench-python-pack", metadata_version = "1.0.0rc1",
    artifact_identity = artifact
  )
  runtime <- list(
    schema = "scworkbench.operation_pack_runtime.python.v1", backend = "Python",
    identity_scheme = identity$identity_scheme,
    manifest_source = manifest_source,
    distribution = distribution,
    entry_point = list(group = "scworkbench.operation_packs.v1", name = "reference-pack",
      value = "fixture:register"),
    interpreter = list(implementation = "CPython", version = "3.12", abi = "cp312",
      platform = "fixture", executable_sha256 = paste(rep("b", 64L), collapse = "")),
    dependencies = list(scheme = "python-distribution-set-v1", distributions = list(),
      sha256 = sha256(list())),
    pybench = list(protocol = protocol)
  )
  discovery <- list(
    schema = "pybench.operation_pack_discovery.v1",
    manifest_identity = identity,
    manifest_source = manifest_source,
    distribution = distribution,
    entry_point = list(group = "scworkbench.operation_packs.v1", name = "reference-pack",
      value = "fixture:register"),
    runtime_attestation = runtime
  )
  output_path <- file.path(work, "discovery.json")
  args_path <- file.path(work, "args.txt")
  writeLines(canonical(discovery), output_path, useBytes = TRUE)
  driver <- file.path(work, "python")
  writeLines(c("#!/bin/sh", 'printf "%s\\n" "$@" > "$SCWB_AUTH_ARGS"',
    'cat "$SCWB_AUTH_OUTPUT"'), driver)
  Sys.chmod(driver, "0755")
  old <- Sys.getenv(c("SCWB_AUTH_ARGS", "SCWB_AUTH_OUTPUT"), unset = NA_character_)
  on.exit({
    for (name in names(old)) {
      if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, setNames(list(old[[name]]), name))
    }
  }, add = TRUE)
  Sys.setenv(SCWB_AUTH_ARGS = args_path, SCWB_AUTH_OUTPUT = output_path)

  before_packs <- wb_operation_packs()
  before_ops <- wb_list_ops()
  before_semantic <- wb_semantic_catalog()$catalog_sha256
  activated <- wb_operation_pack_activate(manifest_path, python = driver, timeout_seconds = 10)
  args <- readLines(args_path, warn = FALSE)
  stopifnot(identical(activated$identity, identity),
    identical(normalizePath(args[[length(args)]], winslash = "/", mustWork = TRUE),
      normalizePath(manifest_path, winslash = "/", mustWork = TRUE)))
  stopifnot(wb_operation_pack_unload("scwbpython"), file.exists(manifest_path))
  stopifnot(identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_semantic_catalog()$catalog_sha256, before_semantic))

  wrong_source <- discovery
  wrong_source$manifest_source$bytes_sha256 <- paste(rep("f", 64L), collapse = "")
  writeLines(canonical(wrong_source), output_path, useBytes = TRUE)
  error <- tryCatch(
    wb_operation_pack_activate(manifest_path, python = driver, timeout_seconds = 10),
    error = base::identity)
  stopifnot(inherits(error, "wb_operation_pack_identity_error"),
    identical(error$code, "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH"),
    identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_semantic_catalog()$catalog_sha256, before_semantic))

  wrong_runtime_scheme <- discovery
  wrong_runtime_scheme$runtime_attestation$identity_scheme <-
    "scworkbench.operation_pack.canonical_json.v999"
  writeLines(canonical(wrong_runtime_scheme), output_path, useBytes = TRUE)
  error <- tryCatch(
    wb_operation_pack_activate(manifest_path, python = driver, timeout_seconds = 10),
    error = base::identity)
  stopifnot(inherits(error, "wb_operation_pack_identity_error"),
    identical(error$code, "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH"),
    identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_semantic_catalog()$catalog_sha256, before_semantic))

  bad <- discovery
  bad$manifest_identity$pack_sha256 <- paste(rep("0", 64L), collapse = "")
  writeLines(canonical(bad), output_path, useBytes = TRUE)
  error <- tryCatch(
    wb_operation_pack_activate(manifest_path, python = driver, timeout_seconds = 10),
    error = base::identity)
  if (!inherits(error, "wb_operation_pack_identity_error") ||
      !identical(error$code, "OPERATION_PACK_IDENTITY_MISMATCH")) {
    stop("unexpected identity failure: class=", paste(class(error), collapse = "/"),
      " code=", error$code %||% "<none>", " message=", conditionMessage(error), call. = FALSE)
  }
  stopifnot(
    identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_semantic_catalog()$catalog_sha256, before_semantic))

  writeLines(canonical(discovery), output_path, useBytes = TRUE)
  original_text <- readLines(manifest_path, warn = FALSE)
  tampered_text <- sub('"default": 1,', '"default": 2,', original_text, fixed = TRUE)
  writeLines(tampered_text, manifest_path, useBytes = TRUE)
  error <- tryCatch(
    wb_operation_pack_activate(manifest_path, python = driver, timeout_seconds = 10),
    error = base::identity)
  stopifnot(inherits(error, "wb_operation_pack_identity_error"),
    identical(error$code, "OPERATION_PACK_IDENTITY_MISMATCH"),
    identical(wb_operation_packs(), before_packs), identical(wb_list_ops(), before_ops),
    identical(wb_semantic_catalog()$catalog_sha256, before_semantic))
  writeLines(original_text, manifest_path, useBytes = TRUE)

  parsed <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  error <- tryCatch(wb_operation_pack_activate(parsed, python = driver), error = base::identity)
  if (!inherits(error, "wb_operation_pack_identity_error") ||
      !identical(error$code, "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED")) {
    stop("unexpected source failure: class=", paste(class(error), collapse = "/"),
      " code=", error$code %||% "<none>", " message=", conditionMessage(error), call. = FALSE)
  }
  stopifnot(
    identical(wb_operation_packs(), before_packs))
  TRUE
}
