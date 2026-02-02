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
#'
#' Pipe-friendly selector.
#'
#' @param x A bundle (start of pipeline) or a character vector of cell_ids (continuation).
#' @param cell_set Cell set selector (e.g. "core", "all", "set:bulkers", "set:interesting").
#' @param dataset_id Optional dataset filter.
#' @param bundle Optional bundle when piping cell_ids without a bundle attribute (rare).
#'
#' @return Character vector of selected cell_ids, ordered like the bundle, with bundle attached.
#' @export
wb_sel_all <- function(x, cell_set = "core", dataset_id = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  ids <- wb_cells(b, cell_set = cell_set, dataset_id = dataset_id)
  .wb_sel_attach_bundle(.wb_order_like_bundle(b, ids), b)
}

#' Select union of one or more named sets
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param sets Character vector of set selectors (e.g. c("set:bulkers","set:interesting")).
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_set <- function(x, sets, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x)

  sets <- as.character(sets)
  .wb_assert(length(sets) > 0, "sets must be a non-empty character vector.")

  out <- unique(unlist(lapply(sets, function(s) wb_cells(b, cell_set = s)), use.names = FALSE))
  if (!is.null(base)) out <- intersect(base, out)

  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}

#' Select by cell metadata column (categorical values or numeric range)
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param col Column name in the SQLite `cells` table.
#' @param values Optional categorical selection: keep rows where col in values.
#' @param min,max Optional numeric range selection.
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
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
    ids <- DBI::dbGetQuery(con, q, params = list(js, vals))$cell_id
    return(.wb_sel_attach_bundle(as.character(ids), b))
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
    ids <- DBI::dbGetQuery(con, q, params = list(js, min, min, max, max))$cell_id
    return(.wb_sel_attach_bundle(as.character(ids), b))
  }

  stop("Provide either values= or min/max=", call. = FALSE)
}

#' Select by a registered cell vector (numeric)
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param vector_id Registered vector id (see wb_list_cell_vectors()).
#' @param min,max Range filter.
#' @param na.rm Drop NA values before applying thresholds.
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_vector <- function(x, vector_id, min = NULL, max = NULL, na.rm = TRUE, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  v <- wb_read_cell_vector(b, vector_id = vector_id, cell_ids = base) # named numeric
  ok <- rep(TRUE, length(v))
  if (isTRUE(na.rm)) ok <- ok & !is.na(v)
  if (!is.null(min)) ok <- ok & (v >= min)
  if (!is.null(max)) ok <- ok & (v <= max)

  out <- names(v)[ok]
  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}

#' Select by expression of a single feature (scalar getter)
#'
#' Uses wb_matrix_read_feature() and thresholds on the returned named vector.
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param matrix_id Matrix id.
#' @param feature_id Feature id (gene/peak id depending on matrix).
#' @param min,max Range filter.
#' @param na.rm Drop NA before applying thresholds (TRUE recommended).
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_expr <- function(x, matrix_id, feature_id, min = NULL, max = NULL,
                        na.rm = TRUE, bundle = NULL) {

  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  v <- wb_matrix_read_feature(
    b,
    matrix_id = matrix_id,
    feature_id = feature_id,
    cell_ids = base
  ) # named numeric (may include NA depending on your getter behavior)

  ok <- rep(TRUE, length(v))
  if (isTRUE(na.rm)) ok <- ok & !is.na(v)
  if (!is.null(min)) ok <- ok & (v >= min)
  if (!is.null(max)) ok <- ok & (v <= max)

  out <- names(v)[ok]
  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}

#' Select cells inside an axis-aligned box in a 2D space
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param space_id 2D space id.
#' @param xmin,xmax,ymin,ymax Box limits.
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_space_box <- function(x, space_id, xmin, xmax, ymin, ymax, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% wb_cells(b, cell_set = "all")

  df <- .wb_space_2d_safe(b, space_id = space_id, cells = base) # df(cell_id,x,y)
  if (!nrow(df)) return(.wb_sel_attach_bundle(character(0), b))

  hit <- df$cell_id[
    df$x >= xmin & df$x <= xmax &
      df$y >= ymin & df$y <= ymax
  ]

  .wb_sel_attach_bundle(.wb_order_like_bundle(b, hit), b)
}

# -------------------------
# Set algebra (pipe-friendly)
# -------------------------

#' Intersect (AND) one or more cell_id vectors
#'
#' Pipe-friendly: `bundle %>% wb_sel_all() %>% wb_sel_and(other_ids)`
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param ... One or more character vectors of cell_ids.
#' @param universe Optional universe (defaults to "all" cells).
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_and <- function(x, ..., universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% (universe %||% wb_cells(b, cell_set = "all"))
  sets <- list(...)
  out <- base
  for (s in sets) out <- intersect(out, as.character(s))
  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}

#' Union (OR) one or more cell_id vectors
#'
#' @export
wb_sel_or <- function(x, ..., universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x) %||% character(0)
  sets <- list(...)
  out <- unique(c(base, unlist(sets, use.names = FALSE)))
  if (!is.null(universe)) out <- intersect(out, as.character(universe))
  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}

#' Negation (NOT): universe minus x
#'
#' @param x Bundle (start) or cell_ids (continuation).
#' @param universe Optional universe; default all cells.
#' @param bundle Optional bundle override.
#'
#' @return cell_ids (ordered, bundle-attached)
#' @export
wb_sel_not <- function(x, universe = NULL, bundle = NULL) {
  b <- .wb_sel_resolve_bundle(x, bundle = bundle)
  base <- .wb_sel_resolve_cell_ids(x)
  .wb_assert(!is.null(base), "wb_sel_not() must be called on cell_ids (e.g. after a selector).")

  uni <- as.character(universe %||% wb_cells(b, cell_set = "all"))
  out <- setdiff(uni, base)

  .wb_sel_attach_bundle(.wb_order_like_bundle(b, out), b)
}
