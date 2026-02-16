# R/promote_primitives.R
# Promotion v2: primitives-first
#
# - Uses .wb_ops() as the sole op contract
# - Uses run$outputs (wb_primitive) as the sole source of promotable data
# - No .wb_op_spec(), no .wb_op_registry(), no saveable_outputs registry
#
# Output names are the run output names: clusters, pseudotime, curves, space_2d, model, ...
# Artifact type is determined from primitive kind.
# ---- mapping: primitive kind -> promoter function ----
# Keep this small. This is your "promotion kernel".
.wb_promoters_by_kind <- function() {
  list(
    cell_vector         = .wb_promote_cell_vector,
    cell_vector_family  = .wb_promote_cell_vector_family,
    path_2d_family      = .wb_promote_path_2d_family,
    space_2d            = .wb_promote_space_2d_ref,
    model_ref           = .wb_promote_model_ref
  )
}

.wb_get_promoter_for_kind <- function(kind) {
  regs <- .wb_promoters_by_kind()
  fn <- regs[[kind]]
  .wb_assert(!is.null(fn), paste0("No promoter registered for primitive kind: ", kind))
  fn
}

.wb_db_append_chunked <- function(con, table, df, chunk_size = 1000L) {
  if (is.null(df) || nrow(df) == 0) return(invisible(TRUE))
  chunk_size <- as.integer(chunk_size)
  .wb_assert(chunk_size >= 1L, "chunk_size must be >= 1")

  n <- nrow(df)
  idx <- seq.int(1L, n, by = chunk_size)
  for (i in idx) {
    j <- min(i + chunk_size - 1L, n)
    sub <- df[i:j, , drop = FALSE]
    # dbAppendTable avoids some sqlite temp-file issues seen with large dbWriteTable append calls.
    DBI::dbAppendTable(con, table, sub)
  }
  invisible(TRUE)
}

# ---- New promotion entrypoint: promote analysis DAG from runs ----
#' Promote a session analysis DAG to persisted artifacts
#' @export
wb_promote_analysis <- function(bundle,
                                runs,
                                head_run_id,
                                name_prefix = NULL,
                                description = NULL,
                                created_by = NULL,
                                fail_fast = TRUE) {

  .wb_assert(is.list(runs) && length(runs) > 0, "runs must be a non-empty list.")
  # ensure named by run_id
  if (is.null(names(runs)) || any(names(runs) == "")) {
    ids <- vapply(runs, function(r) r$run_id, character(1))
    names(runs) <- ids
  }
  .wb_assert(all(vapply(runs, wb_is_run, logical(1))), "runs must contain wb_run objects.")
  heads <- as.character(head_run_id)
  .wb_assert(length(heads) >= 1, "head_run_id must have length >= 1.")
  .wb_assert(all(heads %in% names(runs)), "One or more head_run_id not in runs.")

  # topo order by DFS postorder
  visited <- new.env(parent = emptyenv())
  topo <- character(0)
  visit <- function(rid) {
    if (exists(rid, envir = visited, inherits = FALSE)) return(invisible(TRUE))
    assign(rid, TRUE, envir = visited)
    run <- runs[[rid]]
    parents <- run$inputs$parents %||% character(0)
    for (p in parents) visit(p)
    topo <<- c(topo, rid)
    invisible(TRUE)
  }
  for (h in heads) visit(h)

  # Artifact pool: lets downstream promotions reference upstream artifacts if they want
  # (most primitive promoters won't need it, but keep it for provenance)
  artifact_pool <- list()

  rows <- list()
  row_i <- 0L

  for (rid in topo) {
    run <- runs[[rid]]
    op <- .wb_get_op(run$op_name)

    # only promote outputs declared promotable by op contract
    promotable <- op$promotable %||% character(0)

    # optional name seed
    nm <- NULL
    if (!is.null(name_prefix) && nzchar(name_prefix)) {
      nm <- paste0(name_prefix, "__", run$op_name, "__", substr(run$run_id, 1, 12))
    }

    # promote each promotable output that exists on the run
    promoted_ids <- list()
    err <- NULL

    tryCatch({
      for (out_name in promotable) {
        if (!out_name %in% names(run$outputs)) next

        prim <- run$outputs[[out_name]]
        .wb_assert(.wb_is_primitive(prim),
                   paste0("Run output '", out_name, "' is not a wb_primitive (kind missing)."))

        promoter <- .wb_get_promoter_for_kind(prim$kind)

        # Each promoter returns an artifact_id
        artifact_id <- promoter(
          bundle = bundle,
          run = run,
          out_name = out_name,
          prim = prim,
          name = nm,
          description = description,
          created_by = created_by,
          parent_artifacts = artifact_pool
        )

        promoted_ids[[out_name]] <- artifact_id
      }
    }, error = function(e) {
      err <<- conditionMessage(e)
      if (isTRUE(fail_fast)) stop(e)
    })

    if (length(promoted_ids)) {
      # update pool so later promotions can reference earlier ones
      for (k in names(promoted_ids)) {
        if (is.null(artifact_pool[[k]]) || !nzchar(artifact_pool[[k]])) {
          artifact_pool[[k]] <- promoted_ids[[k]]
        }
      }

      for (out_name in names(promoted_ids)) {
        row_i <- row_i + 1L
        rows[[row_i]] <- data.frame(
          run_id = run$run_id,
          op_name = run$op_name,
          output = out_name,
          artifact_id = as.character(promoted_ids[[out_name]]),
          status = "ok",
          error = NA_character_,
          stringsAsFactors = FALSE
        )
      }
    } else {
      row_i <- row_i + 1L
      rows[[row_i]] <- data.frame(
        run_id = run$run_id,
        op_name = run$op_name,
        output = NA_character_,
        artifact_id = NA_character_,
        status = if (is.null(err)) "skipped" else "error",
        error = if (is.null(err)) NA_character_ else err,
        stringsAsFactors = FALSE
      )
    }
  }

  promoted_df <- do.call(rbind, rows)

  list(
    artifact_pool = artifact_pool,
    promoted = promoted_df
  )
}

