#' @keywords internal
.wb_recipe_init <- function(bundle, step) {
  list(
    version = 1L,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    steps = list(step)
  )
}

#' @keywords internal
.wb_recipe_get <- function(x) {
  attr(x, "wb_recipe", exact = TRUE)
}

#' @keywords internal
.wb_recipe_attach <- function(x, recipe) {
  attr(x, "wb_recipe") <- recipe
  x
}

#' @keywords internal
.wb_recipe_append <- function(x, bundle, step, parents = NULL) {
  # parents: optional list of recipe objects to embed (for and/or/not)
  r <- .wb_recipe_get(x)
  if (is.null(r)) r <- .wb_recipe_init(bundle, step)
  else r$steps <- c(r$steps, list(step))

  if (!is.null(parents)) {
    # stash parent recipes inside this step (optional but very useful)
    # (only if you want; safe even if empty)
    r$steps[[length(r$steps)]]$parents <- parents
  }

  .wb_recipe_attach(x, r)
}

#' @keywords internal
.wb_sel_attach_bundle_recipe <- function(cell_ids, bundle, recipe_from = NULL, step = NULL, parents = NULL) {
  out <- .wb_sel_attach_bundle(cell_ids, bundle)
  if (!is.null(recipe_from)) {
    out <- .wb_recipe_attach(out, .wb_recipe_get(recipe_from))
  }
  if (!is.null(step)) {
    out <- .wb_recipe_append(out, bundle, step = step, parents = parents)
  }
  out
}


wb_recipe <- function(x) attr(x, "wb_recipe", exact = TRUE)
