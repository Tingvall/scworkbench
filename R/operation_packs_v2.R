# Operation-pack ABI v2 admission and R reference adapter.
#
# ABI v1 remains implemented in operation_packs.R.  The two paths share only
# canonical JSON v1 bytes and the process-local registry publication primitive.

.wb_operation_pack_v2_manifest_schema <- function() {
  path <- system.file("protocol", "operation-pack-v2.schema.json", package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol", "operation-pack-v2.schema.json")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v2_transition_schema <- function(kind = c("request", "receipt")) {
  kind <- match.arg(kind)
  filename <- paste0("operation-pack-transition-", kind, "-v2.schema.json")
  path <- system.file("protocol", filename, package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol", filename)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v2_error <- function(code, message, phase, ...) {
  .wb_operation_pack_abort(code, message, phase = phase, ...,
    class = "wb_operation_pack_v2_error")
}

.wb_operation_pack_v2_id <- function(scheme, value, scope = NULL) {
  out <- list(scheme = scheme)
  if (!is.null(scope)) out$scope <- scope
  out$sha256 <- .wb_operation_pack_sha256(value)
  out
}

.wb_operation_pack_v2_file_sha256 <- function(path) {
  .wb_require_pkg("digest", "operation-pack v2 file identity")
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

# A small strict JSON grammar pass is intentionally performed before jsonlite.
# It rejects duplicate raw object keys, trailing content, and malformed values
# without ever constructing a last-key-wins object.
.wb_operation_pack_v2_assert_strict_json <- function(text) {
  text <- enc2utf8(as.character(text)[1])
  .wb_operation_pack_assert(!is.na(text) && !is.na(iconv(text, from = "UTF-8",
    to = "UTF-8", sub = NA_character_)), "OPERATION_PACK_MANIFEST_PARSE_INVALID",
    "Manifest source is not valid UTF-8.", class = "wb_operation_pack_v2_error")
  # substr() positions are Unicode characters, not UTF-8 byte offsets. Using
  # a byte count here incorrectly reports trailing content for non-ASCII JSON.
  n <- nchar(text, type = "chars")
  byte <- function(i) if (i > n) "" else substr(text, i, i)
  skip <- function(i) {
    while (i <= n && byte(i) %in% c(" ", "\t", "\r", "\n")) i <- i + 1L
    i
  }
  string_end <- function(i) {
    if (!identical(byte(i), '"')) stop("expected string")
    j <- i + 1L
    while (j <= n) {
      if (identical(byte(j), '"')) return(j + 1L)
      if (identical(byte(j), "\\")) {
        j <- j + 1L
        if (j > n) stop("unterminated escape")
        if (identical(byte(j), "u")) {
          if (j + 4L > n || !grepl("^[0-9A-Fa-f]{4}$", substr(text, j + 1L, j + 4L))) {
            stop("invalid unicode escape")
          }
          code <- strtoi(substr(text, j + 1L, j + 4L), 16L)
          if (code >= 0xD800 && code <= 0xDBFF) {
            if (j + 10L > n || substr(text, j + 5L, j + 6L) != "\\u" ||
                !grepl("^[0-9A-Fa-f]{4}$", substr(text, j + 7L, j + 10L)))
              stop("unpaired high surrogate")
            low <- strtoi(substr(text, j + 7L, j + 10L), 16L)
            if (low < 0xDC00 || low > 0xDFFF) stop("invalid surrogate pair")
            j <- j + 6L
          } else if (code >= 0xDC00 && code <= 0xDFFF) stop("unpaired low surrogate")
          j <- j + 4L
        } else if (!byte(j) %in% c('"', "\\", "/", "b", "f", "n", "r", "t")) {
          stop("invalid escape")
        }
      } else if (utf8ToInt(byte(j)) < 32L) stop("control byte in string")
      j <- j + 1L
    }
    stop("unterminated string")
  }
  parse_value <- NULL
  parse_object <- function(i) {
    i <- skip(i + 1L)
    keys <- character()
    if (identical(byte(i), "}")) return(i + 1L)
    repeat {
      start <- i
      i <- string_end(i)
      token <- substr(text, start, i - 1L)
      key <- jsonlite::fromJSON(token)
      if (key %in% keys) stop(paste0("duplicate object key: ", key))
      keys <- c(keys, key)
      i <- skip(i)
      if (!identical(byte(i), ":")) stop("expected colon")
      i <- parse_value(skip(i + 1L))
      i <- skip(i)
      if (identical(byte(i), "}")) return(i + 1L)
      if (!identical(byte(i), ",")) stop("expected object separator")
      i <- skip(i + 1L)
    }
  }
  parse_array <- function(i) {
    i <- skip(i + 1L)
    if (identical(byte(i), "]")) return(i + 1L)
    repeat {
      i <- parse_value(i)
      i <- skip(i)
      if (identical(byte(i), "]")) return(i + 1L)
      if (!identical(byte(i), ",")) stop("expected array separator")
      i <- skip(i + 1L)
    }
  }
  parse_value <- function(i) {
    ch <- byte(i)
    if (identical(ch, "{")) return(parse_object(i))
    if (identical(ch, "[")) return(parse_array(i))
    if (identical(ch, '"')) return(string_end(i))
    tail <- substr(text, i, n)
    hit <- regexpr("^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:[.][0-9]+)?(?:[eE][+-]?[0-9]+)?)", tail, perl = TRUE)
    if (hit[[1]] != 1L) stop("expected JSON value")
    i + attr(hit, "match.length")
  }
  error <- tryCatch({
    end <- skip(parse_value(skip(1L)))
    if (end != n + 1L) stop("trailing JSON content")
    NULL
  }, error = identity)
  if (!is.null(error)) .wb_operation_pack_v2_error(
    "OPERATION_PACK_MANIFEST_PARSE_INVALID",
    paste0("Operation-pack v2 manifest is not strict JSON: ", conditionMessage(error)),
    phase = "parse")
  invisible(TRUE)
}

.wb_operation_pack_v2_read_manifest <- function(path) {
  path <- normalizePath(.wb_operation_pack_scalar(path, "manifest"), winslash = "/", mustWork = TRUE)
  text <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(text)
  parsed <- tryCatch(.wb_operation_pack_parse_canonical_json(text), error = identity)
  if (inherits(parsed, "error")) .wb_operation_pack_v2_error(
    "OPERATION_PACK_MANIFEST_PARSE_INVALID", conditionMessage(parsed), phase = "parse")
  attr(parsed, "operation_pack_v2_source_path") <- path
  attr(parsed, "operation_pack_v2_source_sha256") <- .wb_operation_pack_v2_file_sha256(path)
  parsed
}

.wb_operation_pack_manifest_input_any <- function(manifest) {
  if (is.character(manifest) && length(manifest) == 1L && !is.na(manifest)) {
    path <- normalizePath(manifest, winslash = "/", mustWork = TRUE)
    text <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
    probe <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = identity)
    schema_version <- if (inherits(probe, "error")) "" else
      as.character(probe$schema_version %||% "")[1]
    if (identical(schema_version, "scworkbench.operation_pack.v4"))
      return(.wb_operation_pack_v4_read_manifest(path))
    if (identical(schema_version, "scworkbench.operation_pack.v3"))
      return(.wb_operation_pack_v3_read_manifest(path))
    if (identical(schema_version, "scworkbench.operation_pack.v2"))
      return(.wb_operation_pack_v2_read_manifest(path))
    return(.wb_operation_pack_read_manifest(path))
  }
  .wb_operation_pack_assert(is.list(manifest), "OPERATION_PACK_MANIFEST_INVALID",
    "manifest must be a parsed JSON object or a path to one.")
  manifest
}

.wb_json_schema_instance_type <- function(x) {
  if (is.null(x)) return("null")
  if (is.logical(x) && length(x) == 1L) return("boolean")
  if ((is.integer(x) || is.numeric(x)) && length(x) == 1L) {
    if (is.finite(x) && identical(as.numeric(x), trunc(as.numeric(x)))) return(c("integer", "number"))
    return("number")
  }
  if (is.character(x) && length(x) == 1L) return("string")
  if (is.list(x)) {
    if (!is.null(names(x)) && (length(x) || length(names(x)))) return("object")
    return(c("array", "object")) # empty JSON arrays/objects are indistinguishable after jsonlite
  }
  "unknown"
}

.wb_json_schema_pointer <- function(root, ref) {
  .wb_operation_pack_assert(startsWith(ref, "#/"), "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
    paste0("Only local JSON Schema references are supported: ", ref),
    class = "wb_operation_pack_v2_error")
  parts <- strsplit(sub("^#/", "", ref), "/", fixed = FALSE)[[1]]
  parts <- gsub("~1", "/", gsub("~0", "~", parts, fixed = TRUE), fixed = TRUE)
  out <- root
  for (part in parts) {
    if (!is.list(out) || is.null(out[[part]])) return(NULL)
    out <- out[[part]]
  }
  out
}

# Native R validator for the frozen Draft 2020-12 feature subset used by the
# live ABI records and embedded closed parameter-schema profile.
.wb_json_schema_validate_2020 <- function(instance, schema, root = schema, path = "$") {
  fail <- function(message) list(ok = FALSE, path = path, message = message)
  pass <- function() list(ok = TRUE, path = path, message = "")
  if (is.logical(schema) && length(schema) == 1L) return(if (isTRUE(schema)) pass() else fail("false schema"))
  if (!is.list(schema)) return(fail("schema is neither object nor boolean"))
  if (!is.null(schema[["$ref"]])) {
    target <- .wb_json_schema_pointer(root, as.character(schema[["$ref"]])[1])
    if (is.null(target)) return(fail("unresolved local reference"))
    return(.wb_json_schema_validate_2020(instance, target, root, path))
  }
  evaluate <- function(child) .wb_json_schema_validate_2020(instance, child, root, path)
  if (!is.null(schema$allOf)) for (child in schema$allOf) {
    result <- evaluate(child); if (!isTRUE(result$ok)) return(result)
  }
  if (!is.null(schema$anyOf)) {
    results <- lapply(schema$anyOf, evaluate)
    if (!any(vapply(results, `[[`, logical(1), "ok"))) return(fail("no anyOf branch matched"))
  }
  if (!is.null(schema$oneOf)) {
    results <- lapply(schema$oneOf, evaluate)
    if (sum(vapply(results, `[[`, logical(1), "ok")) != 1L) return(fail("oneOf did not match exactly one branch"))
  }
  if (!is.null(schema$not) && isTRUE(evaluate(schema$not)$ok)) return(fail("not schema matched"))
  if (!is.null(schema[["if"]])) {
    branch <- if (isTRUE(evaluate(schema[["if"]])$ok)) schema[["then"]] else schema[["else"]]
    if (!is.null(branch)) { result <- evaluate(branch); if (!isTRUE(result$ok)) return(result) }
  }
  canonical_equal <- function(a, b) identical(.wb_operation_pack_canonical_json(a), .wb_operation_pack_canonical_json(b))
  if (!is.null(schema$const) && !canonical_equal(instance, schema$const)) return(fail("const mismatch"))
  if (!is.null(schema$enum) && !any(vapply(schema$enum,
      function(choice) canonical_equal(instance, choice), logical(1)))) return(fail("enum mismatch"))
  if (!is.null(schema$type)) {
    accepted <- as.character(unlist(schema$type, use.names = FALSE))
    if (!length(intersect(.wb_json_schema_instance_type(instance), accepted))) return(fail(paste0("expected type ", paste(accepted, collapse = "|"))))
  }
  types <- .wb_json_schema_instance_type(instance)
  if ("string" %in% types) {
    length_chars <- nchar(instance, type = "chars")
    if (!is.null(schema$minLength) && length_chars < as.integer(schema$minLength)) return(fail("minLength"))
    if (!is.null(schema$maxLength) && length_chars > as.integer(schema$maxLength)) return(fail("maxLength"))
    if (!is.null(schema$pattern)) {
      # JSON Schema uses ECMAScript Unicode escapes; PCRE uses \x{HHHH}.
      # Keep the shared schema bytes and their character semantics unchanged.
      pattern <- gsub("\\\\u([0-9A-Fa-f]{4})", "\\\\x{\\1}", schema$pattern, perl = TRUE)
      if (!grepl(pattern, instance, perl = TRUE)) return(fail("pattern"))
    }
  }
  if ("number" %in% types) {
    value <- as.numeric(instance)
    if (!is.null(schema$minimum) && value < as.numeric(schema$minimum)) return(fail("minimum"))
    if (!is.null(schema$maximum) && value > as.numeric(schema$maximum)) return(fail("maximum"))
    if (!is.null(schema$exclusiveMinimum) && value <= as.numeric(schema$exclusiveMinimum)) return(fail("exclusiveMinimum"))
    if (!is.null(schema$exclusiveMaximum) && value >= as.numeric(schema$exclusiveMaximum)) return(fail("exclusiveMaximum"))
    if (!is.null(schema$multipleOf) && abs(value / as.numeric(schema$multipleOf) - round(value / as.numeric(schema$multipleOf))) > 1e-12) return(fail("multipleOf"))
  }
  object_like <- is.list(instance) && (!is.null(names(instance)) || !length(instance))
  array_like <- is.list(instance) && (is.null(names(instance)) || !length(instance))
  if (object_like && any(c("properties", "required", "additionalProperties", "minProperties", "maxProperties") %in% names(schema))) {
    keys <- names(instance) %||% character()
    if (!is.null(schema$required)) {
      missing <- setdiff(as.character(unlist(schema$required, use.names = FALSE)), keys)
      if (length(missing)) return(fail(paste0("missing required property ", missing[[1]])))
    }
    properties <- schema$properties %||% list()
    for (key in intersect(keys, names(properties))) {
      result <- .wb_json_schema_validate_2020(instance[[key]], properties[[key]], root, paste0(path, "/", key))
      if (!isTRUE(result$ok)) return(result)
    }
    extras <- setdiff(keys, names(properties))
    if (length(extras) && identical(schema$additionalProperties, FALSE)) return(fail(paste0("unknown property ", extras[[1]])))
    if (length(extras) && is.list(schema$additionalProperties)) for (key in extras) {
      result <- .wb_json_schema_validate_2020(instance[[key]], schema$additionalProperties, root, paste0(path, "/", key))
      if (!isTRUE(result$ok)) return(result)
    }
    if (!is.null(schema$minProperties) && length(keys) < as.integer(schema$minProperties)) return(fail("minProperties"))
    if (!is.null(schema$maxProperties) && length(keys) > as.integer(schema$maxProperties)) return(fail("maxProperties"))
  }
  if (array_like && any(c("items", "prefixItems", "minItems", "maxItems", "uniqueItems") %in% names(schema))) {
    if (!is.null(schema$minItems) && length(instance) < as.integer(schema$minItems)) return(fail("minItems"))
    if (!is.null(schema$maxItems) && length(instance) > as.integer(schema$maxItems)) return(fail("maxItems"))
    if (isTRUE(schema$uniqueItems) && anyDuplicated(vapply(instance, .wb_operation_pack_canonical_json, character(1)))) return(fail("uniqueItems"))
    prefix <- schema$prefixItems %||% list()
    if (length(prefix)) for (i in seq_len(min(length(prefix), length(instance)))) {
      result <- .wb_json_schema_validate_2020(instance[[i]], prefix[[i]], root, paste0(path, "/", i - 1L))
      if (!isTRUE(result$ok)) return(result)
    }
    if (!is.null(schema$items)) for (i in seq_along(instance)) {
      if (i <= length(prefix)) next
      result <- .wb_json_schema_validate_2020(instance[[i]], schema$items, root, paste0(path, "/", i - 1L))
      if (!isTRUE(result$ok)) return(result)
    }
  }
  pass()
}

.wb_operation_pack_v2_outer_validate <- function(manifest) {
  schema <- .wb_operation_pack_v2_read_schema(.wb_operation_pack_v2_manifest_schema())
  result <- .wb_json_schema_validate_2020(manifest, schema)
  if (!isTRUE(result$ok)) .wb_operation_pack_v2_error(
    "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
    paste0("Operation-pack v2 manifest failed Draft 2020-12 validation at ", result$path, ": ", result$message),
    phase = "outer_schema", instance_path = result$path)
  invisible(TRUE)
}

.wb_operation_pack_v2_read_schema <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

.wb_operation_pack_v2_param_profile_validate <- function(schema, operation) {
  dialect <- "https://json-schema.org/draft/2020-12/schema"
  allowed <- c(
    "$schema", "$defs", "$ref", "$comment", "title", "description", "type", "enum",
    "const", "default", "examples", "allOf", "anyOf", "oneOf", "not", "if", "then",
    "else", "properties", "required", "additionalProperties", "minProperties", "maxProperties",
    "items", "prefixItems", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength",
    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"
  )
  types <- c("null", "boolean", "object", "array", "number", "integer", "string")
  walk <- function(node, root = FALSE, path = "$") {
    if (is.logical(node) && length(node) == 1L && !is.na(node)) return(invisible(TRUE))
    if (!is.list(node)) .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_INVALID",
      paste0("Parameter schema at ", path, " is not an object or boolean schema."), "parameter_schema", operation = operation)
    keys <- names(node) %||% character()
    extra <- setdiff(keys, allowed)
    if (length(extra)) .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_PROFILE_UNSUPPORTED",
      paste0("Unsupported parameter-schema keyword at ", path, ": ", sort(extra, method = "radix")[[1]]),
      "parameter_schema", operation = operation)
    if ("$schema" %in% keys && (!root || !identical(as.character(node[["$schema"]])[1], dialect))) {
      .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_DIALECT_UNSUPPORTED",
        paste0("Unsupported parameter-schema dialect at ", path, "."), "parameter_schema", operation = operation)
    }
    if ("$ref" %in% keys && !grepl("^#/[\\$]defs/[A-Za-z][A-Za-z0-9._-]*(?:/[A-Za-z0-9._~-]+)*$", as.character(node[["$ref"]])[1], perl = TRUE)) {
      .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_PROFILE_UNSUPPORTED",
        paste0("Only local #/$defs references are allowed at ", path, "."), "parameter_schema", operation = operation)
    }
    if ("type" %in% keys) {
      value <- as.character(unlist(node$type, use.names = FALSE))
      if (!length(value) || any(!value %in% types) || anyDuplicated(value)) .wb_operation_pack_v2_error(
        "OPERATION_PACK_PARAM_SCHEMA_INVALID", paste0("Invalid type declaration at ", path, "."), "parameter_schema", operation = operation)
    }
    if ("required" %in% keys) {
      value <- unlist(node$required, use.names = FALSE)
      if ((length(value) && !is.character(value)) || anyDuplicated(value)) .wb_operation_pack_v2_error(
        "OPERATION_PACK_PARAM_SCHEMA_INVALID", paste0("Invalid required declaration at ", path, "."), "parameter_schema", operation = operation)
    }
    for (key in intersect(c("$defs", "properties"), keys)) {
      value <- node[[key]]
      if (!is.list(value)) .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_INVALID",
        paste0("Invalid schema map at ", path, "/", key, "."), "parameter_schema", operation = operation)
      for (name in names(value) %||% character()) walk(value[[name]], FALSE, paste0(path, "/", key, "/", name))
    }
    for (key in intersect(c("allOf", "anyOf", "oneOf", "prefixItems"), keys)) {
      value <- node[[key]]
      if (!is.list(value) || (!length(value) && !identical(key, "prefixItems"))) .wb_operation_pack_v2_error(
        "OPERATION_PACK_PARAM_SCHEMA_INVALID", paste0("Invalid schema array at ", path, "/", key, "."), "parameter_schema", operation = operation)
      for (i in seq_along(value)) walk(value[[i]], FALSE, paste0(path, "/", key, "/", i - 1L))
    }
    for (key in intersect(c("not", "if", "then", "else", "items", "additionalProperties"), keys)) {
      walk(node[[key]], FALSE, paste0(path, "/", key))
    }
    if ("default" %in% keys) {
      without <- node; without$default <- NULL
      result <- .wb_json_schema_validate_2020(node$default, without, schema, path)
      if (!isTRUE(result$ok)) .wb_operation_pack_v2_error("OPERATION_PACK_PARAM_SCHEMA_INVALID",
        paste0("Default does not validate at ", path, ": ", result$message), "parameter_schema", operation = operation)
    }
    invisible(TRUE)
  }
  walk(schema, TRUE)
  invisible(TRUE)
}

