test_schema_catalog_actual_durable_membership_contract <- function() {
  root <- normalizePath(".", mustWork = TRUE)
  env <- new.env(parent = asNamespace("scworkbench"))
  sys.source("inst/dev/generate_schema_catalog.R", env)
  output <- tempfile("schema_catalog_actual_", fileext = ".md")
  on.exit(unlink(output), add = TRUE)
  env$generate_schema_catalog(root, output)
  text <- readLines(output, warn = FALSE)
  for (scratch in c("attributes", "axes", "selected", "vectors"))
    stopifnot(!any(grepl(paste0("| `", scratch, "` |"), text, fixed = TRUE)))
  stopifnot(any(grepl("59-table durable schema", text, fixed = TRUE)))
  # Source discovery must fail if an actual durable table has no declaration.
  env$wb_init_bundle <- function(...) {
    bundle <- scworkbench::wb_init_bundle(...)
    DBI::dbExecute(bundle$con, "CREATE TABLE undeclared_durable_probe(probe_id TEXT);")
    bundle
  }
  rejected <- tryCatch(env$generate_schema_catalog(root, output), error = identity)
  stopifnot(inherits(rejected, "error"))
  TRUE
}
