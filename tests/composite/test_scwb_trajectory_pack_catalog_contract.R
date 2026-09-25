.trajectory_registry_snapshot <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs,
    operations = registry$operations)
}

.trajectory_registry_restore <- function(snapshot) {
  snapshot$registry$packs <- snapshot$packs
  snapshot$registry$operations <- snapshot$operations
  invisible(TRUE)
}

test_trajectory_catalog_activation_identity_contract <- function() {
  baseline <- .trajectory_registry_snapshot()
  on.exit(.trajectory_registry_restore(baseline), add = TRUE)
  if (!is.null(baseline$packs$scwbtrajectory)) {
    for (name in baseline$packs$scwbtrajectory$operation_names)
      baseline$registry$operations[[name]] <- NULL
    baseline$registry$packs$scwbtrajectory <- NULL
  }
  before_ops <- wb_list_ops()
  before_identity <- wb_operation_catalog_identity()
  unqualified <- c("trajectory_branch_compare", "trajectory_route_smooth",
    "space_path_score", "space_path_project_2d", "space_path_define",
    "trajectory_segment_from_artifacts", "trajectory_space_path_segment",
    "trajectory_segment_join", "trajectory_segment_path_join",
    "slingshot", "slingshot_fit", "slingshot_lineage_weights",
    "slingshot_project")
  qualified <- paste0("scwbtrajectory::", unqualified)
  stopifnot(!any(unqualified %in% before_ops),
    !any(qualified %in% before_ops))
  contract_test_activate_trajectory_pack()
  after_ops <- wb_list_ops()
  after_identity <- wb_operation_catalog_identity()
  pack <- wb_operation_pack_inspect("scwbtrajectory")
  manifest_names <- vapply(pack$manifest$operations, `[[`, "", "name")
  stopifnot(setequal(setdiff(after_ops, before_ops),
      paste0("scwbtrajectory::", manifest_names)),
    all(qualified %in% after_ops),
    identical(wb_op_interface("space_path_score")$op_name,
      "scwbtrajectory::space_path_score"),
    !identical(before_identity$sha256, after_identity$sha256))
  stopifnot(identical(pack$manifest$pack_abi_version, "3"),
    identical(pack$manifest$namespace, "scwbtrajectory"),
    setequal(manifest_names, sub("^scwbtrajectory::", "",
      setdiff(after_ops, before_ops))))
  TRUE
}

test_trajectory_missing_pack_predispatch_contract <- function() {
  baseline <- .trajectory_registry_snapshot()
  on.exit(.trajectory_registry_restore(baseline), add = TRUE)
  root <- tempfile("scwb-trajectory-missing-pack-")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- paste0("c", seq_len(3L))
  wb_define_cells(b, cells)
  values <- cbind(x = seq_along(cells), y = seq_along(cells))
  rownames(values) <- cells
  wb_add_space(b, "latent", values)
  before <- list(artifacts = wb_art_list(b),
    identity = wb_operation_catalog_identity(),
    source = getFromNamespace(".wb_session_source_identity",
      "scworkbench")(b)$scientific_state_fingerprint)
  failure <- try(wb_session_run_op(wb_session_new(), b,
    "scwbtrajectory::space_path_define", inputs = list(space = "latent",
      checkpoint_sets = c("start", "end"))),
    silent = TRUE)
  stopifnot(inherits(failure, "try-error"),
    identical(before$artifacts, wb_art_list(b)),
    identical(before$identity, wb_operation_catalog_identity()),
    identical(before$source, getFromNamespace(
      ".wb_session_source_identity",
      "scworkbench")(b)$scientific_state_fingerprint))
  TRUE
}
