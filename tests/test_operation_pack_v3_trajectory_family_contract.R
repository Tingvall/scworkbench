test_operation_pack_v3_trajectory_family_policy_contract <- function() {
  paths <- system.file("protocol", c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json",
    "fixtures/operation-pack-v3/identities.json"),
    package = "scworkbench")
  expected <- c(
    "643267f5999f80b10cd7a3687236d9c719221e703ede0db6b6f02fe07c825a37",
    "bdcb4eb7a7ffc66fcd95fbecceb8cce5dfad5abf1abc74c61e0f49d88a483fec",
    "87c7c2b7386097d0174c55200e74e02e5863d1bc15970fa5ff401175b6718ed6",
    "0961ffcba4dd2a7bb16e806ec78a7a300faa53719fd1534e9a1fac3beee03796")
  observed <- vapply(paths, digest::digest, character(1), algo = "sha256",
    serialize = FALSE, file = TRUE)
  schema <- jsonlite::read_json(paths[[1L]], simplifyVector = FALSE)
  request <- jsonlite::read_json(paths[[2L]], simplifyVector = FALSE)
  schema_text <- jsonlite::toJSON(schema, auto_unbox = TRUE, null = "null")
  request_text <- jsonlite::toJSON(request, auto_unbox = TRUE,
    null = "null")
  stopifnot(identical(unname(observed), expected),
    grepl("declared_keys_with_optional_prefix_v1", schema_text,
      fixed = TRUE),
    grepl("data_dependent_family_v1", schema_text, fixed = TRUE),
    grepl("declared_keys_with_optional_prefix_v1", request_text,
      fixed = TRUE))
  TRUE
}

test_operation_pack_v3_space_2d_dataframe_transport_contract <- function() {
  root <- tempfile("scwb-v3-space2d-")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- c("c1", "c2", "c3")
  wb_define_cells(b, cells)
  values <- cbind(x = c(0, 1, 2), y = c(2, 1, 0))
  rownames(values) <- cells
  wb_add_space(b, "plot", values)
  primitive <- wb_prim_space_2d("plot")
  bound <- getFromNamespace(".wb_operation_pack_v2_bind_inputs",
    "scworkbench")(b, list(plot_space = primitive), cells)
  stopifnot(is.matrix(bound$plot_space$values),
    identical(rownames(bound$plot_space$values), cells),
    identical(colnames(bound$plot_space$values), c("x", "y")),
    identical(unname(bound$plot_space$values), unname(values)))
  TRUE
}
