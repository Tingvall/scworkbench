# R/session_dag.R

.wb_dag_or <- function(x, y) if (is.null(x)) y else x

.wb_dag_topo_order <- function(session) {
  runs <- session$runs %||% list()
  if (!length(runs)) return(character(0))

  seen <- new.env(parent = emptyenv())
  out <- character(0)

  visit <- function(rid) {
    rid <- as.character(rid)[1]
    if (!nzchar(rid)) return(invisible(NULL))
    if (exists(rid, envir = seen, inherits = FALSE)) return(invisible(NULL))
    assign(rid, TRUE, envir = seen)

    run <- runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) return(invisible(NULL))
    parents <- as.character(run$inputs$parents %||% character(0))
    parents <- parents[nzchar(parents)]
    for (p in parents) visit(p)
    out <<- c(out, rid)
    invisible(NULL)
  }

  head <- as.character(session$head_run_id %||% "")[1]
  if (nzchar(head)) visit(head)

  # include disconnected runs deterministically
  all_ids <- as.character(names(runs))
  all_ids <- all_ids[nzchar(all_ids)]
  for (rid in sort(setdiff(all_ids, out))) visit(rid)

  unique(out)
}

.wb_dag_collect_refs <- function(x, path = "root") {
  out <- list()
  i <- 0L

  rec <- function(v, pth) {
    if (!is.list(v)) return(invisible(NULL))
    rt <- as.character(v$ref_type %||% "")[1]
    if (rt %in% c("run", "artifact")) {
      i <<- i + 1L
      out[[i]] <<- data.frame(
        path = as.character(pth),
        ref_type = rt,
        run_id = as.character(v$run_id %||% NA_character_)[1],
        artifact_id = as.character(v$artifact_id %||% NA_character_)[1],
        output = as.character(v$output %||% NA_character_)[1],
        stringsAsFactors = FALSE
      )
      return(invisible(NULL))
    }
    nms <- names(v) %||% rep("", length(v))
    if (!length(v)) return(invisible(NULL))
    for (j in seq_along(v)) {
      nm <- as.character(nms[[j]] %||% "")[1]
      if (!nzchar(nm)) nm <- paste0("[[", j, "]]")
      rec(v[[j]], paste0(pth, "$", nm))
    }
    invisible(NULL)
  }

  rec(x, path)
  if (!length(out)) {
    return(data.frame(
      path = character(0),
      ref_type = character(0),
      run_id = character(0),
      artifact_id = character(0),
      output = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, out)
}

.wb_dag_artifact_source_run <- function(provenance_json) {
  txt <- as.character(provenance_json %||% "")[1]
  if (!nzchar(txt)) return(NA_character_)
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(NA_character_)
  x <- try(jsonlite::fromJSON(txt, simplifyVector = TRUE), silent = TRUE)
  if (inherits(x, "try-error")) return(NA_character_)
  rid <- as.character(x$run_id %||% NA_character_)[1]
  if (!nzchar(rid)) NA_character_ else rid
}

#' Build A Session DAG View
#'
#' Returns a canonical graph payload with run nodes as the primary vertices.
#' Optional artifact and active-binding nodes are attached when requested.
#'
#' @param session `wb_session` object.
#' @param bundle Optional bundle, used for artifact linkage.
#' @param include_artifacts If `TRUE` and `bundle` is provided, attach promoted
#'   artifact nodes.
#' @param include_active If `TRUE`, attach active-binding nodes.
#'
#' @return A named list with `nodes`, `edges`, `head_run_id`, and `run_order`.
#'
#' @export
wb_session_dag <- function(session,
                           bundle = NULL,
                           include_artifacts = TRUE,
                           include_active = TRUE) {
  .wb_assert(wb_is_session(session), "session must be wb_session")
  if (!is.null(bundle)) .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  runs <- session$runs %||% list()
  run_order <- .wb_dag_topo_order(session)

  nodes <- list()
  edges <- list()
  ni <- 0L
  ei <- 0L

  add_node <- function(id, node_type, label = NA_character_, run_id = NA_character_,
                       op_name = NA_character_, created_at = NA_character_,
                       output = NA_character_, artifact_id = NA_character_,
                       artifact_type = NA_character_) {
    ni <<- ni + 1L
    nodes[[ni]] <<- data.frame(
      id = as.character(id)[1],
      node_type = as.character(node_type)[1],
      label = as.character(label)[1],
      run_id = as.character(run_id)[1],
      op_name = as.character(op_name)[1],
      created_at = as.character(created_at)[1],
      output = as.character(output)[1],
      artifact_id = as.character(artifact_id)[1],
      artifact_type = as.character(artifact_type)[1],
      stringsAsFactors = FALSE
    )
  }

  add_edge <- function(from, to, edge_type, label = NA_character_) {
    ei <<- ei + 1L
    edges[[ei]] <<- data.frame(
      from = as.character(from)[1],
      to = as.character(to)[1],
      edge_type = as.character(edge_type)[1],
      label = as.character(label)[1],
      stringsAsFactors = FALSE
    )
  }

  # run nodes
  for (rid in run_order) {
    run <- runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) next
    add_node(
      id = paste0("run:", rid),
      node_type = "run",
      label = as.character(run$op_name %||% rid),
      run_id = rid,
      op_name = as.character(run$op_name %||% NA_character_),
      created_at = as.character(run$created_at %||% NA_character_)
    )
  }

  # run dependencies
  for (rid in run_order) {
    run <- runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) next
    parents <- as.character(run$inputs$parents %||% character(0))
    parents <- parents[nzchar(parents)]
    for (pid in unique(parents)) {
      if (!pid %in% names(runs)) next
      add_edge(
        from = paste0("run:", pid),
        to = paste0("run:", rid),
        edge_type = "depends_on_run"
      )
    }
  }

  # explicit refs from user_inputs
  for (rid in run_order) {
    run <- runs[[rid]]
    if (is.null(run) || !wb_is_run(run)) next
    refs <- .wb_dag_collect_refs(run$inputs$user_inputs %||% list(), path = "inputs$user_inputs")
    if (!nrow(refs)) next
    refs <- refs[refs$ref_type == "run" & nzchar(refs$run_id), , drop = FALSE]
    if (!nrow(refs)) next
    for (j in seq_len(nrow(refs))) {
      pid <- as.character(refs$run_id[j])
      if (!pid %in% names(runs)) next
      add_edge(
        from = paste0("run:", pid),
        to = paste0("run:", rid),
        edge_type = "input_run_ref",
        label = as.character(refs$output[j] %||% NA_character_)
      )
    }
  }

  # active bindings
  if (isTRUE(include_active)) {
    active <- session$active %||% list()
    if (length(active)) {
      anm <- sort(names(active))
      for (nm in anm) {
        ref <- active[[nm]]
        aid <- paste0("active:", nm)
        add_node(
          id = aid,
          node_type = "active",
          label = nm,
          output = nm
        )
        if (is.list(ref) && identical(ref$ref_type %||% "", "run")) {
          rid <- as.character(ref$run_id %||% "")[1]
          if (rid %in% names(runs)) {
            add_edge(
              from = paste0("run:", rid),
              to = aid,
              edge_type = "binds_active",
              label = as.character(ref$output %||% nm)[1]
            )
          }
        }
      }
    }
  }

  # artifact linkage (if available)
  if (isTRUE(include_artifacts) && !is.null(bundle) && exists("wb_art_list", mode = "function")) {
    arts <- try(wb_art_list(bundle), silent = TRUE)
    if (!inherits(arts, "try-error") && is.data.frame(arts) && nrow(arts)) {
      for (j in seq_len(nrow(arts))) {
        aid <- as.character(arts$artifact_id[j] %||% "")[1]
        if (!nzchar(aid)) next
        src_run <- .wb_dag_artifact_source_run(arts$provenance_json[j] %||% "")
        if (!nzchar(src_run) || !src_run %in% names(runs)) next

        anode <- paste0("artifact:", aid)
        add_node(
          id = anode,
          node_type = "artifact",
          label = as.character(arts$name[j] %||% aid)[1],
          artifact_id = aid,
          artifact_type = as.character(arts$type[j] %||% NA_character_)[1],
          created_at = as.character(arts$created_at[j] %||% NA_character_)[1]
        )
        add_edge(
          from = paste0("run:", src_run),
          to = anode,
          edge_type = "promoted_to_artifact",
          label = as.character(arts$type[j] %||% NA_character_)[1]
        )
      }
    }
  }

  nodes_df <- if (length(nodes)) do.call(rbind, nodes) else data.frame(
    id = character(0), node_type = character(0), label = character(0),
    run_id = character(0), op_name = character(0), created_at = character(0),
    output = character(0), artifact_id = character(0), artifact_type = character(0),
    stringsAsFactors = FALSE
  )

  edges_df <- if (length(edges)) do.call(rbind, edges) else data.frame(
    from = character(0), to = character(0), edge_type = character(0), label = character(0),
    stringsAsFactors = FALSE
  )

  if (nrow(nodes_df)) nodes_df <- unique(nodes_df)
  if (nrow(edges_df)) {
    edges_df <- unique(edges_df)
    edges_df <- edges_df[order(edges_df$from, edges_df$to, edges_df$edge_type), , drop = FALSE]
  }

  list(
    nodes = nodes_df,
    edges = edges_df,
    head_run_id = as.character(session$head_run_id %||% NA_character_)[1],
    run_order = run_order
  )
}

