.numeric_table_bytes <- function(x) writeBin(x, raw(), size = 8L)

.numeric_table_publish <- function(bundle, table, kind = "feature_table") {
  prim <- if (kind == "feature_table") wb_prim_feature_table(table,
    meta = list(label = "precision fixture")) else wb_prim_obs_table(table,
    meta = list(label = "precision fixture"))
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim),
    notes = "Synthetic numeric storage fixture; no biological workflow.")
  result <- wb_promote_analysis(bundle, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- result$promoted$artifact_id[[1L]]
  claim <- scworkbench:::.wb_prov_payload_identity(bundle, prim)
  stopifnot(identical(claim$content_sha256,
    scworkbench:::.wb_prov_stored_table_content_sha256(bundle$con, id)),
    identical(claim$content_identity_scheme,
      "scworkbench.content.table.typed-row-json-fold.v1"))
  list(id = id, prim = prim)
}

test_numeric_table_precision_types_missing_and_reopen_contract <- function() {
  root <- tempfile("numeric_table_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  values <- c(0.0499545077, .05 - .Machine$double.eps / 8,
    .05, .05 + .Machine$double.eps / 8, 1e-50, 1e-300, 0, 0,
    pi, .Machine$double.xmax, .Machine$double.xmin, 5e-324,
    NA_real_, NaN, Inf, -Inf)
  negative_zero <- raw(8L)
  negative_zero[[if (.Platform$endian == "little") 8L else 1L]] <- as.raw(128L)
  values[[8L]] <- readBin(negative_zero, double(), n = 1L,
    size = 8L, endian = .Platform$endian)
  table <- data.frame(feature_id = paste0("f", seq_along(values)),
    p_val_adj = values, integer = rep(c(NA_integer_, 1L), 8),
    integer_double = rep(1, 16), flag = rep(c(TRUE, FALSE, NA, TRUE), 4),
    label = rep(c("NA", "NaN", NA_character_, "雪"), 4),
    missing_double = rep(NA_real_, 16), missing_integer = rep(NA_integer_, 16),
    missing_logical = rep(NA, 16), missing_character = rep(NA_character_, 16))
  stopifnot(identical(wb_prim_feature_table(table)$table, table))
  stopifnot(tail(as.integer(writeBin(values[[8L]], raw(), size = 8L)), 1L) == 128L)
  stopifnot(scworkbench:::.wb_promotion_table_observable(wb_prim_feature_table(table)))
  a <- .numeric_table_publish(b, table)
  empty <- .numeric_table_publish(b, table[0, ], "obs_table")
  single <- .numeric_table_publish(b, data.frame(value = c(1, NA_real_)), "obs_table")
  # The old path remains available for historical primitives with no marker.
  old <- scworkbench:::.wb_prov_table_row_json(table, seq_len(nrow(table)))
  stopifnot(grepl('"p_val_adj":0.05', old[[1L]], fixed = TRUE))
  new <- DBI::dbGetQuery(b$con,
    "SELECT row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx",
    params = list(a$id))$row_json
  stopifnot(grepl('"p_val_adj":null', new[[13L]], fixed = TRUE),
    !identical(old, new))
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- wb_open_bundle(root, read_only = TRUE)
  actual <- wb_art_load(b, a$id)$table
  stopifnot(identical(vapply(actual, typeof, ""), vapply(table, typeof, "")),
    identical(actual, table),
    identical(.numeric_table_bytes(actual$p_val_adj), .numeric_table_bytes(values)),
    sum(actual$p_val_adj < .05, na.rm = TRUE) == sum(values < .05, na.rm = TRUE),
    identical(wb_art_load(b, empty$id)$table, table[0, ]),
    identical(wb_art_load(b, single$id)$table$value, c(1, NA_real_)),
    identical(wb_art_table_slice(b, a$id), table),
    identical(wb_art_table_slice(b, a$id, filters = list(feature_id = "absent")), table[0, ]),
    identical(wb_art_table_slice(b, a$id, filters = list(feature_id = "f1")), table[1, ]))
  certificate <- wb_entity_certificate(b, "artifact", a$id)
  stopifnot(identical(certificate$identity$verification_status, "content_verified"))
  wb_close_bundle(b); b <- NULL
  report <- wb_bundle_validation_report(root, level = "recipient")
  stopifnot(isTRUE(report$ok))
  # A fresh R process must reconstruct the same scientific values and types.
  output <- tempfile("numeric_fresh_process_", fileext = ".rds")
  on.exit(unlink(output), add = TRUE)
  code <- paste0('args <- commandArgs(TRUE); .libPaths(c(args[1], .libPaths())); ',
    'library(scworkbench); b <- wb_open_bundle(args[2], read_only=TRUE); ',
    'saveRDS(wb_art_load(b,args[3])$table,args[4]); wb_close_bundle(b)')
  child <- processx::run(file.path(R.home("bin"), "Rscript"),
    c("-e", code, dirname(find.package("scworkbench")), root, a$id, output),
    timeout = 60000, error_on_status = FALSE)
  stopifnot(child$status == 0L, identical(readRDS(output), table),
    identical(.numeric_table_bytes(readRDS(output)$p_val_adj), .numeric_table_bytes(values)))
  TRUE
}

