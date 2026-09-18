.request01_snapshot_ids <- function(x) {
  as.character(jsonlite::fromJSON(as.character(x)[1], simplifyVector = TRUE))
}

.request01_has_path <- function(edges, from, to) {
  visited <- character(0)
  queue <- as.character(from)
  while (length(queue)) {
    current <- queue[[1L]]
    queue <- queue[-1L]
    if (identical(current, to)) return(TRUE)
    if (current %in% visited) next
    visited <- c(visited, current)
    next_ids <- unique(as.character(edges$to[as.character(edges$from) == current]))
    queue <- c(queue, next_ids[nzchar(next_ids) & !(next_ids %in% visited)])
  }
  FALSE
}

.request01_bundle_fingerprint <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
                           full.names = TRUE, include.dirs = FALSE, no.. = TRUE))
  info <- file.info(files)
  list(
    paths = substring(files, nchar(normalizePath(root, winslash = "/", mustWork = TRUE)) + 2L),
    sizes = as.numeric(info$size),
    modes = as.character(info$mode),
    sha256 = vapply(files, .wb_prov_sha256_file, character(1))
  )
}

.request01_sqlite_sidecars <- function(root) {
  db <- file.path(root, "db", "app.sqlite")
  sort(c(paste0(db, "-wal"), paste0(db, "-shm"), paste0(db, "-journal"))[
    file.exists(c(paste0(db, "-wal"), paste0(db, "-shm"), paste0(db, "-journal")))
  ])
}

.request01_run_literal_audit_wrapper <- function(root) {
  repo <- normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = "."),
                        winslash = "/", mustWork = TRUE)
  wrapper <- file.path(repo, "containers", "apptainer", "recipient_readonly_audit.sh")
  shim_dir <- tempfile("request01_singularity_shim_")
  dir.create(shim_dir)
  on.exit(unlink(shim_dir, recursive = TRUE, force = TRUE), add = TRUE)
  shim <- file.path(shim_dir, "singularity")
  writeLines(c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "bind_spec=''",
    "expression=''",
    "while (($#)); do",
    "  case \"$1\" in",
    "    --bind) bind_spec=$2; shift 2 ;;",
    "    Rscript) shift; [[ \"${1:-}\" == '-e' ]]; expression=$2; break ;;",
    "    *) shift ;;",
    "  esac",
    "done",
    "host_bundle=${bind_spec%%:*}",
    "load_source=\"devtools::load_all(Sys.getenv('SCWORKBENCH_TEST_SOURCE_ROOT'), quiet=TRUE)\"",
    "expression=${expression//library(scworkbench)/$load_source}",
    "expression=${expression//\\/audit_bundle/$host_bundle}",
    "exec Rscript -e \"$expression\""
  ), shim)
  Sys.chmod(shim, mode = "0755")
  old_path <- Sys.getenv("PATH")
  old_root <- Sys.getenv("SCWORKBENCH_TEST_SOURCE_ROOT", unset = NA_character_)
  on.exit({
    Sys.setenv(PATH = old_path)
    if (is.na(old_root)) Sys.unsetenv("SCWORKBENCH_TEST_SOURCE_ROOT")
    else Sys.setenv(SCWORKBENCH_TEST_SOURCE_ROOT = old_root)
  }, add = TRUE)
  Sys.setenv(PATH = paste(shim_dir, old_path, sep = .Platform$path.sep),
             SCWORKBENCH_TEST_SOURCE_ROOT = repo)
  system2("bash", c(shQuote(wrapper), "unused-development-image.sif", shQuote(root)))
}

