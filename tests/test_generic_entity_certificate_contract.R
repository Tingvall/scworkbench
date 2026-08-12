.certificate_json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)

.certificate_fingerprint <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
                           full.names = TRUE, include.dirs = FALSE, no.. = TRUE))
  list(paths = substring(files, nchar(normalizePath(root, winslash = "/", mustWork = TRUE)) + 2L),
       sha256 = vapply(files, .wb_prov_sha256_file, character(1)))
}

test_generic_entity_certificate_contract <- function() {
  required <- c("BPCells", "Matrix", "irlba", "uwot", "rhdf5")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  root <- tempfile("scwb_entity_certificate_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("cell_", seq_len(24L)); genes <- paste0("gene_", seq_len(14L))
  wb_define_cells(b, cells)
  counts <- outer(seq_along(genes), seq_along(cells), function(i, j) as.integer((i * 11L + j * 5L) %% 23L))
  counts <- Matrix::Matrix(counts, sparse = TRUE, dimnames = list(genes, cells))
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")
  source_identity <- list(schema = "scworkbench.source_identity.v2", inputs = list(list(
    scope = "public_file", source_id = "geo_counts", path = "/outside/fixture_counts.mtx.gz",
    uri = "https://example.invalid/GSE_fixture", accession = "GSE_fixture", role = "counts",
    format = "10x_mtx", sha256 = paste(rep("a", 64L), collapse = ""), bundled = FALSE
  )))
  .wb_ingest_report_artifact(b, "core", "atomic", list(n_cells = length(cells)), list(), list(),
    created_by = "certificate-test", source = "certificate-test", matrix_ids = "RNA_counts",
    source_identity = source_identity)

  norm <- wb_session_run_op(wb_session_new(), b, "matrix_log_normalize", inputs = list(
    matrix = "RNA_counts", cell_set = "all", min_cells = 2L,
    output_matrix_id = "RNA_log_norm.certificate", overwrite = TRUE))
  hvg <- wb_session_run_op(norm$session, b, "hvg_select", inputs = list(
    matrix = wb_ref_run(norm$run$run_id, "matrix"), cell_set = "all", min_cells = 2L,
    n_features = 10L, method = "vst", chunk_size = 4L))
  pca <- wb_session_run_op(hvg$session, b, "pca_fit", inputs = list(
    matrix = wb_ref_run(norm$run$run_id, "matrix"),
    features = wb_ref_run(hvg$run$run_id, "selected_features"), cell_set = "all",
    min_cells = 2L, n_components = 4L, backend = "irlba", seed = 11L,
    space_id_out = "rna.pca.certificate", overwrite = TRUE, max_dense_gb = 1))
  pca_promoted <- wb_session_promote_current(b, pca$session,
    outputs = c("loadings", "variance", "fit_summary"), created_by = "certificate-test")
  stopifnot(all(pca_promoted$promoted$status[pca_promoted$promoted$output %in% c("loadings", "variance", "fit_summary")] == "ok"))
  umap <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs = list(
    space = "rna.pca.certificate", cell_set = "all", min_cells = 2L, dims = 1:4,
    space_id_out = "rna.umap.certificate", n_neighbors = 4L, min_dist = 0.1,
    metric = "euclidean", nn_method = "annoy", seed = 17L))
  umap_promoted <- wb_session_promote_current(b, umap$session,
    outputs = c("model", "space_2d"), created_by = "certificate-test")
  stopifnot(all(umap_promoted$promoted$status[umap_promoted$promoted$output %in% c("model", "space_2d")] == "ok"))

  source_id <- wb_prov_source_inputs(b)$source_id[[1L]]
  artifact_id <- as.character(umap_promoted$promoted$artifact_id[umap_promoted$promoted$output == "space_2d"][[1L]])
  model_binding <- DBI::dbGetQuery(b$con,
    "SELECT entity_id FROM prov_run_entity_bindings WHERE run_id = ? AND entity_kind = 'model_ref' ORDER BY entity_id;",
    params = list(umap$run$run_id))
  model_id <- if (nrow(model_binding)) as.character(model_binding$entity_id[[1L]]) else as.character(umap_promoted$promoted$artifact_id[umap_promoted$promoted$output == "model"][[1L]])
  subjects <- list(
    external_source = source_id, matrix = "RNA_counts", space = "rna.umap.certificate",
    model = model_id, artifact = artifact_id, run = umap$run$run_id
  )
  certificates <- Map(function(kind, id) wb_entity_certificate(b, kind, id), names(subjects), subjects)
  stopifnot(length(certificates) == 6L,
    all(vapply(certificates, function(x) identical(x$schema, "scworkbench.provenance.entity_certificate.v1"), logical(1))),
    identical(unname(vapply(certificates, function(x) x$subject$kind, character(1))), names(subjects)))

  dag <- wb_prov_bundle_dag(b, include_superseded = TRUE)
  source_node <- paste0("external_source:", source_id)
  terminal_node <- "space:rna.umap.certificate"
  reachable <- .wb_certificate_reachable(dag$edges, source_node, upstream = FALSE)
  stopifnot(terminal_node %in% reachable,
    certificates$space$relationships$upstream$count > 0L,
    certificates$matrix$details$dimensions$features == length(genes),
    certificates$space$details$dimensions$cells == length(cells),
    identical(certificates$space$details$output_space_id$value, "rna.umap.certificate"),
    identical(certificates$space$details$source_space_id$value, "rna.pca.certificate"),
    identical(certificates$model$producer$status, "available"),
    identical(certificates$artifact$producer$status, "available"))

  run_cert <- certificates$run
  stopifnot(run_cert$details$operation$name == "umap_fit",
    identical(run_cert$details$parameters$status, "available"),
    identical(run_cert$details$symbolic_inputs$status, "available"),
    identical(run_cert$details$resolved_execution_inputs$status, "available"),
    identical(run_cert$details$runtime_attestation$status, "available"),
    length(run_cert$details$outputs$items) >= 2L,
    length(run_cert$details$snapshots) >= 1L)

  all_json <- vapply(certificates, .certificate_json, character(1))
  stopifnot(identical(all_json, vapply(Map(function(k, i) wb_entity_certificate(b, k, i), names(subjects), subjects), .certificate_json, character(1))),
    !any(grepl(normalizePath(dirname(root), winslash = "/", mustWork = TRUE), all_json, fixed = TRUE)),
    !any(grepl('"coordinates"[[:space:]]*:', all_json)),
    !any(grepl('"input_space_id"[[:space:]]*:', all_json)))

  wb_entity_supersede(b, "space", "rna.umap.certificate", "rna.pca.certificate",
    reason = "historical certificate fixture", created_by = "certificate-test")
  historical <- wb_entity_certificate(b, "space", "rna.pca.certificate")
  current <- wb_entity_certificate(b, "space", "rna.umap.certificate")
  stopifnot(historical$subject$lifecycle_state == "superseded",
    length(historical$lifecycle$supersessions$items) == 1L,
    current$subject$lifecycle_state == "current")

  missing_error <- try(wb_entity_certificate(b, "space", "does-not-exist"), silent = TRUE)
  mismatch_error <- try(wb_entity_certificate(b, "matrix", "rna.umap.certificate"), silent = TRUE)
  stopifnot(inherits(missing_error, "try-error"), grepl("ENTITY_CERTIFICATE_NOT_FOUND", missing_error),
    inherits(mismatch_error, "try-error"), grepl("ENTITY_CERTIFICATE_NOT_FOUND", mismatch_error))

  finalized <- wb_finalize_recipient_bundle(b); stopifnot(isTRUE(finalized$ready))
  wb_close_bundle(b)
  before <- .certificate_fingerprint(root)
  ro <- wb_open_bundle(root, read_only = TRUE)
  ro_json <- vapply(Map(function(k, i) wb_entity_certificate(ro, k, i), names(subjects), subjects), .certificate_json, character(1))
  stopifnot(!any(grepl("entity_certificate", DBI::dbListTables(ro$con), fixed = TRUE)))
  wb_close_bundle(ro)
  after <- .certificate_fingerprint(root)
  stopifnot(identical(before, after))

  relocated <- tempfile("scwb_entity_certificate_relocated_")
  dir.create(relocated); stopifnot(file.copy(root, relocated, recursive = TRUE))
  relocated_root <- file.path(relocated, basename(root))
  rb <- wb_open_bundle(relocated_root, read_only = TRUE)
  relocated_json <- vapply(Map(function(k, i) wb_entity_certificate(rb, k, i), names(subjects), subjects), .certificate_json, character(1))
  wb_close_bundle(rb); unlink(relocated, recursive = TRUE, force = TRUE)
  stopifnot(identical(ro_json, relocated_json))
  b <- wb_open_bundle(root, read_only = TRUE)
  TRUE
}