.wb_operation_pack_v2_catalog_param_type <- function(schema) {
  types <- as.character(unlist(schema$type %||% "list", use.names = FALSE))
  if ("integer" %in% types) return("int")
  if ("number" %in% types) return("dbl")
  if ("boolean" %in% types) return("bool")
  if ("string" %in% types) return(if (is.null(schema$enum)) "string" else "choice")
  if ("array" %in% types && identical(as.character(schema$items$type %||% "")[1], "string")) return("string_vec")
  "list"
}

.wb_operation_pack_v2_declaration_error <- function(operation, message) {
  .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
    paste0("Operation '", operation, "' ", message), "semantic_admission",
    operation = operation)
}

.wb_operation_pack_v2_semantic_validate <- function(manifest, allow_graph_replay = FALSE) {
  namespace <- as.character(manifest$namespace)[1]
  operations <- manifest$operations
  short <- vapply(operations, function(x) as.character(x$name)[1], character(1))
  qualified <- vapply(operations, function(x) as.character(x$qualified_name)[1], character(1))
  for (i in seq_along(operations)) {
    expected <- paste0(namespace, "::", short[[i]])
    if (!identical(qualified[[i]], expected)) .wb_operation_pack_v2_error(
      "OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH",
      paste0("Qualified operation name must be exactly '", expected, "'."), "semantic_admission",
      operation_index = i, operation = qualified[[i]])
  }
  if (anyDuplicated(short) || anyDuplicated(qualified)) .wb_operation_pack_v2_error(
    "OPERATION_PACK_MANIFEST_OPERATION_DUPLICATE", "Operation short and qualified names must be unique.",
    "semantic_admission", names = sort(unique(c(short[duplicated(short)], qualified[duplicated(qualified)])), method = "radix"))
  for (i in seq_along(operations)) {
    op <- operations[[i]]; opname <- qualified[[i]]
    input_names <- vapply(op$inputs, function(x) as.character(x$name)[1], character(1))
    output_names <- vapply(op$outputs, function(x) as.character(x$name)[1], character(1))
    allocation <- vapply(op$outputs, function(x) as.character(x$allocated_id_key)[1], character(1))
    dependency <- vapply(op$dependencies, function(x) as.character(x$requirement_id)[1], character(1))
    if (anyDuplicated(input_names)) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_INPUT_DUPLICATE",
      paste0("Operation '", opname, "' repeats an input name."), "semantic_admission", operation = opname)
    if (anyDuplicated(output_names)) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_OUTPUT_DUPLICATE",
      paste0("Operation '", opname, "' repeats an output name."), "semantic_admission", operation = opname)
    if (anyDuplicated(allocation)) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_ALLOCATION_KEY_DUPLICATE",
      paste0("Operation '", opname, "' repeats an allocated ID key."), "semantic_admission", operation = opname)
    if (anyDuplicated(dependency)) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_DEFINITION_KEY_DUPLICATE",
      paste0("Operation '", opname, "' repeats a dependency requirement ID."), "semantic_admission", operation = opname)
    for (dep in op$dependencies) if (identical(as.character(dep$kind %||% "")[1], "dynamic_input_metadata_package")) {
      if (!as.character(dep$input_name %||% "")[1] %in% input_names) .wb_operation_pack_v2_error(
        "OPERATION_PACK_MANIFEST_DEFINITION_KEY_DUPLICATE", "Dynamic dependency names an undeclared input.",
        "semantic_admission", operation = opname, requirement_id = dep$requirement_id)
    }
    properties <- op$params_schema$properties %||% list()
    registry_reads <- op$registry_reads %||% list()
    registry_names <- vapply(registry_reads, function(x) as.character(x$name)[1], character(1))
    if (anyDuplicated(registry_names) || length(intersect(registry_names, input_names))) {
      .wb_operation_pack_v2_declaration_error(opname,
        "repeats a registry-read name or collides with a primitive input name.")
    }
    for (registry_read in registry_reads) {
      matrix_input <- as.character(registry_read$matrix_input)[1]
      matrix_index <- match(matrix_input, input_names)
      if (is.na(matrix_index) ||
          !identical(as.character(op$inputs[[matrix_index]]$kind)[1], "matrix")) {
        .wb_operation_pack_v2_declaration_error(opname,
          "has a feature-set registry read without a declared matrix input.")
      }
      scalar_parameter <- as.character(registry_read$namespace_parameter %||% "")[1]
      vector_parameters <- c(
        as.character(registry_read$namespaces_parameter %||% "")[1],
        as.character(registry_read$feature_sets_parameter %||% "")[1]
      )
      vector_parameters <- vector_parameters[nzchar(vector_parameters)]
      if (nzchar(scalar_parameter)) {
        schema_type <- as.character(unlist(properties[[scalar_parameter]]$type %||%
          character(), use.names = FALSE))
        if (is.null(properties[[scalar_parameter]]) || !"string" %in% schema_type) {
          .wb_operation_pack_v2_declaration_error(opname,
            "has an incompatible scalar namespace selector binding.")
        }
      }
      for (parameter in vector_parameters) {
        schema <- properties[[parameter]]
        schema_type <- as.character(unlist(schema$type %||% character(), use.names = FALSE))
        if (is.null(schema) || !"array" %in% schema_type ||
            !identical(as.character(schema$items$type %||% "")[1], "string")) {
          .wb_operation_pack_v2_declaration_error(opname,
            "has an incompatible registry vector-selector binding.")
        }
      }
      selector_parameters <- c(scalar_parameter, vector_parameters)
      selector_parameters <- selector_parameters[nzchar(selector_parameters)]
      if (anyDuplicated(selector_parameters)) .wb_operation_pack_v2_declaration_error(
        opname, "reuses one parameter for multiple registry selector roles.")
    }
    public <- op$public_interface %||% NULL
    if (!is.null(public)) {
      public_inputs <- vapply(public$inputs, `[[`, character(1), "name")
      public_params <- vapply(public$parameters, `[[`, character(1), "name")
      public_outputs <- vapply(public$outputs, `[[`, character(1), "name")
      if (anyDuplicated(public_inputs) || any(!public_inputs %in% input_names) ||
          anyDuplicated(public_params) || any(!public_params %in% names(properties)) ||
          anyDuplicated(public_outputs) || !setequal(public_outputs, output_names)) {
        .wb_operation_pack_v2_declaration_error(opname,
          "public interface is not an exact bijection with its inputs, parameters, and outputs.")
      }
      for (item in public$parameters) {
        name <- as.character(item$name)[1]
        expected <- .wb_operation_pack_v2_catalog_param_type(properties[[name]])
        declared <- as.character(item$type)[1]
        compatible <- identical(declared, expected) ||
          (identical(expected, "string_vec") && declared %in% c("cell_ids_or_set", "string_vec")) ||
          (identical(expected, "string") && identical(declared, "cell_set"))
        if (!compatible) .wb_operation_pack_v2_declaration_error(opname,
          paste0("public parameter '", name, "' type conflicts with params_schema."))
      }
    }
    bindings <- op$parameter_bindings %||% list()
    binding_names <- vapply(bindings, function(x) as.character(x$parameter)[1], character(1))
    if (anyDuplicated(binding_names)) .wb_operation_pack_v2_declaration_error(opname,
      "repeats a parameter binding.")
    for (binding in bindings) {
      parameter <- as.character(binding$parameter)[1]
      input <- as.character(binding$input)[1]
      policy <- as.character(binding$policy)[1]
      input_index <- match(input, input_names)
      if (is.na(input_index) || is.null(properties[[parameter]]) ||
          !identical(as.character(op$inputs[[input_index]]$kind)[1], "matrix")) {
        .wb_operation_pack_v2_declaration_error(opname,
          "has a parameter binding with a missing or incompatible input/parameter reference.")
      }
      schema_type <- as.character(unlist(properties[[parameter]]$type %||% character(), use.names = FALSE))
      if (!"array" %in% schema_type ||
          !identical(as.character(properties[[parameter]]$items$type %||% "")[1], "string")) {
        .wb_operation_pack_v2_declaration_error(opname,
          paste0("binding policy '", policy, "' requires an array-of-string parameter."))
      }
    }
    policies <- op$dimension_policies %||% list()
    policy_outputs <- vapply(policies, function(x) as.character(x$output)[1], character(1))
    if (anyDuplicated(policy_outputs)) .wb_operation_pack_v2_declaration_error(opname,
      "repeats a dimension policy output.")
    for (policy in policies) {
      output_index <- match(as.character(policy$output)[1], output_names)
      valid <- !is.na(output_index) &&
        identical(as.character(op$outputs[[output_index]]$category)[1], "terminal_artifact") &&
        as.character(op$outputs[[output_index]]$kind)[1] %in% c("feature_table", "obs_table") &&
        identical(as.character(op$outputs[[output_index]]$storage_profile)[1], "terminal_primitive_v1")
      if (!valid) .wb_operation_pack_v2_declaration_error(opname,
        "declares data-dependent dimensions for an incompatible output.")
    }
    chunk <- op$chunking %||% NULL
    if (!is.null(chunk)) {
      input_index <- match(as.character(chunk$input)[1], input_names)
      output_index <- match(as.character(chunk$output)[1], output_names)
      sequence_schema <- properties[[as.character(chunk$sequence_parameter)[1]]]
      size_schema <- properties[[as.character(chunk$size_parameter)[1]]]
      adjust_schema <- properties[[as.character(chunk$adjust_parameter)[1]]]
      valid <- !is.na(input_index) && !is.na(output_index) &&
        identical(as.character(op$inputs[[input_index]]$kind)[1], "matrix") &&
        identical(as.character(op$outputs[[output_index]]$kind)[1], "feature_table") &&
        as.character(chunk$output)[1] %in% policy_outputs &&
        identical(.wb_operation_pack_v2_catalog_param_type(sequence_schema), "string_vec") &&
        identical(.wb_operation_pack_v2_catalog_param_type(size_schema), "int") &&
        identical(.wb_operation_pack_v2_catalog_param_type(adjust_schema), "string") &&
        is.numeric(size_schema$minimum) && as.numeric(size_schema$minimum) >= 1 &&
        !is.null(size_schema$default) && as.numeric(size_schema$default) >= 1 &&
        as.character(chunk$sequence_parameter)[1] %in% binding_names
      if (!valid) .wb_operation_pack_v2_declaration_error(opname,
        "has a chunk declaration with a missing, incompatible, or undeclared reference.")
    }
    retained <- op$retained_parameters %||% list()
    retained_names <- vapply(retained, function(x) as.character(x$name)[1], character(1))
    if (anyDuplicated(retained_names)) .wb_operation_pack_v2_declaration_error(opname,
      "repeats a retained parameter name.")
    for (item in retained) {
      source <- as.character(item$source)[1]
      needs_output <- source %in% c("output_meta", "output_first_row", "output_row_count")
      needs_input <- identical(source, "input_feature_count")
      needs_parameter <- source %in% c("parameter_supplied", "parameter_count", "parameter_value")
      needs_field <- source %in% c("output_meta", "output_first_row")
      valid <- (!needs_output || as.character(item$output %||% "")[1] %in% output_names) &&
        (!needs_input || as.character(item$input %||% "")[1] %in% input_names) &&
        (!needs_parameter || as.character(item$parameter %||% "")[1] %in% names(properties)) &&
        (!needs_field || nzchar(as.character(item$field %||% "")[1]))
      if (!valid) .wb_operation_pack_v2_declaration_error(opname,
        paste0("retained parameter '", item$name, "' has an invalid source reference."))
    }
    groups <- vapply(op$outputs, function(x) as.character(x$promotion_group)[1], character(1))
    categories <- vapply(op$outputs, function(x) as.character(x$category)[1], character(1))
    terminal_names <- output_names[categories == "terminal_artifact"]
    closure <- op$promotion_closure
    invalid_closure <- !setequal(names(closure), terminal_names) || anyDuplicated(names(closure))
    if (!invalid_closure) for (terminal in terminal_names) {
      group <- groups[match(terminal, output_names)]
      expected_members <- sort(output_names[groups == group], method = "radix")
      observed <- as.character(unlist(closure[[terminal]], use.names = FALSE))
      if (!identical(observed, expected_members) || anyDuplicated(observed)) invalid_closure <- TRUE
    }
    if (!invalid_closure) for (group in unique(groups)) {
      witnesses <- terminal_names[groups[match(terminal_names, output_names)] == group]
      if (!length(witnesses)) invalid_closure <- TRUE
      for (j in which(groups == group & categories == "materialization")) {
        observed <- as.character(unlist(op$outputs[[j]]$materialized_by_terminals %||% character(), use.names = FALSE))
        if (!identical(observed, sort(witnesses, method = "radix"))) invalid_closure <- TRUE
      }
    }
    if (invalid_closure) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_PROMOTION_CLOSURE_INVALID",
      paste0("Operation '", opname, "' promotion closure is not the exact group-derived closure."),
      "semantic_admission", operation = opname)
    replay <- op$replay_equivalence
    invalid_replay <- !setequal(names(replay), output_names) || anyDuplicated(names(replay))
    allowed_policy <- function(output) {
      category <- as.character(output$category)[1]; kind <- as.character(output$kind)[1]
      if (allow_graph_replay && identical(kind, "graph") &&
          identical(category, "terminal_artifact")) return("exact_graph_descriptor")
      if (identical(category, "materialization") && kind %in% c("matrix", "space")) return("exact_canonical_value")
      if (kind == "space_2d" && category %in% c("materialization", "terminal_artifact")) return(c("exact_canonical_value", "cell_aligned_embedding"))
      if (identical(category, "terminal_artifact") && identical(kind, "model_ref")) return("loadable_reference")
      if (identical(category, "terminal_artifact")) return("exact_canonical_value")
      if (identical(category, "core_registry_request") && identical(kind, "cell_set_admission")) return("exact_membership_and_order")
      if (identical(category, "core_registry_request") && identical(kind, "cell_set_family_admission")) return("exact_family_membership_and_order")
      character()
    }
    if (!invalid_replay) for (output in op$outputs) {
      policy <- as.character(replay[[as.character(output$name)[1]]])[1]
      if (!policy %in% allowed_policy(output)) invalid_replay <- TRUE
    }
    if (invalid_replay) .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_REPLAY_EQUIVALENCE_INVALID",
      paste0("Operation '", opname, "' replay map is incomplete or policy-incompatible."),
      "semantic_admission", operation = opname)
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_normalize <- function(manifest, package = NULL, package_description = NULL) {
  .wb_operation_pack_v2_outer_validate(manifest)
  .wb_operation_pack_v2_semantic_validate(manifest)
  for (op in manifest$operations) .wb_operation_pack_v2_param_profile_validate(op$params_schema, op$qualified_name)
  if (!identical(as.character(manifest$identity_scheme)[1], .wb_operation_pack_identity_scheme())) {
    .wb_operation_pack_v2_error("OPERATION_PACK_IDENTITY_SCHEME_MISMATCH",
      "Operation-pack v2 requires canonical JSON v1.", "identity",
      class = "wb_operation_pack_identity_error")
  }
  if (manifest$namespace %in% .wb_operation_pack_reserved_namespaces()) .wb_operation_pack_v2_error(
    "OPERATION_PACK_NAMESPACE_RESERVED", "Operation-pack namespace is reserved.", "semantic_admission")
  current <- tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "0.1.0")
  minimum <- as.character(manifest$compatibility$scworkbench$minimum)[1]
  maximum <- as.character(manifest$compatibility$scworkbench$maximum_exclusive)[1]
  if (utils::compareVersion(current, minimum) < 0L || utils::compareVersion(current, maximum) >= 0L) {
    .wb_operation_pack_v2_error("OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE",
      paste0("Pack range [", minimum, ", ", maximum, ") excludes scworkbench ", current, "."), "semantic_admission")
  }
  if (!identical(as.character(manifest$compatibility$pack_abi$minimum)[1], "2") ||
      !identical(as.character(manifest$compatibility$pack_abi$maximum)[1], "2")) {
    .wb_operation_pack_v2_error("OPERATION_PACK_PROTOCOL_INCOMPATIBLE",
      "Operation-pack v2 requires the closed ABI interval 2 through 2.", "semantic_admission")
  }
  if (!is.null(package) && !identical(as.character(manifest$package$name)[1], as.character(package)[1])) {
    .wb_operation_pack_v2_error("OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH",
      "Manifest package name differs from the installed R package.", "authentication")
  }
  if (!is.null(package_description) && !identical(as.character(manifest$package$version)[1], as.character(package_description$Version)[1])) {
    .wb_operation_pack_v2_error("OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH",
      "Manifest version differs from the installed R package.", "authentication")
  }
  manifest
}

