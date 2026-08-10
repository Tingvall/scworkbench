test_file_backed_dense_space_corruption_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) {
    return(contract_test_skip("rhdf5 is not installed."))
  }
  root <- tempfile("scwb_dense_corruption_")
  base <- file.path(root, "base")
  dir.create(root, recursive = TRUE)
  b <- wb_init_bundle(base, overwrite = TRUE)
  cells <- paste0("cell_", seq_len(16L))
  wb_define_cells(b, cells)
  coords <- outer(seq_along(cells), 1:3, function(i, j) i + j / 10)
  rownames(coords) <- cells; colnames(coords) <- paste0("dim", 1:3)
  wb_add_space(b, "latent", coords, source = "corruption_contract")
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  clone <- function(name) {
    dst <- file.path(root, name)
    dir.create(dst, recursive = TRUE)
    entries <- list.files(base, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    stopifnot(all(file.copy(entries, dst, recursive = TRUE, copy.date = TRUE)))
    dst
  }
  payload_rel <- function(path) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    as.character(DBI::dbGetQuery(con, "SELECT path FROM space_payloads WHERE space_id='latent'")$path[[1L]])
  }
  mutate_db <- function(path, sql) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con, sql)
  }
  assert_code <- function(path, code) {
    report <- wb_bundle_validation_report(path, level = "content")
    stopifnot(!isTRUE(report$ok), code %in% as.character(report$diagnostics$code))
  }

  p <- clone("missing"); unlink(file.path(p, payload_rel(p))); assert_code(p, "SPACE_PAYLOAD_MISSING")
  p <- clone("truncated"); writeBin(raw(), file.path(p, payload_rel(p))); assert_code(p, "SPACE_PAYLOAD_DATASET_MISSING")
  p <- clone("byte_mutated"); h5 <- file.path(p, payload_rel(p))
  value <- rhdf5::h5read(h5, "coordinates", index = list(1L, 1L))
  rhdf5::h5write(as.numeric(value) + .Machine$double.eps, h5, "coordinates", index = list(1L, 1L))
  assert_code(p, "SPACE_PAYLOAD_CONTENT_HASH_MISMATCH")

  p <- clone("wrong_cell_order"); h5 <- file.path(p, payload_rel(p)); ids <- rhdf5::h5read(h5, "cell_ids"); rhdf5::h5write(rev(ids), h5, "cell_ids")
  assert_code(p, "SPACE_PAYLOAD_CELL_ORDER_MISMATCH")
  p <- clone("wrong_shape"); mutate_db(p, "UPDATE space_payloads SET n_cells=n_cells+1 WHERE space_id='latent'")
  assert_code(p, "SPACE_PAYLOAD_REGISTRY_MISMATCH")
  p <- clone("unknown_version"); h5 <- file.path(p, payload_rel(p)); handle <- rhdf5::H5Fopen(h5); rhdf5::h5writeAttribute("scworkbench.dense-space.hdf5.v999", handle, "schema_version"); rhdf5::H5Fclose(handle)
  assert_code(p, "SPACE_PAYLOAD_VERSION_UNKNOWN")
  p <- clone("registry_mismatch"); mutate_db(p, "UPDATE space_payloads SET dtype='float32' WHERE space_id='latent'")
  assert_code(p, "SPACE_PAYLOAD_REGISTRY_MISMATCH")
  p <- clone("path_escape"); mutate_db(p, "UPDATE space_payloads SET path='../escaped.h5' WHERE space_id='latent'")
  assert_code(p, "SPACE_PAYLOAD_PATH_ESCAPE")

  p <- clone("symlink_escape"); rel <- payload_rel(p); original <- file.path(p, rel); outside <- file.path(root, "outside.h5")
  stopifnot(file.copy(original, outside)); unlink(original); stopifnot(file.symlink(outside, original))
  assert_code(p, "SPACE_PAYLOAD_PATH_SYMLINK_ESCAPE")
  invisible(TRUE)
}
