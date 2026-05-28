#' Build categorical labels from cell_id suffix
#'
#' Parses each cell ID by a separator and maps the suffix token to a label.
#' Useful for source/dataset covariates when explicit metadata is absent.
#'
#' @param bundle Bundle handle.
#' @param cells Optional cell IDs (default: all).
#' @param sep Separator used in cell IDs (default "-").
#' @param mapping Optional named character vector suffix->label.
#' @param default_label Label used when suffix is unmapped.
#' @export
wb_op_cell_suffix_label <- function(bundle,
                                    cells = NULL,
                                    sep = "-",
                                    mapping = NULL,
                                    default_label = "UNKNOWN") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(sep) && length(sep) == 1 && nzchar(sep), "sep must be a non-empty string")
  .wb_assert(is.character(default_label) && length(default_label) == 1, "default_label must be a single string")

  all_cells <- as.character(wb_cells(bundle, cell_set = "all"))
  target <- if (is.null(cells)) all_cells else unique(as.character(cells))
  target <- intersect(target, all_cells)
  .wb_assert(length(target) > 0, "No target cells after filtering.")

  suffix <- sub(
    paste0("^.*", gsub("([.|()\\^{}+$*?]|\\[|\\]|\\\\)", "\\\\\\1", sep), ""),
    "",
    target
  )
  label <- as.character(suffix)

  if (!is.null(mapping)) {
    .wb_assert(is.character(mapping), "mapping must be a character vector when provided.")
    .wb_assert(!is.null(names(mapping)), "mapping must be named (suffix->label).")
    map <- as.character(mapping)
    names(map) <- as.character(names(mapping))
    hit <- unname(map[suffix])
    hit[is.na(hit) | !nzchar(hit)] <- as.character(default_label)
    label <- hit
  }

  v <- label
  names(v) <- target

  tab <- data.frame(
    cell_id = target,
    suffix = suffix,
    label = label,
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      labels = wb_prim_cell_vector(v, value_type = "categorical"),
      label_table = wb_prim_obs_table(
        table = tab,
        table_type = "cell_suffix_label",
        entity_kind = "cell",
        meta = list(
          sep = as.character(sep),
          default_label = as.character(default_label)
        )
      )
    ),
    params = list(
      n_cells = length(target),
      sep = as.character(sep),
      mapped = !is.null(mapping),
      default_label = as.character(default_label)
    )
  )
}
