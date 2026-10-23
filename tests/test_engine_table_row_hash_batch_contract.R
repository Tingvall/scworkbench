.engine_row_fold_oracle <- function(initial) {
  state <- initial
  function(row_json) {
    for (text in row_json) {
      row <- digest::digest(text, algo = "sha256", serialize = FALSE)
      state <<- digest::digest(jsonlite::serializeJSON(list(previous = state,
        row_sha256 = row), digits = NA), algo = "sha256", serialize = FALSE)
    }
    state
  }
}

.engine_row_hash_replace <- function(package, name, value) {
  ns <- asNamespace(package); old <- get(name, ns, inherits = FALSE)
  unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
  function() {
    unlockBinding(name, ns); assign(name, old, ns); lockBinding(name, ns)
  }
}

test_engine_table_row_hash_bytes_and_frozen_preimages_contract <- function() {
  utf8 <- enc2utf8('{"text":"é雪"}')
  latin <- iconv('{"text":"é"}', from = "UTF-8", to = "latin1")
  Encoding(latin) <- "latin1"
  tagged <- rawToChar(c(charToRaw('{"text":"'), as.raw(c(233L, 255L)), charToRaw('"}')))
  Encoding(tagged) <- "bytes"
  rows <- c("", "{}", '{"text":"quote\\\"\\n\\t\\u0000"}', utf8, latin, tagged,
    '{"value":-0}', '{"value":1.2345678901234567e-308}')
  initial <- strrep("c", 64L); expected <- character(); state <- initial
  for (text in rows) {
    row <- digest::digest(text, algo = "sha256", serialize = FALSE)
    preimage <- as.character(jsonlite::serializeJSON(list(previous = state,
      row_sha256 = row), digits = NA))
    expected <- c(expected, preimage)
    state <- digest::digest(preimage, algo = "sha256", serialize = FALSE)
  }
  actual_preimages <- character()
  original <- digest::digest
  restore <- .engine_row_hash_replace("digest", "digest", function(object, ...) {
    if (is.character(object) && length(object) == 1L && !is.na(object) &&
        grepl('"row_sha256"', object, fixed = TRUE))
      actual_preimages <<- c(actual_preimages, object)
    original(object, ...)
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  fold <- scworkbench:::.wb_prov_table_fold(initial)
  stopifnot(identical(fold(rows), state), identical(actual_preimages, expected))
  TRUE
}

test_engine_table_row_hash_eligibility_and_old_fallback_contract <- function() {
  eligible <- function(value) .Call(get("C_scwb_table_row_hash_eligible",
    asNamespace("scworkbench"), inherits = FALSE), value)
  stopifnot(isTRUE(eligible(c("{}", '{"x":1}'))),
    !eligible(character()), !eligible(c("{}", NA_character_)),
    !eligible(setNames("{}", "named")), !eligible(structure("{}", class = "json")),
    !eligible(list("{}")), !eligible(charToRaw("{}")),
    !eligible(rep("{}", 1001L)), !eligible(as.character(seq_len(100L))))
  original <- openssl::sha256; calls <- 0L
  restore <- .engine_row_hash_replace("openssl", "sha256", function(...) {
    calls <<- calls + 1L; original(...)
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  initial <- strrep("d", 64L)
  for (rows in list(c("{}", NA_character_, "NA"), setNames(c("{}", "[]"), c("a", "b")),
      structure(c("{}", "[]"), class = "json"), list("{}", "[]"),
      charToRaw("{}"), rep("{}", 1001L), as.character(seq_len(100L)))) {
    oracle <- .engine_row_fold_oracle(initial)
    fold <- scworkbench:::.wb_prov_table_fold(initial)
    stopifnot(identical(fold(rows), oracle(rows)))
  }
  stopifnot(calls == 0L)
  TRUE
}

test_engine_table_row_hash_partial_error_and_backend_failure_contract <- function() {
  initial <- strrep("e", 64L)
  for (rows in list(list("{}", 1L, "[]"), list("{}", new.env(parent = emptyenv())))) {
    fold <- scworkbench:::.wb_prov_table_fold(initial)
    oracle <- .engine_row_fold_oracle(initial)
    failure <- tryCatch(fold(rows), error = identity)
    expected <- tryCatch(oracle(rows), error = identity)
    stopifnot(inherits(failure, "error"), inherits(expected, "error"),
      identical(class(failure), class(expected)),
      identical(conditionMessage(failure), conditionMessage(expected)),
      identical(fold(character()), oracle(character())))
  }
  calls <- 0L
  restore <- .engine_row_hash_replace("openssl", "sha256", function(...) {
    calls <<- calls + 1L; stop("ROW_HASH_BACKEND_FAULT")
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  rows <- c('{"key":"first"}', '{"key":"last"}')
  fold <- scworkbench:::.wb_prov_table_fold(initial)
  oracle <- .engine_row_fold_oracle(initial)
  stopifnot(identical(fold(rows), oracle(rows)), calls == 1L)
  TRUE
}

test_engine_table_row_hash_partition_memory_and_rng_contract <- function() {
  initial <- strrep("f", 64L)
  rows <- paste0('{"row":', seq_len(2003L), '}')
  seed <- if (exists(".Random.seed", globalenv(), inherits = FALSE))
    get(".Random.seed", globalenv()) else NULL
  expected <- .engine_row_fold_oracle(initial)(rows)
  for (size in c(1L, 127L, 1000L, 1001L)) {
    fold <- scworkbench:::.wb_prov_table_fold(initial)
    for (start in seq.int(1L, length(rows), by = size))
      actual <- fold(rows[seq.int(start, min(length(rows), start + size - 1L))])
    stopifnot(identical(actual, expected))
  }
  calls <- 0L
  restore <- .engine_row_hash_replace("openssl", "sha256", function(...) {
    calls <<- calls + 1L; stop("MEMORY_FALLBACK_MUST_NOT_HASH_BATCH")
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  old <- options(scworkbench.max_dense_materialize_mb = .01)
  on.exit(options(old), add = TRUE)
  admitted_shape <- rows[seq_len(1000L)]
  stopifnot(identical(scworkbench:::.wb_prov_table_fold(initial)(admitted_shape),
    .engine_row_fold_oracle(initial)(admitted_shape)), calls == 0L)
  for (unsupported in list("not_numeric", NA_real_, structure(256, custom = TRUE))) {
    options(scworkbench.max_dense_materialize_mb = unsupported)
    withCallingHandlers(stopifnot(identical(scworkbench:::.wb_prov_table_fold(initial)(admitted_shape),
      .engine_row_fold_oracle(initial)(admitted_shape)), calls == 0L),
      warning = function(w) stop(conditionMessage(w)))
  }
  after <- if (exists(".Random.seed", globalenv(), inherits = FALSE))
    get(".Random.seed", globalenv()) else NULL
  stopifnot(identical(seed, after))
  TRUE
}

test_engine_table_row_hash_stored_primitive_identity_contract <- function() {
  root <- tempfile("row_hash_table_identity_"); b <- wb_init_bundle(root)
  on.exit(wb_close_bundle(b), add = TRUE)
  table <- data.frame(feature_id = c("f_2", "f_10", "f_1"),
    score = c(.2, .5, .8), label = c("é雪", "quote\"\\\n", ""))
  prim <- wb_prim_feature_table(table, table_type = "generic", meta = list(label = "nonempty"))
  # Explicit legacy primitive: preserve the frozen historical identity fixture.
  prim$table_storage <- NULL
  header <- list(identity_version = "scworkbench.payload.table.stream.v1",
    kind = "feature_table", table_type = "generic", entity_kind = NULL,
    meta = jsonlite::fromJSON(as.character(jsonlite::toJSON(prim$meta,
      auto_unbox = TRUE, null = "null")), simplifyVector = TRUE))
  initial <- digest::digest(jsonlite::serializeJSON(header, digits = NA),
    algo = "sha256", serialize = FALSE)
  rows <- vapply(seq_len(nrow(table)), function(i) as.character(jsonlite::toJSON(
    scworkbench:::.wb_json_sanitize(as.list(table[i, , drop = FALSE])),
    auto_unbox = TRUE, null = "null")), character(1))
  expected <- .engine_row_fold_oracle(initial)(rows)
  stopifnot(identical(scworkbench:::.wb_prov_table_content_sha256(prim), expected))
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim),
    notes = "Synthetic storage fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(identical(scworkbench:::.wb_prov_stored_table_content_sha256(b$con, id), expected),
    identical(wb_art_load(b, id)$table, table))
  TRUE
}
