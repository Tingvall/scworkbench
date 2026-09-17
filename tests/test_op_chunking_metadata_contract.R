test_op_chunking_metadata_contract <- function() {
  iface_tde <- wb_op_interface("trajectory_de")
  stopifnot(is.list(iface_tde$chunking))
  stopifnot(identical(as.character(iface_tde$chunking$axis), "features"))

  iface_ts <- wb_op_interface("trajectory_smooth")
  stopifnot(is.list(iface_ts$chunking))
  stopifnot(identical(as.character(iface_ts$chunking$axis), "features"))

  TRUE
}
