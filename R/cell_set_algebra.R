wb_sel_and <- function(bundle, ..., cell_ids = NULL) {
  sets <- list(...)
  out <- cell_ids %||% sets[[1]]
  for (s in sets) out <- intersect(out, s)
  .wb_order_like_bundle(bundle, out)
}

wb_sel_or <- function(bundle, ..., cell_ids = NULL) {
  sets <- c(list(cell_ids), list(...))
  out <- unique(unlist(sets, use.names = FALSE))
  .wb_order_like_bundle(bundle, out)
}

wb_sel_not <- function(bundle, cell_ids, universe = NULL) {
  uni <- universe %||% wb_cells(bundle, cell_set = "all")
  out <- setdiff(uni, cell_ids)
  .wb_order_like_bundle(bundle, out)
}


.wb_recipe_init <- function(bundle, step) {
  list(
    version = 1L,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    steps = list(step)
  )
}

.wb_recipe_append <- function(x, bundle, step) {
  r <- attr(x, "wb_recipe", exact = TRUE)
  if (is.null(r)) r <- .wb_recipe_init(bundle, step)
  else r$steps <- c(r$steps, list(step))
  attr(x, "wb_recipe") <- r
  x
}

wb_recipe <- function(x) attr(x, "wb_recipe", exact = TRUE)
