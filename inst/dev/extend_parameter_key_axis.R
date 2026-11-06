#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")

name <- list(type = "string", pattern = "^[a-z][a-z0-9_]*$")
nonempty <- list(type = "string", minLength = 1L)
string_array <- function() list(type = "array", minItems = 1L,
  uniqueItems = TRUE, items = nonempty)
object <- function(required, properties) list(type = "object",
  additionalProperties = FALSE, required = unname(as.list(required)),
  properties = properties)

declaration <- object(c("source", "keys_parameter", "prefix_parameter",
  "separator"), list(
    source = list(const = "parameter_keys_with_optional_prefix_v1"),
    keys_parameter = name,
    prefix_parameter = name,
    separator = nonempty))
resolution <- object(c("source", "keys_parameter", "keys_parameter_value",
  "prefix_parameter", "prefix_value", "separator", "order", "keys"),
  list(
    source = list(const = "parameter_keys_with_optional_prefix_v1"),
    keys_parameter = name,
    keys_parameter_value = string_array(),
    prefix_parameter = name,
    prefix_value = list(type = c("string", "null"), minLength = 1L),
    separator = nonempty,
    order = list(const = "parameter_order_v1"),
    keys = string_array()))

brace_pairs <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  stack <- integer()
  pairs <- integer(length(chars))
  in_string <- escaped <- FALSE
  ancestors <- vector("list", length(chars))
  for (i in seq_along(chars)) {
    ch <- chars[[i]]
    if (in_string) {
      if (escaped) escaped <- FALSE else if (ch == "\\") escaped <- TRUE else
        if (ch == '"') in_string <- FALSE
      next
    }
    if (ch == '"') {
      in_string <- TRUE
    } else if (ch == "{") {
      stack <- c(stack, i)
    } else if (ch == "}") {
      start <- stack[[length(stack)]]
      pairs[[start]] <- i
      stack <- stack[-length(stack)]
    }
    ancestors[[i]] <- stack
  }
  list(pairs = pairs, ancestors = ancestors)
}

indent_json <- function(value, indent) {
  rendered <- jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE,
    null = "null", digits = NA)
  paste0(indent, gsub("\n", paste0("\n", indent), rendered,
    fixed = TRUE))
}

extend_text <- function(text) {
  marker <- '"const": "declared_keys_with_optional_prefix_v1"'
  positions <- gregexpr(marker, text, fixed = TRUE)[[1L]]
  if (identical(positions, -1L) || grepl(
      '"const": "parameter_keys_with_optional_prefix_v1"', text,
      fixed = TRUE)) return(text)
  structure <- brace_pairs(text)
  for (position in rev(positions)) {
    stack <- structure$ancestors[[position]]
    branch_start <- stack[[length(stack) - 2L]]
    branch_end <- structure$pairs[[branch_start]]
    branch <- substr(text, branch_start, branch_end)
    addition <- if (grepl('"base_keys"', branch, fixed = TRUE))
      resolution else declaration
    newlines <- gregexpr("\n", substr(text, 1L, branch_start),
      fixed = TRUE)[[1L]]
    line_start <- max(c(0L, newlines[newlines > 0L])) + 1L
    indent <- substr(text, line_start, branch_start - 1L)
    inserted <- paste0(",\n", indent_json(addition, indent))
    text <- paste0(substr(text, 1L, branch_end), inserted,
      substr(text, branch_end + 1L, nchar(text)))
  }
  text
}

files <- c("operation-pack-v3.schema.json",
  "operation-pack-transition-request-v3.schema.json",
  "operation-pack-transition-receipt-v3.schema.json",
  "operation-pack-v4.schema.json",
  "operation-pack-transition-request-v4.schema.json",
  "operation-pack-transition-receipt-v4.schema.json")
for (file in files) {
  path <- file.path(protocol, file)
  text <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
  writeChar(extend_text(text), path, eos = NULL, useBytes = TRUE)
}
