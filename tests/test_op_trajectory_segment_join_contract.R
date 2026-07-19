.make_segment_artifacts <- function(bundle, fit_id, cells, values, weights = NULL, prefix = fit_id) {
  weights <- weights %||% rep(1, length(cells))
  pt <- wb_prim_cell_vector_family(
    key = rep("L1", length(cells)),
    cell_id = cells,
    value = values,
    value_type = "continuous",
    meta = list(
      trajectory_fit_id = fit_id,
      engine = "synthetic",
      n_lineages = 1L,
      family_kind = "trajectory_pseudotime"
    )
  )
  wt <- wb_prim_cell_vector_family(
    key = rep("L1", length(cells)),
    cell_id = cells,
    value = weights,
    value_type = "continuous",
    meta = list(
      trajectory_fit_id = fit_id,
      engine = "synthetic",
      n_lineages = 1L,
      family_kind = "trajectory_membership_weight"
    )
  )
  run <- wb_new_run(
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      user_inputs = list(source = prefix)
    ),
    params = list(
      trajectory_fit_id = fit_id,
      trajectory_engine = "synthetic",
      engine = "synthetic",
      n_lineages = 1L,
      fit_space_id = paste0(prefix, "_space")
    ),
    outputs = list(
      pseudotime = pt,
      lineage_weights = wt
    ),
    notes = paste0("synthetic segment fixture ", prefix)
  )
  prom <- wb_promote_analysis(
    bundle = bundle,
    runs = setNames(list(run), run$run_id),
    head_run_id = run$run_id,
    name_prefix = paste0("segment ", prefix),
    created_by = "test",
    fail_fast = TRUE
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  ids <- stats::setNames(
    as.character(prom$promoted$artifact_id),
    as.character(prom$promoted[[output_col]])
  )
  list(
    pseudotime = ids[["pseudotime"]],
    lineage_weights = ids[["lineage_weights"]],
    run = run,
    promoted = prom
  )
}

