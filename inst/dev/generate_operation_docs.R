#!/usr/bin/env Rscript

# Generate R/operation_docs.R from the runtime operation interface catalog.
# Run from the package root:
#   Rscript inst/dev/generate_operation_docs.R

`%||%` <- function(x, y) if (is.null(x)) y else x

.wb_operation_docs_shared <- function(name) {
  docs <- c(
    bundle = "Open `scworkbench_bundle` that owns input storage, output registration, and provenance.",
    cells = "Canonical cell ids defining the analysis universe; when omitted, the operation uses its documented cell-set behavior.",
    cell_set = "Named bundle cell set used to resolve the analysis universe.",
    matrix_id = "Registered logical matrix identifier consumed by this operation.",
    feature_table = "Feature-table data frame or primitive supplying selected features and annotations.",
    path = "Path-family primitive or compatible path reference.",
    cells_a = "Canonical cell ids for the first comparison group.",
    cells_b = "Canonical cell ids for the second comparison group.",
    space_id = "Registered coordinate-space identifier consumed by this operation.",
    fit_space_id = "Registered coordinate space used to fit the model.",
    plot_space_id = "Registered two-dimensional display space used for projection.",
    source_space_id = "Registered source coordinate space used for fitting.",
    model_ref = "Typed `model_ref` primitive required by this engine-specific helper.",
    monocle3_model = "Authenticated Monocle3 `model_ref` primitive.",
    slingshot_model = "Authenticated Slingshot `model_ref` primitive.",
    peakvi_model = "PeakVI `model_ref` primitive returned by the Python-backed fitting workflow.",
    seed = "Integer random seed used to make stochastic computation reproducible.",
    n_iterations = "Number of optimization or clustering iterations.",
    weight = "Whether weighted nearest-neighbor relationships are used by the engine.",
    verbose = "Whether the underlying engine emits progress output.",
    nn_control = "Optional nearest-neighbor control list passed to the underlying engine.",
    learn_graph_control = "Optional principal-graph learning control list passed to the underlying engine.",
    exclude_cells = "Optional cell ids excluded before fitting.",
    include_clusters = "Optional cluster labels retained before fitting.",
    shrink = "Engine shrinkage control for fitted trajectory curves.",
    maxit = "Maximum engine fitting iterations.",
    table = "Optional in-memory feature-set source table.",
    sets = "Optional named in-memory feature-set list.",
    organism = "Organism label recorded with the imported feature-set namespace.",
    created_by = "Optional actor label recorded in provenance.",
    origin = "Human-readable origin label recorded for imported source material.",
    is_readonly = "Whether imported feature sets are marked read-only after registration.",
    pseudotime_artifact_id = "Optional promoted pseudotime artifact id recorded in explicit-pseudotime provenance.",
    membership_artifact_id = "Optional promoted membership artifact id recorded in explicit-pseudotime provenance.",
    composite_id = "Stable identifier for a derived composite trajectory.",
    runs = "Optional session run registry used to resolve symbolic input references.",
    model_space_id = "Registered model-space identifier used to locate a stored projection model.",
    in_space_id = "Registered input-space identifier expected by the stored projection model.",
    python_bin = "Python executable used for an optional pybench-backed runtime.",
    chunk_size = "Maximum chunk size used for bounded-memory processing.",
    `...` = "Additional engine-specific arguments accepted by this wrapper."
  )
  if (!name %in% names(docs)) return(NA_character_)
  unname(docs[[name]])
}

.wb_operation_docs_input_alias <- function(name) {
  aliases <- c(
    matrix_id = "matrix", space_id = "space", fit_space_id = "fit_space",
    plot_space_id = "plot_space", source_space_id = "source_space",
    model = "model", pseudotime = "pseudotime", membership = "membership",
    signal = "signal", feature_table = "feature_table", feature_set = "feature_set",
    namespace = "namespace", path = "path", path_scores = "path_scores",
    segments = "segments", paths = "paths", clusters = "clusters"
  )
  if (!name %in% names(aliases)) return(name)
  unname(aliases[[name]])
}

.wb_operation_docs_input_text <- function(name, input) {
  kind <- as.character(input$kind %||% input$type %||% "input")[1]
  req <- if (isTRUE(input$required)) "Required" else "Optional"
  paste0(req, " `", name, "` input represented as `", kind,
         "`; accepted symbolic references are resolved by the operation interface.")
}

