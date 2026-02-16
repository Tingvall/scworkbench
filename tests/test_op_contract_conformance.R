test_op_contract_conformance <- function() {
  # 1) Execution contract and interface contract must align 1:1.
  scworkbench:::.wb_validate_op_contract_alignment()

  # 2) Interface registry itself is structurally valid.
  scworkbench:::.wb_validate_op_interface_registry()

  # 3) Every execution op has a dispatch runner with required formals.
  scworkbench:::.wb_validate_op_dispatch_registry()

  # 4) Session registry shim must point to canonical execution contract.
  stopifnot(identical(names(scworkbench:::.wb_session_op_registry()), names(scworkbench:::.wb_ops())))

  # 5) wb_ops() table reflects canonical ops.
  ops_tbl <- wb_ops()
  stopifnot(is.data.frame(ops_tbl), nrow(ops_tbl) == length(scworkbench:::.wb_ops()))
  stopifnot(setequal(as.character(ops_tbl$op_name), names(scworkbench:::.wb_ops())))

  TRUE
}
