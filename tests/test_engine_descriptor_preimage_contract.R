.engine_descriptor_oracle <- function() {
  env <- new.env(parent = asNamespace("scworkbench"))
  sys.source(file.path("tests", "fixtures", "engine_descriptor_repaired_oracle.R"), env)
  env$.engine_descriptor_repaired_oracle
}

test_engine_descriptor_preimage_exact_contract <- function() {
  oracle <- .engine_descriptor_oracle()
  candidate <- scworkbench:::.wb_operation_pack_v2_input_descriptor
  cells <- c("cell_2", "cell_10", "cell_1")
  objects <- list(wb_prim_matrix("counts"), wb_prim_space("pca"),
    wb_prim_space_2d("umap"),
    wb_prim_cell_vector(setNames(c(-0, pi, NA_real_), cells), "continuous",
      meta = list(label = "é 雪 \" \\ \n", optional = NULL)),
    wb_prim_cell_vector_family(rep(c("b", "a"), each = 3L), rep(cells, 2L),
      c(1, 1.0, 1e-7, -1e5, 0, NA_real_), value_type = "continuous"),
    wb_prim_relation_family(rep("r", 3L), cells, weight = c(1, 2, 3)),
    wb_prim_feature_table(data.frame(feature_id = c("g_2", "g_1"),
      score = c(1e-7, 1e8))),
    wb_prim_obs_table(data.frame(key = c("b", "a"), ok = c(TRUE, FALSE))),
    wb_prim_path_2d_family(rep("p", 3L), 1:3, c(1, 0, -2), c(3, 1, 0)),
    wb_prim_space_path_family(rep("pca", 4L), rep("p", 4L),
      rep(1:2, each = 2L), rep(1:2, 2L), c(1, 2, 3, 4)),
    wb_prim_model_ref("fit", "pca"))
  for (value in objects) for (name in c("input", "é雪\"\\\n")) {
    declaration <- list(kind = value$kind, alignment = "exact")
    for (transport in list(NULL, unclass(value))) {
      expected <- oracle(name, value, declaration, transport_value = transport)
      actual <- candidate(name, value, declaration, transport_value = transport)
      stopifnot(identical(actual, expected),
        identical(actual$descriptor$ancestry_identity$sha256,
          actual$descriptor$payload_manifest_identity$sha256),
        !identical(actual$descriptor$ancestry_identity$scheme,
          actual$descriptor$payload_manifest_identity$scheme))
    }
  }
  # G1 removes the inaccessible process-local object before canonicalization;
  # undeclared ordinary model access still rejects noncanonical contents.
  model <- wb_prim_model_ref("fit", "pca"); model$model_obj <- new.env()
  declaration <- list(kind = "model_ref", alignment = "exact")
  stopifnot(identical(candidate("model", model, declaration, g1_model_read = TRUE),
    oracle("model", model, declaration, g1_model_read = TRUE)))
  TRUE
}

test_engine_descriptor_preimage_rejection_contract <- function() {
  oracle <- .engine_descriptor_oracle()
  candidate <- scworkbench:::.wb_operation_pack_v2_input_descriptor
  original <- wb_prim_cell_vector(setNames(1:3, c("c2", "c10", "c1")),
    "continuous")
  bad <- list(list(value = Inf), list(value = -Inf), list(value = new.env()),
    structure(list("a", "b"), names = c("value_semantics", "value_semantics")))
  for (metadata in bad) {
    value <- original; value$meta <- metadata
    declaration <- list(kind = "cell_vector", alignment = "exact")
    expected <- tryCatch(oracle("vector", value, declaration), error = identity)
    actual <- tryCatch(candidate("vector", value, declaration), error = identity)
    stopifnot(inherits(expected, "error"), inherits(actual, "error"),
      identical(class(actual), class(expected)),
      identical(conditionMessage(actual), conditionMessage(expected)))
  }
  TRUE
}
