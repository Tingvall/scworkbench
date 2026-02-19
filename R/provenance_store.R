# R/provenance_store.R

.wb_prov_new_snapshot_id <- function() {
  paste0(
    "prov_",
    format(Sys.time(), "%Y%m%d_%H%M%S"),
    "_",
    paste0(sample(c(0:9, letters), 8, TRUE), collapse = "")
  )
}

.wb_hash_text <- function(x) {
  txt <- paste(as.character(x %||% ""), collapse = "|")
  b <- as.integer(charToRaw(enc2utf8(txt)))
  if (!length(b)) return("0000000000000000")

  h1 <- 0
  h2 <- 0
  for (i in seq_along(b)) {
    h1 <- (h1 + (b[[i]] * i)) %% 2147483647
    h2 <- (h2 + (b[[i]] * ((i %% 251) + 1L))) %% 2147483629
  }
  paste0(sprintf("%08x", as.integer(h1)), sprintf("%08x", as.integer(h2)))
}

.wb_prov_schema_version <- function() "1.1"

.wb_migrate_provenance_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_heads (
      snapshot_id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL,
      created_by TEXT,
      name_prefix TEXT,
      description TEXT,
      schema_version TEXT,
      head_run_ids_json TEXT NOT NULL,
      n_runs INTEGER NOT NULL,
      n_artifacts INTEGER NOT NULL
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_heads_created_at ON prov_heads(created_at);")
  if (!.wb_db_has_column(con, "prov_heads", "schema_version")) {
    DBI::dbExecute(con, "ALTER TABLE prov_heads ADD COLUMN schema_version TEXT;")
    DBI::dbExecute(con, "UPDATE prov_heads SET schema_version = ? WHERE schema_version IS NULL OR schema_version = '';", params = list(.wb_prov_schema_version()))
  }

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_runs (
      snapshot_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      op_name TEXT NOT NULL,
      created_at TEXT,
      notes TEXT,
      params_json TEXT NOT NULL,
      inputs_json TEXT NOT NULL,
      symbolic_inputs_json TEXT,
      execution_inputs_json TEXT,
      run_hash TEXT NOT NULL,
      PRIMARY KEY(snapshot_id, run_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_runs_snapshot ON prov_runs(snapshot_id);")
  if (!.wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN symbolic_inputs_json TEXT;")
  }
  if (!.wb_db_has_column(con, "prov_runs", "execution_inputs_json")) {
    DBI::dbExecute(con, "ALTER TABLE prov_runs ADD COLUMN execution_inputs_json TEXT;")
  }

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_run_edges (
      snapshot_id TEXT NOT NULL,
      parent_run_id TEXT NOT NULL,
      child_run_id TEXT NOT NULL,
      edge_type TEXT NOT NULL,
      edge_label TEXT,
      PRIMARY KEY(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_edges_snapshot ON prov_run_edges(snapshot_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS prov_run_outputs (
      snapshot_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      output_name TEXT NOT NULL,
      primitive_kind TEXT NOT NULL,
      output_hash TEXT NOT NULL,
      artifact_id TEXT,
      PRIMARY KEY(snapshot_id, run_id, output_name)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_outputs_snapshot ON prov_run_outputs(snapshot_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_prov_outputs_artifact ON prov_run_outputs(artifact_id);")

  invisible(TRUE)
}

.wb_prov_write_snapshot <- function(bundle,
                                    runs,
                                    topo,
                                    heads,
                                    promoted_df,
                                    name_prefix = NULL,
                                    description = NULL,
                                    created_by = NULL) {
  .wb_require_pkg("jsonlite", "provenance snapshot write")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  sid <- .wb_prov_new_snapshot_id()
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  head_json <- jsonlite::toJSON(as.character(heads), auto_unbox = FALSE, null = "null")
  n_artifacts <- sum(
    !is.na(promoted_df$artifact_id %||% NA_character_) &
      nzchar(as.character(promoted_df$artifact_id %||% ""))
  )

  artifact_map <- list()
  ok <- promoted_df[
    as.character(promoted_df$status %||% "") == "ok" &
      !is.na(promoted_df$output %||% NA_character_) &
      !is.na(promoted_df$artifact_id %||% NA_character_),
    ,
    drop = FALSE
  ]
  if (nrow(ok)) {
    for (i in seq_len(nrow(ok))) {
      k <- paste0(as.character(ok$run_id[i]), "::", as.character(ok$output[i]))
      artifact_map[[k]] <- as.character(ok$artifact_id[i])
    }
  }

  DBI::dbWithTransaction(con, {
    DBI::dbExecute(
      con,
      "INSERT INTO prov_heads(snapshot_id, created_at, created_by, name_prefix, description, schema_version, head_run_ids_json, n_runs, n_artifacts)
       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);",
      params = list(
        sid, created_at, created_by %||% NA_character_, name_prefix %||% NA_character_,
        description %||% NA_character_, .wb_prov_schema_version(),
        as.character(head_json), as.integer(length(topo)), as.integer(n_artifacts)
      )
    )

    for (rid in topo) {
      run <- runs[[rid]]
      if (is.null(run) || !wb_is_run(run)) next

      params_json <- jsonlite::toJSON(.wb_json_sanitize(run$params %||% list()), auto_unbox = TRUE, null = "null")
      inputs_json <- jsonlite::toJSON(.wb_json_sanitize(run$inputs %||% list()), auto_unbox = TRUE, null = "null")
      symbolic_inputs <- run$inputs$symbolic_inputs %||% run$inputs$user_inputs %||% list()
      execution_inputs <- run$inputs$execution_inputs %||% list(
        effective_n = run$inputs$effective_n %||% NA_integer_,
        resolved = list()
      )
      symbolic_inputs_json <- jsonlite::toJSON(.wb_json_sanitize(symbolic_inputs), auto_unbox = TRUE, null = "null")
      execution_inputs_json <- jsonlite::toJSON(.wb_json_sanitize(execution_inputs), auto_unbox = TRUE, null = "null")
      run_hash <- .wb_hash_text(c(run$op_name %||% "", params_json, inputs_json, symbolic_inputs_json, execution_inputs_json))

      DBI::dbExecute(
        con,
        "INSERT INTO prov_runs(snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, symbolic_inputs_json, execution_inputs_json, run_hash)
         VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
        params = list(
          sid,
          as.character(run$run_id),
          as.character(run$op_name %||% ""),
          as.character(run$created_at %||% NA_character_),
          as.character(run$notes %||% NA_character_),
          as.character(params_json),
          as.character(inputs_json),
          as.character(symbolic_inputs_json),
          as.character(execution_inputs_json),
          as.character(run_hash)
        )
      )

      parents <- unique(as.character(run$inputs$parents %||% character(0)))
      parents <- parents[nzchar(parents)]
      for (p in parents) {
        DBI::dbExecute(
          con,
          "INSERT OR IGNORE INTO prov_run_edges(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
           VALUES(?, ?, ?, ?, ?);",
          params = list(sid, as.character(p), as.character(rid), "depends_on_run", NA_character_)
        )
      }

      refs <- .wb_dag_collect_refs(run$inputs$user_inputs %||% list(), path = "inputs$user_inputs")
      if (nrow(refs)) {
        refs <- refs[refs$ref_type == "run" & nzchar(refs$run_id), , drop = FALSE]
        if (nrow(refs)) {
          for (j in seq_len(nrow(refs))) {
            DBI::dbExecute(
              con,
              "INSERT OR IGNORE INTO prov_run_edges(snapshot_id, parent_run_id, child_run_id, edge_type, edge_label)
               VALUES(?, ?, ?, ?, ?);",
              params = list(
                sid,
                as.character(refs$run_id[j]),
                as.character(rid),
                "input_run_ref",
                as.character(refs$output[j] %||% NA_character_)
              )
            )
          }
        }
      }

      outs <- run$outputs %||% list()
      if (length(outs)) {
        for (nm in names(outs)) {
          prim <- outs[[nm]]
          kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
          sum_txt <- if (.wb_is_primitive(prim)) {
            jsonlite::toJSON(.wb_json_sanitize(.wb_prim_summary(prim)), auto_unbox = TRUE, null = "null")
          } else {
            paste(class(prim), collapse = ",")
          }
          out_hash <- .wb_hash_text(c(kind, sum_txt))
          art_id <- artifact_map[[paste0(rid, "::", nm)]] %||% NA_character_

          DBI::dbExecute(
            con,
            "INSERT INTO prov_run_outputs(snapshot_id, run_id, output_name, primitive_kind, output_hash, artifact_id)
             VALUES(?, ?, ?, ?, ?, ?);",
            params = list(
              sid, as.character(rid), as.character(nm), as.character(kind), as.character(out_hash), as.character(art_id)
            )
          )
        }
      }
    }
  })

  sid
}

#' List persisted provenance snapshots
#'
#' @param bundle scworkbench bundle
#' @return data.frame of provenance snapshot heads
#' @export
wb_prov_list_heads <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  DBI::dbGetQuery(
    con,
    "SELECT snapshot_id, created_at, created_by, name_prefix, description, schema_version, n_runs, n_artifacts
     FROM prov_heads
     ORDER BY created_at DESC;"
  )
}

#' Reconstruct persisted DAG for a promoted snapshot
#'
#' @param bundle scworkbench bundle
#' @param snapshot_id Optional snapshot id (default latest)
#' @return list(snapshot_id, head_run_ids, nodes, edges)
#' @export
wb_prov_dag <- function(bundle, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance DAG reconstruction")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
    if (!nrow(h)) {
      return(list(
        snapshot_id = NA_character_,
        head_run_ids = character(0),
        nodes = data.frame(id = character(0), node_type = character(0), label = character(0), stringsAsFactors = FALSE),
        edges = data.frame(from = character(0), to = character(0), edge_type = character(0), label = character(0), stringsAsFactors = FALSE)
      ))
    }
    sid <- as.character(h$snapshot_id[1])
  }

  head <- DBI::dbGetQuery(
    con,
    "SELECT head_run_ids_json FROM prov_heads WHERE snapshot_id = ?;",
    params = list(sid)
  )
  .wb_assert(nrow(head) == 1, paste0("Unknown snapshot_id: ", sid))
  head_runs <- jsonlite::fromJSON(as.character(head$head_run_ids_json[1]))
  head_runs <- as.character(head_runs %||% character(0))

  runs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, op_name, created_at FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;",
    params = list(sid)
  )
  run_nodes <- if (nrow(runs)) data.frame(
    id = paste0("run:", as.character(runs$run_id)),
    node_type = "run",
    label = as.character(runs$op_name),
    run_id = as.character(runs$run_id),
    op_name = as.character(runs$op_name),
    created_at = as.character(runs$created_at),
    artifact_id = NA_character_,
    artifact_type = NA_character_,
    stringsAsFactors = FALSE
  ) else data.frame(
    id = character(0), node_type = character(0), label = character(0), run_id = character(0),
    op_name = character(0), created_at = character(0), artifact_id = character(0), artifact_type = character(0),
    stringsAsFactors = FALSE
  )

  arts <- DBI::dbGetQuery(
    con,
    "SELECT o.run_id, o.output_name, o.artifact_id, a.type, a.name, a.created_at
     FROM prov_run_outputs o
     LEFT JOIN artifacts a ON a.artifact_id = o.artifact_id
     WHERE o.snapshot_id = ? AND o.artifact_id IS NOT NULL AND o.artifact_id <> ''
     ORDER BY o.run_id, o.output_name;",
    params = list(sid)
  )
  art_nodes <- if (nrow(arts)) data.frame(
    id = paste0("artifact:", as.character(arts$artifact_id)),
    node_type = "artifact",
    label = as.character(arts$name %||% arts$artifact_id),
    run_id = NA_character_,
    op_name = NA_character_,
    created_at = as.character(arts$created_at %||% NA_character_),
    artifact_id = as.character(arts$artifact_id),
    artifact_type = as.character(arts$type %||% NA_character_),
    stringsAsFactors = FALSE
  ) else run_nodes[0, , drop = FALSE]

  nodes <- unique(rbind(run_nodes, art_nodes))

  ee <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id, edge_type, edge_label
     FROM prov_run_edges WHERE snapshot_id = ?
     ORDER BY parent_run_id, child_run_id, edge_type;",
    params = list(sid)
  )
  run_edges <- if (nrow(ee)) data.frame(
    from = paste0("run:", as.character(ee$parent_run_id)),
    to = paste0("run:", as.character(ee$child_run_id)),
    edge_type = as.character(ee$edge_type),
    label = as.character(ee$edge_label %||% NA_character_),
    stringsAsFactors = FALSE
  ) else data.frame(from = character(0), to = character(0), edge_type = character(0), label = character(0), stringsAsFactors = FALSE)

  art_edges <- if (nrow(arts)) data.frame(
    from = paste0("run:", as.character(arts$run_id)),
    to = paste0("artifact:", as.character(arts$artifact_id)),
    edge_type = "promoted_to_artifact",
    label = as.character(arts$output_name),
    stringsAsFactors = FALSE
  ) else run_edges[0, , drop = FALSE]

  list(
    snapshot_id = sid,
    head_run_ids = head_runs,
    nodes = nodes,
    edges = unique(rbind(run_edges, art_edges))
  )
}

#' Inspect one persisted run from a provenance snapshot
#'
#' @param bundle scworkbench bundle
#' @param run_id run_id inside snapshot
#' @param snapshot_id Optional snapshot id (default latest)
#' @return list(run, parents, children, outputs)
#' @export
wb_prov_run_details <- function(bundle, run_id, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance run inspection")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  rid <- as.character(run_id)[1]
  .wb_assert(nzchar(rid), "run_id must be non-empty")

  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
    .wb_assert(nrow(h) == 1, "No provenance snapshots available.")
    sid <- as.character(h$snapshot_id[1])
  }

  has_sym <- .wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")
  has_exec <- .wb_db_has_column(con, "prov_runs", "execution_inputs_json")
  rr <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT run_id, op_name, created_at, notes, params_json, inputs_json, ",
      if (has_sym) "symbolic_inputs_json" else "NULL AS symbolic_inputs_json",
      ", ",
      if (has_exec) "execution_inputs_json" else "NULL AS execution_inputs_json",
      ", run_hash FROM prov_runs WHERE snapshot_id = ? AND run_id = ?;"
    ),
    params = list(sid, rid)
  )
  .wb_assert(nrow(rr) == 1, paste0("Run not found in snapshot: ", rid))

  parents <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id FROM prov_run_edges
     WHERE snapshot_id = ? AND child_run_id = ?
       AND edge_type IN ('depends_on_run','input_run_ref')
     ORDER BY parent_run_id;",
    params = list(sid, rid)
  )$parent_run_id
  parents <- unique(as.character(parents %||% character(0)))

  children <- DBI::dbGetQuery(
    con,
    "SELECT child_run_id FROM prov_run_edges
     WHERE snapshot_id = ? AND parent_run_id = ?
       AND edge_type IN ('depends_on_run','input_run_ref')
     ORDER BY child_run_id;",
    params = list(sid, rid)
  )$child_run_id
  children <- unique(as.character(children %||% character(0)))

  outs <- DBI::dbGetQuery(
    con,
    "SELECT output_name, primitive_kind, output_hash, artifact_id
     FROM prov_run_outputs
     WHERE snapshot_id = ? AND run_id = ?
     ORDER BY output_name;",
    params = list(sid, rid)
  )
  if (!nrow(outs)) {
    outs <- data.frame(
      output_name = character(0),
      primitive_kind = character(0),
      output_hash = character(0),
      artifact_id = character(0),
      stringsAsFactors = FALSE
    )
  }

  list(
    snapshot_id = sid,
    run = list(
      run_id = as.character(rr$run_id[1]),
      op_name = as.character(rr$op_name[1]),
      created_at = as.character(rr$created_at[1]),
      notes = as.character(rr$notes[1]),
      params = jsonlite::fromJSON(as.character(rr$params_json[1]), simplifyVector = FALSE),
      inputs = jsonlite::fromJSON(as.character(rr$inputs_json[1]), simplifyVector = FALSE),
      symbolic_inputs = jsonlite::fromJSON(as.character(rr$symbolic_inputs_json[1] %||% "null"), simplifyVector = FALSE),
      execution_inputs = jsonlite::fromJSON(as.character(rr$execution_inputs_json[1] %||% "null"), simplifyVector = FALSE),
      run_hash = as.character(rr$run_hash[1])
    ),
    parents = parents,
    children = children,
    outputs = outs
  )
}

