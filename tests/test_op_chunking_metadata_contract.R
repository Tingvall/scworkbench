test_op_chunking_metadata_contract <- function() {
  contract_test_activate_statistics_pack()
  iface_ucell <- wb_op_interface("ucell")
  stopifnot(is.list(iface_ucell))
  stopifnot(is.list(iface_ucell$chunking))
  stopifnot(isTRUE(iface_ucell$chunking$chunkable))
  stopifnot(identical(as.character(iface_ucell$chunking$axis), "cells"))
  stopifnot(identical(as.character(iface_ucell$chunking$chunk_size_param), "chunk_size"))
  stopifnot(identical(as.integer(iface_ucell$chunking$chunk_size_default), 2000L))
  stopifnot("chunk_size" %in% vapply(iface_ucell$params, `[[`, character(1), "name"))

  iface_ft <- wb_op_interface("feature_trend_spearman")
  stopifnot(is.list(iface_ft$chunking))
  stopifnot(isTRUE(iface_ft$chunking$chunkable))
  stopifnot(identical(as.character(iface_ft$chunking$axis), "features"))
  stopifnot(identical(as.character(iface_ft$chunking$status), "implemented_generic"))

  iface_tde <- wb_op_interface("trajectory_de")
  stopifnot(is.list(iface_tde$chunking))
  stopifnot(identical(as.character(iface_tde$chunking$axis), "features"))

  iface_ts <- wb_op_interface("trajectory_smooth")
  stopifnot(is.list(iface_ts$chunking))
  stopifnot(identical(as.character(iface_ts$chunking$axis), "features"))

  reg_ucell <- .wb_op("ucell")
  stopifnot(is.list(reg_ucell$chunking))
  stopifnot(identical(as.character(reg_ucell$chunking$status), "active"))

  TRUE
}
