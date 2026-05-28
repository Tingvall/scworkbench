test_getter_catalog_semantic_contract <- function() {
  cat_sem <- wb_getter_catalog_semantic()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.getter_catalog.semantic.v1"))
  stopifnot(is.list(cat_sem$getters), length(cat_sem$getters) >= 20)

  getter_names <- vapply(cat_sem$getters, function(g) as.character(g$function_name %||% ""), character(1))
  stopifnot(all(nzchar(getter_names)))
  stopifnot(!anyDuplicated(getter_names))
  stopifnot(all(c("wb_cells", "wb_meta", "wb_matrices", "wb_spaces", "wb_art_list") %in% getter_names))

  for (getter in cat_sem$getters) {
    stopifnot(nzchar(as.character(getter$function_name %||% "")[1]))
    stopifnot(nzchar(as.character(getter$title %||% "")[1]))
    stopifnot(nzchar(as.character(getter$description %||% "")[1]))
    stopifnot(nzchar(as.character(getter$category %||% "")[1]))
    stopifnot(nzchar(as.character(getter$returns %||% "")[1]))
    stopifnot(nzchar(as.character(getter$payload_level %||% "")[1]))
    stopifnot(identical(as.logical(getter$mutates %||% TRUE), FALSE))
    stopifnot(is.list(getter$arguments) || is.character(getter$arguments))
    stopifnot(is.list(getter$use_when) || is.character(getter$use_when))
  }

  tmp_md <- tempfile("getter_catalog_", fileext = ".md")
  tmp_json <- tempfile("getter_catalog_", fileext = ".json")
  wb_write_getter_catalog_reference(path_md = tmp_md, path_json = tmp_json)
  stopifnot(file.exists(tmp_md), file.exists(tmp_json))
  txt <- paste(readLines(tmp_json, warn = FALSE), collapse = "\n")
  stopifnot(jsonlite::validate(txt))
  md <- readLines(tmp_md, warn = FALSE)
  stopifnot(any(grepl("^### `wb_cells`", md)))
  stopifnot(any(grepl("^### `wb_art_list`", md)))

  TRUE
}
