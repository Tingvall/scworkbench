test_provenance_snapshot_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  r1 <- wb_new_run(
    op_name = "de_wilcox",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = character(0),
      user_inputs = list(group_a = "set:a", group_b = "set:b")
    ),
    params = list(min_pct = 0, p_adjust_method = "BH", vec_param = c("x", "y")),
    outputs = list(
      de_table = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(1.2, 0.4), stringsAsFactors = FALSE),
        table_type = "de_wilcox"
      )
    ),
    notes = "synthetic de"
  )

  r2 <- wb_new_run(
    op_name = "markers_topn",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = c(r1$run_id),
      user_inputs = list(de_ref = wb_ref_run(r1$run_id, "de_table"))
    ),
    params = list(top_n = 10L, min_pct = 0.1),
    outputs = list(
      markers = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(2.1, 1.4), stringsAsFactors = FALSE),
        table_type = "markers_topn"
      )
    ),
    notes = "synthetic markers"
  )

  runs <- list()
  runs[[r1$run_id]] <- r1
  runs[[r2$run_id]] <- r2

  prom <- wb_promote_analysis(
    bundle = b,
    runs = runs,
    head_run_id = r2$run_id,
    name_prefix = "provtest",
    created_by = "test",
    fail_fast = TRUE
  )

  sid <- as.character(prom$provenance_snapshot_id %||% "")[1]
  stopifnot(nzchar(sid))
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 2)
  stopifnot(all(prom$promoted$snapshot_id == sid))

  heads <- wb_prov_list_heads(b)
  stopifnot(is.data.frame(heads), nrow(heads) >= 1)
  stopifnot(sid %in% as.character(heads$snapshot_id))
  stopifnot("schema_version" %in% colnames(heads))
  sv <- heads$schema_version
  if (is.null(sv)) sv <- ""
  stopifnot(any(nzchar(as.character(sv))))

  dag <- wb_prov_dag(b, snapshot_id = sid)
  stopifnot(is.list(dag))
  stopifnot(identical(as.character(dag$snapshot_id), sid))
  stopifnot(is.data.frame(dag$nodes), nrow(dag$nodes) >= 2)
  stopifnot(is.data.frame(dag$edges), nrow(dag$edges) >= 1)
  stopifnot(any(dag$edges$edge_type == "depends_on_run"))
  stopifnot(any(dag$edges$edge_type == "promoted_to_artifact"))
  stopifnot(any(dag$nodes$node_type == "artifact"))

  dag_latest <- wb_prov_dag(b)
  stopifnot(is.list(dag_latest), is.data.frame(dag_latest$nodes))
  stopifnot(nrow(dag_latest$nodes) >= 2)

  val <- wb_prov_validate_replay(b, snapshot_id = sid, mode = "symbolic", strict = FALSE)
  stopifnot(is.list(val), is.list(val$summary))
  stopifnot(is.numeric(val$summary$n_runs), val$summary$n_runs >= 1)
  stopifnot(is.numeric(val$summary$n_outputs), val$summary$n_outputs >= 0)
  stopifnot(is.data.frame(val$per_run), nrow(val$per_run) >= 1)
  stopifnot(is.data.frame(val$per_output))
  val_kind <- wb_prov_validate_replay(b, snapshot_id = sid, mode = "symbolic", profile = "kind_only", strict = FALSE)
  stopifnot(is.list(val_kind), is.list(val_kind$summary))
  stopifnot(identical(as.character(val_kind$summary$profile), "kind_only"))

  det <- wb_prov_run_details(b, run_id = r2$run_id, snapshot_id = sid)
  stopifnot(is.list(det), is.list(det$run))
  stopifnot(identical(as.character(det$run$run_id), as.character(r2$run_id)))
  stopifnot(is.list(det$run$symbolic_inputs))
  stopifnot(is.list(det$run$execution_inputs))
  sym_cell_set <- det$run$symbolic_inputs$cell_set
  if (is.null(sym_cell_set)) sym_cell_set <- "all"
  stopifnot(identical(as.character(sym_cell_set), "all"))
  stopifnot(is.data.frame(det$outputs), nrow(det$outputs) >= 1)
  stopifnot(any(as.character(det$outputs$output_name) == "markers"))

  replay <- wb_prov_emit_r_script(
    b,
    snapshot_id = sid,
    bundle_dir_literal = "/tmp/replay_bundle",
    mode = "symbolic"
  )
  stopifnot(is.character(replay), length(replay) == 1)
  stopifnot(grepl("snapshot_id", replay, fixed = TRUE))
  stopifnot(grepl("wb_session_run_op", replay, fixed = TRUE))
  stopifnot(grepl(r1$run_id, replay, fixed = TRUE))
  stopifnot(grepl(r2$run_id, replay, fixed = TRUE))
  stopifnot(!grepl("cell_ids", replay, fixed = TRUE))
  stopifnot(grepl("recorded_inputs <- list\\(", replay))
  stopifnot(!grepl("params_json_txt", replay, fixed = TRUE))
  replay_lines <- strsplit(replay, "\n", fixed = TRUE)[[1]]
  stopifnot(max(nchar(replay_lines, type = "chars")) < 3500)

  replay_raw <- wb_prov_emit_r_script(
    b,
    snapshot_id = sid,
    bundle_dir_literal = "/tmp/replay_bundle",
    mode = "symbolic",
    style = "raw_json"
  )
  stopifnot(grepl("params_json_txt", replay_raw, fixed = TRUE))
  stopifnot(grepl("fromJSON", replay_raw, fixed = TRUE))

  sidecar <- file.path(tempdir(), paste0("prov_replay_", as.integer(Sys.time()), ".rds"))
  replay_lit <- wb_prov_emit_r_script(
    b,
    snapshot_id = sid,
    bundle_dir_literal = "/tmp/replay_bundle",
    mode = "literal",
    sidecar_rds_path = sidecar
  )
  stopifnot(file.exists(sidecar))
  lit_payload <- base::readRDS(sidecar)
  stopifnot(is.list(lit_payload), length(lit_payload) >= 2)
  stopifnot(is.character(lit_payload[[r1$run_id]]$params$vec_param))
  stopifnot(length(lit_payload[[r1$run_id]]$params$vec_param) == 2)
  stopifnot(is.character(replay_lit), length(replay_lit) == 1)
  stopifnot(grepl("readRDS", replay_lit, fixed = TRUE))
  stopifnot(grepl(basename(sidecar), replay_lit, fixed = TRUE))

  freeze_dir <- file.path(tempdir(), paste0("scwb_freeze_", as.integer(Sys.time())))
  fr <- wb_freeze_snapshot(
    bundle = b,
    out_dir = freeze_dir,
    snapshot_id = sid,
    include_literal = TRUE,
    replay_style = "bench_pretty",
    validate_replay = TRUE
  )
  stopifnot(is.list(fr), identical(as.character(fr$snapshot_id), sid))
  stopifnot(file.exists(file.path(freeze_dir, "manifest.json")))
  stopifnot(file.exists(file.path(freeze_dir, "dag.json")))
  stopifnot(file.exists(file.path(freeze_dir, "runs.csv")))
  stopifnot(file.exists(file.path(freeze_dir, "outputs.csv")))
  stopifnot(file.exists(file.path(freeze_dir, "replay_symbolic.R")))
  stopifnot(file.exists(file.path(freeze_dir, "replay_literal.R")))
  stopifnot(file.exists(file.path(freeze_dir, "replay_inputs.rds")))
  stopifnot(file.exists(file.path(freeze_dir, "validation.json")))

  packet_dir <- file.path(tempdir(), paste0("scwb_packet_", as.integer(Sys.time())))
  fp <- wb_freeze_packet(
    bundle = b,
    out_dir = packet_dir,
    snapshot_id = sid,
    include_literal = TRUE,
    replay_style = "bench_pretty",
    validate_replay = TRUE,
    validation_profile = "kind_only",
    include_report = TRUE
  )
  stopifnot(is.list(fp), identical(as.character(fp$snapshot_id), sid))
  stopifnot(file.exists(file.path(packet_dir, "manifest.json")))
  stopifnot(file.exists(file.path(packet_dir, "report_draft.md")))

  TRUE
}
