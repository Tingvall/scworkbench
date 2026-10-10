test_graph_strict_json_unicode_contract <- function() {
  strict <- scworkbench:::.wb_operation_pack_v2_assert_strict_json
  positives <- c('{"東京":"é","escaped":"\\u00e9"}',
    '{"東京":"\\ud83d\\ude00","escape":"\\\\\\\""}')
  for (text in positives) stopifnot(strict(text))
  negatives <- c('{"東京":1,"東京":2}', '{"é":1,"\\u00e9":2}',
    '{"東京":"ok"} trailing', '{"東京":"\\x"}',
    '{"東京":"\\ud800"}', '{"東京":"\\udc00"}',
    '{"東京":"\\ud800\\u0041"}', '{"東京":"unterminated}',
    '{"東京":01}', '{"東京":true false}',
    rawToChar(as.raw(c(123,34,120,34,58,34,255,34,125))))
  for (text in negatives) stopifnot(inherits(tryCatch(strict(text), error = identity),
    "wb_operation_pack_v2_error"))
  TRUE
}
