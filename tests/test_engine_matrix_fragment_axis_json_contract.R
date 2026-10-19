# Literal pre-candidate expression; do not derive the oracle from the helper.
.engine_fragment_axis_json_old <- function(ids) {
  as.character(jsonlite::toJSON(as.list(ids), auto_unbox = TRUE))
}

.engine_fragment_axis_outcome <- function(fun, ids) {
  warnings <- character()
  result <- tryCatch(withCallingHandlers(fun(ids), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  }), error = function(e) list(error_class = class(e), error = conditionMessage(e)))
  list(result = result, warnings = warnings)
}

.engine_fragment_axis_fixture <- function() {
  root <- tempfile("fragment_axis_json_")
  b <- wb_init_bundle(root)
  ok <- FALSE
  on.exit(if (!ok) {
    if (DBI::dbIsValid(b$con)) try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE)
  }, add = TRUE)
  features <- c("g2", "quote\"", "slash/", "back\\slash")
  cells <- c("c2", "c1", "zero", "c3")
  value <- matrix(as.double(seq_len(16)), 4L, dimnames = list(features, cells))
  value[, "zero"] <- 0
  wb_define_cells(b, cells)
  wb_attach_matrix(b, "m", Matrix::Matrix(value, sparse = TRUE))
  ok <- TRUE
  list(root = root, b = b, features = features, cells = cells, value = value)
}

.engine_fragment_axis_cleanup <- function(f) {
  if (DBI::dbIsValid(f$b$con)) try(wb_close_bundle(f$b), silent = TRUE)
  unlink(f$root, recursive = TRUE)
}

test_engine_matrix_fragment_axis_json_literal_bytes_contract <- function() {
  encode <- scworkbench:::.wb_matrix_fragment_axis_json
  eligible <- scworkbench:::.wb_matrix_fragment_axis_json_vector_eligible
  examples <- list(character(), "one", c("one", "two"),
    c("quote\"", "back\\slash", "/", "[brackets]", " spaced ", ""),
    paste0("feature_", seq_len(31535L)))
  for (ids in examples) stopifnot(identical(
    .engine_fragment_axis_outcome(encode, ids),
    .engine_fragment_axis_outcome(.engine_fragment_axis_json_old, ids)))
  old <- options(scworkbench.max_dense_materialize_mb = 256)
  on.exit(options(old), add = TRUE)
  supported <- identical(as.character(utils::packageVersion("jsonlite")), "1.8.8")
  stopifnot(identical(eligible(c("a", "quote\"", "back\\slash")), supported),
    !eligible(character()))
  # Locale is not changed by production. Exercise any installed alternates and
  # restore the original even after failure; absence is not a claimed coverage.
  original_locale <- Sys.getlocale("LC_CTYPE")
  on.exit(Sys.setlocale("LC_CTYPE", original_locale), add = TRUE)
  for (locale in unique(c(original_locale, "C", "C.UTF-8"))) {
    changed <- suppressWarnings(Sys.setlocale("LC_CTYPE", locale))
    if (nzchar(changed)) stopifnot(identical(encode(examples[[4L]]),
      .engine_fragment_axis_json_old(examples[[4L]])))
  }
  TRUE
}

test_engine_matrix_fragment_axis_json_fallback_encoding_contract <- function() {
  encode <- scworkbench:::.wb_matrix_fragment_axis_json
  eligible <- scworkbench:::.wb_matrix_fragment_axis_json_vector_eligible
  latin <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9))); Encoding(latin) <- "latin1"
  invalid <- rawToChar(as.raw(c(0x61, 0xff))); Encoding(invalid) <- "UTF-8"
  bytes <- invalid; Encoding(bytes) <- "bytes"
  examples <- list(c("\u03b1", "\u96ea"), c("a\nb", "a\rb", "a\tb", "\001"),
    latin, invalid, bytes, NA_character_, setNames(c("a", "b"), c("x", "y")),
    structure("a", unrelated = TRUE), structure("a", class = "engine_axis_unfamiliar"))
  for (ids in examples) {
    stopifnot(!eligible(ids), identical(.engine_fragment_axis_outcome(encode, ids),
      .engine_fragment_axis_outcome(.engine_fragment_axis_json_old, ids)))
  }
  for (limit in list(0, -1, Inf, NA_real_, "256", c(1, 2), structure(256, note = TRUE), 1e-9)) {
    old <- options(scworkbench.max_dense_materialize_mb = limit)
    tryCatch(stopifnot(!eligible(c("a", "b")),
      identical(encode(c("a", "b")), .engine_fragment_axis_json_old(c("a", "b")))),
      finally = options(old))
  }
  TRUE
}