.wb_r_single_quote_escape <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("\\\\", "\\\\\\\\", x)
  x <- gsub("'", "\\\\'", x, fixed = TRUE)
  x
}

.wb_emit_r_paste0_chunks <- function(var_name, txt, chunk_size = 700L) {
  s <- .wb_r_single_quote_escape(txt %||% "")
  n <- nchar(s, type = "chars")
  if (!is.finite(n) || n <= chunk_size) {
    return(paste0(var_name, " <- '", s, "'"))
  }
  starts <- seq.int(1L, n, by = as.integer(chunk_size))
  chunks <- vapply(starts, function(i) substr(s, i, min(i + chunk_size - 1L, n)), character(1))
  c(
    paste0(var_name, " <- paste0("),
    paste0("  '", chunks, "'", collapse = ",\n"),
    ")"
  )
}

.wb_prov_compact_inputs <- function(stored_inputs) {
  x <- stored_inputs %||% list()
  if (!is.list(x)) return(list())
  ui <- x$user_inputs %||% list()
  if (!is.list(ui)) ui <- list()
  if (is.null(ui$cell_set) && !is.null(x$cell_set)) ui$cell_set <- x$cell_set
  if (is.null(ui$min_cells) && !is.null(x$min_cells)) ui$min_cells <- x$min_cells
  ui
}

