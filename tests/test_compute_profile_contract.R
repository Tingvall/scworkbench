test_compute_profile_contract <- function() {
  old_dense <- getOption("scworkbench.max_dense_materialize_mb")
  old_chunk <- getOption("scworkbench.feature_plan_chunk_size")
  on.exit({
    options(
      scworkbench.max_dense_materialize_mb = old_dense,
      scworkbench.feature_plan_chunk_size = old_chunk
    )
  }, add = TRUE)

  x <- wb_compute_profile("local")
  stopifnot(identical(as.character(x$profile), "local"))
  stopifnot(isTRUE(all.equal(as.numeric(x$scworkbench.max_dense_materialize_mb), 256)))
  stopifnot(identical(as.integer(x$scworkbench.feature_plan_chunk_size), 500L))

  y <- wb_compute_profile("cluster")
  stopifnot(identical(as.character(y$profile), "cluster"))
  stopifnot(isTRUE(all.equal(as.numeric(y$scworkbench.max_dense_materialize_mb), 32768)))
  stopifnot(identical(as.integer(y$scworkbench.feature_plan_chunk_size), 2000L))

  z <- wb_compute_profile(
    profile = "custom",
    max_dense_materialize_mb = 1024,
    feature_plan_chunk_size = 777
  )
  stopifnot(identical(as.character(z$profile), "custom"))
  stopifnot(isTRUE(all.equal(as.numeric(z$scworkbench.max_dense_materialize_mb), 1024)))
  stopifnot(identical(as.integer(z$scworkbench.feature_plan_chunk_size), 777L))

  TRUE
}