test_engine_matrix_fragment_axis_json_single_coercion_contract <- function() {
  # Model the writer's unchanged normalization exactly, including a method that
  # returns names/attributes. Neither new helper nor fallback normalizes again.
  method_name <- "as.character.engine_axis_once"
  prior <- if (exists(method_name, .GlobalEnv, inherits = FALSE)) get(method_name, .GlobalEnv) else NULL
  calls <- 0L
  assign(method_name, function(x, ...) {
    calls <<- calls + 1L
    warning("axis normalization sentinel")
    structure(c("first", "second"), names = c("n1", "n2"), extra = "preserved")
  }, .GlobalEnv)
  on.exit(if (is.null(prior)) rm(list = method_name, envir = .GlobalEnv) else
    assign(method_name, prior, .GlobalEnv), add = TRUE)
  x <- structure(c("a", "b"), class = "engine_axis_once")
  old <- .engine_fragment_axis_outcome(function(ids) .engine_fragment_axis_json_old(as.character(ids)), x)
  stopifnot(calls == 1L)
  calls <- 0L
  new <- .engine_fragment_axis_outcome(function(ids) scworkbench:::.wb_matrix_fragment_axis_json(as.character(ids)), x)
  stopifnot(calls == 1L, identical(old, new),
    identical(new$warnings, "axis normalization sentinel"))
  fallback_name <- "as.list.engine_axis_fallback"
  prior_fallback <- if (exists(fallback_name, .GlobalEnv, inherits = FALSE)) get(fallback_name, .GlobalEnv) else NULL
  fallback_calls <- 0L
  assign(fallback_name, function(x, ...) {
    fallback_calls <<- fallback_calls + 1L
    warning("axis fallback warning sentinel")
    stop("axis fallback first error sentinel")
  }, .GlobalEnv)
  on.exit(if (is.null(prior_fallback)) rm(list = fallback_name, envir = .GlobalEnv) else
    assign(fallback_name, prior_fallback, .GlobalEnv), add = TRUE)
  opaque <- structure("x", class = "engine_axis_fallback")
  old_fallback <- .engine_fragment_axis_outcome(.engine_fragment_axis_json_old, opaque)
  stopifnot(fallback_calls == 1L)
  fallback_calls <- 0L
  new_fallback <- .engine_fragment_axis_outcome(scworkbench:::.wb_matrix_fragment_axis_json, opaque)
  stopifnot(fallback_calls == 1L, identical(old_fallback, new_fallback),
    identical(new_fallback$warnings, "axis fallback warning sentinel"),
    identical(new_fallback$result$error, "axis fallback first error sentinel"))
  TRUE
}

test_engine_matrix_fragment_axis_json_stored_membership_contract <- function() {
  f <- .engine_fragment_axis_fixture()
  on.exit(.engine_fragment_axis_cleanup(f), add = TRUE)
  row <- wb_matrix_fragments(f$b, "m")
  stopifnot(nrow(row) == 1L,
    identical(row$feature_ids_json[[1L]], .engine_fragment_axis_json_old(f$features)),
    identical(row$cell_ids_json[[1L]], .engine_fragment_axis_json_old(f$cells)))
  for (axis in c("features", "cells")) {
    id <- if (axis == "features") "feature_id" else "cell_id"
    actual <- DBI::dbGetQuery(f$b$con, paste0("SELECT ", id,
      " FROM matrix_fragment_", axis, " WHERE fragment_id=? ORDER BY rowid;"),
      params = list(row$fragment_id[[1L]]))[[id]]
    stopifnot(identical(actual, f[[axis]]))
  }
  stopifnot(identical(as.matrix(wb_slice(f$b, "m", features = f$features,
    cells = f$cells)), f$value), isTRUE(wb_finalize_recipient_bundle(f$b)$ready))
  wb_close_bundle(f$b)
  f$b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  before <- scworkbench:::.wb_prov_file_tree_sha256(f$root)
  stopifnot(identical(as.matrix(wb_slice(f$b, "m", features = f$features,
    cells = f$cells)), f$value),
    identical(before, scworkbench:::.wb_prov_file_tree_sha256(f$root)))
  TRUE
}

test_engine_matrix_fragment_axis_json_registry_rollback_contract <- function() {
  f <- .engine_fragment_axis_fixture()
  on.exit(.engine_fragment_axis_cleanup(f), add = TRUE)
  row <- wb_matrix_fragments(f$b, "m")
  register <- function() wb_register_matrix_fragment(f$b$con, "m", row$path[[1L]],
    f$features, f$cells, created_at = row$created_at[[1L]])
  # Current registration must still reject overlaps before publication. It does
  # not offer overwrite; legacy getter overwrite tests remain separate.
  overlap <- tryCatch(register(), error = identity)
  stopifnot(inherits(overlap, "error"), grepl("disjoint cell identities", conditionMessage(overlap), fixed = TRUE))
  for (table in c("matrix_fragment_cells", "matrix_fragment_features"))
    DBI::dbExecute(f$b$con, paste0("DELETE FROM ", table, " WHERE fragment_id=?;"),
      params = list(row$fragment_id[[1L]]))
  DBI::dbExecute(f$b$con, "DELETE FROM matrix_fragments WHERE fragment_id=?;",
    params = list(row$fragment_id[[1L]]))
  DBI::dbExecute(f$b$con, paste0("CREATE TEMP TRIGGER engine_axis_fail BEFORE INSERT ON main.matrix_fragment_cells ",
    "BEGIN SELECT RAISE(ABORT, 'axis membership fault sentinel'); END;"))
  fault <- tryCatch(register(), error = identity)
  stopifnot(inherits(fault, "error"), grepl("axis membership fault sentinel", conditionMessage(fault), fixed = TRUE))
  for (table in c("matrix_fragments", "matrix_fragment_features", "matrix_fragment_cells"))
    stopifnot(DBI::dbGetQuery(f$b$con, paste0("SELECT COUNT(*) AS n FROM ", table))$n[[1L]] == 0)
  DBI::dbExecute(f$b$con, "DROP TRIGGER engine_axis_fail;")
  register()
  stopifnot(identical(as.matrix(wb_slice(f$b, "m", features = f$features,
    cells = f$cells)), f$value))
  TRUE
}
