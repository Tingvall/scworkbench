test_op_catalog_semantic_contract <- function() {
  cat_sem <- wb_op_catalog_semantic()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.op_catalog.semantic.v1"))
  stopifnot(is.list(cat_sem$ops), length(cat_sem$ops) == length(wb_list_ops()))

  op_names <- vapply(cat_sem$ops, function(op) as.character(op$op_name %||% ""), character(1))
  stopifnot(setequal(op_names, wb_list_ops()))

  for (op in cat_sem$ops) {
    stopifnot(nzchar(as.character(op$op_name %||% "")[1]))
    stopifnot(nzchar(as.character(op$title %||% "")[1]))
    stopifnot(nzchar(as.character(op$description %||% "")[1]))
    stopifnot(is.list(op$consumes))
    stopifnot(is.list(op$produces))
    if (length(op$produces)) {
      out_names <- vapply(op$produces, function(x) as.character(x$name %||% ""), character(1))
      out_kinds <- vapply(op$produces, function(x) as.character(x$kind %||% ""), character(1))
      stopifnot(all(nzchar(out_names)), all(nzchar(out_kinds)))
    }
  }

  tmp_md <- tempfile("op_catalog_", fileext = ".md")
  tmp_json <- tempfile("op_catalog_", fileext = ".json")
  wb_write_op_catalog_reference(path_md = tmp_md, path_json = tmp_json)
  stopifnot(file.exists(tmp_md), file.exists(tmp_json))
  txt <- paste(readLines(tmp_json, warn = FALSE), collapse = "\n")
  stopifnot(jsonlite::validate(txt))
  md <- readLines(tmp_md, warn = FALSE)
  stopifnot(any(grepl("^## `slingshot_fit`", md)))

  TRUE
}
