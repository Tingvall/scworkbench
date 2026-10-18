args <- commandArgs(TRUE)
.libPaths(c(args[[1]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2]]
dir.create(root, recursive = TRUE, showWarnings = FALSE)
io <- function() {
  z <- strsplit(readLines('/proc/self/io'), ': *')
  setNames(vapply(z, function(x) as.numeric(x[[2]]), 0),
    vapply(z, `[[`, '', 1L))
}
rows <- list()
measure <- function(name, code) {
  before <- io(); p <- proc.time(); ans <- force(code); p <- proc.time() - p
  delta <- io() - before
  rows[[length(rows) + 1L]] <<- data.frame(case = name,
    elapsed = unname(p[['elapsed']]), user = unname(p[['user.self']]),
    system = unname(p[['sys.self']]), rchar = delta[['rchar']],
    wchar = delta[['wchar']], read_bytes = delta[['read_bytes']],
    write_bytes = delta[['write_bytes']])
  cat('MEASUREMENT ', name, ' ', p[['elapsed']], ' seconds\n', sep = '')
  write.csv(do.call(rbind, rows), file.path(root, 'measurements.csv'), row.names = FALSE)
  ans
}
cells <- paste0('c', seq_len(300L))
metadata <- data.frame(cell_id = cells, group = rep(c('A','B','C'), 100L))
for (history in c(0L, 5L, 15L)) {
  path <- file.path(root, paste0('history_', history, '.bundle'))
  b <- measure(paste0('history_', history, '_initialize'), {
    b <- wb_init_bundle(path); wb_define_cells(b, cells)
    wb_attach_metadata(b, metadata); b
  })
  s <- measure(paste0('history_', history, '_session_create'),
    wb_session_create(b, file.path(root, 'sessions'), paste0('history_',history)))
  for (i in seq_len(history)) {
    rr <- wb_session_run_op(s, b, 'metadata_cell_vector', inputs = list(
      source_column = 'group', vector_name = paste0('prior_',i),
      value_type = 'categorical', missing_policy = 'error', overwrite = FALSE,
      cell_set = 'all', min_cells = 1L))
    s <- rr$session
  }
  rr <- measure(paste0('history_',history,'_final_operation'),
    wb_session_run_op(s, b, 'metadata_cell_vector', inputs = list(
      source_column = 'group', vector_name = 'final', value_type = 'categorical',
      missing_policy = 'error', overwrite = FALSE, cell_set = 'all', min_cells = 1L)))
  stopifnot(identical(as.character(rr$run$outputs$vector$value), metadata$group))
  measure(paste0('history_',history,'_promotion'),
    wb_session_promote_current(b, rr$session, outputs = 'vector'))
  measure(paste0('history_',history,'_finalize_reopen'), {
    wb_finalize_recipient_bundle(b); wb_close_bundle(b)
    rb <- wb_open_bundle(path, read_only = TRUE)
    stopifnot(nrow(wb_art_list(rb)) >= 1L); wb_close_bundle(rb)
  })
}
# Direct complete workflow: same input and output values, SQLite source/read/
# compute/output/write/reopen; no engine metadata/provenance contract claimed.
measure('direct_metadata_vector_complete', {
  path <- file.path(root, 'direct.sqlite')
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbWriteTable(con, 'metadata', metadata)
  values <- DBI::dbReadTable(con, 'metadata')
  output <- data.frame(cell_id = values$cell_id, value = as.character(values$group))
  DBI::dbWriteTable(con, 'vector', output); DBI::dbDisconnect(con)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  stopifnot(identical(DBI::dbReadTable(con,'vector'), output)); DBI::dbDisconnect(con)
})
cat('REPRESENTATIVE_HISTORY_AND_DIRECT_OK\n')
