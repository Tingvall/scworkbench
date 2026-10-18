# Operation-pack v1 process-local registry and public R author boundary.

.wb_operation_pack_protocol_version <- function() "1"

.wb_operation_pack_supported_backends <- function() c("R", "Python")

.wb_operation_pack_python_entry_point_group <- function() {
  "scworkbench.operation_packs.v1"
}

.wb_operation_pack_python_normalize_name <- function(name) {
  name <- .wb_operation_pack_scalar(name, "Python distribution name")
  tolower(gsub("[-_.]+", "-", name, perl = TRUE))
}

.wb_operation_pack_python_version_pattern <- function() {
  paste0(
    "^[vV]?(?:[0-9]+!)?[0-9]+(?:[.][0-9]+)*",
    "(?:[-_.]?(?:alpha|a|beta|b|preview|pre|c|rc)[-_.]?[0-9]*)?",
    "(?:(?:-[0-9]+)|(?:[-_.]?(?:post|rev|r)[-_.]?[0-9]*))?",
    "(?:[-_.]?dev[-_.]?[0-9]*)?",
    "(?:[+][A-Za-z0-9]+(?:[-_.][A-Za-z0-9]+)*)?\\z"
  )
}

.wb_operation_pack_integer_token <- function(x) {
  out <- sub("^0+", "", as.character(x), perl = TRUE)
  if (nzchar(out)) out else "0"
}

.wb_operation_pack_python_version_key <- function(version) {
  version <- .wb_operation_pack_scalar(version, "Python distribution version")
  .wb_operation_pack_assert(
    grepl(.wb_operation_pack_python_version_pattern(), version, perl = TRUE, ignore.case = TRUE),
    "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Python distribution version is not valid PEP 440 syntax: ", version, "."),
    version = version
  )
  value <- tolower(sub("^[vV]", "", version, perl = TRUE))
  local <- ""
  if (grepl("[+]", value, perl = TRUE)) {
    parts <- strsplit(value, "+", fixed = TRUE)[[1]]
    value <- parts[[1]]
    local_parts <- strsplit(gsub("[-_]", ".", parts[[2]], perl = TRUE), ".", fixed = TRUE)[[1]]
    local <- paste(vapply(local_parts, function(x) {
      if (grepl("^[0-9]+$", x, perl = TRUE)) .wb_operation_pack_integer_token(x) else x
    }, character(1)), collapse = ".")
  }
  epoch <- "0"
  if (grepl("!", value, fixed = TRUE)) {
    parts <- strsplit(value, "!", fixed = TRUE)[[1]]
    epoch <- .wb_operation_pack_integer_token(parts[[1]])
    value <- parts[[2]]
  }
  dev <- ""
  dev_hit <- regexec("[-_.]?dev[-_.]?([0-9]*)$", value, perl = TRUE)
  dev_match <- regmatches(value, dev_hit)[[1]]
  if (length(dev_match)) {
    dev <- if (nzchar(dev_match[[2]])) .wb_operation_pack_integer_token(dev_match[[2]]) else "0"
    value <- substr(value, 1L, nchar(value) - nchar(dev_match[[1]]))
  }
  post <- ""
  post_hit <- regexec("(?:-([0-9]+)|[-_.]?(?:post|rev|r)[-_.]?([0-9]*))$", value, perl = TRUE)
  post_match <- regmatches(value, post_hit)[[1]]
  if (length(post_match)) {
    number <- post_match[[2]]
    if (!nzchar(number) && length(post_match) >= 3L) number <- post_match[[3]]
    post <- if (nzchar(number)) .wb_operation_pack_integer_token(number) else "0"
    value <- substr(value, 1L, nchar(value) - nchar(post_match[[1]]))
  }
  pre <- ""
  pre_hit <- regexec("[-_.]?(alpha|a|beta|b|preview|pre|c|rc)[-_.]?([0-9]*)$", value, perl = TRUE)
  pre_match <- regmatches(value, pre_hit)[[1]]
  if (length(pre_match)) {
    label <- switch(pre_match[[2]], alpha = "a", a = "a", beta = "b", b = "b",
                    preview = "rc", pre = "rc", c = "rc", rc = "rc")
    number <- if (nzchar(pre_match[[3]])) .wb_operation_pack_integer_token(pre_match[[3]]) else "0"
    pre <- paste0(label, number)
    value <- substr(value, 1L, nchar(value) - nchar(pre_match[[1]]))
  }
  release <- strsplit(value, ".", fixed = TRUE)[[1]]
  release <- vapply(release, .wb_operation_pack_integer_token, character(1))
  while (length(release) > 1L && identical(unname(release[[length(release)]]), "0")) {
    release <- release[-length(release)]
  }
  paste(epoch, paste(release, collapse = "."), pre, post, dev, local, sep = "|")
}

.wb_operation_pack_registry <- local({
  e <- new.env(parent = emptyenv())
  e$packs <- list()
  e$operations <- list()
  e$registration_context <- NULL
  e
})

.wb_operation_pack_abort <- function(code, message, ..., class = "wb_operation_pack_error") {
  fields <- list(...)
  condition <- structure(
    c(list(message = as.character(message)[1], call = NULL, code = as.character(code)[1]), fields),
    class = c(class, "wb_operation_pack_error", "error", "condition")
  )
  stop(condition)
}

.wb_operation_pack_assert <- function(ok, code, message, ..., class = "wb_operation_pack_validation_error") {
  if (!isTRUE(ok)) .wb_operation_pack_abort(code, message, ..., class = class)
  invisible(TRUE)
}

.wb_operation_pack_scalar <- function(x, label, pattern = NULL) {
  .wb_operation_pack_assert(
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x),
    "OPERATION_PACK_MANIFEST_INVALID", paste0(label, " must be one non-empty string."), field = label
  )
  if (!is.null(pattern)) {
    .wb_operation_pack_assert(
      grepl(pattern, x, perl = TRUE), "OPERATION_PACK_MANIFEST_INVALID",
      paste0(label, " has an invalid value: ", x, "."), field = label
    )
  }
  as.character(x)[1]
}

.wb_operation_pack_named_object <- function(x, label, allow_empty = TRUE) {
  .wb_operation_pack_assert(is.list(x), "OPERATION_PACK_MANIFEST_INVALID",
                            paste0(label, " must be a JSON object."), field = label)
  if (length(x)) {
    .wb_operation_pack_assert(!is.null(names(x)) && !anyNA(names(x)) &&
      all(nzchar(names(x))) && !anyDuplicated(names(x)),
      "OPERATION_PACK_MANIFEST_INVALID", paste0(label, " must have unique non-empty keys."), field = label)
  } else if (!isTRUE(allow_empty)) {
    .wb_operation_pack_abort("OPERATION_PACK_MANIFEST_INVALID",
      paste0(label, " must not be empty."), field = label,
      class = "wb_operation_pack_validation_error")
  }
  x
}

.wb_operation_pack_identity_scheme <- function() {
  "scworkbench.operation_pack.canonical_json.v1"
}

.wb_operation_pack_canonical_number <- function(token) {
  token <- as.character(token)[1]
  match <- regexec(
    "^(-)?(0|[1-9][0-9]*)(?:[.]([0-9]+))?(?:[eE]([+-]?[0-9]+))?$",
    token, perl = TRUE
  )
  parts <- regmatches(token, match)[[1]]
  .wb_operation_pack_assert(length(parts) == 5L,
    "OPERATION_PACK_CANONICAL_NUMBER_INVALID",
    paste0("Canonical identity received a malformed JSON number: ", token, "."),
    number = token, class = "wb_operation_pack_identity_error")
  negative <- identical(parts[[2]], "-")
  integer <- parts[[3]]
  fraction <- parts[[4]]
  exponent_text <- parts[[5]]
  exponent <- if (nzchar(exponent_text)) suppressWarnings(as.numeric(exponent_text)) else 0
  .wb_operation_pack_assert(is.finite(exponent) && abs(exponent) <= 10000,
    "OPERATION_PACK_CANONICAL_NUMBER_RANGE",
    paste0("Canonical identity number exponent is outside the parsing boundary: ", token, "."),
    number = token, class = "wb_operation_pack_identity_error")

  digits <- paste0(integer, fraction)
  first <- regexpr("[1-9]", digits, perl = TRUE)[1]
  if (identical(first, -1L)) return("0")
  last <- max(gregexpr("[1-9]", digits, perl = TRUE)[[1]])
  significant <- substr(digits, first, last)
  .wb_operation_pack_assert(nchar(significant, type = "bytes") <= 15L,
    "OPERATION_PACK_CANONICAL_NUMBER_PRECISION",
    paste0("Canonical identity numbers may contain at most 15 significant decimal digits: ", token, "."),
    number = token, class = "wb_operation_pack_identity_error")
  adjusted <- exponent + nchar(integer, type = "bytes") - first
  .wb_operation_pack_assert(adjusted >= -307 && adjusted <= 308,
    "OPERATION_PACK_CANONICAL_NUMBER_RANGE",
    paste0("Canonical identity number is outside the adjusted exponent range [-307, 308]: ", token, "."),
    number = token, class = "wb_operation_pack_identity_error")
  coefficient <- if (nchar(significant, type = "bytes") == 1L) significant else {
    paste0(substr(significant, 1L, 1L), ".", substr(significant, 2L, nchar(significant)))
  }
  paste0(if (negative) "-" else "", coefficient, "e", format(adjusted, scientific = FALSE, trim = TRUE))
}

.wb_operation_pack_number_token <- function(x) {
  token <- attr(x, "operation_pack_json_number", exact = TRUE)
  if (!is.null(token)) return(as.character(token)[1])
  .wb_operation_pack_assert(length(x) == 1L && !is.na(x) && is.finite(x),
    "OPERATION_PACK_CANONICAL_NUMBER_INVALID",
    "Canonical identity numbers must be finite scalar values.",
    class = "wb_operation_pack_identity_error")
  if (identical(as.numeric(x), 0)) return("0")
  if (is.integer(x)) return(as.character(x))
  trimws(formatC(as.numeric(x), digits = 15L, format = "g", flag = ""))
}

.wb_operation_pack_canonical_string <- function(x) {
  .wb_operation_pack_assert(length(x) == 1L && !is.na(x),
    "OPERATION_PACK_CANONICAL_STRING_INVALID",
    "Canonical identity strings must be non-missing UTF-8 scalar values.",
    class = "wb_operation_pack_identity_error")
  value <- iconv(as.character(x), from = "", to = "UTF-8", sub = NA_character_)
  .wb_operation_pack_assert(!is.na(value), "OPERATION_PACK_CANONICAL_STRING_INVALID",
    "Canonical identity strings must be valid UTF-8.",
    class = "wb_operation_pack_identity_error")
  # A maximum-size ordinary UTF-8 scalar need not allocate a character object
  # and execute an R callback for every code point. The slow escape path below
  # remains authoritative for quotes, backslashes and ASCII control characters.
  if (!grepl('["\\\\\\x00-\\x1F]', value, perl = TRUE)) return(paste0('"', value, '"'))
  points <- utf8ToInt(value)
  encoded <- vapply(points, function(point) {
    if (point == 34L) return("\\\"")
    if (point == 92L) return("\\\\")
    if (point == 8L) return("\\b")
    if (point == 9L) return("\\t")
    if (point == 10L) return("\\n")
    if (point == 12L) return("\\f")
    if (point == 13L) return("\\r")
    if (point < 32L) return(sprintf("\\u%04x", point))
    intToUtf8(point)
  }, character(1), USE.NAMES = FALSE)
  paste0('"', paste0(encoded, collapse = ""), '"')
}

.wb_operation_pack_canonical_string_tokens <- function(ids) {
  # Same canonical array bytes, without one R callback/iconv per ordinary ID.
  # The scalar encoder remains authoritative for escapes and diagnostics.
  if (!is.character(ids) || is.object(ids))
    stop("Canonical string-array encoder requires ordinary character values.", call. = FALSE)
  if (!length(ids)) return(character())
  missing <- is.na(ids)
  utf8 <- iconv(ids, from = "", to = "UTF-8", sub = NA_character_)
  invalid <- which(!missing & is.na(utf8))
  if (length(invalid)) .wb_operation_pack_canonical_string(ids[[invalid[[1L]]]])
  escaped <- !missing & grepl('["\\\\\\x00-\\x1F]', utf8, perl = TRUE)
  tokens <- paste0('"', utf8, '"')
  tokens[missing] <- "null"
  if (any(escaped)) tokens[escaped] <- vapply(utf8[escaped],
    .wb_operation_pack_canonical_string, character(1), USE.NAMES = FALSE)
  tokens
}

