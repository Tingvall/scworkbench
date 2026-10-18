args <- commandArgs(TRUE)
.libPaths(c(args[1L], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
new <- new.env(parent = asNamespace("scworkbench"))
sys.source("R/operation_packs_v2.R", new)
legacy <- readRDS("/tmp/scwb-matrix-streaming-forge-20261018/legacy_strict_validator.rds")
test <- new.env(parent = asNamespace("scworkbench"))
sys.source("tests/test_operation_pack_matrix_streaming_contract.R", test)
body(test$test_operation_pack_matrix_streaming_strict_json_contract)[[2L]] <-
  quote(validate <- new$.wb_operation_pack_v2_assert_strict_json)
environment(test$test_operation_pack_matrix_streaming_strict_json_contract) <- environment()
stopifnot(test$test_operation_pack_matrix_streaming_strict_json_contract())
set.seed(49)
texts <- c('null', '{}', '[]', '{"é":"雪","emoji":"\\ud83d\\ude00"}',
  '{"é":1,"\\u00e9":2}', '"\\ud800"', '"\\udc00"', '"\\q"', '01', 'truefalse')
for (i in seq_len(150L)) texts <- c(texts, as.character(jsonlite::toJSON(list(
  names = as.list(sample(c("g1", "é", "雪", "false", "\\\"", "1e10"), 5L, TRUE)),
  values = as.list(sample(c(-1, 0, 1, 3.1415), 5L, TRUE)),
  flags = list(TRUE, FALSE, NULL)), auto_unbox = TRUE, null = "null", pretty = i %% 2 == 0)))
accept <- function(fn, text) isTRUE(tryCatch(fn(text), error = function(e) FALSE))
before <- vapply(texts, function(text) accept(legacy, text), logical(1))
after <- vapply(texts, function(text) accept(new$.wb_operation_pack_v2_assert_strict_json, text), logical(1))
stopifnot(identical(before, after))
cat("STRICT_JSON_DIFFERENTIAL cases=", length(texts), " outcomes_identical=TRUE\n", sep = "")
for (size in c(100L, 500L)) {
  text <- as.character(jsonlite::toJSON(list(rows = lapply(seq_len(size),
    function(i) list(feature_id = paste0("Xelaev", i, "_雪"), type = "gene",
      missing = NULL))), auto_unbox = TRUE, null = "null", pretty = TRUE))
  cat("ROWS", size, "BYTES", nchar(text, type = "bytes"), "\n")
  cat("legacy\n"); print(system.time(legacy(text)))
  cat("indexed\n"); print(system.time(new$.wb_operation_pack_v2_assert_strict_json(text)))
}
