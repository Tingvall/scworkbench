test_phase5_s2_core_ownership_contract <- function() {
  legacy <- c(
    "trajectory_de", "trajectory_smooth", "trajectory_signature_smooth",
    "trajectory_geneset_dynamics", "trajectory_vector_smooth",
    "trajectory_signal_dynamics"
  )
  explicit <- c("trajectory_geneset_dynamics_explicit", "trajectory_signal_dynamics_explicit")
  available <- wb_list_ops()
  stopifnot(!any(c(legacy, explicit) %in% available))
  for (name in legacy) {
    err <- try(wb_op_interface(name), silent = TRUE)
    stopifnot(inherits(err, "try-error"))
  }

  inventory <- file.path("tests", "fixtures", "phase5_s2_exact_name_ownership_inventory.jsonl")
  rows <- lapply(readLines(inventory, warn = FALSE), jsonlite::fromJSON)
  header <- rows[[1L]]
  rows <- rows[-1L]
  stopifnot(
    identical(as.character(header$schema), "scworkbench.phase5_s2.exact_name_inventory.v1"),
    identical(as.character(header$source_core_commit), "b8d53a55d9403e1fae813d08fba69125f22fbae6"),
    identical(as.character(header$accepted_pack_commit), "d4fd81a524d6104fa526b4960d5e1498242ad60e"),
    identical(as.character(header$pack_migration_candidate_commit), "6702deafbcc999386686cf2b0371ae8f3fb08bec"),
    identical(as.integer(header$reference_count), length(rows)),
    setequal(as.character(header$operation_names), legacy),
    setequal(vapply(rows, `[[`, character(1), "operation"), legacy),
    all(vapply(rows, function(x) x$ownership_class %in% c(
      "pack_owned_scientific", "core_owned_synthetic_conformance",
      "pinned_composite", "archival_migration_evidence"
    ), logical(1))),
    all(vapply(rows, function(x) x$disposition %in% c(
      "move", "retain_core", "replace_with_conformance",
      "retain_composite", "archive_migration_evidence"
    ), logical(1))),
    all(vapply(rows, function(x) nzchar(x$destination_path) && nzchar(x$justification), logical(1)))
  )

  # This archive was promoted by the accepted pre-migration core. The current
  # core must inspect its historical source names and terminal values as-is.
  retained <- tempfile("scwb_s2_retained_")
  dir.create(retained)
  on.exit(unlink(retained, recursive = TRUE, force = TRUE), add = TRUE)
  archive <- file.path("tests", "fixtures", "phase5_s2_retained_old_core_bundle.tar.gz")
  stopifnot(identical(digest::digest(archive, file = TRUE, algo = "sha256",
                                  serialize = FALSE),
                      "e6b2a277b2ff614d44f04ab8bbb80fbd3339f82886df8b0168d437733d67051b"))
  utils::untar(archive, exdir = retained)
  b <- wb_open_bundle(file.path(retained, "forge1-s2-retained-bundle"), read_only = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)
  arts <- wb_art_list(b)
  stopifnot(all(legacy[c(1L, 2L, 4L, 6L)] %in% arts$source_op))
  tbls <- DBI::dbGetQuery(b$con, "SELECT artifact_id, table_type FROM artifact_tables")
  stopifnot(all(legacy[c(1L, 2L, 4L, 6L)] %in% tbls$table_type))
  de_id <- tbls$artifact_id[tbls$table_type == "trajectory_de"][[1L]]
  de <- wb_art_load(b, de_id, expected_kind = "feature_table")
  stopifnot(
    identical(as.character(de$table_type), "trajectory_de"),
    identical(as.character(de$table$feature_id), paste0("g", 1:4)),
    identical(as.character(de$table$lineage_id), rep("L1", 4L))
  )
  stopifnot(!any(legacy %in% wb_list_ops()))
  TRUE
}
