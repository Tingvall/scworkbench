test_space_cell_identity_contract <- function() {
  root <- tempfile("scwb_space_identity_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)

  canonical <- c("cell_z", "cell_a", "cell_m", "cell_absent")
  present <- canonical[1:3]
  wb_define_cells(b, canonical)
  insertion <- c("cell_m", "cell_z", "cell_a")
  wide <- matrix(
    c(3, 30, 1, 10, 2, 20), ncol = 2L, byrow = TRUE,
    dimnames = list(insertion, c("x", "y"))
  )
  wb_add_space(b, "wide_identity", wide, source = "identity-test")
  long <- matrix(
    seq_len(9L), nrow = 3L,
    dimnames = list(insertion, paste0("d", 1:3))
  )
  wb_add_space(b, "long_identity", long, source = "identity-test")

  wide_default <- wb_space(b, "wide_identity")
  stopifnot(
    identical(as.character(wide_default$cell_id), present),
    identical(rownames(wide_default), present),
    identical(as.numeric(wide_default$x), c(1, 2, 3))
  )
  wide_explicit <- wb_space(b, "wide_identity", cells = c("cell_m", "cell_z"))
  stopifnot(identical(as.character(wide_explicit$cell_id), c("cell_m", "cell_z")))
  safe_default <- .wb_space_2d_safe(b, "wide_identity")
  stopifnot(identical(as.character(safe_default$cell_id), present), identical(rownames(safe_default), present))

  long_default <- wb_space(b, "long_identity")
  stopifnot(identical(rownames(long_default), present), nrow(long_default) == 3L, !anyNA(long_default))
  converted <- .wb_as_coord_matrix(wide_default)
  pseudobulk_converted <- .wb_space_to_matrix(wide_default, requested_cells = rev(present))
  scvi_converted <- .wb_scvi_space_matrix(b, "wide_identity", rev(present))
  stopifnot(
    identical(rownames(converted), present),
    identical(rownames(pseudobulk_converted), rev(present)),
    identical(rownames(scvi_converted), rev(present)),
    is.numeric(converted), is.numeric(pseudobulk_converted), is.numeric(scvi_converted)
  )

  # Consumer audit: every distinct wb_space conversion route is either the
  # canonical converter, the tested kNN-pseudobulk adapter, or explicit
  # cell-id alignment at the Python handoff boundary.
  converter_consumers <- list(
    geometry = wb_op_knn_graph,
    slingshot_fit = .wb_slingshot_prepare_fit,
    slingshot_project = wb_op_slingshot_project,
    monocle3_fit = wb_op_monocle3_fit,
    monocle3_project = wb_op_monocle3_project,
    palantir_project = wb_op_palantir_project,
    space_path = .wb_space_path_coord_matrix,
    peakvi_fit = wb_op_peakvi_fit,
    peakvi_project = wb_op_peakvi_project,
    scvi = .wb_scvi_space_matrix
  )
  bodies <- vapply(converter_consumers, function(fn) paste(deparse(body(fn)), collapse = "\n"), character(1))
  stopifnot(all(grepl(".wb_as_coord_matrix", bodies, fixed = TRUE)))
  knn_body <- paste(deparse(body(.wb_knn_neighbors_in_space)), collapse = "\n")
  stopifnot(grepl(".wb_space_to_matrix", knn_body, fixed = TRUE))
  TRUE
}
