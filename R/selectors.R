# selectors.R
# A clean, pipe-friendly selector layer for scworkbench.
#
# Design:
# - Selectors are magrittr-native: bundle %>% wb_sel_*() %>% wb_sel_*()
# - After the first selector, the pipeline carries plain character cell_ids,
#   with the bundle attached as an attribute so you don't need to pass bundle=.
# - Every selector returns ordered cell_ids (bundle rowid order), with bundle attribute retained.

# -------------------------
# Internal utilities
# -------------------------

#' @keywords internal
.wb_sel_resolve_bundle <- function(x, bundle = NULL) {
  if (inherits(x, "scworkbench_bundle")) return(x)
  b <- bundle %||% attr(x, "wb_bundle", exact = TRUE)
  .wb_assert(!is.null(b) && inherits(b, "scworkbench_bundle"),
             "Selector pipeline lost the bundle. Start with `bundle %>% ...` or supply bundle=.")
  b
}

#' @keywords internal
.wb_sel_resolve_cell_ids <- function(x) {
  if (inherits(x, "scworkbench_bundle")) return(NULL)
  .wb_assert(is.character(x), "Selector input must be a bundle or a character vector of cell_ids.")
  unique(as.character(x))
}

#' @keywords internal
.wb_sel_attach_bundle <- function(cell_ids, bundle) {
  out <- as.character(cell_ids)
  attr(out, "wb_bundle") <- bundle
  out
}

#' Order a cell_id vector like the bundle's canonical cell order (cells.rowid)
#' Drops IDs that are not present in bundle$cells.
#' @keywords internal
.wb_order_like_bundle <- function(bundle, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  cell_ids <- unique(as.character(cell_ids))
  if (!length(cell_ids)) return(character(0))

  con <- bundle$con
  js <- jsonlite::toJSON(as.list(cell_ids), auto_unbox = TRUE)

  hit <- DBI::dbGetQuery(
    con,
    "SELECT cell_id
     FROM cells
     WHERE cell_id IN (SELECT value FROM json_each(?))
     ORDER BY rowid;",
    params = list(js)
  )$cell_id

  as.character(hit)
}

# -------------------------
# Selectors
# -------------------------

#' Select all cells from a cell_set (optionally within a dataset)
#' @inheritParams wb_sel_all
#' @return Character vector of selected cell_ids, ordered like the bundle, with bundle + recipe attached.
#' @export
wb_sel_all <- function(x, cell_set = "core", dataset_id = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  ids <- wb_cells(b, cell_set = cell_set, dataset_id = dataset_id)
  out <- .wb_order_like_bundle(b, ids)

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(
      sel  = "wb_sel_all",
      args = list(cell_set = cell_set, dataset_id = dataset_id)
    )
  )
}

#' Select union of one or more named sets
#' @inheritParams wb_sel_set
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_set <- function(x, sets, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x)

  sets <- as.character(sets)
  .wb_assert(length(sets) > 0, "sets must be a non-empty character vector.")

  out <- unique(unlist(lapply(sets, function(s) wb_cells(b, cell_set = s)), use.names = FALSE))
  if (!is.null(base)) out <- intersect(base, out)
  out <- .wb_order_like_bundle(b, out)

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(
      sel  = "wb_sel_set",
      args = list(sets = sets)
    )
  )
}


#' Select by cell metadata column (categorical values or numeric range)
#' @inheritParams wb_sel_meta
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_meta <- function(x, col, values = NULL, min = NULL, max = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  con <- b$con
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  .wb_assert(is.character(col) && length(col) == 1 && nzchar(col), "col must be a non-empty column name.")
  js <- jsonlite::toJSON(as.list(base), auto_unbox = TRUE)

  if (!is.null(values)) {
    vals <- jsonlite::toJSON(as.list(values), auto_unbox = TRUE)
    q <- sprintf(
      'SELECT cell_id FROM cells
       WHERE cell_id IN (SELECT value FROM json_each(?))
         AND "%s" IN (SELECT value FROM json_each(?))
       ORDER BY rowid;', col
    )
    ids <- as.character(DBI::dbGetQuery(con, q, params = list(js, vals))$cell_id)

    return(.wb_sel_attach_bundle_recipe(
      cell_ids = ids,
      bundle   = b,
      recipe_from = x,
      step = list(sel="wb_sel_meta", args=list(col=col, values=as.character(values)))
    ))
  }

  if (!is.null(min) || !is.null(max)) {
    q <- sprintf(
      'SELECT cell_id FROM cells
       WHERE cell_id IN (SELECT value FROM json_each(?))
         AND ("%s" IS NOT NULL)
         AND (? IS NULL OR "%s" >= ?)
         AND (? IS NULL OR "%s" <= ?)
       ORDER BY rowid;', col, col, col, col
    )
    ids <- as.character(DBI::dbGetQuery(con, q, params = list(js, min, min, max, max))$cell_id)

    return(.wb_sel_attach_bundle_recipe(
      cell_ids = ids,
      bundle   = b,
      recipe_from = x,
      step = list(sel="wb_sel_meta", args=list(col=col, min=min, max=max))
    ))
  }

  stop("Provide either values= or min/max=", call. = FALSE)
}