.wb_operation_pack_v2_content_identity <- function(installed_path) {
  root <- normalizePath(installed_path, winslash = "/", mustWork = TRUE)
  paths <- list.files(root, recursive = TRUE, all.files = TRUE, full.names = TRUE,
    include.dirs = FALSE, no.. = TRUE)
  paths <- sort(normalizePath(paths, winslash = "/", mustWork = TRUE), method = "radix")
  links <- Sys.readlink(paths)
  if (any(nzchar(links))) .wb_operation_pack_v2_error("OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "Installed v2 pack content may not contain symbolic links.", "authentication")
  rel <- substring(paths, nchar(root) + 2L)
  entries <- lapply(seq_along(paths), function(i) list(
    path = rel[[i]], size = as.numeric(file.info(paths[[i]])$size),
    sha256 = .wb_operation_pack_v2_file_sha256(paths[[i]])))
  value <- list(scheme = "scworkbench.operation_pack.content_manifest.v1", files = entries)
  .wb_operation_pack_v2_id("scworkbench.operation_pack.content.v1", value)
}

.wb_operation_pack_v2_identity <- function(manifest, source_sha256, pack_content_identity) {
  definitions <- stats::setNames(lapply(manifest$operations, function(op) {
    .wb_operation_pack_v2_id("scworkbench.operation_pack.definition.v2", op)
  }), vapply(manifest$operations, function(op) as.character(op$qualified_name)[1], character(1)))
  manifest_id <- .wb_operation_pack_v2_id("scworkbench.operation_pack.manifest.v2", manifest)
  entry <- .wb_operation_pack_v2_id("scworkbench.operation_pack.entry_point.v2", list(
    backend = manifest$backend, package = manifest$package, value = manifest$entry_point))
  source_id <- list(scheme = "scworkbench.operation_pack.manifest_source.bytes.v1", sha256 = source_sha256)
  pack_value <- list(
    scheme = "scworkbench.operation_pack.pack.v2",
    manifest_sha256 = manifest_id$sha256,
    namespace = manifest$namespace, package = manifest$package, backend = manifest$backend,
    entry_point = manifest$entry_point,
    operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
    pack_content_sha256 = pack_content_identity$sha256)
  pack <- .wb_operation_pack_v2_id("scworkbench.operation_pack.pack.v2", pack_value)
  list(
    identity_scheme = .wb_operation_pack_identity_scheme(), schema_version = manifest$schema_version,
    pack_abi_version = "2", namespace = manifest$namespace, package = manifest$package,
    backend = manifest$backend, compatibility = manifest$compatibility, entry_point = manifest$entry_point,
    manifest_source_identity = source_id, manifest_identity = manifest_id,
    manifest_sha256 = manifest_id$sha256,
    operation_definition_identities = definitions,
    operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
    distribution_identity = pack_content_identity, entry_point_identity = entry,
    pack_identity = pack, pack_sha256 = pack$sha256)
}

.wb_operation_pack_v2_params_to_catalog <- function(schema, public = NULL) {
  properties <- schema$properties %||% list()
  required <- as.character(unlist(schema$required %||% character(), use.names = FALSE))
  lapply(names(properties) %||% character(), function(name) {
    item <- properties[[name]]
    public_index <- if (is.null(public)) NA_integer_ else match(name,
      vapply(public, `[[`, character(1), "name"))
    metadata <- if (is.na(public_index)) NULL else public[[public_index]]
    type <- as.character(metadata$type %||% .wb_operation_pack_v2_catalog_param_type(item))[1]
    # JSON array parameters cross the protocol as lists, while the public R
    # operator boundary should retain ordinary integral-vector ergonomics.
    # This is a catalog projection only; wire validation remains schema-owned.
    if (identical(type, "list") && "array" %in% as.character(unlist(
        item$type %||% character(), use.names = FALSE)) &&
        identical(as.character(item$items$type %||% "")[1], "integer"))
      type <- "int_range"
    out <- list(name = name, type = type)
    if (identical(type, "string_vec") &&
        as.numeric(item$minItems %||% 0) == 0) out$allow_empty <- TRUE
    if ("default" %in% names(item)) out["default"] <- list(if (type %in% c("int", "dbl"))
      as.numeric(item$default) else item$default)
    if (!is.null(item$minimum)) out$min <- as.numeric(item$minimum)
    if (!is.null(item$maximum)) out$max <- as.numeric(item$maximum)
    if (!is.null(item$enum)) out$choices <- as.character(unlist(item$enum, use.names = FALSE))
    out$help <- as.character(metadata$help %||% item$description %||% paste0("ABI v2 parameter ", name))[1]
    out$required <- name %in% required
    out
  })
}

.wb_operation_pack_v2_catalog_definition <- function(op) {
  required <- op$inputs[vapply(op$inputs, function(x) isTRUE(x$required), logical(1))]
  optional <- op$inputs[!vapply(op$inputs, function(x) isTRUE(x$required), logical(1))]
  requires <- stats::setNames(lapply(required, `[[`, "kind"), vapply(required, `[[`, character(1), "name"))
  optional_requires <- stats::setNames(lapply(optional, `[[`, "kind"), vapply(optional, `[[`, character(1), "name"))
  ordinary <- Filter(function(x) !identical(as.character(x$category)[1], "core_registry_request"), op$outputs)
  produces <- stats::setNames(lapply(ordinary, `[[`, "kind"), vapply(ordinary, `[[`, character(1), "name"))
  terminals <- vapply(Filter(function(x) identical(as.character(x$category)[1], "terminal_artifact"), ordinary), `[[`, character(1), "name")
  public <- op$public_interface %||% NULL
  public_inputs <- if (is.null(public)) list() else stats::setNames(public$inputs,
    vapply(public$inputs, `[[`, character(1), "name"))
  public_outputs <- if (is.null(public)) list() else stats::setNames(public$outputs,
    vapply(public$outputs, `[[`, character(1), "name"))
  inputs <- stats::setNames(lapply(op$inputs, function(x) {
    metadata <- public_inputs[[as.character(x$name)[1]]] %||% list()
    value <- list(required = x$required, kind = x$kind)
    if (!is.null(metadata$label)) value$label <- metadata$label
    if (!is.null(metadata$help)) value$help <- metadata$help
    value
  }), vapply(op$inputs, `[[`, character(1), "name"))
  interface_produces <- stats::setNames(lapply(ordinary, function(x) list(
    kind = x$kind, description = public_outputs[[as.character(x$name)[1]]]$description %||% NULL)),
    vapply(ordinary, `[[`, character(1), "name"))
  definition <- list(
    name = op$qualified_name, op_name = op$qualified_name, title = op$title,
    description = op$description,
    intent = public$intent %||% "operation_pack_v2_reference",
    requires = requires, optional_requires = optional_requires,
    inputs = inputs,
    params = .wb_operation_pack_v2_params_to_catalog(op$params_schema,
      public$parameters %||% NULL), produces = produces,
    interface_produces = interface_produces,
    promotable = terminals, replay_equivalence = op$replay_equivalence[names(produces)],
    coverage = list(), pack_abi_version = "2", v2_definition = op)
  if (!is.null(op$chunking)) {
    size <- op$params_schema$properties[[as.character(op$chunking$size_parameter)[1]]]
    definition$chunking <- list(chunkable = TRUE, axis = op$chunking$axis,
      chunk_size_param = op$chunking$size_parameter,
      chunk_size_default = as.integer(size$default),
      merge = as.list(stats::setNames("row_bind_feature_table", op$chunking$output)),
      status = "implemented_generic")
  }
  definition
}

.wb_operation_pack_v2_registration <- function(manifest, runners, package_description,
                                                installed_path, manifest_path) {
  .wb_operation_pack_named_object(runners, "operations", allow_empty = FALSE)
  expected <- vapply(manifest$operations, function(x) as.character(x$qualified_name)[1], character(1))
  if (!setequal(names(runners), expected) || anyDuplicated(names(runners))) .wb_operation_pack_v2_error(
    "OPERATION_PACK_ENTRY_POINT_INVALID", "V2 runner names must exactly equal manifest qualified operation names.",
    "authentication")
  for (name in expected) {
    runner <- runners[[name]]
    if (!is.function(runner) || !identical(names(formals(runner)), c("readers", "writers", "params", "context"))) {
      .wb_operation_pack_v2_error("OPERATION_PACK_ENTRY_POINT_INVALID",
        paste0("V2 runner '", name, "' must have formals readers, writers, params, context."), "authentication")
    }
  }
  content <- .wb_operation_pack_v2_content_identity(installed_path)
  identity <- .wb_operation_pack_v2_identity(manifest,
    .wb_operation_pack_v2_file_sha256(manifest_path), content)
  definitions <- stats::setNames(lapply(manifest$operations, .wb_operation_pack_v2_catalog_definition), expected)
  structure(list(
    manifest = manifest, runners = runners, identity = identity,
    definitions = definitions, protocol_version = "2",
    manifest_path = manifest_path, installed_path = installed_path,
    runtime_attestation = list(
      schema = "scworkbench.operation_pack.runtime.r.v2", backend = "R",
      package = manifest$package,
      built = as.character(package_description$Built %||% NA_character_)[1],
      remote_sha = as.character(package_description$RemoteSha %||% NA_character_)[1],
      distribution_identity = content, manifest_source_identity = identity$manifest_source_identity,
      entry_point_identity = identity$entry_point_identity)
  ), class = c("wb_operation_pack_registration_v2", "wb_operation_pack_registration", "list"))
}

.wb_operation_pack_v2_manifest_path <- function(package, lib.loc = NULL) {
  package <- .wb_operation_pack_scalar(package, "package", "^[A-Za-z][A-Za-z0-9.]*$")
  path <- system.file("scworkbench", "operation-pack.json", package = package, lib.loc = lib.loc)
  .wb_operation_pack_assert(nzchar(path) && file.exists(path), "OPERATION_PACK_MANIFEST_NOT_FOUND",
    paste0("Installed package '", package, "' has no operation-pack manifest."), package = package)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v2_invoke <- function(package, lib.loc = NULL) {
  manifest_path <- .wb_operation_pack_v2_manifest_path(package, lib.loc)
  description <- utils::packageDescription(package, lib.loc = lib.loc)
  manifest <- .wb_operation_pack_v2_normalize(.wb_operation_pack_v2_read_manifest(manifest_path),
    package = package, package_description = description)
  if (!identical(as.character(manifest$backend)[1], "R")) .wb_operation_pack_v2_error(
    "OPERATION_PACK_RUNTIME_UNAVAILABLE", "Phase 2A implements only the ABI v2 R adapter.",
    "authentication")
  .wb_operation_pack_assert(requireNamespace(package, quietly = TRUE, lib.loc = lib.loc),
    "OPERATION_PACK_PACKAGE_UNAVAILABLE", paste0("Installed package '", package, "' could not be loaded."))
  entry_parts <- strsplit(as.character(manifest$entry_point)[1], "::", fixed = TRUE)[[1]]
  if (length(entry_parts) != 2L || !identical(entry_parts[[1]], package)) .wb_operation_pack_v2_error(
    "OPERATION_PACK_ENTRY_POINT_INVALID", "V2 R entry point must be the exact installed package::export.",
    "authentication")
  exports <- getNamespaceExports(package)
  if (!entry_parts[[2]] %in% exports) .wb_operation_pack_v2_error("OPERATION_PACK_ENTRY_POINT_INVALID",
    "V2 R entry point is not exported by the installed package.", "authentication")
  entry <- getExportedValue(package, entry_parts[[2]])
  if (!is.function(entry) || length(formals(entry)) != 0L) .wb_operation_pack_v2_error(
    "OPERATION_PACK_ENTRY_POINT_INVALID", "V2 R entry point must be a zero-argument function.", "authentication")
  context <- new.env(parent = emptyenv())
  context$abi <- "2"; context$package <- package; context$manifest_path <- manifest_path
  context$package_description <- description; context$installed_path <- dirname(dirname(manifest_path))
  context$result <- NULL
  .wb_operation_pack_registry$registration_context <- context
  on.exit({ .wb_operation_pack_registry$registration_context <- NULL }, add = TRUE)
  returned <- tryCatch(entry(), error = function(error) {
    if (inherits(error, "wb_operation_pack_error")) stop(error)
    .wb_operation_pack_v2_error("OPERATION_PACK_ENTRY_POINT_FAILED",
      paste0("V2 R entry point failed: ", conditionMessage(error)), "authentication")
  })
  if (!inherits(returned, "wb_operation_pack_registration_v2") ||
      !inherits(context$result, "wb_operation_pack_registration_v2") || !identical(returned, context$result)) {
    .wb_operation_pack_v2_error("OPERATION_PACK_ENTRY_POINT_INVALID",
      "V2 R entry point must return exactly one wb_operation_pack_register() result.", "authentication")
  }
  returned
}

.wb_operation_pack_v2_manifest_conformance <- function(manifest) {
  path <- attr(manifest, "operation_pack_v2_source_path", exact = TRUE)
  source_sha <- attr(manifest, "operation_pack_v2_source_sha256", exact = TRUE)
  normalized <- .wb_operation_pack_v2_normalize(manifest)
  if (is.null(source_sha)) source_sha <- .wb_operation_pack_sha256(normalized)
  content <- .wb_operation_pack_v2_id("scworkbench.operation_pack.content.v1",
    list(structural_manifest_only = TRUE, manifest_source_sha256 = source_sha))
  identity <- .wb_operation_pack_v2_identity(normalized, source_sha, content)
  structure(list(
    schema_version = "scworkbench.operation_pack.manifest_conformance.v2", ok = TRUE,
    activated = FALSE, structural_only = TRUE, backend = normalized$backend,
    identity = identity, manifest = normalized,
    source = if (!is.null(path)) list(path = path, authenticated_original_bytes = TRUE) else list(authenticated_original_bytes = FALSE),
    claims = list(structurally_validated = TRUE, runtime_activated = FALSE,
      scientifically_validated = FALSE, host_sandboxed = FALSE, bundle_mutated = FALSE)
  ), class = c("wb_operation_pack_manifest_conformance_v2", "wb_operation_pack_manifest_conformance", "list"))
}
