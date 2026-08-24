register_fixture_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json", package = "scworkbenchOperationPackFixture"),
    list("scwbfixture::identity_cell_vector" = .fixture_identity)
  )
}

.fixture_identity <- function(bundle, resolved, effective_cells, inputs, ...) {
  signal <- resolved$signal
  keep <- signal$cell_id %in% effective_cells
  x <- as.numeric(signal$value[keep])
  names(x) <- signal$cell_id[keep]
  list(outputs = list(vector = scworkbench::wb_prim_cell_vector(x, "continuous")), params = list())
}
