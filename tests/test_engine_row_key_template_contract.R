.engine_row_key_template_old <- function(keys) {
  if (!nrow(keys)) return(character())
  vapply(seq_len(nrow(keys)), function(i) {
    jsonlite::serializeJSON(as.list(keys[i, , drop = FALSE]), digits = NA)
  }, character(1))
}

.engine_row_key_template_observe <- function(helper, keys) {
  warnings <- character()
  value <- withCallingHandlers(tryCatch(helper(keys), error = function(e)
    list(class = class(e), message = conditionMessage(e))), warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
  list(value = value, warnings = warnings)
}

.engine_row_key_template_raw <- function(tokens) {
  # Independent complete byte framing, not a scientific identity replacement.
  lapply(tokens, charToRaw)
}

test_engine_row_key_template_complete_typed_bytes_and_positive_contract <- function() {
  fast <- scworkbench:::.wb_object_row_key_tokens_template
  actual <- scworkbench:::.wb_object_row_key_tokens
  eligible <- identical(as.character(getRversion()), "4.4.1") &&
    identical(as.character(getNamespaceVersion("jsonlite")), "1.8.8")
  for (n in c(0L, 1L, 2L, 1001L, 50000L)) {
    keys <- data.frame(key = rep(c("key_50", "key_01"), length.out = n),
      cell_id = if (n) paste0("cell_", seq_len(n)) else character(), stringsAsFactors = FALSE)
    if (n > 1L) rownames(keys) <- paste0("row_", rev(seq_len(n)))
    expected <- .engine_row_key_template_old(keys)
    observed <- actual(keys)
    stopifnot(identical(observed, expected, attrib.as.set = FALSE),
      identical(attributes(observed), attributes(expected)),
      identical(Encoding(observed), Encoding(expected)),
      identical(.engine_row_key_template_raw(observed), .engine_row_key_template_raw(expected)))
    if (eligible && n > 1L) {
      # The motivating50k case must actually enter the new route. Spy only
      # after the independent original oracle has finished, and restore exactly.
      ns <- asNamespace("jsonlite"); original <- get("serializeJSON", ns)
      calls <- 0L
      spy <- function(...) {calls <<- calls + 1L; original(...)}
      unlockBinding("serializeJSON", ns); assign("serializeJSON", spy, ns); lockBinding("serializeJSON", ns)
      result <- tryCatch(fast(keys), finally = {
        unlockBinding("serializeJSON", ns); assign("serializeJSON", original, ns); lockBinding("serializeJSON", ns)
      })
      stopifnot(!is.null(result), calls == 1L, identical(result, expected, attrib.as.set = FALSE))
    }
  }
  markers <- c("__scwb_row_key_template_1__", "__scwb_row_key_template_2__")
  values <- data.frame(key = c(markers[[2L]], markers[[1L]], ""),
    cell_id = c(paste0("x", markers[[1L]], markers[[2L]]), "a:b-c.d_3", ""))
  stopifnot(identical(actual(values), .engine_row_key_template_old(values), attrib.as.set = FALSE))
  if (eligible) stopifnot(!is.null(fast(values)))
  for (keys in list(values[, 2:1], values[c(3L, 1L, 2L), ]))
    stopifnot(identical(actual(keys), .engine_row_key_template_old(keys), attrib.as.set = FALSE))
  TRUE
}

test_engine_row_key_template_whole_fallback_and_errors_contract <- function() {
  fast <- scworkbench:::.wb_object_row_key_tokens_template
  actual <- scworkbench:::.wb_object_row_key_tokens
  base <- data.frame(key = rep("ordinary", 1001L), cell_id = paste0("cell_", seq_len(1001L)))
  variants <- list()
  for (bad in c(NA_character_, "雪", "quote\"", "slash/", "apostrophe'", "back\\slash", "new\nline",
      "cell_1\n", "cell_2\n", "cell_3\r\n", "</script>")) {
    x <- base; x$key[[1001L]] <- bad; variants[[length(variants) + 1L]] <- x
  }
  encoded <- c(enc2utf8("雪"), iconv("café", to = "latin1"), rawToChar(as.raw(255L)), rawToChar(as.raw(255L)))
  Encoding(encoded[[3L]]) <- "bytes"; Encoding(encoded[[4L]]) <- "UTF-8"
  for (bad in encoded) {
    x <- base; x$key[[1001L]] <- bad; variants[[length(variants) + 1L]] <- x
  }
  x <- base; x$key <- seq_len(nrow(x)); variants[[length(variants) + 1L]] <- x
  x <- base; x$key <- rep(c(-0, .25, NA_real_, NaN, Inf), length.out = nrow(x)); variants[[length(variants) + 1L]] <- x
  x <- base; x$key <- rep(c(TRUE, FALSE, NA), length.out = nrow(x)); variants[[length(variants) + 1L]] <- x
  x <- base; x$key <- factor(x$key); variants[[length(variants) + 1L]] <- x
  x <- base; x$key <- as.Date(seq_len(nrow(x)), origin = "1970-01-01"); variants[[length(variants) + 1L]] <- x
  x <- base; x$key <- as.list(x$key); variants[[length(variants) + 1L]] <- x
  x <- base; attr(x$key, "extra") <- "retained"; variants[[length(variants) + 1L]] <- x
  x <- base; attr(x, "extra") <- "retained"; variants[[length(variants) + 1L]] <- x
  x <- base; names(x) <- c("key", "key"); variants[[length(variants) + 1L]] <- x
  x <- base; names(x) <- c("key name", "cell_id"); variants[[length(variants) + 1L]] <- x
  x <- base; names(x) <- c("x__scwb_row_key_template_1__", "cell_id"); variants[[length(variants) + 1L]] <- x
  x <- base; class(x) <- c("custom_frame", "data.frame"); variants[[length(variants) + 1L]] <- x
  x <- base; names(x) <- c(NA_character_, "cell_id"); variants[[length(variants) + 1L]] <- x
  for (keys in variants) {
    expected <- .engine_row_key_template_observe(.engine_row_key_template_old, keys)
    observed <- .engine_row_key_template_observe(actual, keys)
    stopifnot(is.null(fast(keys)), identical(observed, expected))
    if (is.character(expected$value)) stopifnot(identical(
      .engine_row_key_template_raw(observed$value), .engine_row_key_template_raw(expected$value)))
  }
  # Exact typed JSON metadata/order rather than a toJSON-shaped token.
  tokens <- actual(base[1:2, ])
  parsed <- jsonlite::fromJSON(tokens[[1L]], simplifyVector = FALSE)
  stopifnot(identical(parsed$type, "list"), identical(parsed$attributes$names$type, "character"),
    identical(unlist(parsed$attributes$names$value, use.names = FALSE), names(base)),
    all(vapply(parsed$value, function(x) identical(x$type, "character"), logical(1))))
  TRUE
}

test_engine_row_key_template_resource_version_and_rng_contract <- function() {
  fast <- scworkbench:::.wb_object_row_key_tokens_template
  actual <- scworkbench:::.wb_object_row_key_tokens
  old <- options(scworkbench.max_dense_materialize_mb = 256)
  on.exit(options(old), add = TRUE)
  seed <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  keys <- data.frame(key = c("a", "b"), cell_id = c("cell_2", "cell_1"))
  expected <- .engine_row_key_template_old(keys)
  for (guard in list(.001, NA_real_, "unknown", structure(256, custom = TRUE))) {
    options(scworkbench.max_dense_materialize_mb = guard)
    stopifnot(is.null(fast(keys)), identical(actual(keys), expected, attrib.as.set = FALSE))
  }
  options(scworkbench.max_dense_materialize_mb = 256)
  # Unknown versions only in a private function copy, never installed namespaces.
  copy <- fast
  environment(copy) <- list2env(list(getNamespaceVersion = function(package) "0.0.0"), parent = environment(fast))
  stopifnot(is.null(copy(keys)))
  copy <- fast
  environment(copy) <- list2env(list(getRversion = function() "0.0.0"), parent = environment(fast))
  stopifnot(is.null(copy(keys)))
  long <- data.frame(key = rep(strrep("a", 100000L), 2L), cell_id = c("c2", "c1"))
  options(scworkbench.max_dense_materialize_mb = 1)
  stopifnot(is.null(fast(long)), identical(actual(long), .engine_row_key_template_old(long)))
  after <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  stopifnot(identical(seed, after))
  TRUE
}

test_engine_row_key_template_promoted_family_legacy_inspection_contract <- function() {
  root <- tempfile("row_key_template_family_"); b <- wb_init_bundle(root)
  on.exit(wb_close_bundle(b), add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1"); wb_define_cells(b, cells)
  prim <- wb_prim_cell_vector_family(rep(c("key_2", "key_1"), each = 3L), rep(cells, 2L),
    c(0, .25, NA_real_, -1, 2, 3), value_type = "continuous",
    meta = list(label = "ordered metadata", semantics = list("first", "second")))
  expected_identity <- scworkbench:::.wb_prov_payload_identity(b, prim)
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim),
    notes = "Synthetic family storage/inspection fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id), head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- wb_open_bundle(root, read_only = TRUE, validate = FALSE)
  inventory <- function() {
    files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
    files <- files[!file.info(files)$isdir]
    setNames(vapply(files, function(path) digest::digest(file = path, algo = "sha256"), ""),
      substring(files, nchar(root) + 2L))
  }
  before <- inventory(); actual <- wb_art_load(b, id)
  ns <- asNamespace("scworkbench"); original <- get(".wb_object_row_key_tokens", ns)
  unlockBinding(".wb_object_row_key_tokens", ns)
  assign(".wb_object_row_key_tokens", .engine_row_key_template_old, ns); lockBinding(".wb_object_row_key_tokens", ns)
  expected <- tryCatch(wb_art_load(b, id), finally = {
    unlockBinding(".wb_object_row_key_tokens", ns); assign(".wb_object_row_key_tokens", original, ns)
    lockBinding(".wb_object_row_key_tokens", ns)
  })
  stopifnot(identical(actual, expected, attrib.as.set = FALSE), identical(actual, prim, attrib.as.set = FALSE),
    identical(scworkbench:::.wb_prov_payload_identity(b, actual), expected_identity),
    identical(inventory(), before))
  TRUE
}
