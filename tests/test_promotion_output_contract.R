test_promotion_output_contract <- function() {
  stopifnot(isTRUE(.wb_validate_promotion_output_contract()))
  for (op in c("scvi_train", "pca_fit", "umap_fit")) {
    x <- wb_op_interface(op)$produces
    stopifnot(all(vapply(x, function(y) all(c("output_name","primitive_kind","durability_role","promotable_directly","materialized_by_terminals") %in% names(y)), logical(1))))
  }
  scvi <- wb_op_interface("scvi_train")$produces
  stopifnot(identical(scvi$space$durability_role, "materialization"), !isTRUE(scvi$space$promotable_directly), all(c("model","fit_summary") %in% scvi$space$materialized_by_terminals))
  peak <- wb_op_interface("peakvi_project")$produces
  stopifnot(identical(peak$space$durability_role, "materialization"), identical(peak$space$materialized_by_terminals, "fit_summary"), isTRUE(peak$fit_summary$promotable_directly))
  run <- wb_new_run("peakvi_project", inputs=list(parents=character()), outputs=list(space=wb_prim_space("staged_only")))
  s <- wb_session_new(); s$runs <- setNames(list(run), run$run_id); s$head_run_id <- run$run_id
  z <- try(wb_session_promote_current(wb_init_bundle(tempfile("scwb_zero_"),overwrite=TRUE),s),silent=TRUE)
  stopifnot(inherits(z,"try-error"), grepl("zero promotable terminal",as.character(z)))
  TRUE
}