#' Select by a registered cell vector (numeric)
#' @inheritParams wb_sel_vector
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_vector <- function(x, vector_id, min = NULL, max = NULL, na.rm = TRUE, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  v <- wb_read_cell_vector(b, vector_id = vector_id, cell_ids = base)
  ok <- rep(TRUE, length(v))
  if (isTRUE(na.rm)) ok <- ok & !is.na(v)
  if (!is.null(min)) ok <- ok & (v >= min)
  if (!is.null(max)) ok <- ok & (v <= max)

  out <- .wb_order_like_bundle(b, names(v)[ok])

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_vector", args=list(vector_id=vector_id, min=min, max=max, na.rm=na.rm))
  )
}

#' Select by expression of a single feature (scalar getter)
#' @inheritParams wb_sel_expr
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_expr <- function(x, matrix_id, feature_id, min = NULL, max = NULL,
                        na.rm = TRUE, bundle = NULL) {

  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  v <- wb_matrix_read_feature(
    b,
    matrix_id  = matrix_id,
    feature_id = feature_id,
    cell_ids   = base
  )

  ok <- rep(TRUE, length(v))
  if (isTRUE(na.rm)) ok <- ok & !is.na(v)
  if (!is.null(min)) ok <- ok & (v >= min)
  if (!is.null(max)) ok <- ok & (v <= max)

  out <- .wb_order_like_bundle(b, names(v)[ok])

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_expr", args=list(matrix_id=matrix_id, feature_id=feature_id, min=min, max=max, na.rm=na.rm))
  )
}


#' Select cells inside an axis-aligned box in a 2D space
#' @inheritParams wb_sel_space_box
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_space_box <- function(x, space_id, xmin, xmax, ymin, ymax, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  df <- .wb_space_2d_safe(b, space_id = space_id, cells = base)
  if (!nrow(df)) {
    return(.wb_sel_attach_bundle_recipe(
      cell_ids = character(0),
      bundle   = b,
      recipe_from = x,
      step = list(sel="wb_sel_space_box", args=list(space_id=space_id, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax))
    ))
  }

  hit <- df$cell_id[
    df$x >= xmin & df$x <= xmax &
      df$y >= ymin & df$y <= ymax
  ]

  out <- .wb_order_like_bundle(b, hit)

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_space_box", args=list(space_id=space_id, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax))
  )
}


# -------------------------
# Set algebra (pipe-friendly)
# -------------------------

#' Intersect (AND) one or more cell_id vectors
#' @inheritParams wb_sel_and
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_and <- function(x, ..., universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% (universe %||% wb_cells(b, cell_set = "all"))

  sets <- list(...)
  out <- base
  for (s in sets) out <- intersect(out, as.character(s))
  out <- .wb_order_like_bundle(b, out)

  parent_recipes <- lapply(sets, function(s) attr(s, "wb_recipe", exact = TRUE))
  parent_recipes <- Filter(Negate(is.null), parent_recipes)

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_and", args=list(n_inputs=length(sets))),
    parents = if (length(parent_recipes)) parent_recipes else NULL
  )
}

#' Union (OR) one or more cell_id vectors
#' @inheritParams wb_sel_or
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_or <- function(x, ..., universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% character(0)

  sets <- list(...)
  out <- unique(c(base, unlist(sets, use.names = FALSE)))
  if (!is.null(universe)) out <- intersect(out, as.character(universe))
  out <- .wb_order_like_bundle(b, out)

  parent_recipes <- lapply(sets, function(s) attr(s, "wb_recipe", exact = TRUE))
  parent_recipes <- Filter(Negate(is.null), parent_recipes)

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_or", args=list(n_inputs=length(sets), has_universe=!is.null(universe))),
    parents = if (length(parent_recipes)) parent_recipes else NULL
  )
}


#' Negation (NOT): universe minus x
#' @inheritParams wb_sel_not
#' @return cell_ids (ordered, bundle-attached, recipe-attached)
#' @export
wb_sel_not <- function(x, universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x)
  .wb_assert(!is.null(base), "wb_sel_not() must be called on cell_ids (e.g. after a selector).")

  uni <- as.character(universe %||% wb_cells(b, cell_set = "all"))
  out <- .wb_order_like_bundle(b, setdiff(uni, base))

  .wb_sel_attach_bundle_recipe(
    cell_ids = out,
    bundle   = b,
    recipe_from = x,
    step = list(sel="wb_sel_not", args=list(has_universe = !is.null(universe)))
  )
}

#' Get the recipe from a selector result
#' @export
wb_sel_recipe <- function(x) {
  attr(x, "wb_recipe", exact = TRUE)
}

#' Print a compact recipe summary
#' @export
wb_sel_recipe_print <- function(x) {
  r <- wb_sel_recipe(x)
  if (is.null(r)) {
    cat("<no recipe>\n")
    return(invisible(NULL))
  }
  cat("wb_recipe v", r$version, " created_at=", r$created_at, "\n", sep = "")
  for (i in seq_along(r$steps)) {
    st <- r$steps[[i]]
    cat(sprintf("  %02d) %s\n", i, st$sel))
  }
  invisible(r)
}