# ------------------------------------------------------------------
# Primitive promoters
# ------------------------------------------------------------------

.wb_new_artifact_id <- function(prefix) {
  paste0(prefix, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
         paste0(sample(c(0:9, letters), 8, TRUE), collapse=""))
}


# ---- cell_vector -> artifacts + artifact_labels ----
# Your existing schema already has artifacts + artifact_labels; we use it.
.wb_promote_cell_vector <- function(bundle, run, out_name, prim,
                                    name = NULL, description = NULL, created_by = NULL,
                                    parent_artifacts = list()) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "cell_vector", "Expected kind=cell_vector")
  .wb_assert(!is.null(prim$cell_id) && !is.null(prim$value), "cell_vector missing fields")
  .wb_assert(length(prim$cell_id) == length(prim$value), "cell_vector: cell_id/value length mismatch")

  artifact_id <- .wb_new_artifact_id("cell_vector")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  # Write artifact metadata
  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "cell_vector",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  # Store as labels table for now (value as label)
  df <- data.frame(
    artifact_id = artifact_id,
    cell_id = as.character(prim$cell_id),
    label = as.character(prim$value),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_labels", df, chunk_size = 1000L)

  artifact_id
}

# ---- cell_vector_family -> artifact_pseudotime (fits your schema) ----
.wb_promote_cell_vector_family <- function(bundle, run, out_name, prim,
                                           name = NULL, description = NULL, created_by = NULL,
                                           parent_artifacts = list()) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "cell_vector_family", "Expected kind=cell_vector_family")
  .wb_assert(!is.null(prim$key) && !is.null(prim$cell_id) && !is.null(prim$value), "cell_vector_family missing fields")
  .wb_assert(length(prim$key) == length(prim$cell_id) && length(prim$key) == length(prim$value),
             "cell_vector_family: key/cell_id/value length mismatch")

  artifact_id <- .wb_new_artifact_id("cell_vector_family")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "cell_vector_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  # For pseudotime: reuse artifact_pseudotime table
  pt <- data.frame(
    artifact_id = artifact_id,
    cell_id = as.character(prim$cell_id),
    lineage_id = as.character(prim$key),
    pseudotime = as.numeric(prim$value),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_pseudotime", pt, chunk_size = 1000L)

  artifact_id
}

# ---- path_2d_family -> artifact_curves_2d ----
.wb_promote_path_2d_family <- function(bundle, run, out_name, prim,
                                       name = NULL, description = NULL, created_by = NULL,
                                       parent_artifacts = list()) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "path_2d_family", "Expected kind=path_2d_family")
  .wb_assert(!is.null(prim$key) && !is.null(prim$point) && !is.null(prim$x) && !is.null(prim$y),
             "path_2d_family missing fields")
  .wb_assert(length(prim$key) == length(prim$point) &&
               length(prim$key) == length(prim$x) &&
               length(prim$key) == length(prim$y),
             "path_2d_family: length mismatch")

  artifact_id <- .wb_new_artifact_id("path_2d_family")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "path_2d_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  cv <- data.frame(
    artifact_id = artifact_id,
    lineage_id = as.character(prim$key),
    point = as.integer(prim$point),
    x = as.numeric(prim$x),
    y = as.numeric(prim$y),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_curves_2d", cv, chunk_size = 1000L)

  artifact_id
}