.wb_drop_key_recursive <- function(x, key) {
  if (!is.list(x)) return(x)
  nms <- names(x) %||% character(length(x))
  keep <- if (length(nms)) !(nms %in% key) else rep(TRUE, length(x))
  y <- x[keep]
  if (!length(y)) return(y)
  y <- lapply(y, .wb_drop_key_recursive, key = key)
  if (!is.null(names(x))) names(y) <- names(x)[keep]
  y
}

.wb_emit_r_object_assign <- function(var_name, obj) {
  txt <- utils::capture.output(base::dput(obj))
  if (!length(txt)) return(paste0(var_name, " <- list()"))
  if (length(txt) == 1L) return(paste0(var_name, " <- ", txt[[1]]))
  c(paste0(var_name, " <- ", txt[[1]]), txt[-1])
}

#' Emit an R replay script from persisted provenance
#'
#' The generated script replays the persisted run order using `wb_session_run_op()`
#' with stored params/inputs from the selected provenance snapshot.
#'
#' @param bundle scworkbench bundle
#' @param snapshot_id Optional snapshot id (default latest)
#' @param bundle_dir_literal Optional literal bundle path to embed in script; defaults to `<BUNDLE_DIR>`
#' @param include_header If TRUE, include comments and setup header
#' @return length-1 character string containing R script text
#' @export
wb_prov_emit_r_script <- function(bundle,
                                  snapshot_id = NULL,
                                  bundle_dir_literal = "<BUNDLE_DIR>",
                                  include_header = TRUE,
                                  mode = c("symbolic", "literal"),
                                  sidecar_rds_path = "replay_inputs.rds",
                                  style = c("bench_pretty", "raw_json")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance replay script")
  mode <- match.arg(mode)
  style <- match.arg(style)
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid)) {
    h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
    .wb_assert(nrow(h) == 1, "No provenance snapshots available.")
    sid <- as.character(h$snapshot_id[1])
  }

  runs <- .wb_prov_select_runs(con, sid)
  .wb_assert(nrow(runs) > 0, paste0("No runs for snapshot_id: ", sid))

  edges <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id
     FROM prov_run_edges
     WHERE snapshot_id = ? AND edge_type IN ('depends_on_run','input_run_ref');",
    params = list(sid)
  )

  run_ids <- as.character(runs$run_id)
  if (nrow(edges)) {
    indeg <- stats::setNames(integer(length(run_ids)), run_ids)
    kids <- stats::setNames(vector("list", length(run_ids)), run_ids)
    for (i in seq_len(nrow(edges))) {
      p <- as.character(edges$parent_run_id[i])
      c <- as.character(edges$child_run_id[i])
      if (!(p %in% run_ids) || !(c %in% run_ids)) next
      kids[[p]] <- c(kids[[p]], c)
      indeg[[c]] <- indeg[[c]] + 1L
    }
    q <- sort(names(indeg[indeg == 0L]))
    topo <- character(0)
    while (length(q)) {
      n <- q[1]
      q <- q[-1]
      topo <- c(topo, n)
      ch <- unique(as.character(kids[[n]] %||% character(0)))
      ch <- ch[ch %in% names(indeg)]
      for (c in ch) {
        indeg[[c]] <- indeg[[c]] - 1L
      }
      q <- sort(unique(c(q, names(indeg[indeg == 0L & !(names(indeg) %in% topo)]))))
    }
    run_order <- if (length(topo) == length(run_ids)) topo else run_ids
  } else {
    run_order <- run_ids
  }

  run_idx <- stats::setNames(seq_len(nrow(runs)), as.character(runs$run_id))
  payload <- list()
  for (rid in run_order) {
    i <- run_idx[[rid]]
    sym_txt <- as.character(runs$symbolic_inputs_json[i] %||% "")[1]
    if (nzchar(sym_txt)) {
      inputs_use <- jsonlite::fromJSON(sym_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)
      if (is.null(inputs_use)) inputs_use <- list()
    } else {
      inputs_stored <- jsonlite::fromJSON(
        as.character(runs$inputs_json[i] %||% "{}"),
        simplifyVector = TRUE,
        simplifyDataFrame = FALSE
      )
      inputs_use <- .wb_prov_compact_inputs(inputs_stored)
    }
    if (identical(mode, "symbolic")) {
      inputs_use <- .wb_drop_key_recursive(inputs_use, key = "cell_ids")
    }
    params_use <- jsonlite::fromJSON(
      as.character(runs$params_json[i] %||% "{}"),
      simplifyVector = TRUE,
      simplifyDataFrame = FALSE
    )
    payload[[rid]] <- list(params = params_use, inputs = inputs_use)
  }

  if (identical(mode, "literal")) {
    base::saveRDS(payload, file = sidecar_rds_path)
  }

  lines <- character(0)
  if (isTRUE(include_header)) {
    lines <- c(
      lines,
      "# scworkbench provenance replay script",
      paste0("# snapshot_id: ", sid),
      paste0("# mode: ", mode),
      paste0("# style: ", style),
      "library(scworkbench)",
      "library(jsonlite)",
      "",
      paste0("bundle_dir <- '", .wb_r_single_quote_escape(bundle_dir_literal), "'"),
      "bundle <- wb_open_bundle(bundle_dir)",
      "on.exit(wb_close_bundle(bundle), add = TRUE)",
      "sess <- wb_session_new()",
      "replay_map <- list()",
      "",
      "rewrite_run_refs <- function(x, replay_map) {",
      "  if (!is.list(x)) return(x)",
      "  if (identical(as.character(x$ref_type %||% '')[1], 'run')) {",
      "    old <- as.character(x$run_id %||% '')[1]",
      "    if (nzchar(old) && !is.null(replay_map[[old]])) x$run_id <- replay_map[[old]]",
      "    return(x)",
      "  }",
      "  y <- lapply(x, rewrite_run_refs, replay_map = replay_map)",
      "  if (!is.null(names(x))) names(y) <- names(x)",
      "  y",
      "}",
      ""
    )
    if (identical(mode, "literal")) {
      lines <- c(
        lines,
        paste0("replay_payload <- readRDS('", .wb_r_single_quote_escape(sidecar_rds_path), "')"),
        ""
      )
    }
  }

  for (rid in run_order) {
    i <- run_idx[[rid]]
    op_name <- as.character(runs$op_name[i])
    notes <- as.character(runs$notes[i] %||% "")
    if (identical(mode, "literal")) {
      lines <- c(
        lines,
        paste0("# run_id: ", rid, " op: ", op_name),
        paste0("entry <- replay_payload[['", .wb_r_single_quote_escape(rid), "']]"),
        "params <- entry$params %||% list()",
        "inputs <- rewrite_run_refs(entry$inputs %||% list(), replay_map = replay_map)",
        paste0("res <- do.call(wb_session_run_op, c(list(",
               "session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
               "inputs = inputs, notes = '", .wb_r_single_quote_escape(notes), "'), params))"),
        "sess <- res$session",
        paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
        ""
      )
    } else {
      if (identical(style, "bench_pretty")) {
        lines <- c(
          lines,
          paste0("# run_id: ", rid, " op: ", op_name),
          .wb_emit_r_object_assign("params", payload[[rid]]$params %||% list()),
          .wb_emit_r_object_assign("inputs", payload[[rid]]$inputs %||% list()),
          "inputs <- rewrite_run_refs(inputs, replay_map = replay_map)",
          paste0("res <- do.call(wb_session_run_op, c(list(",
                 "session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
                 "inputs = inputs, notes = '", .wb_r_single_quote_escape(notes), "'), params))"),
          "sess <- res$session",
          paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
          ""
        )
      } else {
        params_json <- jsonlite::toJSON(payload[[rid]]$params %||% list(), auto_unbox = TRUE, null = "null")
        inputs_json <- jsonlite::toJSON(payload[[rid]]$inputs %||% list(), auto_unbox = TRUE, null = "null")
        lines <- c(
          lines,
          paste0("# run_id: ", rid, " op: ", op_name),
          .wb_emit_r_paste0_chunks("params_json_txt", params_json),
          .wb_emit_r_paste0_chunks("inputs_json_txt", inputs_json),
          "params <- jsonlite::fromJSON(params_json_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)",
          "inputs <- jsonlite::fromJSON(inputs_json_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)",
          "inputs <- rewrite_run_refs(inputs, replay_map = replay_map)",
          paste0("res <- do.call(wb_session_run_op, c(list(",
                 "session = sess, bundle = bundle, op_name = '", .wb_r_single_quote_escape(op_name), "', ",
                 "inputs = inputs, notes = '", .wb_r_single_quote_escape(notes), "'), params))"),
          "sess <- res$session",
          paste0("replay_map[['", .wb_r_single_quote_escape(rid), "']] <- res$run$run_id"),
          ""
        )
      }
    }
  }

  lines <- c(
    lines,
    "# replay complete",
    "cat('replay complete\\n')",
    "cat('runs:', length(sess$runs), '\\n')"
  )

  paste(lines, collapse = "\n")
}

