# Target-centric, durable reproduction plans.  This intentionally uses the
# provenance tables as an implementation detail; callers receive only typed
# node ids and a portable plan.

.wb_target_parse <- function(target) {
  target <- as.character(target %||% "")[1]
  p <- regexec("^([A-Za-z_]+):(.+)$", target)
  m <- regmatches(target, p)[[1]]
  .wb_assert(length(m) == 3L && m[2] %in% c("artifact", "matrix", "space", "model", "run"),
             "target must be artifact:<id>, matrix:<id>, space:<id>, model:<id>, or run:<id>.")
  list(id = target, type = m[2], entity_id = m[3])
}

.wb_target_toposort <- function(run_ids, edges) {
  ids <- sort(unique(as.character(run_ids)))
  ee <- unique(edges[edges$parent_run_id %in% ids & edges$child_run_id %in% ids,
                     c("parent_run_id", "child_run_id"), drop = FALSE])
  indeg <- stats::setNames(integer(length(ids)), ids)
  kids <- stats::setNames(vector("list", length(ids)), ids)
  for (i in seq_len(nrow(ee))) {
    p <- as.character(ee$parent_run_id[i]); ch <- as.character(ee$child_run_id[i])
    kids[[p]] <- unique(c(kids[[p]], ch)); indeg[[ch]] <- indeg[[ch]] + 1L
  }
  ans <- character(0); ready <- sort(names(indeg)[indeg == 0L])
  while (length(ready)) {
    cur <- ready[1]; ready <- ready[-1]; ans <- c(ans, cur)
    for (ch in kids[[cur]]) {
      indeg[[ch]] <- indeg[[ch]] - 1L
      if (indeg[[ch]] == 0L) ready <- sort(unique(c(ready, ch)))
    }
  }
  list(order = ans, cyclic = setdiff(ids, ans))
}

.wb_target_source_state <- function(bundle, parsed, diagnostics) {
  structure(list(
    status = "source_state",
    reproducible = FALSE, target = c(parsed, list(producing_run_id = NA_character_, output_name = NA_character_)),
    run_order = character(0), runs = data.frame(), subgraph = list(nodes = data.frame(), edges = data.frame()),
    boundary_prerequisites = data.frame(), terminal_outputs = data.frame(), excluded_siblings = data.frame(),
    diagnostics = c(diagnostics, list(list(code = "source_state", message = "No engine-producing provenance run resolves this durable source state.")))
  ), class = "wb_target_reproduction_plan")
}