test_numeric_table_fallback_and_legacy_contract <- function() {
  root <- tempfile("numeric_table_fallback_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  table <- data.frame(feature_id = c("a", "b"), value = c(pi, NA_real_),
    group = factor(c("a", "b")), day = as.Date(c("2020-01-01", "2020-01-02")))
  a <- .numeric_table_publish(b, table)
  actual <- wb_art_load(b, a$id)$table
  stopifnot(identical(actual$value, table$value),
    identical(.numeric_table_bytes(actual$value), .numeric_table_bytes(table$value)),
    identical(actual$group, as.character(table$group)),
    identical(actual$day, as.character(table$day)))
  stopifnot(identical(scworkbench:::.wb_prov_table_content_sha256(wb_art_load(b, a$id)),
    scworkbench:::.wb_prov_table_content_sha256(a$prim)))
  # Historical attributes/list classes remain a documented limitation, not
  # newly invented class restoration. Row-expanding nested values must fail.
  bad <- table; bad$list <- I(list(c(1, 2), c(3, 4)))
  stopifnot(inherits(try(scworkbench:::.wb_prov_table_content_sha256(wb_prim_feature_table(bad)), silent = TRUE), "try-error"))

  collision <- wb_prim_feature_table(data.frame(feature_id = "old", value = .0499545077),
    meta = list(storage_format = "scworkbench.table.typed-json.v1",
      columns = list(names = "value", types = "double"), meta = list(label = "old user metadata")))
  collision$table_storage <- NULL
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = collision))
  result <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  old_id <- result$promoted$artifact_id[[1L]]
  old_loaded <- wb_art_load(b, old_id)
  stopifnot(is.null(old_loaded$table_storage), old_loaded$table$value == .05,
    identical(old_loaded$meta, collision$meta),
    identical(scworkbench:::.wb_prov_stored_table_content_sha256(b$con, old_id),
      scworkbench:::.wb_prov_table_content_sha256(collision)))

  archive <- "tests/fixtures/provenance_legacy_table_96a37.tar.gz"
  expected_file <- "tests/fixtures/provenance_legacy_table_96a37_expected.rds"
  stopifnot(digest::digest(file = archive, algo = "sha256", serialize = FALSE) ==
      "8e950dce09deff4cec627ca8e21d4baa9c25fb11beb77e369dc7922ad9499462",
    digest::digest(file = expected_file, algo = "sha256", serialize = FALSE) ==
      "a57c4e0548445ed82da20bd7dc93307f0f860f42bbf0c80d4e6b002a06a34407")
  old_root <- tempfile("numeric_legacy_"); dir.create(old_root)
  on.exit(unlink(old_root, recursive = TRUE), add = TRUE)
  utils::untar(archive, exdir = old_root)
  expected <- readRDS(expected_file)
  legacy <- wb_open_bundle(file.path(old_root, "authentic.bundle"))
  on.exit(wb_close_bundle(legacy), add = TRUE)
  before <- DBI::dbGetQuery(legacy$con,
    "SELECT * FROM artifact_table_rows ORDER BY artifact_id,row_idx")
  loaded <- wb_art_load(legacy, expected$id)
  stopifnot(identical(unclass(loaded), unclass(expected$primitive)),
    is.null(loaded$table_storage),
    identical(before, DBI::dbGetQuery(legacy$con,
      "SELECT * FROM artifact_table_rows ORDER BY artifact_id,row_idx")))
  TRUE
}
