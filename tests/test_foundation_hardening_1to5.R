test_foundation_hardening_1to5 <- function(bundle_dir) {
  contract_test_activate_statistics_pack()
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  # ---------------------------------------------------------
  # 1) Canonical ordering + alignment invariants
  # ---------------------------------------------------------
  cells_all <- wb_cells(b, cell_set = "all")
  stopifnot(is.character(cells_all), length(cells_all) > 0)

  meta_cell <- wb_meta(b, cols = "cell_id")
  stopifnot(identical(meta_cell$cell_id, cells_all))

  idx <- seq(1, min(length(cells_all), 300), by = 3)
  cells_sub <- cells_all[idx]
  meta_sub <- wb_meta(b, cells = cells_sub, cols = c("cell_id", "dataset_id"))
  stopifnot(identical(meta_sub$cell_id, cells_sub))

  sp <- wb_spaces(b)
  if (nrow(sp) > 0) {
    sid <- sp$space_id[1]
    s <- wb_space(b, sid, cells = cells_sub)
    if (is.data.frame(s)) {
      stopifnot(identical(as.character(s$cell_id), cells_sub))
    } else {
      stopifnot(identical(rownames(s), cells_sub))
    }
  }

  # ---------------------------------------------------------
  # 2) Getter contract: shape + errors are explicit
  # ---------------------------------------------------------
  mats <- wb_matrices(b)
  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]
    fids <- wb_feature_ids(b, mid)
    stopifnot(is.character(fids), length(fids) > 0)

    bad_mid <- try(wb_feature_ids(b, ".__missing_matrix__."), silent = TRUE)
    stopifnot(inherits(bad_mid, "try-error"))

    bad_col <- try(wb_meta(b, cols = c("cell_id", ".__missing_col__.")), silent = TRUE)
    stopifnot(inherits(bad_col, "try-error"))
  }

  # ---------------------------------------------------------
  # 3) Selector determinism + empty-safety across rule types
  # ---------------------------------------------------------
  sel_all <- wb_sel_all(b, cell_set = "all")
  stopifnot(identical(as.character(sel_all), cells_all))

  # set
  sets <- wb_cell_sets(b)
  if (length(sets) > 0) {
    ss <- wb_sel_set(b, sets = sets[1])
    stopifnot(all(as.character(ss) %in% cells_all))
  }

  # meta (use dataset_id, guaranteed)
  ds <- unique(wb_meta(b, cols = "dataset_id")$dataset_id)
  ds <- as.character(ds[!is.na(ds)])
  if (length(ds) > 0) {
    sm <- wb_sel_meta(b, col = "dataset_id", values = ds[1])
    stopifnot(all(as.character(sm) %in% cells_all))
  }

  # expr + empty-safe
  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]
    fid <- wb_feature_ids(b, mid)[1]
    se <- wb_sel_expr(b, matrix_id = mid, feature_id = fid, min = 0)
    stopifnot(all(as.character(se) %in% cells_all))

    se0 <- wb_sel_expr(character(0), bundle = b, matrix_id = mid, feature_id = fid, min = 0)
    stopifnot(is.character(se0), length(se0) == 0)
    stopifnot(inherits(attr(se0, "wb_bundle", exact = TRUE), "scworkbench_bundle"))
  }

  # space_box + empty-safe
  sp2d <- sp$space_id[as.integer(sp$dims) == 2L]
  if (length(sp2d) > 0) {
    sb <- wb_sel_space_box(sel_all, space_id = sp2d[1], xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf)
    stopifnot(all(as.character(sb) %in% cells_all))

    sb0 <- wb_sel_and(sb, character(0))
    stopifnot(is.character(sb0), length(sb0) == 0)
    stopifnot(inherits(attr(sb0, "wb_bundle", exact = TRUE), "scworkbench_bundle"))
  }

  # vector_range rule via session ref in selection plan
  n_vec <- min(length(cells_all), 500L)
  vv_cells <- cells_all[seq_len(n_vec)]
  vv <- seq_along(vv_cells)
  names(vv) <- vv_cells
  # Keep the selector test non-empty for both the tiny golden fixture and
  # larger integration bundles.
  range_min <- max(1L, as.integer(ceiling(n_vec / 3)))
  range_max <- min(n_vec, range_min + max(1L, as.integer(floor(n_vec / 3))) - 1L)

  run <- wb_new_run(
    op_name = "test_vector",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(),
    outputs = list(scores = wb_prim_cell_vector(vv, value_type = "continuous")),
    notes = "foundation hardening test"
  )
  runs <- list()
  runs[[run$run_id]] <- run

  plan <- list(
    universe = "all",
    rules = list(
      list(
        type = "vector_range",
        vector_ref = paste0("session:", run$run_id, ":scores"),
        min = range_min,
        max = range_max,
        na.rm = TRUE
      )
    )
  )
  sel_v <- wb_exec_selection_plan(b, plan, runs = runs)
  want_v <- cells_all[cells_all %in% names(vv)[vv >= range_min & vv <= range_max]]
  stopifnot(identical(sel_v, want_v))

  # Boolean groups + NOT
  if (length(sets) > 0) {
    set_members <- lapply(sets, function(set_name) {
      cells <- as.character(wb_cells(b, cell_set = set_name))
      cells[cells %in% cells_all]
    })
    proper <- vapply(set_members, function(cells) {
      length(cells) > 0L && length(cells) < length(cells_all)
    }, logical(1))
    set_name <- as.character(sets[which(proper)[1L] %||% NA_integer_])
    set1 <- if (is.na(set_name)) character(0) else set_members[[which(sets == set_name)[1L]]]
    if (length(set1) > 0) {
      not_plan <- list(
        universe = "all",
        groups = list(
          list(rules = list(
            list(type = "set", sets = set_name, negate = TRUE)
          ))
        )
      )
      sel_not <- wb_exec_selection_plan(b, not_plan, runs = runs)
      stopifnot(identical(sel_not, setdiff(cells_all, set1)))

      or_plan <- list(
        universe = "all",
        groups = list(
          list(rules = list(list(type = "set", sets = set_name))),
          list(rules = list(list(type = "vector_range",
                                 vector_ref = paste0("session:", run$run_id, ":scores"),
                                 min = range_min,
                                 max = min(range_max, range_min + 1L),
                                 na.rm = TRUE)))
        )
      )
      sel_or <- wb_exec_selection_plan(b, or_plan, runs = runs)
      want_or <- unique(c(set1, names(vv)[vv >= range_min & vv <= min(range_max, range_min + 1L)]))
      want_or <- cells_all[cells_all %in% want_or]
      stopifnot(identical(sel_or, want_or))
    }
  }

  # ---------------------------------------------------------
  # 4) Coverage/effective-cells semantics are stable
  # ---------------------------------------------------------
  sid_cov <- if (nrow(sp) > 0) sp$space_id[1] else NULL
  if (!is.null(sid_cov)) {
    cells_req <- head(cells_all, 250)
    cov_req <- wb_cell_coverage(
      b,
      cell_set = "all",
      inputs = list(cell_ids = cells_req, space_id = sid_cov)
    )
    stopifnot(identical(cov_req$requested, length(unique(as.character(cells_req)))))
    stopifnot(cov_req$effective <= cov_req$requested)

    eff <- scworkbench:::.wb_effective_cells(
      bundle = b,
      cell_set = "all",
      inputs = list(cell_ids = cells_req, space_id = sid_cov),
      op_name = "test_effective_cells",
      min_cells = 10L
    )
    stopifnot(all(eff %in% cells_req))

    err_min <- try(
      scworkbench:::.wb_effective_cells(
        bundle = b,
        cell_set = "all",
        inputs = list(cell_ids = head(cells_all, 20), space_id = sid_cov),
        op_name = "test_effective_cells",
        min_cells = 1000L
      ),
      silent = TRUE
    )
    stopifnot(inherits(err_min, "try-error"))
  }

  cov_zero <- wb_cell_coverage(
    b,
    cell_set = "all",
    inputs = list(cell_ids = character(0))
  )
  stopifnot(identical(cov_zero$requested, 0L))
  stopifnot(identical(cov_zero$effective, 0L))
  stopifnot(identical(cov_zero$percent, 0))

  # ---------------------------------------------------------
  # 5) Canonical reference model consistency
  # ---------------------------------------------------------
  rr <- wb_ref_run(run$run_id, "scores")
  stopifnot(identical(rr$ref_type, "run"))

  prim_run <- wb_resolve_primitive(
    b,
    spec = list(type = "session", value = list(run_id = run$run_id, output = "scores")),
    runs = runs,
    expected_kind = "cell_vector"
  )
  stopifnot(identical(prim_run$kind, "cell_vector"))

  # Artifact reference path: promote one tiny known-op run and resolve by ref
  run_promote <- wb_new_run(
    op_name = "leiden",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(),
    outputs = list(clusters = wb_prim_cell_vector(setNames(rep("A", length(vv_cells)), vv_cells), value_type = "categorical")),
    notes = "foundation hardening promote test"
  )

  s2 <- wb_session_new()
  s2 <- wb_session_add_run(s2, run_promote)
  s2$head_run_id <- run_promote$run_id
  prom <- wb_session_promote_current(
    bundle = b,
    session = s2,
    name_prefix = "foundation_ref",
    created_by = "test",
    fail_fast = FALSE
  )
  ok <- prom$promoted[prom$promoted$status == "ok", , drop = FALSE]
  if (nrow(ok) > 0) {
    aid <- as.character(ok$artifact_id[1])
    ar <- wb_ref_artifact(aid, "scores")
    stopifnot(identical(ar$ref_type, "artifact"))

    if (exists("wb_client_load", mode = "function")) {
      p_art <- wb_client_load(b, ar, session = s2, expected_kind = "cell_vector")
    } else {
      p_art <- wb_resolve_primitive(
        b,
        spec = list(type = "artifact", value = aid),
        runs = s2$runs,
        expected_kind = "cell_vector"
      )
    }
    stopifnot(identical(p_art$kind, "cell_vector"))
  }

  run_cv_cont <- wb_new_run(
    op_name = "test_vector",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(),
    outputs = list(scores = wb_prim_cell_vector(vv, value_type = "continuous")),
    notes = "continuous cell_vector roundtrip test"
  )
  aid_cv_cont <- scworkbench:::.wb_promote_cell_vector(
    bundle = b,
    run = run_cv_cont,
    out_name = "scores",
    prim = run_cv_cont$outputs$scores,
    created_by = "test"
  )
  p_cv_cont <- wb_art_load(b, artifact_id = as.character(aid_cv_cont), expected_kind = "cell_vector")
  stopifnot(identical(p_cv_cont$kind, "cell_vector"))
  stopifnot(identical(as.character(p_cv_cont$value_type), "continuous"))
  stopifnot(identical(as.character(p_cv_cont$cell_id), as.character(vv_cells)))
  stopifnot(isTRUE(all.equal(suppressWarnings(as.numeric(p_cv_cont$value)), as.numeric(vv))))

  # ---------------------------------------------------------
  # 6) Tabular primitives are promotable and loadable
  # ---------------------------------------------------------
  run_ft <- wb_new_run(
    op_name = "de_wilcox",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(matrix_id = if (nrow(wb_matrices(b)) > 0) wb_matrices(b)$matrix_id[1] else NA_character_),
    outputs = list(
      de_table = wb_prim_feature_table(
        table = data.frame(
          feature_id = c("f1", "f2"),
          p_val = c(0.01, 0.02),
          p_val_adj = c(0.02, 0.03),
          stringsAsFactors = FALSE
        ),
        table_type = "de_wilcox"
      )
    ),
    notes = "feature_table promote/load test"
  )

  s3 <- wb_session_new()
  s3 <- wb_session_add_run(s3, run_ft)
  s3$head_run_id <- run_ft$run_id

  prom_tbl <- wb_promote_analysis(
    bundle = b,
    runs = s3$runs,
    head_run_id = run_ft$run_id,
    name_prefix = "foundation_tables",
    created_by = "test",
    fail_fast = TRUE
  )
  ok_tbl <- prom_tbl$promoted[prom_tbl$promoted$status == "ok", , drop = FALSE]
  stopifnot(nrow(ok_tbl) >= 1)

  aid_ft <- ok_tbl$artifact_id[ok_tbl$output == "de_table"][1]
  pft <- wb_art_load(b, artifact_id = as.character(aid_ft), expected_kind = "feature_table")
  stopifnot(identical(pft$kind, "feature_table"), nrow(pft$table) == 2)

  # wrangler projection: artifact ref -> normalized table
  if (exists("wb_client_load_table", mode = "function")) {
    tft <- wb_client_load_table(
      bundle = b,
      ref = wb_ref_artifact(as.character(aid_ft), "de_table"),
      include_context = TRUE
    )
    stopifnot(is.data.frame(tft), nrow(tft) == 2, "feature_id" %in% names(tft), "kind" %in% names(tft))
  }

  # obs_table promotion path (internal promoter, same artifact schema)
  run_obs <- wb_new_run(
    op_name = "de_wilcox",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(),
    outputs = list(),
    notes = "obs_table promote/load test"
  )
  obs_prim <- wb_prim_obs_table(
    table = data.frame(sample_id = c("s1", "s2"), n = c(10, 20), stringsAsFactors = FALSE),
    table_type = "qc_summary",
    entity_kind = "sample"
  )
  aid_ot <- scworkbench:::.wb_promote_obs_table(
    bundle = b,
    run = run_obs,
    out_name = "summary",
    prim = obs_prim,
    created_by = "test"
  )
  pot <- wb_art_load(b, artifact_id = as.character(aid_ot), expected_kind = "obs_table")
  stopifnot(identical(pot$kind, "obs_table"), nrow(pot$table) == 2)
  if (exists("wb_client_load_table", mode = "function")) {
    tot <- wb_client_load_table(
      bundle = b,
      ref = wb_ref_artifact(as.character(aid_ot), "summary"),
      include_context = TRUE
    )
    stopifnot(is.data.frame(tot), nrow(tot) == 2, "kind" %in% names(tot), "entity_kind" %in% names(tot))
  }

  TRUE
}
