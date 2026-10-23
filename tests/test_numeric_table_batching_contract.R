# Literal typed-row emitter from commit 450213c: scientific byte oracle.
.numeric_table_450213c_emitter <- function(table, rows, storage) {
  block <- table[rows, , drop = FALSE]
  # Ordinary columns bypass the historical sanitizer, which turns numeric NA
  # into strings. Non-finite doubles retain the already supported value domain;
  # the declared double type makes their string encodings unambiguous.
  vapply(seq_len(nrow(block)), function(i) {
    row <- as.list(block[i, , drop = FALSE])
    if (!length(row)) return("{}")
    for (j in seq_along(row)) {
      value <- row[[j]]
      if (storage$types[[j]] == "legacy") {
        row[j] <- list(.wb_json_sanitize(value))
      } else if (is.double(value) && !is.na(value) && !is.finite(value)) {
        row[[j]] <- as.character(value)
      } else if (is.double(value) && is.nan(value)) row[[j]] <- "NaN"
    }
    as.character(jsonlite::toJSON(row, auto_unbox = TRUE,
      null = "null", na = "null", digits = 17))
  }, character(1))
}

environment(.numeric_table_450213c_emitter) <- asNamespace("scworkbench")

test_numeric_table_batched_bytes_and_identity_contract <- function() {
  values <- c(.0499545077, .05 - .Machine$double.eps/8, .05,
    .05 + .Machine$double.eps/8, pi, 1e-50, 1e-300, 5e-324,
    .Machine$double.xmax, .Machine$double.xmin, 0, -0, NA_real_, NaN, Inf, -Inf)
  table <- data.frame(feature_id = rep(c("é雪", "quote\"\\\n", NA, ""), 4),
    value = values, integer = rep(c(NA_integer_, 1L), 8),
    flag = rep(c(TRUE, FALSE, NA, TRUE), 4),
    character = rep(c("NA", "NaN", "Inf", NA), 4),
    missing_double = rep(NA_real_, 16), missing_integer = rep(NA_integer_, 16),
    missing_character = rep(NA_character_, 16), missing_logical = rep(NA, 16),
    integer_double = rep(1, 16), check.names = FALSE)
  names(table)[2] <- "quoted\" column"
  rownames(table) <- paste0("custom", seq_len(nrow(table)))
  special <- table
  special$factor <- factor(table$feature_id)
  special$date <- as.Date("2020-01-01") + seq_len(nrow(table))
  cases <- list(table, table[0, ], table[16:1, ], table[rep(1:16, 64), ], special,
    data.frame(value = c(NA_real_, -0, pi)), data.frame(row.names = 1:3))
  for (x in cases) {
    prim <- wb_prim_obs_table(x)
    storage <- scworkbench:::.wb_table_storage(prim)
    rows <- seq_len(nrow(x))
    expected <- .numeric_table_450213c_emitter(x, rows, storage)
    actual <- scworkbench:::.wb_table_typed_row_json(x, rows, storage)
    stopifnot(identical(actual, expected))
    # Independent frozen header and row-fold oracle, with no new serializer.
    header <- list(identity_version = "scworkbench.payload.table.stream.v2",
      kind = "obs_table", table_type = "generic", entity_kind = "generic", meta = list(),
      storage = storage)
    sha <- scworkbench:::.wb_prov_sha256_object(header)
    for (row in expected) sha <- scworkbench:::.wb_prov_sha256_object(list(
      previous = sha, row_sha256 = digest::digest(row, algo = "sha256", serialize = FALSE)))
    stopifnot(identical(scworkbench:::.wb_prov_table_content_sha256(prim), sha))
  }
  TRUE
}
