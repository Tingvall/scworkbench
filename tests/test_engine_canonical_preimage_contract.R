.engine_canonical_oracle <- function() {
  env <- new.env(parent = asNamespace("scworkbench"))
  sys.source(file.path("tests", "fixtures", "engine_canonical_repaired_oracle.R"), env)
  env$.engine_canonical_repaired_oracle
}

test_engine_canonical_array_and_key_plan_contract <- function() {
  old <- .engine_canonical_oracle()
  new <- scworkbench:::.wb_operation_pack_canonical_json
  latin <- iconv("é", from = "UTF-8", to = "latin1"); Encoding(latin) <- "latin1"
  controls <- intToUtf8(1:31)
  cases <- list(character(), "x", NA_character_, list(),
    structure(list(), names = character()), list("x"), list(NA_character_),
    c("é", "雪", "quoted\"\\", controls, NA_character_),
    list("é", "雪", "quoted\"\\", controls, NA_character_),
    c(latin, "é"), list(latin, "é"), factor(c("b", "a", NA)),
    structure(c("x", "y"), label = "fallback"),
    list(I("x"), "y"), list("x", 1, NULL), list(list("x"), list("y")),
    list(list(z = 1, a = "b"), list(z = 2, a = "c")),
    list(list(z = list(inner = "b"), a = "one"),
      list(z = list(other = "c"), a = "two")),
    list(setNames(list("x"), "é"), setNames(list("y"), latin)),
    list(list("a\"" = "x", "b\\" = 1), list("a\"" = "y", "b\\" = 2)),
    data.frame(feature_id = c("g_2", "g_10", "g_1"),
      loading = c(-0, pi, 1e-10), component = c(2L, 1L, 3L)))
  for (value in cases) {
    expected <- old(value); actual <- new(value)
    stopifnot(identical(charToRaw(actual), charToRaw(expected)),
      identical(digest::digest(actual, algo = "sha256", serialize = FALSE),
        digest::digest(expected, algo = "sha256", serialize = FALSE)))
  }
  # Shape and object-key uniqueness are not inferred from element count.
  stopifnot(new("x") == '"x"', new(list("x")) == '["x"]',
    new(character()) == "[]", new(structure(list(), names = character())) == "{}")
  TRUE
}

test_engine_canonical_table_batches_contract <- function() {
  old <- .engine_canonical_oracle()
  new <- scworkbench:::.wb_operation_pack_canonical_json
  values <- data.frame("雪" = c(NA_real_, NaN, -0, pi, 1e-307),
    "é" = c("é", NA, "quote\"\\\n", "", "雪"),
    flag = c(TRUE, FALSE, NA, FALSE, TRUE), n = c(NA_integer_, 1:4),
    check.names = FALSE, stringsAsFactors = FALSE)
  special <- values; special$factor <- factor(c("b", "a", NA, "b", "a"))
  special$date <- as.Date("2020-01-01") + 1:5
  special$nested <- I(rep(list(list(value = c("x", "y"))), 5L))
  attributed <- values; attr(attributed$n, "label") <- "conservative fallback"
  cases <- list(values, values[0, ], values[1, , drop = FALSE], special,
    attributed, data.frame(row.names = 1:2), values[, "雪", drop = FALSE])
  for (n in c(999L, 1000L, 1001L, 2100L)) {
    case <- values[rep(seq_len(nrow(values)), length.out = n), ]
    rownames(case) <- paste0("noncanonical_", rev(seq_len(n)))
    cases[[length(cases) + 1L]] <- case
  }
  for (value in cases) {
    a <- tryCatch(old(value), error = identity)
    b <- tryCatch(new(value), error = identity)
    if (inherits(a, "error")) stopifnot(inherits(b, "error"),
      identical(class(a), class(b)), identical(conditionMessage(a), conditionMessage(b)))
    else stopifnot(identical(charToRaw(a), charToRaw(b)))
  }
  invalid <- rawToChar(as.raw(255)); Encoding(invalid) <- "UTF-8"
  # Column-major speculative conversion must not change the first row-major
  # error: every questionable frame falls back before scalar emission.
  bad <- list(data.frame(a = c(0, Inf), b = c(Inf, 0)),
    data.frame(a = c(0, 1e-310), b = c(1e-309, 0)),
    data.frame(a = c("good", invalid), b = c(invalid, "good")),
    data.frame(a = 1, b = 2))
  names(bad[[4L]]) <- c("same", "same")
  for (value in bad) {
    a <- tryCatch(old(value), error = identity)
    b <- tryCatch(new(value), error = identity)
    if (inherits(a, "error")) stopifnot(inherits(b, "error"),
      identical(class(a), class(b)), identical(conditionMessage(a), conditionMessage(b)))
    else stopifnot(identical(a, b))
  }
  TRUE
}

test_engine_canonical_preimage_rejection_contract <- function() {
  old <- .engine_canonical_oracle()
  new <- scworkbench:::.wb_operation_pack_canonical_json
  invalid <- rawToChar(as.raw(255)); Encoding(invalid) <- "UTF-8"
  cases <- list(c("good", invalid), list("good", invalid),
    structure(list(1, 2), names = c("same", "same")),
    list(list(valid = 1), structure(list(2, 3), names = c("x", "x"))),
    setNames(list(1), NA_character_), setNames(list(1), invalid))
  for (value in cases) {
    a <- tryCatch(old(value), error = identity)
    b <- tryCatch(new(value), error = identity)
    stopifnot(inherits(a, "error"), inherits(b, "error"),
      identical(class(a), class(b)), identical(conditionMessage(a), conditionMessage(b)))
  }
  TRUE
}
