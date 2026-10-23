test_pybench_typed_table_binding_contract <- function() {
  python <- Sys.getenv("PYBENCH_PARITY_PYTHON", unset = "")
  pythonpath <- Sys.getenv("PYBENCH_PARITY_PYTHONPATH", unset = "")
  stopifnot(file.exists(python), dir.exists(pythonpath))
  root <- tempfile("typed_pybench_bundle_")
  workspace <- tempfile("typed_pybench_workspace_")
  on.exit(unlink(c(root, workspace), recursive = TRUE, force = TRUE), add = TRUE)
  bundle <- wb_init_bundle(root)
  on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
  wb_define_cells(bundle, c("c2", "c1"), set_name = "core")
  session <- wb_session_create(bundle, workspace, session_id = "typed_table_contract")
  stage <- wb_session_view(session)
  on.exit(try(wb_close_bundle(stage), silent = TRUE), add = TRUE)
  stage$pybench_session_binding <- list(
    session_id = session$session_id,
    source_attestation = list(scheme = "scworkbench-scientific-state-v1",
      content_sha256 = session$durable$source_identity$scientific_state_fingerprint),
    checkpoint_generation = session$durable$checkpoint_generation,
    root_sha256 = .wb_prov_sha256_object(list(session_id = session$session_id,
      stage_root = normalizePath(stage$dir, winslash = "/"))))
  declaration <- list(format = "scworkbench.table.typed-json.v1",
    columns = list(names = c("metric", "value", "cell_set"),
      types = c("character", "double", "character")))
  run <- wb_new_run("py_protocol_hello", inputs = list(cell_set = "all"),
    outputs = list())
  output <- list(summary = list(type = "obs_table", table_storage = declaration))
  .wb_with_mutation_context(bundle = stage, route = "session_execution",
    run_id = "typed_run", op_name = "py_protocol_hello", code = {
      id <- "obs_table_typed_probe"
      output$summary$artifact_id <- id
      request <- .wb_pybench_build_request(stage, "py_protocol_hello",
        "typed_run", inputs = list(cell_set = "all"),
        params = list(probe = TRUE), outputs = output)
      result <- .wb_pybench_run_module("pybench.ops.py_protocol_hello",
        request, bundle = stage, python_bin = python,
        env = paste0("PYTHONPATH=", pythonpath),
        prepare_transition = function(clone, request)
          .wb_pybench_preregister_outputs(clone, run,
            list(summary = c(output$summary, list(artifact_id = id)))))
      stopifnot(identical(result$receipt$status, "ok"))
      loaded <- wb_art_load(stage, id, expected_kind = "obs_table")
      stopifnot(identical(loaded$table_storage$columns$names,
          declaration$columns$names),
        identical(loaded$table_storage$columns$types,
          declaration$columns$types),
        identical(loaded$table$metric, "n_cells_written"),
        identical(loaded$table$value, 2),
        identical(loaded$table$cell_set, "all"),
        identical(.wb_prov_table_content_sha256(loaded),
          .wb_prov_stored_table_content_sha256(stage$con, id)))
    })
  adversarial <- list(format = "scworkbench.table.typed-json.v1",
    columns = list(names = c("feature id", "p_val_adj", "count", "flag", "label",
      "missing double", "missing integer", "missing logical", "missing character"),
      types = c("character", "double", "integer", "logical", "character",
        "double", "integer", "logical", "character")))
  adversarial_id <- "obs_table_adversarial_probe"
  adversarial_output <- list(table = list(type = "obs_table",
    artifact_id = adversarial_id, table_storage = adversarial))
  .wb_with_mutation_context(bundle = stage, route = "session_execution",
    run_id = "typed_adversarial", op_name = "typed_table_probe", code = {
      request <- .wb_pybench_build_request(stage, "typed_table_probe",
        "typed_adversarial", inputs = list(cell_set = "all"),
        params = list(case = "adversarial"), outputs = adversarial_output)
      result <- .wb_pybench_run_module("typed_table_probe", request,
        bundle = stage, python_bin = python,
        env = paste0("PYTHONPATH=", pythonpath, ":",
          file.path(dirname(pythonpath), "tests", "support")),
        prepare_transition = function(clone, request)
          .wb_pybench_preregister_outputs(clone, run, adversarial_output))
      stopifnot(identical(result$receipt$status, "ok"))
      loaded <- wb_art_load(stage, adversarial_id,
        expected_kind = "obs_table")
      expected <- c(0.0499545077, 0.049999999999999996, 0.05,
        0.05000000000000001, 1e-50, 1e-300, 0, 0, pi,
        .Machine$double.xmax, .Machine$double.xmin, 5e-324,
        NA_real_, NaN, Inf, -Inf)
      negative_zero <- raw(8L)
      negative_zero[[if (.Platform$endian == "little") 8L else 1L]] <- as.raw(128L)
      expected[[8L]] <- readBin(negative_zero, double(), n = 1L,
        size = 8L, endian = .Platform$endian)
      stopifnot(tail(as.integer(writeBin(expected[[8L]], raw(), size = 8L)),
        1L) == 128L)
      wrong <- which(!vapply(seq_along(expected), function(i)
        identical(writeBin(loaded$table$p_val_adj[[i]], raw(), size = 8L),
          writeBin(expected[[i]], raw(), size = 8L)), logical(1)))
      if (length(wrong)) stop("Python-to-R double bit mismatch at rows: ",
        paste(wrong, collapse = ", "))
      stopifnot(identical(loaded$table_storage$columns$names,
          adversarial$columns$names),
        identical(loaded$table_storage$columns$types,
          adversarial$columns$types),
        identical(writeBin(loaded$table$p_val_adj, raw(), size = 8L),
          writeBin(expected, raw(), size = 8L)),
        identical(loaded$table$label[[1L]], "NA"),
        identical(loaded$table$label[[2L]], "Inf"),
        identical(loaded$table$label[[3L]], "雪"),
        identical(typeof(loaded$table$count), "integer"),
        identical(typeof(loaded$table$flag), "logical"),
        all(is.na(loaded$table$`missing double`)),
        sum(loaded$table$p_val_adj < .05, na.rm = TRUE) ==
          sum(expected < .05, na.rm = TRUE),
        identical(.wb_prov_table_content_sha256(loaded),
          .wb_prov_stored_table_content_sha256(stage$con, adversarial_id)))
    })
  expected_table <- wb_art_load(stage, adversarial_id)$table
  before_listing <- .wb_prov_stored_table_content_sha256(stage$con, adversarial_id)
  light <- wb_art_list(stage)
  full <- wb_art_list(stage, include_provenance = TRUE)
  stopifnot(adversarial_id %in% light$artifact_id,
    !"provenance_json" %in% names(light),
    "provenance_json" %in% names(full),
    identical(light, full[, setdiff(names(full), "provenance_json")]),
    identical(wb_art_load(stage, adversarial_id)$table, expected_table),
    identical(.wb_prov_stored_table_content_sha256(stage$con, adversarial_id),
      before_listing))
  empty_output <- adversarial_output
  empty_output$table$artifact_id <- "obs_table_empty_probe"
  .wb_with_mutation_context(bundle = stage, route = "session_execution",
    run_id = "typed_empty", op_name = "typed_table_probe", code = {
      request <- .wb_pybench_build_request(stage, "typed_table_probe", "typed_empty",
        inputs = list(cell_set = "all"), params = list(case = "empty"),
        outputs = empty_output)
      .wb_pybench_run_module("typed_table_probe", request, bundle = stage,
        python_bin = python, env = paste0("PYTHONPATH=", pythonpath, ":",
          file.path(dirname(pythonpath), "tests", "support")),
        prepare_transition = function(clone, request)
          .wb_pybench_preregister_outputs(clone, run, empty_output))
      empty <- wb_art_load(stage, empty_output$table$artifact_id)
      stopifnot(identical(empty$table, expected_table[0, ]),
        identical(.wb_prov_table_content_sha256(empty),
          .wb_prov_stored_table_content_sha256(stage$con,
            empty_output$table$artifact_id)))
    })
  fresh_output <- tempfile(fileext = ".rds")
  on.exit(unlink(fresh_output), add = TRUE)
  fresh_code <- paste('a<-commandArgs(TRUE);.libPaths(c(a[1],.libPaths()));library(scworkbench);',
    'b<-wb_open_bundle(a[2],validate=FALSE,read_only=TRUE);',
    'p<-wb_art_load(b,a[3]);stopifnot(identical(scworkbench:::.wb_prov_table_content_sha256(p),',
    'scworkbench:::.wb_prov_stored_table_content_sha256(b$con,a[3])));',
    'saveRDS(p$table,a[4]);wb_close_bundle(b)')
  for (case in c("wrong_order", "wrong_type", "wrong_meta", "forged_schema")) {
    bad_id <- paste0("obs_table_rejected_", case)
    bad_output <- list(table = list(type = "obs_table", artifact_id = bad_id,
      table_storage = adversarial))
    .wb_with_mutation_context(bundle = stage, route = "session_execution",
      run_id = paste0("typed_", case), op_name = "typed_table_probe", code = {
        request <- .wb_pybench_build_request(stage, "typed_table_probe",
          paste0("typed_", case), inputs = list(cell_set = "all"),
          params = list(case = case), outputs = bad_output)
        failure <- tryCatch(.wb_pybench_run_module("typed_table_probe", request,
          bundle = stage, python_bin = python,
          env = paste0("PYTHONPATH=", pythonpath, ":",
            file.path(dirname(pythonpath), "tests", "support")),
          prepare_transition = function(clone, request)
            .wb_pybench_preregister_outputs(clone, run, bad_output)), error = identity)
        stopifnot(inherits(failure, "error"))
        if (case == "forged_schema") stopifnot(grepl("DECLARATION_MISMATCH",
          conditionMessage(failure), fixed = TRUE))
        for (name in c("artifacts", "artifact_tables", "artifact_table_rows")) {
          rows <- DBI::dbGetQuery(stage$con, paste0("SELECT count(*) n FROM ",
            name, " WHERE artifact_id=?"), params = list(bad_id))
          stopifnot(rows$n[[1L]] == 0L)
        }
      })
  }
  if (identical(Sys.getenv("PYBENCH_TYPED_MEASURE"), "1")) {
    schema <- list(format = "scworkbench.table.typed-json.v1", columns = list(
      names = c("gene", "p_adj", "logfc", "score", "count", "flag", "group", "missing"),
      types = c("character", "double", "double", "double", "integer", "logical", "character", "double")))
    for (n in c(5000L, 20000L)) {
      id <- paste0("obs_table_bench_", n)
      output <- list(table = list(type = "obs_table", artifact_id = id,
        table_storage = schema))
      .wb_with_mutation_context(bundle = stage, route = "session_execution",
        run_id = paste0("typed_bench_", n), op_name = "typed_table_probe", code = {
          request <- .wb_pybench_build_request(stage, "typed_table_probe",
            paste0("typed_bench_", n), inputs = list(cell_set = "all"),
            params = list(case = "benchmark", n_rows = n), outputs = output)
          elapsed <- system.time(.wb_pybench_run_module("typed_table_probe", request,
            bundle = stage, python_bin = python,
            env = paste0("PYTHONPATH=", pythonpath, ":",
              file.path(dirname(pythonpath), "tests", "support")),
            prepare_transition = function(clone, request)
              .wb_pybench_preregister_outputs(clone, run, output)))[["elapsed"]]
          read_time <- system.time(table <- wb_art_load(stage, id)$table)[["elapsed"]]
          i <- 0:(n - 1L)
          expected <- data.frame(gene = paste0("gene_", i), p_adj = (i %% 1000L)/20000,
            logfc = (i %% 37L - 18L)/7, score = (i %% 101L)/13,
            count = i %% 500L, flag = i %% 2L == 0L,
            group = ifelse(i %% 2L != 0L, "A", "B"),
            missing = ifelse(i %% 11L == 0L, NA_real_, (i %% 23L)/9))
          stopifnot(identical(table, expected),
            identical(writeBin(table$logfc, raw(), size = 8L),
              writeBin(expected$logfc, raw(), size = 8L)))
          cat("BRIDGE_MEASURE rows=", n, " transition_seconds=", elapsed,
            " R_read_seconds=", read_time, "\n", sep = "")
        })
    }
  }
  # The native bridge publishes into a session stage. Transfer only after
  # canonical terminal promotion and recipient finalization, not from a live WAL.
  retained <- wb_art_load(stage, adversarial_id)
  canonical <- wb_new_run("metadata_cell_vector", outputs = list(vector = retained),
    notes = "Synthetic Python-produced typed table promotion fixture")
  promoted <- wb_promote_analysis(bundle, setNames(list(canonical), canonical$run_id),
    canonical$run_id, outputs = "vector")
  committed_id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(wb_finalize_recipient_bundle(bundle)$ready)
  wb_close_bundle(bundle)
  fresh <- processx::run(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "-e", fresh_code, dirname(find.package("scworkbench")),
      root, committed_id, fresh_output), timeout = 60000,
    error_on_status = FALSE)
  if (fresh$status != 0L) stop(fresh$stderr)
  stopifnot(identical(readRDS(fresh_output), expected_table),
    identical(writeBin(readRDS(fresh_output)$p_val_adj, raw(), size = 8L),
      writeBin(expected_table$p_val_adj, raw(), size = 8L)))
  TRUE
}

test_typed_reader_true_zero_and_quoted_token_contract <- function() {
  table <- data.frame(`key ":-0` = c(1 / -Inf, 0, 1 / -Inf),
    label = c('embedded \":-0,} and backslash \\', '-0', '雪:-0,}'),
    value = c(0, 1 / -Inf, NA_real_), check.names = FALSE)
  storage <- .wb_table_storage(wb_prim_obs_table(table))
  text <- .wb_table_typed_row_json(table, seq_len(nrow(table)), storage)
  decoded <- .wb_table_typed_rows_to_df(data.frame(row_json = text), storage)
  stopifnot(identical(table, decoded),
    identical(writeBin(table[[1]], raw(), size = 8L),
      writeBin(decoded[[1]], raw(), size = 8L)),
    identical(writeBin(table$value, raw(), size = 8L),
      writeBin(decoded$value, raw(), size = 8L)))
  TRUE
}