.wb_operation_pack_canonical_string_array <- function(ids) {
  paste0("[", paste(.wb_operation_pack_canonical_string_tokens(ids),
    collapse = ","), "]")
}

# Ordinary homogeneous object rows share an immutable shape, not encoded
# values. Everything is checked nonthrowingly before optimized assembly; the
# caller retains the original encoder and its row-major error precedence.
.wb_operation_pack_canonical_object_rows <- function(value, numeric_tokens) {
  tryCatch({
    if (!is.list(value) || !length(value) || !is.null(attributes(value)) || is.object(value)) return(NULL)
    limit <- getOption("scworkbench.max_dense_materialize_mb",256)*1024^2
    if (!is.numeric(limit) || length(limit)!=1L || !is.finite(limit) || limit<=0) return(NULL)
    limit <- min(32*1024^2,limit)
    state <- new.env(parent=emptyenv());state$keys<-0L;state$nodes<-0L;state$structure<-0
    plain_object <- function(node) is.list(node) && !is.object(node) &&
      !is.null(names(node)) && identical(names(attributes(node)),"names")
    compile <- function(node,depth=1L) {
      if(depth>8L)return(NULL)
      state$nodes<-state$nodes+1L
      if(plain_object(node)) {
        names<-names(node)
        if(anyNA(names)||anyDuplicated(names))return(NULL)
        state$keys<-state$keys+length(names)
        if(state$keys>128L || 32*sum(nchar(names,type="bytes"))>limit)return(NULL)
        keys<-iconv(names,from="",to="UTF-8",sub=NA_character_)
        if(anyNA(keys))return(NULL)
        state$structure<-state$structure+2+max(0,length(keys)-1L)+
          sum(6*nchar(keys,type="bytes")+3)
        children<-lapply(node,function(child)compile(child,depth+1L))
        if(any(vapply(children,is.null,logical(1))))return(NULL)
        return(list(kind="object",names=names,keys=keys,order=order(keys,method="radix"),children=children))
      }
      if(is.null(node))return(list(kind="null"))
      if(!is.null(attributes(node)) || is.object(node) || length(node)!=1L ||
          !typeof(node)%in%c("integer","double","logical","character"))return(NULL)
      kind<-if(is.numeric(node))"numeric" else typeof(node)
      if(kind=="numeric" && !numeric_tokens)return(NULL)
      list(kind=kind,type=typeof(node))
    }
    template<-compile(value[[1L]])
    if(is.null(template)||template$kind!="object")return(NULL)
    # This bounds temporary carriers even for many empty/narrow scalar leaves.
    batch_rows<-min(1000L,max(0,floor((limit-65536)/(256*state$nodes+8*state$structure))))
    if(batch_rows<1L)return(NULL)
    batch_rows<-as.integer(batch_rows)
    inspect <- function(nodes,plan) {
      n<-length(nodes)
      if(plan$kind=="object") {
        if(!all(vapply(nodes,function(node)plain_object(node)&&identical(names(node),plan$names),logical(1))))return(NULL)
        bytes<-rep(0,n)
        for(j in seq_along(plan$children)) {
          child<-inspect(lapply(nodes,`[[`,j),plan$children[[j]])
          if(is.null(child))return(NULL)
          bytes<-bytes+child
        }
        return(bytes)
      }
      if(plan$kind=="null")return(if(all(vapply(nodes,is.null,logical(1))))rep(4,n) else NULL)
      if(!all(vapply(nodes,function(node)is.null(attributes(node))&&!is.object(node)&&length(node)==1L,
          logical(1))))return(NULL)
      types<-vapply(nodes,typeof,character(1))
      # Keep exact ordinary scalar carrier types; do not implicitly broaden
      # eligibility through unlist's integer-to-double coercion.
      if(!all(types==plan$type))return(NULL)
      column<-unlist(nodes,recursive=FALSE,use.names=FALSE)
      if(plan$kind=="numeric") {
        if(!all((is.finite(column)|is.na(column)) &
            (is.na(column)|column==0|abs(column)>=1e-307)))return(NULL)
        return(rep(32,n))
      }
      if(plan$kind=="logical")return(rep(5,n))
      # Admit conversion before iconv; UTF8 can use at most four bytes per
      # original byte. The later ledger uses actual converted UTF8 lengths.
      if(32*sum(nchar(column,type="bytes"),na.rm=TRUE)+256*state$nodes*n>limit)return(NULL)
      converted<-iconv(column,from="",to="UTF-8",sub=NA_character_)
      if(any(!is.na(column)&is.na(converted)))return(NULL)
      ifelse(is.na(converted),4,6*nchar(converted,type="bytes")+2)
    }
    starts<-seq.int(1L,length(value),by=batch_rows)
    # ALL rows, including late invalid leaves, are eligible before any fast
    # framing. A fallback therefore preserves the old first error exactly.
    for(start in starts) {
      selected<-seq.int(start,min(length(value),start+batch_rows-1L))
      bytes<-inspect(value[selected],template)
      if(is.null(bytes)||65536+256*state$nodes*length(selected)+
          8*sum(bytes+state$structure)>limit)return(NULL)
    }
    prefixes<-function(plan) {
      if(plan$kind=="object") {
        plan$prefixes<-vapply(plan$order,function(j)paste0(
          .wb_operation_pack_canonical_string(plan$keys[[j]]),":"),character(1))
        plan$children<-lapply(plan$children,prefixes)
      }
      plan
    }
    template<-prefixes(template)
    emit <- function(nodes,plan) {
      n<-length(nodes)
      if(plan$kind=="object") {
        rows<-rep("{",n)
        for(k in seq_along(plan$order)) {
          j<-plan$order[[k]]
          tokens<-emit(lapply(nodes,`[[`,j),plan$children[[j]])
          rows<-paste0(rows,if(k==1L)"" else ",",plan$prefixes[[k]],tokens)
        }
        return(paste0(rows,"}"))
      }
      if(plan$kind=="null")return(rep("null",n))
      column<-unlist(nodes,recursive=FALSE,use.names=FALSE)
      if(plan$kind=="character")return(.wb_operation_pack_canonical_string_tokens(column))
      if(plan$kind=="logical")return(ifelse(is.na(column),"null",ifelse(column,"true","false")))
      tokens<-.Call(C_scwb_canonical_numeric_tokens,column)
      if(is.null(tokens))stop("Numeric object-row eligibility changed.")
      tokens
    }
    batches<-vapply(starts,function(start) {
      selected<-seq.int(start,min(length(value),start+batch_rows-1L))
      paste(emit(value[selected],template),collapse=",")
    },character(1))
    paste0("[",paste(batches,collapse=","),"]")
  },error=function(e)NULL)
}


.wb_operation_pack_canonical_json <- function(x) {
  # A single invocation-local last-name plan. Never reuse encoded values;
  # nested objects can replace this plan and merely cause a later cache miss.
  last_key_plan <- NULL
  fast_numeric <- exists("C_scwb_canonical_numeric", inherits = TRUE) &&
    identical(getOption("OutDec", "."), ".") &&
    identical(Sys.localeconv()[["decimal_point"]], ".")
  fast_numeric_tokens <- fast_numeric &&
    exists("C_scwb_canonical_numeric_tokens", inherits = TRUE)
  fast_numeric_array <- fast_numeric &&
    exists("C_scwb_canonical_numeric_array", inherits = TRUE)
  encode <- function(value) {
    if (is.null(value)) return("null")
    if (is.factor(value)) value <- as.character(value)
    if (is.data.frame(value)) {
      # Ordinary table rows share one key shape. Assemble the SAME canonical
      # row objects in bounded token batches, not one recursively built R list
      # per row. Questionable inputs fall back before emitting anything, so the
      # original row-major typed diagnostics retain precedence.
      plain <- identical(class(value), "data.frame") && nrow(value) > 0L &&
        ncol(value) > 0L && !anyNA(names(value)) && !anyDuplicated(names(value)) &&
        all(vapply(value, function(column) is.null(attributes(column)) &&
          typeof(column) %in% c("integer", "double", "logical", "character"), logical(1)))
      keys <- NULL
      if (plain) {
        keys <- tryCatch(iconv(names(value), from = "", to = "UTF-8",
          sub = NA_character_), error = function(e) NULL)
        plain <- !is.null(keys) && !anyNA(keys) && all(vapply(value,
          function(column) {
            if (is.numeric(column)) return(all((is.finite(column) | is.na(column)) &
              (is.na(column) | column == 0 | abs(column) >= 1e-307)))
            if (!is.character(column)) return(TRUE)
            converted <- tryCatch(iconv(column, from = "", to = "UTF-8",
              sub = NA_character_), error = function(e) NULL)
            !is.null(converted) && !any(!is.na(column) & is.na(converted))
          }, logical(1)))
      }
      if (plain) {
        ord <- order(keys, method = "radix")
        prefixes <- vapply(ord, function(i)
          paste0(.wb_operation_pack_canonical_string(keys[[i]]), ":"), character(1))
        batches <- vapply(seq.int(1L, nrow(value), by = 1000L), function(start) {
          selected <- seq.int(start, min(nrow(value), start + 999L))
          rows <- rep("", length(selected))
          for (j in seq_along(ord)) {
            column <- value[[ord[[j]]]][selected]
            tokens <- if (is.character(column)) {
              .wb_operation_pack_canonical_string_tokens(column)
            } else {
              batch <- if (fast_numeric_tokens && is.numeric(column))
                .Call(C_scwb_canonical_numeric_tokens, column) else NULL
              if (!is.null(batch)) batch else
                vapply(seq_along(column), function(i) encode(column[[i]]), character(1))
            }
            rows <- paste0(rows, if (j == 1L) "" else ",", prefixes[[j]], tokens)
          }
          paste(paste0("{", rows, "}"), collapse = ",")
        }, character(1))
        return(paste0("[", paste(batches, collapse = ","), "]"))
      }
      value <- lapply(seq_len(nrow(value)), function(i) as.list(value[i, , drop = FALSE]))
    }
    if (is.atomic(value) && length(value) != 1L) {
      if (is.character(value) && is.null(attributes(value)))
        return(.wb_operation_pack_canonical_string_array(value))
      if (fast_numeric_array) {
        array <- .Call(C_scwb_canonical_numeric_array, value, FALSE)
        if (!is.null(array)) return(array)
      }
      if (fast_numeric_tokens) {
        batch <- .Call(C_scwb_canonical_numeric_tokens, value)
        if (!is.null(batch)) return(paste0("[",paste(batch,collapse=","),"]"))
      }
      return(paste0("[", paste(vapply(seq_along(value), function(i) encode(value[[i]]), character(1)), collapse = ","), "]"))
    }
    if (is.atomic(value) && length(value) == 1L && is.na(value)) return("null")
    if (is.list(value)) {
      nms <- names(value)
      if (is.null(nms)) {
        if (fast_numeric_array) {
          array <- .Call(C_scwb_canonical_numeric_array, value, FALSE)
          if (!is.null(array)) return(array)
        }
        if (fast_numeric_tokens) {
          batch <- .Call(C_scwb_canonical_numeric_tokens, value)
          if (!is.null(batch)) return(paste0("[",paste(batch,collapse=","),"]"))
        }
        if (length(value) && all(vapply(value, function(item)
            is.character(item) && length(item) == 1L &&
              is.null(attributes(item)), logical(1))))
          return(.wb_operation_pack_canonical_string_array(
            vapply(value, identity, character(1), USE.NAMES = FALSE)))
        rows <- .wb_operation_pack_canonical_object_rows(value,fast_numeric_tokens)
        if(!is.null(rows))return(rows)
        return(paste0("[", paste(vapply(value, encode, character(1)), collapse = ","), "]"))
      }
      encoding <- Encoding(nms)
      locale <- Sys.getlocale("LC_CTYPE")
      plan <- last_key_plan
      if (is.null(plan) || !identical(plan$names, nms) ||
          !identical(plan$encoding, encoding) || !identical(plan$locale, locale)) {
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
        plan <- list(names = nms, encoding = encoding, locale = locale,
          order = ord, prefixes = vapply(ord, function(i)
            paste0(.wb_operation_pack_canonical_string(keys[[i]]), ":"),
            character(1)))
        last_key_plan <<- plan
      }
      fields <- vapply(seq_along(plan$order), function(i)
        paste0(plan$prefixes[[i]], encode(value[[plan$order[[i]]]])), character(1))
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

.wb_operation_pack_sha256 <- function(x) {
  .wb_require_pkg("digest", "operation-pack canonical identity")
  digest::digest(.wb_operation_pack_canonical_json(x), algo = "sha256", serialize = FALSE)
}

# The operation/semantic catalogs predate the cross-language pack identity
# scheme and retain their accepted v1 serializer. Pack identities embedded in
# those catalogs still carry their new explicit scheme and digests.
.wb_operation_catalog_canonicalize_v1 <- function(x) {
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) {
    return(lapply(seq_len(nrow(x)), function(i) {
      .wb_operation_catalog_canonicalize_v1(as.list(x[i, , drop = FALSE]))
    }))
  }
  if (is.list(x)) {
    out <- lapply(x, .wb_operation_catalog_canonicalize_v1)
    nms <- names(x)
    if (!is.null(nms)) {
      ord <- order(nms, method = "radix")
      out <- out[ord]
      names(out) <- nms[ord]
    }
    return(out)
  }
  if (is.integer(x) || is.logical(x) || is.character(x)) return(x)
  if (is.numeric(x)) return(as.numeric(x))
  x
}

.wb_operation_catalog_sha256_v1 <- function(x) {
  .wb_require_pkg("jsonlite", "operation catalog identity")
  .wb_require_pkg("digest", "operation catalog identity")
  bytes <- as.character(jsonlite::toJSON(
    .wb_operation_catalog_canonicalize_v1(x), auto_unbox = TRUE, null = "null",
    na = "null", digits = NA, pretty = FALSE
  ))
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

.wb_operation_pack_manifest_path <- function(package, lib.loc = NULL) {
  package <- .wb_operation_pack_scalar(package, "package", "^[A-Za-z][A-Za-z0-9.]*$")
  path <- system.file("scworkbench", "operation-pack.json", package = package, lib.loc = lib.loc)
  .wb_operation_pack_assert(nzchar(path) && file.exists(path), "OPERATION_PACK_MANIFEST_NOT_FOUND",
    paste0("Installed package '", package, "' has no inst/scworkbench/operation-pack.json manifest."),
    package = package)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_json_number_tokens <- function(text) {
  # Called after JSON parsing. Skip complete quoted tokens in compiled PCRE,
  # preserving original numeric lexemes without a per-byte R masking loop.
  # Possessive runs avoid recursive matching per character of large strings.
  pattern <- paste0('"(?:[^"\\\\]++|\\\\.)*+"(*SKIP)(*F)|',
    "-?(?:0|[1-9][0-9]*)(?:[.][0-9]+)?(?:[eE][+-]?[0-9]+)?")
  unname(regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]])
}

.wb_operation_pack_decorate_numbers <- function(value, tokens) {
  index <- 0L
  decorate <- function(x) {
    if (is.list(x)) return(lapply(x, decorate))
    if (is.integer(x) || is.numeric(x)) {
      index <<- index + 1L
      .wb_operation_pack_assert(index <= length(tokens),
        "OPERATION_PACK_MANIFEST_INVALID",
        "Operation-pack JSON numeric token accounting failed.",
        class = "wb_operation_pack_validation_error")
      canonical <- .wb_operation_pack_canonical_number(tokens[[index]])
      attr(x, "operation_pack_json_number") <- tokens[[index]]
      attr(x, "operation_pack_canonical_number") <- canonical
    }
    x
  }
  out <- decorate(value)
  .wb_operation_pack_assert(index == length(tokens),
    "OPERATION_PACK_MANIFEST_INVALID",
    "Operation-pack JSON numeric token accounting failed.",
    class = "wb_operation_pack_validation_error")
  out
}

.wb_operation_pack_parse_canonical_json <- function(text) {
  .wb_require_pkg("jsonlite", "operation-pack manifest")
  parsed <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = identity)
  .wb_operation_pack_assert(!inherits(parsed, "error"),
    "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Operation-pack input is not valid JSON: ",
           if (inherits(parsed, "error")) conditionMessage(parsed) else "unknown parse failure"),
    class = "wb_operation_pack_validation_error")
  .wb_operation_pack_decorate_numbers(
    parsed, .wb_operation_pack_json_number_tokens(text))
}

