.kg_cross_snapshot_fingerprint <- function(path) {
  files <- sort(list.files(
    path, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE
  ))
  files <- files[file.info(files)$isdir %in% FALSE]
  relative <- substring(files, nchar(path) + 2L)
  data.frame(
    path = relative,
    size = unname(file.info(files)$size),
    md5 = unname(tools::md5sum(files)),
    stringsAsFactors = FALSE
  )
}

test_provenance_kg_cross_snapshot_edge_canonicalization_contract <- function() {
  root <- tempfile("scwb_kg_cross_snapshot_")
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  b <- wb_init_bundle(root, overwrite = TRUE)
  wb_define_cells(b, c("cell_1", "cell_2"), created_by = "kg-cross-snapshot-contract")

  source_identity <- list(
    schema = "scworkbench.source_identity.v2",
    dataset_name = "synthetic cross-snapshot source",
    inputs = list(
      list(
        scope = "public_file", source_id = "synthetic_h5ad",
        accession = "SYNTHETIC_H5AD", path = "/not-required/source.h5ad",
        uri = "https://example.org/source.h5ad", role = "source_object",
        format = "h5ad", sha256 = paste(rep("a", 64L), collapse = ""),
        checksum_algorithm = "sha256", bundled = FALSE, accession_derived = TRUE
      ),
      list(
        scope = "in_memory", source_id = "synthetic_h5ad__converted_sce",
        uri = "scworkbench-ingestion://synthetic/converted-sce",
        role = "conversion_intermediate", format = "SingleCellExperiment",
        bundled = FALSE, parent_source_id = "synthetic_h5ad",
        source_relation = "CONVERTS_TO", conversion_owner = "synthetic-contract"
      )
    )
  )
  run <- wb_new_run(
    op_name = "metadata_cell_vector",
    inputs = list(), params = list(),
    outputs = list(vector = wb_prim_cell_vector(
      setNames(c(1, 2), c("cell_1", "cell_2")), value_type = "continuous"
    )),
    notes = "same run observed in two promoted snapshots"
  )
  runs <- stats::setNames(list(run), run$run_id)
  snapshot_ids <- vapply(seq_len(2L), function(i) {
    promoted <- wb_promote_analysis(
      bundle = b, runs = runs, head_run_id = run$run_id,
      outputs = "vector", name_prefix = paste0("cross-snapshot-", i),
      created_by = "kg-cross-snapshot-contract"
    )
    promoted$provenance_snapshot_id
  }, character(1))
  for (snapshot_id in snapshot_ids) {
    scworkbench:::.wb_prov_record_source_inputs(
      b, snapshot_id, run$run_id, source_identity
    )
  }

  raw <- scworkbench:::.wb_kg_provenance_nodes_edges(b)$edges
  repeated <- raw[
    raw$source_id == "external_source:synthetic_h5ad" &
      raw$target_id == "in_memory_source:synthetic_h5ad_converted_sce" &
      raw$edge_type == "CONVERTS_TO",
    , drop = FALSE
  ]
  stopifnot(nrow(repeated) == 2L, length(unique(repeated$id)) == 1L)
  forward <- scworkbench:::.wb_kg_canonicalize_rows(repeated, "edge")
  reverse <- scworkbench:::.wb_kg_canonicalize_rows(repeated[2:1, , drop = FALSE], "edge")
  stopifnot(identical(forward, reverse), nrow(forward) == 1L)
  evidence <- jsonlite::fromJSON(forward$payload_json[[1L]], simplifyVector = FALSE)
  occurrence_snapshots <- sort(vapply(
    evidence$occurrences, function(x) as.character(x$snapshot_id), character(1)
  ))
  occurrence_runs <- unique(vapply(
    evidence$occurrences, function(x) as.character(x$run_id), character(1)
  ))
  stopifnot(
    identical(sort(unlist(evidence$snapshot_ids, use.names = FALSE)), sort(snapshot_ids)),
    identical(occurrence_snapshots, sort(snapshot_ids)),
    identical(occurrence_runs, run$run_id)
  )

  conflicting <- repeated
  conflicting_payload <- jsonlite::fromJSON(
    conflicting$payload_json[[2L]], simplifyVector = FALSE
  )
  conflicting_payload$checksum_status <- "contradictory_status"
  conflicting$payload_json[[2L]] <- scworkbench:::.wb_kg_json(conflicting_payload)
  conflict <- tryCatch(
    scworkbench:::.wb_kg_canonicalize_rows(conflicting, "edge"),
    error = identity
  )
  stopifnot(
    inherits(conflict, "scworkbench_provenance_composition_error"),
    identical(conflict$code, "PROVENANCE_KG_EDGE_CONFLICT")
  )

  wb_close_bundle(b)
  b <- NULL
  writable <- wb_open_bundle(root)
  writable_before <- .kg_cross_snapshot_fingerprint(root)
  writable_graph <- wb_kg_provenance_graph(writable)
  writable_after <- .kg_cross_snapshot_fingerprint(root)
  stopifnot(
    identical(writable_before, writable_after),
    !anyDuplicated(writable_graph$nodes$id),
    !anyDuplicated(writable_graph$edges$id)
  )
  stopifnot(isTRUE(wb_finalize_recipient_bundle(writable)$ready))
  wb_close_bundle(writable)
  before <- .kg_cross_snapshot_fingerprint(root)
  ro <- wb_open_bundle(root, read_only = TRUE)
  graph_a <- wb_kg_provenance_graph(ro)
  graph_b <- wb_kg_provenance_graph(ro)
  wb_close_bundle(ro)
  after <- .kg_cross_snapshot_fingerprint(root)
  stopifnot(
    identical(graph_a$nodes, graph_b$nodes),
    identical(graph_a$edges, graph_b$edges),
    identical(before, after),
    !anyDuplicated(graph_a$nodes$id),
    !anyDuplicated(graph_a$edges$id)
  )

  TRUE
}