#' Build a minimal, target-centric reproduction plan
#'
#' `target` is a stable composed-DAG node id: `artifact:`, `matrix:`,
#' `space:`, `model:`, or `run:`.  The result deliberately distinguishes a
#' durable imported/source entity from a replayable engine result.
#'
#' @param bundle Open scworkbench bundle.
#' @param target Stable target node id.
#' @return A `wb_target_reproduction_plan` list.
#' @export
wb_target_reproduction_plan <- function(bundle, target) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "target reproduction plan")
  .wb_assert_observational_schema(
    bundle,
    c("prov_heads", "prov_runs", "prov_run_outputs", "prov_run_edges", "prov_run_entity_bindings"),
    action = "target reproduction planning"
  )
  x <- .wb_target_parse(target); con <- bundle$con
  out <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id, run_id, output_name, primitive_kind, artifact_id, ",
    .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con),
    " FROM prov_run_outputs ORDER BY snapshot_id, run_id, output_name;"))
  bind <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, direction, binding_name, entity_kind, entity_id FROM prov_run_entity_bindings WHERE direction = 'output' ORDER BY snapshot_id, run_id, binding_name;")
  ingestion_runs <- DBI::dbGetQuery(
    con,
    "SELECT DISTINCT r.run_id FROM prov_runs r JOIN prov_heads h ON h.snapshot_id = r.snapshot_id WHERE h.name_prefix = 'ingestion';"
  )$run_id
  ingestion_runs <- unique(as.character(ingestion_runs %||% character(0)))
  replay_out <- out[!(as.character(out$run_id) %in% ingestion_runs), , drop = FALSE]
  replay_bind <- bind[!(as.character(bind$run_id) %in% ingestion_runs), , drop = FALSE]
  candidates <- data.frame(snapshot_id=character(), run_id=character(), output_name=character(), stringsAsFactors=FALSE)
  if (x$type == "artifact") candidates <- replay_out[!is.na(replay_out$artifact_id) & as.character(replay_out$artifact_id) == x$entity_id, c("snapshot_id","run_id","output_name"), drop=FALSE]
  if (x$type == "run") candidates <- unique(replay_out[as.character(replay_out$run_id) == x$entity_id, c("snapshot_id","run_id","output_name"), drop=FALSE])
  if (x$type %in% c("matrix", "space", "model")) {
    ek <- if (x$type == "model") "model_ref" else x$type
    bb <- replay_bind[as.character(replay_bind$entity_kind) == ek & as.character(replay_bind$entity_id) == x$entity_id, , drop=FALSE]
    if (nrow(bb)) candidates <- merge(bb[,c("snapshot_id","run_id","binding_name")], replay_out, by=c("snapshot_id","run_id"), all.x=TRUE)
    if (nrow(candidates)) candidates$output_name <- as.character(candidates$binding_name)
    candidates <- candidates[, intersect(c("snapshot_id","run_id","output_name"), names(candidates)), drop=FALSE]
  }
  candidates <- unique(candidates[nzchar(as.character(candidates$run_id)), , drop=FALSE])
  if (!nrow(candidates)) return(.wb_target_source_state(bundle, x, list(list(code="unresolved_target", message=paste0("No output producer for ", x$id, ".")))))
  if (length(unique(as.character(candidates$run_id))) != 1L) return(structure(list(status="ambiguous", reproducible=FALSE, target=x, candidates=candidates, run_order=character(0), runs=data.frame(), subgraph=list(nodes=data.frame(),edges=data.frame()), boundary_prerequisites=data.frame(), terminal_outputs=data.frame(), excluded_siblings=data.frame(), diagnostics=list(list(code="ambiguous_producer",message="Target has multiple producing runs; select an artifact or run-specific target."))), class="wb_target_reproduction_plan"))
  target_run <- as.character(candidates$run_id[1]); target_out <- as.character(candidates$output_name[1] %||% "")[1]
  edges <- DBI::dbGetQuery(con, "SELECT DISTINCT parent_run_id, child_run_id, edge_type, edge_label FROM prov_run_edges WHERE edge_type IN ('depends_on_run','input_run_ref') ORDER BY parent_run_id, child_run_id, edge_type;")
  # Durable string inputs cross promotion snapshots without a run edge.  Walk
  # their typed entity bindings to the unique producer; record absent durable
  # producers as explicit immutable/source boundaries and fail on ambiguity.
  parents <- split(as.character(edges$parent_run_id), as.character(edges$child_run_id)); closure <- character(0); stack <- target_run
  typed_edges <- data.frame(parent_run_id=character(), child_run_id=character(), edge_type=character(), edge_label=character(), stringsAsFactors=FALSE)
  cell_set_binding_select <- paste(
    if (.wb_db_has_column(con,"prov_run_entity_bindings","source_membership_sha256")) "source_membership_sha256" else "NULL AS source_membership_sha256",
    if (.wb_db_has_column(con,"prov_run_entity_bindings","source_membership_identity_scheme")) "source_membership_identity_scheme" else "NULL AS source_membership_identity_scheme",
    if (.wb_db_has_column(con,"prov_run_entity_bindings","source_member_count")) "source_member_count" else "NULL AS source_member_count",
    sep=", "
  )
  bind_all <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id, run_id, direction, binding_name, entity_kind, entity_id, content_hash, ", cell_set_binding_select, " FROM prov_run_entity_bindings ORDER BY snapshot_id, run_id, direction, binding_name;"))
  boundary <- data.frame(run_id=character(), entity_kind=character(), entity_id=character(), binding_name=character(), content_hash=character(), content_identity_scheme=character(), member_count=integer(), reason=character(), stringsAsFactors=FALSE)
  ambiguous <- list()
  while(length(stack)) {
    cur <- stack[1]; stack <- stack[-1]; if (cur %in% closure) next; closure <- c(closure,cur)
    typed <- character(0)
    ins <- bind_all[as.character(bind_all$direction) == "input" & as.character(bind_all$run_id) == cur & as.character(bind_all$entity_kind) %in% c("matrix","space","model_ref","artifact","cell_set"),,drop=FALSE]
    if (nrow(ins)) for (j in seq_len(nrow(ins))) {
      pp <- bind_all[as.character(bind_all$direction) == "output" & as.character(bind_all$entity_kind) == as.character(ins$entity_kind[j]) & as.character(bind_all$entity_id) == as.character(ins$entity_id[j]) & as.character(bind_all$run_id) != cur & !(as.character(bind_all$run_id) %in% ingestion_runs),,drop=FALSE]
      pp <- pp[!duplicated(as.character(pp$run_id)),,drop=FALSE]
      if (nrow(pp) > 1L) ambiguous[[length(ambiguous)+1L]] <- list(code="ambiguous_dependency", message=paste0("Multiple producers for ",ins$entity_kind[j],":",ins$entity_id[j]))
      else if (nrow(pp) == 1L) {
        producer <- as.character(pp$run_id[1])
        typed <- c(typed, producer)
        typed_edges <- rbind(typed_edges, data.frame(
          parent_run_id=producer, child_run_id=cur,
          edge_type="typed_entity_dependency",
          edge_label=paste0(ins$entity_kind[j], ":", ins$entity_id[j]),
          stringsAsFactors=FALSE
        ))
      }
      else {
        is_cell_set <- identical(as.character(ins$entity_kind[j]), "cell_set")
        boundary <- rbind(boundary, data.frame(
          run_id=cur, entity_kind=as.character(ins$entity_kind[j]),
          entity_id=as.character(ins$entity_id[j]), binding_name=as.character(ins$binding_name[j]),
          content_hash=as.character(if (is_cell_set) ins$source_membership_sha256[j] else ins$content_hash[j] %||% ""),
          content_identity_scheme=as.character(if (is_cell_set) ins$source_membership_identity_scheme[j] else NA_character_),
          member_count=as.integer(if (is_cell_set) ins$source_member_count[j] else NA_integer_),
          reason=if (is_cell_set) "immutable_named_cell_set_membership" else "immutable_or_external_source",
          stringsAsFactors=FALSE
        ))
      }
    }
    stack <- c(stack, setdiff(unique(c(parents[[cur]] %||% character(), typed)),closure))
  }
  if (length(ambiguous)) return(structure(list(status="ambiguous", reproducible=FALSE, target=x, candidates=candidates, run_order=character(0), runs=data.frame(), subgraph=list(nodes=data.frame(),edges=data.frame()), boundary_prerequisites=unique(boundary), terminal_outputs=data.frame(), excluded_siblings=data.frame(), diagnostics=ambiguous), class="wb_target_reproduction_plan"))
  closure_edges <- unique(rbind(edges, typed_edges))
  topo <- .wb_target_toposort(closure, closure_edges)
  rr <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json FROM prov_runs ORDER BY created_at, snapshot_id, run_id;")
  rr <- rr[as.character(rr$run_id) %in% closure, , drop=FALSE]; rr <- rr[!duplicated(as.character(rr$run_id)),,drop=FALSE]
  rr <- rr[match(topo$order, rr$run_id),,drop=FALSE]
  terminal <- out[as.character(out$run_id) == target_run, , drop=FALSE]
  # A fitted UMAP is a map plus its model reference: include both outputs.
  terminal <- terminal[!duplicated(paste(terminal$run_id, terminal$output_name)),,drop=FALSE]
  prereq <- unique(boundary)
  if (nrow(prereq)) for (i in seq_len(nrow(prereq))) {
    recorded <- as.character(prereq$content_hash[i] %||% "")[1]
    if (!grepl("^[0-9a-f]{64}$", recorded)) {
      identity <- .wb_target_boundary_identity(
        bundle, as.character(prereq$entity_kind[i]),
        as.character(prereq$entity_id[i])
      )
      prereq$content_hash[i] <- as.character(identity$content_sha256 %||% "")[1]
    }
  }
  graph <- wb_prov_bundle_dag(bundle, include_snapshots=FALSE, include_registry_mutations=FALSE)
  focus_runs <- paste0("run:", closure)
  from_run <- as.character(graph$edges$from) %in% focus_runs
  to_run <- as.character(graph$edges$to) %in% focus_runs
  from_other_run <- grepl("^run:", as.character(graph$edges$from))
  to_other_run <- grepl("^run:", as.character(graph$edges$to))
  # Keep only closure run-to-run edges and entities directly consumed or
  # materialized by a closure run.  In particular, do not pull a sibling child
  # merely because it has the same parent.
  keep_edge <- (from_run & (to_run | !to_other_run)) | (to_run & (from_run | !from_other_run))
  focus_ids <- unique(c(focus_runs, as.character(graph$edges$from[keep_edge]), as.character(graph$edges$to[keep_edge])))
  run_nodes <- graph$nodes[as.character(graph$nodes$id) %in% focus_ids,,drop=FALSE]
  sg_edges <- graph$edges[keep_edge & as.character(graph$edges$from) %in% focus_ids & as.character(graph$edges$to) %in% focus_ids,,drop=FALSE]
  sib <- edges[edges$parent_run_id %in% closure & !(edges$child_run_id %in% closure),,drop=FALSE]
  promotable <- as.character(.wb_get_op(as.character(rr$op_name[match(target_run, rr$run_id)]))$promotable %||% character())
  promotion_outputs <- terminal[as.character(terminal$output_name) %in% promotable, , drop=FALSE]
  durable_outputs <- bind_all[as.character(bind_all$direction) == "output" & as.character(bind_all$run_id) %in% closure & as.character(bind_all$entity_kind) %in% c("matrix","space","model_ref"),,drop=FALSE]
  artifact_sources <- out[as.character(out$run_id) %in% closure & !is.na(out$artifact_id) & nzchar(as.character(out$artifact_id)), c("artifact_id","run_id","output_name"), drop=FALSE]
  registry_requests <- .wb_operation_pack_v2_registry_replay_rows(
    bundle, topo$order)
  structure(list(status=if(length(topo$cyclic)) "cyclic" else "ok", reproducible=!length(topo$cyclic), target=c(x,list(producing_run_id=target_run,output_name=target_out)), run_order=topo$order, runs=rr, subgraph=list(nodes=run_nodes,edges=sg_edges), boundary_prerequisites=prereq, terminal_outputs=terminal, promotion_outputs=promotion_outputs, durable_outputs=durable_outputs, artifact_sources=artifact_sources, registry_requests=registry_requests, source_bundle_dir=normalizePath(bundle$dir,winslash="/",mustWork=FALSE), excluded_siblings=sib, diagnostics=c(if(!nrow(promotion_outputs)) list(list(code="no_promotable_terminal",message="The producing run has no promotable terminal output.")) else list(), if(length(topo$cyclic)) list(list(code="cyclic",message="Run closure contains a cycle.")) else list(), if(any(terminal$replay_equivalence_policy == "not_comparable")) list(list(code="legacy_not_comparable",message="One or more terminal outputs predate replay-equivalence declarations and will be reported as unsupported.")) else list())), class="wb_target_reproduction_plan")
}

