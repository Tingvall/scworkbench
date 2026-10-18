.engine_table_legacy_rows <- function(table) vapply(seq_len(nrow(table)),
  function(i) as.character(jsonlite::toJSON(
    scworkbench:::.wb_json_sanitize(as.list(table[i, , drop = FALSE])),
    auto_unbox = TRUE, null = "null")), character(1))

.engine_table_legacy_identity <- function(prim) {
  header <- list(identity_version = "scworkbench.payload.table.stream.v1",
    kind = as.character(prim$kind),
    table_type = as.character(prim$table_type %||% "generic")[1],
    entity_kind = if (identical(prim$kind, "obs_table"))
      as.character(prim$entity_kind %||% "generic")[1] else NULL,
    meta = jsonlite::fromJSON(as.character(jsonlite::toJSON(
      scworkbench:::.wb_json_sanitize(prim$meta %||% list()),
      auto_unbox = TRUE, null = "null")), simplifyVector = TRUE))
  state <- scworkbench:::.wb_prov_sha256_object(header)
  for (row in .engine_table_legacy_rows(prim$table))
    state <- scworkbench:::.wb_prov_sha256_object(list(previous = state,
      row_sha256 = digest::digest(row, algo = "sha256", serialize = FALSE)))
  state
}

test_engine_table_streaming_identity_contract <- function() {
  set.seed(37)
  table <- data.frame(feature_id = c("g_2", "g_10", "é", "雪", NA,
      "quote\"\\\n", ""), value = c(NA, NaN, Inf, -Inf, pi, 1e-10, -0),
    integer = c(NA_integer_, 1:6), logical = c(TRUE, FALSE, NA, TRUE, FALSE,
      TRUE, FALSE), stringsAsFactors = FALSE)
  special <- table
  special$factor <- factor(c("b", "a", NA, "b", "a", "a", "b"))
  special$date <- as.Date("2020-01-01") + seq_len(nrow(table))
  special$nested <- I(lapply(seq_len(nrow(table)), function(i)
    list(value = i, text = c("x", "é"))))
  cases <- list(table, table[0, ], table[7:1, ], special,
    table[rep(seq_len(nrow(table)), 300L), ])
  for (data in cases) {
    actual <- unlist(lapply(split(seq_len(nrow(data)),
        ceiling(seq_len(nrow(data)) / 127L)),
      function(rows) scworkbench:::.wb_prov_table_row_json(data, rows)),
      use.names = FALSE)
    if (!nrow(data)) actual <- character()
    stopifnot(identical(actual, .engine_table_legacy_rows(data)))
    for (kind in c("feature_table", "obs_table")) {
      prim <- structure(list(kind = kind, table = data, table_type = "test",
        entity_kind = "feature", meta = list(label = "nonempty é")),
        class = "wb_primitive")
      stopifnot(identical(scworkbench:::.wb_prov_table_content_sha256(prim),
        .engine_table_legacy_identity(prim)))
    }
  }
  state <- paste(rep("a", 64L), collapse = "")
  fold <- scworkbench:::.wb_prov_table_fold(state)
  for (row in .engine_table_legacy_rows(table)) {
    state <- scworkbench:::.wb_prov_sha256_object(list(previous = state,
      row_sha256 = digest::digest(row, algo = "sha256", serialize = FALSE)))
    stopifnot(identical(fold(row), state))
  }
  TRUE
}
