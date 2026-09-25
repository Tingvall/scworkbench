test_phase5_s2_pinned_v3_chunking_interface_projection_contract <- function() {
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbTrajectory")
  stopifnot(nzchar(manifest))
  wb_operation_pack_activate(manifest, lib.loc = .libPaths())
  for (name in c("trajectory_de", "trajectory_smooth")) {
    interface <- wb_op_interface(paste0("scwbtrajectory::", name))
    chunking <- interface$chunking
    stopifnot(identical(chunking$chunkable, TRUE),
      identical(chunking$axis, "features"),
      identical(chunking$chunk_size_param, "chunk_size"),
      identical(chunking$chunk_size_default, 128L),
      identical(chunking$status, "v3_typed_slice_capability"),
      is.null(chunking$merge))
  }
  TRUE
}