#' Emit an executable target-reproduction script
#'
#' The emitted text contains a self-contained plan and calls only the exported
#' [wb_target_execute_plan()] boundary. The plan's inspected-source path is
#' retained solely for the executor's explicit non-mutation identity check;
#' all scientific execution is relative to `execution_bundle_dir`.
#'
#' @param plan A successful target reproduction plan.
#' @param execution_bundle_dir Literal path placeholder for a writable clone.
#' @return Length-one R script string using only public scworkbench APIs.
#' @export
wb_target_emit_r_script <- function(plan, execution_bundle_dir = "<WRITABLE_INGESTION_READY_CLONE>") {
  .wb_target_plan_assert_executable(plan)
  plan_lines <- .wb_emit_r_object_assign("plan", plan)
  destination <- .wb_r_single_quote_escape(as.character(execution_bundle_dir)[1])
  paste(c(
    "# scworkbench public target-reproduction script",
    "# The source path inside plan is used only for the non-mutation preflight.",
    "library(scworkbench)",
    plan_lines,
    paste0("result <- wb_target_execute_plan(plan, '", destination, "')"),
    "stopifnot(identical(result$status, 'promoted_and_verified'))",
    "print(result$run_map)",
    "print(result$verification)",
    "cat('target reproduction promoted and verified\\n')"
  ), collapse = "\n")
}
