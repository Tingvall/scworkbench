test_trajectory_segment_contract <- function() {
  tmp <- file.path(tempdir(), paste0("scwb_trajseg_contract_", as.integer(Sys.time())))
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)
  cells <- paste0("c", 1:9)
  wb_define_cells(b, cells)

  mk_pt <- function(cell_ids, values, fit_id, engine = "slingshot", key = "L1") {
    wb_prim_cell_vector_family(
      key = rep(key, length(cell_ids)),
      cell_id = cell_ids,
      value = values,
      value_type = "continuous",
      meta = list(
        trajectory_fit_id = fit_id,
        engine = engine,
        family_kind = "trajectory_pseudotime"
      )
    )
  }
  mk_path <- function(fit_id, key = "L1", source_kind = "fitted_model") {
    wb_prim_path_2d_family(
      key = rep(key, 3L),
      point = 1:3,
      x = seq(0, 1, length.out = 3),
      y = seq(0, 1, length.out = 3),
      meta = list(trajectory_fit_id = fit_id, engine = if (identical(source_kind, "fitted_model")) "slingshot" else "space_path")
    )
  }

  seg1_pt <- mk_pt(c("c1", "c2", "c3", "c4"), c(0, 1, 2, 3), "fit_s1")
  seg3_pt <- mk_pt(c("c6", "c7", "c8", "c9"), c(0, 1, 2, 3), "fit_s3")

  fitted_1 <- wb_op_trajectory_segment_from_artifacts(
    bundle = b,
    pseudotime = seg1_pt,
    lineage = "L1",
    segment_id = "fitted_1",
    segment_order = 1,
    path = mk_path("fit_s1"),
    source_engine = "slingshot",
    start_label = "STHSC/root",
    end_label = "DN3"
  )
  fitted_3 <- wb_op_trajectory_segment_from_artifacts(
    bundle = b,
    pseudotime = seg3_pt,
    lineage = "L1",
    segment_id = "fitted_3",
    segment_order = 3,
    path = mk_path("fit_s3"),
    source_engine = "slingshot",
    start_label = "post_bridge",
    end_label = "distal"
  )
  stopifnot(identical(as.character(fitted_1$outputs$segment_manifest$table$source_kind[1]), "fitted_model"))
  stopifnot(identical(as.character(fitted_1$outputs$segment_manifest$table_type), "trajectory_segment_manifest"))

  iface_fit <- wb_op_interface("trajectory_segment_from_artifacts")
  stopifnot(identical(as.character(iface_fit$op_name), "trajectory_segment_from_artifacts"))
  stopifnot(identical(as.character(iface_fit$produces$segment_manifest$kind), "obs_table"))

  path_scores <- wb_prim_cell_vector_family(
    key = rep(c("progress", "distance", "nearest_segment", "nearest_anchor"), each = 3L),
    cell_id = rep(c("c4", "c5", "c6"), times = 4L),
    value = c(0, 0.5, 1, 0.05, 0.10, 0.05, 1, 1, 1, 1, 1, 2),
    value_type = "continuous"
  )
  bridge <- wb_op_trajectory_space_path_segment(
    bundle = b,
    path_scores = path_scores,
    segment_id = "bridge_dn3",
    segment_order = 2,
    distance_threshold = 0.11,
    start_label = "DN3",
    end_label = "post_bridge"
  )
  stopifnot(identical(as.character(bridge$outputs$pseudotime$kind), "cell_vector_family"))
  stopifnot(identical(as.character(bridge$outputs$membership$kind), "cell_vector"))
  stopifnot(identical(as.character(bridge$outputs$confidence$kind), "cell_vector_family"))
  stopifnot(identical(as.character(bridge$outputs$segment_manifest$table_type), "trajectory_segment_manifest"))
  stopifnot(identical(as.character(bridge$outputs$segment_manifest$table$source_kind[1]), "space_path_bridge"))
  stopifnot(all(bridge$outputs$pseudotime$value >= 0 & bridge$outputs$pseudotime$value <= 1))

  s <- wb_session_new()
  rr_bridge <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_space_path_segment",
    inputs = list(
      path_scores = path_scores,
      segment_id = "bridge_session",
      segment_order = 2,
      distance_threshold = 0.11,
      min_cells = 1L
    )
  )
  stopifnot(all(c("pseudotime", "membership", "confidence", "segment_manifest") %in% names(rr_bridge$run$outputs)))
  stopifnot(identical(as.character(rr_bridge$run$outputs$segment_manifest$table_type), "trajectory_segment_manifest"))

  rr_fit <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_segment_from_artifacts",
    inputs = list(
      pseudotime = seg1_pt,
      lineage = "L1",
      segment_id = "fitted_session",
      segment_order = 1,
      source_engine = "slingshot",
      min_cells = 1L
    )
  )
  stopifnot(all(c("pseudotime", "membership", "confidence", "segment_manifest") %in% names(rr_fit$run$outputs)))
  stopifnot(identical(as.character(rr_fit$run$outputs$segment_manifest$table$source_kind[1]), "fitted_model"))

  joined <- wb_op_trajectory_segment_join(
    bundle = b,
    segments = list(
      list(
        segment_id = "fitted_1",
        order = 1,
        source_kind = "fitted_model",
        source_engine = "slingshot",
        pseudotime = seg1_pt,
        lineage = "L1",
        path = mk_path("fit_s1"),
        start_label = "STHSC/root",
        end_label = "DN3"
      ),
      list(
        segment_id = "bridge_dn3",
        order = 2,
        source_kind = "space_path_bridge",
        source_engine = "space_path",
        pseudotime = bridge$outputs$pseudotime,
        lineage = "bridge_dn3",
        membership = bridge$outputs$membership,
        confidence = bridge$outputs$confidence,
        confidence_key = "bridge_dn3",
        segment_manifest = bridge$outputs$segment_manifest,
        start_label = "DN3",
        end_label = "post_bridge"
      ),
      list(
        segment_id = "fitted_3",
        order = 3,
        source_kind = "fitted_model",
        source_engine = "slingshot",
        pseudotime = seg3_pt,
        lineage = "L1",
        path = mk_path("fit_s3"),
        start_label = "post_bridge",
        end_label = "distal"
      )
    ),
    composite_id = "mixed_contract",
    composite_key = "mixed_contract",
    join_policy = "exact_boundary_collapse"
  )
  stopifnot(identical(as.character(joined$outputs$composite_pseudotime_unit_segment$kind), "cell_vector_family"))
  stopifnot(identical(as.character(joined$outputs$composite_pseudotime_cell_weighted_0_1$kind), "cell_vector_family"))
  stopifnot(identical(as.character(joined$outputs$segment_local_table$table_type), "trajectory_segment_local_membership"))
  stopifnot(identical(as.character(joined$outputs$composite_manifest$table_type), "trajectory_segment_join_manifest"))
  local <- joined$outputs$segment_local_table$table
  manifest <- joined$outputs$composite_manifest$table
  comp <- wb_primitive_to_table(joined$outputs$composite_pseudotime_unit_segment, include_context = FALSE)
  comp_weighted <- wb_primitive_to_table(joined$outputs$composite_pseudotime_cell_weighted_0_1, include_context = FALSE)
  stopifnot(all(c("source_kind", "source_engine", "raw_pseudotime", "local_pseudotime_0_1", "confidence") %in% names(local)))
  stopifnot(all(c("fitted_model", "space_path_bridge") %in% unique(as.character(manifest$source_kind))))
  stopifnot(!any(as.character(manifest$source_kind) %in% c("graph_path_bridge", "imported_pseudotime", "manual_pseudotime", "composite")))
  stopifnot(identical(as.character(manifest$boundary_policy[manifest$segment_id == "bridge_dn3"]), "exact_boundary_collapse"))
  stopifnot(identical(as.numeric(comp$value[comp$cell_id == "c4"]), 1))
  stopifnot(identical(as.numeric(comp$value[comp$cell_id == "c6"]), 2))
  stopifnot(isTRUE(all.equal(as.numeric(comp_weighted$value[comp_weighted$cell_id == "c4"]), 4 / 11, tolerance = 1e-12)))
  stopifnot(isTRUE(all.equal(as.numeric(comp_weighted$value[comp_weighted$cell_id == "c6"]), 7 / 11, tolerance = 1e-12)))
  stopifnot(identical(as.character(joined$outputs$composite_membership$value[joined$outputs$composite_membership$cell_id == "c4"]), "waypoint"))
  stopifnot(identical(as.character(joined$outputs$composite_membership$value[joined$outputs$composite_membership$cell_id == "c6"]), "waypoint"))

  legacy_policy <- paste0("waypoint", "_collapse")
  alias_err <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(segment_id = "s1", order = 1, pseudotime = seg1_pt, lineage = "L1"),
        list(segment_id = "s2", order = 2, pseudotime = seg3_pt, lineage = "L1")
      ),
      join_policy = legacy_policy
    ),
    silent = TRUE
  )
  stopifnot(inherits(alias_err, "try-error"))
  stopifnot(grepl("unsupported join_policy", as.character(alias_err), fixed = TRUE))

  reserved_err <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(segment_id = "manual_reserved", order = 1, source_kind = "manual_pseudotime", source_engine = "manual", pseudotime = seg1_pt, lineage = "L1"),
        list(segment_id = "s2", order = 2, pseudotime = seg3_pt, lineage = "L1")
      )
    ),
    silent = TRUE
  )
  stopifnot(inherits(reserved_err, "try-error"))
  stopifnot(grepl("reserved but not currently implemented", as.character(reserved_err), fixed = TRUE))

  non_adjacent <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(segment_id = "s1", order = 1, pseudotime = mk_pt(c("cx", "a"), c(0, 1), "fit_na1"), lineage = "L1"),
        list(segment_id = "s2", order = 2, pseudotime = mk_pt(c("b", "c"), c(0, 1), "fit_na2"), lineage = "L1"),
        list(segment_id = "s3", order = 3, pseudotime = mk_pt(c("cx", "d"), c(0, 1), "fit_na3"), lineage = "L1")
      ),
      composite_id = "non_adjacent",
      composite_key = "non_adjacent"
    ),
    silent = TRUE
  )
  stopifnot(inherits(non_adjacent, "try-error"))
  stopifnot(grepl("non-adjacent or multi-segment overlap", as.character(non_adjacent)))

  triple <- try(
    wb_op_trajectory_segment_join(
      bundle = b,
      segments = list(
        list(segment_id = "s1", order = 1, pseudotime = mk_pt(c("cz", "a"), c(0, 1), "fit_t1"), lineage = "L1"),
        list(segment_id = "s2", order = 2, pseudotime = mk_pt(c("cz", "b"), c(0, 1), "fit_t2"), lineage = "L1"),
        list(segment_id = "s3", order = 3, pseudotime = mk_pt(c("cz", "c"), c(0, 1), "fit_t3"), lineage = "L1")
      ),
      composite_id = "triple",
      composite_key = "triple"
    ),
    silent = TRUE
  )
  stopifnot(inherits(triple, "try-error"))
  stopifnot(grepl("non-adjacent or multi-segment overlap", as.character(triple)))

  path_join <- wb_op_trajectory_segment_path_join(
    bundle = b,
    paths = list(
      list(segment_id = "fitted_1", order = 1, source_kind = "fitted_model", source_engine = "slingshot", path = mk_path("fit_s1"), lineage = "L1"),
      list(segment_id = "bridge_dn3", order = 2, source_kind = "space_path_bridge", source_engine = "space_path", path = mk_path("", key = "bridge_dn3", source_kind = "space_path_bridge"), lineage = "bridge_dn3"),
      list(segment_id = "fitted_3", order = 3, source_kind = "fitted_model", source_engine = "slingshot", path = mk_path("fit_s3"), lineage = "L1")
    ),
    composite_id = "mixed_contract",
    composite_key = "mixed_contract"
  )
  stopifnot(identical(as.character(path_join$outputs$curves$kind), "path_2d_family"))
  stopifnot(identical(as.character(path_join$outputs$path_manifest$table_type), "trajectory_segment_path_join_manifest"))
  stopifnot(all(c("fitted_model", "space_path_bridge") %in% unique(as.character(path_join$outputs$path_manifest$table$source_kind))))

  TRUE
}