.wb_prov_snapshot_id_or_latest <- function(con, snapshot_id = NULL) {
  sid <- as.character(snapshot_id %||% "")[1]
  if (nzchar(sid)) return(sid)
  h <- DBI::dbGetQuery(con, "SELECT snapshot_id FROM prov_heads ORDER BY created_at DESC LIMIT 1;")
  .wb_assert(nrow(h) == 1, "No provenance snapshots available.")
  as.character(h$snapshot_id[1])
}

.wb_prov_select_runs <- function(con, sid) {
  has_sym <- .wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")
  has_exec <- .wb_db_has_column(con, "prov_runs", "execution_inputs_json")
  q <- paste0(
    "SELECT run_id, op_name, created_at, notes, params_json, inputs_json, ",
    if (has_sym) "symbolic_inputs_json" else "NULL AS symbolic_inputs_json",
    ", ",
    if (has_exec) "execution_inputs_json" else "NULL AS execution_inputs_json",
    " FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;"
  )
  DBI::dbGetQuery(con, q, params = list(sid))
}

.wb_prov_get_runs_order <- function(con, sid) {
  runs <- .wb_prov_select_runs(con, sid)
  .wb_assert(nrow(runs) > 0, paste0("No runs for snapshot_id: ", sid))

  edges <- DBI::dbGetQuery(
    con,
    "SELECT parent_run_id, child_run_id
     FROM prov_run_edges
     WHERE snapshot_id = ? AND edge_type IN ('depends_on_run','input_run_ref');",
    params = list(sid)
  )

  run_ids <- as.character(runs$run_id)
  if (!nrow(edges)) return(list(runs = runs, run_order = run_ids))

  indeg <- stats::setNames(integer(length(run_ids)), run_ids)
  kids <- stats::setNames(vector("list", length(run_ids)), run_ids)
  for (i in seq_len(nrow(edges))) {
    p <- as.character(edges$parent_run_id[i])
    c <- as.character(edges$child_run_id[i])
    if (!(p %in% run_ids) || !(c %in% run_ids)) next
    kids[[p]] <- c(kids[[p]], c)
    indeg[[c]] <- indeg[[c]] + 1L
  }
  q <- sort(names(indeg[indeg == 0L]))
  topo <- character(0)
  while (length(q)) {
    n <- q[1]
    q <- q[-1]
    topo <- c(topo, n)
    ch <- unique(as.character(kids[[n]] %||% character(0)))
    ch <- ch[ch %in% names(indeg)]
    for (c in ch) indeg[[c]] <- indeg[[c]] - 1L
    q <- sort(unique(c(q, names(indeg[indeg == 0L & !(names(indeg) %in% topo)]))))
  }
  run_order <- if (length(topo) == length(run_ids)) topo else run_ids
  list(runs = runs, run_order = run_order)
}