.wb_operation_pack_read_manifest <- function(path) {
  .wb_require_pkg("jsonlite", "operation-pack manifest")
  path <- .wb_operation_pack_scalar(path, "manifest")
  .wb_operation_pack_assert(file.exists(path), "OPERATION_PACK_MANIFEST_NOT_FOUND",
                            paste0("Operation-pack manifest does not exist: ", path), manifest = path)
  size <- file.info(path)$size
  text <- readChar(path, nchars = size, useBytes = TRUE)
  manifest <- .wb_operation_pack_parse_canonical_json(text)
  .wb_operation_pack_assert(is.list(manifest),
    "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Operation-pack manifest is not a JSON object: ", path),
    manifest = path)
  manifest
}

.wb_operation_pack_allowed_primitives <- function() {
  c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family",
    "relation_family", "feature_table", "obs_table", "model_ref",
    "path_2d_family", "space_path_family")
}

.wb_operation_pack_reserved_namespaces <- function() {
  c("scworkbench", "core", "wb", "internal", "base", "stats", "utils",
    "methods", "graphics", "grDevices", "datasets")
}

.wb_operation_pack_version_satisfies <- function(version, requirement) {
  version <- as.character(version)[1]
  requirement <- trimws(as.character(requirement)[1])
  clauses <- strsplit(requirement, "[[:space:],]+", perl = TRUE)[[1]]
  clauses <- clauses[nzchar(clauses)]
  if (!length(clauses)) return(FALSE)
  all(vapply(clauses, function(clause) {
    m <- regexec("^(>=|<=|==|=|>|<)([0-9]+(?:[.][0-9A-Za-z-]+)*)$", clause, perl = TRUE)
    hit <- regmatches(clause, m)[[1]]
    if (length(hit) != 3L) return(FALSE)
    cmp <- utils::compareVersion(version, hit[3])
    switch(hit[2], ">=" = cmp >= 0L, "<=" = cmp <= 0L, ">" = cmp > 0L,
           "<" = cmp < 0L, "=" = cmp == 0L, "==" = cmp == 0L, FALSE)
  }, logical(1)))
}

.wb_operation_pack_validate_param <- function(param, op_name) {
  .wb_operation_pack_named_object(param, paste0(op_name, "$params[]"), allow_empty = FALSE)
  allowed <- c("name", "type", "default", "required", "nullable", "allow_non_finite",
               "allow_empty", "min", "max", "choices", "help")
  extra <- setdiff(names(param), allowed)
  .wb_operation_pack_assert(!length(extra), "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", op_name, "' parameter contains unsupported fields: ", paste(extra, collapse = ", "), "."),
    operation = op_name)
  name <- .wb_operation_pack_scalar(param$name, paste0(op_name, "$params$name"), "^[a-z][a-z0-9_]*$")
  type <- .wb_operation_pack_scalar(param$type, paste0(op_name, "$params$", name, "$type"))
  supported <- c("int", "int_range", "int_vec", "dbl", "number", "bool", "logical",
                 "string", "path", "cell_set", "choice", "string_vec", "string_array",
                 "cell_ids", "metadata_field", "metadata_field_array", "string_vec_or_list",
                 "cell_ids_or_set", "list_or_cell_set", "list")
  .wb_operation_pack_assert(type %in% supported, "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", op_name, "' parameter '", name, "' has unsupported type '", type, "'."),
    operation = op_name, parameter = name)
  if ("allow_empty" %in% names(param)) {
    .wb_operation_pack_assert(is.logical(param$allow_empty) &&
      length(param$allow_empty) == 1L && !is.na(param$allow_empty) &&
      type %in% c("string_vec", "string_array", "cell_ids"),
      "OPERATION_PACK_PARAMETER_INVALID",
      paste0("Operation '", op_name, "' parameter '", name,
        "' has an invalid allow_empty declaration."),
      operation = op_name, parameter = name)
  }
  if (identical(type, "choice")) {
    choices <- unlist(param$choices %||% list(), use.names = FALSE)
    .wb_operation_pack_assert(is.character(choices) && length(choices) && !anyNA(choices) &&
      all(nzchar(choices)) && !anyDuplicated(choices), "OPERATION_PACK_PARAMETER_INVALID",
      paste0("Operation '", op_name, "' choice parameter '", name, "' requires unique non-empty choices."),
      operation = op_name, parameter = name)
    param$choices <- choices
  }
  if ("default" %in% names(param)) {
    tryCatch(.wb_validate_param_value(param$default, param, op_name), error = function(e) {
      .wb_operation_pack_abort("OPERATION_PACK_PARAMETER_INVALID",
        paste0("Operation '", op_name, "' parameter '", name, "' has an invalid default: ", conditionMessage(e)),
        operation = op_name, parameter = name, class = "wb_operation_pack_validation_error")
    })
  }
  param$name <- name
  param$type <- type
  param
}

