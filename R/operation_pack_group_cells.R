# Resolve generic cell-group inputs for authenticated operation-pack grants.
# This is core selector authority, not a statistical method implementation.
.wb_resolve_group_cells <- function(bundle, x, effective_cells) {
  .wb_assert(!is.null(x), "Group input is missing.")
  effective <- unique(as.character(effective_cells))
  if (is.character(x) && length(x) == 1L) {
    token <- as.character(x)[1]
    known <- try(as.character(wb_cell_sets(bundle)), silent = TRUE)
    if (inherits(known, "try-error")) known <- character()
    is_set <- startsWith(token, "set:") || token %in% c("core", "all") || token %in% known
    candidates <- if (is_set) wb_cells(bundle, cell_set = token) else token
    if (is_set && !length(candidates) && !startsWith(token, "set:") &&
        !token %in% c("core", "all")) {
      candidates <- wb_cells(bundle, cell_set = paste0("set:", token))
    }
  } else if (is.character(x)) {
    candidates <- x
  } else {
    stop("Unsupported group input. Use cell IDs, 'core'/'all', or set selectors.", call. = FALSE)
  }
  unique(intersect(as.character(candidates), effective))
}