.wb_prov_payload_from_runs <- function(runs, run_order, mode = "symbolic") {
  payload <- list()
  run_idx <- stats::setNames(seq_len(nrow(runs)), as.character(runs$run_id))
  for (rid in run_order) {
    i <- run_idx[[rid]]
    sym_txt <- as.character(runs$symbolic_inputs_json[i] %||% "")[1]
    if (nzchar(sym_txt)) {
      inputs_use <- jsonlite::fromJSON(sym_txt, simplifyVector = TRUE, simplifyDataFrame = FALSE)
      if (is.null(inputs_use)) inputs_use <- list()
    } else {
      inputs_stored <- jsonlite::fromJSON(
        as.character(runs$inputs_json[i] %||% "{}"),
        simplifyVector = TRUE,
        simplifyDataFrame = FALSE
      )
      inputs_use <- .wb_prov_compact_inputs(inputs_stored)
    }
    if (identical(mode, "symbolic")) {
      inputs_use <- .wb_drop_key_recursive(inputs_use, key = "cell_ids")
    }
    params_use <- jsonlite::fromJSON(
      as.character(runs$params_json[i] %||% "{}"),
      simplifyVector = TRUE,
      simplifyDataFrame = FALSE
    )
    payload[[rid]] <- list(params = params_use, inputs = inputs_use)
  }
  payload
}