.wb_operation_docs_roxygen_text <- function(text) {
  # Catalog prose can contain numeric intervals such as [0,1]. Escape square
  # brackets so Roxygen does not interpret them as unresolved Rd links.
  text <- as.character(text)[1]
  text <- gsub("[", "\\\\[", text, fixed = TRUE)
  gsub("]", "\\\\]", text, fixed = TRUE)
}

.wb_operation_docs_contract_details <- function(iface) {
  outputs <- iface$produces %||% list()
  if (!length(outputs)) return("For the live typed interface, including accepted symbolic references, see [wb_op_interface()].")
  bits <- vapply(names(outputs), function(nm) {
    out <- outputs[[nm]]
    paste0("`outputs$", nm, "` (`", as.character(out$kind %||% "unknown")[1],
           "`): ", .wb_operation_docs_roxygen_text(out$description %||% "Declared operation output."))
  }, character(1))
  paste0(
    "For the live typed interface, including accepted symbolic references and defaults, see [wb_op_interface()]. ",
    "Before runner execution, the engine derives one canonical ordered effective-cell universe by intersecting every resolved cell-indexed required input and every present cell-indexed optional input; per-input coverage diagnostics are recorded in run provenance. ",
    "The runtime catalog declares: ", paste(bits, collapse = "; "),
    ". Promotion eligibility is declared by the operation catalog."
  )
}

.wb_operation_docs_build <- function(root = ".", namespace = NULL) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(root)
  if (is.null(namespace)) {
    devtools::load_all(".", quiet = TRUE)
    namespace <- asNamespace("scworkbench")
  }
  stopifnot(is.environment(namespace),
    identical(namespace, asNamespace("scworkbench")))
  ns <- namespace
  exported <- sort(grep("^wb_op_", getNamespaceExports("scworkbench"), value = TRUE))
  generated <- list()
  missing <- list()

  for (fun_name in exported) {
    op_name <- sub("^wb_op_", "", fun_name)
    iface <- try(get("wb_op_interface", envir = ns)(op_name), silent = TRUE)
    if (inherits(iface, "try-error")) next
    formal_names <- names(formals(get(fun_name, envir = ns)))
    params <- iface$params %||% list()
    param_help <- setNames(
      vapply(params, function(x) as.character(x$help %||% "")[1], character(1)),
      vapply(params, function(x) as.character(x$name %||% "")[1], character(1))
    )
    inputs <- iface$inputs %||% list()
    lines <- c(
      paste0("#' @name ", fun_name),
      paste0("#' @aliases ", fun_name),
      paste0("#' @description ", .wb_operation_docs_roxygen_text(iface$description %||% ""))
    )
    for (arg in formal_names) {
      text <- .wb_operation_docs_shared(arg)
      if (is.na(text) && arg %in% names(param_help) && nzchar(param_help[[arg]])) text <- param_help[[arg]]
      input_name <- .wb_operation_docs_input_alias(arg)
      if (is.na(text) && input_name %in% names(inputs)) text <- .wb_operation_docs_input_text(arg, inputs[[input_name]])
      if (is.na(text)) {
        missing[[fun_name]] <- c(missing[[fun_name]], arg)
        next
      }
      lines <- c(lines, paste0("#' @param ", arg, " ", .wb_operation_docs_roxygen_text(text)))
    }
    lines <- c(lines, paste0("#' @details ", .wb_operation_docs_contract_details(iface)), "NULL", "")
    generated[[fun_name]] <- lines
  }
  if (length(missing)) {
    msg <- vapply(names(missing), function(nm) paste0(nm, ": ", paste(missing[[nm]], collapse = ", ")), character(1))
    stop("Operation documentation metadata missing for formals:\n", paste(msg, collapse = "\n"), call. = FALSE)
  }
  list(
    text = c(
      "# Generated from the runtime operation interface catalog; do not edit by hand.",
      "# Source: .wb_op_catalog() via wb_op_interface().",
      "# Regenerate: Rscript inst/dev/generate_operation_docs.R",
      "",
      unlist(generated, use.names = FALSE)
    ),
    documented = names(generated),
    exported = exported
  )
}

.wb_operation_docs_write <- function(path = "R/operation_docs.R", root = ".") {
  built <- .wb_operation_docs_build(root)
  writeLines(built$text, path, useBytes = TRUE)
  invisible(built)
}

if (sys.nframe() == 0L) .wb_operation_docs_write()
