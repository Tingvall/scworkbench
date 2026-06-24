# -------------------------
# Cell set recipes (provenance)
# -------------------------

#' Ensure the cell_set_recipes table exists
#'
#' Internal helper. Stores a single "latest" recipe per cell_set.
#'
#' Schema:
#' - cell_set TEXT PRIMARY KEY
#' - recipe_json TEXT NOT NULL
#' - created_at TEXT NOT NULL
#' - created_by TEXT
#' - source TEXT
#' - description TEXT
#'
#' @keywords internal
.wb_ensure_cell_set_recipes_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_recipes (
      cell_set     TEXT PRIMARY KEY,
      recipe_json  TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      created_by   TEXT,
      source       TEXT,
      description  TEXT
    );
  ")
  have <- DBI::dbListFields(con, "cell_set_recipes")
  add_col <- function(name, type) {
    if (name %in% have) return(invisible(NULL))
    DBI::dbExecute(con, paste0("ALTER TABLE cell_set_recipes ADD COLUMN ", name, " ", type, ";"))
  }
  add_col("role", "TEXT")
  add_col("status", "TEXT")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csr_set ON cell_set_recipes(cell_set);")
  invisible(TRUE)
}

#' @keywords internal
.wb_now_sqlite <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}

#' @keywords internal
.wb_normalize_cell_set <- function(cell_set) {
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set), "cell_set invalid")
  if (!startsWith(cell_set, "set:") && !identical(cell_set, "core") && !identical(cell_set, "all")) {
    cell_set <- paste0("set:", cell_set)
  }
  cell_set
}

#' @keywords internal
.wb_extract_recipe_from_cells <- function(cells) {
  if (is.null(cells)) return(NULL)
  attr(cells, "wb_recipe", exact = TRUE)
}

#' @keywords internal
.wb_recipe_to_json <- function(recipe) {
  if (is.null(recipe)) return(NULL)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Missing suggested package 'jsonlite' for recipe serialization.", call. = FALSE)
  }

  # If it's already a JSON string, keep it (best-effort check).
  if (is.character(recipe) && length(recipe) == 1 && nzchar(recipe)) {
    # Try to validate quickly; if invalid, we still store as string to avoid data loss.
    ok <- TRUE
    tryCatch(jsonlite::fromJSON(recipe), error = function(e) ok <<- FALSE)
    if (ok) return(recipe)
    return(jsonlite::toJSON(list(type = "raw_string", value = recipe), auto_unbox = TRUE))
  }

  # Otherwise serialize list/object
  jsonlite::toJSON(recipe, auto_unbox = TRUE, null = "null")
}

.wb_cell_set_roles <- function() {
  c("core", "annotation", "analysis_universe", "exclusion_set", "endpoint_set", "diagnostic", "temporary")
}

.wb_cell_set_statuses <- function() {
  c("active", "candidate", "accepted", "superseded", "rejected", "temporary")
}

