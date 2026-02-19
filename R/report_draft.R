# R/report_draft.R

.wb_report_or <- function(x, y) if (is.null(x)) y else x

.wb_report_param_value <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.atomic(x)) {
    if (!length(x)) return("<empty>")
    y <- as.character(x)
    if (length(y) > 5) y <- c(y[1:5], "...")
    return(paste(y, collapse = ","))
  }
  if (is.list(x)) return("<list>")
  as.character(x)
}

.wb_report_params_inline <- function(params) {
  params <- params %||% list()
  if (!is.list(params) || !length(params)) return("none")
  nms <- names(params) %||% rep("", length(params))
  parts <- character(0)
  for (i in seq_along(params)) {
    nm <- as.character(nms[[i]] %||% "")[1]
    if (!nzchar(nm)) nm <- paste0("param", i)
    parts <- c(parts, paste0(nm, "=", .wb_report_param_value(params[[i]])))
  }
  paste(parts, collapse = "; ")
}

.wb_report_output_summary <- function(run) {
  outs <- run$outputs %||% list()
  if (!length(outs)) {
    return(data.frame(
      output = character(0),
      kind = character(0),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(names(outs), function(nm) {
    p <- outs[[nm]]
    kind <- if (.wb_is_primitive(p)) as.character(p$kind %||% "unknown")[1] else "unknown"
    data.frame(output = as.character(nm), kind = kind, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' Draft a methods narrative from session runs
#'
#' @param session wb_session object
#' @param bundle Optional bundle for enrichment
#' @param run_ids Optional run_ids; default uses session DAG order
#' @return list(title, text, lines, run_table)
#' @export
wb_report_methods <- function(session, bundle = NULL, run_ids = NULL) {
  .wb_assert(wb_is_session(session), "session must be wb_session")
  if (!is.null(bundle)) .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  order_ids <- if (is.null(run_ids)) {
    wb_session_dag(session, bundle = bundle, include_artifacts = FALSE, include_active = FALSE)$run_order
  } else {
    as.character(run_ids)
  }
  order_ids <- order_ids[nzchar(order_ids)]

  lines <- character(0)
  run_rows <- list()
  ri <- 0L
  for (rid in order_ids) {
    run <- session$runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) next

    eff_n <- as.integer(run$inputs$effective_n %||% NA_integer_)[1]
    cell_set <- as.character(run$inputs$cell_set %||% NA_character_)[1]
    params_inline <- .wb_report_params_inline(run$params %||% list())
    outs <- .wb_report_output_summary(run)
    out_inline <- if (nrow(outs)) paste0(outs$output, ":", outs$kind, collapse = ", ") else "none"

    lines <- c(lines, paste0(
      "Run ", rid, " executed op '", run$op_name, "'",
      if (!is.na(eff_n)) paste0(" on ", eff_n, " effective cells") else "",
      if (nzchar(cell_set)) paste0(" (cell_set=", cell_set, ")") else "",
      ". Params: ", params_inline, ". Outputs: ", out_inline, "."
    ))

    ri <- ri + 1L
    run_rows[[ri]] <- data.frame(
      run_id = rid,
      op_name = as.character(run$op_name %||% NA_character_)[1],
      created_at = as.character(run$created_at %||% NA_character_)[1],
      cell_set = cell_set,
      effective_n = eff_n,
      params = params_inline,
      outputs = out_inline,
      stringsAsFactors = FALSE
    )
  }

  run_table <- if (length(run_rows)) do.call(rbind, run_rows) else data.frame(
    run_id = character(0),
    op_name = character(0),
    created_at = character(0),
    cell_set = character(0),
    effective_n = integer(0),
    params = character(0),
    outputs = character(0),
    stringsAsFactors = FALSE
  )

  list(
    title = "Methods (Draft)",
    text = paste(lines, collapse = "\n"),
    lines = lines,
    run_table = run_table
  )
}

#' Build a structured analysis report draft from engine truth
#'
#' @param bundle scworkbench bundle handle
#' @param session wb_session object
#' @param head_run_id Optional run_id to emphasize in summary
#' @param question Optional research question string
#' @param include_dag If TRUE, include `wb_session_dag()` payload
#' @param style Optional style tags (e.g. c("methods","results"))
#' @return list(metadata, summary, methods, results, dag)
#' @export
wb_report_draft <- function(bundle,
                            session,
                            head_run_id = NULL,
                            question = NULL,
                            include_dag = TRUE,
                            style = c("methods", "results")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(wb_is_session(session), "session must be wb_session")

  dag <- if (isTRUE(include_dag)) {
    wb_session_dag(session, bundle = bundle, include_artifacts = TRUE, include_active = TRUE)
  } else NULL

  methods <- wb_report_methods(session = session, bundle = bundle)

  run_ids <- if (!is.null(dag)) dag$run_order else names(session$runs %||% list())
  run_ids <- as.character(run_ids)
  run_ids <- run_ids[nzchar(run_ids)]

  result_rows <- list()
  i <- 0L
  for (rid in run_ids) {
    run <- session$runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) next
    outs <- .wb_report_output_summary(run)
    if (!nrow(outs)) next
    for (j in seq_len(nrow(outs))) {
      i <- i + 1L
      result_rows[[i]] <- data.frame(
        run_id = rid,
        op_name = as.character(run$op_name %||% NA_character_)[1],
        output = as.character(outs$output[j]),
        kind = as.character(outs$kind[j]),
        stringsAsFactors = FALSE
      )
    }
  }
  results <- if (length(result_rows)) do.call(rbind, result_rows) else data.frame(
    run_id = character(0), op_name = character(0), output = character(0), kind = character(0),
    stringsAsFactors = FALSE
  )

  promoted <- data.frame(
    artifact_id = character(0),
    type = character(0),
    name = character(0),
    source_op = character(0),
    created_at = character(0),
    stringsAsFactors = FALSE
  )
  if (exists("wb_art_list", mode = "function")) {
    arts <- try(wb_art_list(bundle), silent = TRUE)
    if (!inherits(arts, "try-error") && is.data.frame(arts) && nrow(arts)) {
      keep <- intersect(c("artifact_id", "type", "name", "source_op", "created_at"), colnames(arts))
      promoted <- arts[, keep, drop = FALSE]
    }
  }

  head_id <- as.character(head_run_id %||% session$head_run_id %||% NA_character_)[1]
  if (!nzchar(head_id)) head_id <- NA_character_

  list(
    metadata = list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      scworkbench_version = as.character(utils::packageVersion("scworkbench")),
      bundle_dir = bundle$dir %||% NA_character_,
      style = as.character(style %||% character(0)),
      question = as.character(question %||% NA_character_)[1]
    ),
    summary = list(
      head_run_id = head_id,
      n_runs = length(run_ids),
      n_outputs = nrow(results),
      n_promoted = nrow(promoted)
    ),
    methods = methods,
    results = list(
      outputs = results,
      promoted_artifacts = promoted
    ),
    dag = dag
  )
}

#' Render a report draft as Markdown
#'
#' @param report Output from `wb_report_draft()`
#' @param include_dag_text If TRUE, include a compact DAG summary section
#' @return length-1 markdown string
#' @export
wb_report_render_md <- function(report, include_dag_text = TRUE) {
  .wb_assert(is.list(report), "report must be a list from wb_report_draft()")
  md <- character(0)

  q <- as.character(report$metadata$question %||% NA_character_)[1]
  md <- c(md, "# Analysis Report (Draft)", "")
  if (!is.na(q) && nzchar(q)) {
    md <- c(md, "## Question", "", q, "")
  }

  md <- c(md, "## Summary", "")
  md <- c(
    md,
    paste0("- Generated at: ", as.character(report$metadata$generated_at %||% NA_character_)[1]),
    paste0("- Runs: ", as.integer(report$summary$n_runs %||% 0L)),
    paste0("- Outputs: ", as.integer(report$summary$n_outputs %||% 0L)),
    paste0("- Promoted artifacts: ", as.integer(report$summary$n_promoted %||% 0L)),
    paste0("- Head run: ", as.character(report$summary$head_run_id %||% NA_character_)[1]),
    ""
  )

  md <- c(md, "## Methods", "")
  meth <- as.character(report$methods$text %||% "")[1]
  if (nzchar(meth)) {
    md <- c(md, meth, "")
  } else {
    md <- c(md, "No methods text available.", "")
  }

  outs <- report$results$outputs %||% data.frame()
  md <- c(md, "## Outputs", "")
  if (is.data.frame(outs) && nrow(outs)) {
    md <- c(md, "| run_id | op_name | output | kind |", "|---|---|---|---|")
    for (i in seq_len(nrow(outs))) {
      md <- c(md, paste0(
        "| ", outs$run_id[i], " | ", outs$op_name[i], " | ",
        outs$output[i], " | ", outs$kind[i], " |"
      ))
    }
    md <- c(md, "")
  } else {
    md <- c(md, "No outputs.", "")
  }

  arts <- report$results$promoted_artifacts %||% data.frame()
  md <- c(md, "## Promoted Artifacts", "")
  if (is.data.frame(arts) && nrow(arts)) {
    keep <- intersect(c("artifact_id", "type", "name", "source_op", "created_at"), colnames(arts))
    md <- c(md, paste0("Count: ", nrow(arts)), "")
    if (length(keep) >= 2) {
      hdr <- paste0("| ", paste(keep, collapse = " | "), " |")
      sep <- paste0("|", paste(rep("---", length(keep)), collapse = "|"), "|")
      md <- c(md, hdr, sep)
      for (i in seq_len(nrow(arts))) {
        row_vals <- vapply(keep, function(k) as.character(arts[[k]][i] %||% ""), character(1))
        md <- c(md, paste0("| ", paste(row_vals, collapse = " | "), " |"))
      }
      md <- c(md, "")
    }
  } else {
    md <- c(md, "No promoted artifacts.", "")
  }

  if (isTRUE(include_dag_text)) {
    dag <- report$dag %||% NULL
    md <- c(md, "## DAG", "")
    if (is.list(dag) && is.data.frame(dag$nodes) && is.data.frame(dag$edges)) {
      md <- c(
        md,
        paste0("- Nodes: ", nrow(dag$nodes)),
        paste0("- Edges: ", nrow(dag$edges)),
        paste0("- Run order: ", paste(as.character(dag$run_order %||% character(0)), collapse = " -> ")),
        ""
      )
    } else {
      md <- c(md, "DAG not included.", "")
    }
  }

  paste(md, collapse = "\n")
}