.wb_operation_pack_validate_definition <- function(definition, namespace) {
  .wb_operation_pack_named_object(definition, "manifest$operations[]", allow_empty = FALSE)
  allowed <- c("name", "title", "description", "intent", "requires", "optional_requires",
               "inputs", "params", "produces", "promotable", "replay_equivalence", "coverage",
               "interface_produces", "chunking", "determinism", "resources", "software")
  extra <- setdiff(names(definition), allowed)
  .wb_operation_pack_assert(!length(extra), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation definition contains forbidden or unknown fields: ", paste(extra, collapse = ", "), "."))
  required_fields <- c("name", "title", "description", "intent", "requires", "inputs", "params",
                       "produces", "promotable", "replay_equivalence", "determinism", "resources", "software")
  missing <- setdiff(required_fields, names(definition))
  .wb_operation_pack_assert(!length(missing), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation definition is missing required fields: ", paste(missing, collapse = ", "), "."))

  name <- .wb_operation_pack_scalar(definition$name, "operation$name",
                                    "^[a-z][a-z0-9._-]*::[a-z][a-z0-9_]*$")
  expected_prefix <- paste0(namespace, "::")
  .wb_operation_pack_assert(startsWith(name, expected_prefix), "OPERATION_PACK_NAMESPACE_MISMATCH",
    paste0("Operation '", name, "' must use namespace '", namespace, "'."), operation = name)
  .wb_operation_pack_scalar(definition$title, paste0(name, "$title"))
  .wb_operation_pack_scalar(definition$description, paste0(name, "$description"))
  intent <- unlist(definition$intent, use.names = FALSE)
  .wb_operation_pack_assert(is.character(intent) && length(intent) && !anyNA(intent) && all(nzchar(intent)),
    "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' intent must be non-empty."), operation = name)

  requires <- .wb_operation_pack_named_object(definition$requires, paste0(name, "$requires"))
  optional <- .wb_operation_pack_named_object(definition$optional_requires %||% list(), paste0(name, "$optional_requires"))
  typed <- c(requires, optional)
  .wb_operation_pack_assert(!anyDuplicated(names(typed)), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation '", name, "' duplicates a required/optional input."), operation = name)
  kinds <- unlist(typed, use.names = FALSE)
  .wb_operation_pack_assert(is.character(kinds) && all(kinds %in% .wb_operation_pack_allowed_primitives()),
    "OPERATION_PACK_PRIMITIVE_UNSUPPORTED",
    paste0("Operation '", name, "' declares an unknown input primitive: ",
           paste(setdiff(kinds, .wb_operation_pack_allowed_primitives()), collapse = ", "), "."), operation = name)
  inputs <- .wb_operation_pack_named_object(definition$inputs, paste0(name, "$inputs"))
  .wb_operation_pack_assert(setequal(names(inputs), names(typed)), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation '", name, "' inputs must exactly describe requires and optional_requires."), operation = name)
  for (input_name in names(typed)) {
    item <- .wb_operation_pack_named_object(inputs[[input_name]], paste0(name, "$inputs$", input_name), allow_empty = FALSE)
    item_kind <- as.character(item$kind %||% "")[1]
    .wb_operation_pack_assert(identical(item_kind, as.character(typed[[input_name]])[1]),
      "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' input '", input_name,
      "' kind must match its typed requirement."), operation = name, input = input_name)
    required_flag <- item$required
    .wb_operation_pack_assert(is.logical(required_flag) && length(required_flag) == 1L && !is.na(required_flag) &&
      identical(isTRUE(required_flag), input_name %in% names(requires)),
      "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' input '", input_name,
      "' required flag disagrees with requires/optional_requires."), operation = name, input = input_name)
  }

  produces <- .wb_operation_pack_named_object(definition$produces, paste0(name, "$produces"), allow_empty = FALSE)
  output_kinds <- unlist(produces, use.names = FALSE)
  .wb_operation_pack_assert(all(grepl("^[a-z][a-z0-9_]*$", names(produces), perl = TRUE)),
    "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' output names are malformed."), operation = name)
  .wb_operation_pack_assert(is.character(output_kinds) && all(output_kinds %in% .wb_operation_pack_allowed_primitives()),
    "OPERATION_PACK_PRIMITIVE_UNSUPPORTED",
    paste0("Operation '", name, "' declares an unknown output primitive: ",
           paste(setdiff(output_kinds, .wb_operation_pack_allowed_primitives()), collapse = ", "), "."), operation = name)
  interface_produces <- .wb_operation_pack_named_object(
    definition$interface_produces %||% lapply(produces, function(kind) list(kind = kind)),
    paste0(name, "$interface_produces"), allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(interface_produces), names(produces)),
    "OPERATION_PACK_OUTPUT_INVALID",
    paste0("Operation '", name, "' interface_produces must exactly describe declared outputs."), operation = name)
  for (output_name in names(produces)) {
    item <- .wb_operation_pack_named_object(interface_produces[[output_name]],
      paste0(name, "$interface_produces$", output_name), allow_empty = FALSE)
    actual <- as.character(item$kind %||% "")[1]
    .wb_operation_pack_assert(identical(actual, as.character(produces[[output_name]])[1]),
      "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' output '", output_name,
      "' interface kind disagrees with produces."), operation = name, output = output_name)
  }
  promotable <- unlist(definition$promotable, use.names = FALSE)
  .wb_operation_pack_assert(is.character(promotable) && length(promotable) && !anyNA(promotable) &&
    all(nzchar(promotable)) && !anyDuplicated(promotable) && all(promotable %in% names(produces)),
    "OPERATION_PACK_PROMOTABLE_INVALID",
    paste0("Operation '", name, "' must declare unique promotable terminal outputs drawn from produces."), operation = name)
  replay <- .wb_operation_pack_named_object(definition$replay_equivalence,
                                             paste0(name, "$replay_equivalence"), allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(replay), names(produces)), "OPERATION_PACK_OUTPUT_INVALID",
    paste0("Operation '", name, "' replay_equivalence must cover every output exactly."), operation = name)
  policies <- unlist(replay, use.names = FALSE)
  .wb_operation_pack_assert(all(policies %in% .wb_replay_equivalence_policies()),
    "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' has an unsupported replay-equivalence policy."), operation = name)
  .wb_operation_pack_assert(!any(unlist(replay[promotable], use.names = FALSE) == "not_comparable"),
    "OPERATION_PACK_PROMOTABLE_INVALID", paste0("Operation '", name,
    "' promotable terminals must declare an executable replay-equivalence policy."), operation = name)

  coverage <- .wb_operation_pack_named_object(definition$coverage %||% list(), paste0(name, "$coverage"))
  .wb_operation_pack_assert(all(names(coverage) %in% names(typed)) &&
    all(unlist(coverage, use.names = FALSE) %in% c("cell_indexed", "reference_only", "model_associated_unless_query_space")),
    "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' coverage contains an unknown input or mode."), operation = name)
  .wb_operation_pack_named_object(definition$determinism, paste0(name, "$determinism"), allow_empty = FALSE)
  .wb_operation_pack_named_object(definition$resources, paste0(name, "$resources"), allow_empty = FALSE)
  .wb_operation_pack_named_object(definition$software, paste0(name, "$software"), allow_empty = FALSE)

  params <- definition$params %||% list()
  .wb_operation_pack_assert(is.list(params), "OPERATION_PACK_PARAMETER_INVALID",
                            paste0("Operation '", name, "' params must be an array."), operation = name)
  params <- lapply(params, .wb_operation_pack_validate_param, op_name = name)
  param_names <- vapply(params, function(p) p$name, character(1))
  .wb_operation_pack_assert(!anyDuplicated(param_names), "OPERATION_PACK_PARAMETER_INVALID",
                            paste0("Operation '", name, "' duplicates parameter names."), operation = name)
  reserved_inputs <- unique(c(names(typed), names(.wb_op_engine_input_specs())))
  .wb_operation_pack_assert(!length(intersect(param_names, reserved_inputs)), "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", name, "' parameters collide with typed or engine inputs: ",
           paste(intersect(param_names, reserved_inputs), collapse = ", "), "."), operation = name)

  definition$name <- name
  definition$op_name <- name
  definition$intent <- intent
  definition$requires <- requires
  definition$optional_requires <- optional
  definition$inputs <- inputs
  definition$params <- params
  definition$produces <- produces
  definition$interface_produces <- interface_produces
  definition$promotable <- promotable
  definition$replay_equivalence <- replay
  definition$coverage <- coverage
  definition$definition_sha256 <- .wb_operation_pack_sha256(definition[setdiff(names(definition), c("op_name", "definition_sha256"))])
  definition
}

.wb_operation_pack_validate_manifest <- function(manifest, package = NULL, package_description = NULL,
                                                 expected_backend = NULL) {
  .wb_operation_pack_named_object(manifest, "manifest", allow_empty = FALSE)
  allowed <- c("schema_version", "protocol_version", "identity_scheme", "namespace", "package", "backend",
               "compatibility", "entry_point", "operations")
  extra <- setdiff(names(manifest), allowed)
  missing <- setdiff(setdiff(allowed, "identity_scheme"), names(manifest))
  .wb_operation_pack_assert(!length(extra) && !length(missing), "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Manifest fields disagree with v1 schema; missing=[", paste(missing, collapse = ", "),
           "], unknown=[", paste(extra, collapse = ", "), "]."))
  schema_version <- .wb_operation_pack_scalar(manifest$schema_version, "schema_version")
  protocol_version <- .wb_operation_pack_scalar(manifest$protocol_version, "protocol_version")
  identity_scheme <- if ("identity_scheme" %in% names(manifest)) {
    .wb_operation_pack_scalar(manifest$identity_scheme, "identity_scheme")
  } else .wb_operation_pack_identity_scheme()
  .wb_operation_pack_assert(identical(identity_scheme, .wb_operation_pack_identity_scheme()),
    "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH",
    paste0("Operation-pack manifest claims unsupported identity scheme '", identity_scheme,
           "'; required '", .wb_operation_pack_identity_scheme(), "'."),
    expected_identity_scheme = .wb_operation_pack_identity_scheme(),
    observed_identity_scheme = identity_scheme,
    class = "wb_operation_pack_identity_error")
  .wb_operation_pack_assert(identical(schema_version, "scworkbench.operation_pack.v1"),
    "OPERATION_PACK_SCHEMA_INCOMPATIBLE", paste0("Unsupported operation-pack schema: ", schema_version, "."))
  .wb_operation_pack_assert(identical(protocol_version, .wb_operation_pack_protocol_version()),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE",
    paste0("Operation-pack protocol '", protocol_version, "' is incompatible with protocol '",
           .wb_operation_pack_protocol_version(), "'."), protocol_version = protocol_version)
  namespace <- .wb_operation_pack_scalar(manifest$namespace, "namespace", "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
  .wb_operation_pack_assert(!namespace %in% .wb_operation_pack_reserved_namespaces(),
    "OPERATION_PACK_NAMESPACE_RESERVED", paste0("Operation-pack namespace '", namespace, "' is reserved."), namespace = namespace)
  backend <- .wb_operation_pack_scalar(manifest$backend, "backend")
  .wb_operation_pack_assert(backend %in% .wb_operation_pack_supported_backends(),
    "OPERATION_PACK_BACKEND_UNSUPPORTED",
    paste0("Unsupported operation-pack backend '", backend,
           "'; protocol v1 supports exactly 'R' and 'Python'."), backend = backend)
  if (!is.null(expected_backend) && !identical(backend, as.character(expected_backend)[1])) {
    if (identical(backend, "Python") && identical(as.character(expected_backend)[1], "R")) {
      .wb_operation_pack_abort(
        "OPERATION_PACK_RUNTIME_UNAVAILABLE",
        paste0("Python operation pack '", namespace,
               "' is structurally supported, but Python runtime activation is unavailable in this checkpoint."),
        backend = backend, namespace = namespace,
        class = "wb_operation_pack_runtime_unavailable"
      )
    }
    .wb_operation_pack_abort(
      "OPERATION_PACK_BACKEND_MISMATCH",
      paste0("Operation-pack backend '", backend, "' cannot be admitted by runtime '",
             as.character(expected_backend)[1], "'."),
      backend = backend, expected_backend = as.character(expected_backend)[1],
      class = "wb_operation_pack_validation_error"
    )
  }
  package_rec <- .wb_operation_pack_named_object(manifest$package, "package", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(package_rec), c("name", "version")), "OPERATION_PACK_MANIFEST_INVALID",
                            "Manifest package must contain exactly name and version.")
  if (identical(backend, "R")) {
    package_name <- .wb_operation_pack_scalar(package_rec$name, "package$name", "^[A-Za-z][A-Za-z0-9.]*$")
    package_version <- .wb_operation_pack_scalar(package_rec$version, "package$version", "^[0-9]+(?:[.-][0-9A-Za-z]+)*$")
  } else {
    package_name <- .wb_operation_pack_scalar(
      package_rec$name, "package$name",
      "^(?:[A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])\\z"
    )
    package_version <- .wb_operation_pack_scalar(package_rec$version, "package$version")
    .wb_operation_pack_python_version_key(package_version)
  }
  if (!is.null(package)) {
    .wb_operation_pack_assert(identical(backend, "R"), "OPERATION_PACK_BACKEND_MISMATCH",
      "Installed-R-package identity may be supplied only for backend 'R'.",
      backend = backend, class = "wb_operation_pack_validation_error")
    .wb_operation_pack_assert(identical(package_name, as.character(package)[1]),
      "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", paste0("Manifest package '", package_name,
        "' does not match installed package '", package, "'."), package = package)
  }
  if (!is.null(package_description)) {
    .wb_operation_pack_assert(identical(backend, "R"), "OPERATION_PACK_BACKEND_MISMATCH",
      "R package metadata may be supplied only for backend 'R'.",
      backend = backend, class = "wb_operation_pack_validation_error")
    installed_version <- as.character(package_description$Version %||% "")[1]
    .wb_operation_pack_assert(identical(package_version, installed_version),
      "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", paste0("Manifest version '", package_version,
      "' does not match installed package version '", installed_version, "'."), package = package_name)
  }
  compatibility <- .wb_operation_pack_named_object(manifest$compatibility, "compatibility", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(compatibility), c("scworkbench", "protocol")),
                            "OPERATION_PACK_MANIFEST_INVALID",
                            "Manifest compatibility must contain exactly scworkbench and protocol.")
  requirement <- .wb_operation_pack_scalar(compatibility$scworkbench, "compatibility$scworkbench")
  required_protocol <- .wb_operation_pack_scalar(compatibility$protocol, "compatibility$protocol")
  current_version <- tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "0.1.0")
  .wb_operation_pack_assert(.wb_operation_pack_version_satisfies(current_version, requirement),
    "OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE", paste0("Pack requires scworkbench '", requirement,
    "'; current version is '", current_version, "'."), requirement = requirement, current_version = current_version)
  .wb_operation_pack_assert(identical(required_protocol, .wb_operation_pack_protocol_version()),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE", paste0("Pack compatibility requires protocol '",
    required_protocol, "'; current protocol is '", .wb_operation_pack_protocol_version(), "'."))
  entry_point_pattern <- if (identical(backend, "R")) {
    "^[A-Za-z][A-Za-z0-9._]*$"
  } else {
    "^[A-Za-z0-9][A-Za-z0-9._-]*$"
  }
  entry_point <- .wb_operation_pack_scalar(manifest$entry_point, "entry_point", entry_point_pattern)
  operations <- manifest$operations
  .wb_operation_pack_assert(is.list(operations) && length(operations), "OPERATION_PACK_DEFINITION_INVALID",
                            "Manifest operations must be a non-empty array.")
  operations <- lapply(operations, .wb_operation_pack_validate_definition, namespace = namespace)
  op_names <- vapply(operations, function(x) x$name, character(1))
  .wb_operation_pack_assert(!anyDuplicated(op_names), "OPERATION_PACK_OPERATION_DUPLICATE",
                            "Manifest contains duplicate operation names.", namespace = namespace)
  names(operations) <- op_names
  manifest$operations <- unname(operations)
  manifest$schema_version <- schema_version
  manifest$protocol_version <- protocol_version
  manifest$identity_scheme <- identity_scheme
  manifest$namespace <- namespace
  manifest$package <- list(name = package_name, version = package_version)
  manifest$backend <- backend
  manifest$compatibility <- list(scworkbench = requirement, protocol = required_protocol)
  manifest$entry_point <- entry_point
  manifest
}

