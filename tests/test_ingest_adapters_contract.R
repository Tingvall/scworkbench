test_ingest_adapters_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  tag <- paste0(format(Sys.time(), "%Y%m%d%H%M%S"), "_", paste(sample(letters, 4, TRUE), collapse = ""))
  set_name <- paste0("ingest_adapter_", tag)
  ids <- paste0("ing_", tag, "_", 1:3)

  md <- data.frame(
    id_col = ids,
    donor = c("d1", "d1", "d2"),
    stringsAsFactors = FALSE
  )
  sp2d <- data.frame(
    cid = ids,
    x = c(0.1, 0.2, 0.3),
    y = c(1.1, 1.2, 1.3),
    stringsAsFactors = FALSE
  )

  v <- wb_ingest_validate(
    bundle = b,
    set_name = set_name,
    metadata = md,
    spaces = list(space_test_ingest = sp2d),
    strict = FALSE
  )
  stopifnot(is.list(v), isTRUE(v$valid), v$n_cells == 3)
  stopifnot(is.list(v$details))
  stopifnot(is.list(v$details$spaces))
  stopifnot("space_test_ingest" %in% names(v$details$spaces))

  nrm <- wb_ingest_normalize(
    bundle = b,
    set_name = set_name,
    metadata = md,
    spaces = list(space_test_ingest = sp2d)
  )
  stopifnot(is.list(nrm))
  stopifnot(identical(sort(nrm$cell_ids), sort(ids)))
  stopifnot(is.data.frame(nrm$metadata), "cell_id" %in% names(nrm$metadata))
  stopifnot(is.data.frame(nrm$spaces$space_test_ingest))
  stopifnot(is.list(nrm$report))

  dry <- wb_ingest_apply(
    bundle = b,
    set_name = set_name,
    metadata = md,
    spaces = list(space_test_ingest = sp2d),
    validate_only = TRUE
  )
  stopifnot(is.list(dry), isTRUE(dry$validated))
  stopifnot(is.list(dry$validation), isTRUE(dry$validation$valid))

  res <- wb_ingest_apply(
    bundle = b,
    set_name = set_name,
    metadata = md,
    spaces = list(space_test_ingest = sp2d),
    source = "test",
    created_by = "test",
    apply_mode = "atomic",
    emit_report_artifact = TRUE
  )
  stopifnot(is.list(res))
  stopifnot(identical(as.character(res$cell_set), paste0("set:", set_name)))
  rep <- attr(res, "ingest_report", exact = TRUE)
  stopifnot(is.list(rep), identical(as.character(rep$apply_mode), "atomic"))
  aid <- attr(res, "ingest_report_artifact_id", exact = TRUE)
  if (is.null(aid)) aid <- ""
  aid <- as.character(aid)[1]
  stopifnot(nzchar(aid))
  p <- wb_art_load(b, artifact_id = aid, expected_kind = "obs_table")
  stopifnot(identical(as.character(p$table_type), "ingest_report"))
  stopifnot(is.data.frame(p$table), nrow(p$table) >= 1)
  ir <- wb_ingest_reports(b, set_name = set_name, limit = 10)
  stopifnot(is.data.frame(ir), nrow(ir) >= 1)
  stopifnot(aid %in% as.character(ir$artifact_id))
  ig <- wb_ingest_report(b, artifact_id = aid, parse_json = TRUE)
  stopifnot(is.list(ig), is.data.frame(ig$metadata), is.data.frame(ig$table))
  stopifnot(nrow(ig$table) >= 1)
  stopifnot("validation" %in% names(ig$table))

  ing_set <- wb_cells(b, cell_set = paste0("set:", set_name))
  stopifnot(all(ids %in% ing_set))

  v2 <- wb_ingest_validate(
    bundle = b,
    set_name = set_name,
    cell_ids = ids,
    strict = FALSE
  )
  stopifnot(is.list(v2), !isTRUE(v2$valid), length(v2$errors) >= 1)

  TRUE
}
