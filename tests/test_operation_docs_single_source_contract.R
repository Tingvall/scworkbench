test_operation_docs_single_source_contract <- function() {
  source("inst/dev/generate_operation_docs.R", local = TRUE)
  built <- .wb_operation_docs_build(".")
  checked_in <- readLines("R/operation_docs.R", warn = FALSE)
  stopifnot(identical(checked_in, built$text))
  stopifnot(!any(grepl("Operation-specific parameter", checked_in, fixed = TRUE)))
  stopifnot(!any(grepl("typed operation result", checked_in, fixed = TRUE)))

  ns <- asNamespace("scworkbench")
  exported <- sort(grep("^wb_op_", getNamespaceExports("scworkbench"), value = TRUE))
  op_rd_text <- character()
  for (fun_name in exported) {
    rd_path <- file.path("man", paste0(fun_name, ".Rd"))
    stopifnot(file.exists(rd_path))
    rd_text <- paste(readLines(rd_path, warn = FALSE), collapse = "\n")
    op_rd_text <- c(op_rd_text, rd_text)
    for (arg in names(formals(get(fun_name, envir = ns))) ) {
      if (identical(arg, "...")) next
      if (!grepl(paste0("\\\\item\\{", arg, "\\}"), rd_text)) {
        stop(fun_name, " missing Rd argument: ", arg, call. = FALSE)
      }
    }
  }
  stopifnot(!any(grepl("Operation-specific parameter", op_rd_text, fixed = TRUE)))
  stopifnot(!any(grepl("typed operation result", op_rd_text, fixed = TRUE)))

  # The generated adjunct must render the catalog's operation description and
  # declared output contract, rather than merely linking to the live interface.
  for (fun_name in built$documented) {
    op_name <- sub("^wb_op_", "", fun_name)
    iface <- wb_op_interface(op_name)
    formal_names <- names(formals(get(fun_name, envir = ns)))
    param_names <- vapply(iface$params %||% list(), function(x) as.character(x$name %||% "")[1], character(1))
    # These are session-level controls, not direct wb_op_* formals. The direct
    # wrapper documents its concrete cell-id inputs, while wb_op_interface()
    # remains the canonical typed surface for symbolic group/set references.
    session_only_params <- list(
      de_wilcox = c("group_a", "group_b"),
      matrix_log_normalize = "cell_set",
      rna_qc_metrics = "cell_set",
      metadata_cell_vector = "cell_set",
      cell_vector_association = "cell_set"
    )
    allowed_session_only <- session_only_params[[op_name]] %||% character()
    stopifnot(
      all(nzchar(param_names)),
      all(param_names %in% c(formal_names, allowed_session_only))
    )
    rd_text <- paste(readLines(file.path("man", paste0(fun_name, ".Rd")), warn = FALSE), collapse = "\n")
    description <- as.character(iface$description %||% "")[1]
    stopifnot(nzchar(description), grepl(description, rd_text, fixed = TRUE))
    outputs <- iface$produces %||% list()
    stopifnot(length(outputs) > 0L)
    for (output_name in names(outputs)) {
      output_description <- as.character(outputs[[output_name]]$description %||% "")[1]
      output_kind <- as.character(outputs[[output_name]]$kind %||% "")[1]
      expected_description <- .wb_operation_docs_roxygen_text(output_description)
      stopifnot(
        nzchar(output_description),
        any(grepl(expected_description, checked_in, fixed = TRUE)),
        grepl(paste0("outputs$", output_name), rd_text, fixed = TRUE),
        grepl(output_kind, rd_text, fixed = TRUE)
      )
    }
  }

  # Catalog-backed exports are generated from wb_op_interface(); remaining
  # exported helpers are documented beside their direct deterministic wrappers.
  direct_helpers <- setdiff(exported, built$documented)
  stopifnot(all(startsWith(direct_helpers, "wb_op_")))
  invisible(TRUE)
}