.wb_operation_pack_identity <- function(manifest) {
  operation_names <- vapply(manifest$operations, function(x) x$name, character(1))
  definition_hashes <- stats::setNames(
    vapply(manifest$operations, function(x) x$definition_sha256, character(1)), operation_names)
  manifest_identity_input <- manifest
  manifest_identity_input$operations <- lapply(manifest_identity_input$operations, function(x) x[setdiff(names(x), c("op_name", "definition_sha256"))])
  manifest_sha256 <- .wb_operation_pack_sha256(manifest_identity_input)
  pack_identity <- list(
    identity_scheme = .wb_operation_pack_identity_scheme(),
    schema_version = manifest$schema_version,
    protocol_version = manifest$protocol_version,
    manifest_sha256 = manifest_sha256,
    namespace = manifest$namespace,
    package = manifest$package,
    backend = manifest$backend,
    compatibility = manifest$compatibility,
    entry_point = manifest$entry_point,
    operation_definition_sha256 = as.list(definition_hashes)
  )
  if (identical(manifest$backend, "Python")) {
    pack_identity$distribution <- list(
      declared_name = manifest$package$name,
      normalized_name = .wb_operation_pack_python_normalize_name(manifest$package$name),
      version = manifest$package$version
    )
    pack_identity$entry_point_group <- .wb_operation_pack_python_entry_point_group()
  }
  pack_identity$pack_sha256 <- .wb_operation_pack_sha256(pack_identity)
  pack_identity
}

.wb_operation_pack_registration <- function(manifest, runners, package_description = NULL,
                                            installed_path = NULL) {
  operation_names <- vapply(manifest$operations, function(x) x$name, character(1))
  .wb_operation_pack_assert(identical(manifest$backend, "R"),
    "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    paste0("Backend '", manifest$backend,
           "' cannot register R runner functions in this runtime checkpoint."),
    backend = manifest$backend, namespace = manifest$namespace,
    class = "wb_operation_pack_runtime_unavailable")
  .wb_operation_pack_named_object(runners, "operations", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(runners), operation_names), "OPERATION_PACK_ENTRY_POINT_INVALID",
    paste0("Entry point runners must exactly match manifest operations; expected [",
           paste(operation_names, collapse = ", "), "]."), namespace = manifest$namespace)
  for (name in names(runners)) {
    runner <- runners[[name]]
    .wb_operation_pack_assert(is.function(runner), "OPERATION_PACK_ENTRY_POINT_INVALID",
                              paste0("Entry point for operation '", name, "' is not a function."), operation = name)
    expected <- c("bundle", "resolved", "effective_cells", "inputs", "...")
    .wb_operation_pack_assert(identical(names(formals(runner)), expected), "OPERATION_PACK_ENTRY_POINT_INVALID",
      paste0("Runner '", name, "' must have formals: ", paste(expected, collapse = ", "), "."), operation = name)
  }
  pack_identity <- .wb_operation_pack_identity(manifest)
  attestation <- list(
    package = manifest$package,
    built = as.character(package_description$Built %||% NA_character_)[1],
    remote_sha = as.character(package_description$RemoteSha %||% NA_character_)[1]
  )
  structure(list(manifest = manifest, runners = runners, identity = pack_identity,
                 runtime_attestation = attestation),
            class = c("wb_operation_pack_registration", "list"))
}

.wb_operation_pack_manifest_input <- function(manifest) {
  if (is.character(manifest) && length(manifest) == 1L && !is.na(manifest)) {
    return(.wb_operation_pack_read_manifest(manifest))
  }
  .wb_operation_pack_assert(is.list(manifest), "OPERATION_PACK_MANIFEST_INVALID",
                            "manifest must be a parsed JSON object or a path to one.")
  manifest
}

.wb_operation_pack_python_runtime_identity_validate <- function(manifest, runtime_identity) {
  .wb_operation_pack_named_object(runtime_identity, "runtime_identity", allow_empty = FALSE)
  .wb_operation_pack_assert(identical(as.character(runtime_identity$backend %||% "")[1], "Python"),
    "OPERATION_PACK_BACKEND_MISMATCH",
    "Python runtime identity must declare backend 'Python'.",
    backend = runtime_identity$backend %||% NULL,
    class = "wb_operation_pack_validation_error")
  distribution <- runtime_identity$distribution %||% NULL
  .wb_operation_pack_assert(is.list(distribution), "OPERATION_PACK_DISTRIBUTION_UNAVAILABLE",
    paste0("Python distribution '", manifest$package$name, "' is not installed or could not be resolved."),
    distribution = manifest$package$name,
    class = "wb_operation_pack_runtime_unavailable")
  observed_name <- .wb_operation_pack_scalar(distribution$name, "runtime_identity$distribution$name")
  observed_version <- .wb_operation_pack_scalar(distribution$version, "runtime_identity$distribution$version")
  expected_normalized <- .wb_operation_pack_python_normalize_name(manifest$package$name)
  observed_normalized <- .wb_operation_pack_python_normalize_name(observed_name)
  .wb_operation_pack_assert(identical(expected_normalized, observed_normalized),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    paste0("Manifest distribution '", manifest$package$name, "' normalizes to '", expected_normalized,
           "', but installed metadata name '", observed_name, "' normalizes to '", observed_normalized, "'."),
    expected_distribution = manifest$package$name, observed_distribution = observed_name,
    class = "wb_operation_pack_validation_error")
  .wb_operation_pack_assert(
    identical(.wb_operation_pack_python_version_key(manifest$package$version),
              .wb_operation_pack_python_version_key(observed_version)),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    paste0("Manifest distribution version '", manifest$package$version,
           "' is not PEP 440-equivalent to installed version '", observed_version, "'."),
    expected_version = manifest$package$version, observed_version = observed_version,
    class = "wb_operation_pack_validation_error"
  )
  entry_points <- runtime_identity$entry_points %||% list()
  .wb_operation_pack_assert(is.list(entry_points), "OPERATION_PACK_ENTRY_POINT_INVALID",
                            "Python runtime entry_points must be an array.")
  group <- .wb_operation_pack_python_entry_point_group()
  candidates <- Filter(function(x) {
    is.list(x) && identical(as.character(x$group %||% "")[1], group) &&
      identical(as.character(x$name %||% "")[1], manifest$entry_point)
  }, entry_points)
  matches <- Filter(function(x) {
    owner <- x$distribution %||% distribution
    if (!is.list(owner)) return(FALSE)
    owner_name <- as.character(owner$name %||% "")[1]
    owner_version <- as.character(owner$version %||% "")[1]
    if (!nzchar(owner_name) || !nzchar(owner_version)) return(FALSE)
    identical(.wb_operation_pack_python_normalize_name(owner_name), expected_normalized) &&
      identical(.wb_operation_pack_python_version_key(owner_version),
                .wb_operation_pack_python_version_key(manifest$package$version))
  }, candidates)
  if (!length(matches)) {
    .wb_operation_pack_abort(
      "OPERATION_PACK_ENTRY_POINT_UNAVAILABLE",
      paste0("Distribution '", manifest$package$name, "' does not provide entry point '",
             manifest$entry_point, "' in group '", group, "'."),
      distribution = manifest$package$name, entry_point_group = group,
      entry_point = manifest$entry_point,
      class = "wb_operation_pack_runtime_unavailable"
    )
  }
  if (length(matches) != 1L) {
    .wb_operation_pack_abort(
      "OPERATION_PACK_ENTRY_POINT_AMBIGUOUS",
      paste0("Distribution '", manifest$package$name, "' provides ", length(matches),
             " matching entry points named '", manifest$entry_point, "' in group '", group, "'."),
      distribution = manifest$package$name, entry_point_group = group,
      entry_point = manifest$entry_point, matches = length(matches),
      class = "wb_operation_pack_validation_error"
    )
  }
  match <- matches[[1]]
  value <- .wb_operation_pack_scalar(match$value, "runtime_identity$entry_points$value",
    "^[A-Za-z_][A-Za-z0-9_]*(?:[.][A-Za-z_][A-Za-z0-9_]*)*(?::[A-Za-z_][A-Za-z0-9_]*(?:[.][A-Za-z_][A-Za-z0-9_]*)*)?$")
  match_distribution <- match$distribution %||% distribution
  match_name <- .wb_operation_pack_scalar(match_distribution$name, "entry point distribution name")
  match_version <- .wb_operation_pack_scalar(match_distribution$version, "entry point distribution version")
  .wb_operation_pack_assert(
    identical(.wb_operation_pack_python_normalize_name(match_name), expected_normalized) &&
      identical(.wb_operation_pack_python_version_key(match_version),
                .wb_operation_pack_python_version_key(manifest$package$version)),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "Resolved Python entry point belongs to a different distribution identity.",
    expected_distribution = manifest$package, observed_distribution = match_distribution,
    class = "wb_operation_pack_validation_error"
  )
  list(
    backend = "Python",
    distribution = list(
      declared_name = manifest$package$name,
      normalized_name = expected_normalized,
      version = manifest$package$version,
      metadata_name = observed_name,
      metadata_normalized_name = observed_normalized,
      metadata_version = observed_version
    ),
    entry_point = list(group = group, name = manifest$entry_point, value = value)
  )
}

.wb_operation_pack_require_runtime <- function(manifest, runtime_identity = NULL) {
  if (identical(manifest$backend, "R")) return(invisible(TRUE))
  if (!is.null(runtime_identity)) {
    .wb_operation_pack_python_runtime_identity_validate(manifest, runtime_identity)
  }
  .wb_operation_pack_abort(
    "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    paste0("Python operation pack '", manifest$namespace,
           "' is structurally supported, but Python runtime activation is unavailable in this checkpoint."),
    backend = "Python", namespace = manifest$namespace,
    distribution = manifest$package, entry_point_group = .wb_operation_pack_python_entry_point_group(),
    entry_point = manifest$entry_point,
    class = "wb_operation_pack_runtime_unavailable"
  )
}

.wb_operation_pack_distribution_key <- function(identity) {
  backend <- as.character(identity$backend %||% "")[1]
  name <- as.character(identity$package$name %||% "")[1]
  if (identical(backend, "Python")) {
    name <- .wb_operation_pack_python_normalize_name(name)
  }
  paste(backend, name, sep = ":")
}