test_generic_entity_certificate_corruption_contract <- function() {
  root <- tempfile("scwb_entity_certificate_corrupt_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  wb_define_cells(b, c("c1", "c2"))
  wb_attach_matrix(b, "RNA_counts", matrix(1:4, 2, dimnames = list(c("g1", "g2"), c("c1", "c2"))))
  clean <- wb_entity_certificate(b, "matrix", "RNA_counts")
  stopifnot(identical(clean$identity$verification_status, "content_verified"))
  fragment <- DBI::dbGetQuery(b$con, "SELECT path FROM matrix_fragments WHERE matrix_id = 'RNA_counts' ORDER BY fragment_id LIMIT 1;")$path[[1L]]
  payload_files <- list.files(file.path(root, fragment), recursive = TRUE, full.names = TRUE)
  payload_files <- payload_files[!dir.exists(payload_files)]
  stopifnot(length(payload_files) > 0L)
  con <- file(payload_files[[1L]], open = "ab"); writeBin(as.raw(0L), con); close(con)
  DBI::dbExecute(b$con, "UPDATE entity_lifecycle SET identity_hash = 'corrupted' WHERE entity_kind = 'matrix' AND entity_id = 'RNA_counts';")
  cert <- wb_entity_certificate(b, "matrix", "RNA_counts")
  stopifnot(identical(cert$identity$verification_status, "content_identity_mismatch"),
    identical(cert$identity$observed$status, "corrupt"),
    identical(cert$lifecycle$record$value$identity_hash, "corrupted"))
  binding <- DBI::dbGetQuery(b$con,
    "SELECT * FROM prov_run_entity_bindings WHERE entity_kind = 'matrix' AND entity_id = 'RNA_counts' AND relationship_type = 'MATERIALIZES' LIMIT 1;")
  stopifnot(nrow(binding) == 1L)
  binding$binding_name <- paste0(binding$binding_name, "_malformed_duplicate")
  DBI::dbWriteTable(b$con, "prov_run_entity_bindings", binding, append = TRUE)
  malformed <- wb_entity_certificate(b, "matrix", "RNA_counts")
  stopifnot(identical(malformed$producer$status, "corrupt"),
    identical(malformed$producer$reason, "producer_binding_is_not_unique"))
  TRUE
}
