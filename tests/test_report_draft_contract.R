test_report_draft_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  s <- wb_session_new()

  r1 <- wb_new_run(
    op_name = "synthetic_core_categorical_labels",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = character(0),
      user_inputs = list(resolution = 0.8)
    ),
    params = list(resolution = 0.8, k = 30L),
    outputs = list(clusters = wb_prim_cell_vector(c("c1" = "A", "c2" = "B"))),
    notes = "clusters"
  )
  r2 <- wb_new_run(
    op_name = "synthetic_named_terminal_report",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = c(r1$run_id),
      user_inputs = list(clusters_ref = wb_ref_run(r1$run_id, "clusters"))
    ),
    params = list(top_n = 20L, min_pct = 0.1),
    outputs = list(
      report_table = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(2, 1), stringsAsFactors = FALSE),
        table_type = "synthetic_named_terminal_report"
      )
    ),
    notes = "markers"
  )

  s <- wb_session_add_run(s, r1)
  s <- wb_session_add_run(s, r2)
  s <- wb_session_set_active(s, "clusters", wb_ref_run(r1$run_id, "clusters"))
  s <- wb_session_set_active(s, "report_table", wb_ref_run(r2$run_id, "report_table"))

  m <- wb_report_methods(session = s, bundle = b)
  stopifnot(is.list(m))
  stopifnot(is.character(m$text), length(m$text) == 1)
  stopifnot(length(m$lines) >= 2)
  stopifnot(any(grepl("synthetic_core_categorical_labels", m$text, fixed = TRUE)))
  stopifnot(any(grepl("synthetic_named_terminal_report", m$text, fixed = TRUE)))
  stopifnot(is.data.frame(m$run_table), nrow(m$run_table) >= 2)

  rep <- wb_report_draft(
    bundle = b,
    session = s,
    question = "What markers distinguish clusters?",
    include_dag = TRUE
  )
  stopifnot(is.list(rep))
  stopifnot(is.list(rep$metadata), is.list(rep$summary))
  stopifnot(is.list(rep$methods), is.list(rep$results))
  stopifnot(is.list(rep$dag))
  stopifnot(rep$summary$n_runs >= 2)
  stopifnot(is.data.frame(rep$results$outputs), nrow(rep$results$outputs) >= 2)
  stopifnot(any(rep$results$outputs$output == "clusters"))
  stopifnot(any(rep$results$outputs$output == "report_table"))
  stopifnot(is.data.frame(rep$dag$nodes), nrow(rep$dag$nodes) >= 2)

  md <- wb_report_render_md(rep, include_dag_text = TRUE)
  stopifnot(is.character(md), length(md) == 1)
  stopifnot(grepl("# Analysis Report \\(Draft\\)", md))
  stopifnot(grepl("## Methods", md, fixed = TRUE))
  stopifnot(grepl("## DAG", md, fixed = TRUE))

  TRUE
}