.wb_cell_set_recipe_row_upsert <- function(bundle,
                                           cell_set,
                                           recipe_json,
                                           created_at,
                                           created_by = NULL,
                                           source = NULL,
                                           description = NULL,
                                           role = NULL,
                                           status = NULL) {
  con <- bundle$con
  .wb_ensure_cell_set_recipes_table(con)
  DBI::dbExecute(
    con,
    "
      INSERT INTO cell_set_recipes(
        cell_set, recipe_json, created_at, created_by, source, description, role, status
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(cell_set) DO UPDATE SET
        recipe_json = excluded.recipe_json,
        created_at  = excluded.created_at,
        created_by  = excluded.created_by,
        source      = excluded.source,
        description = excluded.description,
        role        = excluded.role,
        status      = excluded.status;
    ",
    params = list(
      as.character(cell_set)[1],
      as.character(recipe_json %||% "")[1],
      as.character(created_at)[1],
      as.character(created_by %||% NA_character_)[1],
      as.character(source %||% NA_character_)[1],
      as.character(description %||% NA_character_)[1],
      as.character(role %||% NA_character_)[1],
      as.character(status %||% NA_character_)[1]
    )
  )
  invisible(TRUE)
}

.wb_cell_set_recipe_steps <- function(recipe) {
  if (!is.list(recipe)) return(list())
  steps <- recipe$steps %||% list()
  if (!is.list(steps)) list() else steps
}

.wb_cell_set_step_source <- function(step) {
  sel <- as.character(step$sel %||% "")[1]
  args <- step$args %||% list()
  if (identical(sel, "wb_sel_set")) return(list(kind = "cell_set", id = paste(as.character(args$sets %||% ""), collapse = ",")))
  if (identical(sel, "wb_sel_meta")) return(list(kind = "metadata", id = as.character(args$col %||% "")[1]))
  if (identical(sel, "wb_sel_vector") || identical(sel, "wb_sel_vector_values")) return(list(kind = "cell_vector", id = as.character(args$vector_id %||% "")[1]))
  if (identical(sel, "wb_sel_vector_family")) return(list(kind = "cell_vector_family", id = paste(c(as.character(args$vector_id %||% "")[1], as.character(args$key %||% "")[1]), collapse = ":")))
  if (identical(sel, "wb_sel_expr")) return(list(kind = "matrix_feature", id = paste(c(as.character(args$matrix_id %||% "")[1], as.character(args$feature_id %||% "")[1]), collapse = ":")))
  if (identical(sel, "wb_sel_space_box")) return(list(kind = "space", id = as.character(args$space_id %||% "")[1]))
  list(kind = "selector", id = sel)
}

.wb_cell_set_rule_description <- function(step) {
  sel <- as.character(step$sel %||% "unknown")[1]
  args <- step$args %||% list()
  vals <- names(args)
  vals <- vals[nzchar(vals)]
  if (!length(vals)) return(sel)
  paste0(sel, "(", paste(paste0(vals, "=", vapply(args[vals], function(x) paste(as.character(x), collapse = ","), character(1))), collapse = "; "), ")")
}

.wb_replay_selector_step <- function(bundle, current, step) {
  sel <- as.character(step$sel %||% "")[1]
  args <- step$args %||% list()
  if (identical(sel, "wb_sel_not") && isTRUE(args$has_universe %||% FALSE) && is.null(args$universe)) {
    return(NULL)
  }
  x <- current %||% bundle
  tryCatch(
    switch(
      sel,
      wb_sel_all = wb_sel_all(x, cell_set = args$cell_set %||% "core", dataset_id = args$dataset_id %||% NULL, bundle = bundle),
      wb_sel_set = wb_sel_set(x, sets = as.character(args$sets %||% character(0)), bundle = bundle),
      wb_sel_meta = {
        if (!is.null(args$values)) wb_sel_meta(x, col = as.character(args$col)[1], values = args$values, bundle = bundle)
        else wb_sel_meta(x, col = as.character(args$col)[1], min = args$min %||% NULL, max = args$max %||% NULL, bundle = bundle)
      },
      wb_sel_vector = wb_sel_vector(x, vector_id = as.character(args$vector_id)[1], min = args$min %||% NULL, max = args$max %||% NULL, na.rm = isTRUE(args$na.rm %||% TRUE), bundle = bundle),
      wb_sel_vector_values = wb_sel_vector_values(x, vector_id = as.character(args$vector_id)[1], values = args$values, na.rm = isTRUE(args$na.rm %||% TRUE), bundle = bundle),
      wb_sel_vector_family = wb_sel_vector_family(x, vector_id = as.character(args$vector_id)[1], key = as.character(args$key)[1], min = args$min %||% NULL, max = args$max %||% NULL, na.rm = isTRUE(args$na.rm %||% TRUE), bundle = bundle),
      wb_sel_expr = wb_sel_expr(x, matrix_id = as.character(args$matrix_id)[1], feature_id = as.character(args$feature_id)[1], min = args$min %||% NULL, max = args$max %||% NULL, na.rm = isTRUE(args$na.rm %||% TRUE), bundle = bundle),
      wb_sel_space_box = wb_sel_space_box(x, space_id = as.character(args$space_id)[1], xmin = args$xmin, xmax = args$xmax, ymin = args$ymin, ymax = args$ymax, bundle = bundle),
      wb_sel_not = wb_sel_not(x, universe = args$universe %||% NULL, bundle = bundle),
      NULL
    ),
    error = function(e) NULL
  )
}

.wb_cell_set_rule_table <- function(bundle, recipe, final_cells) {
  steps <- .wb_cell_set_recipe_steps(recipe)
  if (!length(steps)) {
    return(data.frame(
      rule_index = integer(0),
      rule_type = character(0),
      input_n = integer(0),
      output_n = integer(0),
      n_removed = integer(0),
      rule_description = character(0),
      source_kind = character(0),
      source_id = character(0),
      field = character(0),
      operator = character(0),
      value = character(0),
      stringsAsFactors = FALSE
    ))
  }
  rows <- vector("list", length(steps))
  current <- NULL
  for (i in seq_along(steps)) {
    step <- steps[[i]]
    input_n <- if (is.null(current)) length(wb_cells(bundle, cell_set = "all")) else length(current)
    next_cells <- .wb_replay_selector_step(bundle, current, step)
    if (is.null(next_cells)) {
      next_cells <- if (i == length(steps)) final_cells else character(0)
    }
    output_n <- length(next_cells)
    src <- .wb_cell_set_step_source(step)
    args <- step$args %||% list()
    rows[[i]] <- data.frame(
      rule_index = as.integer(i),
      rule_type = as.character(step$sel %||% "unknown")[1],
      input_n = as.integer(input_n),
      output_n = as.integer(output_n),
      n_removed = as.integer(max(0L, input_n - output_n)),
      rule_description = .wb_cell_set_rule_description(step),
      source_kind = as.character(src$kind %||% "")[1],
      source_id = as.character(src$id %||% "")[1],
      field = as.character(args$col %||% args$vector_id %||% args$feature_id %||% args$space_id %||% "")[1],
      operator = if (!is.null(args$values)) "in" else if (!is.null(args$min) || !is.null(args$max)) "range" else as.character(step$sel %||% "")[1],
      value = paste(as.character(args$values %||% c(args$min %||% character(0), args$max %||% character(0))), collapse = ","),
      stringsAsFactors = FALSE
    )
    current <- next_cells
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# -------------------------
# Public API
# -------------------------

#' Define a cell set (persist membership + optionally persist recipe)
#'
#' This is the "promotable" version of tagging:
#' - Writes membership (either REPLACE or ADD depending on overwrite=).
#' - Optionally stores a provenance recipe in `cell_set_recipes`.
#'
#' The recipe can be supplied explicitly via `recipe=`, or taken from
#' `attr(cells, "wb_recipe")` when `cells` comes from selector pipelines.
#'
#' @param bundle scworkbench bundle handle
#' @param cell_set Target set name. Accepts "set:foo" or "foo" (auto-prefixes to "set:foo").
#' @param cells Character vector of cell_ids (optionally bundle-attached from selectors).
#' @param overwrite If TRUE, set becomes exactly `cells` (replace). If FALSE, adds `cells` to set (union).
#' @param source Provenance tag for membership rows (stored in membership table).
#' @param created_by Optional author.
#' @param description Optional description stored on both membership rows and recipe row.
#' @param store_recipe If TRUE, writes a recipe row if a recipe is available (or provided).
#' @param recipe Optional explicit recipe (list or JSON string). If NULL, tries attr(cells,"wb_recipe").
#' @param role Optional lifecycle role for the cell set.
#' @param status Optional lifecycle status for the cell set.
#'
#' @return Invisible list summary: cell_set, n_written, recipe_stored (TRUE/FALSE).
#' @export
wb_cell_set_define <- function(bundle,
                               cell_set,
                               cells,
                               overwrite = TRUE,
                               source = "rule",
                               created_by = NULL,
                               description = NULL,
                               store_recipe = TRUE,
                               recipe = NULL,
                               role = NULL,
                               status = NULL) {

  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  cell_set <- .wb_normalize_cell_set(cell_set)

  .wb_assert(is.character(cells) && length(cells) > 0,
             "cells must be a non-empty character vector of cell_ids")
  cell_ids <- unique(as.character(cells))
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0, "cells empty after cleaning")

  # 1) Persist membership
  mem_res <- NULL
  if (isTRUE(overwrite)) {
    # Replace: set becomes exactly these cells
    mem_res <- wb_cell_set_replace(
      bundle      = bundle,
      cell_set    = cell_set,
      cell_ids    = cell_ids,
      source      = source,
      created_by  = created_by,
      description = description,
      strict      = TRUE
    )
  } else {
    # Add/union: keep existing members, add these cells
    mem_res <- wb_cell_set_add(
      bundle      = bundle,
      cell_set    = cell_set,
      cell_ids    = cell_ids,
      source      = source,
      created_by  = created_by,
      description = description
    )
  }

  # 2) Persist recipe (optional)
  recipe_stored <- FALSE
  if (isTRUE(store_recipe)) {
    rec <- recipe %||% .wb_extract_recipe_from_cells(cells)
    rec_json <- .wb_recipe_to_json(rec)

    if (!is.null(rec_json) && nzchar(rec_json)) {
      created_at <- .wb_now_sqlite()
      .wb_cell_set_recipe_row_upsert(
        bundle = bundle,
        cell_set = cell_set,
        recipe_json = rec_json,
        created_at = created_at,
        created_by = created_by,
        source = source,
        description = description,
        role = role,
        status = status
      )

      recipe_stored <- TRUE
    }
  }

  # Normalize output summary
  n_written <- mem_res$n_written %||% mem_res$n_added %||% mem_res$n %||% length(cell_ids)

  invisible(list(
    cell_set      = cell_set,
    overwrite     = isTRUE(overwrite),
    n_written     = as.integer(n_written),
    recipe_stored = recipe_stored,
    role          = role,
    status        = status
  ))
}

#' Derive A Named Cell Set With Lifecycle Manifest
#'
#' Materializes a claim-supporting cell universe as a named membership-backed
#' cell set and returns promotable manifest tables. This is the lifecycle-aware
#' counterpart to exploratory selector pipelines.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param cell_set Target set name. Accepts `"set:name"` or `"name"`.
#' @param cells Character vector of cell IDs, ideally carrying `wb_recipe()`
#'   metadata from selector pipelines.
#' @param role Lifecycle role such as `"analysis_universe"` or
#'   `"endpoint_set"`.
#' @param status Lifecycle status such as `"candidate"` or `"accepted"`.
#' @param source Provenance/source label stored on membership rows.
#' @param created_by Optional author.
#' @param description Human-readable derivation description.
#' @param recipe Optional explicit recipe object or JSON. Defaults to
#'   `wb_recipe(cells)` when available.
#' @param overwrite Replace existing membership for this set.
#' @param promote_manifest If `TRUE`, immediately promote the manifest outputs
#'   using `wb_promote_analysis()`. Session workflows should usually leave this
#'   `FALSE` and promote the session run.
#'
#' @return Standard op-style result with `outputs$manifest` and
#'   `outputs$rule_table`, plus optional `promoted` when
#'   `promote_manifest=TRUE`.
#' @export
wb_cell_set_derive <- function(bundle,
                               cell_set,
                               cells,
                               role = "analysis_universe",
                               status = "candidate",
                               source = "selector_recipe",
                               created_by = NULL,
                               description = NULL,
                               recipe = NULL,
                               overwrite = TRUE,
                               promote_manifest = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  cell_set <- .wb_normalize_cell_set(cell_set)
  role <- as.character(role %||% "analysis_universe")[1]
  status <- as.character(status %||% "candidate")[1]
  .wb_assert(role %in% .wb_cell_set_roles(), paste0("role must be one of: ", paste(.wb_cell_set_roles(), collapse = ", ")))
  .wb_assert(status %in% .wb_cell_set_statuses(), paste0("status must be one of: ", paste(.wb_cell_set_statuses(), collapse = ", ")))
  .wb_assert(is.character(cells), "cells must be a character vector")
  cell_ids <- unique(as.character(cells))
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0L, "cells empty after cleaning")

  rec <- recipe %||% .wb_extract_recipe_from_cells(cells)
  rec_json <- .wb_recipe_to_json(rec)
  recipe_available <- !is.null(rec_json) && nzchar(rec_json)
  if (!recipe_available) {
    rec <- list(
      version = 1L,
      created_at = .wb_now_sqlite(),
      derivation_type = "explicit_cell_ids_from_run_inputs",
      limitation = "No selector recipe metadata was available; membership was derived from explicit cell IDs."
    )
    rec_json <- .wb_recipe_to_json(rec)
  }

  base_n <- length(wb_cells(bundle, cell_set = "all"))
  rule_tbl <- if (recipe_available) .wb_cell_set_rule_table(bundle, rec, cell_ids) else data.frame(
    rule_index = 1L,
    rule_type = "explicit_cell_ids",
    input_n = as.integer(base_n),
    output_n = as.integer(length(cell_ids)),
    n_removed = as.integer(max(0L, base_n - length(cell_ids))),
    rule_description = "explicit cell_ids without selector recipe",
    source_kind = "explicit_cell_ids",
    source_id = "",
    field = "",
    operator = "explicit",
    value = "",
    stringsAsFactors = FALSE
  )
  if (nrow(rule_tbl)) base_n <- as.integer(rule_tbl$input_n[1])

  def <- wb_cell_set_define(
    bundle = bundle,
    cell_set = cell_set,
    cells = cell_ids,
    overwrite = overwrite,
    source = source,
    created_by = created_by,
    description = description,
    store_recipe = TRUE,
    recipe = rec,
    role = role,
    status = status
  )
  created_at <- .wb_now_sqlite()
  recipe_row <- wb_get_cell_set_recipe(bundle, cell_set = cell_set, parse = FALSE)
  if (nrow(recipe_row)) created_at <- as.character(recipe_row$created_at[1])

  source_kind <- if (nrow(rule_tbl)) as.character(rule_tbl$source_kind[1]) else as.character(source %||% "")[1]
  source_id <- if (nrow(rule_tbl)) as.character(rule_tbl$source_id[1]) else ""
  manifest <- data.frame(
    cell_set = cell_set,
    role = role,
    status = status,
    n_cells = as.integer(length(wb_cells(bundle, cell_set = cell_set))),
    base_n = as.integer(base_n),
    created_by = as.character(created_by %||% "")[1],
    created_at = created_at,
    description = as.character(description %||% "")[1],
    recipe_available = isTRUE(recipe_available),
    recipe_json = as.character(rec_json %||% "")[1],
    source_kind = source_kind,
    source_id = source_id,
    source_run_id = "",
    source_snapshot_id = "",
    derivation_type = if (recipe_available) "selector_recipe" else "explicit_cell_ids_from_run_inputs",
    stringsAsFactors = FALSE
  )
  meta <- list(
    cell_set = cell_set,
    role = role,
    status = status,
    recipe_available = isTRUE(recipe_available),
    source = source
  )
  outputs <- list(
    manifest = wb_prim_obs_table(manifest, table_type = "derived_cell_set_manifest", entity_kind = "cell_set", meta = meta),
    rule_table = wb_prim_obs_table(rule_tbl, table_type = "derived_cell_set_rules", entity_kind = "cell_set_rule", meta = meta)
  )
  res <- list(
    outputs = outputs,
    params = list(
      cell_set = cell_set,
      role = role,
      status = status,
      n_cells = as.integer(length(cell_ids)),
      base_n = as.integer(base_n),
      recipe_available = isTRUE(recipe_available),
      overwrite = isTRUE(overwrite),
      source = source,
      n_rules = as.integer(nrow(rule_tbl))
    ),
    membership = def
  )

  if (isTRUE(promote_manifest)) {
    run <- wb_new_run(
      op_name = "cell_set_derive",
      inputs = list(
        cell_set = cell_set,
        effective_n = length(cell_ids),
        parents = character(0),
        provenance_refs = list(),
        user_inputs = list(target_cell_set = cell_set, role = role, status = status),
        symbolic_inputs = list(),
        execution_inputs = list(effective_n = length(cell_ids), resolved = list())
      ),
      params = res$params,
      outputs = outputs,
      notes = description
    )
    prom <- wb_promote_analysis(
      bundle = bundle,
      runs = stats::setNames(list(run), run$run_id),
      head_run_id = run$run_id,
      name_prefix = paste0("Derived Cell Set ", cell_set),
      description = description,
      created_by = created_by,
      fail_fast = TRUE
    )
    res$promoted <- prom
  }

  res
}


#' Get the stored recipe for a cell set (if any)
#'
#' Returns the recipe metadata row. If `parse=TRUE`, also includes `recipe`
#' as a parsed R object (jsonlite::fromJSON).
#'
#' @param bundle scworkbench bundle handle
#' @param cell_set Set name (accepts "foo" or "set:foo")
#' @param parse If TRUE, parse recipe_json into an R object.
#'
#' @return data.frame with columns (cell_set, recipe_json, created_at, created_by, source, description),
#'   plus `recipe` if parse=TRUE. Returns 0-row data.frame if not found.
#' @export
wb_get_cell_set_recipe <- function(bundle, cell_set, parse = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  cell_set <- .wb_normalize_cell_set(cell_set)

  con <- bundle$con
  .wb_ensure_cell_set_recipes_table(con)

  df <- DBI::dbGetQuery(
    con,
    "SELECT cell_set, recipe_json, created_at, created_by, source, description, role, status
     FROM cell_set_recipes
     WHERE cell_set = ?;",
    params = list(cell_set)
  )

  if (!nrow(df)) return(df)

  if (isTRUE(parse)) {
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      stop("Missing suggested package 'jsonlite' to parse recipes (parse=TRUE).", call. = FALSE)
    }
    df$recipe <- lapply(df$recipe_json, function(x) {
      tryCatch(jsonlite::fromJSON(x), error = function(e) NULL)
    })
  }

  df
}
