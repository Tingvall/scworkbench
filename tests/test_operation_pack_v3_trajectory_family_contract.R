test_operation_pack_v3_trajectory_family_policy_contract <- function() {
  paths <- system.file("protocol", c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json",
    "fixtures/operation-pack-v3/identities.json"),
    package = "scworkbench")
  expected <- c(
    "3f06cc79680488f71d07a0691a44637731c6b8f11afe1ed63200433e054b3734",
    "d46ebe83e00c3c1add2fc7518025242d14b1defa57e174c7304b7a536c0e61b6",
    "f35fb54c87f4671e67da4d2841b4659b2a1304310d89d5453b21059b2bacd538",
    "27f0e7317298815b82dc7ab4d2b7f4967549a8f90663bf5d3f337d1e5bca9793")
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
