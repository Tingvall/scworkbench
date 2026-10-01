# Static checks complement semantic review; they do not execute examples.
scwb_audit_agent_documentation <- function(root = ".", pack_root = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  source(file.path(root, "inst/dev/documentation_policy.R"), local = TRUE)
  policy <- scwb_documentation_policy(root)
  paths <- vapply(policy$entries, `[[`, character(1), "path")
  paths <- sort(unique(c("AGENTS.md", paths[grepl("[.]md$", paths)],
    file.path("docs", list.files(file.path(root, "docs"), pattern = "[.]md$")),
    "inst/standard_profile/README.md", "containers/docker/README.md",
    "containers/licenses/README.md")))
  namespace <- parse(file.path(root, "NAMESPACE"))
  exports <- unlist(lapply(namespace, function(expr) {
    if (is.call(expr) && identical(expr[[1L]], as.name("export"))) {
      vapply(as.list(expr)[-1L], as.character, character(1))
    } else character()
  }), use.names = FALSE)
  signatures <- list()
  for (file in list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)) {
    for (expr in parse(file)) {
      if (!is.call(expr) || !identical(expr[[1L]], as.name("<-")) ||
          !is.symbol(expr[[2L]]) || !is.call(expr[[3L]]) ||
          !identical(expr[[3L]][[1L]], as.name("function"))) next
      signatures[[as.character(expr[[2L]])]] <- names(expr[[3L]][[2L]])
    }
  }
  operations <- list()
  if (!is.null(pack_root)) {
    profile <- jsonlite::read_json(file.path(root, "inst/standard_profile/profile.json"))
    for (pack in profile$packs) {
      manifest <- jsonlite::read_json(file.path(pack_root, pack$package,
                                               "inst/scworkbench/operation-pack.json"))
      for (op in manifest$operations) {
        operations[[op$qualified_name]] <- c(names(op$params_schema$properties),
          vapply(op$inputs, `[[`, character(1), "name"))
      }
    }
  }
  issues <- list()
  add_issue <- function(path, line, type, detail) {
    issues[[length(issues) + 1L]] <<- data.frame(path, line, type, detail)
  }
  calls <- 0L
  inspect <- function(expr, path, line) {
    if (missing(expr)) return()
    if (!is.call(expr) && !is.expression(expr) && !is.pairlist(expr)) return()
    if (is.call(expr)) {
      head <- expr[[1L]]
      name <- if (is.symbol(head)) as.character(head) else ""
      if (identical(name, "function")) {
        inspect(expr[[3L]], path, line)
        return()
      }
      if (is.call(head) && identical(head[[1L]], as.name("::")) &&
          identical(as.character(head[[2L]]), "scworkbench")) {
        name <- as.character(head[[3L]])
      }
      if (startsWith(name, "wb_")) {
        calls <<- calls + 1L
        if (!name %in% exports) add_issue(path, line, "nonpublic_api", name)
        args <- names(as.list(expr)[-1L])
        args <- args[!is.na(args) & nzchar(args)]
        formal <- signatures[[name]]
        if (!is.null(formal) && !"..." %in% formal) {
          invalid <- args[!vapply(args, function(arg) {
            sum(startsWith(formal, arg)) == 1L || arg %in% formal
          }, logical(1))]
          if (length(invalid)) add_issue(path, line, "unknown_argument",
                                        paste(name, paste(invalid, collapse = ",")))
        }
        if (name %in% c("wb_session_run_op", "wb_op_interface")) {
          matched <- tryCatch(match.call(
            definition = if (name == "wb_session_run_op") {
              function(session, bundle, op_name, ..., inputs = list(), notes = NULL) NULL
            } else function(op_name, ...) NULL, call = expr), error = function(e) NULL)
          op_name <- matched$op_name
          if (is.character(op_name) && length(op_name) == 1L) {
            legacy <- names(operations)[sub("^.*::", "", names(operations)) == op_name]
            if (length(legacy)) add_issue(path, line, "unqualified_pack_operation", op_name)
            allowed <- operations[[op_name]]
            inputs <- matched$inputs
            if (!is.null(allowed) && is.call(inputs) && identical(inputs[[1L]], as.name("list"))) {
              supplied <- names(as.list(inputs)[-1L])
              invalid <- setdiff(supplied[nzchar(supplied)],
                                 c(allowed, "cell_set", "cell_ids", "min_cells"))
              if (length(invalid)) add_issue(path, line, "unknown_operation_parameter",
                                            paste(op_name, paste(invalid, collapse = ",")))
            }
          }
        }
      }
    }
    for (child in as.list(expr)) {
      if (!identical(child, quote(expr = ))) inspect(child, path, line)
    }
  }
  blocks <- 0L
  for (path in paths) {
    lines <- readLines(file.path(root, path), warn = FALSE)
    references <- regmatches(lines, gregexpr(
      "`(?:docs|inst|R|tests|containers)/[A-Za-z0-9_./-]+[.](?:md|R|json|sh)`",
      lines, perl = TRUE))
    for (i in seq_along(references)) {
      for (reference in references[[i]]) {
        target <- substring(reference, 2L, nchar(reference) - 1L)
        pack_relative <- identical(target, "inst/scworkbench/operation-pack.json") &&
          path %in% c("docs/operation_packs.md", "docs/rna_map_ops.md")
        if (!pack_relative && !file.exists(file.path(root, target)) &&
            !file.exists(file.path(root, dirname(path), target))) {
          add_issue(path, i, "missing_source_reference", target)
        }
      }
    }
    in_fence <- FALSE
    is_r <- FALSE
    code <- character()
    start <- 0L
    for (i in seq_along(lines)) {
      if (grepl("^```", lines[[i]])) {
        if (!in_fence) {
          in_fence <- TRUE
          is_r <- grepl("^```[rR][[:space:]]*$", lines[[i]])
          start <- i + 1L
          code <- character()
        } else {
          if (is_r) {
            blocks <- blocks + 1L
            parsed <- tryCatch(parse(text = code), error = identity)
            if (inherits(parsed, "error")) {
              add_issue(path, start, "unparseable_example", conditionMessage(parsed))
            } else inspect(parsed, path, start)
          }
          in_fence <- FALSE
        }
      } else if (in_fence && is_r) code <- c(code, lines[[i]])
    }
    if (in_fence) add_issue(path, length(lines), "unclosed_fence", "Markdown fence")
  }
  list(paths = paths, r_blocks = blocks, api_calls = calls,
       issues = if (length(issues)) do.call(rbind, issues) else
         data.frame(path = character(), line = integer(), type = character(), detail = character()))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  report_index <- match("--report", args)
  report <- NULL
  if (!is.na(report_index)) {
    if (report_index == length(args)) stop("--report requires an output path")
    report <- args[[report_index + 1L]]
    args <- args[-c(report_index, report_index + 1L)]
  }
  result <- scwb_audit_agent_documentation(pack_root = if (length(args)) args[[1L]] else NULL)
  cat(sprintf("Scanned %d documents, %d R blocks, %d API calls\n",
              length(result$paths), result$r_blocks, result$api_calls))
  print(result$issues, row.names = FALSE)
  if (!is.null(report)) {
    inventory <- lapply(result$paths, function(path) list(
      path = path, sha256 = digest::digest(file = path, algo = "sha256")))
    jsonlite::write_json(list(
      scope = "Maintained core Markdown, installed onboarding, SDK and generated references",
      validation = "Static API/reference checks; examples are not executed by this audit",
      documents = inventory, r_blocks = result$r_blocks, api_calls = result$api_calls,
      issues = result$issues), report, auto_unbox = TRUE, pretty = TRUE)
  }
  quit(status = as.integer(nrow(result$issues) > 0L))
}
