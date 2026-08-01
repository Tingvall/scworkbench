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
    .wb_prov_output_identity_select(con), " FROM prov_run_outputs ORDER BY snapshot_id, run_id, output_name;"))
  bind <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, direction, binding_name, entity_kind, entity_id FROM prov_run_entity_bindings WHERE direction = 'output' ORDER BY snapshot_id, run_id, binding_name;")
  candidates <- data.frame(snapshot_id=character(), run_id=character(), output_name=character(), stringsAsFactors=FALSE)
  if (x$type == "artifact") candidates <- out[as.character(out$artifact_id) == x$entity_id, c("snapshot_id","run_id","output_name"), drop=FALSE]
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
  parents <- split(as.character(edges$parent_run_id), as.character(edges$child_run_id)); closure <- character(0); stack <- target_run
  while(length(stack)) { cur <- stack[1]; stack <- stack[-1]; if (cur %in% closure) next; closure <- c(closure,cur); stack <- c(stack, setdiff(unique(parents[[cur]] %||% character()),closure)) }
  topo <- .wb_target_toposort(closure, edges)
  rr <- DBI::dbGetQuery(con, "SELECT snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json FROM prov_runs ORDER BY created_at, snapshot_id, run_id;")
  rr <- rr[as.character(rr$run_id) %in% closure, , drop=FALSE]; rr <- rr[!duplicated(as.character(rr$run_id)),,drop=FALSE]
  rr <- rr[match(topo$order, rr$run_id),,drop=FALSE]
  terminal <- out[as.character(out$run_id) == target_run, , drop=FALSE]
  # A fitted UMAP is a map plus its model reference: include both outputs.
  terminal <- terminal[!duplicated(paste(terminal$run_id, terminal$output_name)),,drop=FALSE]
  roots <- topo$order[!topo$order %in% as.character(edges$child_run_id)]
  prereq <- bind[as.character(bind$direction) == "input" & as.character(bind$run_id) %in% roots, , drop=FALSE]
  prereq <- prereq[, intersect(c("entity_kind","entity_id","binding_name","run_id"),names(prereq)),drop=FALSE]
  run_nodes <- data.frame(id=paste0("run:",rr$run_id), node_type="run", run_id=rr$run_id, op_name=rr$op_name, output_name=NA_character_, status="persisted", stringsAsFactors=FALSE)
  out_nodes <- data.frame(id=paste0("output:", terminal$run_id, ":", terminal$output_name), node_type=terminal$primitive_kind, run_id=terminal$run_id, op_name=NA_character_, output_name=terminal$output_name, status=terminal$verification_status, stringsAsFactors=FALSE)
  sg_edges <- edges[edges$parent_run_id %in% closure & edges$child_run_id %in% closure,,drop=FALSE]
  sib <- edges[edges$parent_run_id %in% closure & !(edges$child_run_id %in% closure),,drop=FALSE]
  promotable <- as.character(.wb_get_op(as.character(rr$op_name[match(target_run, rr$run_id)]))$promotable %||% character())
  promotion_outputs <- terminal[as.character(terminal$output_name) %in% promotable, , drop=FALSE]
  structure(list(status=if(length(topo$cyclic)) "cyclic" else "ok", reproducible=!length(topo$cyclic), target=c(x,list(producing_run_id=target_run,output_name=target_out)), run_order=topo$order, runs=rr, subgraph=list(nodes=rbind(run_nodes,out_nodes),edges=sg_edges), boundary_prerequisites=prereq, terminal_outputs=terminal, promotion_outputs=promotion_outputs, excluded_siblings=sib, diagnostics=c(if(!nrow(promotion_outputs)) list(list(code="no_promotable_terminal",message="The producing run has no promotable terminal output.")) else list(), if(length(topo$cyclic)) list(list(code="cyclic",message="Run closure contains a cycle.")) else list(), if(any(terminal$verification_level != "content")) list(list(code="structural_only",message="One or more terminal outputs are legacy structural-only.")) else list())), class="wb_target_reproduction_plan")
}

#' Validate a sibling-branch reproduction template
#'
#' @param plan A successful target reproduction plan.
#' @param declared_change Non-empty description of the changed upstream input.
#' @param output_id_map Named explicit ids for every durable matrix, space, or model output.
#' @param bundle Optional destination bundle, used to reject existing IDs.
#' @return The plan annotated as `branch_template`.
#' @export
wb_target_reproduction_branch_template <- function(plan, declared_change, output_id_map, bundle = NULL) {
  .wb_assert(inherits(plan, "wb_target_reproduction_plan") && isTRUE(plan$reproducible), "plan must be reproducible")
  .wb_assert(is.character(declared_change) && nzchar(declared_change[1]), "declared_change must be non-empty")
  durable <- plan$terminal_outputs[plan$terminal_outputs$primitive_kind %in% c("matrix","space","space_2d","model_ref"),,drop=FALSE]
  keys <- paste0(ifelse(durable$primitive_kind == "model_ref", "model", ifelse(durable$primitive_kind %in% c("space","space_2d"),"space","matrix")), ":", durable$output_name)
  .wb_assert(is.character(output_id_map) && !is.null(names(output_id_map)) && all(keys %in% names(output_id_map)) && all(nzchar(output_id_map[keys])), "output_id_map must explicitly map every new matrix/space/model terminal output")
  .wb_assert(!anyDuplicated(unname(output_id_map[keys])), "output_id_map may not reuse an output id")
  if (!is.null(bundle)) { existing <- c(wb_matrices(bundle)$matrix_id %||% character(), wb_spaces(bundle)$space_id %||% character()); .wb_assert(!any(unname(output_id_map[keys]) %in% existing), "output_id_map collides with an existing durable matrix/space id") }
  plan$mode <- "branch_template"; plan$declared_change <- declared_change[1]; plan$output_id_map <- output_id_map; plan
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
  .wb_assert(nrow(plan$promotion_outputs %||% data.frame()) > 0L, "plan has no promotable terminal outputs")
  sels <- paste(vapply(seq_len(nrow(plan$promotion_outputs)), function(i) paste0("wb_ref_run(replay_map[['", .wb_r_single_quote_escape(as.character(plan$promotion_outputs$run_id[i])), "']], '", .wb_r_single_quote_escape(as.character(plan$promotion_outputs$output_name[i])), "')"), character(1)), collapse=", ")
  verifies <- vapply(seq_len(nrow(plan$terminal_outputs)), function(i) { z <- plan$terminal_outputs[i,,drop=FALSE]; if (identical(as.character(z$verification_level[1]),"content") && nzchar(as.character(z$content_sha256[1] %||% ""))) paste0("stopifnot(identical(scworkbench:::.wb_prov_payload_identity(bundle, target_res$run$outputs[['",.wb_r_single_quote_escape(as.character(z$output_name[1])),"']])$content_sha256, '",.wb_r_single_quote_escape(as.character(z$content_sha256[1])),"'))") else paste0("message('structural/legacy verification limitation: ",.wb_r_single_quote_escape(as.character(z$output_name[1])),"')") }, character(1))
  paste(c("# IMPORTANT: this is a writable ingestion-ready execution clone, never the inspected source bundle.", core, "if (file.access(bundle_dir, 2L) != 0L) stop('Execution clone must be writable.')", "# Boundary prerequisite identities are declared by plan$boundary_prerequisites; confirm them before rerunning this script.", "if (is.null(target_res)) stop('Target run was not replayed.')", paste0("promotion <- wb_session_promote_current(bundle, sess, outputs = list(",sels,"))"), verifies, "cat('target reproduction promoted and verified\\n')"), collapse="\n")
}