.wb_prov_output_hash <- function(prim) {
  kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
  sum_txt <- if (.wb_is_primitive(prim)) {
    jsonlite::toJSON(.wb_json_sanitize(.wb_prim_summary(prim)), auto_unbox = TRUE, null = "null")
  } else {
    paste(class(prim), collapse = ",")
  }
  .wb_hash_text(c(kind, sum_txt))
}

#' Validate reproducibility by replaying a persisted snapshot
#'
#' Replays persisted runs and compares output kind/hash against stored `prov_run_outputs`.
#'
#' @param bundle scworkbench bundle
#' @param snapshot_id Optional snapshot id (default latest)
#' @param mode Replay input mode: `symbolic` (default) or `literal`
#' @param profile Validation profile: `strict` (kind+hash), `kind_only`, or `none`
#' @param strict If TRUE, stop on first replay error
#' @return list with summary, per_run table, per_output table, and replay session
#' @export
wb_prov_validate_replay <- function(bundle,
                                    snapshot_id = NULL,
                                    mode = c("symbolic", "literal"),
                                    profile = c("strict", "kind_only", "none"),
                                    strict = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "provenance replay validation")
  mode <- match.arg(mode)
  profile <- match.arg(profile)

  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  sid <- .wb_prov_snapshot_id_or_latest(con, snapshot_id)
  rr <- .wb_prov_get_runs_order(con, sid)
  runs <- rr$runs
  run_order <- rr$run_order
  payload <- .wb_prov_payload_from_runs(runs, run_order, mode = mode)

  expected <- DBI::dbGetQuery(
    con,
    "SELECT run_id, output_name, primitive_kind, output_hash
     FROM prov_run_outputs
     WHERE snapshot_id = ?
     ORDER BY run_id, output_name;",
    params = list(sid)
  )
  exp_map <- list()
  if (nrow(expected)) {
    for (i in seq_len(nrow(expected))) {
      exp_map[[paste0(expected$run_id[i], "::", expected$output_name[i])]] <- list(
        kind = as.character(expected$primitive_kind[i]),
        hash = as.character(expected$output_hash[i])
      )
    }
  }

  replay_map <- list()
  sess <- wb_session_new()
  per_run <- list()
  per_out <- list()
  ri <- 0L
  oi <- 0L

  rewrite_run_refs <- function(x, replay_map) {
    if (!is.list(x)) return(x)
    if (identical(as.character(x$ref_type %||% "")[1], "run")) {
      old <- as.character(x$run_id %||% "")[1]
      if (nzchar(old) && !is.null(replay_map[[old]])) x$run_id <- replay_map[[old]]
      return(x)
    }
    y <- lapply(x, rewrite_run_refs, replay_map = replay_map)
    if (!is.null(names(x))) names(y) <- names(x)
    y
  }

  for (rid in run_order) {
    idx <- which(as.character(runs$run_id) == rid)[1]
    op_name <- as.character(runs$op_name[idx])
    notes <- as.character(runs$notes[idx] %||% "")[1]
    params <- payload[[rid]]$params %||% list()
    inputs <- rewrite_run_refs(payload[[rid]]$inputs %||% list(), replay_map = replay_map)

    err <- NULL
    out <- try(
      do.call(
        wb_session_run_op,
        c(
          list(session = sess, bundle = bundle, op_name = op_name, inputs = inputs, notes = notes),
          params
        )
      ),
      silent = TRUE
    )
    if (inherits(out, "try-error")) {
      err <- as.character(out)
      if (isTRUE(strict)) stop(err, call. = FALSE)
      ri <- ri + 1L
      per_run[[ri]] <- data.frame(
        run_id = rid,
        replay_run_id = NA_character_,
        op_name = op_name,
        status = "error",
        error = err,
        stringsAsFactors = FALSE
      )
      next
    }

    sess <- out$session
    replay_rid <- as.character(out$run$run_id)
    replay_map[[rid]] <- replay_rid

    ri <- ri + 1L
    per_run[[ri]] <- data.frame(
      run_id = rid,
      replay_run_id = replay_rid,
      op_name = op_name,
      status = "ok",
      error = NA_character_,
      stringsAsFactors = FALSE
    )

    outs <- out$run$outputs %||% list()
    for (nm in names(outs)) {
      prim <- outs[[nm]]
      actual_kind <- if (.wb_is_primitive(prim)) as.character(prim$kind %||% "unknown")[1] else "unknown"
      actual_hash <- .wb_prov_output_hash(prim)
      ex <- exp_map[[paste0(rid, "::", nm)]] %||% list(kind = NA_character_, hash = NA_character_)
      kind_match <- identical(as.character(ex$kind), as.character(actual_kind))
      hash_match <- identical(as.character(ex$hash), as.character(actual_hash))

      oi <- oi + 1L
      per_out[[oi]] <- data.frame(
        run_id = rid,
        replay_run_id = replay_rid,
        output_name = as.character(nm),
        expected_kind = as.character(ex$kind),
        actual_kind = as.character(actual_kind),
        expected_hash = as.character(ex$hash),
        actual_hash = as.character(actual_hash),
        kind_match = isTRUE(kind_match),
        hash_match = isTRUE(hash_match),
        output_match = FALSE,
        stringsAsFactors = FALSE
      )
      hash_required <- identical(profile, "strict")
      kind_required <- !identical(profile, "none")
      per_out[[oi]]$output_match <- if (!kind_required) {
        TRUE
      } else if (hash_required) {
        isTRUE(kind_match) && isTRUE(hash_match)
      } else {
        isTRUE(kind_match)
      }
    }
  }

  run_df <- if (length(per_run)) do.call(rbind, per_run) else data.frame(
    run_id = character(0), replay_run_id = character(0), op_name = character(0),
    status = character(0), error = character(0), stringsAsFactors = FALSE
  )
  out_df <- if (length(per_out)) do.call(rbind, per_out) else data.frame(
    run_id = character(0), replay_run_id = character(0), output_name = character(0),
    expected_kind = character(0), actual_kind = character(0), expected_hash = character(0),
    actual_hash = character(0), kind_match = logical(0), hash_match = logical(0), output_match = logical(0),
    stringsAsFactors = FALSE
  )

  list(
    snapshot_id = sid,
    summary = list(
      profile = profile,
      n_runs = nrow(run_df),
      n_run_errors = sum(run_df$status == "error"),
      n_outputs = nrow(out_df),
      n_kind_mismatch = sum(!out_df$kind_match),
      n_hash_mismatch = sum(!out_df$hash_match),
      valid = (sum(run_df$status == "error") == 0L) && (sum(!out_df$output_match) == 0L)
    ),
    per_run = run_df,
    per_output = out_df,
    replay_session = sess
  )
}

