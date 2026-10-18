# Frozen unmodified encoder from repaired core 8f53e950; name only changed.
.engine_canonical_repaired_oracle <- function(x) {
  fast_numeric <- exists("C_scwb_canonical_numeric", inherits = TRUE) &&
    identical(getOption("OutDec", "."), ".") &&
    identical(Sys.localeconv()[["decimal_point"]], ".")
  encode <- function(value) {
    if (is.null(value)) return("null")
    if (is.factor(value)) value <- as.character(value)
    if (is.data.frame(value)) {
      value <- lapply(seq_len(nrow(value)), function(i) as.list(value[i, , drop = FALSE]))
    }
    if (is.atomic(value) && length(value) != 1L) {
      return(paste0("[", paste(vapply(seq_along(value), function(i) encode(value[[i]]), character(1)), collapse = ","), "]"))
    }
    if (is.atomic(value) && length(value) == 1L && is.na(value)) return("null")
    if (is.list(value)) {
      nms <- names(value)
      if (is.null(nms)) return(paste0("[", paste(vapply(value, encode, character(1)), collapse = ","), "]"))
      .wb_operation_pack_assert(!anyNA(nms) && !anyDuplicated(nms),
        "OPERATION_PACK_CANONICAL_OBJECT_INVALID",
        "Canonical identity objects require unique UTF-8 keys.",
        class = "wb_operation_pack_identity_error")
      keys <- iconv(nms, from = "", to = "UTF-8", sub = NA_character_)
      .wb_operation_pack_assert(!anyNA(keys),
        "OPERATION_PACK_CANONICAL_STRING_INVALID",
        "Canonical identity object keys must be valid UTF-8.",
        class = "wb_operation_pack_identity_error")
      ord <- order(keys, method = "radix")
      fields <- vapply(ord, function(i) paste0(.wb_operation_pack_canonical_string(keys[[i]]), ":", encode(value[[i]])), character(1))
      return(paste0("{", paste(fields, collapse = ","), "}"))
    }
    if (is.logical(value)) {
      .wb_operation_pack_assert(length(value) == 1L && !is.na(value),
        "OPERATION_PACK_CANONICAL_VALUE_INVALID", "Canonical identity booleans must be scalar and non-missing.",
        class = "wb_operation_pack_identity_error")
      return(if (isTRUE(value)) "true" else "false")
    }
    if (is.integer(value) || is.numeric(value)) {
      if (fast_numeric && !is.object(value) &&
          is.null(attr(value, "operation_pack_json_number", exact = TRUE))) {
        encoded <- .Call(C_scwb_canonical_numeric, value)
        if (!is.null(encoded)) return(encoded)
      }
      return(.wb_operation_pack_canonical_number(.wb_operation_pack_number_token(value)))
    }
    if (is.character(value) && length(value) == 1L) return(.wb_operation_pack_canonical_string(value))
    .wb_operation_pack_abort("OPERATION_PACK_CANONICAL_VALUE_INVALID",
      paste0("Unsupported canonical identity value type: ", paste(class(value), collapse = "/"), "."),
      class = "wb_operation_pack_identity_error")
  }
  enc2utf8(encode(x))
}