test_op_trajectory_segment_join_contract <- function() {
  iface <- wb_op_interface("trajectory_segment_join")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "trajectory_segment_join"))
  stopifnot(identical(as.character(iface$produces$composite_pseudotime_unit_segment$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$composite_pseudotime_cell_weighted_0_1$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$segment_local_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$composite_manifest$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$composite_membership$kind), "cell_vector"))

  tmp <- tempfile("scwb_segment_join_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", 1:8)
  wb_define_cells(b, cells)

  no1 <- .make_segment_artifacts(b, "fit_no_1", c("c1", "c2", "c3"), c(0, 5, 10), prefix = "no1")
  no2 <- .make_segment_artifacts(b, "fit_no_2", c("c4", "c5", "c6"), c(0, 2, 4), prefix = "no2")
  no_overlap <- wb_op_trajectory_segment_join(
    bundle = b,
    segments = list(
      list(
        segment_id = "seg1",
        pseudotime = wb_ref_artifact(no1$pseudotime, "pseudotime"),
        lineage_weights = wb_ref_artifact(no1$lineage_weights, "lineage_weights"),
        lineage = "L1",
        order = 1,
        start_label = "root",
        end_label = "waypoint"
      ),
      list(
        segment_id = "seg2",
        pseudotime = wb_ref_artifact(no2$pseudotime, "pseudotime"),
        lineage_weights = wb_ref_artifact(no2$lineage_weights, "lineage_weights"),
        lineage = "L1",
        order = 2,
        start_label = "waypoint",
        end_label = "endpoint"
      )
    ),
    composite_id = "comp_no_overlap",
    composite_key = "joined_L1"
  )
  no_vec <- no_overlap$outputs$composite_pseudotime_unit_segment
  no_vals <- stats::setNames(no_vec$value, no_vec$cell_id)
  stopifnot(identical(as.numeric(no_vals[c("c1", "c2", "c3", "c4", "c5", "c6")]), c(0, 0.5, 1, 1, 1.5, 2)))
  no_weighted <- no_overlap$outputs$composite_pseudotime_cell_weighted_0_1
  no_weighted_vals <- stats::setNames(no_weighted$value, no_weighted$cell_id)
  stopifnot(identical(as.numeric(no_weighted_vals[c("c1", "c2", "c3", "c4", "c5", "c6")]), c(0, 0.25, 0.5, 0.5, 0.75, 1)))
  stopifnot(!any(no_overlap$outputs$composite_membership$value == "waypoint"))

  ov1 <- .make_segment_artifacts(b, "fit_ov_1", c("c1", "c2", "c3"), c(0, 5, 10), prefix = "ov1")
  ov2 <- .make_segment_artifacts(b, "fit_ov_2", c("c3", "c4", "c5"), c(0, 3, 6), prefix = "ov2")
  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_segment_join",
    inputs = list(
      cell_set = "all",
      min_cells = 1L,
      segments = list(
        list(
          segment_id = "sthsc_to_dn3",
          pseudotime = wb_ref_artifact(ov1$pseudotime, "pseudotime"),
          lineage_weights = wb_ref_artifact(ov1$lineage_weights, "lineage_weights"),
          lineage = "L1",
          order = 1,
          start_label = "STHSC/root",
          end_label = "DN3"
        ),
        list(
          segment_id = "dn3_to_cd4",
          pseudotime = wb_ref_artifact(ov2$pseudotime, "pseudotime"),
          lineage_weights = wb_ref_artifact(ov2$lineage_weights, "lineage_weights"),
          lineage = "L1",
          order = 2,
          start_label = "DN3",
          end_label = "distal CD4"
        )
      ),
      composite_id = "comp_tcell_demo",
      composite_key = "joined_L1"
    ),
    notes = "test trajectory_segment_join adjacent overlap"
  )
  stopifnot(all(c("composite_pseudotime_unit_segment", "composite_pseudotime_cell_weighted_0_1", "segment_local_table", "composite_manifest", "composite_membership") %in% names(rr$run$outputs)))

  comp <- rr$run$outputs$composite_pseudotime_unit_segment
  comp_vals <- stats::setNames(comp$value, comp$cell_id)
  stopifnot(identical(as.character(comp$meta$trajectory_composite_id), "comp_tcell_demo"))
  stopifnot(identical(as.numeric(comp_vals[c("c1", "c2", "c3", "c4", "c5")]), c(0, 0.5, 1, 1.5, 2)))
  comp_w <- rr$run$outputs$composite_pseudotime_cell_weighted_0_1
  comp_w_vals <- stats::setNames(comp_w$value, comp_w$cell_id)
  stopifnot(isTRUE(all.equal(as.numeric(comp_w_vals[c("c1", "c2", "c3", "c4", "c5")]), c(0, 0.25, 0.5, 0.75, 1), tolerance = 1e-12)))

  local <- rr$run$outputs$segment_local_table$table
  stopifnot(identical(as.character(rr$run$outputs$segment_local_table$table_type), "trajectory_segment_local_membership"))
  stopifnot(sum(local$cell_id == "c3") == 2L)
  stopifnot(setequal(as.character(local$segment_role[local$cell_id == "c3"]), c("waypoint_arrival", "waypoint_departure")))

  manifest <- rr$run$outputs$composite_manifest$table
  stopifnot(identical(as.character(rr$run$outputs$composite_manifest$table_type), "trajectory_segment_join_manifest"))
  stopifnot(nrow(manifest) == 2L)
  stopifnot(setequal(as.character(manifest$trajectory_fit_id), c("fit_ov_1", "fit_ov_2")))
  stopifnot(all(nzchar(as.character(manifest$pseudotime_artifact_id))))
  stopifnot(all(nzchar(as.character(manifest$lineage_weights_artifact_id))))
  stopifnot(all(manifest$n_waypoint_cells == 1L))
  stopifnot(all(c("segment_weight_cell_fraction", "weighted_coordinate_start", "weighted_coordinate_end") %in% names(manifest)))

  mem <- rr$run$outputs$composite_membership
  mem_vals <- stats::setNames(as.character(mem$value), mem$cell_id)
  stopifnot(identical(as.character(mem_vals[["c3"]]), "waypoint"))

  prom <- wb_session_promote_current(
    bundle = b,
    session = rr$session,
    name_prefix = "segment join",
    created_by = "test",
    fail_fast = TRUE,
    outputs = c(
      "composite_pseudotime_unit_segment",
      "composite_pseudotime_cell_weighted_0_1",
      "segment_local_table",
      "composite_manifest",
      "composite_membership"
    )
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  promoted <- stats::setNames(as.character(prom$promoted$artifact_id), as.character(prom$promoted[[output_col]]))
  stopifnot(all(c("composite_pseudotime_unit_segment", "composite_pseudotime_cell_weighted_0_1", "segment_local_table", "composite_manifest", "composite_membership") %in% names(promoted)))
  loaded_pt <- wb_art_load(b, promoted[["composite_pseudotime_unit_segment"]], expected_kind = "cell_vector_family")
  loaded_pt_w <- wb_art_load(b, promoted[["composite_pseudotime_cell_weighted_0_1"]], expected_kind = "cell_vector_family")
  loaded_local <- wb_art_load(b, promoted[["segment_local_table"]], expected_kind = "obs_table")
  loaded_manifest <- wb_art_load(b, promoted[["composite_manifest"]], expected_kind = "obs_table")
  loaded_membership <- wb_art_load(b, promoted[["composite_membership"]], expected_kind = "cell_vector")
  stopifnot(identical(as.character(loaded_pt$kind), "cell_vector_family"))
  stopifnot(identical(as.character(loaded_pt_w$kind), "cell_vector_family"))
  stopifnot(identical(as.character(loaded_local$table_type), "trajectory_segment_local_membership"))
  stopifnot(identical(as.character(loaded_manifest$table_type), "trajectory_segment_join_manifest"))
  stopifnot(identical(as.character(loaded_membership$kind), "cell_vector"))
  selected <- wb_sel_all(b, "all") |>
    wb_sel_vector_family(
      vector_id = paste0("artifact:", promoted[["composite_pseudotime_unit_segment"]]),
      key = "joined_L1",
      min = 1,
      max = 1
    )
  stopifnot(identical(as.character(selected), "c3"))

  bad_same_segment <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(
          segment_id = "bad1",
          pseudotime = wb_ref_artifact(ov1$pseudotime, "pseudotime"),
          lineage_weights = wb_ref_artifact(ov2$lineage_weights, "lineage_weights"),
          lineage = "L1",
          order = 1
        ),
        list(
          segment_id = "bad2",
          pseudotime = wb_ref_artifact(no2$pseudotime, "pseudotime"),
          lineage_weights = wb_ref_artifact(no2$lineage_weights, "lineage_weights"),
          lineage = "L1",
          order = 2
        )
      )
    ),
    silent = TRUE
  )
  stopifnot(inherits(bad_same_segment, "try-error"))
  stopifnot(grepl("different trajectory fit families", as.character(bad_same_segment), fixed = TRUE))

  far1 <- .make_segment_artifacts(b, "fit_far_1", c("c1", "c8"), c(0, 1), prefix = "far1")
  far2 <- .make_segment_artifacts(b, "fit_far_2", c("c2", "c3"), c(0, 1), prefix = "far2")
  far3 <- .make_segment_artifacts(b, "fit_far_3", c("c8", "c4"), c(0, 1), prefix = "far3")
  bad_non_adjacent <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(segment_id = "far1", pseudotime = wb_ref_artifact(far1$pseudotime, "pseudotime"), lineage = "L1", order = 1),
        list(segment_id = "far2", pseudotime = wb_ref_artifact(far2$pseudotime, "pseudotime"), lineage = "L1", order = 2),
        list(segment_id = "far3", pseudotime = wb_ref_artifact(far3$pseudotime, "pseudotime"), lineage = "L1", order = 3)
      )
    ),
    silent = TRUE
  )
  stopifnot(inherits(bad_non_adjacent, "try-error"))
  stopifnot(grepl("non-adjacent", as.character(bad_non_adjacent), fixed = TRUE))

  TRUE
}
