test_promotion_output_contract <- function() {
  stopifnot(isTRUE(.wb_validate_promotion_output_contract()))
  for (op in "model_bound_latent_union") {
    x <- wb_op_interface(op)$produces
    stopifnot(all(vapply(x, function(y) all(c("output_name","primitive_kind","durability_role","promotable_directly","materialized_by_terminals") %in% names(y)), logical(1))))
  }
  union <- wb_op_interface("model_bound_latent_union")$produces
  stopifnot(identical(union$space$durability_role, "materialization"), identical(union$space$materialized_by_terminals, "union_summary"), isTRUE(union$union_summary$promotable_directly))
  run <- wb_new_run("model_bound_latent_union", inputs=list(parents=character()), outputs=list(space=wb_prim_space("staged_only")))
  s <- wb_session_new(); s$runs <- setNames(list(run), run$run_id); s$head_run_id <- run$run_id
  zero_root <- tempfile("scwb_zero_"); zero_bundle <- wb_init_bundle(zero_root,overwrite=TRUE)
  on.exit({try(wb_close_bundle(zero_bundle),silent=TRUE); unlink(zero_root,recursive=TRUE,force=TRUE)},add=TRUE)
  z <- try(wb_session_promote_current(zero_bundle,s),silent=TRUE)
  stopifnot(inherits(z,"try-error"), grepl("zero promotable terminal",as.character(z)))
  first <- wb_new_run("model_bound_latent_union", inputs=list(parents=character()), outputs=list(union_summary=wb_prim_obs_table(data.frame(x=1), table_type="model_bound_latent_union_summary")))
  second <- wb_new_run("model_bound_latent_union", inputs=list(parents=character()), outputs=list(union_summary=wb_prim_obs_table(data.frame(x=1), table_type="model_bound_latent_union_summary")))
  s2 <- wb_session_new(); s2$runs <- setNames(list(first, second), c(first$run_id, second$run_id)); s2$head_run_id <- second$run_id
  bad_ref <- try(wb_session_promote_current(zero_bundle, s2, outputs=list(wb_ref_run("missing", "union_summary"))), silent=TRUE)
  stopifnot(inherits(bad_ref, "try-error"), grepl("absent session run", as.character(bad_ref)))
  bad_terminal <- try(wb_session_promote_current(zero_bundle, s2, outputs=list(wb_ref_run(first$run_id, "selected_features"))), silent=TRUE)
  stopifnot(inherits(bad_terminal, "try-error"), grepl("absent from run", as.character(bad_terminal)))
  TRUE
}
