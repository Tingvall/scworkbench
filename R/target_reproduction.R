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
  .wb_migrate_provenance_tables(bundle$con)
  x <- .wb_target_parse(target); con <- bundle$con
  out <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id, run_id, output_name, primitive_kind, artifact_id, ",
    .wb_prov_output_identity_select(con), ", ", .wb_prov_output_replay_select(con),
    " FROM prov_run_outputs ORDER BY snapshot_id, run_id, output_name;"))
  bind <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, direction, binding_name, entity_kind, entity_id FROM prov_run_entity_bindings WHERE direction = 'output' ORDER BY snapshot_id, run_id, binding_name;")
  candidates <- data.frame(snapshot_id=character(), run_id=character(), output_name=character(), stringsAsFactors=FALSE)
  if (x$type == "artifact") candidates <- out[!is.na(out$artifact_id) & as.character(out$artifact_id) == x$entity_id, c("snapshot_id","run_id","output_name"), drop=FALSE]
  if (x$type == "run") candidates <- unique(out[as.character(out$run_id) == x$entity_id, c("snapshot_id","run_id","output_name"), drop=FALSE])
  if (x$type %in% c("matrix", "space", "model")) {
    ek <- if (x$type == "model") "model_ref" else x$type
    bb <- bind[as.character(bind$entity_kind) == ek & as.character(bind$entity_id) == x$entity_id, , drop=FALSE]
    if (nrow(bb)) candidates <- merge(bb[,c("snapshot_id","run_id","binding_name")], out, by=c("snapshot_id","run_id"), all.x=TRUE)
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
  bind_all <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, direction, binding_name, entity_kind, entity_id, content_hash FROM prov_run_entity_bindings ORDER BY snapshot_id, run_id, direction, binding_name;")
  boundary <- data.frame(run_id=character(), entity_kind=character(), entity_id=character(), binding_name=character(), content_hash=character(), reason=character(), stringsAsFactors=FALSE)
  ambiguous <- list()
  while(length(stack)) {
    cur <- stack[1]; stack <- stack[-1]; if (cur %in% closure) next; closure <- c(closure,cur)
    typed <- character(0)
    ins <- bind_all[as.character(bind_all$direction) == "input" & as.character(bind_all$run_id) == cur & as.character(bind_all$entity_kind) %in% c("matrix","space","model_ref","artifact"),,drop=FALSE]
    if (nrow(ins)) for (j in seq_len(nrow(ins))) {
      pp <- bind_all[as.character(bind_all$direction) == "output" & as.character(bind_all$entity_kind) == as.character(ins$entity_kind[j]) & as.character(bind_all$entity_id) == as.character(ins$entity_id[j]) & as.character(bind_all$run_id) != cur,,drop=FALSE]
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
      else boundary <- rbind(boundary, data.frame(run_id=cur, entity_kind=as.character(ins$entity_kind[j]), entity_id=as.character(ins$entity_id[j]), binding_name=as.character(ins$binding_name[j]), content_hash=as.character(ins$content_hash[j] %||% ""), reason="immutable_or_external_source", stringsAsFactors=FALSE))
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
  structure(list(status=if(length(topo$cyclic)) "cyclic" else "ok", reproducible=!length(topo$cyclic), target=c(x,list(producing_run_id=target_run,output_name=target_out)), run_order=topo$order, runs=rr, subgraph=list(nodes=run_nodes,edges=sg_edges), boundary_prerequisites=prereq, terminal_outputs=terminal, promotion_outputs=promotion_outputs, durable_outputs=durable_outputs, artifact_sources=artifact_sources, source_bundle_dir=normalizePath(bundle$dir,winslash="/",mustWork=FALSE), excluded_siblings=sib, diagnostics=c(if(!nrow(promotion_outputs)) list(list(code="no_promotable_terminal",message="The producing run has no promotable terminal output.")) else list(), if(length(topo$cyclic)) list(list(code="cyclic",message="Run closure contains a cycle.")) else list(), if(any(terminal$replay_equivalence_policy == "not_comparable")) list(list(code="legacy_not_comparable",message="One or more terminal outputs predate replay-equivalence declarations and will be reported as unsupported.")) else list())), class="wb_target_reproduction_plan")
}

#' Emit an executable target-reproduction script
#'
#' The script opens a writable ingestion-ready execution clone, never the
#' inspected source bundle, replays only the planned closure, promotes the
#' selected terminal outputs, and checks recorded content identities.
#'
#' @param plan A successful target reproduction plan.
#' @param execution_bundle_dir Literal path placeholder for a writable clone.
#' @return Length-one R script string.
#' @export
wb_target_emit_r_script <- function(plan, execution_bundle_dir = "<WRITABLE_INGESTION_READY_CLONE>") {
  .wb_assert(inherits(plan,"wb_target_reproduction_plan") && isTRUE(plan$reproducible), "plan is not reproducible")
  .wb_assert(identical(plan$status,"ok"), "plan has diagnostics that prevent script emission")
  runs <- plan$runs; core <- .wb_prov_emit_r_script_core(runs, plan$run_order, "target-plan", execution_bundle_dir, TRUE, "symbolic", style="bench_pretty", target=list(run_id=plan$target$producing_run_id,output_name=plan$target$output_name))
  dest <- .wb_r_single_quote_escape(execution_bundle_dir); src <- .wb_r_single_quote_escape(plan$source_bundle_dir %||% "")
  preflight <- c(
    paste0("if (!dir.exists('", dest, "') || file.access('", dest, "', 2L) != 0L) stop('Destination must be an existing writable ingestion-ready clone.')"),
    paste0("if (nzchar('", src, "') && identical(normalizePath('", dest, "', winslash='/', mustWork=FALSE), normalizePath('", src, "', winslash='/', mustWork=FALSE))) stop('Refusing to mutate the inspected source bundle.')")
  )
  boundary_checks <- character(0)
  if (nrow(plan$boundary_prerequisites %||% data.frame())) for (i in seq_len(nrow(plan$boundary_prerequisites))) {
    b <- plan$boundary_prerequisites[i,,drop=FALSE]; id <- .wb_r_single_quote_escape(as.character(b$entity_id[1])); k <- as.character(b$entity_kind[1])
    present <- if (k == "matrix") paste0("'",id,"' %in% wb_matrices(bundle)$matrix_id") else if (k == "space") paste0("'",id,"' %in% wb_spaces(bundle)$space_id") else if (k == "artifact") paste0("'",id,"' %in% wb_art_list(bundle)$artifact_id") else "TRUE"
    boundary_checks <- c(boundary_checks, paste0("if (!(",present,")) stop('Missing immutable boundary ",k,":",id,"')"))
  }
  collision_checks <- character(0)
  if (nrow(plan$durable_outputs %||% data.frame())) for (i in seq_len(nrow(plan$durable_outputs))) {
    d <- plan$durable_outputs[i,,drop=FALSE]; id <- .wb_r_single_quote_escape(as.character(d$entity_id[1])); k <- as.character(d$entity_kind[1])
    exists <- if (k == "matrix") paste0("'",id,"' %in% wb_matrices(bundle)$matrix_id") else if (k == "space") paste0("'",id,"' %in% wb_spaces(bundle)$space_id") else "FALSE"
    collision_checks <- c(collision_checks, paste0("if (",exists,") stop('Durable output collision: ",k,":",id,"')"))
  }
  artifact_lines <- character(0)
  if (nrow(plan$artifact_sources %||% data.frame())) for (i in seq_len(nrow(plan$artifact_sources))) artifact_lines <- c(artifact_lines, paste0("artifact_replay_map[['",.wb_r_single_quote_escape(as.character(plan$artifact_sources$artifact_id[i])),"']] <- list(run_id='",.wb_r_single_quote_escape(as.character(plan$artifact_sources$run_id[i])),"', output='",.wb_r_single_quote_escape(as.character(plan$artifact_sources$output_name[i])),"')"))
  rewrite <- c("artifact_replay_map <- list()", artifact_lines, "rewrite_artifact_refs <- function(x) { if (!is.list(x)) return(x); if (identical(as.character(x$ref_type %||% '')[1], 'artifact')) { a <- artifact_replay_map[[as.character(x$artifact_id %||% '')[1]]]; if (!is.null(a) && !is.null(replay_map[[a$run_id]])) return(wb_ref_run(replay_map[[a$run_id]], a$output)); return(x) }; y <- lapply(x, rewrite_artifact_refs); if (!is.null(names(x))) names(y) <- names(x); y }")
  core <- sub("sess <- wb_session_new()", paste(c(boundary_checks, collision_checks, "sess <- wb_session_new()", rewrite), collapse="\n"), core, fixed=TRUE)
  core <- gsub("execution_inputs <- rewrite_run_refs(execution_inputs, replay_map = replay_map)", "execution_inputs <- rewrite_artifact_refs(rewrite_run_refs(execution_inputs, replay_map = replay_map))", core, fixed=TRUE)
  .wb_assert(nrow(plan$promotion_outputs %||% data.frame()) > 0L, "plan has no promotable terminal outputs")
  sels <- paste(vapply(seq_len(nrow(plan$promotion_outputs)), function(i) paste0("wb_ref_run(replay_map[['", .wb_r_single_quote_escape(as.character(plan$promotion_outputs$run_id[i])), "']], '", .wb_r_single_quote_escape(as.character(plan$promotion_outputs$output_name[i])), "')"), character(1)), collapse=", ")
  verifies <- vapply(seq_len(nrow(plan$terminal_outputs)), function(i) {
    z <- plan$terminal_outputs[i,,drop=FALSE]
    nm <- .wb_r_single_quote_escape(as.character(z$output_name[1]))
    paste0(
      "replayed_artifact_id <- promotion$promoted$artifact_id[promotion$promoted$run_id == replay_map[['",
      .wb_r_single_quote_escape(as.character(z$run_id[1])), "']] & promotion$promoted$output == '", nm,
      "'][1]; if (length(replayed_artifact_id) == 0L) replayed_artifact_id <- NA_character_; ",
      "verification <- scworkbench:::.wb_prov_verify_replay_output(bundle = bundle, original_run_id = '",
      .wb_r_single_quote_escape(as.character(z$run_id[1])), "', original_output_name = '", nm,
      "', expected_kind = '", .wb_r_single_quote_escape(as.character(z$primitive_kind[1])),
      "', expected_content_sha256 = '", .wb_r_single_quote_escape(as.character(z$content_sha256[1] %||% "")),
      "', replay_equivalence_policy = '", .wb_r_single_quote_escape(as.character(z$replay_equivalence_policy[1] %||% "not_comparable")),
      "', expected_reference = '", .wb_r_single_quote_escape(as.character(z$replay_equivalence_reference[1] %||% "")),
      "', replayed_prim = target_res$run$outputs[['", nm, "']], replay_run_id = replay_map[['",
      .wb_r_single_quote_escape(as.character(z$run_id[1])), "']], replay_snapshot_id = promotion$provenance_snapshot_id, replay_artifact_id = replayed_artifact_id); print(verification)"
    )
  }, character(1))
  paste(c("# IMPORTANT: this is a writable ingestion-ready execution clone, never the inspected source bundle.", preflight, core, "if (is.null(target_res)) stop('Target run was not replayed.')", paste0("promotion <- wb_session_promote_current(bundle, sess, outputs = list(",sels,"))"), verifies, "cat('target reproduction promoted and verified\\n')", "wb_close_bundle(bundle)"), collapse="\n")
}