# ---- space_2d and model_ref promoters (optional snapshot/reference) ----
.wb_promote_space_2d_ref <- function(bundle, run, out_name, prim,
                                     name = NULL, description = NULL, created_by = NULL,
                                     parent_artifacts = list()) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "space_2d", "Expected kind=space_2d")
  space_id <- prim$space_id
  .wb_assert(!is.null(space_id) && nzchar(space_id), "space_2d missing space_id")

  # Here you can either:
  # A) snapshot coords into artifact_space_2d (like your old .wb_promote_space_2d)
  # B) store only a reference "space_2d_ref"
  #
  # I’m choosing A because you already have artifact_space_2d and it’s robust.
  df <- DBI::dbGetQuery(con,
                        "SELECT cell_id, x, y FROM space_2d WHERE space_id = ?;",
                        params = list(space_id)
  )
  .wb_assert(nrow(df) > 0, paste0("No coordinates found in space_2d for space_id=", space_id))

  artifact_id <- .wb_new_artifact_id("space2d")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "space_2d",
    name %||% paste0(space_id, " (2D coords)"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    space_id,
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  out <- df
  out$artifact_id <- artifact_id
  out <- out[, c("artifact_id", "cell_id", "x", "y")]
  .wb_db_append_chunked(con, "artifact_space_2d", out, chunk_size = 1000L)

  artifact_id
}

.wb_promote_model_ref <- function(bundle, run, out_name, prim,
                                  name = NULL, description = NULL, created_by = NULL,
                                  parent_artifacts = list()) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "model_ref", "Expected kind=model_ref")
  space_id <- prim$space_id %||% prim$model_space_id
  .wb_assert(!is.null(space_id) && nzchar(space_id), "model_ref must include space_id/model_space_id")

  # expects you already write model to disk via wb_space_model_path(bundle, space_id)
  model_path <- wb_space_model_path(bundle, space_id)
  .wb_assert(file.exists(model_path), paste0("UMAP model file not found: ", model_path))

  artifact_id <- .wb_new_artifact_id("umap_model")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "umap_model",
    name %||% paste0(space_id, " (UMAP model)"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  .wb_db_append_chunked(con, "artifact_umap_model", data.frame(
    artifact_id = artifact_id,
    space_id = space_id,
    model_path = model_path,
    stringsAsFactors = FALSE
  ), chunk_size = 1000L)

  artifact_id
}

#' @export
wb_migrate_artifacts <- function(bundle) {
  con <- bundle$con

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifacts (
      artifact_id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT,
      description TEXT,
      created_at TEXT NOT NULL,
      created_by TEXT,
      source_op TEXT,
      input_space_id TEXT,
      input_matrix_id TEXT,
      cell_set TEXT,
      provenance_json TEXT NOT NULL,
      scworkbench_version TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_labels (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY (artifact_id, cell_id)
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(type);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_labels_artifact ON artifact_labels(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_pseudotime (
    artifact_id TEXT NOT NULL,
    cell_id TEXT NOT NULL,
    lineage_id TEXT NOT NULL,
    pseudotime REAL NOT NULL,
    PRIMARY KEY (artifact_id, cell_id, lineage_id)
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_pt_artifact ON artifact_pseudotime(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_curves_2d (
    artifact_id TEXT NOT NULL,
    lineage_id TEXT NOT NULL,
    point INTEGER NOT NULL,
    x REAL NOT NULL,
    y REAL NOT NULL,
    PRIMARY KEY (artifact_id, lineage_id, point)
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_curve_artifact ON artifact_curves_2d(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_space_2d (
    artifact_id TEXT NOT NULL,
    cell_id     TEXT NOT NULL,
    x           REAL NOT NULL,
    y           REAL NOT NULL,
    PRIMARY KEY (artifact_id, cell_id)
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_space2d_artifact ON artifact_space_2d(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_umap_model (
    artifact_id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL,
    model_path TEXT NOT NULL
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_umap_model_space ON artifact_umap_model(space_id);")



  invisible(TRUE)
}

#' @keywords internal
.wb_run_input_space_id <- function(run) {
  # 1) Prefer op params (best canonical)
  x <- run$params$space_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  # 2) Fall back to user_inputs (covers old runs / ops that didn't set params)
  ui <- run$inputs$user_inputs %||% list()
  x <- ui$space_id %||% ui$space %||% ui$space_2d %||% ui$in_space %||% ui$in_space_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  NA_character_
}

#' @keywords internal
.wb_run_input_matrix_id <- function(run) {
  x <- run$params$matrix_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  ui <- run$inputs$user_inputs %||% list()
  x <- ui$matrix_id %||% ui$matrix %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  NA_character_
}