#' Structurally Validate an Operation-Pack Manifest
#'
#' This backend-neutral, non-activating boundary validates a parsed manifest or
#' JSON file without loading package code, discovering installed distributions,
#' or mutating a bundle. For Python, optional runtime metadata must already have
#' been obtained for the explicitly named distribution; this function never
#' scans the environment or imports the entry-point target. Structural and
#' runtime conformance are not scientific validation or host sandboxing.
#'
#' @param manifest Parsed manifest list or path to an operation-pack JSON file.
#' @param runtime_identity Optional backend runtime/distribution metadata. The
#'   v1 R checkpoint accepts this only for structurally checking Python
#'   distribution and entry-point identity; it does not activate Python.
#' @return A machine-readable structural conformance report with canonical
#'   manifest, operation definitions, and pack identity.
#' @export
wb_operation_pack_manifest_validate <- function(manifest, runtime_identity = NULL) {
  input <- .wb_operation_pack_manifest_input_any(manifest)
  if (identical(input$schema_version, "scworkbench.operation_pack.v4")) {
    .wb_operation_pack_assert(is.null(runtime_identity), "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      "ABI4 structural validation accepts no caller runtime claims.")
    normalized <- .wb_operation_pack_v4_normalize(input)
    source_sha <- attr(input, "operation_pack_v4_source_sha256", exact = TRUE) %||%
      .wb_operation_pack_sha256(normalized)
    content <- .wb_operation_pack_v2_id("scworkbench.operation_pack.content.v1",
      list(structural_manifest_only = TRUE, manifest_source_sha256 = source_sha))
    return(structure(list(schema_version = "scworkbench.operation_pack.manifest_conformance.v4",
      ok = TRUE, activated = FALSE, structural_only = TRUE, backend = normalized$backend,
      identity = .wb_operation_pack_v4_identity(normalized, source_sha, content), manifest = normalized,
      claims = list(structurally_validated = TRUE, runtime_activated = FALSE,
        scientifically_validated = FALSE, host_sandboxed = FALSE, bundle_mutated = FALSE)),
      class = c("wb_operation_pack_manifest_conformance_v4", "wb_operation_pack_manifest_conformance", "list")))
  }
  if (identical(as.character(input$schema_version %||% "")[1], "scworkbench.operation_pack.v3")) {
    .wb_operation_pack_assert(is.null(runtime_identity), "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      "ABI v3 structural validation derives authentication at activation; caller runtime claims are not accepted.",
      class = "wb_operation_pack_v3_error")
    normalized <- .wb_operation_pack_v3_normalize(input)
    source_sha <- attr(input, "operation_pack_v3_source_sha256", exact = TRUE) %||%
      .wb_operation_pack_sha256(normalized)
    content <- .wb_operation_pack_v3_id("scworkbench.operation_pack.content.v1",
      list(structural_manifest_only = TRUE, manifest_source_sha256 = source_sha))
    identity <- .wb_operation_pack_v3_identity(normalized, source_sha, content)
    return(structure(list(
      schema_version = "scworkbench.operation_pack.manifest_conformance.v3",
      ok = TRUE, activated = FALSE, structural_only = TRUE,
      backend = normalized$backend, identity = identity, manifest = normalized,
      claims = list(structurally_validated = TRUE, runtime_activated = FALSE,
        scientifically_validated = FALSE, host_sandboxed = FALSE,
        bundle_mutated = FALSE)),
      class = c("wb_operation_pack_manifest_conformance_v3",
        "wb_operation_pack_manifest_conformance", "list")))
  }
  if (identical(as.character(input$schema_version %||% "")[1], "scworkbench.operation_pack.v2")) {
    .wb_operation_pack_assert(is.null(runtime_identity), "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      "ABI v2 structural validation derives authentication at activation; caller runtime claims are not accepted.",
      class = "wb_operation_pack_v2_error")
    return(.wb_operation_pack_v2_manifest_conformance(input))
  }
  validated <- .wb_operation_pack_validate_manifest(input)
  observed_runtime <- NULL
  if (!is.null(runtime_identity)) {
    .wb_operation_pack_assert(identical(validated$backend, "Python"),
      "OPERATION_PACK_BACKEND_MISMATCH",
      "runtime_identity is accepted only for a Python manifest at this checkpoint.",
      backend = validated$backend, class = "wb_operation_pack_validation_error")
    observed_runtime <- .wb_operation_pack_python_runtime_identity_validate(validated, runtime_identity)
  }
  identity <- .wb_operation_pack_identity(validated)
  structure(list(
    schema_version = "scworkbench.operation_pack.manifest_conformance.v1",
    ok = TRUE,
    activated = FALSE,
    structural_only = is.null(observed_runtime),
    backend = validated$backend,
    identity = identity,
    manifest = validated,
    runtime_identity = observed_runtime,
    entry_point_contract = if (identical(validated$backend, "Python")) list(
      group = .wb_operation_pack_python_entry_point_group(),
      name = validated$entry_point,
      target_source = "installed_distribution_metadata"
    ) else list(name = validated$entry_point, target_source = "R_namespace_export"),
    claims = list(structurally_validated = TRUE, runtime_activated = FALSE,
                  scientifically_validated = FALSE, host_sandboxed = FALSE,
                  bundle_mutated = FALSE)
  ), class = c("wb_operation_pack_manifest_conformance", "list"))
}

#' Explicitly Activate an Operation Pack From Its Manifest
#'
#' This is the backend-neutral activation dispatcher. For an R manifest it
#' authenticates the supplied definition against the installed R package and
#' delegates to [wb_operation_pack_load()]. For a Python manifest it asks the
#' explicitly configured PyBench interpreter to discover the exact declared
#' distribution and standard entry point, independently audits all identities,
#' and activates an audited subprocess adapter. It never scans unrelated
#' distributions or executes an arbitrary import string.
#'
#' @param manifest Parsed manifest list or path to an operation-pack JSON file.
#'   Python activation requires the original installed-distribution manifest
#'   path; a parsed list cannot authenticate installed package identity.
#' @param runtime_identity Reserved for backend-neutral structural conformance.
#'   Activation does not accept caller-supplied runtime claims; pass such claims
#'   to [wb_operation_pack_manifest_validate()] instead.
#' @param lib.loc Optional R library location used only for backend `R`.
#' @param python Exact PyBench Python interpreter used only for backend
#'   `Python`. When omitted, the normal PyBench interpreter configuration is
#'   used (`SCWORKBENCH_PYBENCH_PYTHON`, then the R option).
#' @param timeout_seconds Positive discovery/execution subprocess timeout used
#'   only for backend `Python`.
#' @return The activated pack inspection record invisibly.
#' @export
wb_operation_pack_activate <- function(manifest, runtime_identity = NULL, lib.loc = NULL,
                                       python = NULL,
                                       timeout_seconds = getOption(
                                         "scworkbench.operation_pack_python_timeout_seconds", 300)) {
  supplied_manifest_path <- if (is.character(manifest) && length(manifest) == 1L &&
      !is.na(manifest) && file.exists(manifest)) {
    normalizePath(manifest, winslash = "/", mustWork = TRUE)
  } else NULL
  input <- .wb_operation_pack_manifest_input_any(manifest)
  if (as.character(input$schema_version %||% "")[1] %in%
      c("scworkbench.operation_pack.v3", "scworkbench.operation_pack.v4")) {
    abi <- if (identical(input$schema_version, "scworkbench.operation_pack.v4")) "4" else "3"
    .wb_operation_pack_assert(is.null(runtime_identity),
      "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      "ABI v3 activation derives runtime identity and does not accept caller claims.",
      class = "wb_operation_pack_v3_error")
    .wb_operation_pack_assert(!is.null(supplied_manifest_path),
      "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED",
      "ABI v3 activation requires original installed manifest bytes.",
      class = "wb_operation_pack_identity_error")
    validated_v3 <- (if (abi == "4") .wb_operation_pack_v4_normalize else .wb_operation_pack_v3_normalize)(input)
    backend <- as.character(validated_v3$backend)[1]
    if (identical(backend, "R")) {
      .wb_operation_pack_assert(is.null(python), "OPERATION_PACK_BACKEND_MISMATCH",
        "python applies only to backend 'Python'.",
        class = "wb_operation_pack_v3_error")
      package <- as.character(validated_v3$package$name)[1]
      installed_manifest <- .wb_operation_pack_v3_manifest_path(package, lib.loc)
      .wb_operation_pack_assert(identical(normalizePath(supplied_manifest_path,
        winslash = "/", mustWork = TRUE), installed_manifest),
        "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED",
        "ABI v3 activation must authenticate the original installed manifest path.",
        class = "wb_operation_pack_identity_error")
      registration <- .wb_operation_pack_v3_invoke(package, lib.loc, abi = abi)
    } else if (identical(backend, "Python")) {
      .wb_operation_pack_assert(is.null(lib.loc), "OPERATION_PACK_BACKEND_MISMATCH",
        "lib.loc applies only to backend 'R'.",
        class = "wb_operation_pack_v3_error")
      python <- .wb_operation_pack_python_binary(python)
      discovery <- .wb_operation_pack_v3_python_discover(supplied_manifest_path,
        validated_v3, python, timeout_seconds, activate = TRUE, abi = abi)
      registration <- .wb_operation_pack_v3_python_registration(validated_v3,
        discovery, supplied_manifest_path, python, timeout_seconds, abi = abi)
    } else .wb_operation_pack_v3_error("OPERATION_PACK_BACKEND_MISMATCH",
      paste0("Unsupported ABI v3 backend: ", backend), "authentication")
    return(.wb_operation_pack_publish(registration))
  }
  if (identical(as.character(input$schema_version %||% "")[1], "scworkbench.operation_pack.v2")) {
    .wb_operation_pack_assert(is.null(runtime_identity),
      "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      "ABI v2 activation derives runtime identity and does not accept caller claims.",
      class = "wb_operation_pack_v2_error")
    .wb_operation_pack_assert(!is.null(supplied_manifest_path), "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED",
      "ABI v2 activation requires original installed manifest bytes.",
      class = "wb_operation_pack_identity_error")
    validated_v2 <- .wb_operation_pack_v2_normalize(input)
    backend <- as.character(validated_v2$backend)[1]
    if (identical(backend, "R")) {
      .wb_operation_pack_assert(is.null(python), "OPERATION_PACK_BACKEND_MISMATCH",
        "python applies only to backend 'Python'.", class = "wb_operation_pack_v2_error")
      package <- as.character(validated_v2$package$name)[1]
      installed_manifest <- .wb_operation_pack_v2_manifest_path(package, lib.loc)
      .wb_operation_pack_assert(identical(normalizePath(supplied_manifest_path, winslash = "/", mustWork = TRUE),
        installed_manifest), "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED",
        "ABI v2 activation must authenticate the original installed manifest path.",
        class = "wb_operation_pack_identity_error")
      registration <- .wb_operation_pack_v2_invoke(package, lib.loc)
    } else if (identical(backend, "Python")) {
      .wb_operation_pack_assert(is.null(lib.loc), "OPERATION_PACK_BACKEND_MISMATCH",
        "lib.loc applies only to backend 'R'.", class = "wb_operation_pack_v2_error")
      python <- .wb_operation_pack_python_binary(python)
      discovery <- .wb_operation_pack_v2_python_discover(supplied_manifest_path,
        validated_v2, python, timeout_seconds, activate = TRUE)
      registration <- .wb_operation_pack_v2_python_registration(validated_v2,
        discovery, supplied_manifest_path, python, timeout_seconds)
    } else {
      .wb_operation_pack_v2_error("OPERATION_PACK_BACKEND_MISMATCH",
        paste0("Unsupported ABI v2 backend: ", backend), "authentication")
    }
    return(.wb_operation_pack_publish(registration))
  }
  validated <- .wb_operation_pack_validate_manifest(input)
  if (identical(validated$backend, "Python")) {
    .wb_operation_pack_assert(is.null(runtime_identity), "OPERATION_PACK_RUNTIME_IDENTITY_UNTRUSTED",
      paste0("Python activation discovers runtime identity from the explicitly configured ",
             "interpreter; caller-supplied runtime_identity is accepted only by ",
             "wb_operation_pack_manifest_validate()."),
      backend = "Python", class = "wb_operation_pack_validation_error")
    .wb_operation_pack_assert(is.null(lib.loc), "OPERATION_PACK_BACKEND_MISMATCH",
      "lib.loc applies only to installed R operation packs.", backend = "Python",
      class = "wb_operation_pack_validation_error")
    .wb_operation_pack_assert(!is.null(supplied_manifest_path),
      "OPERATION_PACK_MANIFEST_SOURCE_REQUIRED",
      paste0("Python activation requires the original installed-distribution manifest path; ",
             "a parsed or reserialized manifest cannot authenticate package identity."),
      backend = "Python", class = "wb_operation_pack_identity_error")
    python <- .wb_operation_pack_python_binary(python)
    identity <- .wb_operation_pack_identity(validated)
    discovery <- .wb_operation_pack_python_discover(
      supplied_manifest_path, validated, identity, python, timeout_seconds)
    registration <- .wb_operation_pack_python_registration(
      validated, identity, discovery, supplied_manifest_path, python, timeout_seconds)
    result <- .wb_operation_pack_publish(registration)
    return(result)
  }
  .wb_operation_pack_assert(is.null(runtime_identity), "OPERATION_PACK_BACKEND_MISMATCH",
    "runtime_identity must not be supplied when activating an installed R package.",
    backend = "R", class = "wb_operation_pack_validation_error")
  .wb_operation_pack_assert(is.null(python), "OPERATION_PACK_BACKEND_MISMATCH",
    "python applies only to backend 'Python'.", backend = "R",
    class = "wb_operation_pack_validation_error")
  package <- validated$package$name
  installed_path <- .wb_operation_pack_manifest_path(package, lib.loc = lib.loc)
  description <- utils::packageDescription(package, lib.loc = lib.loc)
  installed <- .wb_operation_pack_validate_manifest(
    .wb_operation_pack_read_manifest(installed_path), package = package,
    package_description = description, expected_backend = "R"
  )
  expected_identity <- .wb_operation_pack_identity(validated)
  installed_identity <- .wb_operation_pack_identity(installed)
  .wb_operation_pack_assert(
    identical(expected_identity$pack_sha256, installed_identity$pack_sha256),
    "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
    paste0("Supplied R manifest identity does not match installed package '", package, "'."),
    expected_pack_sha256 = expected_identity$pack_sha256,
    installed_pack_sha256 = installed_identity$pack_sha256,
    class = "wb_operation_pack_validation_error"
  )
  wb_operation_pack_load(package, lib.loc = lib.loc)
}

#' Register an R Operation-Pack Definition
#'
#' This is the public pack-author boundary called by a package's exported
#' manifest entry point. It validates and returns a registration object; it
#' does not activate operations by itself. Users activate an installed package
#' explicitly with [wb_operation_pack_load()]. Pack code is trusted executable
#' R code, not a host sandbox.
#'
#' @param manifest Path to the installed canonical `operation-pack.json`.
#' @param operations Named list of runner functions. Names must exactly match
#'   the fully qualified operation names declared by the manifest. Every runner
#'   has formals `bundle, resolved, effective_cells, inputs, ...`, consumes only
#'   sanctioned arguments, and returns `list(outputs = ..., params = ...)`.
#' @return A validated `wb_operation_pack_registration` object.
#' @export
wb_operation_pack_register <- function(manifest, operations) {
  context <- .wb_operation_pack_registry$registration_context
  .wb_operation_pack_assert(is.environment(context), "OPERATION_PACK_REGISTRATION_CONTEXT_REQUIRED",
    "wb_operation_pack_register() may only be called by an entry point invoked through wb_operation_pack_validate() or wb_operation_pack_load().")
  path <- normalizePath(.wb_operation_pack_scalar(manifest, "manifest"), winslash = "/", mustWork = TRUE)
  .wb_operation_pack_assert(identical(path, context$manifest_path), "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
                            "Entry point attempted to register a manifest other than the installed manifest.")
  if (identical(as.character(context$abi %||% "1")[1], "4")) {
    validated <- .wb_operation_pack_v4_normalize(.wb_operation_pack_v4_read_manifest(path),
      package = context$package, package_description = context$package_description)
    registration <- .wb_operation_pack_v3_registration(validated, operations,
      package_description = context$package_description, installed_path = context$installed_path,
      manifest_path = path, abi = "4")
  } else if (identical(as.character(context$abi %||% "1")[1], "3")) {
    validated <- .wb_operation_pack_v3_normalize(.wb_operation_pack_v3_read_manifest(path),
      package = context$package, package_description = context$package_description)
    registration <- .wb_operation_pack_v3_registration(validated, operations,
      package_description = context$package_description,
      installed_path = context$installed_path, manifest_path = path)
  } else if (identical(as.character(context$abi %||% "1")[1], "2")) {
    validated <- .wb_operation_pack_v2_normalize(.wb_operation_pack_v2_read_manifest(path),
      package = context$package, package_description = context$package_description)
    registration <- .wb_operation_pack_v2_registration(validated, operations,
      package_description = context$package_description, installed_path = context$installed_path,
      manifest_path = path)
  } else {
    validated <- .wb_operation_pack_validate_manifest(.wb_operation_pack_read_manifest(path),
      package = context$package, package_description = context$package_description,
      expected_backend = "R")
    registration <- .wb_operation_pack_registration(validated, operations,
      package_description = context$package_description, installed_path = context$installed_path)
  }
  .wb_operation_pack_assert(is.null(context$result), "OPERATION_PACK_ENTRY_POINT_INVALID",
                            "Operation-pack entry point called wb_operation_pack_register() more than once.")
  context$result <- registration
  registration
}

.wb_operation_pack_invoke <- function(package, lib.loc = NULL) {
  package <- .wb_operation_pack_scalar(package, "package", "^[A-Za-z][A-Za-z0-9.]*$")
  manifest_path <- .wb_operation_pack_manifest_path(package, lib.loc = lib.loc)
  probe <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  if (identical(probe$schema_version, "scworkbench.operation_pack.v4"))
    return(.wb_operation_pack_v3_invoke(package, lib.loc, abi = "4"))
  if (identical(as.character(probe$schema_version %||% "")[1], "scworkbench.operation_pack.v3")) {
    return(.wb_operation_pack_v3_invoke(package, lib.loc = lib.loc))
  }
  if (identical(as.character(probe$schema_version %||% "")[1], "scworkbench.operation_pack.v2")) {
    return(.wb_operation_pack_v2_invoke(package, lib.loc = lib.loc))
  }
  description <- utils::packageDescription(package, lib.loc = lib.loc)
  manifest <- .wb_operation_pack_validate_manifest(.wb_operation_pack_read_manifest(manifest_path),
    package = package, package_description = description, expected_backend = "R")
  .wb_operation_pack_assert(requireNamespace(package, quietly = TRUE, lib.loc = lib.loc),
                            "OPERATION_PACK_PACKAGE_UNAVAILABLE",
                            paste0("Installed package '", package, "' could not be loaded."), package = package)
  exports <- getNamespaceExports(package)
  .wb_operation_pack_assert(manifest$entry_point %in% exports, "OPERATION_PACK_ENTRY_POINT_INVALID",
    paste0("Manifest entry point '", manifest$entry_point, "' is not exported by package '", package, "'."),
    package = package, entry_point = manifest$entry_point)
  entry <- getExportedValue(package, manifest$entry_point)
  .wb_operation_pack_assert(is.function(entry), "OPERATION_PACK_ENTRY_POINT_INVALID",
                            paste0("Exported entry point '", manifest$entry_point, "' is not a function."),
                            package = package, entry_point = manifest$entry_point)
  .wb_operation_pack_assert(length(formals(entry)) == 0L, "OPERATION_PACK_ENTRY_POINT_INVALID",
                            paste0("Exported entry point '", manifest$entry_point, "' must have no formal arguments."),
                            package = package, entry_point = manifest$entry_point)
  context <- new.env(parent = emptyenv())
  context$package <- package
  context$manifest_path <- manifest_path
  context$package_description <- description
  context$installed_path <- dirname(dirname(manifest_path))
  context$result <- NULL
  .wb_operation_pack_registry$registration_context <- context
  on.exit({ .wb_operation_pack_registry$registration_context <- NULL }, add = TRUE)
  returned <- tryCatch(entry(), error = function(e) {
    if (inherits(e, "wb_operation_pack_error")) stop(e)
    .wb_operation_pack_abort("OPERATION_PACK_ENTRY_POINT_FAILED",
      paste0("Operation-pack entry point failed: ", conditionMessage(e)), package = package,
      entry_point = manifest$entry_point, class = "wb_operation_pack_entry_point_error")
  })
  .wb_operation_pack_assert(inherits(returned, "wb_operation_pack_registration") &&
    inherits(context$result, "wb_operation_pack_registration") && identical(returned, context$result),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "Operation-pack entry point must return the object from exactly one wb_operation_pack_register() call.",
    package = package, entry_point = manifest$entry_point)
  returned
}

#' Validate an Installed R Operation Pack Without Activating It
#'
#' Validation is read-only with respect to bundles and the process-local
#' operation registry, but it loads and executes the package's declared entry
#' point. Treat it as an explicit trust decision. Passing conformance means the
#' pack matches engine contracts; it is not scientific validation of a method.
#'
#' @param package Installed R package name.
#' @param lib.loc Optional R library location.
#' @return A machine-readable conformance report containing canonical pack,
#'   manifest, and operation-definition identities.
#' @export
wb_operation_pack_validate <- function(package, lib.loc = NULL) {
  registration <- .wb_operation_pack_invoke(package, lib.loc = lib.loc)
  if (inherits(registration, "wb_operation_pack_registration_v3")) {
    abi <- registration$protocol_version
    return(structure(list(
      schema_version = paste0("scworkbench.operation_pack.conformance.v", abi), ok = TRUE,
      activated = FALSE, identity = registration$identity,
      operations = lapply(registration$manifest$operations, function(x) list(
        op_name = x$qualified_name,
        definition_sha256 = registration$identity$operation_definition_sha256[[x$qualified_name]],
        consumes = x$inputs, produces = x$outputs,
        promotable = names(x$promotion_closure))),
      claims = list(engine_compatible = TRUE, scientifically_validated = FALSE,
        host_sandboxed = FALSE, bundle_mutated = FALSE)),
      class = c(paste0("wb_operation_pack_conformance_v", abi),
        "wb_operation_pack_conformance", "list")))
  }
  if (inherits(registration, "wb_operation_pack_registration_v2")) {
    return(structure(list(
      schema_version = "scworkbench.operation_pack.conformance.v2", ok = TRUE,
      activated = FALSE, identity = registration$identity,
      operations = lapply(registration$manifest$operations, function(x) list(
        op_name = x$qualified_name,
        definition_sha256 = registration$identity$operation_definition_sha256[[x$qualified_name]],
        consumes = x$inputs, produces = x$outputs,
        promotable = names(x$promotion_closure))),
      claims = list(engine_compatible = TRUE, scientifically_validated = FALSE,
        host_sandboxed = FALSE, bundle_mutated = FALSE)
    ), class = c("wb_operation_pack_conformance_v2", "wb_operation_pack_conformance", "list")))
  }
  structure(list(
    schema_version = "scworkbench.operation_pack.conformance.v1",
    ok = TRUE,
    activated = FALSE,
    identity = registration$identity,
    operations = lapply(registration$manifest$operations, function(x) list(
      op_name = x$name, definition_sha256 = x$definition_sha256,
      consumes = x$requires, produces = x$produces, promotable = x$promotable
    )),
    claims = list(engine_compatible = TRUE, scientifically_validated = FALSE,
                  host_sandboxed = FALSE, bundle_mutated = FALSE)
  ), class = c("wb_operation_pack_conformance", "list"))
}

.wb_operation_pack_runner <- function(op_name, runner) {
  force(op_name); force(runner)
  function(bundle, resolved, effective_cells, inputs, ...) {
    rec <- .wb_operation_pack_registry$operations[[op_name]]
    .wb_operation_pack_assert(!is.null(rec), "OPERATION_PACK_REQUIRED",
      paste0("Operation pack required for '", op_name, "' is not loaded."), operation = op_name,
      class = "wb_operation_pack_unavailable")
    rec$execution_depth <- as.integer(rec$execution_depth %||% 0L) + 1L
    .wb_operation_pack_registry$operations[[op_name]] <- rec
    on.exit({
      current <- .wb_operation_pack_registry$operations[[op_name]]
      if (!is.null(current)) {
        current$execution_depth <- max(0L, as.integer(current$execution_depth %||% 1L) - 1L)
        current$used <- TRUE
        .wb_operation_pack_registry$operations[[op_name]] <- current
        pack <- .wb_operation_pack_registry$packs[[current$namespace]]
        if (!is.null(pack)) {
          pack$used <- TRUE
          .wb_operation_pack_registry$packs[[current$namespace]] <- pack
        }
      }
    }, add = TRUE)
    runner(bundle = bundle, resolved = resolved, effective_cells = effective_cells, inputs = inputs, ...)
  }
}

.wb_operation_pack_publish <- function(registration) {
  identity <- registration$identity
  namespace <- identity$namespace
  op_names <- names(identity$operation_definition_sha256)
  core_names <- names(.wb_op_catalog())
  existing <- .wb_operation_pack_registry$packs[[namespace]]
  if (!is.null(existing) && identical(
      as.character(existing$identity$pack_identity$sha256 %||% existing$identity$pack_sha256)[1],
      as.character(identity$pack_identity$sha256 %||% identity$pack_sha256)[1])) {
    return(invisible(wb_operation_pack_inspect(namespace)))
  }
  .wb_operation_pack_assert(!namespace %in% names(.wb_operation_pack_registry$packs),
    "OPERATION_PACK_NAMESPACE_DUPLICATE", paste0("Operation-pack namespace '", namespace, "' is already loaded."),
    namespace = namespace)
  loaded_packages <- vapply(.wb_operation_pack_registry$packs,
    function(x) .wb_operation_pack_distribution_key(x$identity), character(1))
  .wb_operation_pack_assert(!.wb_operation_pack_distribution_key(identity) %in% loaded_packages,
    "OPERATION_PACK_PACKAGE_DUPLICATE", paste0("Operation-pack package '", identity$package$name, "' is already loaded."),
    package = identity$package$name)
  .wb_operation_pack_assert(!length(intersect(op_names, core_names)), "OPERATION_PACK_CORE_SHADOW",
                            "Operation pack attempts to shadow a core operation.")
  .wb_operation_pack_assert(!length(intersect(op_names, names(.wb_operation_pack_registry$operations))),
    "OPERATION_PACK_OPERATION_DUPLICATE", "Operation pack duplicates an already loaded operation.")

  operations <- list()
  definitions <- if (inherits(registration, "wb_operation_pack_registration_v2")) {
    registration$definitions
  } else stats::setNames(registration$manifest$operations, op_names)
  for (op_name in sort(op_names, method = "radix")) {
    definition <- definitions[[op_name]]
    raw_runner <- registration$runners[[op_name]]
    definition$runner <- if (inherits(registration, "wb_operation_pack_registration_v3")) {
      .wb_operation_pack_runner(op_name, .wb_operation_pack_v3_runner(op_name,
        abi = registration$protocol_version))
    } else if (inherits(registration, "wb_operation_pack_registration_v2")) {
      .wb_operation_pack_runner(op_name, .wb_operation_pack_v2_runner(op_name))
    } else .wb_operation_pack_runner(op_name, raw_runner)
    definition$source_pack <- identity
    operations[[op_name]] <- list(namespace = namespace, definition = definition,
                                  execution_depth = 0L, used = FALSE)
  }
  pack <- list(identity = identity, manifest = registration$manifest,
               runtime_attestation = registration$runtime_attestation,
               runtime_config = registration$runtime_config %||% NULL,
               protocol_version = registration$protocol_version %||% "1",
               registration = if (inherits(registration, "wb_operation_pack_registration_v2")) registration else NULL,
               operation_names = sort(op_names, method = "radix"), used = FALSE)
  preimage_packs <- .wb_operation_pack_registry$packs
  preimage_operations <- .wb_operation_pack_registry$operations
  published <- FALSE
  on.exit(if (!published) {
    .wb_operation_pack_registry$packs <- preimage_packs
    .wb_operation_pack_registry$operations <- preimage_operations
  }, add = TRUE)
  tryCatch({
    .wb_operation_pack_v2_fault("catalog_before_pack", namespace = namespace)
    .wb_operation_pack_registry$packs[[namespace]] <- pack
    .wb_operation_pack_v2_fault("catalog_pack_installed", namespace = namespace)
    for (op_name in names(operations)) {
      .wb_operation_pack_registry$operations[[op_name]] <- operations[[op_name]]
      .wb_operation_pack_v2_fault("catalog_operation_installed", namespace = namespace,
        operation = op_name)
    }
    .wb_operation_pack_v2_fault("catalog_before_commit", namespace = namespace)
  }, error = function(error) {
    .wb_operation_pack_registry$packs <- preimage_packs
    .wb_operation_pack_registry$operations <- preimage_operations
    if (inherits(error, "wb_operation_pack_error")) stop(error)
    .wb_operation_pack_v2_error("OPERATION_PACK_CATALOG_PUBLICATION_FAILED",
      paste0("Atomic operation-pack catalog publication failed: ", conditionMessage(error)),
      "catalog_publication")
  })
  published <- TRUE
  invisible(wb_operation_pack_inspect(namespace))
}

#' Explicitly Load and Activate an Installed R Operation Pack
#'
#' Installing a package is inert. This function is the explicit process-local
#' trust and activation boundary; no installed-package scan is performed.
#'
#' @param package Installed R package name.
#' @param lib.loc Optional R library location.
#' @return The inspected activated pack record, invisibly.
#' @export
wb_operation_pack_load <- function(package, lib.loc = NULL) {
  registration <- .wb_operation_pack_invoke(package, lib.loc = lib.loc)
  .wb_operation_pack_publish(registration)
}

#' List Explicitly Loaded Operation Packs
#'
#' @return A data frame with process-local pack identities and usage state.
#' @export
wb_operation_packs <- function() {
  packs <- .wb_operation_pack_registry$packs
  if (!length(packs)) return(data.frame(
    namespace = character(), package = character(), version = character(), backend = character(),
    manifest_sha256 = character(), pack_sha256 = character(), operation_count = integer(), used = logical(),
    stringsAsFactors = FALSE))
  namespaces <- sort(names(packs), method = "radix")
  do.call(rbind, lapply(namespaces, function(namespace) {
    x <- packs[[namespace]]
    data.frame(namespace = namespace, package = x$identity$package$name,
      version = x$identity$package$version, backend = x$identity$backend,
      manifest_sha256 = x$identity$manifest_sha256, pack_sha256 = x$identity$pack_sha256,
      operation_count = length(x$operation_names), used = isTRUE(x$used), stringsAsFactors = FALSE)
  }))
}

#' Inspect One Loaded Operation Pack
#'
#' @param pack Loaded namespace or package name.
#' @return A JSON-friendly record containing exact identity, canonical manifest,
#'   operation definitions, runtime attestation, and usage state. Runner
#'   functions are deliberately omitted.
#' @export
wb_operation_pack_inspect <- function(pack) {
  key <- .wb_operation_pack_scalar(pack, "pack")
  packs <- .wb_operation_pack_registry$packs
  if (!key %in% names(packs)) {
    hits <- names(packs)[vapply(packs, function(x) identical(x$identity$package$name, key), logical(1))]
    .wb_operation_pack_assert(length(hits) == 1L, "OPERATION_PACK_NOT_LOADED",
                              paste0("Operation pack '", key, "' is not loaded."), pack = key,
                              class = "wb_operation_pack_unavailable")
    key <- hits[[1]]
  }
  x <- packs[[key]]
  definitions <- stats::setNames(x$manifest$operations, vapply(x$manifest$operations, function(z) z$name, character(1)))
  abi <- as.character(x$identity$pack_abi_version %||% "1")[1]
  structure(list(schema_version = paste0("scworkbench.operation_pack.inspection.v", abi),
    identity = x$identity, manifest = x$manifest, operations = definitions,
    runtime_attestation = x$runtime_attestation, used = isTRUE(x$used)),
    class = c("wb_operation_pack", "list"))
}

#' Safely Unload a Process-Local Operation Pack
#'
#' A pack can be unloaded only before any contributed operation has executed in
#' the process. This conservative rule ensures no ephemeral or durable staged
#' session can lose the contract needed for promotion. Package namespaces may
#' remain loaded by R; only scworkbench activation is removed.
#'
#' @param pack Loaded namespace or package name.
#' @return Invisibly `TRUE` on success.
#' @export
wb_operation_pack_unload <- function(pack) {
  inspected <- wb_operation_pack_inspect(pack)
  namespace <- inspected$identity$namespace
  current <- .wb_operation_pack_registry$packs[[namespace]]
  active <- any(vapply(current$operation_names, function(op) {
    x <- .wb_operation_pack_registry$operations[[op]]
    as.integer(x$execution_depth %||% 0L) > 0L
  }, logical(1)))
  .wb_operation_pack_assert(!active && !isTRUE(current$used), "OPERATION_PACK_IN_USE",
    paste0("Operation pack '", namespace, "' cannot be unloaded after execution because active or staged session state may depend on it."),
    namespace = namespace, class = "wb_operation_pack_in_use")
  for (op in current$operation_names) .wb_operation_pack_registry$operations[[op]] <- NULL
  .wb_operation_pack_registry$packs[[namespace]] <- NULL
  invisible(TRUE)
}

.wb_operation_pack_definitions <- function() {
  records <- .wb_operation_pack_registry$operations
  if (!length(records)) return(list())
  names_sorted <- sort(names(records), method = "radix")
  stats::setNames(lapply(names_sorted, function(name) records[[name]]$definition), names_sorted)
}

.wb_operation_catalog <- function() {
  core <- .wb_op_catalog()
  external <- .wb_operation_pack_definitions()
  if (!length(external)) return(core)
  c(core, external)
}

.wb_operation_pack_identity_for_op <- function(op_name) {
  rec <- .wb_operation_pack_registry$operations[[as.character(op_name)[1]]]
  if (is.null(rec)) return(NULL)
  rec$definition$source_pack %||% NULL
}

#' Canonical Identity of the Runtime Operation Catalog
#'
#' The identity covers core operation interfaces plus explicitly loaded pack
#' identities and is independent of pack load order and process identifiers.
#'
#' @return A list containing the identity scheme, SHA-256, core operation count,
#'   and sorted loaded pack identities.
#' @export
wb_operation_catalog_identity <- function() {
  catalog <- .wb_operation_catalog()
  definitions <- lapply(names(catalog), function(name) {
    x <- catalog[[name]]
    list(op_name = name, title = x$title %||% "", description = x$description %||% "",
      intent = x$intent %||% character(), requires = x$requires %||% list(),
      optional_requires = x$optional_requires %||% list(), inputs = x$inputs %||% list(),
      params = x$params %||% list(), produces = x$produces %||% list(),
      promotable = x$promotable %||% character(), replay_equivalence = x$replay_equivalence %||% list(),
      source_pack = x$source_pack %||% NULL)
  })
  names(definitions) <- names(catalog)
  packs <- .wb_operation_pack_registry$packs
  pack_names <- if (length(packs)) sort(names(packs), method = "radix") else character(0)
  pack_ids <- lapply(pack_names, function(namespace) packs[[namespace]]$identity)
  names(pack_ids) <- pack_names
  payload <- list(protocol_version = .wb_operation_pack_protocol_version(),
                  definitions = definitions, loaded_packs = pack_ids)
  list(scheme = "scworkbench-operation-catalog-v1",
       sha256 = .wb_operation_catalog_sha256_v1(payload),
       core_operation_count = length(.wb_op_catalog()), loaded_packs = pack_ids)
}
