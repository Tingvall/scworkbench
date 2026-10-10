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

test_graph_large_string_numeric_lexeme_contract <- function() {
  strict <- scworkbench:::.wb_operation_pack_v2_assert_strict_json
  tokens <- scworkbench:::.wb_operation_pack_json_number_tokens
  # Independent former byte-mask projection proves token parity; do not use
  # parsed/reserialized numeric values as the expected identity preimage.
  reference <- function(text) {
    bytes <- masked <- charToRaw(enc2utf8(text)); inside <- escaped <- FALSE
    for (i in seq_along(bytes)) {
      byte <- as.integer(bytes[[i]])
      if (inside) {
        masked[[i]] <- as.raw(32L)
        if (escaped) escaped <- FALSE else if (byte == 92L) escaped <- TRUE else
          if (byte == 34L) inside <- FALSE
      } else if (byte == 34L) {inside <- TRUE; masked[[i]] <- as.raw(32L)}
    }
    x <- rawToChar(masked)
    unname(regmatches(x, gregexpr("-?(?:0|[1-9][0-9]*)(?:[.][0-9]+)?(?:[eE][+-]?[0-9]+)?", x,
      perl = TRUE))[[1L]])
  }
  text <- c('{"東京":"1.0", "x":1.00e-2,"y":[-0,2]}',
    '{"\\u0031":"\\\\1\\\"2", "n":-1.20E+03}',
    paste0('{"large":"', paste(rep("a", 65536L), collapse = ""), '123","n":1.000}'),
    paste0('{"escape":"', paste(rep("\\\\", 32768L), collapse = ""), '","n":2e-3}'))
  for (value in text) stopifnot(strict(value), identical(tokens(value), reference(value)))
  plain <- paste0(paste(rep("a", 65536L), collapse = ""), "東京é😀/")
  stopifnot(identical(scworkbench:::.wb_operation_pack_canonical_string(plain), paste0('"', plain, '"')),
    identical(scworkbench:::.wb_operation_pack_canonical_string("東京\n\\\""), '"東京\\n\\\\\\\""'))
  stopifnot(identical(tokens('{"n":[] ,"text":"123"}'), character()))
  # Keys still compare after decoding and malformed escapes/control bytes reject,
  # even following a maximum-size ordinary string run.
  prefix <- paste0('{"large":"', paste(rep("a", 65536L), collapse = ""), '",')
  for (suffix in c('"é":1,"\\u00e9":2}', '"x":"bad\\x"}',
      paste0('"x":"bad', intToUtf8(1L), '"}'), '"x":"\\ud800"}'))
    stopifnot(inherits(tryCatch(strict(paste0(prefix, suffix)), error = identity), "wb_operation_pack_v2_error"))
  TRUE
}
