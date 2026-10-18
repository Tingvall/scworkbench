test_operation_pack_v3_genomic_registry_contract <- function() {
  root <- tempfile("scwb-genomic-registry-")
  bundle <- wb_init_bundle(root)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("cell_2", "cell_1")
  peaks <- c("chr2:10-20", "chr1:30-40")
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "ATAC", Matrix::Matrix(matrix(c(1, 0, 2, 3),
    nrow = 2L, dimnames = list(peaks, cells)), sparse = TRUE),
    feature_type = "peak")
  wb_matrix_set_genome(bundle, "ATAC", organism = "human",
    genome_build = "hg19", genome_provider = "BSgenome.Hsapiens.UCSC.hg19")
  wb_motif_library_register(bundle, "motifs", "fixture",
    organism = "human", genome_build = "hg19")
  wb_motif_register(bundle, "motifs", "motif_z", motif_id = "z",
    payload_json = '{"pwm":"z"}')
  wb_motif_register(bundle, "motifs", "motif_a", motif_id = "a",
    payload_json = '{"pwm":"a"}')
  wb_motif_match_replace(bundle, "matches", "ATAC", "motifs",
    matches = data.frame(motif_key = c("motif_z", "motif_a"),
      feature_id = peaks), organism = "human", genome_build = "hg19",
    genome_provider = "BSgenome.Hsapiens.UCSC.hg19")
  identity <- scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.test.input.v1", list(matrix_id = "ATAC"))
  input <- list(matrix = list(kind = "matrix", matrix_id = "ATAC",
    feature_id = peaks, cell_id = cells))
  records <- list(matrix = list(descriptor_identity = identity,
    content_identity = identity))
  genomic_decl <- list(kind = "genomic_matrix_source",
    matrix_input = "matrix")
  library_decl <- list(kind = "motif_library",
    library_parameter = "motif_library")
  match_decl <- list(kind = "motif_match_set",
    match_set_parameter = "motif_match_set")
  genomic <- function() scworkbench:::.wb_operation_pack_v3_genomic_registry_snapshot(
    bundle, genomic_decl, input, records, list(), cells)
  library <- function() scworkbench:::.wb_operation_pack_v3_genomic_registry_snapshot(
    bundle, library_decl, input, records,
    list(motif_library = "motifs"), cells)
  matches <- function() scworkbench:::.wb_operation_pack_v3_genomic_registry_snapshot(
    bundle, match_decl, input, records,
    list(motif_match_set = "matches"), cells)
  fingerprint <- function(snapshot, kind)
    scworkbench:::.wb_operation_pack_v3_registry_snapshot_identities(
      snapshot, kind)$content$sha256
  first_genomic <- genomic()
  first_library <- library()
  first_matches <- matches()
  stopifnot(identical(vapply(first_genomic$peaks, `[[`, character(1),
    "feature_id"), peaks),
    identical(vapply(first_library$motifs, `[[`, character(1),
      "motif_key"), c("motif_a", "motif_z")),
    length(first_matches$membership) == 2L,
    is.null(scworkbench:::.wb_operation_pack_v3_genomic_registry_snapshot(
      bundle, match_decl, input, records,
      list(motif_match_set = NULL), cells)$selection))

  # The namespace-export probe is part of the authenticated runtime evidence,
  # not merely a preflight observation. A same-name/version resolution with a
  # different probe must fail both dispatch and promotion currentness checks.
  operation <- list(dependencies = list(list(
    kind = "dynamic_matrix_registry_package", requirement_id = "provider",
    matrix_input = "matrix")))
  preflight <- scworkbench:::.wb_operation_pack_v3_genomic_provider_preflight(
    bundle, operation, input, list(declared = list(), selected = list(),
      dispositions = list(), dynamic = list()))
  check_dispatch <- scworkbench:::.wb_operation_pack_v3_genomic_provider_assert_current
  stopifnot(isTRUE(check_dispatch(bundle, operation, input, preflight)))
  changed_preflight <- preflight
  changed_preflight$dispositions$provider$resolved_package$
    probe_evidence_identity$sha256 <- paste(rep("0", 64L), collapse = "")
  dispatch_error <- tryCatch(check_dispatch(bundle, operation, input,
    changed_preflight), error = base::identity)
  stopifnot(inherits(dispatch_error, "wb_operation_pack_error"),
    identical(dispatch_error$code, "OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED"))

  stage_root <- tempfile("scwb-genomic-provider-stage-")
  dir.create(file.path(stage_root, "registry_reads", "genomic"),
    recursive = TRUE)
  on.exit(unlink(stage_root, recursive = TRUE, force = TRUE), add = TRUE)
  jsonlite::write_json(first_genomic, file.path(stage_root,
    "registry_reads", "genomic", "payload.json"), auto_unbox = TRUE,
    null = "null")
  genomic_identity <- scworkbench:::.wb_operation_pack_v3_registry_snapshot_identities(
    first_genomic, "genomic_matrix_source")
  request <- list(registry_reads = list(list(name = "genomic",
    descriptor = list(kind = "genomic_matrix_source", matrix_input = "matrix",
      matrix_id = "ATAC", content_identity = genomic_identity$content,
      source_identity = genomic_identity$source))),
    inputs = list(list(name = "matrix", descriptor = records$matrix)),
    params = list(), dependency_resolution = list(dynamic = preflight$dynamic))
  check_promotion <- scworkbench:::.wb_operation_pack_v3_genomic_retained_assert_current
  stopifnot(isTRUE(check_promotion(bundle, request, stage_root)))
  request$dependency_resolution$dynamic[[1L]]$resolved_package$
    probe_evidence_identity$sha256 <- paste(rep("0", 64L), collapse = "")
  promotion_error <- tryCatch(check_promotion(bundle, request, stage_root),
    error = base::identity)
  stopifnot(inherits(promotion_error, "wb_operation_pack_error"),
    identical(promotion_error$code, "OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED"))

  # All three generic genomic registry kinds also use fresh boundary reads
  # before an exactly equal private issuance can avoid identity reconstruction.
  declarations <- Map(function(value, name, reader) {
    value$name <- name; value$reader <- reader
    value$category <- "authenticated_core_registry_snapshot"
    value$call_discipline <- "single_use"
    value
  }, list(genomic_decl, library_decl, match_decl),
    c("genomic", "library", "matches"),
    c("read_genomic_matrix_source", "read_motif_library", "read_motif_match_set"))
  registry_operation <- list(registry_reads = unname(declarations))
  registry_params <- list(motif_library = "motifs", motif_match_set = "matches")
  issued <- scworkbench:::.wb_operation_pack_v3_registry_read_records(bundle,
    registry_operation, input, records, registry_params, stage_root, cells,
    "session", "run", "ephemeral", NULL)
  registry_request <- list(registry_reads = issued$records,
    inputs = list(list(name = "matrix", descriptor = records$matrix)),
    execution_capability = list(source_state_identity = NULL))
  attr(registry_request, "operation_pack_v3_registry_observations") <- issued$observations
  check_registry <- function() scworkbench:::.wb_operation_pack_v3_registry_reads_assert_current(
    bundle, registry_operation, input, registry_params, registry_request, cells,
    "session", "run", "ephemeral")
  stopifnot(isTRUE(check_registry()))
  wb_matrix_set_genome(bundle, "ATAC", organism = "human",
    genome_build = "hg19", genome_provider = "BSgenome.Hsapiens.UCSC.hg38")
  stopifnot(inherits(try(check_registry(), silent = TRUE), "try-error"))
  stopifnot(!identical(fingerprint(first_genomic, "genomic_matrix_source"),
    fingerprint(genomic(), "genomic_matrix_source")))
  wb_matrix_set_genome(bundle, "ATAC", organism = "human",
    genome_build = "hg19", genome_provider = "BSgenome.Hsapiens.UCSC.hg19")
  DBI::dbExecute(bundle$con,
    "UPDATE features SET chr='chr9' WHERE matrix_id='ATAC' AND feature_id='chr2:10-20';")
  stopifnot(!identical(fingerprint(first_genomic, "genomic_matrix_source"),
    fingerprint(genomic(), "genomic_matrix_source")))
  wb_motif_register(bundle, "motifs", "motif_z", motif_id = "z",
    payload_json = '{"pwm":"changed"}')
  stopifnot(!identical(fingerprint(first_library, "motif_library"),
    fingerprint(library(), "motif_library")))
  wb_motif_match_replace(bundle, "matches", "ATAC", "motifs",
    matches = data.frame(motif_key = "motif_z", feature_id = peaks[[1L]]),
    organism = "human", genome_build = "hg19",
    genome_provider = "BSgenome.Hsapiens.UCSC.hg19")
  stopifnot(!identical(fingerprint(first_matches, "motif_match_set"),
    fingerprint(matches(), "motif_match_set")))
  duplicated <- first_library
  duplicated$motifs[[2L]] <- duplicated$motifs[[1L]]
  rejected <- try(scworkbench:::.wb_operation_pack_v3_registry_snapshot_identities(
    duplicated, "motif_library"), silent = TRUE)
  stopifnot(inherits(rejected, "try-error"))
  TRUE
}

test_operation_pack_v3_phase7_shared_identity_fixture_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/phase7-genomic-runtime-family-identities.json",
    simplifyVector = FALSE)
  stopifnot(identical(fixture$schema,
    "scworkbench.operation_pack.phase7_identity_fixtures.v1"),
    identical(fixture$canonical_json_scheme,
      "scworkbench.operation_pack.canonical_json.v1"),
    length(fixture$cases) == 8L)
  for (case in fixture$cases) for (identity in case$identities) {
    actual <- .wb_operation_pack_v2_identity_scoped(identity$scheme,
      identity$scope, case$preimage)
    stopifnot(identical(actual$sha256, identity$sha256))
  }
  TRUE
}
