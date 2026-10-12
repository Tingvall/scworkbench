test_graph_native_matrix_producer_run_frame_parity_contract <- function() {
  root <- tempfile("matrix_producer_frame_"); dir.create(root)
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(root, "producer.sqlite"))
  on.exit({DBI::dbDisconnect(con); unlink(root, recursive = TRUE)}, add = TRUE)
  DBI::dbExecute(con, paste0("CREATE TABLE prov_runs(op_name TEXT,params_json TEXT,inputs_json TEXT,",
    "symbolic_inputs_json TEXT,execution_inputs_json TEXT);"))
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  large <- paste0('{"label":"', strrep("東京é😀", 750000L), '"}')
  stopifnot(nchar(large, type = "bytes") > 8388608)
  for (params in list("{}", large, NA_character_)) {
    DBI::dbExecute(con, "DELETE FROM prov_runs;")
    values <- list("producer_東京", params, '{"x":"\\u00e9"}', "", NA_character_)
    DBI::dbExecute(con, "INSERT INTO prov_runs VALUES(?,?,?,?,?);", params = values)
    expected <- do.call(scworkbench:::.wb_prov_run_hash, values)
    observed <- scworkbench:::.wb_graph_matrix_producer_run_hash(con, 1L, policy)
    stopifnot(identical(expected, observed))
  }
  TRUE
}
