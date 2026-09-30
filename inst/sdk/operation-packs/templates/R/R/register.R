register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(
    system.file("scworkbench", "operation-pack.json", package = "@PACKAGE@"),
    list(`@NAMESPACE@::matrix_cell_sum` = .matrix_cell_sum))
}
