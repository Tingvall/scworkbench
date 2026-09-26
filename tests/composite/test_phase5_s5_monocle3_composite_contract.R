test_phase5_s5_monocle3_exact_pair_composite_contract <- function() {
  contract_test_activate_trajectory_pack()
  names <- wb_list_ops()
  stopifnot(!any(c("monocle3_fit", "monocle3_project") %in% names),
    sum(names == "scwbtrajectory::monocle3_fit") == 1L,
    sum(names == "scwbtrajectory::monocle3_project") == 1L)
  oracle <- jsonlite::read_json(file.path("tests", "fixtures",
    "phase5_s5_old_core_relation_oracle.json"), simplifyVector = FALSE)
  cells <- as.character(unlist(oracle$oracles$monocle3$source_cells))
  t <- seq(0.15, 1.2, length.out = 8L)
  coordinates <- rbind(cbind(t, rep(0, 8L)),
    cbind(-t, 0.25 * t), cbind(rep(0, 8L), -t))
  rownames(coordinates) <- cells
  colnames(coordinates) <- c("d1", "d2")
  display <- cbind(x = 1.5 * coordinates[, 1L] +
      0.2 * coordinates[, 2L],
    y = 0.8 * coordinates[, 2L] - 0.1 * coordinates[, 1L])
  rownames(display) <- cells
  root <- tempfile("scwb-phase5-s5-composite-")
  bundle <- wb_init_bundle(root)
  on.exit({
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "latent", coordinates)
  wb_add_space(bundle, "plot", display)
  fit <- wb_session_run_op(wb_session_new(), bundle,
    "scwbtrajectory::monocle3_fit", inputs = list(
      cell_set = "all", cell_ids = cells, fit_space = "latent",
      dims = 1:2, root_cells = cells[[1L]], k = 5L,
      random_seed = 13L, use_partition = FALSE,
      close_loop = FALSE))
  stopifnot(identical(names(fit$run$outputs),
      c("pseudotime", "branch_membership", "model")),
    length(fit$run$outputs$pseudotime$cell_id) == 24L,
    length(fit$run$outputs$branch_membership$key) == 25L)
  promoted <- wb_session_promote_current(bundle, fit$session,
    outputs = names(fit$run$outputs))
  stopifnot(nrow(promoted$promoted) == 3L,
    all(promoted$promoted$status == "ok"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  wb_session_discard(fit$session)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle)
  bundle <- NULL
  relocated <- tempfile("scwb-phase5-s5-relocated-")
  fs::dir_copy(root, relocated)
  on.exit(unlink(relocated, recursive = TRUE, force = TRUE), add = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(relocated,
    level = "recipient")$ok))
  reopened <- wb_open_bundle(relocated)
  on.exit(if (!is.null(reopened))
    try(wb_close_bundle(reopened), silent = TRUE), add = TRUE)
  project <- wb_session_run_op(wb_session_new(), reopened,
    "scwbtrajectory::monocle3_project", inputs = list(
      model = wb_ref_artifact(model_id, "model"),
      plot_space = "plot", approx_points = 200L))
  curves <- project$run$outputs$curves
  stopifnot(identical(curves$kind, "path_2d_family"),
    length(curves$key) == 8L,
    all(is.finite(curves$x)), all(is.finite(curves$y)))
  curves_publication <- wb_session_promote_current(reopened,
    project$session, outputs = "curves")
  stopifnot(nrow(curves_publication$promoted) == 1L,
    identical(curves_publication$promoted$status[[1L]], "ok"))
  wb_session_discard(project$session)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(reopened)$ready))
  wb_close_bundle(reopened)
  reopened <- NULL
  stopifnot(isTRUE(wb_bundle_validation_report(relocated,
    level = "recipient")$ok))
  recipient <- wb_open_bundle(relocated, read_only = TRUE)
  on.exit(wb_close_bundle(recipient), add = TRUE)
  retained_model <- wb_art_load(recipient, model_id,
    expected_kind = "model_ref")
  report_rows <- getFromNamespace(".wb_reporting_trajectory_lineages",
    "scworkbench")(retained_model)
  stopifnot(length(report_rows) == 2L,
    sum(vapply(report_rows, nrow, integer(1))) == 25L)
  TRUE
}
