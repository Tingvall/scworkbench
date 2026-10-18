# Literal pre-change getter assembly. Deliberately retain parsing ALL rows
# before conversion so late malformed JSON remains the first observed error.
.engine_table_columns_old <- function(rows) {
  if (!is.data.frame(rows) || !nrow(rows)) {
    return(data.frame(stringsAsFactors = FALSE))
  }
  rr <- lapply(rows$row_json, jsonlite::fromJSON, simplifyVector = FALSE)
  rr <- lapply(rr, function(x) {
    if (is.list(x) && length(x)) {
      is_null <- vapply(x, is.null, logical(1))
      if (any(is_null)) {
        for (nm in names(x)[is_null]) x[[nm]] <- NA
      }
    }
    x
  })
  rr <- lapply(rr, as.data.frame, stringsAsFactors = FALSE)
  out <- do.call(rbind, rr)
  rownames(out) <- NULL
  out
}

.engine_table_columns_observe <- function(helper, json) {
  warnings <- character()
  value <- withCallingHandlers(tryCatch(helper(data.frame(row_json = json)),
    error = function(e) list(error_class = class(e), message = conditionMessage(e))),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
  list(value = value, warnings = warnings)
}

test_engine_table_scalar_columns_types_order_and_positive_contract <- function() {
  rows <- c('{"z":2,"a":1.5,"label":"quote\\\"\\n雪","flag":true,"empty":null}',
    '{"z":null,"a":2,"label":"","flag":null,"empty":null}',
    '{"z":-3,"a":null,"label":null,"flag":false,"empty":null}')
  actual <- scworkbench:::.wb_art_table_rows_to_df
  stopifnot(identical(.engine_table_columns_observe(actual, rows),
    .engine_table_columns_observe(.engine_table_columns_old, rows)))
  parsed <- lapply(rows, jsonlite::fromJSON, simplifyVector = FALSE)
  parsed <- lapply(parsed, function(x) {
    for (name in names(x)[vapply(x, is.null, logical(1))]) x[[name]] <- NA
    x
  })
  fast <- scworkbench:::.wb_art_table_scalar_columns(parsed)
  stopifnot(is.data.frame(fast), identical(fast, .engine_table_columns_old(data.frame(row_json = rows))),
    identical(names(fast), c("z", "a", "label", "flag", "empty")),
    identical(vapply(fast, typeof, character(1)),
      c(z = "integer", a = "double", label = "character", flag = "logical", empty = "logical")))
  # Integer/double promotion and numeric NA are distinct from neutral logical NA.
  rr <- list(list(x = 1L, y = NA_real_), list(x = 1.25, y = NA))
  stopifnot(identical(scworkbench:::.wb_art_table_scalar_columns(rr),
    data.frame(x = c(1, 1.25), y = c(NA_real_, NA_real_))))
  boundaries <- c('{"x":-0.0,"y":1.7976931348623157e308}',
    '{"x":0.0,"y":-1.7976931348623157e308}', '{"x":1e-300,"y":null}')
  stopifnot(identical(.engine_table_columns_observe(actual, boundaries),
    .engine_table_columns_observe(.engine_table_columns_old, boundaries)))
  numeric_rows <- c('{"x":null}', '{"x":1}', '{"x":1.0}', '{"x":null}',
    '{"x":-0.0}', '{"x":0.0}', '{"x":2147483648}',
    '{"x":9007199254740992}', '{"x":9007199254740993}',
    '{"x":1e-300}', '{"x":1.7976931348623157e308}', '{"x":null}')
  for (json in list(numeric_rows, rev(numeric_rows),
      c(rep('{"x":null}', 1200L), '{"x":1.25}', '{"x":1}'),
      c('{"x":1}', '{"x":1.25}', rep('{"x":null}', 1200L)))) {
    expected <- .engine_table_columns_observe(.engine_table_columns_old, json)
    observed <- .engine_table_columns_observe(actual, json)
    stopifnot(identical(expected, observed),
      identical(writeBin(expected$value$x, raw()), writeBin(observed$value$x, raw())))
  }
  TRUE
}

test_engine_table_scalar_columns_fallback_and_error_precedence_contract <- function() {
  actual <- scworkbench:::.wb_art_table_rows_to_df
  cases <- list(character(), c('{}', '{}'), c('null', '{}'),
    c('{"a":[1,2]}', '{"a":[3,4]}'), c('{"a":{"nested":1}}', '{"a":{"nested":2}}'),
    c('{"a":1}', '{"b":2}'), c('{"a":1,"b":2}', '{"b":3,"a":4}'),
    c('{"a":1,"a":2}', '{"a":3,"a":4}'),
    c('{"a b":1,"row.names":2}', '{"a b":3,"row.names":4}'),
    c('{"stringsAsFactors":1}', '{"stringsAsFactors":2}'),
    c('{"...":1,"check.names":2}', '{"...":3,"check.names":4}'),
    c('{"a":true}', '{"a":2}'), c('{"a":"1"}', '{"a":2}'),
    c('{"a":[]}', '{"a":1}'), c('{"a":[]}', '{broken'),
    c('{"a":null,"a":1}', '{"a":2,"a":null}'))
  for (rows in cases) stopifnot(identical(.engine_table_columns_observe(actual, rows),
    .engine_table_columns_observe(.engine_table_columns_old, rows)))
  for (rr in list(list(list(x = 1L), list(x = TRUE)),
      list(list(x = structure(1, custom = TRUE))),
      list(structure(list(x = 1), custom = TRUE)), list(list(x = integer()))))
    stopifnot(is.null(scworkbench:::.wb_art_table_scalar_columns(rr)))
  TRUE
}

test_engine_table_scalar_columns_admission_and_guard_contract <- function() {
  helper <- scworkbench:::.wb_art_table_scalar_columns
  old <- options(scworkbench.max_dense_materialize_mb = 256)
  on.exit(options(old), add = TRUE)
  rr <- rep(list(list(x = 1L, label = "a")), 40L)
  stopifnot(is.data.frame(helper(rr)))
  for (guard in list(.001, NA_real_, "unknown", structure(256, custom = TRUE))) {
    options(scworkbench.max_dense_materialize_mb = guard)
    stopifnot(is.null(helper(rr)))
  }
  # A classed numeric guard must not invoke user-defined numerical methods.
  env <- environment(helper); fake <- new.env(parent = env)
  fake$is.finite <- function(x) stop("Unexpected guard dispatch")
  local <- helper; environment(local) <- fake
  options(scworkbench.max_dense_materialize_mb = structure(256, class = "custom_guard"))
  stopifnot(is.null(local(rr)))
  options(scworkbench.max_dense_materialize_mb = .3)
  long <- setNames(list(1L), strrep("x", 10000L))
  stopifnot(is.null(helper(list(long))))
  # No source-extent N*C metadata is retained: scalar preflight plus one
  # current result column. Source rr and the returned table are materialized
  # by the existing getter contract, not charged as invented bounded output.
  rows <- c('{"x":1,"label":"a"}', '{"x":null,"label":"b"}')
  stopifnot(identical(.engine_table_columns_observe(scworkbench:::.wb_art_table_rows_to_df, rows),
    .engine_table_columns_observe(.engine_table_columns_old, rows)))
  TRUE
}

test_engine_table_scalar_columns_public_identity_and_purity_contract <- function() {
  root <- tempfile("table_scalar_columns_"); b <- wb_init_bundle(root)
  on.exit(wb_close_bundle(b), add = TRUE)
  table <- data.frame(feature_id = c("f_2", "f_10", "f_1"),
    score = c(-0, NA_real_, .8), ordinal = c(NA_integer_, 2L, 1L),
    empty = rep(NA_real_, 3L), label = c("雪", "", "quote\"\\\n"))
  prim <- wb_prim_feature_table(table, table_type = "generic", meta = list(label = "retained"))
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim),
    notes = "Synthetic table storage fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- wb_open_bundle(root, read_only = TRUE)
  fingerprint <- function() {
    files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
      full.names = TRUE, no.. = TRUE)); files <- files[!file.info(files)$isdir]
    setNames(vapply(files, function(path) digest::digest(file = path,
      algo = "sha256"), character(1)), substring(files, nchar(root) + 2L))
  }
  before <- fingerprint(); actual <- wb_art_load(b, id)
  ns <- asNamespace("scworkbench"); original <- get(".wb_art_table_rows_to_df", ns)
  restore <- function() {
    unlockBinding(".wb_art_table_rows_to_df", ns)
    assign(".wb_art_table_rows_to_df", original, ns); lockBinding(".wb_art_table_rows_to_df", ns)
  }
  on.exit(restore(), add = TRUE, after = FALSE)
  unlockBinding(".wb_art_table_rows_to_df", ns)
  assign(".wb_art_table_rows_to_df", .engine_table_columns_old, ns)
  lockBinding(".wb_art_table_rows_to_df", ns)
  expected <- wb_art_load(b, id)
  # Capture BOTH legacy identities while the literal OLD normalizer is active,
  # including typed NA normalization and the original presentation metadata.
  legacy_payload <- scworkbench:::.wb_prov_table_payload(expected)
  legacy_original_payload <- scworkbench:::.wb_prov_table_payload(prim)
  legacy_v2_digest <- digest::digest(jsonlite::serializeJSON(legacy_payload, digits = NA),
    algo = "sha256", serialize = FALSE)
  legacy_content <- scworkbench:::.wb_prov_table_content_sha256(expected)
  legacy_original_content <- scworkbench:::.wb_prov_table_content_sha256(prim)
  restore()
  # Independent original fold over actual stored SQL header/row JSON. Numeric
  # NA was already stored as the literal string "NA" by the historical writer;
  # loading can consequently promote mixed numeric/string columns to character.
  # That historical stored-versus-reencoded difference is NOT repaired here.
  info <- DBI::dbGetQuery(b$con, paste0("SELECT a.type,t.table_type,t.entity_kind,t.meta_json ",
    "FROM artifacts a JOIN artifact_tables t ON t.artifact_id=a.artifact_id WHERE a.artifact_id=?"),
    params = list(id))
  header <- list(identity_version = "scworkbench.payload.table.stream.v1",
    kind = as.character(info$type[[1L]]), table_type = as.character(info$table_type[[1L]]),
    entity_kind = if (identical(info$type[[1L]], "obs_table")) as.character(info$entity_kind[[1L]]) else NULL,
    meta = jsonlite::fromJSON(info$meta_json[[1L]], simplifyVector = TRUE))
  oracle <- digest::digest(jsonlite::serializeJSON(header, digits = NA), algo = "sha256", serialize = FALSE)
  stored_rows <- DBI::dbGetQuery(b$con,
    "SELECT row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx", params = list(id))$row_json
  for (row in stored_rows) oracle <- digest::digest(jsonlite::serializeJSON(list(
    previous = oracle, row_sha256 = digest::digest(row, algo = "sha256", serialize = FALSE)),
    digits = NA), algo = "sha256", serialize = FALSE)
  stopifnot(identical(actual, expected), identical(actual$table, legacy_original_payload$table),
    identical(scworkbench:::.wb_prov_table_payload(actual), legacy_payload),
    identical(scworkbench:::.wb_prov_table_payload(prim), legacy_original_payload),
    identical(digest::digest(jsonlite::serializeJSON(scworkbench:::.wb_prov_table_payload(actual),
      digits = NA), algo = "sha256", serialize = FALSE), legacy_v2_digest),
    identical(scworkbench:::.wb_prov_table_content_sha256(actual), legacy_content),
    identical(scworkbench:::.wb_prov_table_content_sha256(prim), legacy_original_content),
    identical(scworkbench:::.wb_prov_stored_table_content_sha256(b$con, id), oracle),
    identical(oracle, legacy_original_content), !identical(oracle, legacy_content),
    identical(before, fingerprint()))
  TRUE
}
