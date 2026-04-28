test_pybench_payload_parity_contract <- function(bundle_dir,
                                                 pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    message("Skipping pybench parity test: pybench interpreter not found at ", pybench_python)
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)
  con <- b$con

  stamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  rand <- paste0(sample(c(0:9, letters), 6, TRUE), collapse = "")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  base_id <- paste0("pybench_parity_", stamp, "_", rand)

  core <- wb_cells(b, "core")
  stopifnot(length(core) >= 5L)
  core5 <- as.character(core[1:5])

  art_ids <- list(
    cv = paste0("cell_vector_", base_id),
    cvf = paste0("cell_vector_family_", base_id),
    rf = paste0("relation_family_", base_id),
    pf = paste0("path_2d_family_", base_id),
    mr = paste0("model_ref_", base_id),
    ot = paste0("obs_table_", base_id),
    ft = paste0("feature_table_", base_id)
  )

  model_dir <- file.path(bundle_dir, "artifact_models")
  if (!dir.exists(model_dir)) dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  model_path <- file.path(model_dir, paste0(art_ids$mr, ".pkl"))
  writeBin(charToRaw("PYBENCH_PARITY_SMOKE"), model_path)

  cleanup <- function() {
    ids <- unname(unlist(art_ids, use.names = FALSE))
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_labels WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_relation_rows WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_pseudotime WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_curves_2d WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_model_ref WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_table_rows WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_tables WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifacts WHERE artifact_id IN (",
      paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = as.list(ids)), silent = TRUE)
    if (file.exists(model_path)) unlink(model_path, force = TRUE)
    invisible(TRUE)
  }
  on.exit(cleanup(), add = TRUE)

  prov_json <- jsonlite::toJSON(list(pybench_parity_smoke = TRUE), auto_unbox = TRUE)

  add_artifact_row <- function(artifact_id, type, name, input_space_id = NA_character_) {
    DBI::dbExecute(con, "
      INSERT INTO artifacts(
        artifact_id, type, name, description, created_at, created_by,
        source_op, input_space_id, input_matrix_id, cell_set,
        provenance_json, scworkbench_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ", params = list(
      artifact_id,
      type,
      name,
      NA_character_,
      created_at,
      "pybench-test",
      "pybench_test",
      input_space_id,
      NA_character_,
      "core",
      as.character(prov_json),
      as.character(utils::packageVersion("scworkbench"))
    ))
  }

  add_artifact_row(art_ids$cv, "cell_vector", "pybench parity cell_vector")
  add_artifact_row(art_ids$cvf, "cell_vector_family", "pybench parity cell_vector_family")
  add_artifact_row(art_ids$rf, "relation_family", "pybench parity relation_family")
  add_artifact_row(art_ids$pf, "path_2d_family", "pybench parity path_2d_family", input_space_id = "umap.peakvi_space")
  add_artifact_row(art_ids$mr, "model_ref", "pybench parity model_ref", input_space_id = "peakvi_space")
  add_artifact_row(art_ids$ot, "obs_table", "pybench parity obs_table")
  add_artifact_row(art_ids$ft, "feature_table", "pybench parity feature_table")

  cfg <- list(
    bundle_dir = normalizePath(bundle_dir, winslash = "/", mustWork = TRUE),
    writes = list(
      list(
        kind = "cell_vector",
        artifact_id = art_ids$cv,
        cell_id = core5,
        value = list(0.1, 0.2, 0.3, 0.4, 0.5),
        value_type = "continuous"
      ),
      list(
        kind = "relation_family",
        artifact_id = art_ids$rf,
        relation_key = c("root:Y_1::lineage:Y_9", "root:Y_1::lineage:Y_9", "root:Y_1::lineage:Y_10"),
        cell_id = core5[1:3],
        weight = c(1, 1, 1)
      ),
      list(
        kind = "cell_vector_family",
        artifact_id = art_ids$cvf,
        lineage_id = c("L1", "L1", "L2"),
        cell_id = core5[1:3],
        pseudotime = c(1.25, 2.5, 0.75)
      ),
      list(
        kind = "path_2d_family",
        artifact_id = art_ids$pf,
        lineage_id = c("root:Y_1::lineage:Y_9", "root:Y_1::lineage:Y_9", "root:Y_1::lineage:Y_9"),
        point = c(1, 2, 3),
        x = c(0, 1, 2),
        y = c(0.5, 1.5, 2.5)
      ),
      list(
        kind = "model_ref",
        artifact_id = art_ids$mr,
        engine = "pybench-smoke",
        model_space_id = "peakvi_space",
        in_space_id = "peakvi_space",
        model_type = "smoke",
        model_path = normalizePath(model_path, winslash = "/", mustWork = TRUE)
      ),
      list(
        kind = "obs_table",
        artifact_id = art_ids$ot,
        artifact_type = "obs_table",
        table_type = "generic",
        entity_kind = "pathway",
        meta = list(note = "pybench parity"),
        table_rows = list(
          list(pathway = "PWY_A", score = 1.25, padj = 0.01),
          list(pathway = "PWY_B", score = 0.75, padj = 0.05)
        )
      ),
      list(
        kind = "feature_table",
        artifact_id = art_ids$ft,
        artifact_type = "feature_table",
        table_type = "de_table",
        entity_kind = "feature",
        meta = list(engine = "pybench"),
        table_rows = list(
          list(feature_id = "GeneA", logFC = 1.5, pval = 0.001),
          list(feature_id = "GeneB", logFC = -0.7, pval = 0.02)
        )
      )
    )
  )

  cfg_path <- tempfile("pybench_parity_cfg_", fileext = ".json")
  py_path <- tempfile("pybench_parity_run_", fileext = ".py")
  on.exit(unlink(c(cfg_path, py_path), force = TRUE), add = TRUE)

  jsonlite::write_json(cfg, cfg_path, auto_unbox = TRUE, pretty = TRUE)
  writeLines(c(
    "import json, sys",
    "from pybench import open_bundle, close_bundle",
    "from pybench.artifacts_payload import (",
    "    write_artifact_cell_vector_payload,",
    "    write_artifact_cell_vector_family_payload,",
    "    write_artifact_relation_family_payload,",
    "    write_artifact_path_2d_family_payload,",
    "    write_artifact_model_ref_payload,",
    "    write_artifact_table_payload,",
    ")",
    "",
    "cfg = json.load(open(sys.argv[1]))",
    "b = open_bundle(cfg['bundle_dir'])",
    "try:",
    "    for w in cfg['writes']:",
    "        k = w['kind']",
    "        if k == 'cell_vector':",
    "            write_artifact_cell_vector_payload(b, artifact_id=w['artifact_id'], cell_id=w['cell_id'], value=w['value'], value_type=w.get('value_type', 'categorical'))",
    "        elif k == 'relation_family':",
    "            write_artifact_relation_family_payload(b, artifact_id=w['artifact_id'], relation_key=w['relation_key'], cell_id=w['cell_id'], weight=w.get('weight'), value=w.get('value'), distance=w.get('distance'))",
    "        elif k == 'cell_vector_family':",
    "            write_artifact_cell_vector_family_payload(b, artifact_id=w['artifact_id'], lineage_id=w['lineage_id'], cell_id=w['cell_id'], pseudotime=w['pseudotime'])",
    "        elif k == 'path_2d_family':",
    "            write_artifact_path_2d_family_payload(b, artifact_id=w['artifact_id'], lineage_id=w['lineage_id'], point=w['point'], x=w['x'], y=w['y'])",
    "        elif k == 'model_ref':",
    "            write_artifact_model_ref_payload(b, artifact_id=w['artifact_id'], engine=w['engine'], model_space_id=w['model_space_id'], in_space_id=w.get('in_space_id'), model_type=w.get('model_type'), model_path=w['model_path'])",
    "        elif k == 'obs_table':",
    "            write_artifact_table_payload(b, artifact_id=w['artifact_id'], artifact_type=w.get('artifact_type', 'obs_table'), table_rows=w['table_rows'], table_type=w.get('table_type', 'generic'), entity_kind=w.get('entity_kind', 'generic'), meta=w.get('meta'))",
    "        elif k == 'feature_table':",
    "            write_artifact_table_payload(b, artifact_id=w['artifact_id'], artifact_type=w.get('artifact_type', 'feature_table'), table_rows=w['table_rows'], table_type=w.get('table_type', 'generic'), entity_kind=w.get('entity_kind', 'feature'), meta=w.get('meta'))",
    "        else:",
    "            raise RuntimeError(f'unknown kind: {k}')",
    "finally:",
    "    close_bundle(b)"
  ), py_path)

  out <- system2(pybench_python, c(py_path, cfg_path), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status") %||% 0L
  if (!identical(status, 0L)) {
    stop("pybench parity payload write failed:\n", paste(out, collapse = "\n"), call. = FALSE)
  }

  # R-side loader is the truth test
  cv <- wb_art_load(b, art_ids$cv, expected_kind = "cell_vector")
  cvf <- wb_art_load(b, art_ids$cvf, expected_kind = "cell_vector_family")
  rf <- wb_art_load(b, art_ids$rf, expected_kind = "relation_family")
  pf <- wb_art_load(b, art_ids$pf, expected_kind = "path_2d_family")
  mr <- wb_art_load(b, art_ids$mr, expected_kind = "model_ref")
  # Debug-friendly validation for table payload JSON before loader parse.
  for (aid in c(art_ids$ot, art_ids$ft)) {
    info_row <- DBI::dbGetQuery(con, "SELECT meta_json FROM artifact_tables WHERE artifact_id = ?;", params = list(aid))
    stopifnot(nrow(info_row) == 1L)
    mj <- as.character(info_row$meta_json[[1]] %||% "{}")
    ok_meta <- tryCatch(jsonlite::validate(mj), error = function(e) {
      stop("Invalid meta_json for ", aid, ": ", conditionMessage(e), "\nJSON snippet: ", substr(mj, 1L, 400L), call. = FALSE)
    })
    stopifnot(ok_meta)
    row_jsons <- DBI::dbGetQuery(con, "SELECT row_json FROM artifact_table_rows WHERE artifact_id = ? ORDER BY row_idx;", params = list(aid))$row_json
    if (length(row_jsons)) {
      for (j in seq_along(row_jsons)) {
        txt <- as.character(row_jsons[[j]])
        ok_row <- tryCatch(jsonlite::validate(txt), error = function(e) {
          stop("Invalid row_json for ", aid, " row ", j, ": ", conditionMessage(e), "\nJSON snippet: ", substr(txt, 1L, 400L), call. = FALSE)
        })
        stopifnot(ok_row)
      }
    }
  }
  ot <- wb_art_load(b, art_ids$ot, expected_kind = "obs_table")
  ft <- wb_art_load(b, art_ids$ft, expected_kind = "feature_table")

  stopifnot(identical(as.character(cv$kind), "cell_vector"))
  stopifnot(identical(as.character(cv$value_type), "continuous"))
  cvv <- setNames(as.numeric(cv$value), as.character(cv$cell_id))
  stopifnot(all.equal(unname(cvv[core5]), c(0.1, 0.2, 0.3, 0.4, 0.5), tolerance = 1e-8))

  stopifnot(identical(as.character(cvf$kind), "cell_vector_family"))
  stopifnot(length(cvf$key) == 3L, length(cvf$cell_id) == 3L, length(cvf$value) == 3L)
  stopifnot(identical(as.character(cvf$value_type)[1], "continuous"))
  stopifnot(setequal(as.character(cvf$key), c("L1", "L2")))
  cvf_df <- data.frame(key = as.character(cvf$key), cell_id = as.character(cvf$cell_id), value = as.numeric(cvf$value), stringsAsFactors = FALSE)
  stopifnot(any(cvf_df$key == "L1" & cvf_df$cell_id == core5[1] & abs(cvf_df$value - 1.25) < 1e-8))
  stopifnot(any(cvf_df$key == "L1" & cvf_df$cell_id == core5[2] & abs(cvf_df$value - 2.5) < 1e-8))
  stopifnot(any(cvf_df$key == "L2" & cvf_df$cell_id == core5[3] & abs(cvf_df$value - 0.75) < 1e-8))

  stopifnot(identical(as.character(rf$kind), "relation_family"))
  rf_tbl <- wb_primitive_to_table(rf, include_context = FALSE)
  stopifnot(nrow(rf_tbl) == 3L)
  stopifnot(all(grepl("^root:[^:]+::lineage:[^:]+$", as.character(rf_tbl$key))))
  stopifnot(all(as.numeric(rf_tbl$weight) == 1))

  stopifnot(identical(as.character(pf$kind), "path_2d_family"))
  stopifnot(length(pf$key) == 3L, length(pf$point) == 3L, length(pf$x) == 3L, length(pf$y) == 3L)
  stopifnot(all(as.integer(pf$point) == c(1L, 2L, 3L)))
  stopifnot(all.equal(as.numeric(pf$x), c(0, 1, 2), tolerance = 1e-8))
  stopifnot(all.equal(as.numeric(pf$y), c(0.5, 1.5, 2.5), tolerance = 1e-8))

  stopifnot(identical(as.character(mr$kind), "model_ref"))
  stopifnot(identical(as.character(mr$engine), "pybench-smoke"))
  stopifnot(identical(as.character(mr$model_space_id), "peakvi_space"))
  stopifnot(identical(as.character(mr$in_space_id), "peakvi_space"))
  stopifnot(identical(as.character(mr$model_type), "smoke"))
  stopifnot(identical(normalizePath(mr$model_path, winslash = "/", mustWork = TRUE),
                      normalizePath(model_path, winslash = "/", mustWork = TRUE)))

  stopifnot(identical(as.character(ot$kind), "obs_table"))
  stopifnot(identical(as.character(ot$entity_kind), "pathway"))
  stopifnot(is.data.frame(ot$table), nrow(ot$table) == 2L)
  stopifnot(all(c("pathway", "score", "padj") %in% names(ot$table)))
  stopifnot(any(as.character(ot$table$pathway) == "PWY_A"))
  stopifnot(any(abs(as.numeric(ot$table$score) - 1.25) < 1e-8))

  stopifnot(identical(as.character(ft$kind), "feature_table"))
  stopifnot(is.data.frame(ft$table), nrow(ft$table) == 2L)
  stopifnot(all(c("feature_id", "logFC", "pval") %in% names(ft$table)))
  stopifnot(any(as.character(ft$table$feature_id) == "GeneA"))
  stopifnot(any(abs(as.numeric(ft$table$logFC) - 1.5) < 1e-8))

  TRUE
}