test_canonical_composed_dag_snapshot_lookup_contract <- function() {
  required <- c("BPCells", "Matrix", "irlba", "uwot", "rhdf5", "devtools")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  root <- tempfile("scwb_request01_canonical_dag_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(24L))
  genes <- paste0("gene_", seq_len(14L))
  wb_define_cells(b, cells)
  counts <- outer(seq_along(genes), seq_along(cells), function(i, j) {
    as.integer((i * 11L + j * 5L + (i <= 5L) * (j <= 12L) * 13L) %% 23L)
  })
  counts <- Matrix::Matrix(counts, sparse = TRUE, dimnames = list(genes, cells))
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")
  source_identity <- list(
    dataset_name = "request01 historical ingestion",
    inputs = list(list(
      path = "recipient_fixture_counts.mtx.gz",
      file_name = "recipient_fixture_counts.mtx.gz",
      sha256 = paste(rep("a", 64L), collapse = ""),
      format = "10x_mtx", role = "counts", sample_id = "request01"
    ))
  )
  .wb_ingest_report_artifact(
    b, "core", "atomic", list(n_cells = length(cells)), list(), list(),
    created_by = "request01", source = "request01", matrix_ids = "RNA_counts",
    source_identity = source_identity
  )
  source_pair <- unique(wb_prov_source_inputs(b)[c("snapshot_id", "run_id")])
  matrix_producer <- DBI::dbGetQuery(b$con, paste(
    "SELECT snapshot_id,run_id FROM prov_run_entity_bindings WHERE entity_kind='matrix'",
    "AND entity_id='RNA_counts' AND relationship_type IN ('PRODUCES','MATERIALIZES');"
  ))
  aggregate_run <- DBI::dbGetQuery(b$con,
    "SELECT snapshot_id,run_id FROM prov_runs WHERE op_name='ingest_apply';")
  stopifnot(nrow(source_pair) == 2L, nrow(matrix_producer) == 1L, nrow(aggregate_run) == 1L,
            all(paste(source_pair$snapshot_id, source_pair$run_id) %in%
                  paste(rbind(matrix_producer, aggregate_run)$snapshot_id,
                        rbind(matrix_producer, aggregate_run)$run_id)))

  norm <- wb_session_run_op(wb_session_new(), b, "matrix_log_normalize", inputs = list(
    matrix = "RNA_counts", cell_set = "all", min_cells = 2L,
    output_matrix_id = "RNA_log_norm.request01", overwrite = TRUE
  ))
  pca <- wb_session_run_op(norm$session, b, "pca_fit", inputs = list(
    matrix = wb_ref_run(norm$run$run_id, "matrix"),
    feature_ids = genes[seq_len(10L)],
    cell_set = "all", min_cells = 2L, n_components = 4L, backend = "irlba",
    seed = 11L, space_id_out = "rna.pca.request01", overwrite = TRUE, max_dense_gb = 1
  ))
  pca_promotion <- wb_session_promote_current(
    b, pca$session, outputs = c("loadings", "variance", "fit_summary"),
    created_by = "request01"
  )
  pca_terminal <- pca_promotion$promoted$output %in% c("loadings", "variance", "fit_summary")
  if (!all(pca_promotion$promoted$status[pca_terminal] == "ok")) {
    stop("Request 01 PCA promotion failed: ",
         paste(capture.output(print(pca_promotion$promoted)), collapse = "\n"), call. = FALSE)
  }

  fit_branch <- function(space_id, seed) {
    fit <- wb_session_run_op(wb_session_new(), b, "umap_fit", inputs = list(
      space = "rna.pca.request01", cell_set = "all", min_cells = 2L, dims = 1:4,
      space_id_out = space_id, n_neighbors = 4L, min_dist = 0.1,
      metric = "euclidean", nn_method = "annoy", seed = seed
    ))
    promoted <- wb_session_promote_current(
      b, fit$session, outputs = c("model", "space_2d"), created_by = "request01"
    )
    umap_terminal <- promoted$promoted$output %in% c("model", "space_2d")
    if (!all(promoted$promoted$status[umap_terminal] == "ok")) {
      stop("Request 01 UMAP promotion failed: ",
           paste(capture.output(print(promoted$promoted)), collapse = "\n"), call. = FALSE)
    }
    list(run = fit$run, promotion = promoted)
  }
  branch_a <- fit_branch("rna.umap.request01.a", 17L)
  branch_b <- fit_branch("rna.umap.request01.b", 19L)
  wb_entity_supersede(
    b, "space", "rna.umap.request01.b", "rna.umap.request01.a",
    reason = "Request 01 current-view filter fixture", created_by = "request01"
  )

  history <- wb_prov_bundle_dag(b, include_superseded = TRUE)
  current <- wb_prov_bundle_dag(b, include_superseded = FALSE)
  stopifnot(
    identical(history$schema, "scworkbench.provenance.bundle_dag.v2"),
    nrow(history$nodes) == length(unique(history$nodes$id)),
    !anyDuplicated(history$edges$semantic_key),
    "space:rna.umap.request01.a" %in% history$nodes$id,
    "space:rna.umap.request01.b" %in% history$nodes$id,
    !"space:rna.umap.request01.a" %in% current$nodes$id,
    "space:rna.umap.request01.b" %in% current$nodes$id
  )
  source_node <- history$nodes$id[history$nodes$node_type == "external_source"][[1L]]
  stopifnot(
    .request01_has_path(history$edges, source_node, "space:rna.umap.request01.a"),
    .request01_has_path(history$edges, source_node, "space:rna.umap.request01.b")
  )
  matrix_node <- history$nodes[history$nodes$id == "matrix:RNA_counts", , drop = FALSE]
  stopifnot(nrow(matrix_node) == 1L,
            length(.request01_snapshot_ids(matrix_node$snapshot_ids)) >= 2L)

  focused <- wb_prov_bundle_dag(
    b, run_id = branch_b$run$run_id, direction = "upstream",
    include_superseded = TRUE
  )
  stopifnot(!anyDuplicated(focused$nodes$id), !anyDuplicated(focused$edges$semantic_key),
            source_node %in% focused$nodes$id)
  kg <- wb_kg_provenance_graph(b)
  stopifnot(!anyDuplicated(kg$nodes$id), !anyDuplicated(kg$edges$id))

  duplicated_edge <- rbind(
    .wb_prov_bundle_edge("run:parent", "run:child", "DERIVED_FROM", "space", "child", "snapshot:b"),
    .wb_prov_bundle_edge("run:parent", "run:child", "DERIVED_FROM", "space", "child", "snapshot:a")
  )
  merged_edge <- .wb_prov_canonicalize_edges(duplicated_edge)
  stopifnot(nrow(merged_edge) == 1L,
            identical(.request01_snapshot_ids(merged_edge$snapshot_ids), c("snapshot:a", "snapshot:b")))
  conflicting_node <- rbind(
    .wb_prov_bundle_node("space:conflict", "space", label = "one", snapshot_id = "snapshot:a"),
    .wb_prov_bundle_node("space:conflict", "space", label = "two", snapshot_id = "snapshot:b")
  )
  node_error <- tryCatch(.wb_prov_canonicalize_nodes(conflicting_node), error = identity)
  stopifnot(inherits(node_error, "scworkbench_provenance_composition_error"),
            identical(node_error$code, "PROVENANCE_NODE_CONFLICT"))
  producer_rows <- data.frame(
    artifact_id = c("artifact-conflict", "artifact-conflict"),
    run_id = c("producer_a", "producer_b"), output_name = c("model", "model"),
    primitive_kind = c("model_ref", "model_ref"), stringsAsFactors = FALSE
  )
  producer_error <- tryCatch(.wb_prov_assert_record_consistency(
    producer_rows, "artifact_id", c("run_id", "output_name", "primitive_kind"),
    "PROVENANCE_NODE_CONFLICT"
  ), error = identity)
  stopifnot(inherits(producer_error, "scworkbench_provenance_composition_error"),
            identical(producer_error$code, "PROVENANCE_NODE_CONFLICT"))
  conflicting_edge <- duplicated_edge
  conflicting_edge$run_id[[2L]] <- "different-child-binding"
  edge_error <- tryCatch(.wb_prov_canonicalize_edges(conflicting_edge), error = identity)
  stopifnot(inherits(edge_error, "scworkbench_provenance_composition_error"),
            identical(edge_error$code, "PROVENANCE_EDGE_CONFLICT"))

  historical_explicit <- wb_prov_run_details(
    b, source_pair$run_id[[1L]], source_pair$snapshot_id[[1L]]
  )
  historical_unambiguous <- wb_prov_run_details(b, source_pair$run_id[[1L]])
  stopifnot(identical(historical_explicit$snapshot_id, source_pair$snapshot_id[[1L]]),
            identical(historical_unambiguous$snapshot_id, source_pair$snapshot_id[[1L]]))

  other_snapshot <- as.character(branch_b$promotion$provenance_snapshot_id)
  DBI::dbBegin(b$con)
  ambiguous_row <- DBI::dbGetQuery(
    b$con, "SELECT * FROM prov_runs WHERE snapshot_id = ? AND run_id = ?;",
    params = list(pca_promotion$provenance_snapshot_id, norm$run$run_id)
  )
  ambiguous_row$snapshot_id <- other_snapshot
  DBI::dbWriteTable(b$con, "prov_runs", ambiguous_row, append = TRUE)
  ambiguity <- tryCatch(wb_prov_run_details(b, norm$run$run_id), error = identity)
  explicit_ambiguity <- wb_prov_run_details(b, norm$run$run_id, other_snapshot)
  DBI::dbRollback(b$con)
  stopifnot(inherits(ambiguity, "scworkbench_provenance_lookup_error"),
            identical(ambiguity$code, "PROVENANCE_RUN_AMBIGUOUS"),
            identical(explicit_ambiguity$snapshot_id, other_snapshot))

  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready))
  wb_close_bundle(b)
  before <- .request01_bundle_fingerprint(root)
  before_sidecars <- .request01_sqlite_sidecars(root)
  status <- .request01_run_literal_audit_wrapper(root)
  after <- .request01_bundle_fingerprint(root)
  after_sidecars <- .request01_sqlite_sidecars(root)
  stopifnot(identical(as.integer(status), 0L), identical(before, after),
            identical(before_sidecars, after_sidecars))
  b <- wb_open_bundle(root, read_only = TRUE)
  TRUE
}