#' Freeze a provenance snapshot into a reproducibility packet
#'
#' Writes replay scripts, DAG JSON, run tables, and manifest into `out_dir`.
#'
#' @param bundle scworkbench bundle
#' @param out_dir Output directory (created if missing)
#' @param snapshot_id Optional snapshot id (default latest)
#' @param include_literal If TRUE, include literal replay sidecar (`.rds`)
#' @param replay_style Replay script style (`bench_pretty` or `raw_json`)
#' @param validate_replay If TRUE, run `wb_prov_validate_replay()` and write result files
#' @param validation_profile Validation profile passed to `wb_prov_validate_replay()`
#' @return list(snapshot_id, out_dir, files)
#' @export
wb_freeze_snapshot <- function(bundle,
                               out_dir,
                               snapshot_id = NULL,
                               include_literal = TRUE,
                               replay_style = c("bench_pretty", "raw_json"),
                               validate_replay = TRUE,
                               validation_profile = c("strict", "kind_only", "none")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_require_pkg("jsonlite", "freeze snapshot")
  replay_style <- match.arg(replay_style)
  validation_profile <- match.arg(validation_profile)
  .wb_assert(is.character(out_dir) && length(out_dir) == 1 && nzchar(out_dir), "out_dir must be non-empty path")

  con <- bundle$con
  .wb_migrate_provenance_tables(con)
  sid <- .wb_prov_snapshot_id_or_latest(con, snapshot_id)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list()

  # replay scripts
  sym_path <- file.path(out_dir, "replay_symbolic.R")
  sym_txt <- wb_prov_emit_r_script(
    bundle = bundle,
    snapshot_id = sid,
    bundle_dir_literal = bundle$dir %||% "<BUNDLE_DIR>",
    mode = "symbolic",
    style = replay_style
  )
  writeLines(sym_txt, con = sym_path, useBytes = TRUE)
  files$replay_symbolic <- sym_path

  if (isTRUE(include_literal)) {
    lit_path <- file.path(out_dir, "replay_literal.R")
    side_path <- file.path(out_dir, "replay_inputs.rds")
    lit_txt <- wb_prov_emit_r_script(
      bundle = bundle,
      snapshot_id = sid,
      bundle_dir_literal = bundle$dir %||% "<BUNDLE_DIR>",
      mode = "literal",
      style = replay_style,
      sidecar_rds_path = side_path
    )
    lit_txt <- gsub(
      pattern = paste0("readRDS('", side_path, "')"),
      replacement = "readRDS('replay_inputs.rds')",
      x = lit_txt,
      fixed = TRUE
    )
    writeLines(lit_txt, con = lit_path, useBytes = TRUE)
    files$replay_literal <- lit_path
    files$replay_inputs <- side_path
  }

  # DAG JSON
  dag <- wb_prov_dag(bundle, snapshot_id = sid)
  dag_path <- file.path(out_dir, "dag.json")
  jsonlite::write_json(dag, path = dag_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  files$dag_json <- dag_path

  # runs / outputs tables
  runs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, op_name, created_at, notes, run_hash
     FROM prov_runs WHERE snapshot_id = ? ORDER BY created_at, run_id;",
    params = list(sid)
  )
  runs_path <- file.path(out_dir, "runs.csv")
  utils::write.csv(runs, file = runs_path, row.names = FALSE)
  files$runs_csv <- runs_path

  outs <- DBI::dbGetQuery(
    con,
    "SELECT run_id, output_name, primitive_kind, output_hash, artifact_id
     FROM prov_run_outputs WHERE snapshot_id = ? ORDER BY run_id, output_name;",
    params = list(sid)
  )
  outs_path <- file.path(out_dir, "outputs.csv")
  utils::write.csv(outs, file = outs_path, row.names = FALSE)
  files$outputs_csv <- outs_path

  # replay validation
  if (isTRUE(validate_replay)) {
    val <- wb_prov_validate_replay(
      bundle,
      snapshot_id = sid,
      mode = "symbolic",
      profile = validation_profile,
      strict = FALSE
    )
    val_out <- list(
      snapshot_id = as.character(val$snapshot_id %||% sid),
      summary = val$summary %||% list(),
      per_run = val$per_run %||% data.frame(stringsAsFactors = FALSE),
      per_output = val$per_output %||% data.frame(stringsAsFactors = FALSE)
    )
    val_path <- file.path(out_dir, "validation.json")
    jsonlite::write_json(val_out, path = val_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
    files$validation_json <- val_path
  }

  # manifest
  manifest <- list(
    snapshot_id = sid,
    schema_version = .wb_prov_schema_version(),
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    bundle_dir = bundle$dir %||% NA_character_,
    files = files
  )
  man_path <- file.path(out_dir, "manifest.json")
  jsonlite::write_json(manifest, path = man_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  files$manifest_json <- man_path

  list(snapshot_id = sid, out_dir = out_dir, files = files)
}

.wb_prov_param_inline <- function(x) {
  if (is.null(x)) return("NULL")
  if (is.atomic(x)) {
    y <- as.character(x)
    if (!length(y)) return("<empty>")
    if (length(y) > 5L) y <- c(y[1:5], "...")
    return(paste(y, collapse = ","))
  }
  if (is.list(x)) return("<list>")
  as.character(x)
}

.wb_prov_params_inline <- function(params) {
  params <- params %||% list()
  if (!is.list(params) || !length(params)) return("none")
  nms <- names(params) %||% rep("", length(params))
  out <- character(0)
  for (i in seq_along(params)) {
    nm <- as.character(nms[[i]] %||% "")[1]
    if (!nzchar(nm)) nm <- paste0("param", i)
    out <- c(out, paste0(nm, "=", .wb_prov_param_inline(params[[i]])))
  }
  paste(out, collapse = "; ")
}

.wb_prov_write_report_scaffold <- function(bundle, snapshot_id, out_dir, freeze_files) {
  .wb_require_pkg("jsonlite", "freeze report scaffold")
  con <- bundle$con
  runs <- .wb_prov_select_runs(con, snapshot_id)

  md <- c(
    "# Analysis Freeze Report",
    "",
    paste0("- snapshot_id: ", snapshot_id),
    paste0("- schema_version: ", .wb_prov_schema_version()),
    paste0("- generated_at: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
    ""
  )

  if (!nrow(runs)) {
    md <- c(md, "No runs in snapshot.", "")
  } else {
    md <- c(md, "## Methods (Draft)", "")
    for (i in seq_len(nrow(runs))) {
      rid <- as.character(runs$run_id[i])
      op_name <- as.character(runs$op_name[i])
      params <- jsonlite::fromJSON(as.character(runs$params_json[i] %||% "{}"), simplifyVector = FALSE)
      sym <- jsonlite::fromJSON(as.character(runs$symbolic_inputs_json[i] %||% "null"), simplifyVector = FALSE)
      cell_set <- as.character(sym$cell_set %||% "all")[1]
      ptxt <- .wb_prov_params_inline(params)
      md <- c(
        md,
        paste0("- `", rid, "`: op `", op_name, "` on cell_set `", cell_set, "`. Params: ", ptxt, ".")
      )
    }
    md <- c(md, "")
  }

  md <- c(md, "## Files", "")
  fn <- names(freeze_files)
  if (!length(fn)) {
    md <- c(md, "- none", "")
  } else {
    for (nm in fn) {
      md <- c(md, paste0("- ", nm, ": ", basename(as.character(freeze_files[[nm]]))))
    }
    md <- c(md, "")
  }

  path <- file.path(out_dir, "report_draft.md")
  writeLines(md, con = path, useBytes = TRUE)
  path
}

#' Freeze snapshot + report scaffold in one call
#'
#' Convenience wrapper for agent/client workflows. Runs `wb_freeze_snapshot()`
#' and optionally adds a lightweight `report_draft.md` methods scaffold.
#'
#' @inheritParams wb_freeze_snapshot
#' @param include_report If TRUE, emit `report_draft.md`
#' @return list(snapshot_id, out_dir, files)
#' @export
wb_freeze_packet <- function(bundle,
                             out_dir,
                             snapshot_id = NULL,
                             include_literal = TRUE,
                             replay_style = c("bench_pretty", "raw_json"),
                             validate_replay = TRUE,
                             validation_profile = c("strict", "kind_only", "none"),
                             include_report = TRUE) {
  replay_style <- match.arg(replay_style)
  validation_profile <- match.arg(validation_profile)

  fr <- wb_freeze_snapshot(
    bundle = bundle,
    out_dir = out_dir,
    snapshot_id = snapshot_id,
    include_literal = include_literal,
    replay_style = replay_style,
    validate_replay = validate_replay,
    validation_profile = validation_profile
  )

  files <- fr$files %||% list()
  if (isTRUE(include_report)) {
    report_path <- .wb_prov_write_report_scaffold(
      bundle = bundle,
      snapshot_id = fr$snapshot_id,
      out_dir = out_dir,
      freeze_files = files
    )
    files$report_draft_md <- report_path
  }

  list(snapshot_id = fr$snapshot_id, out_dir = fr$out_dir, files = files)
}
