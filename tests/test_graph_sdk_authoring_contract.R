test_graph_sdk_inventory_and_public_scaffold_contract <- function() {
  catalog <- wb_operation_pack_capabilities(pack_abi_version = "4", kind = "graph")
  stopifnot(catalog$pack_abi_version == "4", catalog$sdk_version == "1.1.0",
    "graph" %in% unlist(catalog$primitive_kinds), "graph_sqlite_v1" %in% unlist(catalog$storage_profiles),
    any(vapply(catalog$capabilities, function(x) x$id == "graph", logical(1))),
    !"graph" %in% unlist(wb_operation_pack_capabilities()$primitive_kinds))
  all <- wb_operation_pack_capabilities(pack_abi_version = "4")
  schema <- jsonlite::read_json(system.file("sdk", "operation-packs",
    "capabilities-v4.schema.json", package = "scworkbench"))
  stopifnot(scworkbench:::.wb_json_schema_validate_2020(all, schema)$ok)
  root <- tempfile("graph_sdk_scaffold_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  before <- wb_list_ops()
  project <- wb_operation_pack_scaffold(file.path(root, "Graph Pack"), "scwbGraphSdkProbe",
    "graphsdkprobe", "SDK Test Author", "author@example.org", template = "graph")
  stopifnot(project$pack_abi_version == "4", wb_operation_pack_check(project$path)$qualified,
    identical(before, wb_list_ops()))
  paths <- list.files(project$path, recursive = TRUE, full.names = TRUE)
  text <- paste(unlist(lapply(paths, readLines, warn = FALSE)), collapse = "\n")
  stopifnot(!grepl(":::|DBI::|SELECT |payload[.]rds|[.]wb_", text),
    grepl("next_part", text, fixed = TRUE), grepl("open_graph", text, fixed = TRUE),
    grepl("wb_graph_binding_from_source", text, fixed = TRUE))
  old <- options(scworkbench.sdk_scaffold_publication_test_hook = function(stage, target) {
    dir.create(target); writeLines("COMPETITOR", file.path(target, "owned"))
  })
  on.exit(options(old), add = TRUE)
  target <- file.path(root, "competing_graph")
  failed <- tryCatch(wb_operation_pack_scaffold(target, "scwbGraphSdkProbe", "graphsdkprobe",
    "SDK Test Author", "author@example.org", template = "graph"), error = identity)
  options(old)
  stopifnot(inherits(failed, "error"), identical(readLines(file.path(target, "owned")), "COMPETITOR"),
    !any(grepl(".scwb-sdk-", list.files(root, all.files = TRUE), fixed = TRUE)))
  TRUE
}
