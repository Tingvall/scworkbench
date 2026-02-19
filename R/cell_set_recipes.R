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
                               recipe = NULL) {

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
      con <- bundle$con
      .wb_ensure_cell_set_recipes_table(con)

      created_at <- .wb_now_sqlite()

      sql <- "
        INSERT INTO cell_set_recipes(
          cell_set, recipe_json, created_at, created_by, source, description
        ) VALUES(?, ?, ?, ?, ?, ?)
        ON CONFLICT(cell_set) DO UPDATE SET
          recipe_json = excluded.recipe_json,
          created_at  = excluded.created_at,
          created_by  = excluded.created_by,
          source      = excluded.source,
          description = excluded.description;
      "

      DBI::dbExecute(
        con, sql,
        params = list(
          cell_set,
          rec_json,
          created_at,
          created_by %||% NA_character_,
          source %||% NA_character_,
          description %||% NA_character_
        )
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
    recipe_stored = recipe_stored
  ))
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
    "SELECT cell_set, recipe_json, created_at, created_by, source, description
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
