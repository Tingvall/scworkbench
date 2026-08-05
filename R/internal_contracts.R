# Canonical package-wide internal helpers. These definitions intentionally live
# in one source file so package collation order cannot change their behavior.

`%||%` <- function(x, y) if (is.null(x)) y else x

.wb_catalog_generated_at <- function() {
  as.character(getOption("scworkbench.catalog_generated_at",
                         format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))[1]
}

.wb_require_cols <- function(df, cols, where = "data.frame") {
  missing <- setdiff(cols, colnames(df))
  .wb_assert(
    length(missing) == 0L,
    paste0(where, " missing required columns: ", paste(missing, collapse = ", "))
  )
}
