test_pybench_protocol_hello_bridge_contract <- function() {
  # The historical implementation remains private solely so retained records
  # can be described without rewriting their operation identity. It is no
  # longer a production operation or public mutation surface.
  stopifnot(
    length(wb_list_ops()) == 39L,
    !"py_protocol_hello" %in% wb_list_ops(),
    inherits(try(wb_op_interface("py_protocol_hello"), silent = TRUE),
      "try-error"),
    exists("wb_op_py_protocol_hello", envir = asNamespace("scworkbench"),
      inherits = FALSE),
    !"wb_op_py_protocol_hello" %in% getNamespaceExports("scworkbench")
  )
  historical <- list(
    op_name = "py_protocol_hello",
    definition_identity = list(scheme = "historical-core-operation-v1",
      sha256 = paste(rep("a", 64L), collapse = "")))
  copy <- unserialize(serialize(historical, NULL, version = 3L))
  stopifnot(identical(copy, historical))
  TRUE
}
