test_plot_catalog_semantic_contract <- function() {
  cat_sem <- wb_plot_catalog_semantic()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.plot_catalog.semantic.v1"))
  stopifnot(is.list(cat_sem$plots), length(cat_sem$plots) == length(names(.wb_plot_contracts())))

  plot_types <- vapply(cat_sem$plots, function(plot) as.character(plot$plot_type %||% ""), character(1))
  stopifnot(setequal(plot_types, names(.wb_plot_contracts())))

  mappers <- wb_plot_mapper_list()
  for (plot in cat_sem$plots) {
    pt <- as.character(plot$plot_type %||% "")[1]
    stopifnot(nzchar(pt))
    stopifnot(nzchar(as.character(plot$title %||% "")[1]))
    stopifnot(nzchar(as.character(plot$description %||% "")[1]))
    stopifnot(nzchar(as.character(plot$dataset_type %||% "")[1]))
    stopifnot(is.list(plot$required_fields))
    if (length(plot$required_fields)) {
      field_names <- vapply(plot$required_fields, function(x) as.character(x$name %||% ""), character(1))
      field_types <- vapply(plot$required_fields, function(x) as.character(x$type %||% ""), character(1))
      stopifnot(all(nzchar(field_names)), all(nzchar(field_types)))
    }
    stopifnot(any(as.character(mappers$plot_type) == pt))
  }

  tmp_md <- tempfile("plot_catalog_", fileext = ".md")
  tmp_json <- tempfile("plot_catalog_", fileext = ".json")
  wb_write_plot_catalog_reference(path_md = tmp_md, path_json = tmp_json)
  stopifnot(file.exists(tmp_md), file.exists(tmp_json))
  txt <- paste(readLines(tmp_json, warn = FALSE), collapse = "\n")
  stopifnot(jsonlite::validate(txt))
  md <- readLines(tmp_md, warn = FALSE)
  stopifnot(any(grepl("^## `embedding_overlay`", md)))
  stopifnot(any(grepl("^## `pseudotime_signature_line`", md)))

  TRUE
}