#' Inspect One Session DAG Run Node
#'
#' Read one run in the same vocabulary used by [wb_session_dag()], including
#' parent/child relationships, input refs, outputs, active bindings, and
#' promoted artifacts when available.
#'
#' @param session `wb_session` object.
#' @param run_id Run id present in `session$runs`.
#' @param bundle Optional bundle; when provided, includes promoted artifacts
#'   from this run.
#'
#' @return A named list with run metadata, refs, output summaries, and local
#'   neighborhood info.
#'
#' @export
wb_session_dag_run_details <- function(session, run_id, bundle = NULL) {
  .wb_assert(wb_is_session(session), "session must be wb_session")
  if (!is.null(bundle)) .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  rid <- as.character(run_id)[1]
  .wb_assert(nzchar(rid), "run_id must be non-empty")
  run <- session$runs[[rid]]
  .wb_assert(!is.null(run) && wb_is_run(run), paste0("run not found in session: ", rid))

  # downstream children
  children <- character(0)
  runs <- session$runs %||% list()
  if (length(runs)) {
    for (cid in names(runs)) {
      r <- runs[[cid]]
      if (is.null(r) || !wb_is_run(r)) next
      p <- as.character(r$inputs$parents %||% character(0))
      if (rid %in% p) children <- c(children, cid)
    }
  }
  children <- sort(unique(children))

  parents <- sort(unique(as.character(run$inputs$parents %||% character(0))))
  parents <- parents[nzchar(parents)]

  refs <- .wb_dag_collect_refs(run$inputs$user_inputs %||% list(), path = "inputs$user_inputs")
  if (nrow(refs)) refs <- refs[order(refs$path), , drop = FALSE]

  active_names <- character(0)
  act <- session$active %||% list()
  if (length(act)) {
    for (nm in names(act)) {
      ref <- act[[nm]]
      if (is.list(ref) && identical(ref$ref_type %||% "", "run") && identical(as.character(ref$run_id)[1], rid)) {
        active_names <- c(active_names, nm)
      }
    }
  }
  active_names <- sort(unique(active_names))

  outs <- run$outputs %||% list()
  out_rows <- list()
  oi <- 0L
  if (length(outs)) {
    for (nm in names(outs)) {
      prim <- outs[[nm]]
      s <- if (.wb_is_primitive(prim)) .wb_prim_summary(prim) else list(kind = "unknown")
      oi <- oi + 1L
      out_rows[[oi]] <- data.frame(
        output = as.character(nm),
        kind = as.character(s$kind %||% "unknown"),
        stringsAsFactors = FALSE
      )
    }
  }
  outputs <- if (length(out_rows)) do.call(rbind, out_rows) else data.frame(
    output = character(0),
    kind = character(0),
    stringsAsFactors = FALSE
  )

  promoted <- data.frame(
    artifact_id = character(0),
    type = character(0),
    name = character(0),
    created_at = character(0),
    stringsAsFactors = FALSE
  )
  if (!is.null(bundle) && exists("wb_art_list", mode = "function")) {
    arts <- try(wb_art_list(bundle), silent = TRUE)
    if (!inherits(arts, "try-error") && is.data.frame(arts) && nrow(arts)) {
      src <- vapply(arts$provenance_json %||% "", .wb_dag_artifact_source_run, character(1))
      keep <- which(src == rid)
      if (length(keep)) {
        promoted <- arts[keep, c("artifact_id", "type", "name", "created_at"), drop = FALSE]
      }
    }
  }

  list(
    run = list(
      run_id = rid,
      op_name = as.character(run$op_name %||% NA_character_)[1],
      created_at = as.character(run$created_at %||% NA_character_)[1],
      notes = run$notes %||% NULL,
      params = run$params %||% list(),
      inputs = run$inputs %||% list()
    ),
    parents = parents,
    children = children,
    input_refs = refs,
    outputs = outputs,
    active_bindings = active_names,
    promoted_artifacts = promoted
  )
}
